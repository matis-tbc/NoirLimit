use std::hash::pedersen_hash;

pub global DECK_SIZE: u32 = 52;

// Domain separation constants for different hash contexts
global KEYGEN_DOMAIN: Field = 113;
global SHARE_DOMAIN: Field = 131;
global MASK_DOMAIN: Field = 97;
global DECK_DOMAIN: Field = 71;

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

pub fn hash2(left: Field, right: Field) -> Field {
    pedersen_hash([left, right])
}

pub fn hash3(a: Field, b: Field, c: Field) -> Field {
    pedersen_hash([a, b, c])
}

// Domain-separated hash for masking
pub fn mask_from_randomizer(randomizer: Field) -> Field {
    hash2(randomizer, MASK_DOMAIN)
}

pub fn commit_card(card: Card, secret_nonce: Field) -> Field {
    hash2(card as Field, secret_nonce)
}

pub fn encrypt_card(card: Card, secret_nonce: Field, mask_randomness: Field) -> EncryptedCard {
    let card_commitment = commit_card(card, secret_nonce);
    let mask = mask_from_randomizer(mask_randomness);

    EncryptedCard {
        card_commitment,
        randomizer: mask_randomness,
        masked_payload: card_commitment + mask,
    }
}

pub fn rerandomize_card(previous: EncryptedCard, rerandomization: Field) -> EncryptedCard {
    let new_randomizer = previous.randomizer + rerandomization;
    let previous_mask = mask_from_randomizer(previous.randomizer);
    let new_mask = mask_from_randomizer(new_randomizer);

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
    hash2(player_secret_key, KEYGEN_DOMAIN)
}

pub fn partial_decryption_share(
    encrypted_card: EncryptedCard,
    player_secret_key: Field,
) -> Field {
    let key_stream = hash2(player_secret_key, encrypted_card.randomizer);
    let card_binding = hash2(encrypted_card.card_commitment, encrypted_card.masked_payload);
    hash2(hash2(key_stream, card_binding), SHARE_DOMAIN)
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
    hash3(card.card_commitment, card.randomizer, card.masked_payload)
}

pub fn deck_commitment<let N: u32>(deck: [EncryptedCard; N]) -> Field {
    let mut state = hash2(N as Field, DECK_DOMAIN);

    for i in 0..N {
        let card_hash = hash_encrypted_card(deck[i]);
        state = hash2(state, card_hash);
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

pub fn assert_full_deck_fixture_valid() {
    let deck = ordered_encrypted_deck::<DECK_SIZE>(0, 5000, 9000);
    assert(deck[0].card_commitment != 0, "first card should be populated");
    assert(deck[DECK_SIZE - 1].card_commitment != 0, "last card should be populated");
    assert(deck_commitment(deck) != 0, "deck should hash cleanly");
}
