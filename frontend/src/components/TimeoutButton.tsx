import { useEffect, useRef, useState } from "react";
import { useWriteContract } from "wagmi";
import { POKER_TABLE_ABI, POKER_TABLE_ADDRESS } from "../utils/contracts";
import { Phase } from "../utils/phase";

interface Props {
  tableId: bigint | undefined;
  phase: number;
  // Local-clock estimate of when the current action window started. The
  // contract resets its deadline on every action, so the caller resets this
  // on phase change AND turn change. If absent we fall back to "always
  // clickable" and rely on the contract to reject.
  phaseStartMs?: number;
}

const TIMEOUT_MS = 120_000;
// Block timestamps on Sepolia update only once per ~12s block, so the on-chain
// clock lags wall-clock by up to one block. Add a buffer so we don't attempt
// claim tx's that will revert with "not timed out" because block.timestamp
// hasn't caught up yet.
const CLOCK_SKEW_BUFFER_MS = 8_000;
const RETRY_DELAY_MS = 6_000;
const MAX_RETRIES = 3;

// Escape hatch. The contract's actionTimeout is 120s; if a player or the bot
// stalls past the deadline, anyone can call claimTimeout to settle. Disabled
// until wall clock says 120s + skew buffer has passed. If the tx reverts
// with "not timed out" (block.timestamp still behind), we auto-retry every
// few seconds until it lands or we hit the retry cap.
export function TimeoutButton({ tableId, phase, phaseStartMs }: Props) {
  const { writeContractAsync, isPending } = useWriteContract();
  const [err, setErr] = useState<string | null>(null);
  const [retrying, setRetrying] = useState(false);
  const retryCount = useRef(0);
  const retryTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);

  // If the caller resets phaseStartMs (action landed), kill any in-flight
  // retry loop; the window we were trying to claim on no longer exists.
  useEffect(() => {
    if (retryTimer.current) {
      clearTimeout(retryTimer.current);
      retryTimer.current = null;
    }
    retryCount.current = 0;
    setRetrying(false);
    setErr(null);
  }, [phaseStartMs]);

  const inactive =
    phase === undefined ||
    phase === Phase.WAITING ||
    phase === Phase.SETTLED ||
    phase === Phase.CANCELLED;
  if (inactive) return null;

  const elapsed = phaseStartMs !== undefined ? now - phaseStartMs : TIMEOUT_MS;
  const threshold = TIMEOUT_MS + CLOCK_SKEW_BUFFER_MS;
  const ready = elapsed >= threshold;
  const remaining = Math.max(0, Math.ceil((threshold - elapsed) / 1000));

  const attempt = async (): Promise<void> => {
    if (tableId === undefined) return;
    try {
      await writeContractAsync({
        address: POKER_TABLE_ADDRESS,
        abi: POKER_TABLE_ABI,
        functionName: "claimTimeout",
        args: [tableId],
      });
      setErr(null);
      setRetrying(false);
      retryCount.current = 0;
    } catch (e: any) {
      const msg = (
        e?.shortMessage ||
        e?.details ||
        e?.message?.split("\n")[0] ||
        "Revert"
      ) as string;
      // On-chain block.timestamp hasn't caught up. Schedule a retry.
      const notTimedOut = msg.toLowerCase().includes("not timed out");
      if (notTimedOut && retryCount.current < MAX_RETRIES) {
        retryCount.current += 1;
        setRetrying(true);
        setErr(
          `block clock behind by a few seconds; retry ${retryCount.current}/${MAX_RETRIES} in ${Math.round(RETRY_DELAY_MS / 1000)}s`
        );
        retryTimer.current = setTimeout(() => {
          retryTimer.current = null;
          void attempt();
        }, RETRY_DELAY_MS);
      } else {
        setRetrying(false);
        setErr(msg);
        setTimeout(() => setErr(null), 8000);
      }
    }
  };

  const click = async () => {
    setErr(null);
    retryCount.current = 0;
    await attempt();
  };

  return (
    <div className="flex items-center gap-2">
      <button
        onClick={click}
        disabled={isPending || retrying || !ready}
        title={
          ready
            ? "Settle the table - opponent missed the 120s deadline."
            : `Available in ${remaining}s once the on-chain deadline passes.`
        }
        className={
          "px-3 py-1 border uppercase text-[10px] tracking-widest disabled:opacity-30 " +
          (ready
            ? "border-yellow-500 text-yellow-300 hover:bg-yellow-900/20"
            : "border-edge text-ink/60")
        }
      >
        {retrying
          ? "retrying..."
          : ready
            ? "Claim Timeout"
            : `Claim in ${remaining}s`}
      </button>
      {err && <span className="text-[10px] text-red-400">{err}</span>}
    </div>
  );
}
