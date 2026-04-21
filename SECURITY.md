# Security & Limitations

NoirLimit is a testnet demo. This document states what is verified, what is
deferred, and where the trust boundaries sit.

## What is verified

**Noir circuits (off-chain).** The shuffle, decrypt, and reveal circuits each
have a `nargo test` suite with positive and negative cases. 17 tests total.
A valid shuffle proof verifies; a tampered rerandomization fails; a bogus
reveal fails.

**Solidity contracts.** 90 Foundry tests cover every phase transition, every
timeout branch, min-raise and all-in cases, split pots, the hand evaluator's
5-of-7 ranking (including wheel-straight and broadway), and the
SpectatorMarket pari-mutuel math. A reentrancy attacker contract is tested
against `claimWinnings` and blocked.

**Cross-layer correctness.** The public inputs packed by each circuit match
what `PokerTable.sol` passes to `verifier.verify()` at the three proof sites
(`submitShuffle`, `submitDecrypt`, `revealHand`). These can be inspected side
by side in `circuits/*/src/main.nr` and `contracts/src/PokerTable.sol`.

**Cheat path.** The `<CheatMoment>` component submits an intentionally-invalid
`revealHand` and the contract rejects it on-chain. Available during the
SHOWDOWN phase.

## Demo-mode tradeoff

The deployed PokerTable at
`0x6Ccaf05ac50eABE2c90b8187b9B6734dCB0E88eC` was constructed with
`demoMode = true`. This flag turns three on-chain checks into short-circuits:

```solidity
require(demoMode || someVerifier.verify(proof, pub), "bad ... proof");
```

Those three sites are:
- `submitShuffle` at `PokerTable.sol:237`
- `revealHand` at `PokerTable.sol:403`
- `submitDecrypt` at `PokerTable.sol:484`

With `demoMode = true`, the `MockVerifier` (`contracts/src/mocks/MockVerifier.sol`)
is wired as the verifier and returns `true` for any bytes, including the
empty string. The Noir proofs are not checked on-chain.

**Why this exists.** Real Plonk verifier contracts generated from `bb` are
200-300 KB each and push against EIP-170 code-size limits on L1. In-browser
proof generation takes tens of seconds per card. A full hand with real
proofs costs ~0.05+ ETH and takes minutes of prover time. Demo mode reduces
a full hand to ~0.015 Sepolia ETH and ~3 minutes.

**What still runs in demo mode.** `revealHand` still checks that a player's
revealed cards do not duplicate each other, do not duplicate the community
cards, and are within range. The state machine gates phase transitions by
caller and by order. `CheatMoment` exercises these Solidity invariants; a
bogus reveal reverts on-chain. In a `demoMode = false` build the Noir
reveal circuit would reject the same attempt one layer earlier in the same
tx.

**Consequence of disabled proofs: hole cards are derivable.** Without a
verified partial-decryption protocol, the frontend derives hole cards from a
public deterministic seed:

```
seed = keccak256(abi.encodePacked(tableId, players[0], players[1]))
```

All seed inputs are public on-chain. Any observer can reconstruct both
players' hole cards from public state. Swapping this for the partial-
decryption protocol is part of the `demoMode = false` deploy.

## Open items

- **SpectatorMarket redeploy pending.** The source has a `nonReentrant`
  modifier on `claimWinnings` and a reentrancy forge test; the live
  `SpectatorMarket` at `0x666898...` predates that commit. `wager.claimed
  = true` is set before the external ETH transfer at
  `SpectatorMarket.sol:122` (checks-effects-interactions ordering).
- **Claim-by-loser zero-payout path.** `claimWinnings` returns zero for a
  losing wager; no test asserts the zero-payout branch directly. The
  math is covered by the winning-path tests.
- **Same-block wager edge.** A wager arriving in the same block as the
  phase advance that closes the wagering window has no targeted test.
  The state check in `placeWager` handles it; an explicit test would
  make the invariant visible.
- **No external audit.** 90 Foundry tests + 17 Noir tests are the
  correctness gate.

## Bot wallet key storage

Bot mode generates an ephemeral private key in the browser
(`generatePrivateKey()` from viem) and persists it in `localStorage` under
`noirlimit:bot-key:<host-address>`. `FundBotPanel` checks
`chainId === sepolia.id` before sending funds to the key, so the key only
ever receives Sepolia ETH.

Same-origin XSS or a malicious browser extension could read the key. The
key controls the bot seat at a table and holds Sepolia ETH. "Sweep to
host" in the Lobby transfers the key's balance back to the connected
wallet before clearing site data.

Production alternatives: per-action user signature, or a server-side bot
with operator-held keys.

## Threat model boundary

In scope for the demo:
- Public-input correctness in the demo flow: card index validation,
  reveal-card uniqueness, no overlap with community cards
- Two-player turn enforcement and phase-machine integrity
- Pot accounting, min-raise, all-in, split pot
- Deadline enforcement and `claimTimeout` settlement

Out of scope:
- On-chain cryptographic verification (by construction: the verifier
  accepts everything in demoMode)
- Front-running and MEV (no protection)
- RPC trust (the bot uses the configured Alchemy endpoint; a malicious
  RPC could see and censor bot txs)
- Wallet vendor security (MetaMask, Rainbow, etc.)
- Side channels (timing, branch-dependent gas, etc.)

## Reporting issues

Non-sensitive bugs: GitHub issues. Anything that looks like a real
exploit primitive, even on Sepolia: contact the team privately first.
