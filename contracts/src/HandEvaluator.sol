// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library HandEvaluator {
    struct HandInfo {
        uint8 quads;
        uint8 trips;
        uint8 pairs;
        uint8 quadRank;
        uint8 tripRank;
        uint8 pairHi;
        uint8 pairLo;
        bool isFlush;
        bool isStraight;
        uint8 straightHigh;
    }

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
        uint8[5] memory r;
        uint8[13] memory rc;
        uint8[4] memory sc;
        for (uint256 i = 0; i < 5; i++) {
            r[i] = hand[i] % 13;
            sc[hand[i] / 13]++;
            rc[r[i]]++;
        }

        // Sort ranks descending
        for (uint256 i = 0; i < 4; i++) {
            for (uint256 j = i + 1; j < 5; j++) {
                if (r[j] > r[i]) {
                    (r[i], r[j]) = (r[j], r[i]);
                }
            }
        }

        HandInfo memory h = _classify(r, rc, sc);
        return _buildScore(r, h);
    }

    function _classify(
        uint8[5] memory r,
        uint8[13] memory rc,
        uint8[4] memory sc
    ) private pure returns (HandInfo memory h) {
        h.isFlush = sc[0] == 5 || sc[1] == 5 || sc[2] == 5 || sc[3] == 5;

        for (uint8 i = 0; i < 13; i++) {
            if (rc[i] == 4) { h.quads++; h.quadRank = i; }
            else if (rc[i] == 3) { h.trips++; h.tripRank = i; }
            else if (rc[i] == 2) {
                h.pairs++;
                if (h.pairs == 1) { h.pairHi = i; }
                else {
                    if (i > h.pairHi) { h.pairLo = h.pairHi; h.pairHi = i; }
                    else { h.pairLo = i; }
                }
            }
        }

        bool allDistinct = (h.quads == 0 && h.trips == 0 && h.pairs == 0);
        if (allDistinct) {
            if (r[0] - r[4] == 4) {
                h.isStraight = true;
                h.straightHigh = r[0];
            }
            if (r[0] == 12 && r[1] == 3 && r[2] == 2 && r[3] == 1 && r[4] == 0) {
                h.isStraight = true;
                h.straightHigh = 3;
            }
        }
    }

    function _buildScore(uint8[5] memory r, HandInfo memory h)
        private pure returns (uint256)
    {
        if (h.isStraight && h.isFlush) {
            return _pack(8, h.straightHigh, 0, 0, 0, 0);
        }
        if (h.quads > 0) {
            uint8 kicker = 0;
            for (uint256 i = 0; i < 5; i++) {
                if (r[i] != h.quadRank) { kicker = r[i]; break; }
            }
            return _pack(7, h.quadRank, kicker, 0, 0, 0);
        }
        if (h.trips > 0 && h.pairs > 0) {
            return _pack(6, h.tripRank, h.pairHi, 0, 0, 0);
        }
        if (h.isFlush) {
            return _pack(5, r[0], r[1], r[2], r[3], r[4]);
        }
        if (h.isStraight) {
            return _pack(4, h.straightHigh, 0, 0, 0, 0);
        }
        if (h.trips > 0) {
            return _packTrips(r, h.tripRank);
        }
        if (h.pairs == 2) {
            return _packTwoPair(r, h.pairHi, h.pairLo);
        }
        if (h.pairs == 1) {
            return _packOnePair(r, h.pairHi);
        }
        return _pack(0, r[0], r[1], r[2], r[3], r[4]);
    }

    function _packTrips(uint8[5] memory r, uint8 tripRank) private pure returns (uint256) {
        uint8 k0; uint8 k1; uint8 ki;
        for (uint256 i = 0; i < 5; i++) {
            if (r[i] != tripRank) {
                if (ki == 0) k0 = r[i];
                else k1 = r[i];
                ki++;
            }
        }
        return _pack(3, tripRank, k0, k1, 0, 0);
    }

    function _packTwoPair(uint8[5] memory r, uint8 pairHi, uint8 pairLo) private pure returns (uint256) {
        uint8 kicker;
        for (uint256 i = 0; i < 5; i++) {
            if (r[i] != pairHi && r[i] != pairLo) { kicker = r[i]; break; }
        }
        return _pack(2, pairHi, pairLo, kicker, 0, 0);
    }

    function _packOnePair(uint8[5] memory r, uint8 pairRank) private pure returns (uint256) {
        uint8 k0; uint8 k1; uint8 k2; uint8 ki;
        for (uint256 i = 0; i < 5; i++) {
            if (r[i] != pairRank) {
                if (ki == 0) k0 = r[i];
                else if (ki == 1) k1 = r[i];
                else k2 = r[i];
                ki++;
            }
        }
        return _pack(1, pairRank, k0, k1, k2, 0);
    }

    function _pack(uint8 t, uint8 a, uint8 b, uint8 c, uint8 d, uint8 e)
        private pure returns (uint256)
    {
        return (uint256(t) << 20) | (uint256(a) << 16) | (uint256(b) << 12)
             | (uint256(c) << 8)  | (uint256(d) << 4)  | uint256(e);
    }
}
