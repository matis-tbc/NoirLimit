import { isAddressEqual, type Address, type Hex } from "viem";
import { POKER_TABLE_ABI, POKER_TABLE_ADDRESS } from "../utils/contracts";
import { Phase, ActionCode } from "../utils/phase";
import { zkLog } from "../utils/zkLog";
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
import type { BotClients } from "./botWallet";

interface TickArgs {
  bot: BotClients;
  tableId: bigint;
  hostAddress: Address;
  publicKeyRegistered: { current: boolean };
  lastSubmitted: { current: string | null };
}

const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000" as Address;

// Read current table state.
async function readTable(bot: BotClients, tableId: bigint) {
  const data = (await bot.publicClient.readContract({
    address: POKER_TABLE_ADDRESS,
    abi: POKER_TABLE_ABI,
    functionName: "getTable",
    args: [tableId],
  })) as [
    [Address, Address],
    [bigint, bigint],
    bigint,
    number,
    number,
    number
  ];
  return {
    players: data[0],
    stacks: data[1],
    pot: data[2],
    phase: data[3] as Phase,
    communityCardCount: data[4],
    turn: data[5],
  };
}

async function send(
  bot: BotClients,
  fn: string,
  args: any[],
  ctx: { tableId: bigint; phase: number; seat: number },
  value?: bigint
): Promise<Hex> {
  const hash = (await bot.wallet.writeContract({
    address: POKER_TABLE_ADDRESS,
    abi: POKER_TABLE_ABI as any,
    functionName: fn,
    args,
    value,
  } as any)) as Hex;
  zkLog.push({
    tableId: ctx.tableId,
    phase: ctx.phase,
    seat: ctx.seat,
    functionName: fn,
    txHash: hash,
    status: "pending",
  });
  try {
    const receipt = await bot.publicClient.waitForTransactionReceipt({ hash });
    zkLog.update(hash, {
      status: receipt.status === "success" ? "confirmed" : "reverted",
      gasUsed: receipt.gasUsed,
      blockNumber: receipt.blockNumber,
    });
  } catch (err: any) {
    zkLog.update(hash, { status: "reverted", revertReason: err?.shortMessage || err?.message });
    throw err;
  }
  return hash;
}

// Returns true if the bot took an action this tick.
export async function botTick({
  bot,
  tableId,
  publicKeyRegistered,
  lastSubmitted,
}: TickArgs): Promise<{ acted: boolean; phase: Phase }> {
  const t = await readTable(bot, tableId);

  // If the table is open and the bot is the host's intended opponent, join now.
  // The bot must occupy seat 1 by being the only other party calling joinTable.
  const botAddr = bot.account.address as Address;
  if (t.phase === Phase.WAITING && isAddressEqual(t.players[1], ZERO_ADDRESS)) {
    if (isAddressEqual(t.players[0], botAddr)) {
      // Defensive: bot accidentally created a table; nothing to do.
      return { acted: false, phase: t.phase };
    }
    // stacks[0] equals buyIn during WAITING (no blinds posted yet).
    const buyIn = t.stacks[0];
    const key = `JOIN-${tableId.toString()}`;
    if (lastSubmitted.current === key) return { acted: false, phase: t.phase };
    lastSubmitted.current = key;
    await send(bot, "joinTable", [tableId], { tableId, phase: t.phase, seat: -1 }, buyIn);
    return { acted: true, phase: t.phase };
  }

  // Determine bot seat.
  const seat = isAddressEqual(t.players[0], botAddr)
    ? 0
    : isAddressEqual(t.players[1], botAddr)
      ? 1
      : -1;
  if (seat === -1) return { acted: false, phase: t.phase };

  const key = `${tableId.toString()}-${t.phase}-${seat}-${publicKeyRegistered.current}-${t.turn}`;
  if (lastSubmitted.current === key) return { acted: false, phase: t.phase };

  const phase = t.phase;

  const ctx = { tableId, phase, seat };

  // Public key registration (any non-zero bytes32 in demo mode).
  if (
    (phase === Phase.SHUFFLE_P1 || phase === Phase.SHUFFLE_P2) &&
    !publicKeyRegistered.current
  ) {
    lastSubmitted.current = key;
    try {
      await send(bot, "registerPublicKey", [tableId, publicKeyFor(seat + 1)], ctx);
    } catch (err) {
      // Bot was already registered on-chain (e.g. after a refresh). Contract is
      // source of truth; mark registered and let the next tick pick up the phase.
      console.warn("[bot] registerPublicKey reverted, assuming already registered", err);
    }
    publicKeyRegistered.current = true;
    return { acted: true, phase };
  }

  // Shuffle phases.
  if (phase === Phase.SHUFFLE_P1 && seat === 0) {
    lastSubmitted.current = key;
    const p = shuffleP1Payload();
    await send(bot, "submitShuffle", [
      tableId,
      p.proof,
      p.newDeckCommitment,
      p.cardCommitments,
      p.cardRandomizers,
      p.cardMaskedPayloads,
    ], ctx);
    return { acted: true, phase };
  }
  if (phase === Phase.SHUFFLE_P2 && seat === 1) {
    lastSubmitted.current = key;
    const p = shuffleP2Payload();
    await send(bot, "submitShuffle", [
      tableId,
      p.proof,
      p.newDeckCommitment,
      p.cardCommitments,
      p.cardRandomizers,
      p.cardMaskedPayloads,
    ], ctx);
    return { acted: true, phase };
  }

  // Decrypt phases.
  if (phase === Phase.DEALING) {
    lastSubmitted.current = key;
    const indices = seat === 0 ? [2, 3] : [0, 1];
    const p = decryptDealing(seat + 1, indices);
    await send(bot, "submitDecrypt", [
      tableId,
      p.cardIndices,
      p.partialDecryptionValues,
      p.proofs,
      p.cardValues,
    ], ctx);
    return { acted: true, phase };
  }
  if (phase === Phase.FLOP_REVEAL) {
    lastSubmitted.current = key;
    const p = decryptReveal(seat + 1, FLOP_INDICES, REVEAL_VALUES.flop);
    await send(bot, "submitDecrypt", [
      tableId,
      p.cardIndices,
      p.partialDecryptionValues,
      p.proofs,
      p.cardValues,
    ], ctx);
    return { acted: true, phase };
  }
  if (phase === Phase.TURN_REVEAL) {
    lastSubmitted.current = key;
    const p = decryptReveal(seat + 1, TURN_INDICES, REVEAL_VALUES.turn);
    await send(bot, "submitDecrypt", [
      tableId,
      p.cardIndices,
      p.partialDecryptionValues,
      p.proofs,
      p.cardValues,
    ], ctx);
    return { acted: true, phase };
  }
  if (phase === Phase.RIVER_REVEAL) {
    lastSubmitted.current = key;
    const p = decryptReveal(seat + 1, RIVER_INDICES, REVEAL_VALUES.river);
    await send(bot, "submitDecrypt", [
      tableId,
      p.cardIndices,
      p.partialDecryptionValues,
      p.proofs,
      p.cardValues,
    ], ctx);
    return { acted: true, phase };
  }

  // Betting phases: only if it's the bot's turn. Prefer CALL; fall back to
  // CHECK when there's nothing to call.
  if (
    (phase === Phase.PREFLOP ||
      phase === Phase.FLOP_BET ||
      phase === Phase.TURN_BET ||
      phase === Phase.RIVER_BET) &&
    t.turn === seat
  ) {
    lastSubmitted.current = key;
    try {
      await send(bot, "act", [tableId, ActionCode.CALL, 0n], ctx);
    } catch {
      await send(bot, "act", [tableId, ActionCode.CHECK, 0n], ctx);
    }
    return { acted: true, phase };
  }

  // Showdown.
  if (phase === Phase.SHOWDOWN) {
    lastSubmitted.current = key;
    const dealt = dealHoleCards(tableId, t.players[0], t.players[1]);
    const cards = seat === 0 ? dealt.p1 : dealt.p2;
    await send(bot, "revealHand", [tableId, "0x", cards], ctx);
    return { acted: true, phase };
  }

  return { acted: false, phase };
}
