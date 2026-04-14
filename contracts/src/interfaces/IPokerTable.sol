// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IPokerTable - Interface for the NoirLimit poker table
/// @notice Defines the external API, state machine, and events for ZK poker
interface IPokerTable {

    // -------------------------------------------------------
    //  Types
    // -------------------------------------------------------

    enum State {
        WAITING,       // 0  - table created, waiting for opponent
        SHUFFLE_P1,    // 1  - player 1 submits shuffle proof
        SHUFFLE_P2,    // 2  - player 2 submits shuffle proof
        DEALING,       // 3  - both players submit partial decryptions
        PREFLOP,       // 4  - pre-flop betting round
        FLOP_REVEAL,   // 5  - both submit flop decryptions
        FLOP_BET,      // 6  - flop betting round
        TURN_REVEAL,   // 7  - both submit turn decryption
        TURN_BET,      // 8  - turn betting round
        RIVER_REVEAL,  // 9  - both submit river decryption
        RIVER_BET,     // 10 - river betting round
        SHOWDOWN,      // 11 - players reveal hands via ZK proofs
        SETTLED,       // 12 - winner determined, pot distributed
        CANCELLED      // 13 - hand cancelled (timeout/disconnect)
    }

    enum Action { FOLD, CHECK, CALL, RAISE }

    // -------------------------------------------------------
    //  Events
    // -------------------------------------------------------

    event TableCreated(uint256 indexed tableId, address creator, uint256 buyIn, uint256 bigBlind);
    event PlayerJoined(uint256 indexed tableId, address player);
    event TableCancelled(uint256 indexed tableId);
    event ShuffleSubmitted(uint256 indexed tableId, address player, bytes32 newDeckCommitment);
    event DecryptSubmitted(uint256 indexed tableId, address player, uint8[] cardIndices, bytes32[] partialDecryptionValues);
    event CommunityCardsRevealed(uint256 indexed tableId, uint8 newCardCount);
    event ActionTaken(uint256 indexed tableId, address player, uint8 action, uint256 amount);
    event HandRevealed(uint256 indexed tableId, address player, uint8 card0, uint8 card1);
    event HandSettled(uint256 indexed tableId, address winner, uint256 pot);
    event TimeoutClaimed(uint256 indexed tableId, address beneficiary);

    // -------------------------------------------------------
    //  Table management
    // -------------------------------------------------------

    function createTable(uint256 bigBlind) external payable returns (uint256 tableId);
    function joinTable(uint256 tableId) external payable;
    function cancelTable(uint256 tableId) external;

    // -------------------------------------------------------
    //  Game phases
    // -------------------------------------------------------

    function registerPublicKey(uint256 tableId, bytes32 publicKey) external;

    function submitShuffle(
        uint256 tableId,
        bytes calldata proof,
        bytes32 newDeckCommitment,
        bytes32[52] calldata cardCommitments,
        bytes32[52] calldata cardRandomizers,
        bytes32[52] calldata cardMaskedPayloads
    ) external;

    function submitDecrypt(
        uint256 tableId,
        uint8[] calldata cardIndices,
        bytes32[] calldata partialDecryptionValues,
        bytes[] calldata proofs,
        uint8[] calldata cardValues
    ) external;

    function act(uint256 tableId, Action action, uint256 raiseAmount) external;
    function revealHand(uint256 tableId, bytes calldata proof, uint8[2] calldata cards) external;
    function claimTimeout(uint256 tableId) external;

    // -------------------------------------------------------
    //  Views
    // -------------------------------------------------------

    function getTable(uint256 tid) external view returns (
        address[2] memory players,
        uint256[2] memory stacks,
        uint256 pot,
        State state,
        uint8 communityCardCount,
        uint8 turn
    );

    function getWinner(uint256 tid) external view returns (address);

    function getEncryptedCard(uint256 tid, uint8 cardIndex) external view returns (
        bytes32 commitment, bytes32 randomizer, bytes32 maskedPayload
    );

    function getPartialDecryption(uint256 tid, uint8 cardIndex, uint8 playerIndex) external view returns (
        bytes32 share
    );
}
