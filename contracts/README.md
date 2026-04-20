# Contracts

Solidity smart contracts for the NoirLimit poker protocol. Built with [Foundry](https://book.getfoundry.sh/).

## Directory Structure

```
contracts/
├── src/
│   ├── PokerTable.sol           # 14-state game machine, betting, timeouts, payouts
│   ├── SpectatorMarket.sol      # Spectator winner-prediction wagering market
│   ├── HandEvaluator.sol        # Poker hand ranking (best 5 of 7, all 9 hand types)
│   ├── interfaces/
│   │   ├── IPokerTable.sol      # Full interface: state enum, actions, events, external API
│   │   ├── ISpectatorMarket.sol # Spectator wagering interface
│   │   └── IVerifier.sol        # Common ZK proof verifier interface
│   └── mocks/
│       ├── MockVerifier.sol     # Always-accept verifier for testing
│       └── RejectingVerifier.sol # Always-reject verifier for testing
├── test/
│   ├── PokerTable.t.sol         # 55 tests: lifecycle, betting, timeouts, showdown
│   ├── SpectatorMarket.t.sol    # 19 tests: wager placement, resolution, refunds, payouts
│   └── HandEvaluator.t.sol      # 15 tests: all hand types, tiebreakers, best-of-7
├── lib/
│   └── forge-std/               # Foundry test framework (git submodule)
└── foundry.toml                 # Foundry config (solc 0.8.24, via_ir, optimizer)
```

## Architecture

`PokerTable.sol` implements `IPokerTable` and manages the full hand lifecycle:

```
WAITING -> SHUFFLE_P1 -> SHUFFLE_P2 -> DEALING -> PREFLOP ->
FLOP_REVEAL -> FLOP_BET -> TURN_REVEAL -> TURN_BET ->
RIVER_REVEAL -> RIVER_BET -> SHOWDOWN -> SETTLED
```

Each phase has a 120-second timeout. Stalling players forfeit.

Three ZK verifier contracts (shuffle, decrypt, reveal) are injected via constructor. Generated verifiers are gitignored; regenerate with `bb` (see `docs/archive/PLAN-original.md`).

`submitDecrypt` is intentionally per-card for this MVP:
- it verifies each proof against the stored encrypted tuple for that card index
- it stores the partial decryption share by player and card index
- it only accepts `cardValues` during community reveal phases, never during `DEALING`

Hole-card recovery stays off-chain. The contract is the source of truth for encrypted tuples and partial decrypt shares, while clients reconstruct openings locally and only reveal them later at showdown.

`HandEvaluator.sol` is a pure library that scores any 7-card hand by checking all 21 five-card combinations.

`SpectatorMarket.sol` is a separate pari-mutuel winner market:
- spectators can back either seated player before betting begins
- wagers resolve once the linked poker hand reaches `SETTLED` or `CANCELLED`
- winning spectators claim a proportional share of the pool, while cancelled or split hands refund wagers

## Build and Test

```bash
forge build    # compile contracts
forge test     # run all 89 tests
forge test -vv # verbose output with gas
```
