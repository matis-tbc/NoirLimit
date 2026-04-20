import { useMemo, useState } from "react";
import { useNavigate, Link } from "react-router-dom";
import { useAccount, useReadContract } from "wagmi";
import {
  parseEther,
  formatEther,
  type Address,
} from "viem";
import { POKER_TABLE_ABI, POKER_TABLE_ADDRESS } from "../utils/contracts";
import { useGameActions } from "../hooks/useGameActions";
import { getBotAddress } from "../bot/botWallet";
import { FundBotPanel } from "../components/FundBotPanel";
import { Phase, PHASE_LABELS } from "../utils/phase";
import { tableIdFromCreateTx, rememberStakes } from "../utils/createTable";

type Mode = "bot" | "manual";
type TableTuple = [
  [Address, Address],
  [bigint, bigint],
  bigint,
  number,
  number,
  number
];

export default function Lobby() {
  const { isConnected, address } = useAccount();
  const nav = useNavigate();
  const actions = useGameActions();
  const [mode, setMode] = useState<Mode>("bot");
  const [buyIn, setBuyIn] = useState("0.001");
  const [bb, setBb] = useState("0.0002");
  const [error, setError] = useState<string | null>(null);

  // Derive the bot address WITHOUT starting the bot loop here; the loop runs
  // exclusively from the Table page to avoid double-ticking against the same
  // ephemeral key during navigation.
  const botAddress = useMemo<Address | undefined>(() => {
    if (mode !== "bot" || !address) return undefined;
    return getBotAddress(address);
  }, [mode, address]);

  const { data: nextId } = useReadContract({
    address: POKER_TABLE_ADDRESS,
    abi: POKER_TABLE_ABI,
    functionName: "nextTableId",
    query: { refetchInterval: 5000 },
  });

  const onCreate = async () => {
    setError(null);
    try {
      const bbWei = parseEther(bb);
      const buyInWei = parseEther(buyIn);
      const hash = (await actions.createTable(bbWei, buyInWei)) as `0x${string}`;
      rememberStakes(buyInWei, bbWei);
      const id = await tableIdFromCreateTx(hash);
      if (id === undefined) {
        setError("Could not determine table id from receipt.");
        return;
      }
      nav(`/table/${id.toString()}${mode === "bot" ? "?bot=1" : ""}`);
    } catch (e: any) {
      setError(e?.shortMessage || e?.message || "Create failed.");
    }
  };

  return (
    <div className="max-w-5xl mx-auto px-6 py-8 space-y-8">
      <section className="space-y-3">
        <h1 className="text-2xl font-bold tracking-widest">LOBBY</h1>
        <p className="text-sm text-ink/80 max-w-2xl">
          NoirLimit is ZK poker on Ethereum. Cards are encrypted on-chain and
          verified by zero-knowledge proofs. Play a full hand against an in-app
          bot, or spectate and wager on outcomes.
        </p>
        <p className="text-xs text-ink/50">
          Running on Sepolia testnet in demo mode.{" "}
          <a
            className="underline hover:text-gold"
            href="https://www.alchemy.com/faucets/ethereum-sepolia"
            target="_blank"
            rel="noreferrer"
          >
            Need Sepolia ETH?
          </a>{" "}
          Bot mode auto-plays the opponent using an in-browser ephemeral wallet.
        </p>
        {!isConnected && (
          <p className="text-ink/60 pt-2">
            Connect a wallet above to create or join a table.
          </p>
        )}
      </section>

      {isConnected && (
        <section className="grid grid-cols-2 gap-6">
          <div className="border border-edge rounded p-4 space-y-3">
            <div className="text-xs uppercase tracking-widest text-ink/60">Mode</div>
            <div className="flex gap-2">
              {(["bot", "manual"] as Mode[]).map((m) => (
                <button
                  key={m}
                  onClick={() => setMode(m)}
                  className={
                    "px-3 py-1 border uppercase text-xs tracking-widest " +
                    (mode === m ? "border-gold text-gold" : "border-edge text-ink/70")
                  }
                >
                  {m === "bot" ? "Bot opponent" : "Manual (PvP)"}
                </button>
              ))}
            </div>

            <div className="text-xs uppercase tracking-widest text-ink/60 pt-3">
              Create table
            </div>
            <label className="block text-xs">
              Buy-in (ETH)
              <input
                value={buyIn}
                onChange={(e) => setBuyIn(e.target.value)}
                className="block w-full mt-1 bg-[#111] border border-edge px-2 py-1"
              />
            </label>
            <label className="block text-xs">
              Big blind (ETH)
              <input
                value={bb}
                onChange={(e) => setBb(e.target.value)}
                className="block w-full mt-1 bg-[#111] border border-edge px-2 py-1"
              />
            </label>
            <button
              disabled={actions.isPending}
              onClick={onCreate}
              className="w-full mt-2 px-3 py-2 border border-gold text-gold uppercase text-xs tracking-widest hover:bg-gold hover:text-bg disabled:opacity-30"
            >
              {actions.isPending ? "creating..." : "Create table"}
            </button>
            {error && <div className="text-xs text-red-400">{error}</div>}
          </div>

          {mode === "bot" && <FundBotPanel botAddress={botAddress} />}
          {mode === "manual" && (
            <div className="border border-edge rounded p-4 text-sm text-ink/70">
              Manual mode: open this app in a second browser profile with a
              different wallet, find your table below, and click Join.
            </div>
          )}
        </section>
      )}

      <section className="space-y-3">
        <div className="text-xs uppercase tracking-widest text-ink/60">Tables</div>
        <TableList
          count={nextId ? Number(nextId as bigint) : 0}
          actions={actions}
          hostAddress={address}
        />
      </section>
    </div>
  );
}

function TableList({
  count,
  actions,
  hostAddress,
}: {
  count: number;
  actions: ReturnType<typeof useGameActions>;
  hostAddress?: Address;
}) {
  if (count === 0) return <div className="text-ink/40">No tables yet.</div>;
  return (
    <div className="space-y-2">
      {Array.from({ length: count }, (_, i) => (
        <TableRow key={i} id={BigInt(i)} actions={actions} hostAddress={hostAddress} />
      ))}
    </div>
  );
}

function TableRow({
  id,
  actions,
  hostAddress,
}: {
  id: bigint;
  actions: ReturnType<typeof useGameActions>;
  hostAddress?: Address;
}) {
  const { data } = useReadContract({
    address: POKER_TABLE_ADDRESS,
    abi: POKER_TABLE_ABI,
    functionName: "getTable",
    args: [id],
    query: { refetchInterval: 6000 },
  });
  if (!data) return null;
  const [players, stacks, pot, phase] = data as TableTuple;
  const phaseNum = phase as number;
  const buyInToJoin = stacks[0]; // creator's stack equals buyIn during WAITING

  // Player is already on this table (as either seat). Don't show Join.
  const isOwnTable =
    !!hostAddress &&
    (hostAddress.toLowerCase() === players[0].toLowerCase() ||
      hostAddress.toLowerCase() === players[1].toLowerCase());

  // Join is for joining SOMEONE ELSE'S waiting table. If you created this
  // table yourself, the bot (or a second wallet) joins. Don't let you call
  // joinTable on a table where you're already P1: contract reverts.
  const canJoin = phaseNum === Phase.WAITING && !isOwnTable;
  const linkSuffix = isOwnTable ? "?bot=1" : "";

  return (
    <div className="border border-edge rounded p-3 flex items-center justify-between text-sm">
      <div>
        <div>
          Table #{id.toString()}
          {isOwnTable && (
            <span className="ml-2 text-[10px] uppercase tracking-widest text-gold/70">
              your seat
            </span>
          )}
        </div>
        <div className="text-xs text-ink/50">
          {PHASE_LABELS[phaseNum]} - buy-in {formatEther(buyInToJoin)} ETH - pot{" "}
          {formatEther(pot)} ETH
        </div>
      </div>
      <div className="flex gap-2">
        {canJoin && (
          <button
            disabled={actions.isPending}
            onClick={() => actions.joinTable(id, buyInToJoin)}
            className="px-3 py-1 border border-gold text-gold uppercase text-xs tracking-widest"
          >
            Join
          </button>
        )}
        <Link
          to={`/table/${id.toString()}${linkSuffix}`}
          className="px-3 py-1 border border-edge uppercase text-xs tracking-widest"
        >
          Open
        </Link>
        <Link
          to={`/spectate/${id.toString()}`}
          className="px-3 py-1 border border-edge uppercase text-xs tracking-widest"
        >
          Spectate
        </Link>
      </div>
    </div>
  );
}
