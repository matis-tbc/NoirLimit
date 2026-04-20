export const RANKS = ["2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"];
export const SUITS = ["c", "d", "h", "s"] as const;
export const SUIT_GLYPHS: Record<(typeof SUITS)[number], string> = {
  c: "\u2663",
  d: "\u2666",
  h: "\u2665",
  s: "\u2660",
};

export type CardId = number;

export function cardName(id: CardId): string {
  return `${RANKS[id % 13]}${SUITS[Math.floor(id / 13)]}`;
}

export function cardToDisplay(id: CardId) {
  const rank = RANKS[id % 13];
  const suit = SUITS[Math.floor(id / 13)];
  const color = suit === "d" || suit === "h" ? "text-red-400" : "text-ink";
  return { rank, suit, glyph: SUIT_GLYPHS[suit], color };
}
