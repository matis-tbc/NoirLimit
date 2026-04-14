// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISpectatorMarket - Interface for spectator wagering on poker hands
/// @notice Allows spectators to place wagers on the outcome of poker hands
interface ISpectatorMarket {

    event WagerPlaced(uint256 indexed tableId, address spectator, address predictedWinner, uint256 amount);
    event WagersResolved(uint256 indexed tableId, address winner);

    function placeWager(uint256 tableId, address predictedWinner) external payable;
    function resolveWagers(uint256 tableId) external;
    function claimWinnings(uint256 tableId) external;
}
