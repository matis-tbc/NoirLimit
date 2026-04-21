# NoirLimit Code Walkthrough

A short tour of the four hotspots a ZK-literate reader probably wants to see
first. Each link is pinned to the release SHA so line numbers do not rot
after future edits.

**Pinned to commit:** `316306a` on `main`.
Re-verify with: `git rev-parse --short 316306a` should resolve, or update
this file when tagging a new release.

> If you are reading this on a later commit, check the corresponding tagged
> release (e.g. `v0.1-demo-walkthrough`) for the exact snapshot these
> references point at.

---

## 1. The shuffle circuit

**File:** [`circuits/shuffle/src/main.nr`](../circuits/shuffle/src/main.nr#L12), `fn main` at line 12.

The shuffle is the largest circuit (103,756 gates). It proves that a player
permuted an encrypted 52-card deck and rerandomized each card, without
revealing either the permutation or the rerandomization scalars. Each card
is represented as an ElGamal-style `(commitment, randomizer, masked_payload)`
triple. `main` takes the old deck plus the new deck, the claimed
permutation, and the rerandomization scalars, and enforces:

1. The permutation is valid (each index in `[0, 52)` appears exactly once).
2. For every output card, the `masked_payload` equals the permuted input's
   `masked_payload` plus a fresh scalar times the group generator.
3. Pedersen commitments are recomputed over the new encoding.

Both players run this in sequence (P1 then P2), so the final deck is
permuted by a composition of two private permutations. Neither side alone
knows the final order.

**Why this matters:** this is the only circuit that touches the full deck.
If it compiles and passes its negative tests (including
`test_invalid_rerandomization_for_one_card`), you can trust that the
re-encryption primitive used throughout the protocol is sound.

---

## 2. The state machine guard on `submitShuffle`

**File:** [`contracts/src/PokerTable.sol`](../contracts/src/PokerTable.sol#L213), `submitShuffle` at line 213.

The contract enforces that each phase transition is gated on the correct
seat, the correct predecessor phase, and a valid proof (in non-demoMode).
`submitShuffle` is the canonical example:

- `require(t.state == expectedState)` catches out-of-order submission.
- `require(msg.sender == expectedPlayer)` catches wrong-seat submission.
- `require(demoMode || shuffleVerifier.verify(proof, publicInputs))` is the
  place the Noir proof actually lands on-chain. In demoMode this line is a
  no-op.

The same pattern repeats for `submitDecrypt` and `revealHand`. The state
machine is tested end-to-end at
[`contracts/test/PokerTable.t.sol`](../contracts/test/PokerTable.t.sol) —
55 tests covering every phase, every timeout, every wrong-seat rejection.

---

## 3. The reveal invariant that catches a cheating player

**File:** [`contracts/src/PokerTable.sol`](../contracts/src/PokerTable.sol#L369), `revealHand` at line 369.

At showdown each player calls `revealHand(tableId, proof, cards)` with the
two hole cards they are claiming. The contract checks:

1. The cards are in `[0, 52)`.
2. The two hole cards are not equal to each other.
3. Neither hole card duplicates a community card.
4. (Non-demoMode only) A Noir proof that binds each claimed card back to
   its original encrypted commitment verifies.

Checks 1-3 are Solidity `require`s; they run regardless of demoMode. Check
4 is the ZK step. A player who submits cards they do not actually hold will
fail check 2 or 3 in the naive case, and will fail check 4 if they try to
construct commitment-matching cards they do not own.

**This is what the `<CheatMoment>` component in the frontend exercises.**
The demo intentionally submits `[51, 50]` (which duplicate the flop's
river card in the deterministic deal), so check 3 fires and the tx reverts.
In a real verifier deployment, check 4 would fire one layer earlier.

---

## 4. The demoMode dealing short-circuit

**File:** [`frontend/src/utils/deal.ts`](../frontend/src/utils/deal.ts#L27), `dealHoleCards` at line 27.

The frontend derives every player's hole cards from a deterministic seed:

```ts
const seed = keccak256(
  encodePacked(["uint256", "address", "address"], [tableId, p0, p1])
);
```

All inputs to the seed are public on-chain. This is acceptable for a demo
whose verifier already accepts any proof; it is unacceptable for real-value
play. `SECURITY.md` documents the limitation at length. The production
build would replace this function entirely with the partial-decryption
protocol implemented in `circuits/decrypt`.

The function is marked with an explicit banner in the source so it cannot
be accidentally used in a real-verifier build. If you are auditing the
frontend and wondering why both seats seem to know each other's cards in
demo mode: this is the reason.

---

## What to read next

If you are evaluating this as a reference implementation in Noir, the
three circuit `main.nr` files are the interesting surface. If you are
evaluating it as an on-chain protocol, `PokerTable.sol` plus
`SpectatorMarket.sol` (pari-mutuel wagering primitive, genuinely novel for
ZK poker) are where the state machine lives. If you are evaluating it as a
demo, watch the 90-second video linked from the project README first, then
come back to this file.
