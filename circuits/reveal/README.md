# Reveal Circuit

Proves that a player's two revealed hole cards at showdown match the original deal-phase commitments.

## What This Proves

1. The two revealed hole-card values match the commitments made during the deal phase
2. The player is revealing their actual showdown hand, not substituting different cards
3. The commitment openings (randomness values) are valid for both cards

## Inputs

- **Public**: `card_commitments: [Field; 2]`, `revealed_cards: [Card; 2]`
- **Private**: `commitment_randomness: [Field; 2]`

## Showdown Flow

1. All remaining players submit reveal proofs
2. Contract verifies each proof against stored deal commitments
3. Revealed cards + community cards are passed to HandEvaluator
4. Winner is determined and pot is distributed

## Files

- `src/main.nr` - Main circuit logic
- `Nargo.toml` - Circuit config
- `Prover.toml` - Example prover input template
