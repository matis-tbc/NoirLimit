use common::{
    assert_valid_partial_decryption,
    derive_player_public_key,
    encrypt_card,
    partial_decryption_share,
    EncryptedCard,
};

fn main(
    encrypted_card_commitment: pub Field,
    encrypted_card_randomizer: pub Field,
    encrypted_card_masked_payload: pub Field,
    partial_decryption: pub Field,
    player_public_key: pub Field,
    player_secret_key: Field,
) {
    let encrypted_card = EncryptedCard {
        card_commitment: encrypted_card_commitment,
        randomizer: encrypted_card_randomizer,
        masked_payload: encrypted_card_masked_payload,
    };

    assert_valid_partial_decryption(
        encrypted_card,
        partial_decryption,
        player_public_key,
        player_secret_key,
    );
}

fn sample_encrypted_card() -> EncryptedCard {
    encrypt_card(9, 444, 888)
}

fn sample_secret_key() -> Field {
    12345
}

#[test]
fn test_valid_partial_decryption_share() {
    let encrypted_card = sample_encrypted_card();
    let player_secret_key = sample_secret_key();
    let player_public_key = derive_player_public_key(player_secret_key);
    let partial_decryption = partial_decryption_share(encrypted_card, player_secret_key);

    main(
        encrypted_card.card_commitment,
        encrypted_card.randomizer,
        encrypted_card.masked_payload,
        partial_decryption,
        player_public_key,
        player_secret_key,
    );
}

#[test]
fn test_distinct_players_have_distinct_valid_shares() {
    let encrypted_card = sample_encrypted_card();

    let player_one_secret = 12345;
    let player_two_secret = 67890;

    let player_one_share = partial_decryption_share(encrypted_card, player_one_secret);
    let player_two_share = partial_decryption_share(encrypted_card, player_two_secret);

    assert(player_one_share != player_two_share, "different secret keys should not collapse to one share");

    main(
        encrypted_card.card_commitment,
        encrypted_card.randomizer,
        encrypted_card.masked_payload,
        player_one_share,
        derive_player_public_key(player_one_secret),
        player_one_secret,
    );

    main(
        encrypted_card.card_commitment,
        encrypted_card.randomizer,
        encrypted_card.masked_payload,
        player_two_share,
        derive_player_public_key(player_two_secret),
        player_two_secret,
    );
}

#[test(should_fail_with = "partial decryption mismatch")]
fn test_invalid_partial_decryption_share() {
    let encrypted_card = sample_encrypted_card();
    let player_secret_key = sample_secret_key();
    let player_public_key = derive_player_public_key(player_secret_key);
    let partial_decryption = partial_decryption_share(encrypted_card, player_secret_key) + 1;

    main(
        encrypted_card.card_commitment,
        encrypted_card.randomizer,
        encrypted_card.masked_payload,
        partial_decryption,
        player_public_key,
        player_secret_key,
    );
}

#[test(should_fail_with = "player public key mismatch")]
fn test_invalid_player_public_key() {
    let encrypted_card = sample_encrypted_card();
    let player_secret_key = sample_secret_key();
    let partial_decryption = partial_decryption_share(encrypted_card, player_secret_key);
    let player_public_key = derive_player_public_key(player_secret_key) + 1;

    main(
        encrypted_card.card_commitment,
        encrypted_card.randomizer,
        encrypted_card.masked_payload,
        partial_decryption,
        player_public_key,
        player_secret_key,
    );
}

#[test(should_fail_with = "partial decryption mismatch")]
fn test_tampered_encrypted_card_rejects_previous_share() {
    let encrypted_card = sample_encrypted_card();
    let player_secret_key = sample_secret_key();
    let player_public_key = derive_player_public_key(player_secret_key);
    let partial_decryption = partial_decryption_share(encrypted_card, player_secret_key);

    main(
        encrypted_card.card_commitment,
        encrypted_card.randomizer,
        encrypted_card.masked_payload + 1,
        partial_decryption,
        player_public_key,
        player_secret_key,
    );
}
