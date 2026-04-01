# Decrypt Circuit

Proves that a submitted partial-decryption share was computed correctly for a specific encrypted card.

## What This Proves

1. The decrypting player knows the secret key corresponding to their published public key
2. The submitted partial decryption share is the expected share for the encrypted card under that secret key
3. The proof binds the share to the full encrypted-card tuple, so tampering with any ciphertext field invalidates the proof

## Inputs

- **Public**:
  - `encrypted_card_commitment`
  - `encrypted_card_randomizer`
  - `encrypted_card_masked_payload`
  - `partial_decryption`
  - `player_public_key`
- **Private**:
  - `player_secret_key`

## Notes

- This package follows the placeholder ciphertext model already used by `shuffle/`.
- The key derivation and share arithmetic are intentionally SNARK-friendly stand-ins, not the final production threshold-decryption scheme.
- Once the team chooses the real mental-poker primitive, the helper functions in `common/` should be swapped while preserving the same high-level proof interface.
