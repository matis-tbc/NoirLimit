// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/SpectatorMarket.sol";

contract DeploySpectator is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address pokerTable = vm.envAddress("POKER_TABLE");

        vm.startBroadcast(deployerKey);
        SpectatorMarket sm = new SpectatorMarket(pokerTable);
        vm.stopBroadcast();

        console.log("PokerTable:", pokerTable);
        console.log("SpectatorMarket:", address(sm));
    }
}
