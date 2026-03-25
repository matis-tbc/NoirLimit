# Reveal Circuit

Proves that revealed cards at showdown match the original dealt commitments.

## What This Proves

1. The card values being revealed match the commitments made during the deal phase
2. The player is revealing their actual cards, not substituting different ones
3. The commitment opening (randomness) is valid

## Inputs

- **Public**: Original card commitments (from dealing), revealed card values
- **Private**: Commitment randomness (opening values)

## Showdown Flow

1. All remaining players submit reveal proofs
2. Contract verifies each proof against stored deal commitments
3. Revealed cards + community cards are passed to HandEvaluator
4. Winner is determined and pot is distributed

## Files

- `src/main.nr` - Main circuit logic
- `Nargo.toml` - Circuit config
