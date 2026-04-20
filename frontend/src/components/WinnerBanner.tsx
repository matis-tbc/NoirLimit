import { useEffect, useState } from "react";
import { formatEther, type Address } from "viem";
import { Card } from "./Card";

interface Props {
  winner?: Address;
  pot?: bigint;
  winnerCards?: [number, number] | null;
  trigger?: number; // bump to re-show (e.g. Date.now() on each HandSettled)
}

function shortAddr(a?: Address) {
  if (!a) return "-";
  return `${a.slice(0, 6)}...${a.slice(-4)}`;
}

// Full-screen overlay that fires when HandSettled is detected. Shows the
// winner, pot size, and revealed hole cards. Auto-dismisses after 6s; click
// to dismiss earlier.
export function WinnerBanner({ winner, pot, winnerCards, trigger }: Props) {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    if (!trigger) return;
    setVisible(true);
    const t = setTimeout(() => setVisible(false), 6000);
    return () => clearTimeout(t);
  }, [trigger]);

  if (!visible || !winner) return null;

  return (
    <div
      onClick={() => setVisible(false)}
      className="fixed inset-0 z-40 bg-black/80 flex items-center justify-center animate-[fadein_200ms_ease-out] cursor-pointer"
    >
      <div className="border border-gold p-8 bg-bg flex flex-col items-center gap-4 max-w-md">
        <div className="text-xs uppercase tracking-[0.3em] text-ink/50">
          Hand settled
        </div>
        {winnerCards && (
          <div className="flex gap-2">
            <Card card={winnerCards[0]} size="lg" />
            <Card card={winnerCards[1]} size="lg" />
          </div>
        )}
        <div className="text-gold text-2xl font-bold">
          {pot !== undefined ? `+${formatEther(pot)} ETH` : "winner"}
        </div>
        <div className="text-sm text-ink/80 font-mono">{shortAddr(winner)}</div>
        <div className="text-[10px] text-ink/40 uppercase tracking-widest">
          click to dismiss
        </div>
      </div>
    </div>
  );
}
