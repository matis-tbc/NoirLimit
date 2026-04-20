import { generatePrivateKey, privateKeyToAccount, type PrivateKeyAccount } from "viem/accounts";
import { createWalletClient, createPublicClient, http, type Address } from "viem";
import { sepolia } from "viem/chains";
import { SEPOLIA_RPC } from "../utils/wagmi";

const KEY_PREFIX = "noirlimit:bot-key:";

export function getOrCreateBotKey(hostAddress: Address): `0x${string}` {
  const k = KEY_PREFIX + hostAddress.toLowerCase();
  let pk = localStorage.getItem(k) as `0x${string}` | null;
  if (!pk) {
    pk = generatePrivateKey();
    localStorage.setItem(k, pk);
  }
  return pk;
}

// Address-only derivation that does NOT spin up wallet/public clients. Use
// from the Lobby so we can show + fund the bot without starting its tick loop
// (which can race the Table page's loop on the very first action).
export function getBotAddress(hostAddress: Address): Address {
  const pk = getOrCreateBotKey(hostAddress);
  return privateKeyToAccount(pk).address;
}

export function clearBotKey(hostAddress: Address) {
  localStorage.removeItem(KEY_PREFIX + hostAddress.toLowerCase());
}

export interface BotClients {
  account: PrivateKeyAccount;
  wallet: ReturnType<typeof createWalletClient>;
  publicClient: ReturnType<typeof createPublicClient>;
}

export function makeBotClients(hostAddress: Address): BotClients {
  const pk = getOrCreateBotKey(hostAddress);
  const account = privateKeyToAccount(pk);
  const wallet = createWalletClient({
    account,
    chain: sepolia,
    transport: http(SEPOLIA_RPC),
  });
  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(SEPOLIA_RPC),
  });
  return { account, wallet, publicClient };
}
