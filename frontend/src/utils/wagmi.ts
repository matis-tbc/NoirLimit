import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { sepolia } from "wagmi/chains";
import { http } from "viem";

const rawRpc = import.meta.env.VITE_SEPOLIA_RPC;
const projectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || "noirlimit-demo";

// Explicitly check for missing RPC so the UI can surface a loud banner instead
// of silently falling back to a throttled public endpoint.
export const RPC_CONFIGURED = Boolean(rawRpc && rawRpc.length > 0);
export const SEPOLIA_RPC = rawRpc || "https://rpc.sepolia.org";

export const wagmiConfig = getDefaultConfig({
  appName: "NoirLimit",
  projectId,
  chains: [sepolia],
  transports: { [sepolia.id]: http(SEPOLIA_RPC) },
  ssr: false,
});
