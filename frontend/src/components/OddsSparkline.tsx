interface Point {
  pct0: number;
  ts: number;
}

interface Props {
  points: Point[];
  width?: number;
  height?: number;
}

// Tiny inline-SVG sparkline of P1 odds over time. No dependencies, no canvas.
// Caller provides at most ~20 points already; we don't bound here. Each point
// is P1's implied win probability as a percent (0-100).
export function OddsSparkline({ points, width = 220, height = 36 }: Props) {
  if (points.length < 2) {
    return (
      <div
        className="flex items-center justify-center text-[10px] text-ink/40 border border-dashed border-edge rounded"
        style={{ width, height }}
      >
        needs 2+ wagers for a trend
      </div>
    );
  }

  const pad = 2;
  const innerW = width - pad * 2;
  const innerH = height - pad * 2;
  const xs = points.map((_, i) =>
    pad + (i / (points.length - 1)) * innerW
  );
  const ys = points.map(
    (p) => pad + (1 - Math.max(0, Math.min(100, p.pct0)) / 100) * innerH
  );
  const d = xs.map((x, i) => `${i === 0 ? "M" : "L"} ${x.toFixed(1)} ${ys[i].toFixed(1)}`).join(" ");

  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      className="block"
    >
      <line
        x1={pad}
        y1={pad + innerH / 2}
        x2={width - pad}
        y2={pad + innerH / 2}
        stroke="currentColor"
        strokeWidth="0.5"
        className="text-ink/20"
        strokeDasharray="2 2"
      />
      <path
        d={d}
        fill="none"
        stroke="currentColor"
        strokeWidth="1.5"
        className="text-gold"
      />
      {xs.map((x, i) => (
        <circle
          key={i}
          cx={x}
          cy={ys[i]}
          r={i === xs.length - 1 ? 2 : 1.2}
          className={i === xs.length - 1 ? "fill-gold" : "fill-ink/60"}
        />
      ))}
    </svg>
  );
}
