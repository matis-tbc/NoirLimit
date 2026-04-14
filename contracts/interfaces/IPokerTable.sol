// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPokerTable {

    enum State {
        WAITING,
        SHUFFLE,
        DEAL,
        BETTING,
        REVEAL,
        FINISHED,
        CANCELLED
    }

    struct Table {
        address player1;
        address player2;

        uint256 buyIn;
        uint256 pot;

        State state;
        uint8 turn;

        bytes32 deckCommitment;
        uint8 shuffleCount;
    }

    function tableCount() external view returns (uint256);

    function getTable(uint256 tableId)
    external
    view
    returns (Table memory);
}