import type { Hex } from "viem";

// Per-tx record emitted by useAutoSubmit and botDriver. Consumed by the
// debug panel, EventLog tx chips, and the Phase 4 ZK reveal animation.
export interface ZkLogEntry {
  id: string; // `${tableId}-${phase}-${seat}-${functionName}-${timestamp}`
  tableId: bigint;
  phase: number;
  seat: number; // 0 | 1 | -1 for observer
  functionName: string;
  txHash: Hex;
  gasUsed?: bigint;
  blockNumber?: bigint;
  timestamp: number;
  status: "pending" | "confirmed" | "reverted" | "unknown";
  revertReason?: string;
}

type Listener = () => void;

class ZkLogStore {
  private entries: ZkLogEntry[] = [];
  private listeners = new Set<Listener>();
  private readonly max = 100;

  getSnapshot = (): readonly ZkLogEntry[] => this.entries;

  subscribe = (listener: Listener): (() => void) => {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  };

  push(entry: Omit<ZkLogEntry, "id" | "timestamp"> & { timestamp?: number }) {
    // Random suffix is purely for React key uniqueness when the same hash is
    // pushed twice (e.g. retry before original receipt resolves). The update()
    // path matches by txHash and hits the first match - dedup is the caller's
    // job, not the store's.
    const suffix = Math.random().toString(36).slice(2, 8);
    const full: ZkLogEntry = {
      ...entry,
      timestamp: entry.timestamp ?? Date.now(),
      id: `${entry.txHash}-${suffix}`,
    };
    this.entries = [...this.entries, full].slice(-this.max);
    this.emit();
  }

  update(txHash: Hex, patch: Partial<ZkLogEntry>) {
    const idx = this.entries.findIndex((e) => e.txHash === txHash);
    if (idx === -1) return;
    this.entries = this.entries.map((e, i) => (i === idx ? { ...e, ...patch } : e));
    this.emit();
  }

  clear() {
    this.entries = [];
    this.emit();
  }

  private emit() {
    for (const l of this.listeners) l();
  }
}

export const zkLog = new ZkLogStore();
