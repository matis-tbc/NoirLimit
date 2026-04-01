# Shuffle Circuit

Week 4 implements the shuffle circuit as a staged **encrypt-shuffle prototype** aligned with `REVIEWED_PLAN.md`, not the older permutation-only design.

## What This Proves

Given a committed encrypted deck state, this circuit proves:

1. `previous_deck` matches `previous_deck_commitment`
2. `new_deck` matches `new_deck_commitment`
3. `permutation` is a valid permutation over the active deck size
4. every `new_deck[i]` is a valid rerandomization of `previous_deck[permutation[i]]`

That gives us the right protocol shape for a mental-poker shuffle proof without forcing the final cryptographic primitive too early.

## Inputs

- **Public**: `previous_deck_commitment`, `new_deck_commitment`
- **Private**:
  - `previous_deck: [EncryptedCard; N]`
  - `new_deck: [EncryptedCard; N]`
  - `permutation: [u8; N]`
  - `rerandomization: [Field; N]`

## Current model

The current `EncryptedCard` is a fixed-width placeholder ciphertext that contains:

- a hidden card commitment
- a rerandomizable masking field
- a stored randomizer used to derive that mask

This is a **SNARK-friendly placeholder model** for Week 4. It is useful for building and testing the shuffle proof shape, but it is not the final ROYALE/ElGamal-style mental-poker encryption scheme.

## Deck sizing

- The live circuit uses a small compile-time `DECK_SIZE` for practical test witnesses.
- The shared library also defines `FULL_DECK_SIZE = 52`.
- Helper APIs are generic over deck length so moving to 52 cards should be a constant/config upgrade rather than a redesign.

## Tests

`src/main.nr` includes circuit tests for:

- valid identity permutation with rerandomization
- valid nontrivial permutation
- duplicate permutation entries
- out-of-range permutation entries
- tampered rerandomization on one card
- invalid previous commitment
- invalid new commitment
- scale-readiness fixture generation for the future 52-card move

## Files

- `src/main.nr` - Main shuffle circuit plus circuit tests
- `Nargo.toml` - Package config
- `Prover.toml` - Placeholder prover input template to fill with concrete fixtures once `nargo` is available
