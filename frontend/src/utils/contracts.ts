import type { Address } from "viem";
import PokerTableArtifact from "../abi/PokerTable.json";
import SpectatorMarketArtifact from "../abi/SpectatorMarket.json";
import RevealVerifierArtifact from "../abi/RevealVerifier.json";

export const POKER_TABLE_ADDRESS = (import.meta.env.VITE_POKER_TABLE_ADDRESS ||
  "0x6Ccaf05ac50eABE2c90b8187b9B6734dCB0E88eC") as Address;

export const SPECTATOR_MARKET_ADDRESS = (import.meta.env
  .VITE_SPECTATOR_MARKET_ADDRESS || "0x0000000000000000000000000000000000000000") as Address;

export const REVEAL_VERIFIER_ADDRESS = (import.meta.env
  .VITE_REVEAL_VERIFIER_ADDRESS || "0x0000000000000000000000000000000000000000") as Address;

export const POKER_TABLE_ABI = PokerTableArtifact.abi;
export const SPECTATOR_MARKET_ABI = SpectatorMarketArtifact.abi;
export const REVEAL_VERIFIER_ABI = RevealVerifierArtifact.abi;
