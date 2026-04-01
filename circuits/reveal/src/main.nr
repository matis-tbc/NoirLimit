use common::{commit_card, Card};

global HOLE_CARD_COUNT: u32 = 2;

fn main(
    card_commitments: pub [Field; HOLE_CARD_COUNT],
    revealed_cards: pub [Card; HOLE_CARD_COUNT],
    commitment_randomness: [Field; HOLE_CARD_COUNT],
) {
    for i in 0..HOLE_CARD_COUNT {
        let expected_commitment = commit_card(revealed_cards[i], commitment_randomness[i]);
        assert(card_commitments[i] == expected_commitment, "revealed card commitment mismatch");
    }
}

fn sample_cards() -> [Card; HOLE_CARD_COUNT] {
    [7, 42]
}

fn sample_randomness() -> [Field; HOLE_CARD_COUNT] {
    [111, 222]
}

fn build_reveal_inputs() -> ([Field; HOLE_CARD_COUNT], [Card; HOLE_CARD_COUNT], [Field; HOLE_CARD_COUNT]) {
    let revealed_cards = sample_cards();
    let commitment_randomness = sample_randomness();
    let card_commitments = [
        commit_card(revealed_cards[0], commitment_randomness[0]),
        commit_card(revealed_cards[1], commitment_randomness[1]),
    ];

    (card_commitments, revealed_cards, commitment_randomness)
}

#[test]
fn test_valid_showdown_reveal() {
    let (card_commitments, revealed_cards, commitment_randomness) = build_reveal_inputs();
    main(card_commitments, revealed_cards, commitment_randomness);
}

#[test]
fn test_distinct_openings_can_reveal_same_card_value() {
    let revealed_cards = [12, 12];
    let commitment_randomness = [9001, 9002];
    let card_commitments = [
        commit_card(revealed_cards[0], commitment_randomness[0]),
        commit_card(revealed_cards[1], commitment_randomness[1]),
    ];

    assert(card_commitments[0] != card_commitments[1], "different nonces should bind identical card values differently");

    main(card_commitments, revealed_cards, commitment_randomness);
}

#[test(should_fail_with = "revealed card commitment mismatch")]
fn test_invalid_first_card_opening() {
    let (card_commitments, revealed_cards, commitment_randomness) = build_reveal_inputs();
    let tampered_randomness = [commitment_randomness[0] + 1, commitment_randomness[1]];

    main(card_commitments, revealed_cards, tampered_randomness);
}

#[test(should_fail_with = "revealed card commitment mismatch")]
fn test_invalid_second_revealed_card_value() {
    let (card_commitments, revealed_cards, commitment_randomness) = build_reveal_inputs();
    let tampered_cards = [revealed_cards[0], revealed_cards[1] + 1];

    main(card_commitments, tampered_cards, commitment_randomness);
}
