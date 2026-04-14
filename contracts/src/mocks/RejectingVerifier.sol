// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IVerifier.sol";

contract RejectingVerifier is IVerifier {
    function verify(bytes calldata, bytes32[] calldata) external pure returns (bool) {
        return false;
    }
}
