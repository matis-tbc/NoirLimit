// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IPokerTable.sol";
import "./interfaces/IVerifier.sol";
import "./HandEvaluator.sol";

contract PokerTable is IPokerTable {

    // Card index convention:
    // [0-1]  Player 0 hole cards
    // [2-3]  Player 1 hole cards
    // [4-6]  Flop
    // [7]    Turn
    // [8]    River

    struct Table {
        address[2] players;
        uint256[2] stacks;
        uint256 buyIn;
        uint256 bigBlind;

        State state;
        uint256 deadline;

        bytes32 deckCommitment;
        bool[2] submitted;   // per-phase submission tracking

        uint8[5] communityCards;
        uint8 communityCardCount;

        uint256 pot;
        uint256 currentBet;
        uint256 lastRaiseSize;
        uint256[2] roundContribution;
        bool[2] actedSinceLastRaise;
        uint8 turn;           // 0 or 1: whose turn to act

        uint8[2][2] holeCards; // [player][card]
        bool[2] handRevealed;

        bytes32[2] playerPublicKeys;

        // Per-card encrypted state stored after final shuffle
        bytes32[52] encCardCommitments;
        bytes32[52] encCardRandomizers;
        bytes32[52] encCardMaskedPayloads;

        // Partial decryption shares: partialDecryptions[playerIndex][cardIndex]
        bytes32[52][2] partialDecryptions;

        address winner;

        // Community card value consensus
        uint8[] pendingCardValues;
    }

    // -------------------------------------------------------
    //  State variables
    // -------------------------------------------------------

    uint256 public nextTableId;
    uint256 public actionTimeout = 120;
    bool public demoMode;

    IVerifier public shuffleVerifier;
    IVerifier public decryptVerifier;
    IVerifier public revealVerifier;

    mapping(uint256 => Table) internal tables;

    // -------------------------------------------------------
    //  Modifiers
    // -------------------------------------------------------

    modifier onlyPlayer(uint256 tid) {
        require(
            msg.sender == tables[tid].players[0] || msg.sender == tables[tid].players[1],
            "not a player"
        );
        _;
    }

    modifier beforeDeadline(uint256 tid) {
        require(block.timestamp <= tables[tid].deadline, "deadline passed");
        _;
    }

    // -------------------------------------------------------
    //  Constructor
    // -------------------------------------------------------

    constructor(address _shuffle, address _decrypt, address _reveal, bool _demoMode) {
        shuffleVerifier = IVerifier(_shuffle);
        decryptVerifier = IVerifier(_decrypt);
        revealVerifier  = IVerifier(_reveal);
        demoMode = _demoMode;
    }

    // -------------------------------------------------------
    //  View helpers
    // -------------------------------------------------------

    function getTable(uint256 tid) external view override returns (
        address[2] memory players,
        uint256[2] memory stacks,
        uint256 pot,
        State state,
        uint8 communityCardCount,
        uint8 turn
    ) {
        Table storage t = tables[tid];
        return (t.players, t.stacks, t.pot, t.state, t.communityCardCount, t.turn);
    }

    function getWinner(uint256 tid) external view override returns (address) {
        return tables[tid].winner;
    }

    function getEncryptedCard(uint256 tid, uint8 cardIndex) external view override returns (
        bytes32 commitment, bytes32 randomizer, bytes32 maskedPayload
    ) {
        require(cardIndex < 52, "invalid card index");
        Table storage t = tables[tid];
        return (t.encCardCommitments[cardIndex], t.encCardRandomizers[cardIndex], t.encCardMaskedPayloads[cardIndex]);
    }

    function getPartialDecryption(uint256 tid, uint8 cardIndex, uint8 playerIndex) external view override returns (
        bytes32 share
    ) {
        require(cardIndex < 52, "invalid card index");
        require(playerIndex < 2, "invalid player index");
        return tables[tid].partialDecryptions[playerIndex][cardIndex];
    }

    // -------------------------------------------------------
    //  Table management
    // -------------------------------------------------------

    function createTable(uint256 bigBlind) external payable override returns (uint256 tableId) {
        require(msg.value > 0, "must send buy-in");
        require(bigBlind > 0 && bigBlind <= msg.value, "invalid big blind");
        require(bigBlind % 2 == 0, "big blind must be even");

        tableId = nextTableId++;
        Table storage t = tables[tableId];
        t.players[0] = msg.sender;
        t.stacks[0]  = msg.value;
        t.buyIn      = msg.value;
        t.bigBlind   = bigBlind;
        t.state      = State.WAITING;

        emit TableCreated(tableId, msg.sender, msg.value, bigBlind);
    }

    function joinTable(uint256 tableId) external payable override {
        Table storage t = tables[tableId];
        require(t.state == State.WAITING, "not waiting");
        require(msg.value == t.buyIn, "must match buy-in");
        require(msg.sender != t.players[0], "cant join own table");

        t.players[1] = msg.sender;
        t.stacks[1]  = msg.value;

        // Post blinds: player 0 = dealer = small blind, player 1 = big blind
        uint256 sb = t.bigBlind / 2;
        uint256 bb = t.bigBlind;
        t.stacks[0] -= sb;
        t.stacks[1] -= bb;
        t.pot = sb + bb;
        t.roundContribution[0] = sb;
        t.roundContribution[1] = bb;
        t.currentBet   = bb;
        t.lastRaiseSize = bb;
        t.turn = 0; // dealer acts first pre-flop

        t.state = State.SHUFFLE_P1;
        _resetDeadline(t);

        emit PlayerJoined(tableId, msg.sender);
    }

    function cancelTable(uint256 tableId) external override {
        Table storage t = tables[tableId];
        require(t.state == State.WAITING, "not waiting");
        require(msg.sender == t.players[0], "only creator");

        t.state = State.CANCELLED;
        emit TableCancelled(tableId);
        (bool ok, ) = payable(t.players[0]).call{value: t.buyIn}("");
        require(ok, "transfer failed");
    }

    // -------------------------------------------------------
    //  Public key registration
    // -------------------------------------------------------

    function registerPublicKey(uint256 tableId, bytes32 publicKey)
        external override onlyPlayer(tableId)
    {
        Table storage t = tables[tableId];
        require(t.state == State.SHUFFLE_P1 || t.state == State.SHUFFLE_P2, "not in shuffle phase");
        uint8 pi = _pindex(t);
        require(t.playerPublicKeys[pi] == bytes32(0), "public key already registered");
        require(publicKey != bytes32(0), "invalid public key");
        t.playerPublicKeys[pi] = publicKey;
    }

    // -------------------------------------------------------
    //  Shuffle phase
    // -------------------------------------------------------

    function submitShuffle(
        uint256 tableId,
        bytes calldata proof,
        bytes32 newDeckCommitment,
        bytes32[52] calldata cardCommitments,
        bytes32[52] calldata cardRandomizers,
        bytes32[52] calldata cardMaskedPayloads
    )
        external override onlyPlayer(tableId) beforeDeadline(tableId)
    {
        Table storage t = tables[tableId];
        uint8 pi = _pindex(t);

        if (t.state == State.SHUFFLE_P1) {
            require(pi == 0, "P1 shuffles first");
        } else if (t.state == State.SHUFFLE_P2) {
            require(pi == 1, "P2 shuffles second");
        } else {
            revert("not in shuffle phase");
        }

        bytes32[] memory pub = new bytes32[](2);
        pub[0] = t.deckCommitment;
        pub[1] = newDeckCommitment;
        require(demoMode || shuffleVerifier.verify(proof, pub), "bad shuffle proof");

        t.deckCommitment = newDeckCommitment;

        if (t.state == State.SHUFFLE_P1) {
            t.state = State.SHUFFLE_P2;
        } else {
            // Both players must have registered public keys before dealing
            require(t.playerPublicKeys[0] != bytes32(0), "P1 missing public key");
            require(t.playerPublicKeys[1] != bytes32(0), "P2 missing public key");

            // Store per-card encrypted state from the final shuffled deck
            for (uint256 i = 0; i < 52; i++) {
                t.encCardCommitments[i] = cardCommitments[i];
                t.encCardRandomizers[i] = cardRandomizers[i];
                t.encCardMaskedPayloads[i] = cardMaskedPayloads[i];
            }

            t.state = State.DEALING;
            t.submitted[0] = false;
            t.submitted[1] = false;
        }
        _resetDeadline(t);
        emit ShuffleSubmitted(tableId, msg.sender, newDeckCommitment);
    }

    // -------------------------------------------------------
    //  Decrypt / reveal phases
    // -------------------------------------------------------

    function submitDecrypt(
        uint256 tableId,
        uint8[] calldata cardIndices,
        bytes32[] calldata partialDecryptionValues,
        bytes[] calldata proofs,
        uint8[] calldata cardValues
    )
        external override onlyPlayer(tableId) beforeDeadline(tableId)
    {
        Table storage t = tables[tableId];
        require(
            t.state == State.DEALING   || t.state == State.FLOP_REVEAL ||
            t.state == State.TURN_REVEAL || t.state == State.RIVER_REVEAL,
            "not in decrypt phase"
        );
        uint8 pi = _pindex(t);
        require(!t.submitted[pi], "already submitted");

        // Validate parallel arrays
        require(cardIndices.length > 0, "no cards");
        require(cardIndices.length == partialDecryptionValues.length, "length mismatch");
        require(cardIndices.length == proofs.length, "length mismatch");

        // Validate card indices match expected for this phase
        uint8[] memory expected = _expectedCardIndices(t.state, pi);
        require(cardIndices.length == expected.length, "wrong number of cards");
        for (uint256 i = 0; i < expected.length; i++) {
            require(cardIndices[i] == expected[i], "unexpected card index");
        }

        // Per-card proof verification
        for (uint256 i = 0; i < cardIndices.length; i++) {
            uint8 ci = cardIndices[i];

            bytes32[] memory pub = new bytes32[](5);
            pub[0] = t.encCardCommitments[ci];
            pub[1] = t.encCardRandomizers[ci];
            pub[2] = t.encCardMaskedPayloads[ci];
            pub[3] = partialDecryptionValues[i];
            pub[4] = t.playerPublicKeys[pi];
            require(demoMode || decryptVerifier.verify(proofs[i], pub), "bad decrypt proof");

            t.partialDecryptions[pi][ci] = partialDecryptionValues[i];
        }

        t.submitted[pi] = true;

        // For community card reveals: first submitter stores values, second must match
        bool isRevealPhase = t.state == State.FLOP_REVEAL ||
            t.state == State.TURN_REVEAL || t.state == State.RIVER_REVEAL;
        if (isRevealPhase && cardValues.length > 0) {
            if (t.pendingCardValues.length == 0) {
                for (uint256 i = 0; i < cardValues.length; i++) {
                    t.pendingCardValues.push(cardValues[i]);
                }
            } else {
                require(cardValues.length == t.pendingCardValues.length, "card count mismatch");
                for (uint256 i = 0; i < cardValues.length; i++) {
                    require(cardValues[i] == t.pendingCardValues[i], "card value mismatch between players");
                }
            }
        }

        emit DecryptSubmitted(tableId, msg.sender, cardIndices, partialDecryptionValues);

        // When both have submitted, advance
        if (t.submitted[0] && t.submitted[1]) {
            if (t.state == State.DEALING) {
                t.state = State.PREFLOP;
                t.actedSinceLastRaise[0] = false;
                t.actedSinceLastRaise[1] = false;
            } else {
                uint8 expectedCount = t.state == State.FLOP_REVEAL ? 3 : 1;
                require(t.pendingCardValues.length == expectedCount, "wrong card count");
                for (uint8 i = 0; i < expectedCount; i++) {
                    require(t.pendingCardValues[i] < 52, "invalid card");
                    t.communityCards[t.communityCardCount++] = t.pendingCardValues[i];
                }
                delete t.pendingCardValues;
                emit CommunityCardsRevealed(tableId, t.communityCardCount);

                State nextBet;
                if (t.state == State.FLOP_REVEAL)  nextBet = State.FLOP_BET;
                else if (t.state == State.TURN_REVEAL) nextBet = State.TURN_BET;
                else nextBet = State.RIVER_BET;

                _startBettingRound(tableId, nextBet);
                return;
            }
            t.submitted[0] = false;
            t.submitted[1] = false;
            _resetDeadline(t);
        } else {
            _resetDeadline(t);
        }
    }

    // -------------------------------------------------------
    //  Betting
    // -------------------------------------------------------

    function act(uint256 tableId, Action action, uint256 raiseAmount)
        external override onlyPlayer(tableId) beforeDeadline(tableId)
    {
        Table storage t = tables[tableId];
        require(_isBettingState(t.state), "not betting");

        uint8 pi = _pindex(t);
        require(pi == t.turn, "not your turn");

        uint256 toCall = t.currentBet - t.roundContribution[pi];
        uint256 amountPut = 0;

        if (action == Action.FOLD) {
            _settleWinner(tableId, 1 - pi);
            return;
        }

        if (action == Action.CHECK) {
            require(toCall == 0, "must call, raise, or fold");
        }

        if (action == Action.CALL) {
            require(toCall > 0, "nothing to call");
            uint256 amount = toCall;
            if (amount > t.stacks[pi]) amount = t.stacks[pi]; // all-in for less
            t.stacks[pi] -= amount;
            t.pot += amount;
            t.roundContribution[pi] += amount;
            amountPut = amount;
        }

        if (action == Action.RAISE) {
            require(t.stacks[pi] > toCall, "not enough to raise");
            uint256 maxRaise = t.stacks[pi] - toCall;
            uint256 actualRaise = raiseAmount > maxRaise ? maxRaise : raiseAmount;
            uint256 minRaise = t.lastRaiseSize > 0 ? t.lastRaiseSize : t.bigBlind;
            require(actualRaise >= minRaise || actualRaise == maxRaise, "raise too small");

            uint256 totalPut = toCall + actualRaise;
            t.stacks[pi] -= totalPut;
            t.pot += totalPut;
            t.roundContribution[pi] += totalPut;
            t.currentBet = t.roundContribution[pi];
            t.lastRaiseSize = actualRaise;
            amountPut = totalPut;

            t.actedSinceLastRaise[0] = false;
            t.actedSinceLastRaise[1] = false;
        }

        t.actedSinceLastRaise[pi] = true;
        emit ActionTaken(tableId, msg.sender, uint8(action), amountPut);

        bool betsEqual = t.roundContribution[0] == t.roundContribution[1];
        bool bothActed = t.actedSinceLastRaise[0] && t.actedSinceLastRaise[1];
        bool callerAllIn = (action == Action.CALL) && (t.stacks[pi] == 0);

        if ((bothActed && betsEqual) || callerAllIn) {
            _endBettingRound(tableId);
        } else {
            t.turn = 1 - pi;
            _resetDeadline(t);
        }
    }

    // -------------------------------------------------------
    //  Showdown
    // -------------------------------------------------------

    function revealHand(uint256 tableId, bytes calldata proof, uint8[2] calldata cards)
        external override onlyPlayer(tableId) beforeDeadline(tableId)
    {
        Table storage t = tables[tableId];
        require(t.state == State.SHOWDOWN, "not in showdown");

        uint8 pi = _pindex(t);
        require(!t.handRevealed[pi], "already revealed");

        require(cards[0] < 52 && cards[1] < 52, "invalid card");
        require(cards[0] != cards[1], "duplicate hole cards");

        // Check hole cards don't duplicate community cards
        for (uint256 i = 0; i < t.communityCardCount; i++) {
            require(cards[0] != t.communityCards[i], "hole card duplicates community");
            require(cards[1] != t.communityCards[i], "hole card duplicates community");
        }

        // If opponent already revealed, check no overlap
        uint8 opp = 1 - pi;
        if (t.handRevealed[opp]) {
            require(cards[0] != t.holeCards[opp][0] && cards[0] != t.holeCards[opp][1], "card already claimed");
            require(cards[1] != t.holeCards[opp][0] && cards[1] != t.holeCards[opp][1], "card already claimed");
        }

        // Hole card commitments come from the encrypted deck (set during P2 shuffle)
        require(t.encCardCommitments[pi * 2] != bytes32(0), "deck not stored");

        // Public inputs match reveal circuit: card_commitments[2], revealed_cards[2]
        bytes32[] memory pub = new bytes32[](4);
        pub[0] = t.encCardCommitments[pi * 2];       // card_commitments[0]
        pub[1] = t.encCardCommitments[pi * 2 + 1];   // card_commitments[1]
        pub[2] = bytes32(uint256(cards[0]));           // revealed_cards[0]
        pub[3] = bytes32(uint256(cards[1]));           // revealed_cards[1]
        require(demoMode || revealVerifier.verify(proof, pub), "bad reveal proof");

        t.holeCards[pi][0] = cards[0];
        t.holeCards[pi][1] = cards[1];
        t.handRevealed[pi] = true;
        emit HandRevealed(tableId, msg.sender, cards[0], cards[1]);

        if (t.handRevealed[0] && t.handRevealed[1]) {
            _evaluateShowdown(tableId);
        } else {
            _resetDeadline(t);
        }
    }

    // -------------------------------------------------------
    //  Timeout
    // -------------------------------------------------------

    function claimTimeout(uint256 tableId) external override {
        Table storage t = tables[tableId];
        require(t.players[0] != address(0), "table not found");
        require(t.state != State.WAITING && t.state != State.SETTLED && t.state != State.CANCELLED, "no timeout");
        require(block.timestamp > t.deadline, "not timed out");

        if (t.state == State.SHUFFLE_P1) {
            _settleTimeout(tableId, 1);
        } else if (t.state == State.SHUFFLE_P2) {
            _settleTimeout(tableId, 0);
        } else if (
            t.state == State.DEALING  || t.state == State.FLOP_REVEAL ||
            t.state == State.TURN_REVEAL || t.state == State.RIVER_REVEAL
        ) {
            if (t.submitted[0] && !t.submitted[1]) {
                _settleTimeout(tableId, 0);
            } else if (!t.submitted[0] && t.submitted[1]) {
                _settleTimeout(tableId, 1);
            } else {
                _settleSplit(tableId, State.CANCELLED);
            }
        } else if (_isBettingState(t.state)) {
            _settleWinner(tableId, 1 - t.turn);
        } else if (t.state == State.SHOWDOWN) {
            if (t.handRevealed[0] && !t.handRevealed[1]) {
                _settleTimeout(tableId, 0);
            } else if (!t.handRevealed[0] && t.handRevealed[1]) {
                _settleTimeout(tableId, 1);
            } else {
                _settleSplit(tableId, State.CANCELLED);
            }
        }
    }

    // -------------------------------------------------------
    //  Internals: card index validation
    // -------------------------------------------------------

    function _expectedCardIndices(State state, uint8 playerIndex)
        internal pure returns (uint8[] memory)
    {
        if (state == State.DEALING) {
            // Each player decrypts the OTHER player's hole cards
            uint8 otherPlayer = 1 - playerIndex;
            uint8[] memory indices = new uint8[](2);
            indices[0] = otherPlayer * 2;
            indices[1] = otherPlayer * 2 + 1;
            return indices;
        } else if (state == State.FLOP_REVEAL) {
            uint8[] memory indices = new uint8[](3);
            indices[0] = 4;
            indices[1] = 5;
            indices[2] = 6;
            return indices;
        } else if (state == State.TURN_REVEAL) {
            uint8[] memory indices = new uint8[](1);
            indices[0] = 7;
            return indices;
        } else if (state == State.RIVER_REVEAL) {
            uint8[] memory indices = new uint8[](1);
            indices[0] = 8;
            return indices;
        }
        revert("invalid state for decrypt");
    }

    // -------------------------------------------------------
    //  Internals: state transitions
    // -------------------------------------------------------

    function _startBettingRound(uint256 tableId, State newState) internal {
        Table storage t = tables[tableId];

        if (t.stacks[0] == 0 || t.stacks[1] == 0) {
            t.state = newState;
            _endBettingRound(tableId);
            return;
        }

        t.state = newState;
        t.roundContribution[0] = 0;
        t.roundContribution[1] = 0;
        t.currentBet = 0;
        t.lastRaiseSize = t.bigBlind;
        t.actedSinceLastRaise[0] = false;
        t.actedSinceLastRaise[1] = false;
        t.turn = 1; // non-dealer acts first post-flop
        t.submitted[0] = false;
        t.submitted[1] = false;
        _resetDeadline(t);
    }

    function _endBettingRound(uint256 tableId) internal {
        Table storage t = tables[tableId];
        t.submitted[0] = false;
        t.submitted[1] = false;

        if (t.state == State.PREFLOP)   { t.state = State.FLOP_REVEAL;  }
        else if (t.state == State.FLOP_BET)  { t.state = State.TURN_REVEAL;  }
        else if (t.state == State.TURN_BET)  { t.state = State.RIVER_REVEAL; }
        else if (t.state == State.RIVER_BET) { t.state = State.SHOWDOWN;     }

        _resetDeadline(t);
    }

    // -------------------------------------------------------
    //  Internals: settlement
    // -------------------------------------------------------

    function _settleWinner(uint256 tableId, uint8 winner) internal {
        Table storage t = tables[tableId];
        uint8 loser = 1 - winner;

        uint256 potAmount = t.pot;
        uint256 winPay = potAmount + t.stacks[winner];
        uint256 losePay = t.stacks[loser];

        t.state = State.SETTLED;
        t.winner = t.players[winner];
        t.pot = 0;
        t.stacks[0] = 0;
        t.stacks[1] = 0;

        emit HandSettled(tableId, t.players[winner], potAmount);

        (bool ok1, ) = payable(t.players[winner]).call{value: winPay}("");
        require(ok1, "transfer failed");
        if (losePay > 0) {
            (bool ok2, ) = payable(t.players[loser]).call{value: losePay}("");
            require(ok2, "transfer failed");
        }
    }

    function _settleTimeout(uint256 tableId, uint8 beneficiary) internal {
        Table storage t = tables[tableId];
        uint256 total = t.pot + t.stacks[0] + t.stacks[1];

        t.state = State.CANCELLED;
        t.winner = t.players[beneficiary];
        t.pot = 0;
        t.stacks[0] = 0;
        t.stacks[1] = 0;

        emit TimeoutClaimed(tableId, t.players[beneficiary]);
        (bool ok, ) = payable(t.players[beneficiary]).call{value: total}("");
        require(ok, "transfer failed");
    }

    function _settleSplit(uint256 tableId, State endState) internal {
        Table storage t = tables[tableId];
        uint256 total = t.pot + t.stacks[0] + t.stacks[1];

        t.state = endState;
        t.winner = address(0);
        t.pot = 0;
        t.stacks[0] = 0;
        t.stacks[1] = 0;

        if (endState == State.CANCELLED) {
            emit TimeoutClaimed(tableId, address(0));
        } else {
            emit HandSettled(tableId, address(0), total);
        }

        (bool ok1, ) = payable(t.players[0]).call{value: total / 2}("");
        require(ok1, "transfer failed");
        (bool ok2, ) = payable(t.players[1]).call{value: total - total / 2}("");
        require(ok2, "transfer failed");
    }

    function _evaluateShowdown(uint256 tableId) internal {
        Table storage t = tables[tableId];

        uint8[7] memory hand0;
        uint8[7] memory hand1;
        hand0[0] = t.holeCards[0][0];
        hand0[1] = t.holeCards[0][1];
        hand1[0] = t.holeCards[1][0];
        hand1[1] = t.holeCards[1][1];
        for (uint256 i = 0; i < 5; i++) {
            hand0[i + 2] = t.communityCards[i];
            hand1[i + 2] = t.communityCards[i];
        }

        uint256 score0 = HandEvaluator.evaluate(hand0);
        uint256 score1 = HandEvaluator.evaluate(hand1);

        if (score0 > score1) {
            _settleWinner(tableId, 0);
        } else if (score1 > score0) {
            _settleWinner(tableId, 1);
        } else {
            _settleSplit(tableId, State.SETTLED);
        }
    }

    // -------------------------------------------------------
    //  Internals: helpers
    // -------------------------------------------------------

    function _pindex(Table storage t) internal view returns (uint8) {
        if (t.players[0] == msg.sender) return 0;
        if (t.players[1] == msg.sender) return 1;
        revert("not a player");
    }

    function _isBettingState(State s) internal pure returns (bool) {
        return s == State.PREFLOP || s == State.FLOP_BET ||
               s == State.TURN_BET || s == State.RIVER_BET;
    }

    function _resetDeadline(Table storage t) internal {
        t.deadline = block.timestamp + actionTimeout;
    }
}
