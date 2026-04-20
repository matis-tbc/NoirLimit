import { useEffect, useRef } from "react";
import { useWriteContract, usePublicClient } from "wagmi";
import type { Hex } from "viem";
import { POKER_TABLE_ABI, POKER_TABLE_ADDRESS } from "../utils/contracts";
import { Phase, isAutoPhase, isTerminal } from "../utils/phase";
import { zkLog } from "../utils/zkLog";
import { gasFor } from "../utils/gas";
import {
  publicKeyFor,
  shuffleP1Payload,
  shuffleP2Payload,
  decryptDealing,
  decryptReveal,
  FLOP_INDICES,
  TURN_INDICES,
  RIVER_INDICES,
  REVEAL_VALUES,
} from "../utils/demoPayloads";
import { dealHoleCards } from "../utils/deal";
import type { PokerTableState } from "./usePokerTable";

interface Args {
  tableId: bigint | undefined;
  table: PokerTableState | undefined;
  seatIndex: 0 | 1 | -1;
  enabled: boolean;
  publicKeyRegistered: boolean;
  setPublicKeyRegistered: (b: boolean) => void;
}

// Drives the connected human player through every non-betting phase by
// auto-submitting the dummy ZK payloads. Idempotent: tracks which (phase, seat)
// pair was last submitted to avoid resubmitting on a re-render.
export function useAutoSubmit({
  tableId,
  table,
  seatIndex,
  enabled,
  publicKeyRegistered,
  setPublicKeyRegistered,
}: Args) {
  const { writeContractAsync } = useWriteContract();
  const publicClient = usePublicClient();
  const lastSentRef = useRef<string | null>(null);
  const inflightRef = useRef(false);

  async function write(functionName: string, args: any[], ctx: { tableId: bigint; phase: number; seat: number }): Promise<Hex> {
    const hash = (await writeContractAsync({
      address: POKER_TABLE_ADDRESS,
      abi: POKER_TABLE_ABI,
      functionName: functionName as any,
      args: args as any,
      gas: gasFor(functionName),
    } as any)) as Hex;
    zkLog.push({
      tableId: ctx.tableId,
      phase: ctx.phase,
      seat: ctx.seat,
      functionName,
      txHash: hash,
      status: "pending",
    });
    if (publicClient) {
      // Race the receipt fetch against a 60s timeout so a stalled RPC does
      // not leave the chip pulsing forever. If timeout wins, mark "unknown"
      // so the user knows to check Etherscan manually.
      const timeout = new Promise<"timeout">((resolve) =>
        setTimeout(() => resolve("timeout"), 60_000)
      );
      Promise.race([
        publicClient.waitForTransactionReceipt({ hash }),
        timeout,
      ])
        .then((result) => {
          if (result === "timeout") {
            zkLog.update(hash, {
              status: "unknown",
              revertReason: "receipt fetch timed out (60s) - check Etherscan",
            });
          } else {
            zkLog.update(hash, {
              status: result.status === "success" ? "confirmed" : "reverted",
              gasUsed: result.gasUsed,
              blockNumber: result.blockNumber,
            });
          }
        })
        .catch((err) =>
          zkLog.update(hash, { status: "reverted", revertReason: err?.shortMessage || err?.message })
        );
    }
    return hash;
  }

  useEffect(() => {
    if (!enabled || !table || tableId === undefined || seatIndex === -1) return;

    const key = `${tableId.toString()}-${table.phase}-${seatIndex}-${publicKeyRegistered}`;
    // Set sentinels BEFORE any await so a StrictMode double-mount cannot race past.
    if (inflightRef.current) return;
    if (lastSentRef.current === key) return;
    inflightRef.current = true;
    lastSentRef.current = key;

    const phase = table.phase as Phase;
    const wantsRegister =
      (phase === Phase.SHUFFLE_P1 || phase === Phase.SHUFFLE_P2) &&
      !publicKeyRegistered;
    const wantsAuto = isAutoPhase(phase);
    const wantsShowdown = phase === Phase.SHOWDOWN;

    if (!wantsRegister && !wantsAuto && !wantsShowdown) {
      inflightRef.current = false;
      lastSentRef.current = null;
      return;
    }

    const ctx = { tableId, phase: table.phase, seat: seatIndex };

    const run = async () => {
      try {
        if (wantsRegister) {
          await write("registerPublicKey", [tableId, publicKeyFor(seatIndex + 1)], ctx);
          setPublicKeyRegistered(true);
        } else if (phase === Phase.SHUFFLE_P1 && seatIndex === 0) {
          const p = shuffleP1Payload();
          await write("submitShuffle", [
            tableId,
            p.proof,
            p.newDeckCommitment,
            p.cardCommitments,
            p.cardRandomizers,
            p.cardMaskedPayloads,
          ], ctx);
        } else if (phase === Phase.SHUFFLE_P2 && seatIndex === 1) {
          const p = shuffleP2Payload();
          await write("submitShuffle", [
            tableId,
            p.proof,
            p.newDeckCommitment,
            p.cardCommitments,
            p.cardRandomizers,
            p.cardMaskedPayloads,
          ], ctx);
        } else if (phase === Phase.DEALING) {
          const indices = seatIndex === 0 ? [2, 3] : [0, 1];
          const p = decryptDealing(seatIndex + 1, indices);
          await write("submitDecrypt", [tableId, p.cardIndices, p.partialDecryptionValues, p.proofs, p.cardValues], ctx);
        } else if (phase === Phase.FLOP_REVEAL) {
          const p = decryptReveal(seatIndex + 1, FLOP_INDICES, REVEAL_VALUES.flop);
          await write("submitDecrypt", [tableId, p.cardIndices, p.partialDecryptionValues, p.proofs, p.cardValues], ctx);
        } else if (phase === Phase.TURN_REVEAL) {
          const p = decryptReveal(seatIndex + 1, TURN_INDICES, REVEAL_VALUES.turn);
          await write("submitDecrypt", [tableId, p.cardIndices, p.partialDecryptionValues, p.proofs, p.cardValues], ctx);
        } else if (phase === Phase.RIVER_REVEAL) {
          const p = decryptReveal(seatIndex + 1, RIVER_INDICES, REVEAL_VALUES.river);
          await write("submitDecrypt", [tableId, p.cardIndices, p.partialDecryptionValues, p.proofs, p.cardValues], ctx);
        } else if (phase === Phase.SHOWDOWN) {
          const dealt = dealHoleCards(tableId, table.players[0], table.players[1]);
          const cards = seatIndex === 0 ? dealt.p1 : dealt.p2;
          await write("revealHand", [tableId, "0x", cards], ctx);
        }
      } catch (err) {
        console.error("[autoSubmit]", err);
        // If this was a double-register attempt (e.g. after refresh), assume the
        // contract is the source of truth and mark registered so we stop looping.
        if (wantsRegister) setPublicKeyRegistered(true);
        // Otherwise allow retry on next state change (phase likely already advanced).
        lastSentRef.current = null;
      } finally {
        inflightRef.current = false;
      }
    };

    void run();
  }, [
    enabled,
    tableId,
    table?.phase,
    seatIndex,
    publicKeyRegistered,
    writeContractAsync,
    setPublicKeyRegistered,
    table?.players,
  ]);
}
