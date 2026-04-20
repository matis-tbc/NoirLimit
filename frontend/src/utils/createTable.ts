import {
  createPublicClient,
  decodeEventLog,
  http,
  type Hex,
  type Address,
} from "viem";
import { sepolia } from "viem/chains";
import { POKER_TABLE_ABI, POKER_TABLE_ADDRESS } from "./contracts";
import { SEPOLIA_RPC } from "./wagmi";

// Shared helper: takes a tx hash from a successful createTable call and
// returns the new tableId by decoding the TableCreated event from the
// receipt logs. Used by both the Lobby's create flow and TerminalPanel's
// "Play again" button.
export async function tableIdFromCreateTx(hash: Hex): Promise<bigint | undefined> {
  const client = createPublicClient({ chain: sepolia, transport: http(SEPOLIA_RPC) });
  const receipt = await client.waitForTransactionReceipt({ hash });
  for (const log of receipt.logs) {
    const addr = (log.address as Address).toLowerCase();
    if (addr !== POKER_TABLE_ADDRESS.toLowerCase()) continue;
    try {
      const parsed = decodeEventLog({
        abi: POKER_TABLE_ABI,
        data: log.data,
        topics: log.topics,
      });
      if (parsed.eventName === "TableCreated") {
        return (parsed.args as any).tableId as bigint;
      }
    } catch {
      // not our event; skip
    }
  }
  return undefined;
}

// localStorage keys used to remember last-used buy-in / big-blind so the
// "Play again" button can spawn a same-blinds rematch without prompting.
const BUYIN_KEY = "noirlimit:lastBuyIn";
const BB_KEY = "noirlimit:lastBb";

export function rememberStakes(buyIn: bigint, bb: bigint) {
  try {
    localStorage.setItem(BUYIN_KEY, buyIn.toString());
    localStorage.setItem(BB_KEY, bb.toString());
  } catch {
    // ignore
  }
}

export function recallStakes(): { buyIn: bigint; bb: bigint } | null {
  try {
    const b = localStorage.getItem(BUYIN_KEY);
    const bb = localStorage.getItem(BB_KEY);
    if (!b || !bb) return null;
    return { buyIn: BigInt(b), bb: BigInt(bb) };
  } catch {
    return null;
  }
}
