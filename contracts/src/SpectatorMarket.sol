// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./interfaces/IPokerTable.sol";
import "./interfaces/ISpectatorMarket.sol";

contract SpectatorMarket is ISpectatorMarket {
    uint8 internal constant UNRESOLVED = type(uint8).max;

    struct Market {
        uint256 totalOnPlayer0;
        uint256 totalOnPlayer1;
        uint256 paidOut;
        uint256 claimedWinningAmount;
        bool resolved;
        bool refundsOnly;
        uint8 winningSide;
    }

    struct Wager {
        address predictedWinner;
        uint256 amount;
        bool claimed;
    }

    IPokerTable public immutable pokerTable;

    mapping(uint256 => Market) internal markets;
    mapping(uint256 => mapping(address => Wager)) internal wagers;

    constructor(address pokerTableAddress) {
        require(pokerTableAddress != address(0), "invalid poker table");
        pokerTable = IPokerTable(pokerTableAddress);
    }

    function placeWager(uint256 tableId, address predictedWinner) external payable override {
        require(msg.value > 0, "must send wager");

        (
            address[2] memory players,
            ,
            ,
            IPokerTable.State state,
            ,
            
        ) = pokerTable.getTable(tableId);

        require(players[0] != address(0) && players[1] != address(0), "table not full");
        require(
            state == IPokerTable.State.SHUFFLE_P1 ||
            state == IPokerTable.State.SHUFFLE_P2 ||
            state == IPokerTable.State.DEALING,
            "wagering closed"
        );
        require(msg.sender != players[0] && msg.sender != players[1], "players cannot wager");
        require(predictedWinner == players[0] || predictedWinner == players[1], "invalid predicted winner");

        Wager storage wager = wagers[tableId][msg.sender];
        if (wager.amount > 0) {
            require(!wager.claimed, "wager already claimed");
            require(wager.predictedWinner == predictedWinner, "cannot switch sides");
        } else {
            wager.predictedWinner = predictedWinner;
        }

        wager.amount += msg.value;

        Market storage market = markets[tableId];
        require(!market.resolved, "market resolved");

        if (predictedWinner == players[0]) {
            market.totalOnPlayer0 += msg.value;
        } else {
            market.totalOnPlayer1 += msg.value;
        }

        emit WagerPlaced(tableId, msg.sender, predictedWinner, msg.value);
    }

    function resolveWagers(uint256 tableId) external override {
        Market storage market = markets[tableId];
        require(!market.resolved, "market already resolved");

        (
            address[2] memory players,
            ,
            ,
            IPokerTable.State state,
            ,
            
        ) = pokerTable.getTable(tableId);
        require(
            state == IPokerTable.State.SETTLED || state == IPokerTable.State.CANCELLED,
            "hand not final"
        );

        address winner = pokerTable.getWinner(tableId);
        market.resolved = true;

        if (state == IPokerTable.State.CANCELLED || winner == address(0)) {
            market.refundsOnly = true;
            market.winningSide = UNRESOLVED;
        } else if (winner == players[0]) {
            market.winningSide = 0;
        } else if (winner == players[1]) {
            market.winningSide = 1;
        } else {
            revert("winner mismatch");
        }

        emit WagersResolved(tableId, winner);
    }

    function claimWinnings(uint256 tableId) external override {
        Market storage market = markets[tableId];
        require(market.resolved, "market not resolved");

        Wager storage wager = wagers[tableId][msg.sender];
        require(wager.amount > 0, "no wager");
        require(!wager.claimed, "already claimed");

        wager.claimed = true;

        uint256 payout = _quoteClaim(market, wager, tableId);
        if (payout > 0) {
            market.paidOut += payout;
            if (!market.refundsOnly) {
                market.claimedWinningAmount += wager.amount;
            }

            (bool ok, ) = payable(msg.sender).call{value: payout}("");
            require(ok, "transfer failed");
        } else if (!market.refundsOnly && _isWinningWager(tableId, market, wager)) {
            market.claimedWinningAmount += wager.amount;
        }

        emit WinningsClaimed(tableId, msg.sender, payout);
    }

    function getMarket(uint256 tableId) external view override returns (
        address[2] memory players,
        uint256 totalOnPlayer0,
        uint256 totalOnPlayer1,
        bool resolved,
        bool refundsOnly,
        address winner
    ) {
        (players, , , , , ) = pokerTable.getTable(tableId);
        Market storage market = markets[tableId];
        address marketWinner = pokerTable.getWinner(tableId);
        if (market.resolved && market.refundsOnly) {
            marketWinner = address(0);
        }

        return (
            players,
            market.totalOnPlayer0,
            market.totalOnPlayer1,
            market.resolved,
            market.refundsOnly,
            marketWinner
        );
    }

    function getWager(uint256 tableId, address spectator) external view override returns (
        address predictedWinner,
        uint256 amount,
        bool claimed
    ) {
        Wager storage wager = wagers[tableId][spectator];
        return (wager.predictedWinner, wager.amount, wager.claimed);
    }

    function quoteClaim(uint256 tableId, address spectator) external view override returns (uint256 amount) {
        Market storage market = markets[tableId];
        Wager storage wager = wagers[tableId][spectator];
        if (!market.resolved || wager.amount == 0 || wager.claimed) {
            return 0;
        }

        return _quoteClaim(market, wager, tableId);
    }

    function _quoteClaim(Market storage market, Wager storage wager, uint256 tableId) internal view returns (uint256) {
        if (market.refundsOnly) {
            return wager.amount;
        }

        if (!_isWinningWager(tableId, market, wager)) {
            return 0;
        }

        uint256 winningPool = market.winningSide == 0 ? market.totalOnPlayer0 : market.totalOnPlayer1;
        uint256 totalPool = market.totalOnPlayer0 + market.totalOnPlayer1;
        require(winningPool > 0, "no winning wagers");

        if (market.claimedWinningAmount + wager.amount == winningPool) {
            return totalPool - market.paidOut;
        }

        return (wager.amount * totalPool) / winningPool;
    }

    function _isWinningWager(uint256 tableId, Market storage market, Wager storage wager) internal view returns (bool) {
        (
            address[2] memory players,
            ,
            ,
            ,
            ,
            
        ) = pokerTable.getTable(tableId);

        if (market.winningSide == 0) {
            return wager.predictedWinner == players[0];
        }
        if (market.winningSide == 1) {
            return wager.predictedWinner == players[1];
        }
        return false;
    }
}
