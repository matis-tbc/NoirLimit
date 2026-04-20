import { formatEther } from "viem";

interface Props {
  pool0: bigint;
  pool1: bigint;
}

// Polymarket-style probability bar computed from pool ratios.
export function OddsBar({ pool0, pool1 }: Props) {
  const total = pool0 + pool1;
  const pct0 = total === 0n ? 50 : Number((pool0 * 10000n) / total) / 100;
  const pct1 = 100 - pct0;

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between text-[11px] uppercase tracking-widest">
        <span className="text-ink/70">
          P1 <span className="text-gold">{pct0.toFixed(1)}%</span>
        </span>
        <span className="text-ink/50">{formatEther(total)} ETH pool</span>
        <span className="text-ink/70">
          <span className="text-gold">{pct1.toFixed(1)}%</span> P2
        </span>
      </div>
      <div className="flex h-2 overflow-hidden rounded">
        <div
          className="bg-gold transition-all duration-500"
          style={{ width: `${pct0}%` }}
        />
        <div
          className="bg-red-500/70 transition-all duration-500"
          style={{ width: `${pct1}%` }}
        />
      </div>
      <div className="flex items-center justify-between text-[10px] text-ink/50">
        <span>{formatEther(pool0)} ETH on P1</span>
        <span>{formatEther(pool1)} ETH on P2</span>
      </div>
    </div>
  );
}
