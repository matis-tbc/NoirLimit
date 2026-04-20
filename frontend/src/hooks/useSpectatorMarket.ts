import { useReadContract, useWriteContract } from "wagmi";
import { type Address } from "viem";
import { SPECTATOR_MARKET_ABI, SPECTATOR_MARKET_ADDRESS } from "../utils/contracts";

const ZERO = "0x0000000000000000000000000000000000000000" as Address;
export const spectatorEnabled = SPECTATOR_MARKET_ADDRESS !== ZERO;

export function useSpectatorMarket(tableId: bigint | undefined, viewer?: Address) {
  const { data: market, refetch: refetchMarket } = useReadContract({
    address: SPECTATOR_MARKET_ADDRESS,
    abi: SPECTATOR_MARKET_ABI,
    functionName: "getMarket",
    args: tableId !== undefined ? [tableId] : undefined,
    query: { enabled: spectatorEnabled && tableId !== undefined, refetchInterval: 5000 },
  });

  const { data: wager, refetch: refetchWager } = useReadContract({
    address: SPECTATOR_MARKET_ADDRESS,
    abi: SPECTATOR_MARKET_ABI,
    functionName: "getWager",
    args: tableId !== undefined && viewer ? [tableId, viewer] : undefined,
    query: { enabled: spectatorEnabled && tableId !== undefined && !!viewer, refetchInterval: 5000 },
  });

  const { data: claimQuote } = useReadContract({
    address: SPECTATOR_MARKET_ADDRESS,
    abi: SPECTATOR_MARKET_ABI,
    functionName: "quoteClaim",
    args: tableId !== undefined && viewer ? [tableId, viewer] : undefined,
    query: { enabled: spectatorEnabled && tableId !== undefined && !!viewer, refetchInterval: 5000 },
  });

  const { writeContractAsync, isPending } = useWriteContract();

  return {
    enabled: spectatorEnabled,
    market,
    wager,
    claimQuote,
    isPending,
    refetch: () => {
      void refetchMarket();
      void refetchWager();
    },
    placeWager: (predictedWinner: Address, amount: bigint) =>
      writeContractAsync({
        address: SPECTATOR_MARKET_ADDRESS,
        abi: SPECTATOR_MARKET_ABI,
        functionName: "placeWager",
        args: [tableId!, predictedWinner],
        value: amount,
      }),
    resolveWagers: () =>
      writeContractAsync({
        address: SPECTATOR_MARKET_ADDRESS,
        abi: SPECTATOR_MARKET_ABI,
        functionName: "resolveWagers",
        args: [tableId!],
      }),
    claimWinnings: () =>
      writeContractAsync({
        address: SPECTATOR_MARKET_ADDRESS,
        abi: SPECTATOR_MARKET_ABI,
        functionName: "claimWinnings",
        args: [tableId!],
      }),
  };
}
