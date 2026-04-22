# NoirLimit Architecture

Three layers. The interesting decisions live at the boundaries.

```
+-------------------------------------------------------------------------------------+
|                                                                                     |
|                                   NOIR CIRCUITS                                     |
|                                                                                     |
|   +------------------+    +------------------+    +------------------+              |
|   |   shuffle        |    |   decrypt        |    |   reveal         |              |
|   |   103,756 gates  |    |   3,351 gates    |    |   3,099 gates    |              |
|   |                  |    |                  |    |                  |              |
|   |   Re-encryption  |    |   Partial        |    |   Opens an       |              |
|   |   + permutation  |    |   decryption     |    |   encrypted card |              |
|   |   proof          |    |   share proof    |    |   commitment     |              |
|   +--------+---------+    +--------+---------+    +--------+---------+              |
|            |                       |                       |                        |
+------------|-----------------------|-----------------------|------------------------+
             |                       |                       |
             |  bb prove             |  bb prove             |  bb prove
             v                       v                       v
+-------------------------------------------------------------------------------------+
|                                                                                     |
|                              ON-CHAIN (Sepolia)                                     |
|                                                                                     |
|   +------------------------------+   +-------------------------------+              |
|   |     [ demoMode = true ]      |   |       PokerTable.sol          |              |
|   |  +------------------------+  |   |  +-------------------------+  |              |
|   |  |  MockVerifier          |  |   |  |  State machine:         |  |              |
|   |  |  accepts ANY bytes     +--+-->|  |  WAITING -> SHUFFLE_P1  |  |              |
|   |  |  incl. empty string    |  |   |  |    -> SHUFFLE_P2        |  |              |
|   |  +------------------------+  |   |  |    -> DEALING           |  |              |
|   |   (Circuits bypassed.        |   |  |    -> PREFLOP ...       |  |              |
|   |    Contract invariants       |   |  |    -> SETTLED           |  |              |
|   |    still enforced.)          |   |  +-------------------------+  |              |
|   +------------------------------+   |  120s deadline per phase     |              |
|                                      |  claimTimeout for recovery   |              |
|                                      +---------------+---------------+              |
|                                                      |                              |
|                                                      | reads: getTable, getWinner   |
|                                                      v                              |
|                                      +-------------------------------+              |
|                                      |     SpectatorMarket.sol       |              |
|                                      |  Pari-mutuel on outcome.      |              |
|                                      |  Wagering open in             |              |
|                                      |  SHUFFLE/DEALING only.        |              |
|                                      |  nonReentrant on claim.       |              |
|                                      +-------------------------------+              |
|                                                                                     |
|                                      +-------------------------------+              |
|                                      |     HandEvaluator.sol         |              |
|                                      |  Best 5-of-7 ranking.         |              |
|                                      |  Pure library.                |              |
|                                      +-------------------------------+              |
|                                                                                     |
+----------------------------------------+--------------------------------------------+
                                         |
                                         | JSON-RPC (wagmi + viem)
                                         v
+-------------------------------------------------------------------------------------+
|                                                                                     |
|                               FRONTEND (Vite + React)                               |
|                                                                                     |
|   Lobby <---> Table <---> Spectator                                                 |
|                |                                                                    |
|                +-- useAutoSubmit    (auto-submits dummy ZK payloads in demoMode)   |
|                +-- useDemoBot       (ephemeral-wallet bot driver)                  |
|                +-- usePokerTable    (polling + events)                             |
|                +-- ZKReveal         (three-beat animation tied to tx lifecycle)    |
|                +-- CheatMoment      (the one moment ZK enforcement is visible)     |
|                +-- OddsBar + sparkline (Spectator)                                 |
|                |                                                                    |
|                +-- utils/deal.ts    (demoMode deterministic dealing --              |
|                |                     hole cards derived from                        |
|                |                     keccak256(tableId, p1, p2).                    |
|                |                     Documented in SECURITY.md.)                    |
|                +-- utils/zkLog.ts   (shared tx store; useSyncExternalStore)        |
|                                                                                     |
+-------------------------------------------------------------------------------------+
```

## Where the demoMode asterisk lives

Three places, called out explicitly:

- **MockVerifier.sol**: the deployed verifier accepts any bytes, including
  the empty string. The Noir circuits compile and pass their own tests, but
  on-chain their proofs are not checked.
- **utils/deal.ts**: hole cards are derived deterministically from the
  public tableId and player addresses. Any observer can recompute them from
  chain state. This is why SECURITY.md flags the demo as "no real-value
  play."
- **PokerTable.sol** gates all three verifier calls on
  `require(demoMode || verifier.verify(...))`. Flipping `demoMode` to false
  is a constructor-time decision and requires a new deployment with real
  verifier addresses.

## What's still enforced in demoMode

Contract invariants run regardless of demoMode:

- Phase transitions (no skipping WAITING -> SHOWDOWN without the intermediate
  txs).
- 120s per-phase deadline.
- Hole cards cannot duplicate each other or the community cards at
  `revealHand`.
- Shuffle and decrypt must come from the correct seat.
- Betting math (blinds, min-raise, all-in, pot accounting).
- Spectator market wagering window and payout distribution.

So a cheating attempt that tries to submit bogus hole cards at showdown is
caught, but by a Solidity `require`, not by the Noir `reveal` circuit. The
CheatMoment component in the frontend makes this visible.

## Standalone RevealVerifier (proof of ZK soundness)

The main table runs in demoMode, so the ZK path in `PokerTable.sol` is
bypassed. To keep the ZK claim honest and demo-able, a second verifier
lives alongside the table:

```
+-------------------------+        +----------------------------------+
|  circuits/reveal        |  bb    |  RevealVerifier.sol              |
|  3,099 gates            | ----> |  UltraPlonk, generated from       |
|  130 ACIR opcodes       |        |  circuits/reveal, deployed       |
|                         |        |  standalone (not wired to table) |
+-------------------------+        +----------------------------------+
                                                 ^
                                                 |
                 browser: bb.js prove + verify   |
                 `frontend/src/pages/ProofDemo`  |
                                                 |
                 shell: prover/prove-reveal.mjs  |
                 + scripts/verify-e2e.sh         |
```

Address: `0x8A6e6fb6e795a22d6eD4cB3922bDE5164B03BB51` on Sepolia.

`/proof-demo` in the frontend runs the full proving pipeline in the browser
(`@noir-lang/noir_js` + `@aztec/bb.js@0.63.1`), self-verifies, then calls
`verify(bytes, bytes32[])` on the live contract. Flipping one public input
makes the verifier revert with the pairing-check selector `0xd71fd263`.
`just verify-e2e` reproduces the same three boundaries from the shell:
bb.js self-verify, Foundry `RevealVerifierTest`, live Sepolia cast calls.

This is the piece a reviewer should read as "the Noir toolchain actually
produces sound proofs that a real EVM verifier enforces." It is kept
separate from the game contract so the demo path and the ZK path are
visibly orthogonal.

## Trust budget

A ZK-literate reviewer should read the demo as: "the contract state machine
and betting logic are real and tested; the ZK primitives are plumbed but
bypassed on-chain; dealing is not private in this posture." The novelty
this demo commits to is the spectator market primitive. Everything else is
reference implementation.

The standalone `RevealVerifier` + `/proof-demo` route is the counterweight:
it proves the Noir-to-EVM toolchain actually produces sound proofs, even
though the live table chooses not to check them. A production deployment
flips `demoMode` to false and points `PokerTable` at real verifiers for
shuffle, decrypt, and reveal, re-using the same proving pipeline.
