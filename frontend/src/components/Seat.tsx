import { useEffect, useRef, useState } from "react";
import type { Address } from "viem";
import { formatEther } from "viem";
import { Card } from "./Card";
import clsx from "clsx";

interface Props {
  label: string;
  address: Address;
  stack: bigint;
  cards?: [number, number] | null;
  hidden?: boolean;
  active?: boolean;
}

function shortAddr(a: Address) {
  return `${a.slice(0, 6)}\u2026${a.slice(-4)}`;
}

// Track the last stack we rendered so we can show "-0.0004" briefly when
// chips move to the pot. Visual aid only; the canonical state is the number
// itself. First render seeds the ref without flashing.
function useStackDelta(stack: bigint) {
  const prev = useRef<bigint | undefined>(undefined);
  const [delta, setDelta] = useState<bigint>(0n);
  useEffect(() => {
    if (prev.current === undefined) {
      prev.current = stack;
      return;
    }
    const d = stack - prev.current;
    prev.current = stack;
    if (d === 0n) return;
    setDelta(d);
    const id = setTimeout(() => setDelta(0n), 3000);
    return () => clearTimeout(id);
  }, [stack]);
  return delta;
}

export function Seat({ label, address, stack, cards, hidden, active }: Props) {
  const delta = useStackDelta(stack);
  return (
    <div
      className={clsx(
        "p-4 rounded border transition-colors",
        active ? "border-gold" : "border-edge",
        "bg-[#0d0d0d]"
      )}
    >
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs uppercase tracking-widest text-ink/60">{label}</span>
        <span className="text-xs">{shortAddr(address)}</span>
      </div>
      <div className="flex items-baseline gap-2 mb-3">
        <span className="text-gold text-sm font-mono tabular-nums">
          {formatEther(stack)} ETH
        </span>
        {delta !== 0n && (
          <span
            className={clsx(
              "text-[10px] font-mono tabular-nums",
              delta < 0n ? "text-red-400" : "text-green-400"
            )}
          >
            {delta < 0n ? "-" : "+"}
            {formatEther(delta < 0n ? -delta : delta)}{" "}
            {delta < 0n ? "-> pot" : "<- pot"}
          </span>
        )}
      </div>
      <div className="flex gap-2">
        {hidden || !cards ? (
          <>
            <Card />
            <Card />
          </>
        ) : (
          <>
            <Card card={cards[0]} />
            <Card card={cards[1]} />
          </>
        )}
      </div>
    </div>
  );
}
