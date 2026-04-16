// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ISpectatorMarket - Interface for spectator wagering on poker hands
/// @notice Allows spectators to place wagers on the outcome of poker hands
interface ISpectatorMarket {

    event WagerPlaced(uint256 indexed tableId, address spectator, address predictedWinner, uint256 amount);
    event WagersResolved(uint256 indexed tableId, address winner);
    event WinningsClaimed(uint256 indexed tableId, address spectator, uint256 amount);

    function placeWager(uint256 tableId, address predictedWinner) external payable;
    function resolveWagers(uint256 tableId) external;
    function claimWinnings(uint256 tableId) external;

    function getMarket(uint256 tableId) external view returns (
        address[2] memory players,
        uint256 totalOnPlayer0,
        uint256 totalOnPlayer1,
        bool resolved,
        bool refundsOnly,
        address winner
    );

    function getWager(uint256 tableId, address spectator) external view returns (
        address predictedWinner,
        uint256 amount,
        bool claimed
    );

    function quoteClaim(uint256 tableId, address spectator) external view returns (uint256 amount);
}
