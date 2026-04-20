import type { Hex } from "viem";

interface Props {
  hash: Hex;
  label?: string;
  status?: "pending" | "confirmed" | "reverted";
  short?: boolean;
}

export function TxChip({ hash, label, status = "confirmed", short = true }: Props) {
  const display = short ? `${hash.slice(0, 6)}...${hash.slice(-4)}` : hash;
  const color =
    status === "confirmed"
      ? "border-green-500/40 text-green-300 hover:border-green-400"
      : status === "reverted"
        ? "border-red-500/40 text-red-300 hover:border-red-400"
        : "border-yellow-500/40 text-yellow-300 hover:border-yellow-400 animate-pulse";
  return (
    <a
      href={`https://sepolia.etherscan.io/tx/${hash}`}
      target="_blank"
      rel="noreferrer"
      className={`inline-flex items-center gap-1 px-2 py-0.5 border rounded text-[10px] font-mono tracking-tight ${color}`}
    >
      {label && <span className="opacity-80">{label}</span>}
      <span>{display}</span>
    </a>
  );
}
