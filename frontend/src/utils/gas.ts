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
  // submitShuffle P1 cold path is ~3.6M (158 cold SSTOREs at 22.1k each +
  // overhead); P2 is ~1M (warm). 4M is the conservative ceiling that keeps
  // bot-wallet upfront gas reservation affordable on a 0.015 ETH fund at
  // Sepolia's typical 1-3 gwei market. Tighter than 5M because the wallet
  // needs balance >= gasLimit * maxFeePerGas PRE-broadcast.
  submitShuffle: 4_000_000n,
  submitDecrypt: 800_000n, // up to 3 cards + community-card writes + phase advance
  act: 200_000n,
  // HandEvaluator runs inline on the SECOND revealer and iterates C(7,5)=21
  // 5-card combinations. Existing forge test_showdown_splitPot uses ~5.2M
  // gas for the full settle path; the second revealHand alone is closer to
  // 2M. 700k was the cost of JUST the first revealer (no evaluator run) and
  // caused OOG reverts for the second. 2.5M gives margin for either side.
  revealHand: 2_500_000n,
};

export const GAS_DEFAULT = 500_000n;

export function gasFor(fn: string): bigint {
  return GAS_BY_FN[fn] ?? GAS_DEFAULT;
}
