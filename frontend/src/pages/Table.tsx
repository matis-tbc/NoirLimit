import { useParams, useSearchParams } from "react-router-dom";
import { useEffect, useMemo, useRef, useState } from "react";
import { useAccount } from "wagmi";
import { formatEther, type Address } from "viem";
import { usePokerTable, usePokerEvents } from "../hooks/usePokerTable";
import { useGameActions } from "../hooks/useGameActions";
import { useAutoSubmit } from "../hooks/useAutoSubmit";
import { useDemoBot } from "../hooks/useDemoBot";
import { Seat } from "../components/Seat";
import { Card } from "../components/Card";
import { ActionBar } from "../components/ActionBar";
import { EventLog } from "../components/EventLog";
import { ZKReveal } from "../components/ZKReveal";
import { DebugPanel } from "../components/DebugPanel";
import { CheatMoment } from "../components/CheatMoment";
import { WinnerBanner } from "../components/WinnerBanner";
import { TimeoutButton } from "../components/TimeoutButton";
import { PhaseTimer } from "../components/PhaseTimer";
import { TerminalPanel } from "../components/TerminalPanel";
import { WalletPendingBanner } from "../components/WalletPendingBanner";
import { MoveHistory } from "../components/MoveHistory";
import { useHandSettled } from "../hooks/useHandSettled";
import { Phase, PHASE_LABELS, isAutoPhase, isBettingPhase, isTerminal } from "../utils/phase";
import { dealHoleCards } from "../utils/deal";

export default function Table() {
  const { id } = useParams<{ id: string }>();
  const [search] = useSearchParams();
  const tableId = id ? BigInt(id) : undefined;
  const { address } = useAccount();
  const { table, seatIndex, isMyTurn, holeCards, communityCards } = usePokerTable(tableId);
  const logs = usePokerEvents(tableId);
  const actions = useGameActions();

  const phaseFromTable = table?.phase ?? -1;
  const terminal = isTerminal(phaseFromTable);

  // Bot mode is opt-in via ?bot=1 (set by the Lobby when creating in bot mode).
  const [botEnabled, setBotEnabled] = useState(search.get("bot") === "1");
  const { botAddress, acting: botActing, wedged: botWedged } = useDemoBot(
    tableId,
    botEnabled,
    table?.phase
  );

  const onBotToggle = (next: boolean) => {
    if (botEnabled && !next && !terminal) {
      const ok = confirm(
        "Bot is mid-action. Turning off will stall the hand until you call Claim Timeout. Continue?"
      );
      if (!ok) return;
    }
    setBotEnabled(next);
  };

  const [pkRegistered, setPkRegistered] = useState(false);
  // Reset on tableId change so switching tables re-registers the host key.
  useEffect(() => {
    setPkRegistered(false);
  }, [tableId?.toString()]);

  // When the user attempts a cheat at SHOWDOWN, this ref flips true and
  // useAutoSubmit skips auto-revealing the user's real cards so the cheat tx
  // hits the contract first. After the cheat resolves (a revert or the
  // rare success path) the user clicks "Submit real reveal" in CheatMoment
  // to finish the hand via useGameActions.revealHand.
  const cheatAttemptedRef = useRef(false);
  useEffect(() => {
    // New hand -> reset the gate.
    cheatAttemptedRef.current = false;
  }, [tableId?.toString()]);

  useAutoSubmit({
    tableId,
    table,
    seatIndex,
    enabled: seatIndex !== -1 && !terminal,
    publicKeyRegistered: pkRegistered,
    setPublicKeyRegistered: setPkRegistered,
    skipShowdownRevealRef: cheatAttemptedRef,
  });

  const phase = (table?.phase ?? Phase.WAITING) as Phase;
  const overlayActive =
    !!table && seatIndex !== -1 && !terminal && (isAutoPhase(phase) || phase === Phase.SHOWDOWN);

  // Flash a "+N" next to the pot for 3s whenever it grows. Gives the user a
  // visible confirmation that their chips went to the pot (pairs with the
  // Seat component's stack-decrease delta). Undefined ref until the first
  // real pot read so we don't flash on initial mount.
  const prevPotRef = useRef<bigint | undefined>(undefined);
  const [potDelta, setPotDelta] = useState<bigint>(0n);
  useEffect(() => {
    const cur = table?.pot;
    if (cur === undefined) return;
    if (prevPotRef.current === undefined) {
      prevPotRef.current = cur;
      return;
    }
    const d = cur - prevPotRef.current;
    prevPotRef.current = cur;
    if (d <= 0n) return;
    setPotDelta(d);
    const id = setTimeout(() => setPotDelta(0n), 3000);
    return () => clearTimeout(id);
  }, [table?.pot]);

  // Track when the current *action window* started so TimeoutButton shows a
  // real countdown to the on-chain deadline. The contract resets the deadline
  // on EVERY successful action (PokerTable.sol:361), not just on phase
  // advance. So reset on turn flips AND phase changes AND tableId changes.
  const [phaseStartMs, setPhaseStartMs] = useState(() => Date.now());
  useEffect(() => {
    setPhaseStartMs(Date.now());
  }, [phase, table?.turn, tableId?.toString()]);

  // Detect terminal events (HandSettled OR TimeoutClaimed) for the banner.
  const liveSettled = useMemo(() => {
    const reversed = [...logs].reverse();
    const handSettled = reversed.find((l) => l.eventName === "HandSettled");
    if (handSettled) {
      return {
        winner: handSettled.args.winner as Address,
        pot: handSettled.args.pot as bigint,
        reason: "settled" as const,
      };
    }
    const timeoutClaimed = reversed.find((l) => l.eventName === "TimeoutClaimed");
    if (timeoutClaimed) {
      return {
        winner: timeoutClaimed.args.beneficiary as Address,
        pot: 0n,
        reason: "timeout" as const,
      };
    }
    return null;
  }, [logs]);
  const backfill = useHandSettled(terminal && !liveSettled ? tableId : undefined);
  const settled = liveSettled
    ? liveSettled
    : backfill
      ? { winner: backfill.winner, pot: backfill.pot, reason: backfill.reason }
      : null;
  const [bannerTrigger, setBannerTrigger] = useState(0);
  useEffect(() => {
    if (settled) setBannerTrigger(Date.now());
  }, [settled?.winner, settled?.pot, settled?.reason]);
  const winnerCards = useMemo<[number, number] | null>(() => {
    if (!settled || tableId === undefined || !table) return null;
    if (settled.reason === "timeout") return null;
    const dealt = dealHoleCards(tableId, table.players[0], table.players[1]);
    const winnerIsP0 =
      settled.winner.toLowerCase() === table.players[0].toLowerCase();
    return winnerIsP0 ? dealt.p1 : dealt.p2;
  }, [settled, tableId, table]);

  if (!table) {
    return <div className="p-8 text-ink/50">Loading table...</div>;
  }

  // Reveal opponent cards on any terminal state past DEALING (the deterministic
  // deal makes them recoverable; we hide nothing once the hand is over).
  const showOpponent = terminal && phase !== Phase.WAITING && phaseFromTable >= Phase.PREFLOP;
  const opponentCards = showOpponent && tableId !== undefined
    ? (() => {
        const dealt = dealHoleCards(tableId, table.players[0], table.players[1]);
        return seatIndex === 0 ? dealt.p2 : dealt.p1;
      })()
    : null;

  return (
    <div className="max-w-5xl mx-auto px-6 py-6 space-y-6">
      <WalletPendingBanner pending={actions.isPending} />
      <ZKReveal
        active={overlayActive}
        phase={phase}
        tableId={tableId}
        phaseStartMs={phaseStartMs}
      />
      <WinnerBanner
        winner={settled?.winner}
        pot={settled?.pot}
        winnerCards={winnerCards}
        reason={settled?.reason}
        trigger={bannerTrigger}
      />

      <header className="flex items-center justify-between gap-4">
        <h1 className="text-xl font-bold tracking-widest shrink-0">
          TABLE #{id}
        </h1>
        <div className="text-sm text-ink/70 flex items-center gap-3 font-mono tabular-nums">
          <span>{PHASE_LABELS[phase]}</span>
          <PhaseTimer
            phase={phase}
            resetKey={`${tableId?.toString()}-${phase}-${table.turn}`}
            compact
          />
          <span className="inline-flex items-baseline gap-1">
            - pot {formatEther(table.pot)} ETH
            {potDelta > 0n && (
              <span className="text-[10px] text-green-400">
                +{formatEther(potDelta)}
              </span>
            )}
          </span>
        </div>
        <div className="flex items-center gap-3 shrink-0">
          <div style={{ minWidth: 120 }}>
            {!terminal && (
              <TimeoutButton tableId={tableId} phase={phase} phaseStartMs={phaseStartMs} />
            )}
          </div>
          <label className="text-xs flex items-center gap-2" style={{ minWidth: 120 }}>
            <input
              type="checkbox"
              checked={botEnabled}
              onChange={(e) => onBotToggle(e.target.checked)}
              disabled={terminal}
            />
            <span className="inline-flex items-center gap-1.5">
              <span
                className={
                  "w-1.5 h-1.5 rounded-full " +
                  (terminal
                    ? "bg-ink/30"
                    : botActing
                      ? "bg-yellow-400 animate-pulse"
                      : "bg-green-500/70")
                }
              />
              Bot
              <span className="text-ink/40 text-[10px] uppercase tracking-widest">
                {terminal ? "stopped" : botActing ? "acting" : "idle"}
              </span>
            </span>
          </label>
        </div>
      </header>

      {botWedged && (
        <div className="border border-red-700 bg-red-950/30 text-red-200 text-xs rounded p-3">
          {botWedged}
        </div>
      )}

      {terminal && <TerminalPanel tableId={tableId!} phase={phase} />}

      <div className="grid grid-cols-2 gap-4">
        <Seat
          label={seatIndex === 0 ? "You" : "Player 1"}
          address={table.players[0]}
          stack={table.stacks[0]}
          cards={seatIndex === 0 ? holeCards : (showOpponent ? opponentCards : null)}
          hidden={seatIndex !== 0 && !showOpponent}
          active={table.turn === 0 && isBettingPhase(phase)}
        />
        <Seat
          label={seatIndex === 1 ? "You" : "Player 2"}
          address={table.players[1]}
          stack={table.stacks[1]}
          cards={seatIndex === 1 ? holeCards : (showOpponent ? opponentCards : null)}
          hidden={seatIndex !== 1 && !showOpponent}
          active={table.turn === 1 && isBettingPhase(phase)}
        />
      </div>

      <div className="rounded border border-edge bg-felt/40 p-6">
        <div className="text-xs uppercase tracking-widest text-ink/50 mb-3">Board</div>
        <div className="flex gap-3 justify-center">
          {[0, 1, 2, 3, 4].map((i) => (
            <Card key={i} card={communityCards[i]} size="lg" index={i} />
          ))}
        </div>
      </div>

      <MoveHistory
        logs={logs}
        youAddress={address}
        botAddress={botEnabled ? botAddress : undefined}
      />

      {!terminal && (
        <ActionBar
          enabled={isBettingPhase(phase) && isMyTurn}
          isPending={actions.isPending}
          phase={phase}
          logs={logs}
          lastError={actions.lastError}
          phaseStartMs={phaseStartMs}
          tableId={tableId}
          onAct={(a, raise) => {
            if (tableId !== undefined) actions.act(tableId, a, raise || 0n);
          }}
        />
      )}

      {botEnabled && botAddress && (
        <div className="text-xs text-ink/40">
          Bot: {botAddress}
        </div>
      )}

      {!terminal && (
        <CheatMoment
          tableId={tableId}
          phase={phase}
          realCards={
            tableId !== undefined && seatIndex !== -1
              ? (() => {
                  const dealt = dealHoleCards(
                    tableId,
                    table.players[0],
                    table.players[1]
                  );
                  return seatIndex === 0 ? dealt.p1 : dealt.p2;
                })()
              : null
          }
          onAttempt={() => {
            cheatAttemptedRef.current = true;
          }}
          onRealReveal={async (cards) => {
            if (tableId === undefined) return;
            await actions.revealHand(tableId, cards);
          }}
        />
      )}

      <DebugPanel
        tableId={tableId}
        table={table}
        seatIndex={seatIndex}
        hostAddress={address}
        botAddress={botAddress}
      />

      <EventLog logs={logs} />
    </div>
  );
}
