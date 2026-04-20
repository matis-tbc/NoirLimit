import { useState } from "react";
import { Link, useNavigate } from "react-router-dom";
import { formatEther, parseEther } from "viem";
import { useGameActions } from "../hooks/useGameActions";
import { tableIdFromCreateTx, recallStakes } from "../utils/createTable";
import { Phase } from "../utils/phase";

interface Props {
  tableId: bigint;
  phase: number;
}

// Renders only on terminal phases (caller gates on isTerminal). Gives the
// user two clear next steps so the URL is never a dead end. Buy-in for the
// rematch comes from localStorage (remembered when the user last created
// a table) so we never show a misleading post-settlement stack as the price.
export function TerminalPanel({ tableId, phase }: Props) {
  const nav = useNavigate();
  const actions = useGameActions();
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  const label =
    phase === Phase.SETTLED
      ? "Hand settled"
      : phase === Phase.CANCELLED
        ? "Hand cancelled (timeout)"
        : "Hand over";

  const stakes = recallStakes();
  const rematchBuyIn = stakes?.buyIn ?? parseEther("0.001");
  const rematchBb = stakes?.bb ?? rematchBuyIn / 10n;

  const playAgain = async () => {
    setBusy(true);
    setErr(null);
    try {
      const hash = (await actions.createTable(rematchBb, rematchBuyIn)) as `0x${string}`;
      const newId = await tableIdFromCreateTx(hash);
      if (newId === undefined) {
        setErr("Created the table but couldn't read its ID; check the lobby.");
        return;
      }
      nav(`/table/${newId.toString()}?bot=1`);
    } catch (e: any) {
      setErr(e?.shortMessage || e?.message?.split("\n")[0] || "Create failed");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="border border-gold/40 bg-gold/5 rounded p-4 space-y-3">
      <div className="flex items-center justify-between">
        <span className="text-xs uppercase tracking-widest text-gold/80">{label}</span>
        <span className="text-[11px] text-ink/50">Table #{tableId.toString()}</span>
      </div>
      <p className="text-sm text-ink/80">
        This hand is over. Start a fresh hand against the bot, or head back to the lobby.
      </p>
      <div className="flex flex-wrap gap-2">
        <button
          onClick={playAgain}
          disabled={busy || actions.isPending}
          className="px-3 py-2 border border-gold text-gold uppercase text-xs tracking-widest hover:bg-gold hover:text-bg disabled:opacity-30"
        >
          {busy ? "creating..." : `Play again (${formatEther(rematchBuyIn)} ETH)`}
        </button>
        <Link
          to="/"
          className="px-3 py-2 border border-edge text-ink/80 uppercase text-xs tracking-widest hover:border-gold"
        >
          Back to lobby
        </Link>
      </div>
      {err && <div className="text-[11px] text-red-400">{err}</div>}
    </div>
  );
}
