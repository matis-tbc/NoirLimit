import { useState } from "react";
import { useWriteContract } from "wagmi";
import { POKER_TABLE_ABI, POKER_TABLE_ADDRESS } from "../utils/contracts";
import { Phase } from "../utils/phase";

interface Props {
  tableId: bigint | undefined;
  phase: number;
}

// Production-visible escape hatch. The contract's actionTimeout is 120s; if
// any player or the bot stalls a phase past the deadline, anyone can call
// claimTimeout to settle the table. This unwedges a stuck demo without a
// page refresh or wallet swap.
export function TimeoutButton({ tableId, phase }: Props) {
  const { writeContractAsync, isPending } = useWriteContract();
  const [err, setErr] = useState<string | null>(null);

  const inactive =
    phase === Phase.WAITING ||
    phase === Phase.SETTLED ||
    phase === Phase.CANCELLED;
  if (inactive) return null;

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
    }
  };

  return (
    <div className="flex items-center gap-2">
      <button
        onClick={click}
        disabled={isPending}
        title="Only succeeds after the 120s on-chain deadline. Use to unwedge a stuck phase."
        className="px-3 py-1 border border-edge text-ink/60 hover:border-yellow-600 hover:text-yellow-300 uppercase text-[10px] tracking-widest disabled:opacity-30"
      >
        Claim Timeout
      </button>
      {err && <span className="text-[10px] text-red-400">{err}</span>}
    </div>
  );
}
