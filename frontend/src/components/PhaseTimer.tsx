import { useEffect, useState } from "react";
import { isTerminal } from "../utils/phase";

interface Props {
  phase: number;
  // bumps when phase changes; resets the timer
  resetKey: string;
  compact?: boolean;
}

const TIMEOUT = 120; // matches contract actionTimeout

// Local-clock timer for the current phase. Resets whenever resetKey changes
// (typically on phase advance). Not authoritative - the on-chain deadline is
// the source of truth - but useful demo signal so a user sees "we are 8s in"
// versus "we are 110s in, about to time out."
export function PhaseTimer({ phase, resetKey, compact }: Props) {
  const terminal = isTerminal(phase);
  const [start, setStart] = useState(() => Date.now());
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    if (terminal) return;
    setStart(Date.now());
    setNow(Date.now());
  }, [resetKey, phase, terminal]);

  useEffect(() => {
    if (terminal) return;
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, [terminal]);

  if (terminal) return null;

  const elapsed = Math.floor((now - start) / 1000);
  const remaining = Math.max(0, TIMEOUT - elapsed);
  const pct = Math.min(100, (elapsed / TIMEOUT) * 100);
  const color =
    elapsed >= 100
      ? "bg-red-500"
      : elapsed >= 60
        ? "bg-yellow-500"
        : "bg-green-500";
  const textColor =
    elapsed >= 100
      ? "text-red-300"
      : elapsed >= 60
        ? "text-yellow-300"
        : "text-ink/70";

  if (compact) {
    return (
      <span className={`text-[10px] font-mono ${textColor}`}>
        {elapsed}s / {TIMEOUT}s
      </span>
    );
  }

  return (
    <div className="space-y-1">
      <div className="flex items-center justify-between text-[10px] uppercase tracking-widest">
        <span className="text-ink/50">Phase elapsed</span>
        <span className={`font-mono ${textColor}`}>
          {elapsed}s / {TIMEOUT}s ({remaining}s remaining)
        </span>
      </div>
      <div className="h-1 bg-edge rounded overflow-hidden">
        <div
          className={`h-full ${color} transition-all duration-1000`}
          style={{ width: `${pct}%` }}
        />
      </div>
      {elapsed >= 100 && (
        <div className="text-[10px] text-red-400">
          Approaching deadline. Anyone can call claimTimeout(tableId) after 120s.
        </div>
      )}
    </div>
  );
}
