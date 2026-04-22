#!/usr/bin/env npx tsx
/**
 * NoirLimit Table Verifier
 *
 * Read-only chain inspection for one tableId. Run while smoke-testing the
 * frontend; the script prints what Sepolia thinks is happening RIGHT NOW
 * (current state + most-recent events in the last ~10 blocks).
 *
 * Usage:
 *   NODE_PATH=./frontend/node_modules npx tsx scripts/verify-table.ts <tableId> [--bot 0xADDRESS]
 *
 * Alchemy free tier caps eth_getLogs at 10-block range, so historical event
 * lookups are intentionally limited. Use the Etherscan link in the output
 * for the full event history.
 */

import {
  createPublicClient,
  http,
  formatEther,
  parseAbiItem,
  type Address,
} from "viem";
import { sepolia } from "viem/chains";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const POKER = "0x6Ccaf05ac50eABE2c90b8187b9B6734dCB0E88eC" as Address;
const SPECTATOR = "0x666898f7706ddd0193012aEc50EAF7D2E9FCbAf0" as Address;

const PHASE_LABELS = [
  "WAITING",
  "SHUFFLE_P1",
  "SHUFFLE_P2",
  "DEALING",
  "PREFLOP",
  "FLOP_REVEAL",
  "FLOP_BET",
  "TURN_REVEAL",
  "TURN_BET",
  "RIVER_REVEAL",
  "RIVER_BET",
  "SHOWDOWN",
  "SETTLED",
  "CANCELLED",
];
const ACTION_NAMES = ["FOLD", "CHECK", "CALL", "RAISE"];

const args = process.argv.slice(2);
const tableId = args[0] ? BigInt(args[0]) : null;
if (tableId === null) {
  console.error(
    "usage: NODE_PATH=./frontend/node_modules npx tsx scripts/verify-table.ts <tableId> [--bot 0x...]"
  );
  process.exit(1);
}
const rpcIdx = args.indexOf("--rpc");
const botIdx = args.indexOf("--bot");

function readEnvLocalRpc(): string | undefined {
  try {
    const file = resolve(process.cwd(), "frontend/.env.local");
    const text = readFileSync(file, "utf8");
    const line = text.split(/\r?\n/).find((l) => l.startsWith("VITE_SEPOLIA_RPC="));
    if (!line) return undefined;
    return line.slice("VITE_SEPOLIA_RPC=".length).replace(/^['"]|['"]$/g, "").trim() || undefined;
  } catch {
    return undefined;
  }
}

const rpc =
  rpcIdx !== -1
    ? args[rpcIdx + 1]
    : process.env.SEPOLIA_RPC || process.env.SEPOLIA_RPC_URL || readEnvLocalRpc();

if (!rpc) {
  console.error(
    "ERROR: no Sepolia RPC configured. Pass --rpc <url>, set SEPOLIA_RPC / SEPOLIA_RPC_URL, or add VITE_SEPOLIA_RPC to frontend/.env.local."
  );
  process.exit(1);
}

const botAddress = botIdx !== -1 ? (args[botIdx + 1] as Address) : undefined;

const client = createPublicClient({ chain: sepolia, transport: http(rpc) });

const POKER_EVENTS = [
  parseAbiItem(
    "event TableCreated(uint256 indexed tableId, address creator, uint256 buyIn, uint256 bigBlind)"
  ),
  parseAbiItem("event PlayerJoined(uint256 indexed tableId, address player)"),
  parseAbiItem(
    "event ShuffleSubmitted(uint256 indexed tableId, address player, bytes32 newDeckCommitment)"
  ),
  parseAbiItem(
    "event DecryptSubmitted(uint256 indexed tableId, address player, uint8[] cardIndices, bytes32[] partialDecryptionValues)"
  ),
  parseAbiItem(
    "event CommunityCardsRevealed(uint256 indexed tableId, uint8 newCardCount)"
  ),
  parseAbiItem(
    "event ActionTaken(uint256 indexed tableId, address player, uint8 action, uint256 amount)"
  ),
  parseAbiItem(
    "event HandRevealed(uint256 indexed tableId, address player, uint8 card0, uint8 card1)"
  ),
  parseAbiItem(
    "event HandSettled(uint256 indexed tableId, address winner, uint256 pot)"
  ),
  parseAbiItem(
    "event TimeoutClaimed(uint256 indexed tableId, address beneficiary)"
  ),
];

const SPEC_EVENTS = [
  parseAbiItem(
    "event WagerPlaced(uint256 indexed tableId, address spectator, address predictedWinner, uint256 amount)"
  ),
  parseAbiItem(
    "event WagersResolved(uint256 indexed tableId, address winner)"
  ),
  parseAbiItem(
    "event WinningsClaimed(uint256 indexed tableId, address spectator, uint256 amount)"
  ),
];

function short(a?: string): string {
  if (!a) return "?";
  return `${a.slice(0, 6)}...${a.slice(-4)}`;
}

function describePoker(eventName: string, a: any): string {
  switch (eventName) {
    case "TableCreated":
      return `created (buy-in ${formatEther(a.buyIn)} ETH, BB ${formatEther(a.bigBlind)})`;
    case "PlayerJoined":
      return `${short(a.player)} joined`;
    case "ShuffleSubmitted":
      return `${short(a.player)} shuffled`;
    case "DecryptSubmitted":
      return `${short(a.player)} decrypted [${(a.cardIndices || []).join(",")}]`;
    case "CommunityCardsRevealed":
      return `revealed ${a.newCardCount} community cards`;
    case "ActionTaken":
      return `${short(a.player)} ${ACTION_NAMES[a.action]}${a.amount > 0n ? " " + formatEther(a.amount) : ""}`;
    case "HandRevealed":
      return `${short(a.player)} reveals ${a.card0}, ${a.card1}`;
    case "HandSettled":
      return `pot ${formatEther(a.pot)} -> ${short(a.winner)}`;
    case "TimeoutClaimed":
      return `timeout -> ${short(a.beneficiary)}`;
    default:
      return eventName;
  }
}

function describeSpec(eventName: string, a: any): string {
  switch (eventName) {
    case "WagerPlaced":
      return `${short(a.spectator)} bet ${formatEther(a.amount)} on ${short(a.predictedWinner)}`;
    case "WagersResolved":
      return `resolved -> winner ${short(a.winner)}`;
    case "WinningsClaimed":
      return `${short(a.spectator)} claimed ${formatEther(a.amount)}`;
    default:
      return eventName;
  }
}

// Pull events for the last N blocks in 10-block chunks (Alchemy free tier
// limit). Default 60 blocks (~12 min). Increase via --blocks flag.
async function getRecentEvents(
  address: Address,
  events: any[],
  fromBlock: bigint,
  toBlock: bigint
): Promise<any[]> {
  const all: any[] = [];
  const chunkSize = 10n;
  for (const event of events) {
    let cur = fromBlock;
    while (cur <= toBlock) {
      const end = cur + chunkSize - 1n > toBlock ? toBlock : cur + chunkSize - 1n;
      try {
        const logs = await client.getLogs({
          address,
          event,
          args: { tableId: tableId! } as any,
          fromBlock: cur,
          toBlock: end,
        });
        all.push(...logs);
      } catch {
        // skip silently
      }
      cur = end + 1n;
    }
  }
  return all.sort((a, b) => Number(a.blockNumber - b.blockNumber));
}

async function main() {
  console.log(`\n=== TABLE #${tableId} on Sepolia ===\n`);

  // 1. getTable state
  const tableData = (await client.readContract({
    address: POKER,
    abi: [
      parseAbiItem(
        "function getTable(uint256) view returns (address[2], uint256[2], uint256, uint8, uint8, uint8)"
      ),
    ],
    functionName: "getTable",
    args: [tableId!],
  })) as [
    readonly [Address, Address],
    readonly [bigint, bigint],
    bigint,
    number,
    number,
    number,
  ];
  const [players, stacks, pot, phase, ccCount, turn] = tableData;

  console.log(`Phase: ${phase} (${PHASE_LABELS[phase] || "?"})`);
  console.log(`Turn:  player ${turn}`);
  console.log(`Pot:   ${formatEther(pot)} ETH (community cards revealed: ${ccCount}/5)`);
  console.log(`P1:    ${players[0]}  stack ${formatEther(stacks[0])} ETH`);
  console.log(`P2:    ${players[1]}  stack ${formatEther(stacks[1])} ETH`);

  if (botAddress) {
    const bal = await client.getBalance({ address: botAddress });
    console.log(`Bot:   ${botAddress}  bal ${formatEther(bal)} ETH`);
  }

  const head = await client.getBlockNumber();

  // 2. Recent poker events (last 60 blocks ~ 12 min, paginated)
  const blocksWindow = 60n;
  const fromBlock = head > blocksWindow ? head - blocksWindow : 0n;

  console.log(`\n--- Recent poker events (last ~12 min, blocks ${fromBlock}-${head}) ---`);
  const pokerLogs = await getRecentEvents(POKER, POKER_EVENTS, fromBlock, head);
  if (pokerLogs.length === 0) {
    console.log("  (none in window; check Etherscan for older history)");
  } else {
    for (const l of pokerLogs.slice(-12)) {
      console.log(
        `  #${l.blockNumber}  ${l.eventName.padEnd(24)} ${describePoker(l.eventName, l.args)}`
      );
    }
  }

  // 3. Spectator market state + recent events
  console.log(`\n--- Spectator market ---`);
  try {
    const market = (await client.readContract({
      address: SPECTATOR,
      abi: [
        parseAbiItem(
          "function getMarket(uint256) view returns (address[2], uint256, uint256, bool, bool, address)"
        ),
      ],
      functionName: "getMarket",
      args: [tableId!],
    })) as [
      readonly [Address, Address],
      bigint,
      bigint,
      boolean,
      boolean,
      Address,
    ];
    console.log(
      `  pools:    ${formatEther(market[1])} on P1 / ${formatEther(market[2])} on P2`
    );
    console.log(
      `  resolved: ${market[3]}  refundsOnly: ${market[4]}  winner: ${market[5]}`
    );

    const specLogs = await getRecentEvents(SPECTATOR, SPEC_EVENTS, fromBlock, head);
    if (specLogs.length === 0) {
      console.log("  (no recent spectator events)");
    } else {
      for (const l of specLogs) {
        console.log(`  #${l.blockNumber}  ${l.eventName}  ${describeSpec(l.eventName, l.args)}`);
      }
    }
  } catch (err: any) {
    console.log(`  (read failed: ${err?.shortMessage || err?.message?.split("\n")[0]})`);
  }

  // 4. Verdict
  console.log(`\n--- Verdict ---`);
  if (phase === 12) {
    console.log("  SETTLED. Hand complete.");
  } else if (phase === 13) {
    console.log("  CANCELLED.");
  } else if (phase === 0) {
    console.log("  WAITING. Bot should call joinTable shortly if in bot mode.");
  } else {
    const lastBlock = pokerLogs.length > 0 ? pokerLogs[pokerLogs.length - 1].blockNumber : 0n;
    const blocksSince = lastBlock > 0n ? head - lastBlock : 0n;
    const secsSince = Number(blocksSince) * 12;
    if (lastBlock === 0n) {
      console.log(`  ${PHASE_LABELS[phase]}: no events in last ${blocksWindow} blocks (state read OK).`);
    } else if (secsSince > 120) {
      console.log(`  STUCK at ${PHASE_LABELS[phase]} for ~${secsSince}s (>120s deadline).`);
      console.log(`  Recovery: call claimTimeout(${tableId}) from any wallet.`);
    } else if (secsSince > 30) {
      console.log(`  SLOW: last event ~${secsSince}s ago at ${PHASE_LABELS[phase]}.`);
      console.log(`  Probably waiting on player ${turn}.`);
    } else {
      console.log(`  PROGRESSING: ${PHASE_LABELS[phase]}, last event ~${secsSince}s ago.`);
    }
  }

  console.log(
    `\n  Etherscan (full history): https://sepolia.etherscan.io/address/${POKER}#events`
  );
  console.log(
    `  SpectatorMarket:          https://sepolia.etherscan.io/address/${SPECTATOR}#events\n`
  );
}

main().catch((err) => {
  console.error("verify-table failed:", err?.shortMessage || err?.message || err);
  process.exit(1);
});
