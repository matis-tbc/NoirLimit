// Lightweight poker AI for the in-app bot. Uses pokersolver to rank the current
// hand across hole + community cards and picks an action. The bot still relies
// on try/fallback in botDriver because getTable does not expose currentBet,
// so "CALL reverts when nothing to call" is caught and downgraded to CHECK.
//
// This is explicitly a demo-day opponent: predictable, never tanks the demo,
// occasionally raises on strong hands so the betting feels alive.

import { Hand } from "pokersolver";
import { cardName } from "../utils/cards";
import { Phase, ActionCode } from "../utils/phase";
import {
  FLOP_CARDS,
  TURN_CARD,
  RIVER_CARD,
} from "../utils/demoPayloads";

export type BotAction =
  | { code: ActionCode.CHECK }
  | { code: ActionCode.CALL }
  | { code: ActionCode.FOLD }
  | { code: ActionCode.RAISE; amount: bigint };

// pokersolver hand rank: 1 (high card) -> 9 (royal flush).
// We expose it so we can display it in zkLog / CheatMoment if we want later.
export interface Evaluation {
  rank: number;
  name: string;
  description: string;
  cards: string[];
}

function visibleCommunity(phase: Phase): number[] {
  if (phase === Phase.PREFLOP) return [];
  if (phase === Phase.FLOP_BET) return [...FLOP_CARDS];
  if (phase === Phase.TURN_BET) return [...FLOP_CARDS, TURN_CARD];
  if (phase === Phase.RIVER_BET)
    return [...FLOP_CARDS, TURN_CARD, RIVER_CARD];
  return [];
}

export function evaluateHand(
  holeCards: [number, number],
  phase: Phase
): Evaluation | null {
  const community = visibleCommunity(phase);
  const cards = [...holeCards, ...community].map(cardName);
  if (cards.length < 2) return null;
  // pokersolver requires at least 5 cards for its standard games. For preflop
  // (2 cards) we short-circuit to a simple hole-card strength score.
  if (cards.length < 5) {
    return {
      rank: preflopScore(holeCards),
      name: "preflop",
      description: cards.join(" "),
      cards,
    };
  }
  const solved = Hand.solve(cards);
  return {
    rank: solved.rank,
    name: solved.name,
    description: solved.descr,
    cards,
  };
}

// Chen-like simplified preflop score, normalized to the 1-9 pokersolver scale
// so downstream thresholds stay consistent. Returns 1 for bottom, up to ~4 for
// premium hands (AA, KK, AKs).
function preflopScore(hole: [number, number]): number {
  const r0 = hole[0] % 13;
  const r1 = hole[1] % 13;
  const s0 = Math.floor(hole[0] / 13);
  const s1 = Math.floor(hole[1] / 13);
  const hi = Math.max(r0, r1);
  const lo = Math.min(r0, r1);
  const pair = r0 === r1;
  const suited = s0 === s1;
  const gap = hi - lo;

  let score = 1;
  if (pair) {
    if (hi >= 10) score = 4; // TT+
    else if (hi >= 6) score = 3; // 88-77 etc
    else score = 2;
  } else {
    // High-card contribution: A=4 boost, K=3, Q=2, J=1.
    if (hi >= 12) score += 1.5;
    else if (hi >= 11) score += 1;
    else if (hi >= 10) score += 0.5;
    if (lo >= 11) score += 0.5;
    if (suited) score += 0.5;
    if (gap === 1) score += 0.3;
    else if (gap >= 4) score -= 0.5;
  }
  return Math.max(1, Math.min(4, score));
}

interface DecideContext {
  phase: Phase;
  potWei: bigint;
  botStackWei: bigint;
  bigBlindWei: bigint;
  // If provided, enables randomized raise frequency instead of always raising.
  randomSeed?: number;
}

// Deterministic-ish jitter based on seed + phase so the same table replays the
// same bot behavior, while different tables feel different.
function jitter(seed: number, phase: number): number {
  return Math.sin(seed * 9301 + phase * 49297) * 0.5 + 0.5;
}

export function decideAction(
  hole: [number, number],
  ctx: DecideContext
): BotAction {
  const evalRes = evaluateHand(hole, ctx.phase);
  if (!evalRes) return { code: ActionCode.CHECK };

  const rank = evalRes.rank;
  const j = jitter(ctx.randomSeed ?? 0, ctx.phase);

  // Strong made hand: raise a chunk of the pot.
  if (rank >= 5) {
    // Two pair or better on flop+, or premium preflop pair (we map preflop to
    // max 4, so this branch is post-flop only).
    const raiseWei = clamp(
      ctx.potWei / 2n || ctx.bigBlindWei * 3n,
      ctx.bigBlindWei,
      ctx.botStackWei
    );
    return { code: ActionCode.RAISE, amount: raiseWei };
  }

  // Decent hand: mostly CALL, occasionally RAISE.
  if (rank >= 3) {
    if (j < 0.25 && ctx.potWei > 0n) {
      const raiseWei = clamp(
        ctx.bigBlindWei * 2n,
        ctx.bigBlindWei,
        ctx.botStackWei
      );
      return { code: ActionCode.RAISE, amount: raiseWei };
    }
    return { code: ActionCode.CALL };
  }

  // Weak-ish: CALL if free (CHECK fallback), FOLD sometimes if there's
  // meaningful pressure in the pot.
  if (ctx.phase !== Phase.PREFLOP && ctx.potWei > ctx.bigBlindWei * 6n && j < 0.3) {
    return { code: ActionCode.FOLD };
  }
  return { code: ActionCode.CALL };
}

function clamp(v: bigint, lo: bigint, hi: bigint): bigint {
  if (hi < lo) return lo;
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}
