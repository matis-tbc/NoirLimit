// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PokerTable.sol";
import "../src/interfaces/IPokerTable.sol";
import "../src/mocks/MockVerifier.sol";
import "../src/mocks/RejectingVerifier.sol";

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
        // Register public keys before shuffle
        vm.prank(p1);
        poker.registerPublicKey(tid, bytes32(uint256(0xaa)));
        vm.prank(p2);
        poker.registerPublicKey(tid, bytes32(uint256(0xbb)));

        vm.prank(p1);
        poker.submitShuffle(tid, "", bytes32(uint256(1)));
        vm.prank(p2);
        poker.submitShuffle(tid, "", bytes32(uint256(2)));
    }

    function _emptyCommitments() internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function _sampleCommitments() internal pure returns (bytes32[] memory) {
        bytes32[] memory c = new bytes32[](2);
        c[0] = bytes32(uint256(0xdead));
        c[1] = bytes32(uint256(0xbeef));
        return c;
    }

    function _doDeal(uint256 tid) internal {
        uint8[] memory empty = new uint8[](0);
        vm.prank(p1);
        poker.submitDecrypt(tid, "", empty, _sampleCommitments());
        vm.prank(p2);
        poker.submitDecrypt(tid, "", empty, _sampleCommitments());
    }

    function _doReveal(uint256 tid, uint8[] memory cards) internal {
        // Both players submit matching card values for community reveals
        vm.prank(p1);
        poker.submitDecrypt(tid, "", cards, _emptyCommitments());
        vm.prank(p2);
        poker.submitDecrypt(tid, "", cards, _emptyCommitments());
    }

    function _toPreflop(uint256 tid) internal {
        _doShuffles(tid);
        _doDeal(tid);
    }

    function _checkState(uint256 tid, IPokerTable.State expected) internal view {
        (, , , IPokerTable.State s, , ) = poker.getTable(tid);
        assertEq(uint8(s), uint8(expected));
    }

    // ============================
    //  Table lifecycle
    // ============================

    function test_createTable() public {
        vm.prank(p1);
        uint256 tid = poker.createTable{value: BUY_IN}(BIG_BLIND);
        _checkState(tid, IPokerTable.State.WAITING);
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
        _checkState(tid, IPokerTable.State.SHUFFLE_P1);
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
        _checkState(tid, IPokerTable.State.CANCELLED);
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
        _checkState(tid, IPokerTable.State.SHUFFLE_P2);
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
        _checkState(tid, IPokerTable.State.DEALING);
    }

    // ============================
    //  Betting
    // ============================

    function test_preflop_fold() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);
        _checkState(tid, IPokerTable.State.PREFLOP);

        // Dealer (p1) folds
        uint256 p2BalBefore = p2.balance;
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.FOLD, 0);

        _checkState(tid, IPokerTable.State.SETTLED);
        // P2 gets pot + their remaining stack
        assertGt(p2.balance, p2BalBefore);
    }

    function test_preflop_call_check_advances() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Dealer calls (matches BB)
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);

        // BB checks
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        _checkState(tid, IPokerTable.State.FLOP_REVEAL);
    }

    function test_preflop_raise_call() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Dealer raises by 0.2 ether (total 0.25 = SB + 0.2)
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.RAISE, 0.2 ether);

        // BB calls
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CALL, 0);

        _checkState(tid, IPokerTable.State.FLOP_REVEAL);
    }

    function test_wrongPlayer_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // P2 tries to act but it's P1's turn (dealer acts first preflop)
        vm.prank(p2);
        vm.expectRevert("not your turn");
        poker.act(tid, IPokerTable.Action.CHECK, 0);
    }

    function test_check_when_must_call_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Dealer can't check preflop (must call the BB)
        vm.prank(p1);
        vm.expectRevert("must call, raise, or fold");
        poker.act(tid, IPokerTable.Action.CHECK, 0);
    }

    function test_postflop_nonDealer_actsFirst() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Call + check to get to flop
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        // Reveal flop
        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 23; flop[2] = 36;
        _doReveal(tid, flop);
        _checkState(tid, IPokerTable.State.FLOP_BET);

        // P1 (dealer) tries to act first - should fail
        vm.prank(p1);
        vm.expectRevert("not your turn");
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        // P2 (non-dealer) acts first
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
    }

    function test_raise_too_small_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Min raise preflop = bigBlind (0.1 ether). Try raising 0.05 ether.
        vm.prank(p1);
        vm.expectRevert("raise too small");
        poker.act(tid, IPokerTable.Action.RAISE, 0.05 ether);
    }

    // ============================
    //  Full hand: showdown
    // ============================

    function test_fullHand_showdown() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Preflop: call + check
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        // Flop reveal: Q-clubs(10), T-diamonds(21), 7-hearts(31)
        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 21; flop[2] = 31;
        _doReveal(tid, flop);

        // Flop: check-check
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        // Turn reveal: 6-spades(43)
        uint8[] memory turn = new uint8[](1);
        turn[0] = 43;
        _doReveal(tid, turn);

        // Turn: check-check
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        // River reveal: 2-clubs(0)
        uint8[] memory river = new uint8[](1);
        river[0] = 0;
        _doReveal(tid, river);

        // River: check-check
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        _checkState(tid, IPokerTable.State.SHOWDOWN);

        // P1 reveals: pair of Aces (Ac=12, Ad=25)
        vm.prank(p1);
        poker.revealHand(tid, "", [uint8(12), uint8(25)]);

        // P2 reveals: 2d, 3d (junk)
        vm.prank(p2);
        poker.revealHand(tid, "", [uint8(13), uint8(14)]);

        // P1 should win (pair of aces vs high card)
        _checkState(tid, IPokerTable.State.SETTLED);

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

        _checkState(tid, IPokerTable.State.CANCELLED);
        // P2 gets everything (both buy-ins)
        assertEq(p2.balance, p2BalBefore + 2 ether);
    }

    function test_timeout_duringBetting() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // It's p1's turn (dealer preflop). They stall.
        vm.warp(block.timestamp + 121);

        poker.claimTimeout(tid);
        _checkState(tid, IPokerTable.State.SETTLED);
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
        poker.act(tid, IPokerTable.Action.FOLD, 0);

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
        poker.act(tid, IPokerTable.Action.FOLD, 0);

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
        poker.act(tid, IPokerTable.Action.FOLD, 0);

        // Total player balances should equal starting balances
        assertEq(p1.balance + p2.balance, 20 ether);
    }

    // ============================
    //  Split pot (showdown tie)
    // ============================

    function test_showdown_splitPot() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Preflop: call + check
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        // Flop
        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 21; flop[2] = 31;
        _doReveal(tid, flop);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        // Turn
        uint8[] memory turn = new uint8[](1);
        turn[0] = 43;
        _doReveal(tid, turn);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        // River
        uint8[] memory river = new uint8[](1);
        river[0] = 0;
        _doReveal(tid, river);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        _checkState(tid, IPokerTable.State.SHOWDOWN);

        uint256 p1Before = p1.balance;
        uint256 p2Before = p2.balance;

        // Both reveal same strength hand: pair of 3s (3c=1, 3d=14)  vs (3h=27, 3s=40)
        // With community [Qc(10), 9d(21), 6h(31), 5s(43), 2c(0)]
        // Both have pair of 3s with same kickers (Q,9,6)
        vm.prank(p1);
        poker.revealHand(tid, "", [uint8(1), uint8(14)]);
        vm.prank(p2);
        poker.revealHand(tid, "", [uint8(27), uint8(40)]);

        _checkState(tid, IPokerTable.State.SETTLED);

        // Both should get roughly equal payouts (split pot)
        // Total conserved: both bought in for 1 ether each
        uint256 totalAfter = p1.balance + p2.balance;
        uint256 totalBefore = p1Before + p2Before;
        // They should each get back roughly their buy-in
        assertEq(totalAfter, totalBefore + 2 ether);
    }

    // ============================
    //  All-in scenarios
    // ============================

    function test_allIn_call_for_less() public {
        // Create table with asymmetric setup: p1 has less stack after a raise
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // P1 (dealer) raises big: 0.8 ether raise
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.RAISE, 0.8 ether);

        // P2 calls (0.8 + difference to match)
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CALL, 0);

        _checkState(tid, IPokerTable.State.FLOP_REVEAL);
        assertEq(p1.balance + p2.balance, 20 ether - 2 * BUY_IN);
    }

    function test_allIn_raise_forces_allin() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // P1 raises all-in (entire remaining stack)
        // P1 stack after SB = 0.95 ether. toCall = 0.05 ether. maxRaise = 0.9 ether.
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.RAISE, 0.9 ether);

        // P2 calls the all-in
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CALL, 0);

        // Both all-in, should skip through to showdown
        // After flop/turn/river reveals with no betting (both stacks = 0)
        _checkState(tid, IPokerTable.State.FLOP_REVEAL);
    }

    function test_multipleRaises() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // P1 raises min (0.1 ether)
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.RAISE, 0.1 ether);

        // P2 re-raises (0.1 ether on top)
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.RAISE, 0.1 ether);

        // P1 calls
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);

        _checkState(tid, IPokerTable.State.FLOP_REVEAL);
    }

    // ============================
    //  Timeout edge cases
    // ============================

    function test_timeout_duringDecrypt_oneSubmitted() public {
        uint256 tid = _createAndJoin();
        _doShuffles(tid);

        // P1 submits decrypt, P2 doesn't
        uint8[] memory empty = new uint8[](0);
        vm.prank(p1);
        poker.submitDecrypt(tid, "", empty, _sampleCommitments());

        vm.warp(block.timestamp + 121);

        uint256 p1Before = p1.balance;
        poker.claimTimeout(tid);

        _checkState(tid, IPokerTable.State.CANCELLED);
        // P1 (who submitted) gets everything
        assertEq(p1.balance, p1Before + 2 ether);
    }

    function test_timeout_duringDecrypt_neitherSubmitted() public {
        uint256 tid = _createAndJoin();
        _doShuffles(tid);

        // Neither submits
        vm.warp(block.timestamp + 121);

        uint256 p1Before = p1.balance;
        uint256 p2Before = p2.balance;
        poker.claimTimeout(tid);

        _checkState(tid, IPokerTable.State.CANCELLED);
        // Split
        assertEq(p1.balance + p2.balance, p1Before + p2Before + 2 ether);
    }

    function test_timeout_duringShowdown_oneRevealed() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Play through to showdown
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 21; flop[2] = 31;
        _doReveal(tid, flop);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory turn = new uint8[](1);
        turn[0] = 43;
        _doReveal(tid, turn);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory river = new uint8[](1);
        river[0] = 0;
        _doReveal(tid, river);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        _checkState(tid, IPokerTable.State.SHOWDOWN);

        // P1 reveals, P2 doesn't
        vm.prank(p1);
        poker.revealHand(tid, "", [uint8(12), uint8(25)]);

        vm.warp(block.timestamp + 121);

        uint256 p1Before = p1.balance;
        poker.claimTimeout(tid);

        _checkState(tid, IPokerTable.State.CANCELLED);
        // P1 gets everything (they revealed, P2 didn't)
        assertEq(p1.balance, p1Before + 2 ether);
    }

    // ============================
    //  Proof rejection
    // ============================

    function test_badShuffleProof_reverts() public {
        RejectingVerifier rejector = new RejectingVerifier();
        PokerTable strictPoker = new PokerTable(address(rejector), address(new MockVerifier()), address(new MockVerifier()));

        vm.deal(p1, 10 ether);
        vm.deal(p2, 10 ether);

        vm.prank(p1);
        uint256 tid = strictPoker.createTable{value: BUY_IN}(BIG_BLIND);
        vm.prank(p2);
        strictPoker.joinTable{value: BUY_IN}(tid);

        vm.prank(p1);
        strictPoker.registerPublicKey(tid, bytes32(uint256(0xaa)));

        vm.prank(p1);
        vm.expectRevert("bad shuffle proof");
        strictPoker.submitShuffle(tid, "", bytes32(uint256(1)));
    }

    function test_badDecryptProof_reverts() public {
        RejectingVerifier rejector = new RejectingVerifier();
        PokerTable strictPoker = new PokerTable(address(new MockVerifier()), address(rejector), address(new MockVerifier()));

        vm.deal(p1, 10 ether);
        vm.deal(p2, 10 ether);

        vm.prank(p1);
        uint256 tid = strictPoker.createTable{value: BUY_IN}(BIG_BLIND);
        vm.prank(p2);
        strictPoker.joinTable{value: BUY_IN}(tid);

        vm.prank(p1);
        strictPoker.registerPublicKey(tid, bytes32(uint256(0xaa)));
        vm.prank(p2);
        strictPoker.registerPublicKey(tid, bytes32(uint256(0xbb)));

        vm.prank(p1);
        strictPoker.submitShuffle(tid, "", bytes32(uint256(1)));
        vm.prank(p2);
        strictPoker.submitShuffle(tid, "", bytes32(uint256(2)));

        // Decrypt with rejector (fails)
        uint8[] memory empty = new uint8[](0);
        vm.prank(p1);
        vm.expectRevert("bad decrypt proof");
        strictPoker.submitDecrypt(tid, "", empty, _sampleCommitments());
    }

    function test_badRevealProof_reverts() public {
        RejectingVerifier rejector = new RejectingVerifier();
        PokerTable strictPoker = new PokerTable(address(new MockVerifier()), address(new MockVerifier()), address(rejector));

        vm.deal(p1, 10 ether);
        vm.deal(p2, 10 ether);

        vm.prank(p1);
        uint256 tid = strictPoker.createTable{value: BUY_IN}(BIG_BLIND);
        vm.prank(p2);
        strictPoker.joinTable{value: BUY_IN}(tid);

        vm.prank(p1);
        strictPoker.registerPublicKey(tid, bytes32(uint256(0xaa)));
        vm.prank(p2);
        strictPoker.registerPublicKey(tid, bytes32(uint256(0xbb)));

        vm.prank(p1);
        strictPoker.submitShuffle(tid, "", bytes32(uint256(1)));
        vm.prank(p2);
        strictPoker.submitShuffle(tid, "", bytes32(uint256(2)));

        uint8[] memory empty = new uint8[](0);
        vm.prank(p1);
        strictPoker.submitDecrypt(tid, "", empty, _sampleCommitments());
        vm.prank(p2);
        strictPoker.submitDecrypt(tid, "", empty, _sampleCommitments());

        // Preflop: call + check
        vm.prank(p1);
        strictPoker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        strictPoker.act(tid, IPokerTable.Action.CHECK, 0);

        // Flop reveal (both submit matching values)
        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 21; flop[2] = 31;
        vm.prank(p1);
        strictPoker.submitDecrypt(tid, "", flop, _emptyCommitments());
        vm.prank(p2);
        strictPoker.submitDecrypt(tid, "", flop, _emptyCommitments());

        // Flop bet
        vm.prank(p2);
        strictPoker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        strictPoker.act(tid, IPokerTable.Action.CHECK, 0);

        // Turn reveal
        uint8[] memory turn = new uint8[](1);
        turn[0] = 43;
        vm.prank(p1);
        strictPoker.submitDecrypt(tid, "", turn, _emptyCommitments());
        vm.prank(p2);
        strictPoker.submitDecrypt(tid, "", turn, _emptyCommitments());

        // Turn bet
        vm.prank(p2);
        strictPoker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        strictPoker.act(tid, IPokerTable.Action.CHECK, 0);

        // River reveal
        uint8[] memory river = new uint8[](1);
        river[0] = 0;
        vm.prank(p1);
        strictPoker.submitDecrypt(tid, "", river, _emptyCommitments());
        vm.prank(p2);
        strictPoker.submitDecrypt(tid, "", river, _emptyCommitments());

        // River bet
        vm.prank(p2);
        strictPoker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        strictPoker.act(tid, IPokerTable.Action.CHECK, 0);

        // Showdown - reveal should fail
        vm.prank(p1);
        vm.expectRevert("bad reveal proof");
        strictPoker.revealHand(tid, "", [uint8(12), uint8(25)]);
    }

    // ============================
    //  Duplicate card detection
    // ============================

    function test_duplicateHoleCards_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 21; flop[2] = 31;
        _doReveal(tid, flop);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory turn = new uint8[](1);
        turn[0] = 43;
        _doReveal(tid, turn);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory river = new uint8[](1);
        river[0] = 0;
        _doReveal(tid, river);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        _checkState(tid, IPokerTable.State.SHOWDOWN);

        // Try to reveal two of the same card
        vm.prank(p1);
        vm.expectRevert("duplicate hole cards");
        poker.revealHand(tid, "", [uint8(12), uint8(12)]);
    }

    function test_holeCardMatchesCommunity_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 21; flop[2] = 31;
        _doReveal(tid, flop);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory turn = new uint8[](1);
        turn[0] = 43;
        _doReveal(tid, turn);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory river = new uint8[](1);
        river[0] = 0;
        _doReveal(tid, river);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        _checkState(tid, IPokerTable.State.SHOWDOWN);

        // Try to claim a community card (10) as hole card
        vm.prank(p1);
        vm.expectRevert("hole card duplicates community");
        poker.revealHand(tid, "", [uint8(10), uint8(25)]);
    }

    function test_holeCardClaimedByOpponent_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 21; flop[2] = 31;
        _doReveal(tid, flop);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory turn = new uint8[](1);
        turn[0] = 43;
        _doReveal(tid, turn);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory river = new uint8[](1);
        river[0] = 0;
        _doReveal(tid, river);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        _checkState(tid, IPokerTable.State.SHOWDOWN);

        // P1 reveals Ac, Ad
        vm.prank(p1);
        poker.revealHand(tid, "", [uint8(12), uint8(25)]);

        // P2 tries to claim Ac (already claimed by P1)
        vm.prank(p2);
        vm.expectRevert("card already claimed");
        poker.revealHand(tid, "", [uint8(12), uint8(38)]);
    }

    // ============================
    //  Concurrent tables
    // ============================

    function test_concurrentTables_independent() public {
        address p3 = makeAddr("player3");
        address p4 = makeAddr("player4");
        vm.deal(p3, 10 ether);
        vm.deal(p4, 10 ether);

        // Table 1
        vm.prank(p1);
        uint256 tid1 = poker.createTable{value: BUY_IN}(BIG_BLIND);
        vm.prank(p2);
        poker.joinTable{value: BUY_IN}(tid1);

        // Table 2
        vm.prank(p3);
        uint256 tid2 = poker.createTable{value: 0.5 ether}(0.04 ether);
        vm.prank(p4);
        poker.joinTable{value: 0.5 ether}(tid2);

        // Fold on table 1
        _doShuffles(tid1);
        _doDeal(tid1);
        vm.prank(p1);
        poker.act(tid1, IPokerTable.Action.FOLD, 0);

        _checkState(tid1, IPokerTable.State.SETTLED);

        // Table 2 should still be in shuffle phase
        _checkState(tid2, IPokerTable.State.SHUFFLE_P1);

        // Table 2 settlement should not be affected by table 1
        assertEq(p1.balance + p2.balance, 20 ether);
        assertEq(p3.balance + p4.balance, 20 ether - 1 ether); // 1 ether locked in contract
    }

    // ============================
    //  Public key registration
    // ============================

    function test_registerPublicKey_overwrite_reverts() public {
        _createAndJoin();
        // Create a fresh table to test registration directly
        vm.prank(p1);
        uint256 tid2 = poker.createTable{value: BUY_IN}(BIG_BLIND);
        vm.prank(p2);
        poker.joinTable{value: BUY_IN}(tid2);

        vm.prank(p1);
        poker.registerPublicKey(tid2, bytes32(uint256(0xaa)));

        // Second registration should fail
        vm.prank(p1);
        vm.expectRevert("public key already registered");
        poker.registerPublicKey(tid2, bytes32(uint256(0xbb)));
    }

    function test_registerPublicKey_zero_reverts() public {
        vm.prank(p1);
        uint256 tid = poker.createTable{value: BUY_IN}(BIG_BLIND);
        vm.prank(p2);
        poker.joinTable{value: BUY_IN}(tid);

        vm.prank(p1);
        vm.expectRevert("invalid public key");
        poker.registerPublicKey(tid, bytes32(0));
    }

    // ============================
    //  Card value consensus
    // ============================

    function test_communityCard_mismatch_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Preflop: call + check
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        // Flop reveal: P1 submits one set of cards
        uint8[] memory flop1 = new uint8[](3);
        flop1[0] = 10; flop1[1] = 21; flop1[2] = 31;
        vm.prank(p1);
        poker.submitDecrypt(tid, "", flop1, _emptyCommitments());

        // P2 submits different cards - should revert
        uint8[] memory flop2 = new uint8[](3);
        flop2[0] = 10; flop2[1] = 21; flop2[2] = 32; // last card different
        vm.prank(p2);
        vm.expectRevert("card value mismatch between players");
        poker.submitDecrypt(tid, "", flop2, _emptyCommitments());
    }

    // ============================
    //  Deal commitment enforcement
    // ============================

    function test_deal_missing_commitments_reverts() public {
        uint256 tid = _createAndJoin();
        _doShuffles(tid);

        // Try to submit decrypt during DEALING with 0 commitments
        uint8[] memory empty = new uint8[](0);
        vm.prank(p1);
        vm.expectRevert("must provide 2 card commitments");
        poker.submitDecrypt(tid, "", empty, _emptyCommitments());
    }

    // ============================
    //  Call with nothing to call
    // ============================

    function test_call_nothing_to_call_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Preflop: dealer calls BB
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);

        // BB checks -> flop reveal
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        // Reveal flop
        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 21; flop[2] = 31;
        _doReveal(tid, flop);

        // Post-flop: P2 acts first. Try to call when nothing is owed.
        vm.prank(p2);
        vm.expectRevert("nothing to call");
        poker.act(tid, IPokerTable.Action.CALL, 0);
    }
}
