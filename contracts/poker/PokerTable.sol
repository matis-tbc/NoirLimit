// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {IVerifier} from "../interfaces/IVerifier.sol";

import "../interfaces/IPokerTable.sol";

contract PokerTable is IPokerTable {

    // -------------------------
    // Storage
    // -------------------------
    uint256 public override tableCount;
    IVerifier public shuffleVerifier;
    mapping(uint256 => Table) private tables;

    // -------------------------
    // Create Table
    // -------------------------
    function createTable(uint256 _buyIn) external payable {

        require(msg.value == _buyIn, "Wrong buyIn");

        tables[tableCount] = Table({
            player1: msg.sender,
            player2: address(0),
            buyIn: _buyIn,
            pot: _buyIn,
            state: State.WAITING,
            turn: 0
        });

        tableCount++;
    }

    // -------------------------
    // Read Table
    // -------------------------
    function getTable(uint256 tableId)
    external
    view
    override
    returns (Table memory)
    {
        return tables[tableId];
    }

    function joinTable(uint256 tableId) external payable {
        Table storage table = tables[tableId];

        require(table.player2 == address(0), "Table full");
        require(msg.value == table.buyIn, "Wrong buyIn");

        table.player2 = msg.sender;
        table.pot += msg.value;

        // Move to shuffle phase
        table.state = State.SHUFFLE;
    }
    constructor(address _shuffleVerifier) {
        shuffleVerifier = IVerifier(_shuffleVerifier);
    }

    function submitShuffleProof(
        uint256 tableId,
        bytes calldata proof,
        bytes32[] calldata publicInputs
    ) external {
        Table storage table = tables[tableId];

        require(table.state == State.SHUFFLE, "Not shuffle phase");

        // Enforce player order
        if (table.shuffleCount == 0) {
            require(msg.sender == table.player1, "P1 must shuffle first");
        } else if (table.shuffleCount == 1) {
            require(msg.sender == table.player2, "P2 must shuffle second");
        } else {
            revert("Shuffle already complete");
        }

        // Verify ZK proof
        bool valid = shuffleVerifier.verify(proof, publicInputs);
        require(valid, "Invalid shuffle proof");

        // Extract new deck commitment (publicInputs[1])
        bytes32 newCommitment = publicInputs[1];

        table.deckCommitment = newCommitment;
        table.shuffleCount++;

        // If both players shuffled → move to DEAL
        if (table.shuffleCount == 2) {
            table.state = State.DEAL;
        }
    }
}