// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IVerifier.sol";

contract MockVerifier is IVerifier {
    function verify(bytes calldata, bytes32[] calldata) external pure returns (bool) {
        return true;
    }
}
