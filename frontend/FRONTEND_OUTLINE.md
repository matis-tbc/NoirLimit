# NoirLimit Frontend Outline

## Tech Stack

- React + TypeScript + Vite
- wagmi v2 + viem (wallet connection + contract interaction)
- @tanstack/react-query (async state)
- Tailwind CSS (dark theme matching Mach Industries aesthetic)

## Setup

```bash
cd frontend
npm create vite@latest . -- --template react-ts
npm install wagmi viem @tanstack/react-query @rainbow-me/rainbowkit
npm install -D tailwindcss @tailwindcss/vite
```

## Contract Integration

- Copy ABI from `contracts/out/PokerTable.sol/PokerTable.json` into `src/abi/`
- Contract addresses stored in `src/config/contracts.ts` (per-chain)
- wagmi hooks auto-generated from ABI

## Pages

### 1. Lobby (`/`)

```
+--------------------------------------------------+
| NoirLimit                    [Connect Wallet]     |
+--------------------------------------------------+
|                                                   |
|  Create Table                                     |
|  [Buy-in: ___ ETH]  [Big Blind: ___ ETH]         |
|  [Create Table]                                   |
|                                                   |
|  Open Tables                                      |
|  +----------------------------------------------+ |
|  | Table #0 | 1 ETH buy-in | Waiting for P2    | |
|  |                              [Join]          | |
|  +----------------------------------------------+ |
|  | Table #1 | 0.5 ETH      | In Progress       | |
|  |                              [Watch]         | |
|  +----------------------------------------------+ |
+--------------------------------------------------+
```

**Data flow:**
- Read `nextTableId` to get table count
- Loop and call `getTable(i)` for each
- Filter by state (WAITING = joinable, others = watchable)
- `createTable` write call with ETH value
- `joinTable` write call matching buy-in

### 2. Table (`/table/:id`)

```
+--------------------------------------------------+
| Table #0                              Pot: 0.4 ETH|
+--------------------------------------------------+
|                                                   |
|   Player 2 (0x709...79C8)                         |
|   Stack: 0.8 ETH                                  |
|   [??] [??]     <- face-down cards                |
|                                                   |
|   Community Cards                                 |
|   [Qc] [9d] [6h] [5s] [ ]                        |
|                                                   |
|   Player 1 (0xf39...2266) <-- you                 |
|   Stack: 0.8 ETH                                  |
|   [Ac] [Ad]     <- your cards (face-up)           |
|                                                   |
|   +--------------------------------------------+  |
|   | [Fold]  [Check]  [Call 0.1]  [Raise ___]  |  |
|   +--------------------------------------------+  |
|                                                   |
|   Phase: FLOP_BET | Your turn                     |
+--------------------------------------------------+
```

**Data flow:**
- Poll `getTable(id)` every 2 seconds (or use event subscription)
- Display state-appropriate controls:
  - WAITING: "Waiting for opponent..."
  - SHUFFLE: "Shuffling deck..." (auto-submit in demoMode)
  - DEALING: "Dealing cards..." (auto-submit in demoMode)
  - BETTING: Show fold/check/call/raise buttons
  - REVEAL: "Revealing community cards..." (auto-submit)
  - SHOWDOWN: "Revealing hands..." (submit revealHand)
  - SETTLED: Show winner + final balances
- Card display: map uint8 card IDs to suit+rank images
  - rank = cardId % 13 (0=2, 1=3, ..., 12=A)
  - suit = cardId / 13 (0=clubs, 1=diamonds, 2=hearts, 3=spades)
- `act(tableId, action, raiseAmount)` for betting

### 3. Spectator (`/table/:id/watch`) -- stretch

Read-only version of Table page + wager controls if SpectatorMarket is deployed.

## Key Components

```
src/
  abi/
    PokerTable.json          # from forge build output
  config/
    contracts.ts             # addresses per chain (localhost, sepolia)
    wagmi.ts                 # wagmi config (chains, transports, connectors)
  components/
    ConnectButton.tsx         # wallet connect
    Card.tsx                  # single card display (face-up or face-down)
    CommunityCards.tsx        # 5-card board
    PlayerSeat.tsx            # avatar + stack + hole cards
    BettingControls.tsx       # fold/check/call/raise buttons
    PhaseIndicator.tsx        # current game phase label
    TableList.tsx             # lobby table listing
  hooks/
    usePokerTable.ts          # read table state, poll/subscribe
    useGameActions.ts         # write hooks (createTable, joinTable, act, etc.)
  pages/
    Lobby.tsx
    Table.tsx
  App.tsx                     # router
  main.tsx                    # entry point
```

## Card Rendering

Card values are uint8 (0-51):
```
rank = id % 13    -> 0:"2" 1:"3" 2:"4" ... 10:"Q" 11:"K" 12:"A"
suit = id / 13    -> 0:"clubs" 1:"diamonds" 2:"hearts" 3:"spades"
```

Use unicode suit symbols for quick MVP: clubs, diamonds, hearts, spades
Color: red for diamonds/hearts, white for clubs/spades on dark background

## Phase-Specific UI Logic

| Phase | UI State | Action Required |
|-------|----------|-----------------|
| WAITING | "Waiting for opponent" | None (or show join button if not your table) |
| SHUFFLE_P1/P2 | "Shuffling deck..." spinner | Auto-submit shuffle in demoMode |
| DEALING | "Dealing cards..." spinner | Auto-submit decrypt in demoMode |
| PREFLOP | Show betting controls | Player action |
| FLOP_REVEAL | "Revealing flop..." | Auto-submit community card decrypt |
| FLOP_BET | Show betting controls | Player action |
| TURN_REVEAL | "Revealing turn..." | Auto-submit |
| TURN_BET | Show betting controls | Player action |
| RIVER_REVEAL | "Revealing river..." | Auto-submit |
| RIVER_BET | Show betting controls | Player action |
| SHOWDOWN | "Revealing hands..." | Submit revealHand |
| SETTLED | Show winner, final stacks | "Play Again" button |

## Demo Mode Flow

When connected to a demoMode contract (detected via `poker.demoMode()` read):
- Shuffle/decrypt/reveal phases auto-submit with empty proofs
- Frontend handles all ZK phase submissions automatically
- Player only interacts during betting and showdown
- This makes the demo playable without any proof generation

## Dark Theme

Match Mach Industries aesthetic:
- Background: near-black (#0a0a0a)
- Card table: dark green (#0d2818)
- Text: off-white (#e5e5e5)
- Accent: gold (#c9a227) for pot amounts and winner highlights
- Cards: white face on dark border
- Buttons: subtle borders, no fills, hover glow

## Events to Subscribe

For real-time updates, watch these contract events:
- `TableCreated` -- new table in lobby
- `PlayerJoined` -- opponent joined, game starts
- `ShuffleSubmitted` -- shuffle phase progress
- `DecryptSubmitted` -- deal/reveal progress
- `ActionTaken` -- betting actions
- `CommunityCardsRevealed` -- flop/turn/river
- `HandRevealed` -- showdown cards
- `HandSettled` -- game over, show winner
