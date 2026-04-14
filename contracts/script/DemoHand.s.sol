// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/PokerTable.sol";
import "../src/interfaces/IPokerTable.sol";
import "../src/mocks/MockVerifier.sol";

/// @title DemoHand - Plays a complete poker hand for demonstration
/// @notice Run with: forge script script/DemoHand.s.sol --fork-url http://localhost:8545 --broadcast
contract DemoHand is Script {
    PokerTable poker;
    address p1;
    address p2;
    uint256 p1Key;
    uint256 p2Key;

    function run() external {
        // Use Anvil's default accounts
        p1Key = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        p2Key = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        p1 = vm.addr(p1Key);
        p2 = vm.addr(p2Key);

        console.log("=== NoirLimit Demo Hand ===");
        console.log("Player 1:", p1);
        console.log("Player 2:", p2);
        console.log("");

        // Deploy
        vm.startBroadcast(p1Key);
        MockVerifier mock = new MockVerifier();
        poker = new PokerTable(address(mock), address(mock), address(mock), true);
        console.log("PokerTable deployed:", address(poker));
        console.log("Demo mode: ON (proofs skipped)");
        console.log("");

        // Create table
        uint256 tid = poker.createTable{value: 1 ether}(0.1 ether);
        console.log("[1] Table created (buy-in: 1 ETH, big blind: 0.1 ETH)");
        vm.stopBroadcast();

        // Join table
        vm.startBroadcast(p2Key);
        poker.joinTable{value: 1 ether}(tid);
        console.log("[2] Player 2 joined. Blinds posted (SB: 0.05, BB: 0.1)");
        vm.stopBroadcast();

        // Register public keys
        vm.startBroadcast(p1Key);
        poker.registerPublicKey(tid, bytes32(uint256(0xaa)));
        vm.stopBroadcast();
        vm.startBroadcast(p2Key);
        poker.registerPublicKey(tid, bytes32(uint256(0xbb)));
        vm.stopBroadcast();
        console.log("[3] Public keys registered");

        // Shuffle phase
        bytes32[52] memory emptyDeck;

        vm.startBroadcast(p1Key);
        poker.submitShuffle(tid, "", bytes32(uint256(1)), emptyDeck, emptyDeck, emptyDeck);
        vm.stopBroadcast();
        console.log("[4] Player 1 shuffled deck");

        // P2 shuffle with deck data
        bytes32[52] memory commitments;
        bytes32[52] memory randomizers;
        bytes32[52] memory payloads;
        for (uint256 i = 0; i < 52; i++) {
            commitments[i] = bytes32(uint256(i + 100));
            randomizers[i] = bytes32(uint256(i + 200));
            payloads[i] = bytes32(uint256(i + 300));
        }
        vm.startBroadcast(p2Key);
        poker.submitShuffle(tid, "", bytes32(uint256(2)), commitments, randomizers, payloads);
        vm.stopBroadcast();
        console.log("[5] Player 2 shuffled deck (encrypted cards stored on-chain)");

        // Deal phase
        _deal(tid);
        console.log("[6] Hole cards dealt (partial decryption shares exchanged)");

        // Pre-flop: P1 calls, P2 checks
        vm.startBroadcast(p1Key);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.stopBroadcast();
        console.log("[7] Player 1 calls (0.05 ETH to match BB)");

        vm.startBroadcast(p2Key);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.stopBroadcast();
        console.log("[8] Player 2 checks. Pot: 0.2 ETH");

        // Flop: Qc(10), 9d(21), 6h(31)
        _revealCommunity(tid, _makeCards3(10, 21, 31));
        console.log("[9] Flop revealed: Qc, 9d, 6h");

        // Flop bet: P2 bets, P1 calls
        vm.startBroadcast(p2Key);
        poker.act(tid, IPokerTable.Action.RAISE, 0.1 ether);
        vm.stopBroadcast();
        console.log("[10] Player 2 bets 0.1 ETH");

        vm.startBroadcast(p1Key);
        poker.act(tid, IPokerTable.Action.CALL, 0);
        vm.stopBroadcast();
        console.log("[11] Player 1 calls. Pot: 0.4 ETH");

        // Turn: 5s(43)
        _revealCommunity(tid, _makeCards1(43));
        console.log("[12] Turn revealed: 5s");

        // Turn bet: check-check
        vm.startBroadcast(p2Key);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.stopBroadcast();
        vm.startBroadcast(p1Key);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.stopBroadcast();
        console.log("[13] Both check. Pot: 0.4 ETH");

        // River: 2c(0)
        _revealCommunity(tid, _makeCards1(0));
        console.log("[14] River revealed: 2c");

        // River bet: check-check
        vm.startBroadcast(p2Key);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.stopBroadcast();
        vm.startBroadcast(p1Key);
        poker.act(tid, IPokerTable.Action.CHECK, 0);
        vm.stopBroadcast();
        console.log("[15] Both check. Showdown!");

        // Showdown: P1 has Ac(12) Ad(25) = pair of aces
        vm.startBroadcast(p1Key);
        poker.revealHand(tid, "", [uint8(12), uint8(25)]);
        vm.stopBroadcast();
        console.log("[16] Player 1 reveals: Ac, Ad (pair of Aces)");

        // P2 has 3d(14) 4d(15) = junk
        vm.startBroadcast(p2Key);
        poker.revealHand(tid, "", [uint8(14), uint8(15)]);
        vm.stopBroadcast();
        console.log("[17] Player 2 reveals: 3d, 4d (high card)");

        // Result
        address winner = poker.getWinner(tid);
        console.log("");
        console.log("=== RESULT ===");
        if (winner == p1) {
            console.log("Player 1 WINS with pair of Aces!");
        } else if (winner == p2) {
            console.log("Player 2 WINS!");
        } else {
            console.log("Split pot!");
        }
        console.log("Player 1 balance:", p1.balance);
        console.log("Player 2 balance:", p2.balance);
        console.log("=== Hand Complete ===");
    }

    function _deal(uint256 tid) internal {
        uint8[] memory p1Idx = new uint8[](2);
        p1Idx[0] = 2; p1Idx[1] = 3;
        bytes32[] memory p1Shares = new bytes32[](2);
        p1Shares[0] = bytes32(uint256(0x1111));
        p1Shares[1] = bytes32(uint256(0x2222));
        bytes[] memory p1Proofs = new bytes[](2);
        p1Proofs[0] = ""; p1Proofs[1] = "";
        uint8[] memory noCards = new uint8[](0);

        vm.startBroadcast(p1Key);
        poker.submitDecrypt(tid, p1Idx, p1Shares, p1Proofs, noCards);
        vm.stopBroadcast();

        uint8[] memory p2Idx = new uint8[](2);
        p2Idx[0] = 0; p2Idx[1] = 1;
        bytes32[] memory p2Shares = new bytes32[](2);
        p2Shares[0] = bytes32(uint256(0x3333));
        p2Shares[1] = bytes32(uint256(0x4444));
        bytes[] memory p2Proofs = new bytes[](2);
        p2Proofs[0] = ""; p2Proofs[1] = "";

        vm.startBroadcast(p2Key);
        poker.submitDecrypt(tid, p2Idx, p2Shares, p2Proofs, noCards);
        vm.stopBroadcast();
    }

    function _revealCommunity(uint256 tid, uint8[] memory cards) internal {
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

        vm.startBroadcast(p1Key);
        poker.submitDecrypt(tid, indices, shares, proofs, cards);
        vm.stopBroadcast();

        vm.startBroadcast(p2Key);
        poker.submitDecrypt(tid, indices, shares, proofs, cards);
        vm.stopBroadcast();
    }

    function _makeCards3(uint8 a, uint8 b, uint8 c) internal pure returns (uint8[] memory) {
        uint8[] memory cards = new uint8[](3);
        cards[0] = a; cards[1] = b; cards[2] = c;
        return cards;
    }

    function _makeCards1(uint8 a) internal pure returns (uint8[] memory) {
        uint8[] memory cards = new uint8[](1);
        cards[0] = a;
        return cards;
    }
}
