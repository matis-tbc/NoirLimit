#!/usr/bin/env npx tsx
/**
 * NoirLimit Event Logger
 *
 * Watches PokerTable events and prints a human-readable game log in real time.
 * Run: npx tsx scripts/watch-game.ts --rpc http://localhost:8545 --contract 0x...
 *
 * Requires: npm install viem (or run from frontend/ which has it)
 */

import { createPublicClient, http, parseAbiItem, formatEther, type Address } from "viem";
import { foundry, sepolia } from "viem/chains";

const args = process.argv.slice(2);
const rpcIdx = args.indexOf("--rpc");
const contractIdx = args.indexOf("--contract");

const rpcUrl = rpcIdx !== -1 ? args[rpcIdx + 1] : "http://localhost:8545";
const contractAddress = contractIdx !== -1 ? (args[contractIdx + 1] as Address) : undefined;

if (!contractAddress) {
  console.error("Usage: npx tsx scripts/watch-game.ts --rpc <url> --contract <address>");
  process.exit(1);
}

const chain = rpcUrl.includes("sepolia") ? sepolia : foundry;

const client = createPublicClient({
  chain,
  transport: http(rpcUrl),
});

const events = [
  parseAbiItem("event TableCreated(uint256 indexed tableId, address creator, uint256 buyIn, uint256 bigBlind)"),
  parseAbiItem("event PlayerJoined(uint256 indexed tableId, address player)"),
  parseAbiItem("event TableCancelled(uint256 indexed tableId)"),
  parseAbiItem("event ShuffleSubmitted(uint256 indexed tableId, address player, bytes32 newDeckCommitment)"),
  parseAbiItem("event DecryptSubmitted(uint256 indexed tableId, address player, uint8[] cardIndices, bytes32[] partialDecryptionValues)"),
  parseAbiItem("event CommunityCardsRevealed(uint256 indexed tableId, uint8 newCardCount)"),
  parseAbiItem("event ActionTaken(uint256 indexed tableId, address player, uint8 action, uint256 amount)"),
  parseAbiItem("event HandRevealed(uint256 indexed tableId, address player, uint8 card0, uint8 card1)"),
  parseAbiItem("event HandSettled(uint256 indexed tableId, address winner, uint256 pot)"),
  parseAbiItem("event TimeoutClaimed(uint256 indexed tableId, address beneficiary)"),
];

const actionNames = ["FOLD", "CHECK", "CALL", "RAISE"];

const cardRanks = ["2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"];
const cardSuits = ["c", "d", "h", "s"]; // clubs, diamonds, hearts, spades

function cardName(id: number): string {
  return cardRanks[id % 13] + cardSuits[Math.floor(id / 13)];
}

function shortAddr(addr: string): string {
  return addr.slice(0, 6) + "..." + addr.slice(-4);
}

console.log(`Watching PokerTable at ${contractAddress}`);
console.log(`RPC: ${rpcUrl}`);
console.log("---");

for (const event of events) {
  client.watchEvent({
    address: contractAddress,
    event,
    onLogs: (logs) => {
      for (const log of logs) {
        const a = log.args as any;
        const tid = a.tableId?.toString() ?? "?";
        const ts = new Date().toLocaleTimeString();

        switch (log.eventName) {
          case "TableCreated":
            console.log(`[${ts}] [Table ${tid}] Created by ${shortAddr(a.creator)} (buy-in: ${formatEther(a.buyIn)} ETH, BB: ${formatEther(a.bigBlind)} ETH)`);
            break;
          case "PlayerJoined":
            console.log(`[${ts}] [Table ${tid}] ${shortAddr(a.player)} joined`);
            break;
          case "TableCancelled":
            console.log(`[${ts}] [Table ${tid}] Cancelled`);
            break;
          case "ShuffleSubmitted":
            console.log(`[${ts}] [Table ${tid}] ${shortAddr(a.player)} shuffled deck`);
            break;
          case "DecryptSubmitted": {
            const indices = (a.cardIndices as number[]).join(",");
            console.log(`[${ts}] [Table ${tid}] ${shortAddr(a.player)} decrypted cards [${indices}]`);
            break;
          }
          case "CommunityCardsRevealed":
            console.log(`[${ts}] [Table ${tid}] Community cards revealed (${a.newCardCount} total)`);
            break;
          case "ActionTaken": {
            const action = actionNames[Number(a.action)] ?? "UNKNOWN";
            const amt = Number(a.amount) > 0 ? ` ${formatEther(a.amount)} ETH` : "";
            console.log(`[${ts}] [Table ${tid}] ${shortAddr(a.player)} ${action}${amt}`);
            break;
          }
          case "HandRevealed":
            console.log(`[${ts}] [Table ${tid}] ${shortAddr(a.player)} reveals: ${cardName(Number(a.card0))}, ${cardName(Number(a.card1))}`);
            break;
          case "HandSettled":
            if (a.winner === "0x0000000000000000000000000000000000000000") {
              console.log(`[${ts}] [Table ${tid}] Split pot: ${formatEther(a.pot)} ETH`);
            } else {
              console.log(`[${ts}] [Table ${tid}] ${shortAddr(a.winner)} WINS ${formatEther(a.pot)} ETH`);
            }
            break;
          case "TimeoutClaimed":
            console.log(`[${ts}] [Table ${tid}] Timeout claimed by ${shortAddr(a.beneficiary)}`);
            break;
        }
      }
    },
  });
}

console.log("Listening for events... (Ctrl+C to stop)");

// Keep process alive
setInterval(() => {}, 1 << 30);
