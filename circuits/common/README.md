# Common Circuit Utilities

Shared types, structs, and helper functions used across all circuits.

## What Goes Here

- **Card struct** - Represents a card as (suit: u4, rank: u4)
- **Deck type** - Array of 52 Card structs
- **Commitment helpers** - Pedersen commitment creation and verification
- **Hash utilities** - Consistent hashing across circuits
- **Constants** - Number of cards, suits, ranks

## Files

- `src/lib.nr` - All shared circuit code
- `Nargo.toml` - Library config (this is a library, not a standalone circuit)

## Usage

Other circuits import from this library:
```noir
use dep::common::Card;
use dep::common::commit_card;
use dep::common::DECK_SIZE;
```
