import { useMemo, useState } from "react";
import { parseEther } from "viem";
import { ActionCode, Phase } from "../utils/phase";
import type { LogEntry } from "../hooks/usePokerTable";

interface Props {
  enabled: boolean;
  isPending: boolean;
  phase: number;
  logs: LogEntry[];
  lastError?: string | null;
  onAct: (action: ActionCode, raise?: bigint) => void;
}

// Without a contract-side `currentBet` getter we use a heuristic: count the
// number of ActionTaken events for this table since the last phase advance.
// On the FIRST action of a betting round:
//   - PREFLOP: small blind owes BB/2 -> CHECK is invalid
//   - FLOP_BET / TURN_BET / RIVER_BET: nothing to call -> CALL is invalid
// After any action this round we re-enable both buttons (we no longer know
// for sure who owes what; let the contract decide).
function deriveActionContext(phase: number, logs: LogEntry[]) {
  const isBetting =
    phase === Phase.PREFLOP ||
    phase === Phase.FLOP_BET ||
    phase === Phase.TURN_BET ||
    phase === Phase.RIVER_BET;
  if (!isBetting) return { canCheck: true, canCall: true, isFirstAction: false };

  // Count ActionTaken events since the last phase advance event. A phase
  // advance is approximated by the latest CommunityCardsRevealed (for
  // post-flop rounds) or PlayerJoined (for the first preflop round).
  const reversed = [...logs].reverse();
  let actionsThisRound = 0;
  for (const l of reversed) {
    if (
      l.eventName === "CommunityCardsRevealed" ||
      l.eventName === "PlayerJoined" ||
      l.eventName === "TableCreated"
    ) {
      break;
    }
    if (l.eventName === "ActionTaken") actionsThisRound += 1;
  }
  const isFirstAction = actionsThisRound === 0;
  const canCheck = phase === Phase.PREFLOP ? !isFirstAction : true;
  const canCall = phase === Phase.PREFLOP ? true : !isFirstAction;
  return { canCheck, canCall, isFirstAction };
}

function parseEthSafe(v: string): { wei: bigint; error: string | null } {
  if (!v.trim()) return { wei: 0n, error: "enter an amount" };
  if (v.startsWith("-")) return { wei: 0n, error: "must be positive" };
  try {
    const wei = parseEther(v);
    if (wei <= 0n) return { wei: 0n, error: "must be > 0" };
    return { wei, error: null };
  } catch {
    return { wei: 0n, error: "invalid amount" };
  }
}

export function ActionBar({
  enabled,
  isPending,
  phase,
  logs,
  lastError,
  onAct,
}: Props) {
  const [raise, setRaise] = useState("0.0002");
  const ctx = useMemo(() => deriveActionContext(phase, logs), [phase, logs]);
  const raiseParsed = useMemo(() => parseEthSafe(raise), [raise]);

  const Btn = ({
    label,
    onClick,
    disabled,
    title,
  }: {
    label: string;
    onClick: () => void;
    disabled?: boolean;
    title?: string;
  }) => (
    <button
      onClick={onClick}
      disabled={!enabled || isPending || disabled}
      title={title}
      className="px-4 py-2 border border-edge hover:border-gold disabled:opacity-30 transition uppercase tracking-widest text-sm"
    >
      {label}
    </button>
  );

  const checkTip = !ctx.canCheck
    ? phase === Phase.PREFLOP
      ? "you owe the big blind - call or raise"
      : undefined
    : undefined;
  const callTip = !ctx.canCall
    ? "nothing to call - check or raise"
    : undefined;

  return (
    <div className="space-y-2">
      <div className="flex gap-2 items-center p-3 border border-edge rounded">
        <Btn label="Fold" onClick={() => onAct(ActionCode.FOLD)} />
        <Btn
          label="Check"
          onClick={() => onAct(ActionCode.CHECK)}
          disabled={!ctx.canCheck}
          title={checkTip}
        />
        <Btn
          label="Call"
          onClick={() => onAct(ActionCode.CALL)}
          disabled={!ctx.canCall}
          title={callTip}
        />
        <div className="flex items-center gap-2 ml-2">
          <input
            value={raise}
            onChange={(e) => setRaise(e.target.value)}
            className="bg-[#111] border border-edge px-2 py-1 w-24 text-sm"
          />
          <span className="text-xs">ETH</span>
          <Btn
            label="Raise"
            onClick={() => onAct(ActionCode.RAISE, raiseParsed.wei)}
            disabled={!!raiseParsed.error}
            title={raiseParsed.error || undefined}
          />
        </div>
        {isPending && (
          <span className="text-[11px] text-yellow-400 ml-2 animate-pulse">
            broadcasting...
          </span>
        )}
      </div>
      {raiseParsed.error && enabled && (
        <div className="text-[11px] text-red-400 px-3">{raiseParsed.error}</div>
      )}
      {lastError && (
        <div className="text-[11px] text-red-400 px-3">{lastError}</div>
      )}
    </div>
  );
}
