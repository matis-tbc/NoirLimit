import { useWriteContract } from "wagmi";
import { POKER_TABLE_ABI, POKER_TABLE_ADDRESS } from "../utils/contracts";
import { ActionCode } from "../utils/phase";

export function useGameActions() {
  const { writeContractAsync, isPending } = useWriteContract();

  return {
    isPending,
    createTable: (bigBlind: bigint, buyIn: bigint) =>
      writeContractAsync({
        address: POKER_TABLE_ADDRESS,
        abi: POKER_TABLE_ABI,
        functionName: "createTable",
        args: [bigBlind],
        value: buyIn,
      }),
    joinTable: (tableId: bigint, buyIn: bigint) =>
      writeContractAsync({
        address: POKER_TABLE_ADDRESS,
        abi: POKER_TABLE_ABI,
        functionName: "joinTable",
        args: [tableId],
        value: buyIn,
      }),
    cancelTable: (tableId: bigint) =>
      writeContractAsync({
        address: POKER_TABLE_ADDRESS,
        abi: POKER_TABLE_ABI,
        functionName: "cancelTable",
        args: [tableId],
      }),
    act: (tableId: bigint, action: ActionCode, raiseAmount: bigint = 0n) =>
      writeContractAsync({
        address: POKER_TABLE_ADDRESS,
        abi: POKER_TABLE_ABI,
        functionName: "act",
        args: [tableId, action, raiseAmount],
      }),
    revealHand: (tableId: bigint, cards: [number, number]) =>
      writeContractAsync({
        address: POKER_TABLE_ADDRESS,
        abi: POKER_TABLE_ABI,
        functionName: "revealHand",
        args: [tableId, "0x", cards],
      }),
  };
}
