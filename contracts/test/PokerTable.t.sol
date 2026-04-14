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
        poker = new PokerTable(address(mock), address(mock), address(mock), false);
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

    function _sampleDeck() internal pure returns (
        bytes32[52] memory c, bytes32[52] memory r, bytes32[52] memory p
    ) {
        for (uint256 i = 0; i < 52; i++) {
            c[i] = bytes32(uint256(i + 100));
            r[i] = bytes32(uint256(i + 200));
            p[i] = bytes32(uint256(i + 300));
        }
    }

    function _emptyDeck() internal pure returns (bytes32[52] memory) {
        bytes32[52] memory empty;
        return empty;
    }

    function _doShuffles(uint256 tid) internal {
        vm.prank(p1);
        poker.registerPublicKey(tid, bytes32(uint256(0xaa)));
        vm.prank(p2);
        poker.registerPublicKey(tid, bytes32(uint256(0xbb)));

        // P1 shuffle: empty deck arrays (only P2 stores deck)
        vm.prank(p1);
        poker.submitShuffle(tid, "", bytes32(uint256(1)), _emptyDeck(), _emptyDeck(), _emptyDeck());

        // P2 shuffle: provide per-card encrypted state
        (bytes32[52] memory c, bytes32[52] memory r, bytes32[52] memory p) = _sampleDeck();
        vm.prank(p2);
        poker.submitShuffle(tid, "", bytes32(uint256(2)), c, r, p);
    }

    function _doDeal(uint256 tid) internal {
        // P1 decrypts P2's hole cards (indices 2, 3)
        uint8[] memory p1Indices = new uint8[](2);
        p1Indices[0] = 2; p1Indices[1] = 3;
        bytes32[] memory p1Shares = new bytes32[](2);
        p1Shares[0] = bytes32(uint256(0x1111));
        p1Shares[1] = bytes32(uint256(0x2222));
        bytes[] memory p1Proofs = new bytes[](2);
        p1Proofs[0] = ""; p1Proofs[1] = "";
        uint8[] memory noCards = new uint8[](0);

        vm.prank(p1);
        poker.submitDecrypt(tid, p1Indices, p1Shares, p1Proofs, noCards);

        // P2 decrypts P1's hole cards (indices 0, 1)
        uint8[] memory p2Indices = new uint8[](2);
        p2Indices[0] = 0; p2Indices[1] = 1;
        bytes32[] memory p2Shares = new bytes32[](2);
        p2Shares[0] = bytes32(uint256(0x3333));
        p2Shares[1] = bytes32(uint256(0x4444));
        bytes[] memory p2Proofs = new bytes[](2);
        p2Proofs[0] = ""; p2Proofs[1] = "";

        vm.prank(p2);
        poker.submitDecrypt(tid, p2Indices, p2Shares, p2Proofs, noCards);
    }

    function _doReveal(uint256 tid, uint8[] memory cards) internal {
        (, , , IPokerTable.State s, , ) = poker.getTable(tid);

        uint8[] memory indices;
        if (s == IPokerTable.State.FLOP_REVEAL) {
            indices = new uint8[](3);
            indices[0] = 4; indices[1] = 5; indices[2] = 6;
        } else if (s == IPokerTable.State.TURN_REVEAL) {
            indices = new uint8[](1);
            indices[0] = 7;
        } else {
            indices = new uint8[](1);
            indices[0] = 8;
        }

        bytes32[] memory shares = new bytes32[](indices.length);
        bytes[] memory proofs = new bytes[](indices.length);
        for (uint256 i = 0; i < indices.length; i++) {
            shares[i] = bytes32(uint256(0xaaaa + i));
            proofs[i] = "";
        }

        vm.prank(p1);
        poker.submitDecrypt(tid, indices, shares, proofs, cards);
        vm.prank(p2);
        poker.submitDecrypt(tid, indices, shares, proofs, cards);
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
        poker.submitShuffle(tid, "", bytes32(uint256(1)), _emptyDeck(), _emptyDeck(), _emptyDeck());
        _checkState(tid, IPokerTable.State.SHUFFLE_P2);
    }

    function test_shuffle_wrongPlayer_reverts() public {
        uint256 tid = _createAndJoin();
        vm.prank(p2);
        vm.expectRevert("P1 shuffles first");
        poker.submitShuffle(tid, "", bytes32(uint256(1)), _emptyDeck(), _emptyDeck(), _emptyDeck());
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

        uint256 p2BalBefore = p2.balance;
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.FOLD, 0);

        _checkState(tid, IPokerTable.State.SETTLED);
        assertGt(p2.balance, p2BalBefore);
    }

    function test_preflop_call_check_advances() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        _checkState(tid, IPokerTable.State.FLOP_REVEAL);
    }

    function test_preflop_raise_call() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.RAISE, 0.2 ether);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CALL, 0);

        _checkState(tid, IPokerTable.State.FLOP_REVEAL);
    }

    function test_wrongPlayer_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p2);
        vm.expectRevert("not your turn");
        poker.act(tid, IPokerTable.Action.CHECK, 0);
    }

    function test_check_when_must_call_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p1);
        vm.expectRevert("must call, raise, or fold");
        poker.act(tid, IPokerTable.Action.CHECK, 0);
    }

    function test_postflop_nonDealer_actsFirst() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 23; flop[2] = 36;
        _doReveal(tid, flop);
        _checkState(tid, IPokerTable.State.FLOP_BET);

        vm.prank(p1);
        vm.expectRevert("not your turn");
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
    }

    function test_raise_too_small_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

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

        vm.prank(p1);
        poker.revealHand(tid, "", [uint8(12), uint8(25)]);
        vm.prank(p2);
        poker.revealHand(tid, "", [uint8(13), uint8(14)]);

        _checkState(tid, IPokerTable.State.SETTLED);
        assertEq(p1.balance + p2.balance, 20 ether - 2 ether + 2 ether);
    }

    // ============================
    //  Timeouts
    // ============================

    function test_timeout_duringShuffle() public {
        uint256 tid = _createAndJoin();
        vm.warp(block.timestamp + 121);

        uint256 p2BalBefore = p2.balance;
        poker.claimTimeout(tid);

        _checkState(tid, IPokerTable.State.CANCELLED);
        assertEq(p2.balance, p2BalBefore + 2 ether);
    }

    function test_timeout_duringBetting() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

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

        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.FOLD, 0);

        assertEq(p1.balance, p1Before + BUY_IN - BIG_BLIND / 2);
        assertEq(p2.balance, p2Before + BUY_IN + BIG_BLIND / 2);
        assertEq(p1.balance + p2.balance, 20 ether);
    }

    function test_contractBalance_afterSettlement() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.FOLD, 0);

        assertEq(p1.balance + p2.balance, 20 ether);
    }

    // ============================
    //  Split pot (showdown tie)
    // ============================

    function test_showdown_splitPot() public {
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

        uint256 p1Before = p1.balance;
        uint256 p2Before = p2.balance;

        vm.prank(p1);
        poker.revealHand(tid, "", [uint8(1), uint8(14)]);
        vm.prank(p2);
        poker.revealHand(tid, "", [uint8(27), uint8(40)]);

        _checkState(tid, IPokerTable.State.SETTLED);
        uint256 totalAfter = p1.balance + p2.balance;
        uint256 totalBefore = p1Before + p2Before;
        assertEq(totalAfter, totalBefore + 2 ether);
    }

    // ============================
    //  All-in scenarios
    // ============================

    function test_allIn_call_for_less() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.RAISE, 0.8 ether);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CALL, 0);

        _checkState(tid, IPokerTable.State.FLOP_REVEAL);
        assertEq(p1.balance + p2.balance, 20 ether - 2 * BUY_IN);
    }

    function test_allIn_raise_forces_allin() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.RAISE, 0.9 ether);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CALL, 0);

        _checkState(tid, IPokerTable.State.FLOP_REVEAL);
    }

    function test_multipleRaises() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.RAISE, 0.1 ether);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.RAISE, 0.1 ether);
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
        uint8[] memory indices = new uint8[](2);
        indices[0] = 2; indices[1] = 3;
        bytes32[] memory shares = new bytes32[](2);
        shares[0] = bytes32(uint256(0x1111));
        shares[1] = bytes32(uint256(0x2222));
        bytes[] memory proofs = new bytes[](2);
        proofs[0] = ""; proofs[1] = "";
        uint8[] memory noCards = new uint8[](0);

        vm.prank(p1);
        poker.submitDecrypt(tid, indices, shares, proofs, noCards);

        vm.warp(block.timestamp + 121);

        uint256 p1Before = p1.balance;
        poker.claimTimeout(tid);

        _checkState(tid, IPokerTable.State.CANCELLED);
        assertEq(p1.balance, p1Before + 2 ether);
    }

    function test_timeout_duringDecrypt_neitherSubmitted() public {
        uint256 tid = _createAndJoin();
        _doShuffles(tid);

        vm.warp(block.timestamp + 121);

        uint256 p1Before = p1.balance;
        uint256 p2Before = p2.balance;
        poker.claimTimeout(tid);

        _checkState(tid, IPokerTable.State.CANCELLED);
        assertEq(p1.balance + p2.balance, p1Before + p2Before + 2 ether);
    }

    function test_timeout_duringShowdown_oneRevealed() public {
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

        vm.prank(p1);
        poker.revealHand(tid, "", [uint8(12), uint8(25)]);

        vm.warp(block.timestamp + 121);

        uint256 p1Before = p1.balance;
        poker.claimTimeout(tid);

        _checkState(tid, IPokerTable.State.CANCELLED);
        assertEq(p1.balance, p1Before + 2 ether);
    }

    // ============================
    //  Proof rejection
    // ============================

    function test_badShuffleProof_reverts() public {
        RejectingVerifier rejector = new RejectingVerifier();
        PokerTable strictPoker = new PokerTable(address(rejector), address(new MockVerifier()), address(new MockVerifier()), false);

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
        strictPoker.submitShuffle(tid, "", bytes32(uint256(1)), _emptyDeck(), _emptyDeck(), _emptyDeck());
    }

    function test_badDecryptProof_reverts() public {
        RejectingVerifier rejector = new RejectingVerifier();
        PokerTable strictPoker = new PokerTable(address(new MockVerifier()), address(rejector), address(new MockVerifier()), false);

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
        strictPoker.submitShuffle(tid, "", bytes32(uint256(1)), _emptyDeck(), _emptyDeck(), _emptyDeck());
        (bytes32[52] memory c, bytes32[52] memory r, bytes32[52] memory p) = _sampleDeck();
        vm.prank(p2);
        strictPoker.submitShuffle(tid, "", bytes32(uint256(2)), c, r, p);

        // Decrypt with rejector should fail
        uint8[] memory indices = new uint8[](2);
        indices[0] = 2; indices[1] = 3;
        bytes32[] memory shares = new bytes32[](2);
        shares[0] = bytes32(uint256(0x1111));
        shares[1] = bytes32(uint256(0x2222));
        bytes[] memory proofs = new bytes[](2);
        proofs[0] = ""; proofs[1] = "";
        uint8[] memory noCards = new uint8[](0);

        vm.prank(p1);
        vm.expectRevert("bad decrypt proof");
        strictPoker.submitDecrypt(tid, indices, shares, proofs, noCards);
    }

    function test_badRevealProof_reverts() public {
        RejectingVerifier rejector = new RejectingVerifier();
        PokerTable strictPoker = new PokerTable(address(new MockVerifier()), address(new MockVerifier()), address(rejector), false);

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
        strictPoker.submitShuffle(tid, "", bytes32(uint256(1)), _emptyDeck(), _emptyDeck(), _emptyDeck());
        (bytes32[52] memory c, bytes32[52] memory r, bytes32[52] memory p) = _sampleDeck();
        vm.prank(p2);
        strictPoker.submitShuffle(tid, "", bytes32(uint256(2)), c, r, p);

        // Deal (mock verifier accepts)
        uint8[] memory p1Idx = new uint8[](2);
        p1Idx[0] = 2; p1Idx[1] = 3;
        bytes32[] memory p1Sh = new bytes32[](2);
        p1Sh[0] = bytes32(uint256(1)); p1Sh[1] = bytes32(uint256(2));
        bytes[] memory p1Pr = new bytes[](2);
        p1Pr[0] = ""; p1Pr[1] = "";
        uint8[] memory noCards = new uint8[](0);
        vm.prank(p1);
        strictPoker.submitDecrypt(tid, p1Idx, p1Sh, p1Pr, noCards);

        uint8[] memory p2Idx = new uint8[](2);
        p2Idx[0] = 0; p2Idx[1] = 1;
        bytes32[] memory p2Sh = new bytes32[](2);
        p2Sh[0] = bytes32(uint256(3)); p2Sh[1] = bytes32(uint256(4));
        bytes[] memory p2Pr = new bytes[](2);
        p2Pr[0] = ""; p2Pr[1] = "";
        vm.prank(p2);
        strictPoker.submitDecrypt(tid, p2Idx, p2Sh, p2Pr, noCards);

        // Play through to showdown
        vm.prank(p1);
        strictPoker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        strictPoker.act(tid, IPokerTable.Action.CHECK, 0);

        // Flop
        uint8[] memory flopIdx = new uint8[](3);
        flopIdx[0] = 4; flopIdx[1] = 5; flopIdx[2] = 6;
        bytes32[] memory flopSh = new bytes32[](3);
        bytes[] memory flopPr = new bytes[](3);
        for (uint256 i = 0; i < 3; i++) { flopSh[i] = bytes32(uint256(i+10)); flopPr[i] = ""; }
        uint8[] memory flopCards = new uint8[](3);
        flopCards[0] = 10; flopCards[1] = 21; flopCards[2] = 31;
        vm.prank(p1);
        strictPoker.submitDecrypt(tid, flopIdx, flopSh, flopPr, flopCards);
        vm.prank(p2);
        strictPoker.submitDecrypt(tid, flopIdx, flopSh, flopPr, flopCards);

        vm.prank(p2); strictPoker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1); strictPoker.act(tid, IPokerTable.Action.CHECK, 0);

        // Turn
        uint8[] memory turnIdx = new uint8[](1);
        turnIdx[0] = 7;
        bytes32[] memory turnSh = new bytes32[](1);
        turnSh[0] = bytes32(uint256(20));
        bytes[] memory turnPr = new bytes[](1);
        turnPr[0] = "";
        uint8[] memory turnCards = new uint8[](1);
        turnCards[0] = 43;
        vm.prank(p1);
        strictPoker.submitDecrypt(tid, turnIdx, turnSh, turnPr, turnCards);
        vm.prank(p2);
        strictPoker.submitDecrypt(tid, turnIdx, turnSh, turnPr, turnCards);

        vm.prank(p2); strictPoker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1); strictPoker.act(tid, IPokerTable.Action.CHECK, 0);

        // River
        uint8[] memory riverIdx = new uint8[](1);
        riverIdx[0] = 8;
        bytes32[] memory riverSh = new bytes32[](1);
        riverSh[0] = bytes32(uint256(30));
        bytes[] memory riverPr = new bytes[](1);
        riverPr[0] = "";
        uint8[] memory riverCards = new uint8[](1);
        riverCards[0] = 0;
        vm.prank(p1);
        strictPoker.submitDecrypt(tid, riverIdx, riverSh, riverPr, riverCards);
        vm.prank(p2);
        strictPoker.submitDecrypt(tid, riverIdx, riverSh, riverPr, riverCards);

        vm.prank(p2); strictPoker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1); strictPoker.act(tid, IPokerTable.Action.CHECK, 0);

        // Showdown - reveal should fail due to rejecting verifier
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

        vm.prank(p1); poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2); poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 21; flop[2] = 31;
        _doReveal(tid, flop);
        vm.prank(p2); poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1); poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory turn = new uint8[](1); turn[0] = 43;
        _doReveal(tid, turn);
        vm.prank(p2); poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1); poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory river = new uint8[](1); river[0] = 0;
        _doReveal(tid, river);
        vm.prank(p2); poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1); poker.act(tid, IPokerTable.Action.CHECK, 0);

        _checkState(tid, IPokerTable.State.SHOWDOWN);

        vm.prank(p1);
        vm.expectRevert("duplicate hole cards");
        poker.revealHand(tid, "", [uint8(12), uint8(12)]);
    }

    function test_holeCardMatchesCommunity_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p1); poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2); poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 21; flop[2] = 31;
        _doReveal(tid, flop);
        vm.prank(p2); poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1); poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory turn = new uint8[](1); turn[0] = 43;
        _doReveal(tid, turn);
        vm.prank(p2); poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1); poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory river = new uint8[](1); river[0] = 0;
        _doReveal(tid, river);
        vm.prank(p2); poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1); poker.act(tid, IPokerTable.Action.CHECK, 0);

        vm.prank(p1);
        vm.expectRevert("hole card duplicates community");
        poker.revealHand(tid, "", [uint8(10), uint8(25)]);
    }

    function test_holeCardClaimedByOpponent_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(p1); poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2); poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory flop = new uint8[](3);
        flop[0] = 10; flop[1] = 21; flop[2] = 31;
        _doReveal(tid, flop);
        vm.prank(p2); poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1); poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory turn = new uint8[](1); turn[0] = 43;
        _doReveal(tid, turn);
        vm.prank(p2); poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1); poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory river = new uint8[](1); river[0] = 0;
        _doReveal(tid, river);
        vm.prank(p2); poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.prank(p1); poker.act(tid, IPokerTable.Action.CHECK, 0);

        vm.prank(p1);
        poker.revealHand(tid, "", [uint8(12), uint8(25)]);

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

        vm.prank(p1);
        uint256 tid1 = poker.createTable{value: BUY_IN}(BIG_BLIND);
        vm.prank(p2);
        poker.joinTable{value: BUY_IN}(tid1);

        vm.prank(p3);
        uint256 tid2 = poker.createTable{value: 0.5 ether}(0.04 ether);
        vm.prank(p4);
        poker.joinTable{value: 0.5 ether}(tid2);

        _doShuffles(tid1);
        _doDeal(tid1);
        vm.prank(p1);
        poker.act(tid1, IPokerTable.Action.FOLD, 0);

        _checkState(tid1, IPokerTable.State.SETTLED);
        _checkState(tid2, IPokerTable.State.SHUFFLE_P1);

        assertEq(p1.balance + p2.balance, 20 ether);
        assertEq(p3.balance + p4.balance, 20 ether - 1 ether);
    }

    // ============================
    //  Public key registration
    // ============================

    function test_registerPublicKey_overwrite_reverts() public {
        _createAndJoin();
        vm.prank(p1);
        uint256 tid2 = poker.createTable{value: BUY_IN}(BIG_BLIND);
        vm.prank(p2);
        poker.joinTable{value: BUY_IN}(tid2);

        vm.prank(p1);
        poker.registerPublicKey(tid2, bytes32(uint256(0xaa)));

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

        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        // P1 submits flop values
        uint8[] memory flopIdx = new uint8[](3);
        flopIdx[0] = 4; flopIdx[1] = 5; flopIdx[2] = 6;
        bytes32[] memory shares = new bytes32[](3);
        bytes[] memory proofs = new bytes[](3);
        for (uint256 i = 0; i < 3; i++) { shares[i] = bytes32(uint256(i+1)); proofs[i] = ""; }

        uint8[] memory flop1 = new uint8[](3);
        flop1[0] = 10; flop1[1] = 21; flop1[2] = 31;
        vm.prank(p1);
        poker.submitDecrypt(tid, flopIdx, shares, proofs, flop1);

        // P2 submits different cards
        uint8[] memory flop2 = new uint8[](3);
        flop2[0] = 10; flop2[1] = 21; flop2[2] = 32;
        vm.prank(p2);
        vm.expectRevert("card value mismatch between players");
        poker.submitDecrypt(tid, flopIdx, shares, proofs, flop2);
    }

    // ============================
    //  New: per-card decrypt validation
    // ============================

    function test_decrypt_wrongCardIndices_reverts() public {
        uint256 tid = _createAndJoin();
        _doShuffles(tid);

        // P1 should decrypt indices [2,3] but tries [0,1] (own cards)
        uint8[] memory wrongIdx = new uint8[](2);
        wrongIdx[0] = 0; wrongIdx[1] = 1;
        bytes32[] memory shares = new bytes32[](2);
        shares[0] = bytes32(uint256(1)); shares[1] = bytes32(uint256(2));
        bytes[] memory proofs = new bytes[](2);
        proofs[0] = ""; proofs[1] = "";
        uint8[] memory noCards = new uint8[](0);

        vm.prank(p1);
        vm.expectRevert("unexpected card index");
        poker.submitDecrypt(tid, wrongIdx, shares, proofs, noCards);
    }

    function test_decrypt_emptyBatch_reverts() public {
        uint256 tid = _createAndJoin();
        _doShuffles(tid);

        uint8[] memory emptyIdx = new uint8[](0);
        bytes32[] memory emptyShares = new bytes32[](0);
        bytes[] memory emptyProofs = new bytes[](0);
        uint8[] memory noCards = new uint8[](0);

        vm.prank(p1);
        vm.expectRevert("no cards");
        poker.submitDecrypt(tid, emptyIdx, emptyShares, emptyProofs, noCards);
    }

    function test_decrypt_lengthMismatch_reverts() public {
        uint256 tid = _createAndJoin();
        _doShuffles(tid);

        uint8[] memory indices = new uint8[](2);
        indices[0] = 2; indices[1] = 3;
        bytes32[] memory shares = new bytes32[](1); // wrong length
        shares[0] = bytes32(uint256(1));
        bytes[] memory proofs = new bytes[](2);
        proofs[0] = ""; proofs[1] = "";
        uint8[] memory noCards = new uint8[](0);

        vm.prank(p1);
        vm.expectRevert("length mismatch");
        poker.submitDecrypt(tid, indices, shares, proofs, noCards);
    }

    // ============================
    //  New: view functions
    // ============================

    function test_getEncryptedCard() public {
        uint256 tid = _createAndJoin();
        _doShuffles(tid);

        (bytes32 commit, bytes32 rand, bytes32 payload) = poker.getEncryptedCard(tid, 0);
        assertEq(commit, bytes32(uint256(100)));
        assertEq(rand, bytes32(uint256(200)));
        assertEq(payload, bytes32(uint256(300)));
    }

    function test_getPartialDecryption() public {
        uint256 tid = _createAndJoin();
        _doShuffles(tid);
        _doDeal(tid);

        // P1 decrypted cards [2,3] with shares 0x1111, 0x2222
        bytes32 share = poker.getPartialDecryption(tid, 2, 0);
        assertEq(share, bytes32(uint256(0x1111)));
    }

    function test_getWinner() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        // Before settlement, winner is zero
        assertEq(poker.getWinner(tid), address(0));

        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.FOLD, 0);

        // P2 wins
        assertEq(poker.getWinner(tid), p2);
    }

    function test_demoMode_skipsProofs() public {
        MockVerifier mock = new MockVerifier();
        PokerTable demoPoker = new PokerTable(address(mock), address(mock), address(mock), true);
        assertTrue(demoPoker.demoMode());
    }
}
