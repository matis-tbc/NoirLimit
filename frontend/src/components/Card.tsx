import { useEffect, useRef, useState } from "react";
import { cardToDisplay } from "../utils/cards";
import clsx from "clsx";

interface Props {
  card?: number; // undefined = face-down
  size?: "sm" | "md" | "lg";
}

const SIZES = {
  sm: "w-10 h-14 text-sm",
  md: "w-14 h-20 text-lg",
  lg: "w-16 h-24 text-2xl",
};

// Plays a brief flip animation when a card transitions from face-down to a
// revealed value. Pure CSS; no deps.
export function Card({ card, size = "md" }: Props) {
  const prev = useRef<number | undefined>(card);
  const [flipping, setFlipping] = useState(false);

  useEffect(() => {
    if (card !== undefined && prev.current !== card) {
      setFlipping(true);
      const t = setTimeout(() => setFlipping(false), 450);
      prev.current = card;
      return () => clearTimeout(t);
    }
    prev.current = card;
  }, [card]);

  const sizeClass = SIZES[size];

  if (card === undefined) {
    return (
      <div
        className={clsx(
          sizeClass,
          "rounded border border-edge bg-[#111] flex items-center justify-center text-edge"
        )}
      >
        ?
      </div>
    );
  }

  const { rank, glyph, color } = cardToDisplay(card);
  return (
    <div
      className={clsx(
        sizeClass,
        "rounded border border-edge bg-[#1a1a1a] flex flex-col items-center justify-center font-bold transition-transform duration-300",
        color,
        flipping && "[transform:rotateY(360deg)]"
      )}
      style={{ transformStyle: "preserve-3d" }}
    >
      <div>{rank}</div>
      <div>{glyph}</div>
    </div>
  );
}
