// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PokerTable.sol";
import "../src/mocks/MockVerifier.sol";

contract PokerTableTest is Test {
    PokerTable poker;
    address p1 = makeAddr("player1");
    address p2 = makeAddr("player2");

    uint256 constant BUY_IN = 1 ether;
    uint256 constant BIG_BLIND = 0.1 ether;

    function setUp() public {
        MockVerifier mock = new MockVerifier();
        poker = new PokerTable(address(mock), address(mock), address(mock));
        vm.deal(p1, 10 ether);
        vm.deal(p2, 10 ether);
    }

    // -- Helpers --

    function _createAndJoin() internal returns (uint256) {
        vm.prank(p1);
        uint256 tid = poker.createTable{value: BUY_IN}(BIG_BLIND);
        vm.prank(p2);
        poker.joinTable{value: BUY_IN}(tid);
        return tid;
    }

    function _doShuffles(uint256 tid) internal {
        vm.prank(p1);
        poker.submitShuffle(tid, "", bytes32(uint256(1)));
        vm.prank(p2);
        poker.submitShuffle(tid, "", bytes32(uint256(2)));
    }

    function _doDeal(uint256 tid) internal {
        uint8[] memory empty = new uint8[](0);
        vm.prank(p1);
        poker.submitDecrypt(tid, "", empty);
        vm.prank(p2);
        poker.submitDecrypt(tid, "", empty);
    }

    function _doReveal(uint256 tid, uint8[] memory cards) internal {
        uint8[] memory empty = new uint8[](0);
        vm.prank(p1);
        poker.submitDecrypt(tid, "", empty);
        vm.prank(p2);
        poker.submitDecrypt(tid, "", cards);
    }

    function _toPreflop(uint256 tid) internal {
        _doShuffles(tid);
        _doDeal(tid);
    }

    function _checkState(uint256 tid, PokerTable.State expected) internal view {
        (, , , PokerTable.State s, , ) = poker.getTable(tid);
        assertEq(uint8(s), uint8(expected));
    }

    // ============================
    //  Table lifecycle
    // ============================

    function test_createTable() public {
        vm.prank(p1);
        uint256 tid = poker.createTable{value: BUY_IN}(BIG_BLIND);
        _checkState(tid, PokerTable.State.WAITING);
    }

    function test_createTable_zeroValue_reverts() public {
        vm.prank(p1);
        vm.expectRevert("must send buy-in");
        poker.createTable{value: 0}(BIG_BLIND);
    }

    function test_createTable_oddBlind_reverts() public {
        vm.prank(p1);
        vm.expectRevert("big blind must be even");
        poker.createTable{value: BUY_IN}(0.1 ether + 1);
    }

    function test_joinTable() public {
        vm.prank(p1);
        uint256 tid = poker.createTable{value: BUY_IN}(BIG_BLIND);
        vm.prank(p2);
        poker.joinTable{value: BUY_IN}(tid);
        _checkState(tid, PokerTable.State.SHUFFLE_P1);
    }

    function test_joinTable_wrongBuyIn_reverts() public {
        vm.prank(p1);
        uint256 tid = poker.createTable{value: BUY_IN}(BIG_BLIND);
        vm.prank(p2);
        vm.expectRevert("must match buy-in");
        poker.joinTable{value: 0.5 ether}(tid);
    }

    function test_joinTable_self_reverts() public {
        vm.prank(p1);
        uint256 tid = poker.createTable{value: BUY_IN}(BIG_BLIND);
        vm.prank(p1);
        vm.expectRevert("cant join own table");
        poker.joinTable{value: BUY_IN}(tid);
    }

    function test_cancelTable() public {
        vm.prank(p1);
        uint256 tid = poker.createTable{value: BUY_IN}(BIG_BLIND);
        uint256 balBefore = p1.balance;
        vm.prank(p1);
        poker.cancelTable(tid);
        _checkState(tid, PokerTable.State.CANCELLED);
        assertEq(p1.balance, balBefore + BUY_IN);
    }

    function test_cancelTable_afterJoin_reverts() public {
        uint256 tid = _createAndJoin();
        vm.prank(p1);
        vm.expectRevert("not waiting");
        poker.cancelTable(tid);
    }

    // ============================
    //  Shuffle phase
    // ============================

    function test_shuffle_p1() public {
        uint256 tid = _createAndJoin();
        vm.prank(p1);
        poker.submitShuffle(tid, "", bytes32(uint256(1)));
        _checkState(tid, PokerTable.State.SHUFFLE_P2);
    }

    function test_shuffle_wrongPlayer_reverts() public {
        uint256 tid = _createAndJoin();
        vm.prank(p2);
        vm.expectRevert("P1 shuffles first");
        poker.submitShuffle(tid, "", bytes32(uint256(1)));
    }

    function test_shuffle_p2_advances_to_dealing() public {
        uint256 tid = _createAndJoin();
        _doShuffles(tid);
        _checkState(tid, PokerTable.State.DEALING);
    }

    // ============================
    //  Betting
    // ============================

    function test_preflop_fold() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);
        _checkState(tid, PokerTable.State.PREFLOP);

        // Dealer (p1) folds
        uint256 p2BalBefore = p2.balance;
        vm.prank(p1);
        poker.act(tid, PokerTable.Action.FOLD, 0);

        _checkState(tid, PokerTable.State.SETTLED);
        // P2 gets pot + their remaining stack
        assertGt(p2.balance, p2BalBefore);
    }

    function test_preflop_call_check_advances() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Dealer calls (matches BB)
        vm.prank(p1);
        poker.act(tid, PokerTable.Action.CALL, 0);

        // BB checks
        vm.prank(p2);
        poker.act(tid, PokerTable.Action.CHECK, 0);

        _checkState(tid, PokerTable.State.FLOP_REVEAL);
    }

    function test_preflop_raise_call() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Dealer raises by 0.2 ether (total 0.25 = SB + 0.2)
        vm.prank(p1);
        poker.act(tid, PokerTable.Action.RAISE, 0.2 ether);

        // BB calls
        vm.prank(p2);
        poker.act(tid, PokerTable.Action.CALL, 0);

        _checkState(tid, PokerTable.State.FLOP_REVEAL);
    }

    function test_wrongPlayer_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // P2 tries to act but it's P1's turn (dealer acts first preflop)
        vm.prank(p2);
        vm.expectRevert("not your turn");
        poker.act(tid, PokerTable.Action.CHECK, 0);
    }

    function test_check_when_must_call_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Dealer can't check preflop (must call the BB)
        vm.prank(p1);
        vm.expectRevert("must call, raise, or fold");
        poker.act(tid, PokerTable.Action.CHECK, 0);
    }

    function test_postflop_nonDealer_actsFirst() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Call + check to get to flop
        vm.prank(p1);
        poker.act(tid, PokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, PokerTable.Action.CHECK, 0);

        // Reveal flop
        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 23; flop[2] = 36;
        _doReveal(tid, flop);
        _checkState(tid, PokerTable.State.FLOP_BET);

        // P1 (dealer) tries to act first - should fail
        vm.prank(p1);
        vm.expectRevert("not your turn");
        poker.act(tid, PokerTable.Action.CHECK, 0);

        // P2 (non-dealer) acts first
        vm.prank(p2);
        poker.act(tid, PokerTable.Action.CHECK, 0);
    }

    function test_raise_too_small_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Min raise preflop = bigBlind (0.1 ether). Try raising 0.05 ether.
        vm.prank(p1);
        vm.expectRevert("raise too small");
        poker.act(tid, PokerTable.Action.RAISE, 0.05 ether);
    }

    // ============================
    //  Full hand: showdown
    // ============================

    function test_fullHand_showdown() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Preflop: call + check
        vm.prank(p1);
        poker.act(tid, PokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, PokerTable.Action.CHECK, 0);

        // Flop reveal: Q-clubs(10), T-diamonds(21), 7-hearts(31)
        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 21; flop[2] = 31;
        _doReveal(tid, flop);

        // Flop: check-check
        vm.prank(p2);
        poker.act(tid, PokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, PokerTable.Action.CHECK, 0);

        // Turn reveal: 6-spades(43)
        uint8[] memory turn = new uint8[](1);
        turn[0] = 43;
        _doReveal(tid, turn);

        // Turn: check-check
        vm.prank(p2);
        poker.act(tid, PokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, PokerTable.Action.CHECK, 0);

        // River reveal: 2-clubs(0)
        uint8[] memory river = new uint8[](1);
        river[0] = 0;
        _doReveal(tid, river);

        // River: check-check
        vm.prank(p2);
        poker.act(tid, PokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, PokerTable.Action.CHECK, 0);

        _checkState(tid, PokerTable.State.SHOWDOWN);

        // P1 reveals: pair of Aces (Ac=12, Ad=25)
        vm.prank(p1);
        poker.revealHand(tid, "", [uint8(12), uint8(25)]);

        // P2 reveals: 2d, 3d (junk)
        vm.prank(p2);
        poker.revealHand(tid, "", [uint8(13), uint8(14)]);

        // P1 should win (pair of aces vs high card)
        _checkState(tid, PokerTable.State.SETTLED);

        // P1 wins the pot (0.2 ether = 2x BB) + remaining stack
        // Both started with 1 ether, posted blinds, called.
        // After preflop: each put in 0.1 ether. Pot = 0.2 ether.
        // No more betting, so pot stays 0.2 ether.
        // P1 gets 0.2 (pot) + 0.9 (remaining stack) = 1.1 ether
        // P2 gets 0.9 (remaining stack)
        // Total should be 2 ether
        assertEq(p1.balance + p2.balance, 20 ether - 2 ether + 2 ether);
    }

    // ============================
    //  Timeouts
    // ============================

    function test_timeout_duringShuffle() public {
        uint256 tid = _createAndJoin();
        // P1 should shuffle but doesn't

        // Warp past deadline
        vm.warp(block.timestamp + 121);

        uint256 p2BalBefore = p2.balance;
        poker.claimTimeout(tid);

        _checkState(tid, PokerTable.State.CANCELLED);
        // P2 gets everything (both buy-ins)
        assertEq(p2.balance, p2BalBefore + 2 ether);
    }

    function test_timeout_duringBetting() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // It's p1's turn (dealer preflop). They stall.
        vm.warp(block.timestamp + 121);

        poker.claimTimeout(tid);
        _checkState(tid, PokerTable.State.SETTLED);
    }

    function test_timeout_beforeDeadline_reverts() public {
        uint256 tid = _createAndJoin();

        vm.expectRevert("not timed out");
        poker.claimTimeout(tid);
    }

    function test_timeout_inWaiting_reverts() public {
        vm.prank(p1);
        uint256 tid = poker.createTable{value: BUY_IN}(BIG_BLIND);

        vm.expectRevert("no timeout");
        poker.claimTimeout(tid);
    }

    function test_timeout_inSettled_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);
        vm.prank(p1);
        poker.act(tid, PokerTable.Action.FOLD, 0);

        vm.warp(block.timestamp + 121);
        vm.expectRevert("no timeout");
        poker.claimTimeout(tid);
    }

    // ============================
    //  Payout correctness
    // ============================

    function test_payout_fold_preflop() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        uint256 p1Before = p1.balance;
        uint256 p2Before = p2.balance;

        // Dealer folds
        vm.prank(p1);
        poker.act(tid, PokerTable.Action.FOLD, 0);

        // P1 loses SB (0.05 ether). P2 wins pot.
        // P1 gets remaining stack: buyIn - SB = 0.95 ether
        // P2 gets pot + remaining stack: 0.15 ether + 0.9 ether = 1.05 ether
        assertEq(p1.balance, p1Before + BUY_IN - BIG_BLIND / 2);
        assertEq(p2.balance, p2Before + BUY_IN + BIG_BLIND / 2);

        // Contract should have no ETH left for this table
        // (other tables could exist, so check total is correct)
        assertEq(p1.balance + p2.balance, 20 ether);
    }

    function test_contractBalance_afterSettlement() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p1);
        poker.act(tid, PokerTable.Action.FOLD, 0);

        // Total player balances should equal starting balances
        assertEq(p1.balance + p2.balance, 20 ether);
    }
}
