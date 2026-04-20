import { useState } from "react";
import { useWriteContract } from "wagmi";
import { POKER_TABLE_ABI, POKER_TABLE_ADDRESS } from "../utils/contracts";
import { ActionCode } from "../utils/phase";
import { gasFor } from "../utils/gas";

function parseRevert(err: any): string {
  return (
    err?.shortMessage ||
    err?.details ||
    err?.message?.split("\n")[0] ||
    String(err)
  );
}

export function useGameActions() {
  const { writeContractAsync, isPending } = useWriteContract();
  const [lastError, setLastError] = useState<string | null>(null);

  // Wraps writeContractAsync with explicit gas (so the user side never OOGs
  // the way the bot did) and captures the most recent revert reason for the
  // ActionBar / Lobby to surface inline instead of leaving it in MetaMask.
  async function call(functionName: string, args: any[], value?: bigint) {
    setLastError(null);
    try {
      return await writeContractAsync({
        address: POKER_TABLE_ADDRESS,
        abi: POKER_TABLE_ABI,
        functionName: functionName as any,
        args: args as any,
        value,
        gas: gasFor(functionName),
      } as any);
    } catch (err) {
      setLastError(parseRevert(err));
      throw err;
    }
  }

  return {
    isPending,
    lastError,
    createTable: (bigBlind: bigint, buyIn: bigint) =>
      call("createTable", [bigBlind], buyIn),
    joinTable: (tableId: bigint, buyIn: bigint) =>
      call("joinTable", [tableId], buyIn),
    cancelTable: (tableId: bigint) => call("cancelTable", [tableId]),
    act: (tableId: bigint, action: ActionCode, raiseAmount: bigint = 0n) =>
      call("act", [tableId, action, raiseAmount]),
    revealHand: (tableId: bigint, cards: [number, number]) =>
      call("revealHand", [tableId, "0x", cards]),
  };
}
