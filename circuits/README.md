# Circuits

Noir zero-knowledge circuits for private card handling in NoirLimit. Built with [Nargo](https://noir-lang.org/).

## Directory Structure

```
circuits/
├── shuffle/            # Deck shuffle proof circuits
│   ├── src/
│   │   └── main.nr    # Proves a shuffle is a valid permutation of the deck
│   └── Nargo.toml
│
├── deal/               # Card dealing proof circuits
│   ├── src/
│   │   └── main.nr    # Proves a dealt card belongs to the shuffled deck without revealing it
│   └── Nargo.toml
│
├── bet/                # Betting validity circuits
│   ├── src/
│   │   └── main.nr    # Proves a bet action is valid given hidden hand state
│   └── Nargo.toml
│
├── reveal/             # Card reveal / showdown circuits
│   ├── src/
│   │   └── main.nr    # Proves revealed cards match prior commitments
│   └── Nargo.toml
│
└── common/             # Shared circuit utilities
    ├── src/
    │   └── lib.nr      # Card structs, commitment helpers, shared types
    └── Nargo.toml
```

## Circuit Descriptions

### Shuffle Circuit (`shuffle/`)

**Purpose**: Proves that a player's shuffle is a valid permutation of the input deck.

**Public inputs**: Previous deck commitment, new deck commitment
**Private inputs**: Permutation array, randomness

The shuffle protocol is multi-party -- each player shuffles and proves validity. The final shuffled deck is a composition of all individual shuffles, so no single player controls card ordering.

### Deal Circuit (`deal/`)

**Purpose**: Proves that a dealt card is a valid card from the shuffled deck at a specific position, without revealing which card it is.

**Public inputs**: Deck commitment, card position index, card commitment (hash of card value)
**Private inputs**: Card value, opening randomness

This lets the contract verify a card was dealt correctly while the card value stays private to the recipient.

### Bet Circuit (`bet/`)

**Purpose**: Proves that a player's action (fold/check/call/raise) is valid given their private hand, without revealing the hand.

**Public inputs**: Game state hash, action type, bet amount
**Private inputs**: Player's hand cards

This is mainly used to enforce rules -- e.g., a player can't claim "all-in" if their stack doesn't match, or make an invalid raise.

### Reveal Circuit (`reveal/`)

**Purpose**: At showdown, proves that the cards a player reveals match their original dealt card commitments.

**Public inputs**: Original card commitments (from dealing phase), revealed card values
**Private inputs**: Commitment randomness (opening)

This prevents players from lying about their hand at showdown.

### Common (`common/`)

Shared types and helpers used across circuits:
- Card struct (suit + rank)
- Pedersen commitment helpers
- Deck representation (52-element array)
- Hash utilities

## How Circuits Connect to Contracts

1. Player generates a proof locally using `nargo prove`
2. Proof is submitted to the poker contract on-chain
3. Contract calls the corresponding verifier contract (auto-generated from `nargo codegen-verifier`)
4. Verifier returns true/false; game state advances if valid

## Build & Test

```bash
# Compile all circuits
for dir in shuffle deal bet reveal common; do
  cd $dir && nargo compile && cd ..
done

# Run circuit tests
for dir in shuffle deal bet reveal common; do
  cd $dir && nargo test && cd ..
done

# Generate Solidity verifiers
for dir in shuffle deal bet reveal; do
  cd $dir && nargo codegen-verifier && cd ..
done
```

## Design Considerations

- **Commitment scheme**: Using Pedersen commitments (native to Noir) for card hiding
- **Multi-party shuffle**: Prevents any single player from stacking the deck
- **Proof size**: Each proof is ~1-2KB on-chain; verifying costs ~200-300k gas on L1
- **If gas is too high**: We may deploy on the Aztec network where Noir proofs verify natively with much lower overhead
