# Bet Circuit

Proves that a player's betting action is valid given their hidden hand.

## What This Proves

1. The player's action (fold/check/call/raise) is legal given the current game state
2. The bet amount is within valid bounds (min raise, player's remaining stack)
3. The player actually holds the cards they committed to earlier

## Inputs

- **Public**: Game state hash, action type, bet amount
- **Private**: Player's hole cards

## Note

This circuit is primarily for rule enforcement. In many implementations, bet validity can be checked purely on-chain without ZK proofs (since bet amounts and stack sizes are public). This circuit adds an extra layer of integrity for cases where hand-dependent rules apply.

## Files

- `src/main.nr` - Main circuit logic
- `Nargo.toml` - Circuit config
