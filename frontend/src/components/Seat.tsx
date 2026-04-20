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

export function Seat({ label, address, stack, cards, hidden, active }: Props) {
  return (
    <div
      className={clsx(
        "p-4 rounded border",
        active ? "border-gold" : "border-edge",
        "bg-[#0d0d0d]"
      )}
    >
      <div className="flex items-center justify-between mb-2">
        <span className="text-xs uppercase tracking-widest text-ink/60">{label}</span>
        <span className="text-xs">{shortAddr(address)}</span>
      </div>
      <div className="text-gold text-sm mb-3">{formatEther(stack)} ETH</div>
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
