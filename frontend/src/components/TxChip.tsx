import type { Hex } from "viem";

interface Props {
  hash?: Hex;
  label?: string;
  status?: "pending" | "confirmed" | "reverted" | "unknown";
  short?: boolean;
}

const COLOR: Record<NonNullable<Props["status"]>, string> = {
  confirmed: "border-green-500/40 text-green-300 hover:border-green-400",
  reverted: "border-red-500/40 text-red-300 hover:border-red-400",
  pending:
    "border-yellow-500/40 text-yellow-300 hover:border-yellow-400 animate-pulse",
  unknown: "border-orange-500/40 text-orange-300 hover:border-orange-400",
};

export function TxChip({ hash, label, status = "confirmed", short = true }: Props) {
  if (!hash || hash.length < 10) return null;
  const display = short ? `${hash.slice(0, 6)}...${hash.slice(-4)}` : hash;
  return (
    <a
      href={`https://sepolia.etherscan.io/tx/${hash}`}
      target="_blank"
      rel="noreferrer"
      title={status === "unknown" ? "Receipt fetch timed out - click to verify" : undefined}
      className={`inline-flex items-center gap-1 px-2 py-0.5 border rounded text-[10px] font-mono tracking-tight ${COLOR[status]}`}
    >
      {label && <span className="opacity-80">{label}</span>}
      <span>{display}</span>
    </a>
  );
}
