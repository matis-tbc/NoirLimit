import { useEffect, useRef, useState } from "react";
import { useAccount } from "wagmi";
import type { Address } from "viem";
import { makeBotClients, type BotClients } from "../bot/botWallet";
import { botTick } from "../bot/botDriver";
import { Phase, isTerminal } from "../utils/phase";

const MAX_RETRIES = 3;

// Owns the bot lifecycle for a table. Self-rescheduling tick (no setInterval)
// so we never run two ticks concurrently against the same nonce.
//
// Stops automatically when the caller signals a terminal phase via the
// `phase` arg. Tracks per-step retry counts; if the same step fails
// MAX_RETRIES times in a row, the bot stops and surfaces a wedge error so
// the user can recover via Claim Timeout.
export function useDemoBot(
  tableId: bigint | undefined,
  enabled: boolean,
  phase: number | undefined
) {
  const { address } = useAccount();
  const [botAddress, setBotAddress] = useState<Address | undefined>();
  const [acting, setActing] = useState(false);
  const [wedged, setWedged] = useState<string | null>(null);
  const clientsRef = useRef<BotClients | null>(null);
  const prevHostRef = useRef<Address | undefined>(undefined);
  const publicKeyRegistered = useRef(false);
  const lastSubmitted = useRef<string | null>(null);
  const retries = useRef<Map<string, number>>(new Map());

  // Mirror the latest phase into a ref so the running loop closure always
  // sees the current value without re-mounting on every refetch.
  const phaseRef = useRef<number | undefined>(phase);
  phaseRef.current = phase;

  useEffect(() => {
    if (!enabled || !address) {
      clientsRef.current = null;
      setBotAddress(undefined);
      return;
    }
    const c = makeBotClients(address);
    clientsRef.current = c;
    if (prevHostRef.current !== address) {
      publicKeyRegistered.current = false;
      lastSubmitted.current = null;
      retries.current.clear();
      prevHostRef.current = address;
    }
    setBotAddress(c.account.address);
  }, [enabled, address]);

  useEffect(() => {
    if (!enabled || tableId === undefined) return;
    setWedged(null);

    let stopped = false;
    let timer: ReturnType<typeof setTimeout> | null = null;

    const schedule = (delay: number) => {
      if (stopped) return;
      timer = setTimeout(loop, delay);
    };

    const loop = async () => {
      if (stopped || !clientsRef.current) {
        schedule(2000);
        return;
      }
      // Bail before sending if the table reached a terminal state.
      if (phaseRef.current !== undefined && isTerminal(phaseRef.current)) {
        stopped = true;
        if (timer) clearTimeout(timer);
        setActing(false);
        return;
      }
      try {
        if (!stopped) setActing(true);
        const res = await botTick({
          bot: clientsRef.current,
          tableId,
          hostAddress: address!,
          publicKeyRegistered,
          lastSubmitted,
        });
        if (res.phase === Phase.SETTLED || res.phase === Phase.CANCELLED) {
          stopped = true;
          return;
        }
        // Successful tick: clear retry counter for the key the bot used.
        if (lastSubmitted.current) retries.current.delete(lastSubmitted.current);
      } catch (err) {
        console.error("[bot] tick failed", err);
        const key = lastSubmitted.current ?? "unknown";
        const count = (retries.current.get(key) ?? 0) + 1;
        retries.current.set(key, count);
        if (count >= MAX_RETRIES) {
          setWedged(
            `Bot wedged after ${MAX_RETRIES} retries on ${key}. Use Claim Timeout to recover.`
          );
          stopped = true;
          setActing(false);
          return;
        }
        // Clear dedup so the next tick re-attempts this step.
        lastSubmitted.current = null;
      } finally {
        if (!stopped) setActing(false);
        schedule(4000);
      }
    };

    void loop();
    return () => {
      stopped = true;
      if (timer) clearTimeout(timer);
    };
  }, [enabled, tableId, address]);

  return { botAddress, acting, wedged };
}
