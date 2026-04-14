// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library HandEvaluator {
    /// @notice Evaluate the best 5-card poker hand from 7 cards.
    /// @param cards 7 cards encoded as uint8 (0-51). rank = card % 13, suit = card / 13.
    /// @return score Comparable score where higher = better hand.
    function evaluate(uint8[7] memory cards) internal pure returns (uint256) {
        uint256 best = 0;
        // Try all C(7,5) = 21 combinations by skipping 2 cards
        for (uint256 i = 0; i < 7; i++) {
            for (uint256 j = i + 1; j < 7; j++) {
                uint8[5] memory hand;
                uint256 h = 0;
                for (uint256 k = 0; k < 7; k++) {
                    if (k != i && k != j) {
                        hand[h++] = cards[k];
                    }
                }
                uint256 s = _scoreHand(hand);
                if (s > best) best = s;
            }
        }
        return best;
    }

    /// @notice Score a single 5-card hand.
    function _scoreHand(uint8[5] memory hand) private pure returns (uint256) {
        // Extract ranks and suits
        uint8[5] memory r;
        uint8[13] memory rc; // rank counts
        uint8[4] memory sc;  // suit counts
        for (uint256 i = 0; i < 5; i++) {
            r[i] = hand[i] % 13;
            sc[hand[i] / 13]++;
            rc[r[i]]++;
        }

        // Sort ranks descending (selection sort, 5 elements)
        for (uint256 i = 0; i < 4; i++) {
            for (uint256 j = i + 1; j < 5; j++) {
                if (r[j] > r[i]) {
                    (r[i], r[j]) = (r[j], r[i]);
                }
            }
        }

        // Check flush
        bool isFlush = sc[0] == 5 || sc[1] == 5 || sc[2] == 5 || sc[3] == 5;

        // Classify by rank frequency
        uint8 quads = 0;
        uint8 trips = 0;
        uint8 pairs = 0;
        uint8 quadRank = 0;
        uint8 tripRank = 0;
        uint8 pairHi = 0;
        uint8 pairLo = 0;
        for (uint8 i = 0; i < 13; i++) {
            if (rc[i] == 4) { quads++; quadRank = i; }
            else if (rc[i] == 3) { trips++; tripRank = i; }
            else if (rc[i] == 2) {
                pairs++;
                if (pairs == 1) { pairHi = i; }
                else {
                    if (i > pairHi) { pairLo = pairHi; pairHi = i; }
                    else { pairLo = i; }
                }
            }
        }

        bool allDistinct = (quads == 0 && trips == 0 && pairs == 0);

        // Check straight
        bool isStraight = false;
        uint8 straightHigh = 0;
        if (allDistinct) {
            // Normal straight: 5 consecutive ranks
            if (r[0] - r[4] == 4) {
                isStraight = true;
                straightHigh = r[0];
            }
            // Wheel: A-5-4-3-2 (sorted: 12, 3, 2, 1, 0)
            if (r[0] == 12 && r[1] == 3 && r[2] == 2 && r[3] == 1 && r[4] == 0) {
                isStraight = true;
                straightHigh = 3; // 5-high
            }
        }

        // Build kicker array (ranks not part of the main grouping)
        uint8[5] memory k;

        // Classify hand and return packed score
        if (isStraight && isFlush) {
            return _pack(8, straightHigh, 0, 0, 0, 0);
        }
        if (quads > 0) {
            uint8 ki = 0;
            for (uint256 i = 0; i < 5; i++) {
                if (r[i] != quadRank) { k[ki++] = r[i]; }
            }
            return _pack(7, quadRank, k[0], 0, 0, 0);
        }
        if (trips > 0 && pairs > 0) {
            return _pack(6, tripRank, pairHi, 0, 0, 0);
        }
        if (isFlush) {
            return _pack(5, r[0], r[1], r[2], r[3], r[4]);
        }
        if (isStraight) {
            return _pack(4, straightHigh, 0, 0, 0, 0);
        }
        if (trips > 0) {
            uint8 ki = 0;
            for (uint256 i = 0; i < 5; i++) {
                if (r[i] != tripRank) k[ki++] = r[i];
            }
            return _pack(3, tripRank, k[0], k[1], 0, 0);
        }
        if (pairs == 2) {
            uint8 ki = 0;
            for (uint256 i = 0; i < 5; i++) {
                if (r[i] != pairHi && r[i] != pairLo) k[ki++] = r[i];
            }
            return _pack(2, pairHi, pairLo, k[0], 0, 0);
        }
        if (pairs == 1) {
            uint8 ki = 0;
            for (uint256 i = 0; i < 5; i++) {
                if (r[i] != pairHi) k[ki++] = r[i];
            }
            return _pack(1, pairHi, k[0], k[1], k[2], 0);
        }
        // High card
        return _pack(0, r[0], r[1], r[2], r[3], r[4]);
    }

    function _pack(uint8 t, uint8 a, uint8 b, uint8 c, uint8 d, uint8 e)
        private pure returns (uint256)
    {
        return (uint256(t) << 20) | (uint256(a) << 16) | (uint256(b) << 12)
             | (uint256(c) << 8)  | (uint256(d) << 4)  | uint256(e);
    }
}
