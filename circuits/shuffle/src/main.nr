use common::{
    assert_is_valid_rerandomization,
    assert_scale_ready_fixture_pattern,
    assert_valid_permutation,
    deck_commitment,
    empty_encrypted_card,
    shuffled_rerandomized_deck,
    DECK_SIZE,
    EncryptedCard,
};

fn main(
    previous_deck_commitment: pub Field,
    new_deck_commitment: pub Field,
    previous_deck: [EncryptedCard; DECK_SIZE],
    new_deck: [EncryptedCard; DECK_SIZE],
    permutation: [u8; DECK_SIZE],
    rerandomization: [Field; DECK_SIZE],
) {
    assert(deck_commitment(previous_deck) == previous_deck_commitment, "previous deck commitment mismatch");
    assert(deck_commitment(new_deck) == new_deck_commitment, "new deck commitment mismatch");

    assert_valid_permutation(permutation);

    for i in 0..DECK_SIZE {
        let source_index = permutation[i] as u32;
        assert_is_valid_rerandomization(
            previous_deck[source_index],
            new_deck[i],
            rerandomization[i],
        );
    }
}

fn sample_previous_deck() -> [EncryptedCard; DECK_SIZE] {
    common::ordered_encrypted_deck::<DECK_SIZE>(0, 100, 1000)
}

fn identity_permutation() -> [u8; DECK_SIZE] {
    [0, 1, 2, 3, 4, 5, 6, 7]
}

fn nontrivial_permutation() -> [u8; DECK_SIZE] {
    [2, 5, 1, 7, 0, 6, 4, 3]
}

fn sample_rerandomization() -> [Field; DECK_SIZE] {
    [11, 13, 17, 19, 23, 29, 31, 37]
}

fn build_shuffle_case(
    permutation: [u8; DECK_SIZE],
    rerandomization: [Field; DECK_SIZE],
) -> (
    [EncryptedCard; DECK_SIZE],
    [EncryptedCard; DECK_SIZE],
    Field,
    Field,
) {
    let previous_deck = sample_previous_deck();
    let new_deck = shuffled_rerandomized_deck(previous_deck, permutation, rerandomization);
    let previous_commitment = deck_commitment(previous_deck);
    let new_commitment = deck_commitment(new_deck);

    (previous_deck, new_deck, previous_commitment, new_commitment)
}

#[test]
fn test_valid_identity_shuffle_with_rerandomization() {
    let permutation = identity_permutation();
    let rerandomization = sample_rerandomization();
    let (previous_deck, new_deck, previous_commitment, new_commitment) =
        build_shuffle_case(permutation, rerandomization);

    main(
        previous_commitment,
        new_commitment,
        previous_deck,
        new_deck,
        permutation,
        rerandomization,
    );
}

#[test]
fn test_valid_nontrivial_shuffle() {
    let permutation = nontrivial_permutation();
    let rerandomization = sample_rerandomization();
    let (previous_deck, new_deck, previous_commitment, new_commitment) =
        build_shuffle_case(permutation, rerandomization);

    main(
        previous_commitment,
        new_commitment,
        previous_deck,
        new_deck,
        permutation,
        rerandomization,
    );
}

#[test(should_fail_with = "permutation contains duplicate index")]
fn test_invalid_permutation_duplicate_index() {
    let permutation = [0, 1, 1, 3, 4, 5, 6, 7];
    let rerandomization = sample_rerandomization();
    let (previous_deck, new_deck, previous_commitment, new_commitment) =
        build_shuffle_case(identity_permutation(), rerandomization);

    main(
        previous_commitment,
        new_commitment,
        previous_deck,
        new_deck,
        permutation,
        rerandomization,
    );
}

#[test(should_fail_with = "permutation index out of range")]
fn test_invalid_permutation_out_of_range() {
    let permutation = [0, 1, 2, 3, 4, 5, 6, 8];
    let rerandomization = sample_rerandomization();
    let (previous_deck, new_deck, previous_commitment, new_commitment) =
        build_shuffle_case(identity_permutation(), rerandomization);

    main(
        previous_commitment,
        new_commitment,
        previous_deck,
        new_deck,
        permutation,
        rerandomization,
    );
}

#[test(should_fail_with = "rerandomized payload mismatch")]
fn test_invalid_rerandomization_for_one_card() {
    let permutation = nontrivial_permutation();
    let rerandomization = sample_rerandomization();
    let (previous_deck, new_deck, previous_commitment, _) =
        build_shuffle_case(permutation, rerandomization);

    let mut tampered_deck = new_deck;
    tampered_deck[3] = EncryptedCard {
        card_commitment: tampered_deck[3].card_commitment,
        randomizer: tampered_deck[3].randomizer,
        masked_payload: tampered_deck[3].masked_payload + 1,
    };
    let tampered_commitment = deck_commitment(tampered_deck);

    main(
        previous_commitment,
        tampered_commitment,
        previous_deck,
        tampered_deck,
        permutation,
        rerandomization,
    );
}

#[test(should_fail_with = "previous deck commitment mismatch")]
fn test_invalid_previous_deck_commitment() {
    let permutation = identity_permutation();
    let rerandomization = sample_rerandomization();
    let (previous_deck, new_deck, previous_commitment, new_commitment) =
        build_shuffle_case(permutation, rerandomization);

    main(
        previous_commitment + 1,
        new_commitment,
        previous_deck,
        new_deck,
        permutation,
        rerandomization,
    );
}

#[test(should_fail_with = "new deck commitment mismatch")]
fn test_invalid_new_deck_commitment() {
    let permutation = identity_permutation();
    let rerandomization = sample_rerandomization();
    let (previous_deck, new_deck, previous_commitment, new_commitment) =
        build_shuffle_case(permutation, rerandomization);

    main(
        previous_commitment,
        new_commitment + 1,
        previous_deck,
        new_deck,
        permutation,
        rerandomization,
    );
}

#[test]
fn test_scale_sanity_fixture_generator() {
    let placeholder = empty_encrypted_card();
    assert(placeholder.card_commitment == 0, "empty ciphertext baseline should stay stable");
    assert_scale_ready_fixture_pattern();
}
