# Tests

Test suites for contracts, circuits, and end-to-end integration.

## Directory Structure

```
tests/
├── contracts/              # Solidity contract tests (Foundry)
│   ├── PokerTable.t.sol    # Core poker logic tests
│   ├── SpectatorMarket.t.sol # Spectator wager tests
│   ├── HandEvaluator.t.sol # Hand ranking tests
│   └── Verifier.t.sol      # Verifier contract tests with sample proofs
│
├── circuits/               # Noir circuit tests (Nargo)
│   ├── shuffle_test.nr     # Shuffle validity tests
│   ├── deal_test.nr        # Deal proof tests
│   ├── bet_test.nr         # Bet validity tests
│   └── reveal_test.nr      # Reveal proof tests
│
└── integration/            # End-to-end integration tests
    ├── full-hand.test.ts   # Complete hand lifecycle (shuffle -> payout)
    ├── spectator-wager.test.ts # Spectator places and resolves a wager
    └── disconnect.test.ts  # Player disconnects mid-hand (forced fold)
```

## What Each Suite Tests

### Contract Tests (`contracts/`)

Run with `forge test`. These test the Solidity logic:
- Game state transitions happen in the correct order
- Bets are validated (min raise, max stack, blind posting)
- Hand evaluation returns correct rankings for all hand types
- Pot is split correctly in multi-way pots and side pots
- Spectator wagers resolve correctly based on game outcomes
- Verifier contracts accept valid proofs and reject invalid ones

### Circuit Tests (`circuits/`)

Run with `nargo test` inside each circuit directory. These test the Noir circuits:
- Valid shuffles produce valid proofs
- Invalid shuffles (duplicate cards, missing cards) fail
- Dealt cards match deck commitments
- Reveal proofs match prior deal commitments
- Edge cases (all same suit, sequential ranks, etc.)

### Integration Tests (`integration/`)

Run with `npm test` in the integration directory. These test the full stack:
- Deploy contracts to a local Anvil chain
- Generate real proofs using Noir WASM
- Submit proofs through contract calls
- Verify complete hand lifecycle end-to-end
- Test the spectator wager flow
- Test player disconnection handling

## Running Tests

```bash
# Contract tests
cd contracts && forge test -vvv

# Circuit tests (run from each circuit dir)
cd circuits/shuffle && nargo test

# Integration tests
cd tests/integration && npm test

# Run everything
./scripts/test-all.sh
```
