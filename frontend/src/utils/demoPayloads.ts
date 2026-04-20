import type { Hex } from "viem";
import { toHex } from "viem";

// Fixed community card values used in DemoHand.s.sol  -  both players must submit
// matching arrays in REVEAL phases or the contract rejects the second tx.
export const FLOP_CARDS: number[] = [10, 21, 31]; // Qc 9d 6h (in DemoHand)
export const TURN_CARD: number = 43; // 5s
export const RIVER_CARD: number = 0; // 2c

// Indices in the encrypted deck reserved for community cards.
export const FLOP_INDICES: number[] = [4, 5, 6];
export const TURN_INDICES: number[] = [7];
export const RIVER_INDICES: number[] = [8];

// Bot/auto public keys (any non-zero bytes32 is accepted in demo mode).
export function publicKeyFor(seed: number): Hex {
  return toHex(BigInt(seed) | 0xaan, { size: 32 });
}

function bytes32Array(start: number, count: number): Hex[] {
  const out: Hex[] = [];
  for (let i = 0; i < count; i++) {
    out.push(toHex(BigInt(start + i), { size: 32 }));
  }
  return out;
}

// Match DemoHand.s.sol shuffle payloads.
export function shuffleP1Payload() {
  return {
    proof: "0x" as Hex,
    newDeckCommitment: toHex(1n, { size: 32 }),
    cardCommitments: bytes32Array(1, 52),
    cardRandomizers: bytes32Array(1, 52),
    cardMaskedPayloads: bytes32Array(1, 52),
  };
}

export function shuffleP2Payload() {
  return {
    proof: "0x" as Hex,
    newDeckCommitment: toHex(2n, { size: 32 }),
    cardCommitments: bytes32Array(100, 52),
    cardRandomizers: bytes32Array(200, 52),
    cardMaskedPayloads: bytes32Array(300, 52),
  };
}

// submitDecrypt payloads.
// playerSeed differentiates each player's partial decryption shares so they don't collide.
export function decryptDealing(playerSeed: number, indices: number[]) {
  return {
    cardIndices: indices,
    partialDecryptionValues: indices.map((_, i) => toHex(BigInt(0x1100 + playerSeed * 0x100 + i), { size: 32 })),
    proofs: indices.map(() => "0x" as Hex),
    cardValues: [] as number[],
  };
}

export function decryptReveal(
  playerSeed: number,
  indices: number[],
  values: number[]
) {
  return {
    cardIndices: indices,
    partialDecryptionValues: indices.map((_, i) => toHex(BigInt(0xaa00 + playerSeed * 0x100 + i), { size: 32 })),
    proofs: indices.map(() => "0x" as Hex),
    cardValues: values,
  };
}

export const REVEAL_VALUES = {
  flop: FLOP_CARDS,
  turn: [TURN_CARD],
  river: [RIVER_CARD],
};
