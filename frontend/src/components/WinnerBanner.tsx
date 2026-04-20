import { useEffect, useState } from "react";
import { formatEther, type Address } from "viem";
import { Card } from "./Card";

interface Props {
  winner?: Address;
  pot?: bigint;
  winnerCards?: [number, number] | null;
  reason?: "settled" | "timeout";
  trigger?: number; // bump to re-show (e.g. Date.now() on each event)
}

function shortAddr(a?: Address) {
  if (!a) return "-";
  return `${a.slice(0, 6)}...${a.slice(-4)}`;
}

// Full-screen overlay that fires when HandSettled is detected. Shows the
// winner, pot size, and revealed hole cards. Auto-dismisses after 6s; click
// to dismiss earlier.
export function WinnerBanner({ winner, pot, winnerCards, reason = "settled", trigger }: Props) {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (!trigger) return;
    setVisible(true);
    // No auto-dismiss; user clicks the overlay or uses the TerminalPanel
    // buttons underneath. Without follow-up CTAs the auto-dismiss left users
    // staring at a dead table with no signal what to do.
  }, [trigger]);

  if (!visible || !winner) return null;

  const label = reason === "timeout" ? "Hand cancelled - won by timeout" : "Hand settled";
  const isTimeout = reason === "timeout";

  return (
    <div
      onClick={() => setVisible(false)}
      className="fixed inset-0 z-40 bg-black/80 flex items-center justify-center animate-[fadein_200ms_ease-out] cursor-pointer"
    >
      <div className={`border p-8 bg-bg flex flex-col items-center gap-4 max-w-md ${isTimeout ? "border-yellow-500" : "border-gold"}`}>
        <div className="text-xs uppercase tracking-[0.3em] text-ink/50">
          {label}
        </div>
        {winnerCards && !isTimeout && (
          <div className="flex gap-2">
            <Card card={winnerCards[0]} size="lg" />
            <Card card={winnerCards[1]} size="lg" />
          </div>
        )}
        {pot !== undefined && pot > 0n && (
          <div className={`text-2xl font-bold ${isTimeout ? "text-yellow-400" : "text-gold"}`}>
            +{formatEther(pot)} ETH
          </div>
        )}
        <div className="text-sm text-ink/80 font-mono">{shortAddr(winner)}</div>
        <div className="text-[10px] text-ink/40 uppercase tracking-widest">
          click to dismiss
        </div>
      </div>
    </div>
  );
}
