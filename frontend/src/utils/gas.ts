// Explicit per-function gas limits for PokerTable writes.
//
// viem's eth_estimateGas under-counted submitDecrypt at FLOP_REVEAL (review
// agent traced an OOG at 210k used). HandEvaluator's 21-iteration loop runs
// inline on the second revealHand call - 200k there is a latent OOG too.
// Pad generously: unused gas is refunded; underestimating wedges the hand.
//
// Used by both botDriver.send (bot-signed) and useAutoSubmit.write
// (user-signed) so neither side OOGs in any phase.
//
// IMPORTANT: when demoMode flips false, the real Plonk verifier adds
// ~250-300k per card. Bump submitDecrypt to ~1.5M and submitShuffle to ~6M
// before any non-demo deploy.
export const GAS_BY_FN: Record<string, bigint> = {
  joinTable: 250_000n,
  registerPublicKey: 100_000n,
  submitShuffle: 5_000_000n, // 156 cold SSTOREs + calldata cost
  submitDecrypt: 800_000n, // up to 3 cards + community-card writes + phase advance
  act: 200_000n,
  revealHand: 700_000n, // HandEvaluator runs inline on second revealer
};

export const GAS_DEFAULT = 500_000n;

export function gasFor(fn: string): bigint {
  return GAS_BY_FN[fn] ?? GAS_DEFAULT;
}
