// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../interfaces/IVerifier.sol";

contract AllowListVerifier is IVerifier {
    bytes32 public immutable allowedHashOne;
    bytes32 public immutable allowedHashTwo;

    constructor(bytes32 _allowedHashOne, bytes32 _allowedHashTwo) {
        allowedHashOne = _allowedHashOne;
        allowedHashTwo = _allowedHashTwo;
    }

    function verify(bytes calldata, bytes32[] calldata publicInputs) external view returns (bool) {
        bytes32 digest = keccak256(abi.encode(publicInputs));
        return digest == allowedHashOne || digest == allowedHashTwo;
    }
}
