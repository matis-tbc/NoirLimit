import type { LogEntry } from "../hooks/usePokerTable";
import { formatEther } from "viem";
import { TxChip } from "./TxChip";

interface Props {
  logs: LogEntry[];
}

const ACTION_NAMES = ["FOLD", "CHECK", "CALL", "RAISE"];

function describe(l: LogEntry): string {
  const a = l.args || {};
  switch (l.eventName) {
    case "TableCreated":
      return `Table #${a.tableId} created (buy-in ${formatEther(a.buyIn)} ETH)`;
    case "PlayerJoined":
      return `${short(a.player)} joined`;
    case "ShuffleSubmitted":
      return `${short(a.player)} shuffled`;
    case "DecryptSubmitted":
      return `${short(a.player)} decrypted [${(a.cardIndices || []).join(",")}]`;
    case "CommunityCardsRevealed":
      return `Revealed ${a.newCardCount} community cards`;
    case "ActionTaken":
      return `${short(a.player)} ${ACTION_NAMES[a.action]}${a.amount > 0n ? " " + formatEther(a.amount) + " ETH" : ""}`;
    case "HandRevealed":
      return `${short(a.player)} reveals`;
    case "HandSettled":
      return `Pot ${formatEther(a.pot)} ETH -> ${short(a.winner)}`;
    case "TimeoutClaimed":
      return `Timeout claimed by ${short(a.beneficiary)}`;
    default:
      return l.eventName;
  }
}

const HIGHLIGHT = new Set([
  "HandSettled",
  "TableCreated",
  "PlayerJoined",
  "CommunityCardsRevealed",
]);

function short(a?: string) {
  if (!a) return "?";
  return `${a.slice(0, 6)}...${a.slice(-4)}`;
}

export function EventLog({ logs }: Props) {
  return (
    <div className="border border-edge rounded p-3 h-64 overflow-y-auto text-xs space-y-1">
      <div className="uppercase tracking-widest text-ink/50 mb-2 flex items-center gap-2">
        <span className="w-1.5 h-1.5 rounded-full bg-green-400 animate-pulse" />
        Event log
      </div>
      {logs.length === 0 && <div className="text-ink/30">(no events yet)</div>}
      {logs.slice().reverse().map((l) => (
        <div
          key={`${l.transactionHash}-${l.logIndex}`}
          className="flex items-center gap-2 flex-wrap"
        >
          <span className="text-ink/40">#{l.blockNumber.toString()}</span>
          <span className={HIGHLIGHT.has(l.eventName) ? "text-gold" : "text-ink/80"}>
            {describe(l)}
          </span>
          <TxChip hash={l.transactionHash} short />
        </div>
      ))}
    </div>
  );
}
