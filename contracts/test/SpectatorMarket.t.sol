// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/PokerTable.sol";
import "../src/SpectatorMarket.sol";
import "../src/interfaces/IPokerTable.sol";
import "../src/mocks/MockVerifier.sol";

contract SpectatorMarketTest is Test {
    PokerTable poker;
    SpectatorMarket market;

    address p1 = makeAddr("player1");
    address p2 = makeAddr("player2");
    address s1 = makeAddr("spectator1");
    address s2 = makeAddr("spectator2");
    address s3 = makeAddr("spectator3");

    uint256 constant BUY_IN = 1 ether;
    uint256 constant BIG_BLIND = 0.1 ether;

    function setUp() public {
        MockVerifier mock = new MockVerifier();
        poker = new PokerTable(address(mock), address(mock), address(mock), false);
        market = new SpectatorMarket(address(poker));

        vm.deal(p1, 10 ether);
        vm.deal(p2, 10 ether);
        vm.deal(s1, 10 ether);
        vm.deal(s2, 10 ether);
        vm.deal(s3, 10 ether);
    }

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

    function _registerKeys(uint256 tid) internal {
        vm.prank(p1);
        poker.registerPublicKey(tid, bytes32(uint256(0xaa)));
        vm.prank(p2);
        poker.registerPublicKey(tid, bytes32(uint256(0xbb)));
    }

    function _doShuffles(uint256 tid) internal {
        _registerKeys(tid);

        vm.prank(p1);
        poker.submitShuffle(tid, "", bytes32(uint256(1)), _emptyDeck(), _emptyDeck(), _emptyDeck());

        (bytes32[52] memory c, bytes32[52] memory r, bytes32[52] memory p) = _sampleDeck();
        vm.prank(p2);
        poker.submitShuffle(tid, "", bytes32(uint256(2)), c, r, p);
    }

    function _doDeal(uint256 tid) internal {
        uint8[] memory p1Indices = new uint8[](2);
        p1Indices[0] = 2;
        p1Indices[1] = 3;
        bytes32[] memory p1Shares = new bytes32[](2);
        p1Shares[0] = bytes32(uint256(0x1111));
        p1Shares[1] = bytes32(uint256(0x2222));
        bytes[] memory p1Proofs = new bytes[](2);
        p1Proofs[0] = "";
        p1Proofs[1] = "";
        uint8[] memory noCards = new uint8[](0);
        vm.prank(p1);
        poker.submitDecrypt(tid, p1Indices, p1Shares, p1Proofs, noCards);

        uint8[] memory p2Indices = new uint8[](2);
        p2Indices[0] = 0;
        p2Indices[1] = 1;
        bytes32[] memory p2Shares = new bytes32[](2);
        p2Shares[0] = bytes32(uint256(0x3333));
        p2Shares[1] = bytes32(uint256(0x4444));
        bytes[] memory p2Proofs = new bytes[](2);
        p2Proofs[0] = "";
        p2Proofs[1] = "";
        vm.prank(p2);
        poker.submitDecrypt(tid, p2Indices, p2Shares, p2Proofs, noCards);
    }

    function _doReveal(uint256 tid, uint8[] memory cards) internal {
        (, , , IPokerTable.State s, , ) = poker.getTable(tid);

        uint8[] memory indices;
        if (s == IPokerTable.State.FLOP_REVEAL) {
            indices = new uint8[](3);
            indices[0] = 4;
            indices[1] = 5;
            indices[2] = 6;
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

    function _settlePlayer1WinByFold(uint256 tid) internal {
        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.FOLD, 0);
    }

    function _settleSplitPot(uint256 tid) internal {
        _toPreflop(tid);

        vm.prank(p1);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.prank(p2);
        poker.act(tid, IPokerTable.Action.CHECK, 0);

        uint8[] memory flop = new uint8[](3);
        flop[0] = 10;
        flop[1] = 21;
        flop[2] = 31;
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

        vm.prank(p1);
        poker.revealHand(tid, "", [uint8(1), uint8(14)]);
        vm.prank(p2);
        poker.revealHand(tid, "", [uint8(27), uint8(40)]);
    }

    function _place(address bettor, uint256 tid, address predictedWinner, uint256 amount) internal {
        vm.prank(bettor);
        market.placeWager{value: amount}(tid, predictedWinner);
    }

    function test_placeWager_inShuffleP1() public {
        uint256 tid = _createAndJoin();
        _place(s1, tid, p1, 0.2 ether);

        (, uint256 totalOnPlayer0, uint256 totalOnPlayer1, bool resolved, , ) = market.getMarket(tid);
        assertEq(totalOnPlayer0, 0.2 ether);
        assertEq(totalOnPlayer1, 0);
        assertFalse(resolved);
    }

    function test_placeWager_inShuffleP2() public {
        uint256 tid = _createAndJoin();
        _registerKeys(tid);
        vm.prank(p1);
        poker.submitShuffle(tid, "", bytes32(uint256(1)), _emptyDeck(), _emptyDeck(), _emptyDeck());

        _place(s1, tid, p2, 0.15 ether);

        (, uint256 totalOnPlayer0, uint256 totalOnPlayer1, , , ) = market.getMarket(tid);
        assertEq(totalOnPlayer0, 0);
        assertEq(totalOnPlayer1, 0.15 ether);
    }

    function test_placeWager_inDealing() public {
        uint256 tid = _createAndJoin();
        _doShuffles(tid);

        _place(s1, tid, p1, 0.1 ether);

        (, uint256 totalOnPlayer0, , , , ) = market.getMarket(tid);
        assertEq(totalOnPlayer0, 0.1 ether);
    }

    function test_placeWager_waiting_reverts() public {
        vm.prank(p1);
        uint256 tid = poker.createTable{value: BUY_IN}(BIG_BLIND);

        vm.prank(s1);
        vm.expectRevert("table not full");
        market.placeWager{value: 0.1 ether}(tid, p1);
    }

    function test_placeWager_zero_reverts() public {
        uint256 tid = _createAndJoin();

        vm.prank(s1);
        vm.expectRevert("must send wager");
        market.placeWager{value: 0}(tid, p1);
    }

    function test_placeWager_invalidWinner_reverts() public {
        uint256 tid = _createAndJoin();

        vm.prank(s1);
        vm.expectRevert("invalid predicted winner");
        market.placeWager{value: 0.1 ether}(tid, s2);
    }

    function test_placeWager_player_reverts() public {
        uint256 tid = _createAndJoin();

        vm.prank(p1);
        vm.expectRevert("players cannot wager");
        market.placeWager{value: 0.1 ether}(tid, p1);
    }

    function test_placeWager_revertsAfterPreflop() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);

        vm.prank(s1);
        vm.expectRevert("wagering closed");
        market.placeWager{value: 0.1 ether}(tid, p1);
    }

    function test_placeWager_revertsInSettledAndCancelled() public {
        uint256 settledTid = _createAndJoin();
        _toPreflop(settledTid);
        _settlePlayer1WinByFold(settledTid);

        vm.prank(s1);
        vm.expectRevert("wagering closed");
        market.placeWager{value: 0.1 ether}(settledTid, p2);

        uint256 cancelledTid = _createAndJoin();
        vm.warp(block.timestamp + 121);
        poker.claimTimeout(cancelledTid);

        vm.prank(s1);
        vm.expectRevert("wagering closed");
        market.placeWager{value: 0.1 ether}(cancelledTid, p1);
    }

    function test_repeatWager_sameSideAccumulates() public {
        uint256 tid = _createAndJoin();
        _place(s1, tid, p1, 0.1 ether);
        _place(s1, tid, p1, 0.3 ether);

        (address predictedWinner, uint256 amount, bool claimed) = market.getWager(tid, s1);
        assertEq(predictedWinner, p1);
        assertEq(amount, 0.4 ether);
        assertFalse(claimed);
    }

    function test_repeatWager_oppositeSide_reverts() public {
        uint256 tid = _createAndJoin();
        _place(s1, tid, p1, 0.1 ether);

        vm.prank(s1);
        vm.expectRevert("cannot switch sides");
        market.placeWager{value: 0.1 ether}(tid, p2);
    }

    function test_resolveAndClaim_parimutuelPayouts() public {
        uint256 tid = _createAndJoin();
        _place(s1, tid, p1, 1 ether);
        _place(s2, tid, p1, 2 ether);
        _place(s3, tid, p2, 1 ether);

        _toPreflop(tid);
        _settlePlayer1WinByFold(tid);

        market.resolveWagers(tid);

        uint256 totalPool = 4 ether;
        uint256 winningPool = 3 ether;
        uint256 s1Stake = 1 ether;
        uint256 s2Stake = 2 ether;
        uint256 s1Expected = (s1Stake * totalPool) / winningPool;
        uint256 s2Quoted = (s2Stake * totalPool) / winningPool;
        uint256 s2FinalPayout = totalPool - s1Expected;

        assertEq(market.quoteClaim(tid, s1), s1Expected);
        assertEq(market.quoteClaim(tid, s2), s2Quoted);
        assertEq(market.quoteClaim(tid, s3), 0);

        uint256 s1Before = s1.balance;
        uint256 s2Before = s2.balance;
        uint256 s3Before = s3.balance;

        vm.prank(s1);
        market.claimWinnings(tid);
        vm.prank(s3);
        market.claimWinnings(tid);
        vm.prank(s2);
        market.claimWinnings(tid);

        assertEq(s1.balance, s1Before + s1Expected);
        assertEq(s2.balance, s2Before + s2FinalPayout);
        assertEq(s3.balance, s3Before);
        assertEq(address(market).balance, 0);
    }

    function test_resolveRefundsOnCancelledHand() public {
        uint256 tid = _createAndJoin();
        _place(s1, tid, p1, 0.2 ether);
        _place(s2, tid, p2, 0.3 ether);

        vm.warp(block.timestamp + 121);
        poker.claimTimeout(tid);

        market.resolveWagers(tid);

        (, , , bool resolved, bool refundsOnly, address winner) = market.getMarket(tid);
        assertTrue(resolved);
        assertTrue(refundsOnly);
        assertEq(winner, address(0));

        uint256 s1Before = s1.balance;
        uint256 s2Before = s2.balance;

        vm.prank(s1);
        market.claimWinnings(tid);
        vm.prank(s2);
        market.claimWinnings(tid);

        assertEq(s1.balance, s1Before + 0.2 ether);
        assertEq(s2.balance, s2Before + 0.3 ether);
        assertEq(address(market).balance, 0);
    }

    function test_resolveRefundsOnSplitPot() public {
        uint256 tid = _createAndJoin();
        _place(s1, tid, p1, 0.4 ether);
        _place(s2, tid, p2, 0.6 ether);

        _settleSplitPot(tid);
        market.resolveWagers(tid);

        assertEq(market.quoteClaim(tid, s1), 0.4 ether);
        assertEq(market.quoteClaim(tid, s2), 0.6 ether);
    }

    function test_claimBeforeResolution_reverts() public {
        uint256 tid = _createAndJoin();
        _place(s1, tid, p1, 0.1 ether);

        vm.prank(s1);
        vm.expectRevert("market not resolved");
        market.claimWinnings(tid);
    }

    function test_doubleClaim_reverts() public {
        uint256 tid = _createAndJoin();
        _place(s1, tid, p1, 0.1 ether);

        _toPreflop(tid);
        _settlePlayer1WinByFold(tid);
        market.resolveWagers(tid);

        vm.prank(s1);
        market.claimWinnings(tid);

        vm.prank(s1);
        vm.expectRevert("already claimed");
        market.claimWinnings(tid);
    }

    function test_doubleResolve_reverts() public {
        uint256 tid = _createAndJoin();
        _place(s1, tid, p1, 0.1 ether);

        _toPreflop(tid);
        _settlePlayer1WinByFold(tid);
        market.resolveWagers(tid);

        vm.expectRevert("market already resolved");
        market.resolveWagers(tid);
    }

    function test_resolveBeforeFinal_reverts() public {
        uint256 tid = _createAndJoin();
        _place(s1, tid, p1, 0.1 ether);

        vm.expectRevert("hand not final");
        market.resolveWagers(tid);
    }

    function test_claimWithoutWager_reverts() public {
        uint256 tid = _createAndJoin();
        _toPreflop(tid);
        _settlePlayer1WinByFold(tid);
        market.resolveWagers(tid);

        vm.prank(s1);
        vm.expectRevert("no wager");
        market.claimWinnings(tid);
    }

    function test_reentrancy_blocked() public {
        uint256 tid = _createAndJoin();
        _place(s1, tid, p1, 1 ether);

        ReentrantClaimer attacker = new ReentrantClaimer(market, tid);
        vm.deal(address(attacker), 1 ether);
        attacker.place(p1);

        _toPreflop(tid);
        _settlePlayer1WinByFold(tid);
        market.resolveWagers(tid);

        // With the nonReentrant guard, the re-enter call inside receive()
        // reverts with "reentrant". The outer claim then reverts because the
        // low-level call returns false and "transfer failed" triggers.
        vm.expectRevert("transfer failed");
        attacker.triggerClaim();

        // Book-keeping: attacker.claimed is NOT set (whole tx reverted).
        (, , bool claimed) = market.getWager(tid, address(attacker));
        assertFalse(claimed, "wager should not be marked claimed after revert");
    }
}

contract ReentrantClaimer {
    SpectatorMarket public market;
    uint256 public tid;

    constructor(SpectatorMarket m, uint256 t) {
        market = m;
        tid = t;
    }

    function place(address predictedWinner) external {
        market.placeWager{value: address(this).balance}(tid, predictedWinner);
    }

    function triggerClaim() external {
        market.claimWinnings(tid);
    }

    receive() external payable {
        // Attempt re-entry. If the guard works this reverts with "reentrant",
        // which bubbles up as a failed transfer in the parent claim.
        market.claimWinnings(tid);
    }
}
