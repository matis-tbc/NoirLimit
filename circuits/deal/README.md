# Deal Circuit

Proves that a dealt card is valid without revealing it.

## What This Proves

1. The card at position `index` in the committed deck has value `card_value`
2. The card commitment (hash) corresponds to that card value
3. The card hasn't been dealt before (index is unused)

## Inputs

- **Public**: Deck commitment, card position index, card commitment hash
- **Private**: Card value (suit + rank), commitment randomness

## How Dealing Works

The dealer (or contract) assigns deck positions to players. Each player receives the card value encrypted/committed. The deal circuit proves the commitment is honest without revealing the card to anyone else.

## Files

- `src/main.nr` - Main circuit logic
- `Nargo.toml` - Circuit config
