import { useEffect, useState } from "react";
import { useWriteContract } from "wagmi";
import { POKER_TABLE_ABI, POKER_TABLE_ADDRESS } from "../utils/contracts";
import { Phase } from "../utils/phase";

interface Props {
  tableId: bigint | undefined;
  phase: number;
  // Local-clock estimate of when the current phase started. Used to compute
  // when the on-chain 120s deadline elapses. If absent, we fall back to a
  // permissive "always clickable" mode and let the contract reject.
  phaseStartMs?: number;
}

const TIMEOUT_MS = 120_000;

// Production-visible escape hatch. The contract's actionTimeout is 120s; if
// any player or the bot stalls past the deadline, anyone can call
// claimTimeout to settle the table. Disabled (with countdown) until the
// 120s window has elapsed so users don't burn gas on "not timed out" reverts.
export function TimeoutButton({ tableId, phase, phaseStartMs }: Props) {
  const { writeContractAsync, isPending } = useWriteContract();
  const [err, setErr] = useState<string | null>(null);
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  const inactive =
    phase === undefined ||
    phase === Phase.WAITING ||
    phase === Phase.SETTLED ||
    phase === Phase.CANCELLED;
  if (inactive) return null;

  const elapsed = phaseStartMs !== undefined ? now - phaseStartMs : TIMEOUT_MS;
  const ready = elapsed >= TIMEOUT_MS;
  const remaining = Math.max(0, Math.ceil((TIMEOUT_MS - elapsed) / 1000));

  const click = async () => {
    if (tableId === undefined) return;
    setErr(null);
    try {
      await writeContractAsync({
        address: POKER_TABLE_ADDRESS,
        abi: POKER_TABLE_ABI,
        functionName: "claimTimeout",
        args: [tableId],
      });
    } catch (e: any) {
      setErr(e?.shortMessage || e?.message?.split("\n")[0] || "Revert");
      setTimeout(() => setErr(null), 6000);
    }
  };

  return (
    <div className="flex items-center gap-2">
      <button
        onClick={click}
        disabled={isPending || !ready}
        title={
          ready
            ? "Settle the table - opponent missed the 120s deadline."
            : `Available in ${remaining}s once the on-chain deadline passes.`
        }
        className={
          "px-3 py-1 border uppercase text-[10px] tracking-widest disabled:opacity-30 " +
          (ready
            ? "border-yellow-500 text-yellow-300 hover:bg-yellow-900/20"
            : "border-edge text-ink/60")
        }
      >
        {ready ? "Claim Timeout" : `Claim in ${remaining}s`}
      </button>
      {err && <span className="text-[10px] text-red-400">{err}</span>}
    </div>
  );
}
