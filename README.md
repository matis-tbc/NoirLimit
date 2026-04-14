# NoirLimit

Zero-knowledge poker on EVM. Heads-up No-Limit Texas Hold'em with private cards secured by Noir ZK proofs.

## Team

- **Matis** ([@matis-tbc](https://github.com/matis-tbc))
- **Brady** ([@Braeden464](https://github.com/Braeden464))
- **Xavier Rudnick** ([@XavierRudnick](https://github.com/XavierRudnick))

## Status

MVP in progress. Core contracts and circuits are built and tested. Frontend not started.

**What works:**
- PokerTable.sol: complete state machine (14 states), betting, timeouts, payouts, hand evaluation
- Per-card encrypted deck storage with threshold decryption (protocol-correct per zkShuffle/Barnett-Smart)
- 3 Noir circuits (shuffle, decrypt, reveal) using Pedersen hash at 52-card scale
- Generated Solidity verifier contracts from compiled circuits
- Demo mode flag for testnet deployment (skips proof verification)
- Deploy script + scripted end-to-end demo hand
- 65 contract tests, 17 circuit tests (all passing)

**What's next:**
- SpectatorMarket.sol implementation (spectator wagering)
- Frontend (wallet connect, table UI, in-browser proof generation)
- Testnet deployment to Sepolia

## Project Structure

```
NoirLimit/
├── circuits/                # Noir ZK circuits
│   ├── common/              # Shared crypto primitives (Pedersen hash, card encryption)
│   ├── shuffle/             # Encrypt-shuffle proof (re-encryption permutation)
│   ├── decrypt/             # Threshold decryption proof (partial key share)
│   └── reveal/              # Showdown card reveal proof (commitment opening)
├── contracts/               # Solidity (Foundry)
│   ├── src/
│   │   ├── PokerTable.sol   # Game state machine + betting + settlement
│   │   ├── HandEvaluator.sol # Poker hand ranking (best 5 of 7)
│   │   ├── interfaces/      # IPokerTable, ISpectatorMarket, IVerifier
│   │   └── mocks/           # MockVerifier, RejectingVerifier for tests
│   ├── test/                # Foundry test suite (65 tests)
│   ├── script/              # Deploy.s.sol, DemoHand.s.sol
│   └── verifiers-generated/ # Solidity verifiers generated from circuits via bb
├── frontend/                # React app (not yet implemented)
└── REVIEWED_PLAN.md         # Protocol design document
```

## Tech Stack

- **ZK Proofs**: Noir (Pedersen hash, compiled with nargo 0.39.0)
- **Smart Contracts**: Solidity 0.8.24, Foundry
- **Proof Backend**: Barretenberg (bb 0.63.1 for verifier generation)
- **Frontend** (planned): React, Vite, wagmi, viem, @noir-lang/noir_js

## Getting Started

### Prerequisites

- [Nargo](https://noir-lang.org/docs/getting_started/installation/) (install via `noirup`)
- [Foundry](https://book.getfoundry.sh/) (install via `foundryup`)

### Build and Test

```bash
# Compile and test circuits
cd circuits && nargo test

# Compile and test contracts
cd contracts && forge test
```

### Circuit Benchmarks (52-card deck, Pedersen hash)

| Circuit | ACIR Opcodes | Gates | Description |
|---------|-------------|-------|-------------|
| shuffle | 22,977 | 103,756 | Re-encryption shuffle proof |
| decrypt | 224 | 3,351 | Partial decryption proof |
| reveal | 130 | 3,099 | Card commitment opening |

## How It Works

1. **Table creation**: Player 1 creates a table with a buy-in. Player 2 joins and matches.
2. **Key registration**: Both players register public keys for threshold decryption.
3. **Shuffle**: Each player re-encrypts and permutes the deck, submitting a ZK proof that the shuffle is valid.
4. **Deal**: Both players submit partial decryption shares for hole cards, proven correct via ZK.
5. **Betting**: Standard poker betting rounds (pre-flop, flop, turn, river). All on-chain.
6. **Community reveals**: Both players submit matching decrypted community card values.
7. **Showdown**: Players reveal hole cards with ZK proofs binding to their dealt commitments.
8. **Settlement**: HandEvaluator determines the winner. Contract distributes the pot.

Timeouts at every phase. If a player stalls, the opponent can claim the pot after 120 seconds.

## Known Limitations

- 2-player heads-up only (multi-player requires N-party threshold decryption)
- Decrypt proof public inputs are partially placeholder (protocol design needed for per-card encrypted state tracking)
- No frontend yet
- Gas costs untested on L2 (verifier contracts are large)

## License

MIT
