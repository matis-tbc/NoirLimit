import { useParams } from "react-router-dom";
import { useEffect, useMemo, useState } from "react";
import { useAccount } from "wagmi";
import { formatEther, parseEther, type Address } from "viem";
import { usePokerTable } from "../hooks/usePokerTable";
import { useSpectatorMarket, spectatorEnabled } from "../hooks/useSpectatorMarket";
import { Seat } from "../components/Seat";
import { Card } from "../components/Card";
import { OddsBar } from "../components/OddsBar";
import { OddsSparkline } from "../components/OddsSparkline";
import { SealedStateBadge } from "../components/SealedStateBadge";
import { MoveHistory } from "../components/MoveHistory";
import { WagerTicker } from "../components/WagerTicker";
import { usePokerEvents } from "../hooks/usePokerTable";
import { Phase, PHASE_LABELS } from "../utils/phase";

const MAX_HISTORY = 20;

export default function Spectator() {
  const { id } = useParams<{ id: string }>();
  const tableId = id ? BigInt(id) : undefined;
  const { address } = useAccount();
  const { table, communityCards } = usePokerTable(tableId);
  const logs = usePokerEvents(tableId);
  const market = useSpectatorMarket(tableId, address);
  const [wagerAmt, setWagerAmt] = useState("0.0002");

  const pools = useMemo(() => {
    const m = market.market as any[] | undefined;
    if (!m) return { pool0: 0n, pool1: 0n, resolved: false };
    return {
      pool0: m[1] as bigint,
      pool1: m[2] as bigint,
      resolved: m[3] as boolean,
    };
  }, [market.market]);

  // Bounded history of the P1 win-probability implied by pool ratios. Sampled
  // on every pools change, deduped when the percentage doesn't move, capped
  // at MAX_HISTORY so a long hand doesn't blow up render depth.
  const [oddsHistory, setOddsHistory] = useState<
    Array<{ pct0: number; ts: number }>
  >([]);
  useEffect(() => {
    const total = pools.pool0 + pools.pool1;
    if (total === 0n) return;
    const pct0 = Number((pools.pool0 * 10000n) / total) / 100;
    setOddsHistory((prev) => {
      const last = prev[prev.length - 1];
      if (last && Math.abs(last.pct0 - pct0) < 0.01) return prev;
      const next = [...prev, { pct0, ts: Date.now() }];
      return next.length > MAX_HISTORY ? next.slice(-MAX_HISTORY) : next;
    });
  }, [pools.pool0, pools.pool1]);

  if (!spectatorEnabled) {
    return (
      <div className="max-w-3xl mx-auto p-8 space-y-4">
        <h1 className="text-xl font-bold tracking-widest">SPECTATE - TABLE #{id}</h1>
        <div className="border border-yellow-800/60 bg-yellow-900/10 rounded p-4 text-sm text-ink/80">
          <div className="text-yellow-400 text-xs uppercase tracking-widest mb-2">
            Spectator market coming soon
          </div>
          <p>
            The spectator wagering contract is not deployed on this build. Once
            the contract ships, you'll be able to place wagers on live hands and
            claim winnings when the table settles.
          </p>
          <details className="mt-3 text-[11px] text-ink/40">
            <summary className="cursor-pointer">for developers</summary>
            <p className="pt-2">
              Deploy <code>SpectatorMarket</code> and set{" "}
              <code>VITE_SPECTATOR_MARKET_ADDRESS</code> in{" "}
              <code>.env.local</code>.
            </p>
          </details>
        </div>
      </div>
    );
  }
  if (!table) return <div className="p-8 text-ink/50">Loading...</div>;

  const phase = table.phase as Phase;
  const wagerOpen =
    phase === Phase.SHUFFLE_P1 || phase === Phase.SHUFFLE_P2 || phase === Phase.DEALING;
  const settled = phase === Phase.SETTLED || phase === Phase.CANCELLED;

  // Block self-wagering: contract rejects players betting on their own table.
  const isPlayer =
    !!address &&
    (address.toLowerCase() === table.players[0].toLowerCase() ||
      address.toLowerCase() === table.players[1].toLowerCase());

  // Payout preview: after settle, losing side's ETH is distributed pro-rata to
  // the winning side based on contribution. Rough estimate: if user bets X on
  // side S with pool totals P_S / P_loser, expected payout = X + X * P_loser / P_S.
  const wagerParsed = (() => {
    if (!wagerAmt.trim()) return { wei: 0n, error: "enter an amount" };
    if (wagerAmt.startsWith("-")) return { wei: 0n, error: "must be positive" };
    try {
      const wei = parseEther(wagerAmt);
      if (wei <= 0n) return { wei: 0n, error: "must be > 0" };
      return { wei, error: null as string | null };
    } catch {
      return { wei: 0n, error: "invalid amount (try 0.001)" };
    }
  })();
  const amountWei = wagerParsed.wei;

  const previewFor = (side: 0 | 1): bigint => {
    const yourPool = side === 0 ? pools.pool0 : pools.pool1;
    const oppPool = side === 0 ? pools.pool1 : pools.pool0;
    if (amountWei === 0n) return 0n;
    // After your bet, your side pool grows; losing pool pays out.
    const newPool = yourPool + amountWei;
    if (newPool === 0n) return amountWei;
    return amountWei + (amountWei * oppPool) / newPool;
  };

  const countdown = wagerOpen
    ? "Wagering closes when dealing completes"
    : settled
      ? "Hand settled - claim winnings below"
      : "Wagering closed - watch hand play out";

  return (
    <div className="max-w-5xl mx-auto px-6 py-6 space-y-6">
      <header className="flex items-center justify-between">
        <h1 className="text-xl font-bold tracking-widest">SPECTATE - TABLE #{id}</h1>
        <div className="text-sm text-ink/70">
          {PHASE_LABELS[phase]} - pot {formatEther(table.pot)} ETH
        </div>
      </header>

      <div className="grid grid-cols-2 gap-4">
        <Seat
          label="Player 1"
          address={table.players[0]}
          stack={table.stacks[0]}
          hidden
          active={table.turn === 0}
        />
        <Seat
          label="Player 2"
          address={table.players[1]}
          stack={table.stacks[1]}
          hidden
          active={table.turn === 1}
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

      <div className="grid md:grid-cols-[1fr_320px] gap-4">
        <div className="border border-edge rounded p-4 space-y-4">
          <div className="flex items-center justify-between">
            <div className="text-xs uppercase tracking-widest text-ink/60">Market</div>
            <SealedStateBadge phase={phase} />
          </div>
          <OddsBar pool0={pools.pool0} pool1={pools.pool1} />
          <div>
            <div className="text-[10px] uppercase tracking-widest text-ink/50 mb-1">
              P1 odds (last {oddsHistory.length} changes)
            </div>
            <OddsSparkline points={oddsHistory} />
          </div>
          <div className="text-[11px] text-ink/60">{countdown}</div>

          {wagerOpen && isPlayer && (
            <div className="border border-yellow-700/50 bg-yellow-900/10 rounded p-3 text-[11px] text-yellow-300/90">
              You're playing this hand. Wagering is disabled for table players;
              the contract rejects self-wagers.
            </div>
          )}

          {wagerOpen && !isPlayer && (
            <div className="space-y-3">
              <div className="flex items-center gap-2">
                <input
                  value={wagerAmt}
                  onChange={(e) => setWagerAmt(e.target.value)}
                  className="bg-[#111] border border-edge px-2 py-1 w-28 font-mono"
                />
                <span className="text-xs text-ink/60">ETH</span>
              </div>
              {wagerParsed.error && (
                <div className="text-[11px] text-red-400">{wagerParsed.error}</div>
              )}
              <div className="grid grid-cols-2 gap-2">
                <button
                  disabled={market.isPending || amountWei === 0n}
                  onClick={() => market.placeWager(table.players[0], amountWei)}
                  className="border border-gold/60 text-gold p-3 uppercase text-xs tracking-widest hover:bg-gold/10 disabled:opacity-30"
                >
                  <div>Back P1</div>
                  <div className="text-[10px] text-ink/60 normal-case tracking-normal mt-1">
                    win ~{formatEther(previewFor(0))} ETH
                  </div>
                </button>
                <button
                  disabled={market.isPending || amountWei === 0n}
                  onClick={() => market.placeWager(table.players[1], amountWei)}
                  className="border border-red-500/60 text-red-300 p-3 uppercase text-xs tracking-widest hover:bg-red-900/20 disabled:opacity-30"
                >
                  <div>Back P2</div>
                  <div className="text-[10px] text-ink/60 normal-case tracking-normal mt-1">
                    win ~{formatEther(previewFor(1))} ETH
                  </div>
                </button>
              </div>
            </div>
          )}

          {settled && (
            <div className="flex gap-2 pt-2 items-center">
              <button
                disabled={market.isPending || pools.resolved}
                onClick={() => market.resolveWagers()}
                className="px-3 py-1.5 border border-edge text-xs uppercase tracking-widest disabled:opacity-30"
              >
                {pools.resolved ? "Resolved" : "Resolve"}
              </button>
              <button
                disabled={
                  market.isPending ||
                  !pools.resolved ||
                  !market.claimQuote ||
                  (market.claimQuote as bigint) === 0n
                }
                title={!pools.resolved ? "Resolve first" : undefined}
                onClick={() => market.claimWinnings()}
                className="px-3 py-1.5 border border-gold text-gold text-xs uppercase tracking-widest disabled:opacity-30"
              >
                Claim {market.claimQuote ? formatEther(market.claimQuote as bigint) : "0"} ETH
              </button>
              {!pools.resolved && (
                <span className="text-[10px] text-ink/40">
                  resolve first, then claim
                </span>
              )}
            </div>
          )}
        </div>

        <div className="space-y-4">
          <WagerTicker tableId={tableId} players={table.players as [Address, Address]} />
          <MoveHistory logs={logs} />
        </div>
      </div>
    </div>
  );
}
