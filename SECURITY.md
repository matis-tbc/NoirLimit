# Security & Limitations

NoirLimit is a research and demo artifact, not a production protocol. Do not
use it with real funds. This document enumerates the known limitations and
the threat model boundary.

## Demo posture (Sepolia testnet only)

- The deployed PokerTable at `0x6Ccaf05ac50eABE2c90b8187b9B6734dCB0E88eC`
  runs in `demoMode = true`.
- The injected verifier is `MockVerifier`, which **accepts any proof bytes**
  including the empty string. No zero-knowledge guarantees apply on this
  deployment.
- Buy-ins are denominated in Sepolia ETH. Sepolia ETH has no monetary value.
- Do not point this code at mainnet without first deploying real verifier
  contracts and setting `demoMode = false` in the constructor.

## Hole card disclosure (demo mode only)

In demo mode, the frontend derives hole cards client-side from a deterministic
seed:

```
seed = keccak256(abi.encodePacked(tableId, players[0], players[1]))
```

All inputs to that seed are public on-chain. **Any observer can compute both
players' hole cards from the public chain state**. This is acceptable for a
demo whose contract already accepts mock proofs; it would be unacceptable in
production.

The real-proof path (out of scope for this demo build) would replace the
deterministic deal with the partial-decryption protocol implemented in the
Noir circuits.

## Bot wallet key storage

Bot mode generates an ephemeral private key in the user's browser via
`generatePrivateKey()` and persists it in `localStorage` under the key
`noirlimit:bot-key:<host-address>`. Implications:

- **Plaintext storage.** Any same-origin XSS or malicious browser extension
  can read it.
- **Bound to browser.** Clearing site data permanently destroys the key and
  any Sepolia ETH it holds. The lobby provides a "Sweep to host" button that
  drains the bot back to your connected wallet; use it before clearing data.
- **Sepolia-only.** The frontend's chain is hardcoded to Sepolia. The
  `FundBotPanel` checks `chainId === sepolia.id` before sending funds.

For a production deployment we would either: prompt the user to sign for each
bot action (defeats the auto-play UX), or move the bot to a server-side
service whose key is held by the operator.

## No external audit

The Solidity contracts and Noir circuits have not been audited. The contract
test suite (90 Foundry tests + 17 Noir tests) is the only correctness gate.
Recent review items:

- `SpectatorMarket.claimWinnings` reentrancy: **fixed in source** via a
  `nonReentrant` modifier in `contracts/src/SpectatorMarket.sol` backed by a
  minimal in-tree guard at `contracts/src/ReentrancyGuard.sol`. Verified by
  `test_reentrancy_blocked` in `contracts/test/SpectatorMarket.t.sol`. The
  live deployment at `0x666898...` predates this fix and runs unguarded; the
  CEI pattern at `claimWinnings:122` (state lock set before the external
  call) keeps the live build practically safe until a redeploy.
- `SpectatorMarket` claim-by-loser path (zero payout): still not explicitly
  tested; flagged for the post-demo infra phase.
- `SpectatorMarket` late wager arriving in the same block as phase advance:
  not tested; flagged for the post-demo infra phase.

## Threat model boundary

In scope for this demo:
- Public-input correctness in the demo flow (card index validation, reveal
  card uniqueness, no-overlap with community cards)
- Two-player turn enforcement and phase machine integrity
- Pot accounting and timeout settlement

Out of scope:
- Front-running (no MEV protection)
- RPC trust (bot uses the configured Alchemy endpoint; a malicious RPC could
  see all txs from the bot key)
- Wallet vendor security
- Side channels (timing, gas usage by branch, etc.)
- Correctness of the mocked verifier (by definition: it accepts everything)

## Reporting issues

Open a GitHub issue for non-sensitive bugs. For anything that looks like a
real exploit primitive (even on Sepolia), reach out privately first.
