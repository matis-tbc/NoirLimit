import { useParams, useSearchParams } from "react-router-dom";
import { useEffect, useMemo, useState } from "react";
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
import { CheatButton } from "../components/CheatButton";
import { WinnerBanner } from "../components/WinnerBanner";
import { TimeoutButton } from "../components/TimeoutButton";
import { PhaseTimer } from "../components/PhaseTimer";
import { TerminalPanel } from "../components/TerminalPanel";
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
  useAutoSubmit({
    tableId,
    table,
    seatIndex,
    enabled: seatIndex !== -1 && !terminal,
    publicKeyRegistered: pkRegistered,
    setPublicKeyRegistered: setPkRegistered,
  });

  if (!table) {
    return <div className="p-8 text-ink/50">Loading table...</div>;
  }

  const phase = table.phase as Phase;
  const overlayActive = seatIndex !== -1 && !terminal && (isAutoPhase(phase) || phase === Phase.SHOWDOWN);

  // Track when the current phase started so TimeoutButton can show a real
  // countdown to the on-chain 120s deadline. Local-clock; resets on advance.
  const [phaseStartMs, setPhaseStartMs] = useState(() => Date.now());
  useEffect(() => {
    setPhaseStartMs(Date.now());
  }, [phase, tableId?.toString()]);

  // Reveal opponent cards on any terminal state past DEALING (the deterministic
  // deal makes them recoverable; we hide nothing once the hand is over).
  const showOpponent = terminal && phase !== Phase.WAITING && phaseFromTable >= Phase.PREFLOP;
  const opponentCards = showOpponent && tableId !== undefined
    ? (() => {
        const dealt = dealHoleCards(tableId, table.players[0], table.players[1]);
        return seatIndex === 0 ? dealt.p2 : dealt.p1;
      })()
    : null;

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

  return (
    <div className="max-w-5xl mx-auto px-6 py-6 space-y-6">
      <ZKReveal active={overlayActive} phase={phase} tableId={tableId} />
      <WinnerBanner
        winner={settled?.winner}
        pot={settled?.pot}
        winnerCards={winnerCards}
        reason={settled?.reason}
        trigger={bannerTrigger}
      />

      <header className="flex items-center justify-between">
        <h1 className="text-xl font-bold tracking-widest">TABLE #{id}</h1>
        <div className="text-sm text-ink/70 flex items-center gap-3">
          <span>{PHASE_LABELS[phase]}</span>
          <PhaseTimer
            phase={phase}
            resetKey={`${tableId?.toString()}-${phase}`}
            compact
          />
          <span>- pot {formatEther(table.pot)} ETH</span>
        </div>
        <div className="flex items-center gap-3">
          {!terminal && (
            <TimeoutButton tableId={tableId} phase={phase} phaseStartMs={phaseStartMs} />
          )}
          <label className="text-xs flex items-center gap-2">
            <input
              type="checkbox"
              checked={botEnabled}
              onChange={(e) => onBotToggle(e.target.checked)}
              disabled={terminal}
            />
            Bot {terminal ? "(stopped)" : botActing ? "(acting...)" : ""}
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

      {!terminal && (
        <ActionBar
          enabled={isBettingPhase(phase) && isMyTurn}
          isPending={actions.isPending}
          phase={phase}
          logs={logs}
          lastError={actions.lastError}
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

      {!terminal && <CheatButton tableId={tableId} phase={phase} />}

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
