// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/HandEvaluator.sol";

contract HandEvaluatorTest is Test {
    // Card helper: card(rank, suit) -> uint8
    // rank: 0=2, 1=3, ..., 8=T, 9=J, 10=Q, 11=K, 12=A
    // suit: 0=clubs, 1=diamonds, 2=hearts, 3=spades
    function c(uint8 rank, uint8 suit) internal pure returns (uint8) {
        return suit * 13 + rank;
    }

    function score5(uint8 a, uint8 b, uint8 cc, uint8 d, uint8 e) internal pure returns (uint256) {
        uint8[7] memory cards = [a, b, cc, d, e, uint8(0), uint8(0)];
        // Evaluate with 2 dummy cards that won't help
        // Use cards that duplicate existing ones to avoid improving the hand
        // Actually, just use evaluate with the hand padded. But evaluate picks best 5 of 7.
        // We need a way to score exactly 5 cards. Let's pad with known low non-helping cards.
        // Easiest: just test via 7-card evaluate with 2 irrelevant cards.
        cards[5] = 51; // A spades - might help! Let's use truly junk approach below.
        cards[6] = 50; // K spades
        // This is problematic. Let's just test via 7-card hands directly.
        return HandEvaluator.evaluate(cards);
    }

    // --- Hand type ordering ---

    function test_pairBeatsHighCard() public pure {
        // Pair of 2s vs Ace high
        uint8[7] memory pair   = [c(0,0), c(0,1), c(4,2), c(6,3), c(8,0), c(10,1), c(11,2)];
        uint8[7] memory high   = [c(12,0), c(10,1), c(8,2), c(6,3), c(4,0), c(2,1), c(0,2)];
        assert(HandEvaluator.evaluate(pair) > HandEvaluator.evaluate(high));
    }

    function test_twoPairBeatsPair() public pure {
        uint8[7] memory twop  = [c(0,0), c(0,1), c(1,0), c(1,1), c(8,2), c(6,3), c(4,0)];
        uint8[7] memory onep  = [c(12,0), c(12,1), c(10,2), c(8,3), c(6,0), c(4,1), c(2,2)];
        assert(HandEvaluator.evaluate(twop) > HandEvaluator.evaluate(onep));
    }

    function test_tripsBeatsTwoPair() public pure {
        uint8[7] memory trips  = [c(2,0), c(2,1), c(2,2), c(8,3), c(6,0), c(4,1), c(0,2)];
        uint8[7] memory twop   = [c(12,0), c(12,1), c(11,0), c(11,1), c(10,2), c(8,3), c(6,0)];
        assert(HandEvaluator.evaluate(trips) > HandEvaluator.evaluate(twop));
    }

    function test_straightBeatsTrips() public pure {
        // 5-6-7-8-9 straight
        uint8[7] memory str   = [c(3,0), c(4,1), c(5,2), c(6,3), c(7,0), c(0,1), c(1,2)];
        uint8[7] memory trips = [c(12,0), c(12,1), c(12,2), c(10,3), c(8,0), c(6,1), c(4,2)];
        assert(HandEvaluator.evaluate(str) > HandEvaluator.evaluate(trips));
    }

    function test_flushBeatsStraight() public pure {
        // Flush: 2,4,6,8,T of hearts + junk
        uint8[7] memory flush = [c(0,2), c(2,2), c(4,2), c(6,2), c(8,2), c(1,0), c(3,1)];
        // Straight: 5-6-7-8-9
        uint8[7] memory str   = [c(3,0), c(4,1), c(5,2), c(6,3), c(7,0), c(0,1), c(1,2)];
        assert(HandEvaluator.evaluate(flush) > HandEvaluator.evaluate(str));
    }

    function test_fullHouseBeatsFlush() public pure {
        uint8[7] memory fh    = [c(5,0), c(5,1), c(5,2), c(3,0), c(3,1), c(0,2), c(1,3)];
        uint8[7] memory flush = [c(0,2), c(2,2), c(4,2), c(6,2), c(8,2), c(1,0), c(3,1)];
        assert(HandEvaluator.evaluate(fh) > HandEvaluator.evaluate(flush));
    }

    function test_quadsBeatFullHouse() public pure {
        uint8[7] memory quads = [c(4,0), c(4,1), c(4,2), c(4,3), c(10,0), c(0,1), c(1,2)];
        uint8[7] memory fh    = [c(12,0), c(12,1), c(12,2), c(11,0), c(11,1), c(0,2), c(1,3)];
        assert(HandEvaluator.evaluate(quads) > HandEvaluator.evaluate(fh));
    }

    function test_straightFlushBeatsQuads() public pure {
        // Straight flush: 3-4-5-6-7 of clubs
        uint8[7] memory sf    = [c(1,0), c(2,0), c(3,0), c(4,0), c(5,0), c(10,1), c(11,2)];
        uint8[7] memory quads = [c(12,0), c(12,1), c(12,2), c(12,3), c(10,0), c(0,1), c(1,2)];
        assert(HandEvaluator.evaluate(sf) > HandEvaluator.evaluate(quads));
    }

    // --- Same type comparisons ---

    function test_higherPairWins() public pure {
        uint8[7] memory aces  = [c(12,0), c(12,1), c(8,2), c(6,3), c(4,0), c(2,1), c(0,2)];
        uint8[7] memory kings = [c(11,0), c(11,1), c(8,2), c(6,3), c(4,0), c(2,1), c(0,2)];
        assert(HandEvaluator.evaluate(aces) > HandEvaluator.evaluate(kings));
    }

    function test_kickerBreaksTie() public pure {
        // Both have pair of aces, but different kickers
        uint8[7] memory aceK = [c(12,0), c(12,1), c(11,2), c(6,3), c(4,0), c(2,1), c(0,2)];
        uint8[7] memory aceQ = [c(12,0), c(12,1), c(10,2), c(6,3), c(4,0), c(2,1), c(0,2)];
        assert(HandEvaluator.evaluate(aceK) > HandEvaluator.evaluate(aceQ));
    }

    // --- Straights ---

    function test_wheelStraight() public pure {
        // A-2-3-4-5 (wheel)
        uint8[7] memory wheel = [c(12,0), c(0,1), c(1,2), c(2,3), c(3,0), c(8,1), c(10,2)];
        // High card K
        uint8[7] memory high  = [c(11,0), c(9,1), c(7,2), c(5,3), c(3,0), c(1,1), c(0,2)];
        // Wheel is a straight, should beat high card
        assert(HandEvaluator.evaluate(wheel) > HandEvaluator.evaluate(high));
    }

    function test_wheelLosesToSixHighStraight() public pure {
        uint8[7] memory wheel = [c(12,0), c(0,1), c(1,2), c(2,3), c(3,0), c(8,1), c(10,2)];
        uint8[7] memory six   = [c(0,0), c(1,1), c(2,2), c(3,3), c(4,0), c(8,1), c(10,2)];
        assert(HandEvaluator.evaluate(six) > HandEvaluator.evaluate(wheel));
    }

    function test_broadwayStraight() public pure {
        // T-J-Q-K-A (broadway)
        uint8[7] memory bway = [c(8,0), c(9,1), c(10,2), c(11,3), c(12,0), c(0,1), c(1,2)];
        // 9-T-J-Q-K
        uint8[7] memory nine = [c(7,0), c(8,1), c(9,2), c(10,3), c(11,0), c(0,1), c(1,2)];
        assert(HandEvaluator.evaluate(bway) > HandEvaluator.evaluate(nine));
    }

    // --- Best 5 of 7 ---

    function test_bestFiveFromSeven() public pure {
        // Board makes a pair of 3s available, but hole cards give pair of aces
        // Hole: A-clubs, A-diamonds. Board: 3c, 3d, 7h, Ts, 2c
        uint8[7] memory hand = [c(12,0), c(12,1), c(1,0), c(1,1), c(5,2), c(8,3), c(0,0)];
        // Should find two pair (AA + 33) not just pair of aces
        // Two pair score type = 2
        uint256 score = HandEvaluator.evaluate(hand);
        // Two pair is type 2, shifted left 20 = 2 << 20 = 2097152
        assert(score >= 2097152); // at least two pair
        assert(score < 3145728); // less than trips (3 << 20)
    }

    function test_identicalHandsEqual() public pure {
        uint8[7] memory h1 = [c(12,0), c(11,1), c(8,2), c(6,3), c(4,0), c(2,1), c(0,2)];
        uint8[7] memory h2 = [c(12,0), c(11,1), c(8,2), c(6,3), c(4,0), c(2,1), c(0,2)];
        assertEq(HandEvaluator.evaluate(h1), HandEvaluator.evaluate(h2));
    }
}
