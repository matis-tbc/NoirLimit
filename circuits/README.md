# Circuits

Noir zero-knowledge circuits for private card handling in NoirLimit. The repo is still early, so `REVIEWED_PLAN.md` is the protocol source of truth when older README text conflicts with current implementation.

## Current workspace

The circuits directory now contains a minimal Noir workspace:

```text
circuits/
├── Nargo.toml          # Workspace for active Noir packages
├── common/             # Shared shuffle types and helpers
│   ├── Nargo.toml
│   └── src/lib.nr
├── shuffle/            # Week 4 encrypt-shuffle prototype
│   ├── Nargo.toml
│   ├── Prover.toml
│   └── src/main.nr
├── decrypt/            # Week 4 partial decryption prototype
│   ├── Nargo.toml
│   └── src/main.nr
├── deal/               # Planned
├── bet/                # Planned / likely removed per reviewed plan
└── reveal/             # Planned
```

`common/`, `shuffle/`, and `decrypt/` are the active Noir packages today. The other directories remain planning scaffolds.

## Week 4 shuffle implementation

`shuffle/` now implements the first real vertical slice of the reviewed shuffle protocol:

- Public inputs: `previous_deck_commitment`, `new_deck_commitment`
- Private inputs: `previous_deck`, `new_deck`, `permutation`, `rerandomization`
- Constraints:
  - the previous and new deck commitments match the supplied decks
  - `permutation` is a valid permutation over the active deck size
  - each output card is a valid rerandomization of the selected input card

This is intentionally a **staged prototype**:

- The deck size is currently a small compile-time constant for witness and test practicality.
- The shared library also defines `FULL_DECK_SIZE = 52` and includes a scale-readiness fixture path so the API can grow to a full deck without redesign.
- The ciphertext and hashing model are a **SNARK-friendly placeholder**, not final production cryptography.

## Shared library

`common/` owns the reusable shuffle primitives:

- `Card = u8` card encoding
- `EncryptedCard` fixed-width ciphertext struct
- configurable deck constants
- deck commitment hashing
- permutation validation
- ordered deck fixture generation
- toy rerandomization helpers
- toy player key derivation and partial-decryption helpers

The current hash and ciphertext construction are poseidon-style placeholders designed to validate circuit structure first. They should be replaced later with the final mental-poker primitive once the team chooses the production encryption scheme.

## Week 4 decrypt implementation

`decrypt/` implements the new partial-decryption proof called for in `REVIEWED_PLAN.md`:

- Public inputs:
  - `encrypted_card_commitment`
  - `encrypted_card_randomizer`
  - `encrypted_card_masked_payload`
  - `partial_decryption`
  - `player_public_key`
- Private input:
  - `player_secret_key`
- Constraints:
  - the public key must match the private secret key
  - the partial decryption share must be the expected share for that encrypted card and secret key

Like shuffle, this is still a **placeholder cryptographic model**. The proof shape now matches the protocol flow, but the key/share arithmetic is intentionally toy until the production threshold-encryption primitive is selected.

## Build and test

Once the Noir toolchain is installed:

```bash
cd circuits
nargo check --workspace
nargo test --package shuffle
nargo test --package decrypt
```

Because the repo is still scaffold-heavy, verifier generation and broader integration work should still be scoped to the active packages.
