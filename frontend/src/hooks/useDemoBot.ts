import { useEffect, useRef, useState } from "react";
import { useAccount } from "wagmi";
import type { Address } from "viem";
import { makeBotClients, type BotClients } from "../bot/botWallet";
import { botTick } from "../bot/botDriver";
import { Phase } from "../utils/phase";

// Owns the bot lifecycle for a table. Self-rescheduling tick (no setInterval)
// so we never run two ticks concurrently against the same nonce.
export function useDemoBot(tableId: bigint | undefined, enabled: boolean) {
  const { address } = useAccount();
  const [botAddress, setBotAddress] = useState<Address | undefined>();
  const [acting, setActing] = useState(false);
  const clientsRef = useRef<BotClients | null>(null);
  const prevHostRef = useRef<Address | undefined>(undefined);
  const publicKeyRegistered = useRef(false);
  const lastSubmitted = useRef<string | null>(null);

  useEffect(() => {
    if (!enabled || !address) {
      clientsRef.current = null;
      setBotAddress(undefined);
      return;
    }
    const c = makeBotClients(address);
    clientsRef.current = c;
    // Only reset dedup refs when the host wallet actually changes; avoids a
    // toggle-off-on cycle re-registering the public key on the same table.
    if (prevHostRef.current !== address) {
      publicKeyRegistered.current = false;
      lastSubmitted.current = null;
      prevHostRef.current = address;
    }
    setBotAddress(c.account.address);
  }, [enabled, address]);

  useEffect(() => {
    if (!enabled || tableId === undefined) return;

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
      } catch (err) {
        console.error("[bot] tick failed", err);
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

  return { botAddress, acting };
}
