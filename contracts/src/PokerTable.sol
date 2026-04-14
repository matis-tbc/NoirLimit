// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IPokerTable.sol";
import "./interfaces/IVerifier.sol";
import "./HandEvaluator.sol";

contract PokerTable is IPokerTable {

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

        // Card commitments from deal phase (used to bind reveals to dealt cards)
        bytes32[2][2] holeCardCommitments; // [player][card] commitment from deal
        bytes32[2] playerPublicKeys;       // public keys registered at join

        // First submitter's claimed card values during community reveal
        // Second submitter must match these
        uint8[] pendingCardValues;
    }

    // -------------------------------------------------------
    //  State variables
    // -------------------------------------------------------

    uint256 public nextTableId;
    uint256 public actionTimeout = 120;

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

    constructor(address _shuffle, address _decrypt, address _reveal) {
        shuffleVerifier = IVerifier(_shuffle);
        decryptVerifier = IVerifier(_decrypt);
        revealVerifier  = IVerifier(_reveal);
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
        // Public keys are registered via registerPublicKey before shuffle

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

    function submitShuffle(uint256 tableId, bytes calldata proof, bytes32 newDeckCommitment)
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
        require(shuffleVerifier.verify(proof, pub), "bad shuffle proof");

        t.deckCommitment = newDeckCommitment;

        if (t.state == State.SHUFFLE_P1) {
            t.state = State.SHUFFLE_P2;
        } else {
            // Both players must have registered public keys before dealing
            require(t.playerPublicKeys[0] != bytes32(0), "P1 missing public key");
            require(t.playerPublicKeys[1] != bytes32(0), "P2 missing public key");
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
        bytes calldata proof,
        uint8[] calldata cardValues,
        bytes32[] calldata cardCommitments
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

        // Store hole card commitments during DEALING
        if (t.state == State.DEALING) {
            require(cardCommitments.length == 2, "must provide 2 card commitments");
            t.holeCardCommitments[pi][0] = cardCommitments[0];
            t.holeCardCommitments[pi][1] = cardCommitments[1];
        }

        // Verify decrypt proof
        // Public inputs: deck commitment, player public key, and card commitments if provided
        bytes32[] memory pub = new bytes32[](5);
        pub[0] = t.deckCommitment;
        pub[1] = cardCommitments.length > 0 ? cardCommitments[0] : bytes32(0);
        pub[2] = cardCommitments.length > 1 ? cardCommitments[1] : bytes32(0);
        pub[3] = bytes32(uint256(cardValues.length));
        pub[4] = t.playerPublicKeys[pi];
        require(decryptVerifier.verify(proof, pub), "bad decrypt proof");

        t.submitted[pi] = true;

        // For community card reveals: first submitter stores values, second must match
        bool isRevealPhase = t.state == State.FLOP_REVEAL ||
            t.state == State.TURN_REVEAL || t.state == State.RIVER_REVEAL;
        if (isRevealPhase && cardValues.length > 0) {
            if (t.pendingCardValues.length == 0) {
                // First submitter: store pending values
                for (uint256 i = 0; i < cardValues.length; i++) {
                    t.pendingCardValues.push(cardValues[i]);
                }
            } else {
                // Second submitter: must match first submitter's values
                require(cardValues.length == t.pendingCardValues.length, "card count mismatch");
                for (uint256 i = 0; i < cardValues.length; i++) {
                    require(cardValues[i] == t.pendingCardValues[i], "card value mismatch between players");
                }
            }
        }

        emit DecryptSubmitted(tableId, msg.sender);

        // When both have submitted, advance
        if (t.submitted[0] && t.submitted[1]) {
            if (t.state == State.DEALING) {
                t.state = State.PREFLOP;
                // Blinds already set in joinTable
                t.actedSinceLastRaise[0] = false;
                t.actedSinceLastRaise[1] = false;
            } else {
                // Both players agreed on card values, store them
                uint8 expected = t.state == State.FLOP_REVEAL ? 3 : 1;
                require(t.pendingCardValues.length == expected, "wrong card count");
                for (uint8 i = 0; i < expected; i++) {
                    require(t.pendingCardValues[i] < 52, "invalid card");
                    t.communityCards[t.communityCardCount++] = t.pendingCardValues[i];
                }
                delete t.pendingCardValues;
                emit CommunityCardsRevealed(tableId, t.communityCardCount);

                // Next betting round
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

            // Reset acted flags
            t.actedSinceLastRaise[0] = false;
            t.actedSinceLastRaise[1] = false;
        }

        t.actedSinceLastRaise[pi] = true;
        emit ActionTaken(tableId, msg.sender, uint8(action), amountPut);

        // Check if round is over
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

        // Public inputs match reveal circuit: card_commitments[2], revealed_cards[2]
        bytes32[] memory pub = new bytes32[](4);
        pub[0] = t.holeCardCommitments[pi][0];     // card_commitments[0]
        pub[1] = t.holeCardCommitments[pi][1];     // card_commitments[1]
        pub[2] = bytes32(uint256(cards[0]));        // revealed_cards[0]
        pub[3] = bytes32(uint256(cards[1]));        // revealed_cards[1]
        require(revealVerifier.verify(proof, pub), "bad reveal proof");

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
            // P1 stalled
            _settleTimeout(tableId, 1);
        } else if (t.state == State.SHUFFLE_P2) {
            // P2 stalled
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
                // Neither submitted: split
                _settleSplit(tableId, State.CANCELLED);
            }
        } else if (_isBettingState(t.state)) {
            // Acting player timed out - they forfeit
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
    //  Internals: state transitions
    // -------------------------------------------------------

    function _startBettingRound(uint256 tableId, State newState) internal {
        Table storage t = tables[tableId];

        // If either player is all-in, skip this betting round
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
