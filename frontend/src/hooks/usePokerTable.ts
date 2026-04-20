import { useMemo, useState, useEffect, useRef } from "react";
import { useReadContract, useWatchContractEvent, useAccount } from "wagmi";
import type { Address, Hex } from "viem";
import { POKER_TABLE_ABI, POKER_TABLE_ADDRESS } from "../utils/contracts";
import { dealHoleCards } from "../utils/deal";
import { Phase } from "../utils/phase";
import { FLOP_CARDS, TURN_CARD, RIVER_CARD } from "../utils/demoPayloads";

export interface PokerTableState {
  players: [Address, Address];
  stacks: [bigint, bigint];
  pot: bigint;
  phase: number;
  communityCardCount: number;
  turn: number;
}

export interface LogEntry {
  blockNumber: bigint;
  transactionHash: Hex;
  logIndex: number;
  eventName: string;
  args: any;
}

// Module-level subscribers so usePokerTable + usePokerEvents share ONE RPC
// subscription rather than opening two. onLogs fanout is in-process.
type LogHandler = (logs: any[]) => void;
const subscribers = new Set<LogHandler>();

function usePokerEventSubscriber(handler: LogHandler) {
  const handlerRef = useRef(handler);
  handlerRef.current = handler;

  useEffect(() => {
    const wrapped: LogHandler = (logs) => handlerRef.current(logs);
    subscribers.add(wrapped);
    return () => {
      subscribers.delete(wrapped);
    };
  }, []);
}

// Module-level mount counter so even if multiple hooks call this on the same
// page, only the FIRST one actually registers a wagmi watcher. The others
// no-op via `enabled: false`. Without this, Table.tsx (which mounts both
// usePokerTable and usePokerEvents) doubled the RPC subscription count and
// every event fired the fanout twice.
let activeWatchers = 0;

function useSharedContractEventWatcher() {
  const [isPrimary, setIsPrimary] = useState(false);
  useEffect(() => {
    activeWatchers += 1;
    const primary = activeWatchers === 1;
    setIsPrimary(primary);
    return () => {
      activeWatchers -= 1;
    };
  }, []);

  useWatchContractEvent({
    address: POKER_TABLE_ADDRESS,
    abi: POKER_TABLE_ABI,
    enabled: isPrimary,
    onLogs: (logs) => {
      for (const sub of subscribers) sub(logs);
    },
  });
}

export function usePokerTable(tableId: bigint | undefined) {
  const { address } = useAccount();
  const enabled = tableId !== undefined;

  const { data, refetch } = useReadContract({
    address: POKER_TABLE_ADDRESS,
    abi: POKER_TABLE_ABI,
    functionName: "getTable",
    args: enabled ? [tableId] : undefined,
    query: { enabled, refetchInterval: 4000 },
  });

  useSharedContractEventWatcher();
  usePokerEventSubscriber((logs) => {
    if (tableId === undefined) return;
    const hit = logs.some((l: any) => l.args?.tableId === tableId);
    if (hit) refetch();
  });

  const table: PokerTableState | undefined = useMemo(() => {
    if (!data) return undefined;
    const [players, stacks, pot, phase, ccCount, turn] = data as [
      [Address, Address],
      [bigint, bigint],
      bigint,
      number,
      number,
      number
    ];
    return { players, stacks, pot, phase, communityCardCount: ccCount, turn };
  }, [data]);

  const seatIndex = useMemo<0 | 1 | -1>(() => {
    if (!table || !address) return -1;
    if (address.toLowerCase() === table.players[0].toLowerCase()) return 0;
    if (address.toLowerCase() === table.players[1].toLowerCase()) return 1;
    return -1;
  }, [table, address]);

  const isMyTurn = table !== undefined && seatIndex !== -1 && table.turn === seatIndex;

  const holeCards = useMemo<[number, number] | null>(() => {
    if (!table || tableId === undefined || seatIndex === -1) return null;
    if (table.phase < Phase.PREFLOP) return null;
    const dealt = dealHoleCards(tableId, table.players[0], table.players[1]);
    return seatIndex === 0 ? dealt.p1 : dealt.p2;
  }, [table, tableId, seatIndex]);

  const communityCards = useMemo<number[]>(() => {
    if (!table) return [];
    const out: number[] = [];
    if (table.communityCardCount >= 3) out.push(...FLOP_CARDS);
    if (table.communityCardCount >= 4) out.push(TURN_CARD);
    if (table.communityCardCount >= 5) out.push(RIVER_CARD);
    return out;
  }, [table]);

  return { table, seatIndex, isMyTurn, holeCards, communityCards, refetch };
}

export function usePokerEvents(tableId: bigint | undefined, max = 30) {
  const [logs, setLogs] = useState<LogEntry[]>([]);

  useSharedContractEventWatcher();
  usePokerEventSubscriber((newLogs) => {
    setLogs((prev) => {
      const filtered: LogEntry[] = newLogs
        .filter((l: any) => {
          if (tableId === undefined) return true;
          return l.args?.tableId === tableId;
        })
        .map((l: any) => ({
          blockNumber: l.blockNumber as bigint,
          transactionHash: l.transactionHash as Hex,
          logIndex: l.logIndex as number,
          eventName: l.eventName as string,
          args: l.args,
        }));
      // Dedupe by tx+logIndex to survive reconnect refetches.
      const seen = new Set(prev.map((p) => `${p.transactionHash}-${p.logIndex}`));
      const deduped = filtered.filter((f) => !seen.has(`${f.transactionHash}-${f.logIndex}`));
      return [...prev, ...deduped].slice(-max);
    });
  });

  return logs;
}
