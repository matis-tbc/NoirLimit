# Poker Contracts

Core poker game logic contracts.

## Files to Implement

| File | Purpose |
|------|---------|
| `PokerTable.sol` | Main entry point. Manages table creation, player joins/leaves, hand lifecycle, proof submission routing, and pot distribution. |
| `GameState.sol` | State machine for hand phases: WAITING -> SHUFFLE -> DEAL -> BET (x4 rounds) -> SHOWDOWN -> PAYOUT. Enforces valid transitions. |
| `HandEvaluator.sol` | Evaluates 5-card poker hands from 7 cards (2 hole + 5 community). Returns a comparable rank for showdown winner determination. |

## Key Responsibilities

- **PokerTable**: Owns the game. Players call functions like `joinTable()`, `submitShuffleProof()`, `placeBet()`, `revealHand()`. It delegates proof verification to the verifier contracts and state tracking to GameState.
- **GameState**: Pure state machine. Tracks current phase, active players, community cards (as commitments until revealed), and betting round state (who has acted, current bet amount).
- **HandEvaluator**: Stateless library. Given 7 revealed card values, returns the best 5-card hand ranking. Used only at showdown when cards are proven via reveal circuits.

## Dependencies

- `../verifiers/` - Calls verifier contracts to validate ZK proofs
- `../libraries/CardLib.sol` - Card encoding/decoding
- `../libraries/BettingLib.sol` - Bet validation helpers
