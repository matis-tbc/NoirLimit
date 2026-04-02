// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IVerifier.sol";
import "./HandEvaluator.sol";

contract PokerTable {

    // -------------------------------------------------------
    //  Types
    // -------------------------------------------------------

    enum State {
        WAITING,       // 0
        SHUFFLE_P1,    // 1
        SHUFFLE_P2,    // 2
        DEALING,       // 3
        PREFLOP,       // 4
        FLOP_REVEAL,   // 5
        FLOP_BET,      // 6
        TURN_REVEAL,   // 7
        TURN_BET,      // 8
        RIVER_REVEAL,  // 9
        RIVER_BET,     // 10
        SHOWDOWN,      // 11
        SETTLED,       // 12
        CANCELLED      // 13
    }

    enum Action { FOLD, CHECK, CALL, RAISE }

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
    //  Events
    // -------------------------------------------------------

    event TableCreated(uint256 indexed tableId, address creator, uint256 buyIn, uint256 bigBlind);
    event PlayerJoined(uint256 indexed tableId, address player);
    event TableCancelled(uint256 indexed tableId);
    event ShuffleSubmitted(uint256 indexed tableId, address player, bytes32 newDeckCommitment);
    event DecryptSubmitted(uint256 indexed tableId, address player);
    event CommunityCardsRevealed(uint256 indexed tableId, uint8 newCardCount);
    event ActionTaken(uint256 indexed tableId, address player, uint8 action, uint256 amount);
    event HandRevealed(uint256 indexed tableId, address player, uint8 card0, uint8 card1);
    event HandSettled(uint256 indexed tableId, address winner, uint256 pot);
    event TimeoutClaimed(uint256 indexed tableId, address beneficiary);

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

    function getTable(uint256 tid) external view returns (
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

    function createTable(uint256 bigBlind) external payable returns (uint256 tableId) {
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

    function joinTable(uint256 tableId) external payable {
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

    function cancelTable(uint256 tableId) external {
        Table storage t = tables[tableId];
        require(t.state == State.WAITING, "not waiting");
        require(msg.sender == t.players[0], "only creator");

        t.state = State.CANCELLED;
        payable(t.players[0]).transfer(t.buyIn);
        emit TableCancelled(tableId);
    }

    // -------------------------------------------------------
    //  Shuffle phase
    // -------------------------------------------------------

    function submitShuffle(uint256 tableId, bytes calldata proof, bytes32 newDeckCommitment)
        external onlyPlayer(tableId) beforeDeadline(tableId)
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

    function submitDecrypt(uint256 tableId, bytes calldata proof, uint8[] calldata cardValues)
        external onlyPlayer(tableId) beforeDeadline(tableId)
    {
        Table storage t = tables[tableId];
        require(
            t.state == State.DEALING   || t.state == State.FLOP_REVEAL ||
            t.state == State.TURN_REVEAL || t.state == State.RIVER_REVEAL,
            "not in decrypt phase"
        );
        uint8 pi = _pindex(t);
        require(!t.submitted[pi], "already submitted");

        // Verify decrypt proof (mock verifier accepts all)
        bytes32[] memory pub = new bytes32[](1);
        pub[0] = t.deckCommitment;
        require(decryptVerifier.verify(proof, pub), "bad decrypt proof");

        t.submitted[pi] = true;
        emit DecryptSubmitted(tableId, msg.sender);

        // When both have submitted, advance
        if (t.submitted[0] && t.submitted[1]) {
            if (t.state == State.DEALING) {
                t.state = State.PREFLOP;
                // Blinds already set in joinTable
                t.actedSinceLastRaise[0] = false;
                t.actedSinceLastRaise[1] = false;
            } else {
                // Store community cards from the second submitter
                uint8 expected = t.state == State.FLOP_REVEAL ? 3 : 1;
                require(cardValues.length == expected, "wrong card count");
                for (uint8 i = 0; i < expected; i++) {
                    require(cardValues[i] < 52, "invalid card");
                    t.communityCards[t.communityCardCount++] = cardValues[i];
                }
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
        external onlyPlayer(tableId) beforeDeadline(tableId)
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
        external onlyPlayer(tableId) beforeDeadline(tableId)
    {
        Table storage t = tables[tableId];
        require(t.state == State.SHOWDOWN, "not in showdown");

        uint8 pi = _pindex(t);
        require(!t.handRevealed[pi], "already revealed");

        require(cards[0] < 52 && cards[1] < 52, "invalid card");

        bytes32[] memory pub = new bytes32[](4);
        pub[0] = bytes32(uint256(cards[0]));
        pub[1] = bytes32(uint256(cards[1]));
        pub[2] = bytes32(uint256(0)); // placeholder commitment
        pub[3] = bytes32(uint256(0));
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

    function claimTimeout(uint256 tableId) external {
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

        payable(t.players[winner]).transfer(winPay);
        if (losePay > 0) payable(t.players[loser]).transfer(losePay);
    }

    function _settleTimeout(uint256 tableId, uint8 beneficiary) internal {
        Table storage t = tables[tableId];
        uint256 total = t.pot + t.stacks[0] + t.stacks[1];

        t.state = State.CANCELLED;
        t.pot = 0;
        t.stacks[0] = 0;
        t.stacks[1] = 0;

        emit TimeoutClaimed(tableId, t.players[beneficiary]);
        payable(t.players[beneficiary]).transfer(total);
    }

    function _settleSplit(uint256 tableId, State endState) internal {
        Table storage t = tables[tableId];
        uint256 total = t.pot + t.stacks[0] + t.stacks[1];

        t.state = endState;
        t.pot = 0;
        t.stacks[0] = 0;
        t.stacks[1] = 0;

        payable(t.players[0]).transfer(total / 2);
        payable(t.players[1]).transfer(total - total / 2);

        if (endState == State.CANCELLED) {
            emit TimeoutClaimed(tableId, address(0));
        } else {
            emit HandSettled(tableId, address(0), total);
        }
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
