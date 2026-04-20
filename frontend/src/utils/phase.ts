// Mirrors PokerTable State enum
export enum Phase {
  WAITING = 0,
  SHUFFLE_P1 = 1,
  SHUFFLE_P2 = 2,
  DEALING = 3,
  PREFLOP = 4,
  FLOP_REVEAL = 5,
  FLOP_BET = 6,
  TURN_REVEAL = 7,
  TURN_BET = 8,
  RIVER_REVEAL = 9,
  RIVER_BET = 10,
  SHOWDOWN = 11,
  SETTLED = 12,
  CANCELLED = 13,
}

export const PHASE_LABELS: Record<number, string> = {
  [Phase.WAITING]: "Waiting for opponent",
  [Phase.SHUFFLE_P1]: "Shuffling (P1)",
  [Phase.SHUFFLE_P2]: "Shuffling (P2)",
  [Phase.DEALING]: "Dealing",
  [Phase.PREFLOP]: "Preflop bet",
  [Phase.FLOP_REVEAL]: "Revealing flop",
  [Phase.FLOP_BET]: "Flop bet",
  [Phase.TURN_REVEAL]: "Revealing turn",
  [Phase.TURN_BET]: "Turn bet",
  [Phase.RIVER_REVEAL]: "Revealing river",
  [Phase.RIVER_BET]: "River bet",
  [Phase.SHOWDOWN]: "Showdown",
  [Phase.SETTLED]: "Settled",
  [Phase.CANCELLED]: "Cancelled",
};

export const AUTO_PHASES = new Set<Phase>([
  Phase.SHUFFLE_P1,
  Phase.SHUFFLE_P2,
  Phase.DEALING,
  Phase.FLOP_REVEAL,
  Phase.TURN_REVEAL,
  Phase.RIVER_REVEAL,
]);

export const BETTING_PHASES = new Set<Phase>([
  Phase.PREFLOP,
  Phase.FLOP_BET,
  Phase.TURN_BET,
  Phase.RIVER_BET,
]);

export const TERMINAL_PHASES = new Set<Phase>([Phase.SETTLED, Phase.CANCELLED]);

export function isTerminal(p: number): boolean {
  return TERMINAL_PHASES.has(p);
}

export function isAutoPhase(p: number): boolean {
  return AUTO_PHASES.has(p);
}

export function isBettingPhase(p: number): boolean {
  return BETTING_PHASES.has(p);
}

export enum ActionCode {
  FOLD = 0,
  CHECK = 1,
  CALL = 2,
  RAISE = 3,
}
