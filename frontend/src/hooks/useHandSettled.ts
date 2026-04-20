import { useEffect, useState } from "react";
import { usePublicClient } from "wagmi";
import { type Address, type Hex, parseAbiItem } from "viem";
import { POKER_TABLE_ADDRESS } from "../utils/contracts";

export type SettledReason = "settled" | "timeout";

export interface SettledRecord {
  winner: Address;
  pot: bigint;
  txHash: Hex;
  blockNumber: bigint;
  reason: SettledReason;
}

const HAND_SETTLED = parseAbiItem(
  "event HandSettled(uint256 indexed tableId, address winner, uint256 pot)"
);
const TIMEOUT_CLAIMED = parseAbiItem(
  "event TimeoutClaimed(uint256 indexed tableId, address beneficiary)"
);

// Backfills the most-recent terminal event (HandSettled or TimeoutClaimed)
// for a tableId so the WinnerBanner can fire even when the user lands on
// /table/N AFTER settlement (usePokerEvents only sees events arriving
// after subscription starts).
export function useHandSettled(tableId: bigint | undefined): SettledRecord | null {
  const publicClient = usePublicClient();
  const [record, setRecord] = useState<SettledRecord | null>(null);

  useEffect(() => {
    if (!publicClient || tableId === undefined) {
      setRecord(null);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const head = await publicClient.getBlockNumber();
        const fromBlock = head > 100_000n ? head - 100_000n : 0n;

        // Look for both terminal events in parallel.
        const [settledLogs, timeoutLogs] = await Promise.all([
          publicClient.getLogs({
            address: POKER_TABLE_ADDRESS,
            event: HAND_SETTLED,
            args: { tableId },
            fromBlock,
            toBlock: head,
          }),
          publicClient.getLogs({
            address: POKER_TABLE_ADDRESS,
            event: TIMEOUT_CLAIMED,
            args: { tableId },
            fromBlock,
            toBlock: head,
          }),
        ]);
        if (cancelled) return;

        // Pick whichever fired most recently.
        const candidates: SettledRecord[] = [];
        if (settledLogs.length > 0) {
          const l = settledLogs[settledLogs.length - 1];
          candidates.push({
            winner: l.args.winner as Address,
            pot: l.args.pot as bigint,
            txHash: l.transactionHash as Hex,
            blockNumber: l.blockNumber as bigint,
            reason: "settled",
          });
        }
        if (timeoutLogs.length > 0) {
          const l = timeoutLogs[timeoutLogs.length - 1];
          candidates.push({
            winner: l.args.beneficiary as Address,
            pot: 0n, // pot info not in TimeoutClaimed event
            txHash: l.transactionHash as Hex,
            blockNumber: l.blockNumber as bigint,
            reason: "timeout",
          });
        }
        if (candidates.length === 0) return;
        candidates.sort((a, b) => Number(b.blockNumber - a.blockNumber));
        setRecord(candidates[0]);
      } catch (err) {
        console.warn("[useHandSettled] backfill failed", err);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [publicClient, tableId]);

  return record;
}
