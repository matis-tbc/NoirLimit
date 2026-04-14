// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/PokerTable.sol";
import "../src/mocks/MockVerifier.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        bool demo = vm.envOr("DEMO_MODE", false);

        vm.startBroadcast(deployerKey);

        // For testnet: deploy MockVerifier as placeholder
        // For production: deploy real generated verifiers
        address shuffleVerifier;
        address decryptVerifier;
        address revealVerifier;

        if (demo) {
            // Demo mode: use mock verifiers that accept any proof
            MockVerifier mock = new MockVerifier();
            shuffleVerifier = address(mock);
            decryptVerifier = address(mock);
            revealVerifier  = address(mock);
            console.log("MockVerifier:", address(mock));
        } else {
            // Production: deploy from generated verifier artifacts
            // Requires verifiers-generated/ to be compiled
            shuffleVerifier = deployCode("ShuffleVerifier.sol");
            decryptVerifier = deployCode("DecryptVerifier.sol");
            revealVerifier  = deployCode("RevealVerifier.sol");
            console.log("ShuffleVerifier:", shuffleVerifier);
            console.log("DecryptVerifier:", decryptVerifier);
            console.log("RevealVerifier:", revealVerifier);
        }

        PokerTable poker = new PokerTable(shuffleVerifier, decryptVerifier, revealVerifier, demo);
        console.log("PokerTable:", address(poker));
        console.log("Demo mode:", demo);

        vm.stopBroadcast();
    }
}
