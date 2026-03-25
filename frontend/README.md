# Frontend

React web application for interacting with the NoirLimit poker protocol.

## Directory Structure

```
frontend/
├── public/                  # Static files (index.html, favicon, etc.)
├── src/
│   ├── components/          # Reusable UI components
│   │   ├── Table/           # Poker table rendering (cards, pot, players)
│   │   ├── Hand/            # Player hand display
│   │   ├── BettingControls/ # Fold/Check/Call/Raise UI
│   │   ├── SpectatorPanel/  # Spectator wager interface
│   │   ├── GameLog/         # Action history feed
│   │   └── WalletConnect/   # Wallet connection button
│   │
│   ├── hooks/               # Custom React hooks
│   │   ├── usePokerContract.ts   # Hook for poker contract interactions
│   │   ├── useSpectatorMarket.ts # Hook for spectator wager contract
│   │   ├── useProofGeneration.ts # Hook wrapping Noir proof generation
│   │   └── useGameState.ts       # Hook for subscribing to game state events
│   │
│   ├── utils/               # Helper functions
│   │   ├── noir.ts          # Noir WASM proof generation wrapper
│   │   ├── cards.ts         # Card encoding/decoding and display helpers
│   │   ├── contracts.ts     # Contract address constants and init
│   │   └── crypto.ts        # Commitment scheme helpers (client-side)
│   │
│   ├── pages/               # Page-level components
│   │   ├── Lobby.tsx        # Game lobby - join/create tables
│   │   ├── Table.tsx        # Active poker table view
│   │   └── Spectator.tsx    # Spectator-only view with wagering
│   │
│   ├── assets/              # Static assets (card images, sounds, etc.)
│   ├── abi/                 # Contract ABI JSON files (copied from build artifacts)
│   ├── App.tsx              # Root app component
│   └── main.tsx             # Entry point
│
├── package.json
├── tsconfig.json
└── vite.config.ts           # Vite bundler config
```

## Architecture

### Player Flow

1. **Connect wallet** via WalletConnect/MetaMask
2. **Lobby** - Browse open tables or create a new one (set buy-in, blinds)
3. **Join table** - Send buy-in transaction to PokerTable contract
4. **Play hand**:
   - Participate in shuffle protocol (generate + submit shuffle proof)
   - Receive dealt cards (decrypt card commitment locally)
   - Make betting actions (fold/check/call/raise)
   - At showdown, generate reveal proof for hand
5. **Collect winnings** - Contract distributes pot automatically

### Spectator Flow

1. **Connect wallet**
2. **Browse active tables** from the lobby
3. **Watch a game** - See community cards, pot, player actions (but NOT player hands)
4. **Place wagers** on outcomes through the SpectatorPanel
5. **Collect winnings** when the hand resolves

### Client-Side Proof Generation

The most critical piece of the frontend is the Noir proof generation. Proofs are generated in the browser using Noir's WASM backend:

```
Player action -> Build circuit inputs -> Generate proof (WASM) -> Submit proof to contract
```

This is the main performance bottleneck. Proof generation can take several seconds depending on circuit complexity and device hardware.

## Tech Stack

- **React** with TypeScript
- **Vite** for bundling
- **ethers.js** or **viem** for contract interaction
- **@noir-lang/noir_js** for client-side proof generation
- **@noir-lang/backend_barretenberg** for the proving backend

## Getting Started

```bash
npm install
npm run dev     # Start dev server
npm run build   # Production build
npm run preview # Preview production build
```

## Key Considerations

- **Proof generation is CPU-intensive** - need loading states and possibly web workers
- **Card images/assets** should be minimal since this is an MVP
- **Dark, minimal UI** - clean table view, clear betting controls
- **Mobile is out of scope** for MVP - desktop only
