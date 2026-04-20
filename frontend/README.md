# NoirLimit Frontend

Demo frontend for the NoirLimit ZK poker protocol. Targets the Sepolia
deployment of `PokerTable` running in `demoMode=true` (mock verifier
accepts empty proofs).

## Stack

React + TypeScript + Vite, wagmi v2 + viem, RainbowKit, Tailwind.

## Setup

```bash
cp .env.example .env.local
# fill in VITE_SEPOLIA_RPC (Alchemy / Infura / etc.)
# optional: VITE_WALLETCONNECT_PROJECT_ID (silences a console warning)
npm install
npm run dev
```

Visit http://localhost:51852.

## Modes

- **Bot mode** (default, opens with `?bot=1`): an in-app ephemeral wallet
  plays the opponent. Key generated on first connect, persisted in
  `localStorage` keyed by your host wallet address. Click "Fund 0.005 ETH"
  in the Lobby before creating a table; the bot needs buy-in + gas. Sweep
  funds back to your host with the "Sweep to host" button before clearing
  browser storage.
- **Manual mode**: open the app in a second browser profile with a
  different Sepolia wallet, find the table in the Tables list, click Join.

A full hand is ~17 sequential Sepolia transactions and takes ~2-3 minutes
end to end. **Act within 120 seconds when it's your turn**: the contract
enforces a per-phase deadline. If you blow past it, every action reverts
with "deadline passed" and only the Claim Timeout button (in the header)
will recover the table.

## Spectator market

Already deployed and live at
[`0x666898f7706ddd0193012aEc50EAF7D2E9FCbAf0`](https://sepolia.etherscan.io/address/0x666898f7706ddd0193012aEc50EAF7D2E9FCbAf0)
on Sepolia. The address is wired in `.env.example` so a fresh
`cp .env.example .env.local` makes the spectator page live without
extra steps.

If you redeploy your own SpectatorMarket pointing at the existing
PokerTable:

```bash
cd ../contracts
export PRIVATE_KEY=$YOUR_KEY
export ETHERSCAN_API_KEY=$YOUR_ETHERSCAN_KEY
POKER_TABLE=0x6Ccaf05ac50eABE2c90b8187b9B6734dCB0E88eC \
  forge script script/DeploySpectator.s.sol \
  --rpc-url $SEPOLIA_RPC --broadcast --verify
```

Then update `VITE_SPECTATOR_MARKET_ADDRESS` in `frontend/.env.local`.

## Demo-mode design notes

- All ZK phases (`registerPublicKey`, `submitShuffle`, `submitDecrypt`,
  `revealHand`) are auto-submitted with deterministic dummy payloads.
- Hole and community cards are picked client-side from a deterministic
  seed (`keccak256(tableId, p1, p2)`) so both players and the bot agree
  on the deal. Anyone watching the chain can recompute these in demo mode
  - acceptable for a demo, not for real value (see `../SECURITY.md`).
- Community cards are fixed per the deterministic deal: flop `[10, 21, 31]`,
  turn `[43]`, river `[0]`.
- Per-tx gas limits live in `src/utils/gas.ts` (shared between bot writes
  and user-side writes). Bumped from viem's auto-estimate after a
  documented OOG at FLOP_REVEAL.

## Verify chain state from CLI

```bash
cd ..
NODE_PATH=./frontend/node_modules npx tsx scripts/verify-table.ts <tableId> \
  --bot 0xYOUR_BOT_ADDRESS
```

Prints current phase, players, stacks, pot, recent events, spectator
market state, and a verdict (progressing / slow / stuck / settled).
Useful when the UI is unclear.
