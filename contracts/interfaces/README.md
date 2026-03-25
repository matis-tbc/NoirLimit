# Interfaces

Solidity interfaces for cross-contract communication and frontend integration.

## Files to Implement

| File | Purpose |
|------|---------|
| `IPokerTable.sol` | Interface for the PokerTable contract. Used by SpectatorMarket to read game state. |
| `ISpectatorMarket.sol` | Interface for the SpectatorMarket contract. |
| `IVerifier.sol` | Common interface for all verifier contracts (`verify(bytes proof, bytes32[] publicInputs) returns (bool)`). |
