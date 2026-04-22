declare module "pokersolver" {
  export class Hand {
    static solve(cards: string[], game?: string, canDisqualify?: boolean): Hand;
    static winners(hands: Hand[]): Hand[];
    rank: number;
    name: string;
    descr: string;
    cards: Array<{ value: string; suit: string; wildValue: string; rank: number }>;
    cardPool: Array<{ value: string; suit: string; wildValue: string; rank: number }>;
  }
}
