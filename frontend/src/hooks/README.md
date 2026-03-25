# Hooks

Custom React hooks for contract interaction and proof generation.

## Hooks to Build

| Hook | Purpose |
|------|---------|
| `usePokerContract.ts` | Connects to PokerTable contract. Exposes `joinTable()`, `placeBet()`, `submitProof()`, etc. |
| `useSpectatorMarket.ts` | Connects to SpectatorMarket contract. Exposes `placeWager()`, `getOdds()`, etc. |
| `useProofGeneration.ts` | Wraps Noir WASM proof generation. Handles loading circuits, building inputs, generating proofs. Returns loading state. |
| `useGameState.ts` | Subscribes to contract events to track live game state (current phase, pot, community cards, player actions). |
