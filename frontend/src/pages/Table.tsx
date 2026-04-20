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
import { Phase, PHASE_LABELS, isAutoPhase, isBettingPhase } from "../utils/phase";
import { dealHoleCards } from "../utils/deal";

export default function Table() {
  const { id } = useParams<{ id: string }>();
  const [search] = useSearchParams();
  const tableId = id ? BigInt(id) : undefined;
  const { address } = useAccount();
  const { table, seatIndex, isMyTurn, holeCards, communityCards } = usePokerTable(tableId);
  const logs = usePokerEvents(tableId);
  const actions = useGameActions();

  // Bot mode is opt-in via ?bot=1 (set by the Lobby when creating in bot mode).
  const [botEnabled, setBotEnabled] = useState(search.get("bot") === "1");
  const { botAddress, acting: botActing } = useDemoBot(tableId, botEnabled);

  const onBotToggle = (next: boolean) => {
    if (botEnabled && !next) {
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
    enabled: seatIndex !== -1,
    publicKeyRegistered: pkRegistered,
    setPublicKeyRegistered: setPkRegistered,
  });

  if (!table) {
    return <div className="p-8 text-ink/50">Loading table\u2026</div>;
  }

  const phase = table.phase as Phase;
  const overlayActive = seatIndex !== -1 && (isAutoPhase(phase) || phase === Phase.SHOWDOWN);

  // Determine the opponent's hole cards visibility (only after SHOWDOWN settled).
  const showOpponent = phase === Phase.SETTLED;
  const opponentCards = showOpponent && tableId !== undefined
    ? (() => {
        const dealt = dealHoleCards(tableId, table.players[0], table.players[1]);
        return seatIndex === 0 ? dealt.p2 : dealt.p1;
      })()
    : null;

  // Detect HandSettled events to trigger the winner banner. Reverse so we get
  // the most recent settle, not the first historical one in the log buffer.
  const settled = useMemo(() => {
    const s = [...logs].reverse().find((l) => l.eventName === "HandSettled");
    if (!s) return null;
    return { winner: s.args.winner as Address, pot: s.args.pot as bigint };
  }, [logs]);
  const [bannerTrigger, setBannerTrigger] = useState(0);
  useEffect(() => {
    if (settled) setBannerTrigger(Date.now());
  }, [settled?.winner, settled?.pot]);
  const winnerCards = useMemo<[number, number] | null>(() => {
    if (!settled || tableId === undefined || !table) return null;
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
        trigger={bannerTrigger}
      />

      <header className="flex items-center justify-between">
        <h1 className="text-xl font-bold tracking-widest">TABLE #{id}</h1>
        <div className="text-sm text-ink/70">
          {PHASE_LABELS[phase]}  -  pot {formatEther(table.pot)} ETH
        </div>
        <div className="flex items-center gap-3">
          <TimeoutButton tableId={tableId} phase={phase} />
          <label className="text-xs flex items-center gap-2">
            <input
              type="checkbox"
              checked={botEnabled}
              onChange={(e) => onBotToggle(e.target.checked)}
            />
            Bot {botActing ? "(acting...)" : ""}
          </label>
        </div>
      </header>

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
            <Card key={i} card={communityCards[i]} size="lg" />
          ))}
        </div>
      </div>

      <ActionBar
        enabled={isBettingPhase(phase) && isMyTurn}
        isPending={actions.isPending}
        onAct={(a, raise) => {
          if (tableId !== undefined) actions.act(tableId, a, raise || 0n);
        }}
      />

      {botEnabled && botAddress && (
        <div className="text-xs text-ink/40">
          Bot: {botAddress}
        </div>
      )}

      <CheatButton tableId={tableId} phase={phase} />

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
