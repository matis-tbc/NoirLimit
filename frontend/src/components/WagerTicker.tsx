import { useEffect, useState } from "react";
import { useWatchContractEvent } from "wagmi";
import { formatEther, type Address } from "viem";
import { SPECTATOR_MARKET_ABI, SPECTATOR_MARKET_ADDRESS } from "../utils/contracts";

interface WagerLog {
  spectator: Address;
  predictedWinner: Address;
  amount: bigint;
  blockNumber: bigint;
  txHash: string;
}

interface Props {
  tableId: bigint | undefined;
  players: [Address, Address] | undefined;
}

function shortAddr(a: Address) {
  return `${a.slice(0, 6)}...${a.slice(-4)}`;
}

export function WagerTicker({ tableId, players }: Props) {
  const [wagers, setWagers] = useState<WagerLog[]>([]);

  useWatchContractEvent({
    address: SPECTATOR_MARKET_ADDRESS,
    abi: SPECTATOR_MARKET_ABI,
    eventName: "WagerPlaced",
    onLogs: (logs) => {
      const relevant = logs
        .filter((l: any) => tableId === undefined || l.args?.tableId === tableId)
        .map((l: any) => ({
          spectator: l.args.spectator as Address,
          predictedWinner: l.args.predictedWinner as Address,
          amount: l.args.amount as bigint,
          blockNumber: l.blockNumber as bigint,
          txHash: l.transactionHash as string,
        }));
      if (relevant.length) {
        setWagers((prev) => [...prev, ...relevant].slice(-10));
      }
    },
  });

  const labelFor = (predicted: Address): string => {
    if (!players) return shortAddr(predicted);
    if (predicted.toLowerCase() === players[0].toLowerCase()) return "P1";
    if (predicted.toLowerCase() === players[1].toLowerCase()) return "P2";
    return shortAddr(predicted);
  };

  return (
    <div className="border border-edge rounded p-3 space-y-1">
      <div className="text-[10px] uppercase tracking-widest text-ink/50 flex items-center gap-2">
        <span className="w-1.5 h-1.5 rounded-full bg-green-400 animate-pulse" />
        Recent wagers
      </div>
      {wagers.length === 0 ? (
        <div className="text-[11px] text-ink/30">no wagers yet - be the first</div>
      ) : (
        <div className="text-[11px] space-y-0.5">
          {wagers
            .slice()
            .reverse()
            .map((w) => (
              <div key={w.txHash} className="flex items-center gap-2 text-ink/70">
                <span className="text-ink/40">#{w.blockNumber.toString()}</span>
                <span className="font-mono">{shortAddr(w.spectator)}</span>
                <span className="text-ink/50">on</span>
                <span className="text-gold">{labelFor(w.predictedWinner)}</span>
                <span>{formatEther(w.amount)} ETH</span>
              </div>
            ))}
        </div>
      )}
    </div>
  );
}
