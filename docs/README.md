# Documentation

Technical documentation for the NoirLimit protocol.

## Directory Structure

```
docs/
├── architecture.md         # System architecture overview and diagrams
├── poker-protocol.md       # Detailed poker protocol specification
├── zk-circuits.md          # Circuit design and constraint documentation
├── spectator-market.md     # Spectator wagering market specification
├── deployment-guide.md     # Step-by-step deployment instructions
└── game-flow.md            # Detailed game flow with state diagrams
```

## Document Descriptions

### `architecture.md`

High-level system architecture:
- Component diagram (contracts, circuits, frontend, proving backend)
- Data flow between components
- On-chain vs. off-chain responsibilities
- Trust model and threat analysis

### `poker-protocol.md`

The poker protocol specification:
- Commitment-based card representation
- Multi-party shuffle protocol steps
- Dealing and encryption scheme
- Betting round rules (No-Limit Texas Hold'em)
- Showdown and reveal protocol
- Payout calculation

### `zk-circuits.md`

Circuit design documentation:
- Each circuit's public/private inputs and constraints
- Commitment scheme details (Pedersen)
- Proof size and verification cost estimates
- Constraint counts and performance benchmarks

### `spectator-market.md`

Spectator wagering specification:
- Wager types (winner prediction, hand outcome, etc.)
- Odds calculation methodology
- Wager lifecycle (placement -> lock -> resolution -> payout)
- How spectator contracts read from the poker contract

### `deployment-guide.md`

How to deploy the full protocol:
- Prerequisites and environment setup
- Circuit compilation and verifier generation
- Contract deployment order and configuration
- Frontend build and hosting
- Testnet faucet and wallet setup

### `game-flow.md`

Step-by-step game flow:
- State diagram for a complete hand
- Transaction sequence for each phase
- Proof generation timeline
- Error states and recovery (disconnection, timeout)
