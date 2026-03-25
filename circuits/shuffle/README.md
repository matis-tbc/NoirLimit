# Shuffle Circuit

Proves that a player's shuffle is a valid permutation of the deck.

## What This Proves

Given a committed deck state, this circuit proves:
1. The output deck is a valid permutation of the input deck (no cards added/removed/duplicated)
2. The player contributed randomness to the permutation
3. The new deck commitment matches the shuffled result

## Inputs

- **Public**: Previous deck commitment, new deck commitment
- **Private**: Permutation array (52 indices), randomness value

## Multi-Party Protocol

Each player shuffles in sequence. Player 1 shuffles the initial ordered deck, Player 2 shuffles Player 1's output, etc. Since each player's permutation is private, no single player knows the final card ordering.

## Files

- `src/main.nr` - Main circuit logic
- `Nargo.toml` - Circuit config (name, dependencies)
- `Prover.toml` - Example prover inputs for testing
- `Verifier.toml` - Example verifier inputs
