# NoirLimit - Next Steps

## What's done

- PokerTable.sol: full state machine, betting, timeouts, payouts, duplicate card detection, safe transfers
- HandEvaluator.sol: all 9 hand types with tiebreakers
- 3 Noir circuits (shuffle, decrypt, reveal) with real Pedersen hash at 52-card scale
- 60 contract tests + 17 circuit tests, all passing
- Generated Solidity verifiers from circuits (gitignored, regenerate with bb)

## What needs to happen next

### 1. Fix decrypt proof public input mismatch

The contract's `submitDecrypt` passes 5 public inputs shaped like:
```
[deckCommitment, cardCommitments[0], cardCommitments[1], cardValuesLength, playerPublicKey]
```

But the decrypt circuit expects:
```
[encrypted_card_commitment, encrypted_card_randomizer, encrypted_card_masked_payload, partial_decryption, player_public_key]
```

These are completely different. The circuit operates per-card (single encrypted card in, partial decryption out). The contract operates per-phase (deck-level commitment).

To fix this, the contract needs to:
- Track individual encrypted card state from the shuffle phase (not just a deck commitment)
- Pass the specific encrypted card being decrypted as public inputs
- Store the partial decryption value from the proof
- Combine partial decryptions from both players to recover the card

This is the core protocol design work. Options:
- Store per-card encrypted state on-chain (52 cards x 3 fields = 156 storage slots, expensive)
- Use a Merkle tree of encrypted cards (single root on-chain, per-card proofs include Merkle path)
- Batch decrypt proofs (prove decryption of N cards in one proof)

### 2. Frontend

Design spec first, then build:
- Wallet connect (wagmi/viem)
- Table creation and join flow
- Proof generation in WebWorker (noir_js + barretenberg WASM)
- Game board with card display and betting controls
- Frame proof generation as "shuffling deck" / "dealing cards", never expose ZK terms

### 3. Testnet deployment

- Deploy verifier contracts (compile without via_ir)
- Deploy PokerTable with real verifier addresses
- End-to-end test on Sepolia

## Regenerating verifiers

```bash
# Requires nargo 0.39.0 and bb 0.63.1
cd circuits && nargo compile --workspace
bb write_vk -b target/shuffle.json -o target/shuffle_vk
bb contract -k target/shuffle_vk -o ../contracts/verifiers-generated/ShuffleVerifier.sol
bb write_vk -b target/decrypt.json -o target/decrypt_vk
bb contract -k target/decrypt_vk -o ../contracts/verifiers-generated/DecryptVerifier.sol
bb write_vk -b target/reveal.json -o target/reveal_vk
bb contract -k target/reveal_vk -o ../contracts/verifiers-generated/RevealVerifier.sol
```

Note: generated verifiers must be compiled without `via_ir` (heavy inline assembly is incompatible with the Yul optimizer).
