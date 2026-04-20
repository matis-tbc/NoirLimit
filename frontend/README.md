# NoirLimit Frontend

Demo frontend for the NoirLimit ZK poker protocol. Targets the Sepolia deployment
of `PokerTable` running in `demoMode=true` (mock verifier accepts empty proofs).

## Stack
React + TypeScript + Vite, wagmi v2 + viem, RainbowKit, Tailwind.

## Setup

```bash
cp .env.example .env.local
# fill in VITE_SEPOLIA_RPC and (optional) VITE_WALLETCONNECT_PROJECT_ID
npm install
npm run dev
```

Visit http://localhost:51852.

## Modes

- **Bot mode** (default): an in-app ephemeral wallet plays the opponent. Stored
  in `localStorage` keyed by your connected address. Click "Fund 1.2 ETH" in the
  Lobby before creating a table - the bot needs gas + buy-in.
- **Manual mode**: open the app in a second browser profile with a different
  Sepolia wallet, find the table in the Tables list, click Join.

A full hand is 17 sequential Sepolia transactions and takes ~3-5 minutes.

## Spectator market

`VITE_SPECTATOR_MARKET_ADDRESS` defaults to the zero address. To enable
spectator wagering, deploy `SpectatorMarket` pointing at the existing PokerTable:

```bash
cd ../contracts
POKER_TABLE=0x6Ccaf05ac50eABE2c90b8187b9B6734dCB0E88eC \
  PRIVATE_KEY=$YOUR_KEY \
  forge script script/DeploySpectator.s.sol \
  --rpc-url $SEPOLIA_RPC --broadcast --verify
```

Copy the printed address into `frontend/.env.local`.

## Demo-mode design notes

- All ZK phases (`registerPublicKey`, `submitShuffle`, `submitDecrypt`,
  `revealHand`) are auto-submitted with deterministic dummy payloads.
- Hole and community cards are picked client-side from a deterministic seed
  (`keccak256(tableId, p1, p2)`) so both players and the bot agree on the deal.
- Community cards are fixed per the script: flop `[10, 21, 31]`, turn `[43]`,
  river `[0]`.
