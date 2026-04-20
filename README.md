# NoirLimit

Zero-knowledge poker on Ethereum. Heads-up Texas Hold'em where cards are
encrypted on-chain, dealt via partial decryption shares, and verified with
Noir ZK proofs. Includes a spectator wagering market so anyone can place bets
on a live hand.

> **Demo only.** Live on Sepolia testnet in `demoMode = true` with a mock
> verifier. See [SECURITY.md](./SECURITY.md) for the full posture.

## Team

- **Matis** ([@matis-tbc](https://github.com/matis-tbc))
- **Brady** ([@Braeden464](https://github.com/Braeden464))
- **Xavier Rudnick** ([@XavierRudnick](https://github.com/XavierRudnick))

## Status

| Layer | State |
|---|---|
| Noir circuits (shuffle, decrypt, reveal) | Built, 17 tests passing |
| Solidity contracts (PokerTable, SpectatorMarket, HandEvaluator) | Built, 65+ tests passing |
| Sepolia deployment of PokerTable | Live in demoMode |
| Sepolia deployment of SpectatorMarket | Pending |
| Frontend (Vite + React + wagmi + RainbowKit) | Built, runs locally |
| In-browser bot opponent | Built (ephemeral wallet, auto-plays) |
| Spectator wagering UI | Built (gracefully degrades until SpectatorMarket deploys) |
| ZK reveal animation | Built (three-beat: your view → on-chain → opponent's view) |
| External audit | Not done |

**Deployed addresses (Sepolia):**

- `PokerTable.sol` &mdash; [`0x6Ccaf05ac50eABE2c90b8187b9B6734dCB0E88eC`](https://sepolia.etherscan.io/address/0x6Ccaf05ac50eABE2c90b8187b9B6734dCB0E88eC)
- `MockVerifier.sol` &mdash; [`0xAc89d6BF5cA8e8f672bA2D3994f3AE8Ae7083e40`](https://sepolia.etherscan.io/address/0xAc89d6BF5cA8e8f672bA2D3994f3AE8Ae7083e40)

## Run locally

```bash
git clone https://github.com/matis-tbc/NoirLimit.git
cd NoirLimit/frontend
cp .env.example .env.local       # add your VITE_SEPOLIA_RPC (Alchemy, Infura, etc.)
npm install
npm run dev                      # opens http://localhost:51852
```

A full hand against the in-browser bot costs ~0.005 Sepolia ETH. Hit a
[Sepolia faucet](https://www.alchemy.com/faucets/ethereum-sepolia) if your
wallet is dry. See [`frontend/README.md`](./frontend/README.md) for more.

## How it works

Each hand is a fixed sequence of on-chain transactions across these phases:

```
WAITING -> SHUFFLE_P1 -> SHUFFLE_P2 -> DEALING ->
PREFLOP -> FLOP_REVEAL -> FLOP_BET ->
TURN_REVEAL -> TURN_BET -> RIVER_REVEAL -> RIVER_BET ->
SHOWDOWN -> SETTLED
```

1. Both players register a public key.
2. Each player re-encrypts and permutes the deck, submitting a ZK proof.
3. Each player publishes partial decryption shares for the OPPONENT's hole
   cards; the owner combines shares with their secret to read their own cards.
4. Standard poker betting rounds. Community cards revealed by joint partial
   decryption.
5. At showdown, each player reveals their hole cards bound to the original
   commitments. `HandEvaluator` picks the winner.

Every phase has a 120-second deadline. Stalling players forfeit via
`claimTimeout`.

## Project structure

```
NoirLimit/
├── circuits/                # Noir ZK circuits
│   ├── common/              # Pedersen hash, card encryption primitives
│   ├── shuffle/             # 103,756-gate re-encryption shuffle proof
│   ├── decrypt/             # Partial decryption proof
│   └── reveal/              # Showdown card opening proof
├── contracts/               # Solidity (Foundry)
│   ├── src/
│   │   ├── PokerTable.sol       # Game state machine + betting + settlement
│   │   ├── SpectatorMarket.sol  # Pari-mutuel wagers on hand outcome
│   │   ├── HandEvaluator.sol    # Best 5-of-7 hand ranking
│   │   └── interfaces/, mocks/
│   ├── test/                # Foundry test suite
│   ├── script/              # Deploy scripts
│   └── deployments/         # Per-chain address registry
├── frontend/                # Vite + React + wagmi + RainbowKit
│   ├── src/
│   │   ├── pages/           # Lobby, Table, Spectator
│   │   ├── components/      # Card, Seat, ActionBar, ZKReveal, OddsBar, etc.
│   │   ├── hooks/           # usePokerTable, useGameActions, useAutoSubmit, useDemoBot
│   │   ├── bot/             # Ephemeral-key auto-opponent
│   │   └── utils/           # zkLog (tx hash store), demoPayloads, deal
│   └── README.md            # Frontend run + architecture details
├── docs/archive/            # Original planning + protocol design docs
└── SECURITY.md              # Demo posture + threat model
```

## Tech stack

- **ZK proofs**: Noir, Pedersen hash, compiled with `nargo`
- **Smart contracts**: Solidity 0.8.24, Foundry
- **Proof backend**: Barretenberg (`bb` for verifier generation)
- **Frontend**: React 18, Vite, TypeScript, wagmi v2, viem, RainbowKit, Tailwind

## Build and test

```bash
cd circuits && nargo test
cd contracts && forge test
cd frontend && npm install && npm run build
```

## Circuit benchmarks (52-card deck, Pedersen hash)

| Circuit | ACIR Opcodes | Gates | Purpose |
|---------|-------------:|------:|---------|
| shuffle | 22,977 | 103,756 | Re-encryption shuffle proof |
| decrypt |    224 |  3,351 | Partial decryption proof |
| reveal  |    130 |  3,099 | Card commitment opening |

## Known limitations

- **Demo mode bypasses all proof verification.** The deployed `MockVerifier`
  accepts empty bytes. See [SECURITY.md](./SECURITY.md).
- **Hole cards are derivable from public on-chain state** in the demo build
  (deterministic seed from `tableId + player addresses`). Acceptable for a
  demo, not for real value.
- **Bot wallet key lives in browser localStorage.** Sweep it back to your
  host wallet before clearing storage.
- **2-player heads-up only.** N-party threshold decryption is out of scope.
- **No external audit.** 65+ contract tests are the only correctness gate.
- **Verifier contracts are gas-heavy** and may exceed EIP-170 size limits at
  L1; L2 deployment untested.

## License

MIT (intent; LICENSE file pending).
