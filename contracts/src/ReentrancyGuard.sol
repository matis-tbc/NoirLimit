// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Minimal in-tree reentrancy guard. Kept local to avoid pulling OpenZeppelin
// for a single modifier. Semantics match OZ's ReentrancyGuard: one storage
// slot, 1->2 on entry, 2->1 on exit, revert if already 2.
abstract contract ReentrancyGuard {
    uint256 private _locked = 1;

    modifier nonReentrant() {
        require(_locked == 1, "reentrant");
        _locked = 2;
        _;
        _locked = 1;
    }
}
