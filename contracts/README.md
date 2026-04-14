# Contracts

Solidity smart contracts for the NoirLimit poker protocol. Built with [Foundry](https://book.getfoundry.sh/).

## Directory Structure

```
contracts/
├── src/
│   ├── PokerTable.sol           # 14-state game machine, betting, timeouts, payouts
│   ├── HandEvaluator.sol        # Poker hand ranking (best 5 of 7, all 9 hand types)
│   ├── interfaces/
│   │   ├── IPokerTable.sol      # Full interface: state enum, actions, events, external API
│   │   ├── ISpectatorMarket.sol # Spectator wagering interface (not yet implemented)
│   │   └── IVerifier.sol        # Common ZK proof verifier interface
│   └── mocks/
│       ├── MockVerifier.sol     # Always-accept verifier for testing
│       └── RejectingVerifier.sol # Always-reject verifier for testing
├── test/
│   ├── PokerTable.t.sol         # 45 tests: lifecycle, betting, timeouts, showdown
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

Three ZK verifier contracts (shuffle, decrypt, reveal) are injected via constructor. Generated verifiers are gitignored; regenerate with `bb` (see PLAN.md).

`HandEvaluator.sol` is a pure library that scores any 7-card hand by checking all 21 five-card combinations.

## Build and Test

```bash
forge build    # compile contracts
forge test     # run all 65 tests
forge test -vv # verbose output with gas
```
