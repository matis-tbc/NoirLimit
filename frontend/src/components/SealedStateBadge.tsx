import { Phase } from "../utils/phase";

interface Props {
  phase: number;
}

// Tiny lock-glyph badge that confirms, to a ZK-lit spectator, that hole
// cards remain encrypted until showdown. We hide it once the phase is past
// showdown since the seal is broken by then.
export function SealedStateBadge({ phase }: Props) {
  const broken =
    phase === Phase.SHOWDOWN ||
    phase === Phase.SETTLED ||
    phase === Phase.CANCELLED;
  return (
    <div
      className={
        "flex items-center gap-2 text-[10px] uppercase tracking-widest border rounded px-2 py-1 " +
        (broken
          ? "border-edge text-ink/40"
          : "border-gold/40 text-gold/80 bg-gold/5")
      }
    >
      <span aria-hidden>{broken ? "[open]" : "[lock]"}</span>
      <span>
        {broken
          ? "Hole cards revealed at showdown"
          : "Hole cards sealed until showdown"}
      </span>
    </div>
  );
}
