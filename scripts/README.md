# Scripts

Deployment, setup, and utility scripts for NoirLimit.

## Directory Structure

```
scripts/
├── Deploy.s.sol         # Foundry deployment script for all contracts
├── deploy-testnet.sh    # Shell wrapper for testnet deployment
├── generate-verifiers.sh # Compile circuits and generate Solidity verifiers
└── setup-dev.sh         # Dev environment setup (install deps, compile, etc.)
```

## Scripts Overview

### `Deploy.s.sol`

Foundry deployment script that deploys contracts in the correct order:
1. Deploy verifier contracts (Shuffle, Deal, Bet, Reveal)
2. Deploy library contracts (CardLib, BettingLib)
3. Deploy PokerTable with verifier addresses
4. Deploy SpectatorMarket linked to PokerTable

### `deploy-testnet.sh`

Wraps `forge script` with testnet RPC URL and deployer private key. Handles contract verification on block explorer.

### `generate-verifiers.sh`

Compiles all Noir circuits and generates fresh Solidity verifier contracts, then copies them into `contracts/verifiers/`.

### `setup-dev.sh`

One-command dev setup:
1. Install Node dependencies
2. Install Nargo (if not present)
3. Install Foundry (if not present)
4. Compile circuits
5. Generate verifiers
6. Compile contracts

## Usage

```bash
# Full dev setup
chmod +x scripts/setup-dev.sh && ./scripts/setup-dev.sh

# Regenerate verifiers after circuit changes
./scripts/generate-verifiers.sh

# Deploy to Sepolia testnet
forge script scripts/Deploy.s.sol --rpc-url $SEPOLIA_RPC --broadcast --verify
```
