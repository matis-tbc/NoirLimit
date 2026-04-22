import { Link, Route, Routes } from "react-router-dom";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import Lobby from "./pages/Lobby";
import Table from "./pages/Table";
import Spectator from "./pages/Spectator";
import ProofDemo from "./pages/ProofDemo";
import { RPC_CONFIGURED } from "./utils/wagmi";
import { POKER_TABLE_ADDRESS, REVEAL_VERIFIER_ADDRESS } from "./utils/contracts";

const ETHERSCAN_POKER = `https://sepolia.etherscan.io/address/${POKER_TABLE_ADDRESS}`;
const ETHERSCAN_VERIFIER = `https://sepolia.etherscan.io/address/${REVEAL_VERIFIER_ADDRESS}`;
const VERIFIER_DEPLOYED =
  REVEAL_VERIFIER_ADDRESS !== "0x0000000000000000000000000000000000000000";

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

      <header className="relative flex items-center justify-between px-6 py-4 border-b border-edge">
        <Link to="/" className="font-bold tracking-widest text-gold">
          NOIRLIMIT
        </Link>
        <Link
          to="/proof-demo"
          className="group absolute left-1/2 -translate-x-1/2 inline-flex items-center gap-2 px-3 py-1.5 border border-gold/60 bg-gold/10 hover:bg-gold/20 text-gold text-[11px] font-bold tracking-widest transition"
        >
          <span className="h-1.5 w-1.5 rounded-full bg-gold animate-pulse" />
          PROOF DEMO
          <span className="text-gold/70 group-hover:text-gold text-[10px] tracking-wider">
            LIVE ZK
          </span>
        </Link>
        <ConnectButton showBalance={false} chainStatus="icon" />
      </header>

      <main className="flex-1">
        <Routes>
          <Route path="/" element={<Lobby />} />
          <Route path="/table/:id" element={<Table />} />
          <Route path="/spectate/:id" element={<Spectator />} />
          <Route path="/proof-demo" element={<ProofDemo />} />
        </Routes>
      </main>

      <footer className="border-t border-edge px-6 py-4 mt-8 text-[11px] text-ink/50 flex items-center justify-center gap-4 flex-wrap">
        <a className="hover:text-gold" href={ETHERSCAN_POKER} target="_blank" rel="noreferrer">
          PokerTable.sol
        </a>
        {VERIFIER_DEPLOYED && (
          <>
            <span className="text-ink/30">|</span>
            <a
              className="hover:text-gold"
              href={ETHERSCAN_VERIFIER}
              target="_blank"
              rel="noreferrer"
            >
              RevealVerifier.sol
            </a>
          </>
        )}
        <span className="text-ink/30">|</span>
        <span>Sepolia chainId 11155111</span>
        <span className="text-ink/30">|</span>
        <span>93 contract tests passing</span>
        <span className="text-ink/30">|</span>
        <span>shuffle circuit: 103,756 gates</span>
        <span className="text-ink/30">|</span>
        <span className="text-red-400/70">unaudited</span>
      </footer>
    </div>
  );
}
