// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {UltraVerifier as RevealVerifier} from "../verifiers-generated/RevealVerifier.sol";

/// @notice Deploys only the generated RevealVerifier for the /proof-demo
/// route. This is intentionally standalone — no PokerTable is redeployed.
/// The legacy PokerTable at 0x6Ccaf05a... remains the single game contract.
///
/// Usage:
///   PRIVATE_KEY=0x... forge script script/DeployRevealVerifier.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL --broadcast -vvv
contract DeployRevealVerifier is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);
        RevealVerifier verifier = new RevealVerifier();
        console.log("RevealVerifier:", address(verifier));
        vm.stopBroadcast();
    }
}
