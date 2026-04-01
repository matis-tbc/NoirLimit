pub global DECK_SIZE: u32 = 8;
pub global FULL_DECK_SIZE: u32 = 52;

global HASH_C0: Field = 17;
global HASH_C1: Field = 29;
global HASH_C2: Field = 43;
global HASH_C3: Field = 71;
global HASH_C4: Field = 97;
global KEYGEN_DOMAIN: Field = 113;
global SHARE_DOMAIN: Field = 131;

pub type Card = u8;
pub type Deck<let N: u32> = [EncryptedCard; N];

pub struct EncryptedCard {
    pub card_commitment: Field,
    pub randomizer: Field,
    pub masked_payload: Field,
}

pub fn empty_encrypted_card() -> EncryptedCard {
    EncryptedCard {
        card_commitment: 0,
        randomizer: 0,
        masked_payload: 0,
    }
}

// Week 4 uses a poseidon-style placeholder hash so we can exercise shuffle semantics
// without committing to the final mental-poker primitive yet.
pub fn poseidonish_mix(left: Field, right: Field) -> Field {
    let x = left + HASH_C0;
    let y = right + HASH_C1;
    let sum = x + y + HASH_C2;
    (sum * sum * sum) + (x * y) + HASH_C3
}

pub fn poseidonish_mask(randomizer: Field) -> Field {
    poseidonish_mix(randomizer, HASH_C4)
}

pub fn commit_card(card: Card, secret_nonce: Field) -> Field {
    poseidonish_mix(card as Field, secret_nonce)
}

pub fn encrypt_card(card: Card, secret_nonce: Field, mask_randomness: Field) -> EncryptedCard {
    let card_commitment = commit_card(card, secret_nonce);
    let mask = poseidonish_mask(mask_randomness);

    EncryptedCard {
        card_commitment,
        randomizer: mask_randomness,
        masked_payload: card_commitment + mask,
    }
}

pub fn rerandomize_card(previous: EncryptedCard, rerandomization: Field) -> EncryptedCard {
    let new_randomizer = previous.randomizer + rerandomization;
    let previous_mask = poseidonish_mask(previous.randomizer);
    let new_mask = poseidonish_mask(new_randomizer);

    EncryptedCard {
        card_commitment: previous.card_commitment,
        randomizer: new_randomizer,
        masked_payload: previous.masked_payload - previous_mask + new_mask,
    }
}

pub fn assert_is_valid_rerandomization(
    previous: EncryptedCard,
    next: EncryptedCard,
    rerandomization: Field,
) {
    let expected = rerandomize_card(previous, rerandomization);

    assert(next.card_commitment == expected.card_commitment, "rerandomized commitment mismatch");
    assert(next.randomizer == expected.randomizer, "rerandomized randomizer mismatch");
    assert(next.masked_payload == expected.masked_payload, "rerandomized payload mismatch");
}

pub fn derive_player_public_key(player_secret_key: Field) -> Field {
    poseidonish_mix(player_secret_key, KEYGEN_DOMAIN)
}

pub fn partial_decryption_share(
    encrypted_card: EncryptedCard,
    player_secret_key: Field,
) -> Field {
    let key_stream = poseidonish_mix(player_secret_key, encrypted_card.randomizer);
    let card_binding = poseidonish_mix(encrypted_card.card_commitment, encrypted_card.masked_payload);
    poseidonish_mix(poseidonish_mix(key_stream, card_binding), SHARE_DOMAIN)
}

pub fn assert_valid_partial_decryption(
    encrypted_card: EncryptedCard,
    partial_decryption: Field,
    player_public_key: Field,
    player_secret_key: Field,
) {
    let expected_public_key = derive_player_public_key(player_secret_key);
    assert(player_public_key == expected_public_key, "player public key mismatch");

    let expected_share = partial_decryption_share(encrypted_card, player_secret_key);
    assert(partial_decryption == expected_share, "partial decryption mismatch");
}

pub fn hash_encrypted_card(card: EncryptedCard) -> Field {
    let with_commitment = poseidonish_mix(card.card_commitment, card.randomizer);
    poseidonish_mix(with_commitment, card.masked_payload)
}

pub fn deck_commitment<let N: u32>(deck: [EncryptedCard; N]) -> Field {
    let mut state = poseidonish_mix(N as Field, HASH_C0);

    for i in 0..N {
        let card_hash = hash_encrypted_card(deck[i]);
        state = poseidonish_mix(state, card_hash);
    }

    state
}

pub fn assert_valid_permutation<let N: u32>(permutation: [u8; N]) {
    for i in 0..N {
        let current = permutation[i] as u32;
        assert(current < N, "permutation index out of range");

        for j in 0..i {
            assert(permutation[i] != permutation[j], "permutation contains duplicate index");
        }
    }
}

pub fn ordered_encrypted_deck<let N: u32>(
    start_card: Card,
    secret_nonce_seed: Field,
    mask_randomness_seed: Field,
) -> [EncryptedCard; N] {
    let mut deck = [empty_encrypted_card(); N];

    for i in 0..N {
        let card_value = start_card + (i as u8);
        deck[i] = encrypt_card(
            card_value,
            secret_nonce_seed + (i as Field),
            mask_randomness_seed + (i as Field),
        );
    }

    deck
}

pub fn shuffled_rerandomized_deck<let N: u32>(
    previous_deck: [EncryptedCard; N],
    permutation: [u8; N],
    rerandomization: [Field; N],
) -> [EncryptedCard; N] {
    let mut new_deck = [empty_encrypted_card(); N];

    for i in 0..N {
        let source_index = permutation[i] as u32;
        new_deck[i] = rerandomize_card(previous_deck[source_index], rerandomization[i]);
    }

    new_deck
}

pub fn assert_scale_ready_fixture_pattern() {
    let deck_52 = ordered_encrypted_deck::<FULL_DECK_SIZE>(0, 5000, 9000);
    assert(deck_52[0].card_commitment != 0, "first full-deck fixture should be populated");
    assert(deck_52[51].card_commitment != 0, "last full-deck fixture should be populated");
    assert(deck_commitment(deck_52) != 0, "full-deck fixture should hash cleanly");
}
