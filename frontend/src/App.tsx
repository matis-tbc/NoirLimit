import { Link, Route, Routes } from "react-router-dom";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import Lobby from "./pages/Lobby";
import Table from "./pages/Table";
import Spectator from "./pages/Spectator";
import { RPC_CONFIGURED } from "./utils/wagmi";
import { POKER_TABLE_ADDRESS } from "./utils/contracts";

const ETHERSCAN_POKER = `https://sepolia.etherscan.io/address/${POKER_TABLE_ADDRESS}`;

export default function App() {
  return (
    <div className="min-h-full flex flex-col">
      {!RPC_CONFIGURED && (
        <div className="bg-red-900/40 text-red-200 text-xs text-center py-2 border-b border-red-800">
          No Sepolia RPC configured. Set{" "}
          <code className="font-mono">VITE_SEPOLIA_RPC</code> in{" "}
          <code className="font-mono">.env.local</code> (free Alchemy key at{" "}
          <a
            className="underline"
            href="https://www.alchemy.com/"
            target="_blank"
            rel="noreferrer"
          >
            alchemy.com
          </a>
          ). Public RPC will rate-limit.
        </div>
      )}

      <div className="bg-yellow-900/20 border-b border-yellow-800/50 text-yellow-300/90 text-[11px] text-center py-1.5 tracking-wide">
        TESTNET DEMO - mock verifier active - do not send real funds
      </div>

      <header className="flex items-center justify-between px-6 py-4 border-b border-edge">
        <Link to="/" className="font-bold tracking-widest text-gold">
          NOIRLIMIT
        </Link>
        <ConnectButton showBalance={false} chainStatus="icon" />
      </header>

      <main className="flex-1">
        <Routes>
          <Route path="/" element={<Lobby />} />
          <Route path="/table/:id" element={<Table />} />
          <Route path="/spectate/:id" element={<Spectator />} />
        </Routes>
      </main>

      <footer className="border-t border-edge px-6 py-4 mt-8 text-[11px] text-ink/50 flex items-center justify-center gap-4 flex-wrap">
        <a className="hover:text-gold" href={ETHERSCAN_POKER} target="_blank" rel="noreferrer">
          PokerTable.sol (Etherscan)
        </a>
        <span className="text-ink/30">|</span>
        <span>Sepolia chainId 11155111</span>
        <span className="text-ink/30">|</span>
        <span>90 contract tests passing</span>
        <span className="text-ink/30">|</span>
        <span>shuffle circuit: 103,756 gates</span>
        <span className="text-ink/30">|</span>
        <span className="text-red-400/70">unaudited</span>
      </footer>
    </div>
  );
}
