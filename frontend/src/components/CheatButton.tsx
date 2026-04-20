import { useState } from "react";
import { useWriteContract, usePublicClient } from "wagmi";
import type { Hex } from "viem";
import { POKER_TABLE_ABI, POKER_TABLE_ADDRESS } from "../utils/contracts";
import { Phase } from "../utils/phase";
import { TxChip } from "./TxChip";

interface Props {
  tableId: bigint | undefined;
  phase: number;
}

// Submits a deliberately-invalid revealHand (bogus hole cards that don't match
// the on-chain commitments) to demonstrate that the chain rejects cheating.
// The UI surfaces the revert reason and the failed tx hash on Etherscan.
export function CheatButton({ tableId, phase }: Props) {
  const showdownReady = phase === Phase.SHOWDOWN;
  const { writeContractAsync, isPending } = useWriteContract();
  const publicClient = usePublicClient();
  const [result, setResult] = useState<
    | { kind: "idle" }
    | { kind: "trying" }
    | { kind: "caught"; reason: string; hash?: Hex }
    | { kind: "snuck"; hash: Hex }
  >({ kind: "idle" });

  const tryCheat = async () => {
    if (tableId === undefined) return;
    setResult({ kind: "trying" });
    // Bogus hole cards: intentionally use community-card indices so the
    // contract's "hole card duplicates community" check rejects them even
    // if they somehow passed everything else.
    const BOGUS: [number, number] = [51, 50];
    try {
      const hash = (await writeContractAsync({
        address: POKER_TABLE_ADDRESS,
        abi: POKER_TABLE_ABI,
        functionName: "revealHand",
        args: [tableId, "0x", BOGUS],
      })) as Hex;
      if (publicClient) {
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        if (receipt.status === "success") {
          setResult({ kind: "snuck", hash });
        } else {
          setResult({ kind: "caught", reason: "Transaction reverted on-chain", hash });
        }
      } else {
        setResult({ kind: "snuck", hash });
      }
    } catch (err: any) {
      const reason =
        err?.shortMessage ||
        err?.details ||
        err?.message?.split("\n")[0] ||
        "Unknown revert";
      setResult({ kind: "caught", reason });
    }
  };

  return (
    <div className="border border-red-900/50 bg-red-950/10 rounded p-3 space-y-2">
      <div className="flex items-center justify-between">
        <span className="text-[11px] uppercase tracking-widest text-red-400/80">
          Try to cheat
        </span>
        <button
          onClick={tryCheat}
          disabled={isPending || tableId === undefined || !showdownReady}
          title={!showdownReady ? "Wait until showdown to attempt" : undefined}
          className="px-3 py-1 border border-red-500 text-red-300 uppercase text-xs tracking-widest hover:bg-red-900/30 disabled:opacity-30"
        >
          {result.kind === "trying" ? "attempting..." : "Claim bogus hand"}
        </button>
      </div>
      <p className="text-[11px] text-ink/50 leading-snug">
        Submits a fake <code className="text-ink/70">revealHand</code> claiming
        cards that don't match the on-chain commitments. The contract verifies
        and rejects. {!showdownReady && <span className="text-ink/40">(available at showdown)</span>}
      </p>
      {result.kind === "caught" && (
        <div className="text-[11px] text-green-300 flex items-center gap-2 flex-wrap">
          <span>The chain caught you cheating.</span>
          <span className="text-ink/60">Revert:</span>
          <span className="font-mono text-red-300">"{result.reason}"</span>
          {result.hash && <TxChip hash={result.hash} status="reverted" short />}
        </div>
      )}
      {result.kind === "snuck" && (
        <div className="text-[11px] text-yellow-300">
          Unexpected: tx succeeded. <TxChip hash={result.hash} short />
        </div>
      )}
    </div>
  );
}
