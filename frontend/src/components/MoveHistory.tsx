import { formatEther, type Address } from "viem";
import type { LogEntry } from "../hooks/usePokerTable";

const ACTION_NAMES = ["fold", "check", "call", "raise"];

interface Props {
  logs: LogEntry[];
  // Used to resolve addresses to readable labels. Self-address becomes "You",
  // bot address becomes "Bot". Anything else falls back to short-addr.
  youAddress?: Address;
  botAddress?: Address;
}

interface Move {
  player: Address;
  action: number;
  amount: bigint;
  key: string;
}

interface Round {
  label: string;
  moves: Move[];
}

function short(a?: string): string {
  if (!a) return "?";
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

function labelFor(
  a: Address,
  youAddress?: Address,
  botAddress?: Address
): string {
  if (youAddress && a.toLowerCase() === youAddress.toLowerCase()) return "You";
  if (botAddress && a.toLowerCase() === botAddress.toLowerCase()) return "Bot";
  return short(a);
}

// Readable summary of the hand so far, grouped by betting round. Players can
// scan the history at a glance; spectators follow along without watching the
// raw zkLog scroll. Distinct from the debug EventLog which dumps every chain
// event including shuffle and decrypt noise.
export function MoveHistory({ logs, youAddress, botAddress }: Props) {
  const rounds: Round[] = [{ label: "Preflop", moves: [] }];
  // Walk logs in chain order. Each CommunityCardsRevealed opens a new round.
  // Each ActionTaken appends to the current round.
  const sorted = [...logs].sort((a, b) => {
    if (a.blockNumber === b.blockNumber) return a.logIndex - b.logIndex;
    return a.blockNumber < b.blockNumber ? -1 : 1;
  });

  for (const l of sorted) {
    if (l.eventName === "CommunityCardsRevealed") {
      const count = Number(l.args?.newCardCount ?? 0);
      if (count === 3) rounds.push({ label: "Flop", moves: [] });
      else if (count === 4) rounds.push({ label: "Turn", moves: [] });
      else if (count === 5) rounds.push({ label: "River", moves: [] });
      continue;
    }
    if (l.eventName === "ActionTaken") {
      const move: Move = {
        player: l.args.player as Address,
        action: Number(l.args.action),
        amount: (l.args.amount as bigint) ?? 0n,
        key: `${l.transactionHash}-${l.logIndex}`,
      };
      rounds[rounds.length - 1].moves.push(move);
    }
  }

  const totalMoves = rounds.reduce((n, r) => n + r.moves.length, 0);
  if (totalMoves === 0) {
    return (
      <div className="border border-edge rounded p-3 text-xs">
        <div className="uppercase tracking-widest text-ink/50 mb-2">
          Move history
        </div>
        <div className="text-ink/30">No moves yet. First action will appear here.</div>
      </div>
    );
  }

  return (
    <div className="border border-edge rounded p-3 text-xs space-y-3">
      <div className="uppercase tracking-widest text-ink/50">Move history</div>
      {rounds.map((r, i) => {
        if (r.moves.length === 0 && i > 0) return null;
        return (
          <div key={i} className="space-y-1">
            <div className="text-[10px] uppercase tracking-widest text-gold/70">
              {r.label}
            </div>
            {r.moves.length === 0 ? (
              <div className="text-ink/30 pl-2">(no moves yet)</div>
            ) : (
              <table className="w-full">
                <tbody>
                  {r.moves.map((m) => {
                    const who = labelFor(m.player, youAddress, botAddress);
                    const isYou = who === "You";
                    return (
                      <tr key={m.key} className="text-ink/80">
                        <td
                          className={
                            "py-0.5 pr-3 font-mono " +
                            (isYou ? "text-gold" : "text-ink/70")
                          }
                          style={{ width: "25%" }}
                        >
                          {who}
                        </td>
                        <td className="py-0.5 pr-3 uppercase tracking-widest text-[10px]">
                          {ACTION_NAMES[m.action] ?? "?"}
                        </td>
                        <td className="py-0.5 font-mono tabular-nums text-ink/60">
                          {m.amount > 0n ? `${formatEther(m.amount)} ETH` : ""}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </div>
        );
      })}
    </div>
  );
}
