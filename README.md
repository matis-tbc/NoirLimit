# NoirLimit

Zero-knowledge poker on Ethereum. Heads-up Texas Hold'em where cards are
encrypted on-chain, dealt via partial decryption shares, and verified with
Noir ZK proofs. Includes a spectator wagering market so anyone can place bets
on a live hand.

> **Demo only.** Live on Sepolia testnet in `demoMode = true` with a mock
> verifier. See [SECURITY.md](./SECURITY.md) for the full posture.

## Why NoirLimit

NoirLimit is a ZK poker reference implementation in Noir with a pari-mutuel
**spectator wagering market baked into the protocol**. Observers stake on
outcomes while hole cards stay encrypted until showdown, which is, as far as
we can tell, genuinely novel among ZK poker projects. The current deployment
runs `demoMode = true` against a `MockVerifier`: contract-level invariants
like "your revealed hand must match on-chain commitments" still enforce
correctness, but the Noir circuits themselves are bypassed on-chain. With a
real verifier on, the circuits catch a bogus reveal one layer earlier.
See [SECURITY.md](./SECURITY.md) for what this does and does not prove.

## Team

- **Matis** ([@matis-tbc](https://github.com/matis-tbc))
- **Brady** ([@Braeden464](https://github.com/Braeden464))
- **Xavier Rudnick** ([@XavierRudnick](https://github.com/XavierRudnick))

## Status

| Layer | State |
|---|---|
| Noir circuits (shuffle, decrypt, reveal) | Built, 17 tests passing |
| Solidity contracts (PokerTable, SpectatorMarket, HandEvaluator, RevealVerifier) | Built, 93 tests passing |
| Sepolia deployment of PokerTable | Live in demoMode |
| Sepolia deployment of SpectatorMarket | Live + verified (source-only reentrancy guard pending redeploy) |
| Sepolia deployment of standalone RevealVerifier (UltraPlonk) | Live, accepts real Noir proofs, rejects tampered inputs |
| In-browser proof demo (`/proof-demo`) | Built (bb.js generates a real reveal proof in the browser, calls live verifier) |
| Demo-day e2e verification (`just verify-e2e`) | Built (bb.js self-verify + Foundry + live Sepolia agree) |
| Frontend (Vite + React + wagmi + RainbowKit) | Built, runs locally |
| In-browser bot opponent | Built (ephemeral wallet, pokersolver-driven decisions, retries on revert) |
| Spectator wagering UI | Built with odds bar, time-series sparkline, sealed-state badge, live ticker |
| ZK reveal animation | Built (three-beat tied to tx lifecycle, dismissable) |
| Cheat moment | Built (`<CheatMoment>` dedicated component, confirm + caught modals, demoMode-truthful copy) |
| Move history panel | Built (player-readable, grouped by betting round, on Table and Spectator) |
| Play Again rematch flow | Built (TerminalPanel after settle/cancel) |
| Hide tables from Lobby | Built (localStorage, per-wallet) |
| Wallet-signature banner | Built (tells user MetaMask popup is expected) |
| Frontend test infra | vitest + RTL + happy-dom, `npm run test` runs parseRevert unit suite |
| External audit | Not done |

**Deployed addresses (Sepolia):**

- `PokerTable.sol` &mdash; [`0x6Ccaf05ac50eABE2c90b8187b9B6734dCB0E88eC`](https://sepolia.etherscan.io/address/0x6Ccaf05ac50eABE2c90b8187b9B6734dCB0E88eC)
- `SpectatorMarket.sol` &mdash; [`0x666898f7706ddd0193012aEc50EAF7D2E9FCbAf0`](https://sepolia.etherscan.io/address/0x666898f7706ddd0193012aEc50EAF7D2E9FCbAf0)
- `MockVerifier.sol` &mdash; [`0xAc89d6BF5cA8e8f672bA2D3994f3AE8Ae7083e40`](https://sepolia.etherscan.io/address/0xAc89d6BF5cA8e8f672bA2D3994f3AE8Ae7083e40)
- `RevealVerifier.sol` (standalone UltraPlonk, for `/proof-demo`) &mdash; [`0x8A6e6fb6e795a22d6eD4cB3922bDE5164B03BB51`](https://sepolia.etherscan.io/address/0x8A6e6fb6e795a22d6eD4cB3922bDE5164B03BB51)

## Run locally

**Prerequisites:**

- [MetaMask](https://metamask.io/) browser extension installed and set to the
  Sepolia testnet (MetaMask → Networks → "Show test networks" → Sepolia). Pin
  the extension to your toolbar so signature popups attach to the page instead
  of opening a separate window.
- A Sepolia RPC endpoint. Free tier from [Alchemy](https://www.alchemy.com/)
  or [Infura](https://www.infura.io/) works; paste the URL into
  `frontend/.env.local` as `VITE_SEPOLIA_RPC`.
- ~0.03 Sepolia ETH in your host wallet (0.015 to fund the bot, rest for
  your own gas across ~17 sequential txs per hand). Free from the
  [Sepolia faucet](https://www.alchemy.com/faucets/ethereum-sepolia).

```bash
git clone https://github.com/matis-tbc/NoirLimit.git
cd NoirLimit/frontend
cp .env.example .env.local       # add your VITE_SEPOLIA_RPC (Alchemy, Infura, etc.)
npm install
npm run dev                      # opens http://localhost:51852
```

A full hand against the in-browser bot costs ~0.015 Sepolia ETH in bot gas
plus ~0.005 for your own txs. Hit a
[Sepolia faucet](https://www.alchemy.com/faucets/ethereum-sepolia) if your
wallet is dry. See [`frontend/README.md`](./frontend/README.md) for more.

For a deeper look at the protocol, see
[`docs/ARCHITECTURE.md`](./docs/ARCHITECTURE.md) (three-layer diagram with
the demoMode asterisks called out) and
[`docs/WALKTHROUGH.md`](./docs/WALKTHROUGH.md) (guided tour of five
hotspots: the shuffle circuit, the state machine guard, the reveal
invariant, the demoMode dealing short-circuit, and the `/proof-demo`
in-browser proving pipeline).

### `/proof-demo`: real ZK, no demoMode

The main table runs in `demoMode = true`. To show that the Noir toolchain
actually produces sound proofs against a real on-chain verifier, visit
`http://localhost:51852/proof-demo`. The page:

1. Loads the `reveal` circuit artifact into `@noir-lang/noir_js`.
2. Generates a real UltraPlonk proof in the browser via `@aztec/bb.js`.
3. Self-verifies it.
4. Calls `verify(bytes, bytes32[])` on the live Sepolia `RevealVerifier`.
5. Lets you flip one public input ("tamper") and watch the verifier revert
   with the pairing-check selector `0xd71fd263`.

Same pipeline reproducible from the shell:

```bash
just verify-e2e     # bb.js prove + self-verify, Foundry suite, live Sepolia honest vs. tampered
```

**Important: act within 120 seconds when it's your turn.** The contract
enforces a per-phase deadline. Past 120s, every action reverts with
"deadline passed" and only `claimTimeout` works (the UI surfaces a Claim
Timeout button in the header).

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
│   ├── test/                # Foundry test suite (incl. RevealVerifier.t.sol)
│   ├── script/              # Deploy scripts (incl. DeployRevealVerifier.s.sol)
│   └── deployments/         # Per-chain address registry
├── prover/                  # bb.js reveal-proof fixture generator (Node)
├── scripts/verify-e2e.sh    # Three-stage demo-day ZK pipeline check
├── justfile                 # just verify-e2e, just test-reveal, etc.
├── frontend/                # Vite + React + wagmi + RainbowKit
│   ├── src/
│   │   ├── pages/           # Lobby, Table, Spectator, ProofDemo
│   │   ├── components/      # Card, Seat, ActionBar, ZKReveal, OddsBar, CheatMoment, etc.
│   │   ├── hooks/           # usePokerTable, useGameActions, useAutoSubmit, useDemoBot
│   │   ├── bot/             # Ephemeral-key auto-opponent + pokersolver brain
│   │   └── utils/           # zkLog, demoPayloads, deal, gas, contracts
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
- **No external audit yet.** Correctness is gated by 93 Foundry tests, 17
  Noir tests, and a standalone Sepolia verifier that accepts real reveal
  proofs and rejects tampered ones (see `/proof-demo`).
- **Verifier contracts are gas-heavy** and may exceed EIP-170 size limits at
  L1; L2 deployment untested. When `demoMode` flips to false, the per-tx
  gas overrides in `frontend/src/utils/gas.ts` need to be bumped to cover
  real Plonk verification (~250-300k extra per decrypt card).

## License

MIT (intent; LICENSE file pending).
