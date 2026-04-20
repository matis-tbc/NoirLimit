import { useEffect, useMemo, useState } from "react";
import { useZkLog } from "../hooks/useZkLog";
import { Phase, PHASE_LABELS } from "../utils/phase";
import { TxChip } from "./TxChip";
import { PhaseTimer } from "./PhaseTimer";

interface Props {
  active: boolean;
  phase: number;
  tableId?: bigint;
}

// Replaces the opaque pulsing ZKOverlay with a three-beat reveal that makes
// the zero-knowledge step legible:
//   1. "Your view" - local cards / state visible only to you
//   2. "On-chain" - what the chain sees (ciphertext commitment + tx)
//   3. "Opponent's view" - permanent lock, cannot decrypt
// Must clear the grandma test: a non-crypto viewer watches 10s and can say
// back "his cards are locked in math, not hidden by a server."
export function ZKReveal({ active, phase, tableId }: Props) {
  const [beat, setBeat] = useState(0);
  const entries = useZkLog();

  // Pick the most useful tx to display in the "On-chain" beat:
  //   1. A pending tx for this table (regardless of phase) takes priority,
  //      so a tx still confirming after a phase advance stays visible.
  //   2. Otherwise the most recent matching-phase tx.
  // Without rule 1 the chip vanished at the moment users were most likely
  // to inspect the Etherscan link.
  const latest = useMemo(() => {
    if (tableId === undefined) return undefined;
    const reversed = entries.slice().reverse();
    const pending = reversed.find(
      (e) => e.tableId === tableId && e.status === "pending"
    );
    if (pending) return pending;
    return reversed.find((e) => e.tableId === tableId && e.phase === phase);
  }, [entries, phase, tableId]);

  useEffect(() => {
    if (!active) {
      setBeat(0);
      return;
    }
    setBeat(1);
    const t1 = setTimeout(() => setBeat(2), 1200);
    const t2 = setTimeout(() => setBeat(3), 2400);
    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
    };
  }, [active, phase]);

  if (!active) return null;

  const phaseLabel = PHASE_LABELS[phase] || "...";
  const phaseHint = getPhaseHint(phase);

  return (
    <div className="fixed inset-0 z-40 bg-black/85 backdrop-blur flex items-center justify-center">
      <div className="max-w-3xl w-[90%] border border-gold/50 bg-bg p-6 space-y-5">
        <div className="flex items-center justify-between">
          <div className="text-[10px] uppercase tracking-[0.3em] text-gold">
            Zero-knowledge step
          </div>
          <div className="text-xs text-ink/60">{phaseLabel}</div>
        </div>

        <p className="text-sm text-ink/80">{phaseHint}</p>

        <PhaseTimer
          phase={phase}
          resetKey={`${tableId?.toString()}-${phase}`}
        />

        <div className="grid grid-cols-3 gap-3 pt-2">
          <Beat
            active={beat >= 1}
            title="Your view"
            body="Cards computed locally. Only you see the plaintext."
            icon="eye"
          />
          <Beat
            active={beat >= 2}
            title="On-chain"
            body={
              latest
                ? `Encrypted commitment submitted. Tx confirmed.`
                : "Encrypted commitment submitted to Sepolia."
            }
            icon="chain"
            tx={latest?.txHash}
            txStatus={latest?.status}
          />
          <Beat
            active={beat >= 3}
            title="Opponent's view"
            body="Permanent lock. Even the RPC can't decrypt."
            icon="lock"
          />
        </div>

        <details className="text-[11px] text-ink/50">
          <summary className="cursor-pointer hover:text-ink/80">
            Raw transaction (for devs)
          </summary>
          <div className="mt-2 font-mono text-[10px] space-y-1 break-all">
            {latest ? (
              <>
                <div>fn: {latest.functionName}</div>
                <div>seat: {latest.seat}</div>
                <div>status: {latest.status}</div>
                <div>
                  hash:{" "}
                  <a
                    className="underline text-gold/80"
                    href={`https://sepolia.etherscan.io/tx/${latest.txHash}`}
                    target="_blank"
                    rel="noreferrer"
                  >
                    {latest.txHash}
                  </a>
                </div>
                {latest.gasUsed !== undefined && <div>gas: {latest.gasUsed.toString()}</div>}
              </>
            ) : (
              <div>awaiting tx...</div>
            )}
          </div>
        </details>
      </div>
    </div>
  );
}

function Beat({
  active,
  title,
  body,
  icon,
  tx,
  txStatus,
}: {
  active: boolean;
  title: string;
  body: string;
  icon: "eye" | "chain" | "lock";
  tx?: `0x${string}`;
  txStatus?: "pending" | "confirmed" | "reverted" | "unknown";
}) {
  return (
    <div
      className={
        "border rounded p-3 transition-all duration-500 " +
        (active
          ? "border-gold/60 bg-gold/5 opacity-100 translate-y-0"
          : "border-edge opacity-30 translate-y-1")
      }
    >
      <div className="flex items-center gap-2 text-[11px] uppercase tracking-widest text-gold/80 mb-1">
        <IconGlyph kind={icon} />
        {title}
      </div>
      <p className="text-[11px] text-ink/70 leading-snug">{body}</p>
      {tx && (
        <div className="mt-2">
          <TxChip hash={tx} status={txStatus} short />
        </div>
      )}
    </div>
  );
}

function IconGlyph({ kind }: { kind: "eye" | "chain" | "lock" }) {
  if (kind === "eye") return <span>[eye]</span>;
  if (kind === "chain") return <span>[chain]</span>;
  return <span>[lock]</span>;
}

function getPhaseHint(phase: number): string {
  switch (phase) {
    case Phase.SHUFFLE_P1:
    case Phase.SHUFFLE_P2:
      return "Shuffling an encrypted deck. Each seat's contribution is committed on-chain; neither side can rig the order.";
    case Phase.DEALING:
      return "Dealing hole cards. Each player submits a partial decryption share for the opponent; only the owner can recover their own cards.";
    case Phase.FLOP_REVEAL:
    case Phase.TURN_REVEAL:
    case Phase.RIVER_REVEAL:
      return "Revealing community cards. Both players must submit matching decryption data or the chain rejects the round.";
    case Phase.SHOWDOWN:
      return "Revealing hole cards. A proof ties each card back to the original encrypted commitment.";
    default:
      return "Submitting zero-knowledge data to the chain.";
  }
}
