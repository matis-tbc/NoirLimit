# NoirLimit

Zero-Knowledge Poker and Spectator Wagering Protocol built with Noir.

## Team

- **Matis** ([@matis-tbc](https://github.com/matis-tbc))
- **Brady** ([@Braeden464](https://github.com/Braeden464))
- **Xavier Rudnick** ([@XavierRudnick](https://github.com/XavierRudnick))

## Overview

NoirLimit is a trustless on-chain poker application that uses Noir zero-knowledge proofs to keep player hands private while revealing community cards publicly. It includes a spectator betting market where viewers can wager on game outcomes.

### The Problem

Blockchain data is 100% transparent. For poker to work on-chain, individual player cards must remain hidden while the game state (community cards, pot size, actions) stays public and verifiable. Noir's zero-knowledge circuits solve this by proving card validity without revealing card values.

### How It Works

1. **Deck Shuffling** - A commitment-based shuffle protocol where each player contributes randomness, proven valid via ZK circuits
2. **Private Dealing** - Cards are dealt as encrypted commitments; only the recipient can decrypt their hand
3. **Betting Rounds** - Standard No-Limit Texas Hold'em betting (pre-flop, flop, turn, river) managed by the poker smart contract
4. **Card Reveals** - Community cards are revealed publicly; player hands are only revealed at showdown via ZK proofs
5. **Payouts** - Winner determined by on-chain proof verification; pot distributed automatically
6. **Spectator Wagering** - A secondary contract lets spectators bet on outcomes using only public game state

## Project Structure

```
NoirLimit/
├── contracts/          # Solidity smart contracts
│   ├── poker/          # Core poker game logic
│   ├── spectator/      # Spectator wagering market
│   ├── verifiers/      # Auto-generated proof verifier contracts
│   ├── interfaces/     # Contract interfaces
│   └── libraries/      # Shared Solidity libraries
├── circuits/           # Noir zero-knowledge circuits
│   ├── shuffle/        # Deck shuffle proof circuits
│   ├── deal/           # Card dealing proof circuits
│   ├── bet/            # Betting validity circuits
│   ├── reveal/         # Card reveal/showdown circuits
│   └── common/         # Shared circuit utilities
├── frontend/           # React web application
│   └── src/
│       ├── components/ # UI components
│       ├── hooks/      # Custom React hooks
│       ├── utils/      # Helper functions
│       ├── pages/      # Page-level components
│       ├── assets/     # Static assets
│       └── abi/        # Contract ABIs
├── scripts/            # Deployment and utility scripts
├── tests/              # Test suites
│   ├── contracts/      # Smart contract tests
│   ├── circuits/       # Circuit tests
│   └── integration/    # End-to-end integration tests
└── docs/               # Technical documentation
```

## Tech Stack

- **ZK Proofs**: [Noir](https://noir-lang.org/) (by Aztec)
- **Smart Contracts**: Solidity (EVM-compatible)
- **Frontend**: React + ethers.js/viem
- **Testnet**: Ethereum EVM testnet (Sepolia)
- **Potential L2**: Aztec Network (if L1 gas costs are prohibitive)

## Getting Started

### Prerequisites

- [Node.js](https://nodejs.org/) >= 18
- [Nargo](https://noir-lang.org/docs/getting_started/installation/) (Noir toolchain)
- [Foundry](https://book.getfoundry.sh/) (Solidity development)
- A wallet with testnet ETH

### Installation

```bash
# Clone the repo
git clone https://github.com/matis-tbc/NoirLimit.git
cd NoirLimit

# Install frontend dependencies
cd frontend && npm install

# Compile Noir circuits
cd ../circuits && nargo compile

# Compile Solidity contracts
cd ../contracts && forge build
```

### Running Tests

```bash
# Circuit tests
cd circuits && nargo test

# Contract tests
cd contracts && forge test

# Integration tests
cd tests/integration && npm test
```

## Timeline

| Week | Dates | Focus |
|------|-------|-------|
| 1 | Mar 11 - Mar 17 | Research & System Design |
| 2 | Mar 18 - Mar 24 | Core Poker Logic |
| 3 | Mar 25 - Mar 31 | Zero-Knowledge Integration |
| 4 | Apr 1 - Apr 7 | Betting System & Spectator Market |
| 5 | Apr 8 - Apr 14 | Frontend & Integration |
| 6 | Apr 15 - Apr 20 | Testing & Final Deployment |

## Definition of Success

Launch an MVP on an EVM testnet that can:
1. Complete a full hand of poker (shuffle, deal, bet, payout) with private card data secured on-chain
2. Process at least one spectator wager through the secondary smart contract

## Known Risks & Blind Spots

- **Client-side proof generation performance** on low-spec hardware is unknown
- **Gas overhead** for verifying multiple complex proofs may exceed L1 practical limits (may require Aztec L2)
- **Player disconnection** means their cards can't be decrypted, forcing a fold

## License

MIT
