import { useBalance, useWriteContract } from "wagmi";
import { formatEther, type Address } from "viem";
import { POKER_TABLE_ABI, POKER_TABLE_ADDRESS } from "../utils/contracts";
import { PHASE_LABELS } from "../utils/phase";
import { useZkLog } from "../hooks/useZkLog";
import type { PokerTableState } from "../hooks/usePokerTable";

interface Props {
  tableId: bigint | undefined;
  table: PokerTableState | undefined;
  seatIndex: 0 | 1 | -1;
  hostAddress?: Address;
  botAddress?: Address;
}

// DEV-only. Surfaces the state needed to debug a smoke test without leaving
// the UI: phase, turn, stacks, pot, recent txs, revert reasons, plus a
// claimTimeout button to unwedge a stuck phase.
export function DebugPanel({ tableId, table, seatIndex, hostAddress, botAddress }: Props) {
  if (!import.meta.env.DEV) return null;

  const entries = useZkLog();
  const recent = entries.slice(-5).reverse();
  const { writeContractAsync, isPending } = useWriteContract();

  const { data: hostBal } = useBalance({
    address: hostAddress,
    query: { enabled: !!hostAddress, refetchInterval: 8000 },
  });
  const { data: botBal } = useBalance({
    address: botAddress,
    query: { enabled: !!botAddress, refetchInterval: 8000 },
  });

  const claimTimeout = async () => {
    if (tableId === undefined) return;
    try {
      await writeContractAsync({
        address: POKER_TABLE_ADDRESS,
        abi: POKER_TABLE_ABI,
        functionName: "claimTimeout",
        args: [tableId],
      });
    } catch (err) {
      console.error("claimTimeout failed", err);
    }
  };

  return (
    <div className="border border-yellow-800/60 bg-yellow-900/10 rounded p-3 text-xs space-y-2 font-mono">
      <div className="flex items-center justify-between">
        <span className="text-yellow-400 uppercase tracking-widest">Debug (DEV only)</span>
        <button
          onClick={claimTimeout}
          disabled={isPending || tableId === undefined}
          className="px-2 py-0.5 border border-red-500 text-red-400 uppercase text-[10px] tracking-widest disabled:opacity-30"
        >
          Claim Timeout
        </button>
      </div>

      <div className="grid grid-cols-2 gap-x-4 gap-y-1">
        <div>tableId: <span className="text-ink">{tableId?.toString() ?? "-"}</span></div>
        <div>
          phase:{" "}
          <span className="text-ink">
            {table ? `${table.phase} (${PHASE_LABELS[table.phase]})` : "-"}
          </span>
        </div>
        <div>turn: <span className="text-ink">{table?.turn ?? "-"}</span></div>
        <div>my seat: <span className="text-ink">{seatIndex}</span></div>
        <div>
          pot: <span className="text-ink">{table ? formatEther(table.pot) : "-"} ETH</span>
        </div>
        <div>
          stacks: <span className="text-ink">
            {table ? `${formatEther(table.stacks[0])} / ${formatEther(table.stacks[1])}` : "-"}
          </span>
        </div>
        <div>host bal: <span className="text-ink">{hostBal ? formatEther(hostBal.value) : "-"}</span></div>
        <div>bot bal: <span className="text-ink">{botBal ? formatEther(botBal.value) : "-"}</span></div>
      </div>

      <div>
        <div className="text-yellow-400/70 uppercase tracking-widest text-[10px] mb-1">
          recent txs ({entries.length})
        </div>
        {recent.length === 0 && <div className="text-ink/30">no txs yet</div>}
        {recent.map((e) => (
          <div key={e.id} className="flex items-center gap-2">
            <span
              className={
                e.status === "confirmed"
                  ? "text-green-400"
                  : e.status === "reverted"
                    ? "text-red-400"
                    : "text-yellow-400"
              }
            >
              {e.status === "confirmed" ? "OK" : e.status === "reverted" ? "XX" : ".."}
            </span>
            <span className="text-ink/70">{e.functionName}</span>
            <span className="text-ink/40">seat={e.seat}</span>
            <a
              className="text-ink/60 underline truncate max-w-[160px]"
              href={`https://sepolia.etherscan.io/tx/${e.txHash}`}
              target="_blank"
              rel="noreferrer"
            >
              {e.txHash.slice(0, 10)}...
            </a>
            {e.revertReason && (
              <span className="text-red-400/80 truncate max-w-[200px]">{e.revertReason}</span>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
