# Spectator Contracts

Spectator wagering market contracts.

## Files to Implement

| File | Purpose |
|------|---------|
| `SpectatorMarket.sol` | Wager placement, tracking, and resolution. Reads game outcomes from the PokerTable contract. |
| `OddsEngine.sol` | Calculates payout odds based on public game state (number of players, pot size, community cards). |

## Key Responsibilities

- **SpectatorMarket**: Spectators call `placeWager()` with their prediction and ETH. Wagers lock when the relevant game phase begins. After showdown, `resolveWagers()` distributes payouts to winners.
- **OddsEngine**: Provides odds for different wager types. For MVP, this can be simple (e.g., equal odds per player, adjusted by pot contribution).

## Wager Types (MVP)

For the MVP, support at minimum:
- **Winner prediction** - Bet on which player wins the hand

Future expansion could include:
- Hand type prediction (pair, flush, etc.)
- Over/under on final pot size
- Will there be an all-in?

## Dependencies

- `../poker/PokerTable.sol` - Reads game state and outcomes
- `../interfaces/IPokerTable.sol` - Interface for cross-contract calls
