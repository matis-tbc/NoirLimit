import { keccak256, encodePacked, type Address, type Hex } from "viem";
import { FLOP_CARDS, TURN_CARD, RIVER_CARD } from "./demoPayloads";

// Deterministic client-side deal so both players (and the bot) see consistent
// hole cards in demo mode, where on-chain decryption shares are dummy values.
// Reserves the community cards used by demoPayloads so they don't double-deal.

const RESERVED = new Set<number>([...FLOP_CARDS, TURN_CARD, RIVER_CARD]);

function seedRng(seed: Hex): () => number {
  // xorshift32 seeded from 4 bytes of keccak.
  let s = parseInt(seed.slice(2, 10), 16) || 0xdeadbeef;
  return () => {
    s ^= s << 13;
    s ^= s >>> 17;
    s ^= s << 5;
    s = s >>> 0;
    return s / 0x100000000;
  };
}

export interface DealResult {
  p1: [number, number];
  p2: [number, number];
}

export function dealHoleCards(
  tableId: bigint,
  p1: Address,
  p2: Address
): DealResult {
  const seed = keccak256(
    encodePacked(["uint256", "address", "address"], [tableId, p1, p2])
  );
  const rng = seedRng(seed);
  const deck: number[] = [];
  for (let i = 0; i < 52; i++) if (!RESERVED.has(i)) deck.push(i);
  // Fisher-Yates over remaining deck.
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }
  return {
    p1: [deck[0], deck[1]],
    p2: [deck[2], deck[3]],
  };
}
