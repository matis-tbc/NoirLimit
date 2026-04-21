import { useEffect, useMemo, useState } from "react";
import { parseEther } from "viem";
import { ActionCode, Phase } from "../utils/phase";
import type { LogEntry } from "../hooks/usePokerTable";
import { TimeoutButton } from "./TimeoutButton";

interface Props {
  enabled: boolean;
  isPending: boolean;
  phase: number;
  logs: LogEntry[];
  lastError?: string | null;
  // When elapsed >= 120s the on-chain deadline has passed; act() reverts
  // unconditionally with "deadline passed" until claimTimeout settles the
  // table. We disable buttons rather than let the user submit doomed txs.
  phaseStartMs?: number;
  tableId?: bigint;
  onAct: (action: ActionCode, raise?: bigint) => void;
}

const DEADLINE_MS = 120_000;
// When the deadline is this close, surface the TimeoutButton adjacent to the
// action buttons so the user doesn't have to hunt the header for recovery.
const DEADLINE_NEAR_MS = 90_000;

// UI-side mirror of the contract's can-check / can-call rules. The contract
// at PokerTable.sol:309 computes toCall = currentBet - roundContribution,
// then rejects CHECK when toCall > 0 and CALL when toCall == 0. We can't
// read currentBet directly from getTable(), so we derive from the
// ActionTaken event stream for the current betting round:
//
//   - Round boundary = latest CommunityCardsRevealed / PlayerJoined /
//     TableCreated. ActionTaken events before that belong to a previous
//     round.
//   - PREFLOP special case: before any action, SB owes BB so CHECK is
//     invalid and CALL is valid.
//   - After any RAISE in the round, the non-raising seat faces a bet:
//     CALL / RAISE / FOLD are valid, CHECK is not.
//   - After any CHECK or CALL with no subsequent RAISE, no one owes: only
//     CHECK / RAISE / FOLD are valid, CALL is not.
//
// The contract is still the source of truth; if our derivation is wrong
// the tx reverts and the user sees the reason in lastError.
function deriveActionContext(phase: number, logs: LogEntry[]) {
  const isBetting =
    phase === Phase.PREFLOP ||
    phase === Phase.FLOP_BET ||
    phase === Phase.TURN_BET ||
    phase === Phase.RIVER_BET;
  if (!isBetting) {
    return {
      canCheck: true,
      canCall: true,
      isFirstAction: false,
      facingRaise: false,
    };
  }

  const reversed = [...logs].reverse();
  const roundActions: LogEntry[] = [];
  for (const l of reversed) {
    if (
      l.eventName === "CommunityCardsRevealed" ||
      l.eventName === "PlayerJoined" ||
      l.eventName === "TableCreated"
    ) {
      break;
    }
    if (l.eventName === "ActionTaken") roundActions.unshift(l);
  }

  const isFirstAction = roundActions.length === 0;
  const last = roundActions[roundActions.length - 1]?.args;
  // Action enum in the contract: 0 FOLD, 1 CHECK, 2 CALL, 3 RAISE.
  const facingRaise = last ? Number(last.action) === 3 : false;

  if (phase === Phase.PREFLOP && isFirstAction) {
    // SB acts first preflop; BB is a standing bet. SB must call, raise, or
    // fold. CHECK is invalid.
    return { canCheck: false, canCall: true, isFirstAction: true, facingRaise: true };
  }

  if (facingRaise) {
    return { canCheck: false, canCall: true, isFirstAction: false, facingRaise: true };
  }

  // Post a CHECK or CALL with no subsequent raise: nothing to call.
  return { canCheck: true, canCall: false, isFirstAction, facingRaise: false };
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
  phaseStartMs,
  tableId,
  onAct,
}: Props) {
  const [raise, setRaise] = useState("0.0002");
  const [now, setNow] = useState(() => Date.now());
  const ctx = useMemo(() => deriveActionContext(phase, logs), [phase, logs]);
  const raiseParsed = useMemo(() => parseEthSafe(raise), [raise]);

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);
  const elapsed = phaseStartMs !== undefined ? now - phaseStartMs : 0;
  const expired = phaseStartMs !== undefined && elapsed >= DEADLINE_MS;
  const deadlineNear = phaseStartMs !== undefined && elapsed >= DEADLINE_NEAR_MS;
  const effectiveEnabled = enabled && !expired;

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
      disabled={!effectiveEnabled || isPending || disabled}
      title={expired ? "deadline passed - use Claim Timeout to recover" : title}
      className="px-4 py-2 border border-edge hover:border-gold disabled:opacity-30 transition uppercase tracking-widest text-sm"
    >
      {label}
    </button>
  );

  const checkTip = !ctx.canCheck
    ? phase === Phase.PREFLOP && ctx.isFirstAction
      ? "you owe the big blind - call, raise, or fold"
      : "facing a bet - call, raise, or fold"
    : undefined;
  const callTip = !ctx.canCall
    ? "nothing to call - check, raise, or fold"
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
        <span
          className="text-[11px] text-yellow-400 ml-2 animate-pulse"
          style={{ visibility: isPending ? "visible" : "hidden" }}
        >
          broadcasting...
        </span>
        <div className="ml-auto" style={{ minWidth: 150 }}>
          {deadlineNear && (
            <TimeoutButton
              tableId={tableId}
              phase={phase}
              phaseStartMs={phaseStartMs}
            />
          )}
        </div>
      </div>
      {expired && enabled && (
        <div className="text-[11px] text-red-400 px-3">
          Phase deadline passed (120s). Click Claim Timeout in the header to settle.
        </div>
      )}
      {raiseParsed.error && enabled && (
        <div className="text-[11px] text-red-400 px-3">{raiseParsed.error}</div>
      )}
      {lastError && (
        <div className="text-[11px] text-red-400 px-3">{lastError}</div>
      )}
    </div>
  );
}
