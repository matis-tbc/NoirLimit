import { useState } from "react";
import { useWriteContract, usePublicClient } from "wagmi";
import type { Hex } from "viem";
import { POKER_TABLE_ABI, POKER_TABLE_ADDRESS } from "../utils/contracts";
import { Phase } from "../utils/phase";
import { parseRevert } from "../utils/parseRevert";

interface Props {
  tableId: bigint | undefined;
  phase: number;
  // Real hole cards for the current seat, so we can submit the honest reveal
  // after the cheat attempt resolves. Null when the viewer has no seat.
  realCards: [number, number] | null;
  // Called the instant the user confirms they want to cheat. Parent uses this
  // to gate useAutoSubmit so our bogus reveal reaches the chain first instead
  // of racing the auto-submitted honest reveal.
  onAttempt: () => void;
  // Called when the user clicks "Submit real reveal" after the cheat has
  // resolved. Parent wires this to useGameActions.revealHand.
  onRealReveal: (cards: [number, number]) => Promise<void>;
}

type State =
  | { kind: "idle" }
  | { kind: "confirming" }
  | { kind: "trying" }
  | { kind: "caught"; reason: string; hash?: Hex }
  | { kind: "snuck"; hash: Hex }
  | { kind: "revealing" }
  | { kind: "revealed" };

// The one moment in the demo where a ZK-enforced invariant is visible. Submits
// a deliberately-invalid revealHand that duplicates community-card indices;
// PokerTable.sol:390 rejects it. In demoMode the MockVerifier accepts any
// proof bytes, so what catches this is a Solidity require, NOT the Noir
// circuit. The copy reflects that truthfully; with a real verifier deployed
// the circuit would catch it one layer earlier.
export function CheatMoment({ tableId, phase, realCards, onAttempt, onRealReveal }: Props) {
  const showdownReady = phase === Phase.SHOWDOWN;
  const { writeContractAsync, isPending } = useWriteContract();
  const publicClient = usePublicClient();
  const [state, setState] = useState<State>({ kind: "idle" });

  const tryCheat = async () => {
    if (tableId === undefined) return;
    // Flip the gate BEFORE submitting so useAutoSubmit cannot fire an honest
    // reveal between our state update and the tx hitting the chain.
    onAttempt();
    setState({ kind: "trying" });
    const BOGUS: [number, number] = [51, 50];
    try {
      const hash = (await writeContractAsync({
        address: POKER_TABLE_ADDRESS,
        abi: POKER_TABLE_ABI,
        functionName: "revealHand",
        args: [tableId, "0x", BOGUS],
      })) as Hex;
      if (publicClient) {
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        if (receipt.status === "success") {
          setState({ kind: "snuck", hash });
        } else {
          setState({ kind: "caught", reason: "Transaction reverted on-chain", hash });
        }
      } else {
        setState({ kind: "snuck", hash });
      }
    } catch (err) {
      const { reason } = parseRevert(err);
      setState({ kind: "caught", reason });
    }
  };

  return (
    <>
      <div className="border border-red-900/60 bg-red-950/20 rounded p-4 space-y-3">
        <div className="flex items-center justify-between">
          <div>
            <div className="text-xs uppercase tracking-[0.3em] text-red-400">
              Break the proof
            </div>
            <div className="text-[11px] text-ink/60 mt-1">
              Submit a bogus reveal. The contract should refuse it.
            </div>
          </div>
          <button
            onClick={() => setState({ kind: "confirming" })}
            disabled={isPending || tableId === undefined || !showdownReady}
            title={!showdownReady ? "Available at showdown" : undefined}
            className="px-4 py-2 border border-red-500 text-red-300 uppercase text-xs tracking-widest hover:bg-red-900/40 disabled:opacity-30 transition"
          >
            {state.kind === "trying" ? "attempting..." : "Try to cheat"}
          </button>
        </div>
        <p className="text-[11px] text-ink/50 leading-snug">
          This is the only moment in this UI where a cheating attempt is
          visibly caught. In demoMode the MockVerifier accepts any proof
          bytes, so what rejects this is a Solidity <code>require</code> in{" "}
          <code>revealHand</code>. With a real verifier on, the Noir{" "}
          <code>reveal</code> circuit would catch it one layer earlier.
          {!showdownReady && (
            <span className="text-ink/40"> (wait for showdown)</span>
          )}
        </p>
      </div>

      {state.kind === "confirming" && (
        <ConfirmModal
          onCancel={() => setState({ kind: "idle" })}
          onConfirm={tryCheat}
        />
      )}

      {state.kind === "caught" && (
        <CaughtModal
          reason={state.reason}
          hash={state.hash}
          canReveal={realCards !== null}
          revealing={false}
          onClose={() => setState({ kind: "idle" })}
          onSubmitReal={async () => {
            if (!realCards) return;
            setState({ kind: "revealing" });
            try {
              await onRealReveal(realCards);
              setState({ kind: "revealed" });
            } catch {
              // Parent already surfaced the error via useGameActions.lastError.
              // Drop back to the caught modal so the user can retry.
              setState({ kind: "caught", reason: "real reveal failed, retry" });
            }
          }}
        />
      )}

      {state.kind === "revealing" && (
        <RevealingModal />
      )}

      {state.kind === "revealed" && (
        <RevealedModal onClose={() => setState({ kind: "idle" })} />
      )}

      {state.kind === "snuck" && (
        <SnuckModal hash={state.hash} onClose={() => setState({ kind: "idle" })} />
      )}
    </>
  );
}

function ConfirmModal({ onCancel, onConfirm }: { onCancel: () => void; onConfirm: () => void }) {
  return (
    <div className="fixed inset-0 z-50 bg-black/85 backdrop-blur flex items-center justify-center">
      <div className="max-w-md w-[90%] border border-red-500/60 bg-bg p-6 space-y-4">
        <div className="text-xs uppercase tracking-[0.3em] text-red-400">
          Send invalid tx
        </div>
        <p className="text-sm text-ink/80 leading-snug">
          This sends a deliberately-invalid <code>revealHand</code> tx with
          cards that cannot match the on-chain commitments. It should fail.
          Costs Sepolia gas (~30k) but no ETH.
        </p>
        <div className="flex gap-2 justify-end">
          <button
            onClick={onCancel}
            className="px-4 py-2 border border-edge text-xs uppercase tracking-widest hover:border-gold/60"
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            className="px-4 py-2 border border-red-500 text-red-300 text-xs uppercase tracking-widest hover:bg-red-900/40"
          >
            Submit bogus reveal
          </button>
        </div>
      </div>
    </div>
  );
}

function CaughtModal({
  reason,
  hash,
  canReveal,
  revealing,
  onClose,
  onSubmitReal,
}: {
  reason: string;
  hash?: Hex;
  canReveal: boolean;
  revealing: boolean;
  onClose: () => void;
  onSubmitReal: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 bg-black/85 backdrop-blur flex items-center justify-center">
      <div className="max-w-xl w-[90%] border border-green-500/60 bg-bg p-6 space-y-4">
        <div className="text-xs uppercase tracking-[0.3em] text-green-400">
          Contract caught the cheat
        </div>
        <p className="text-sm text-ink/80 leading-snug">
          The chain refused the bogus reveal. The revert reason below is what
          the on-chain invariant returned. In demoMode this is a Solidity
          check; with a real verifier deployed, the Noir circuit would catch
          it one layer earlier.
        </p>
        <div className="border border-edge bg-black/40 p-3 space-y-2">
          <div className="text-[10px] uppercase tracking-widest text-ink/50">
            Revert reason
          </div>
          <div className="font-mono text-sm text-red-300 break-words">
            {reason}
          </div>
        </div>
        {hash && (
          <div className="text-[11px] text-ink/60 break-all">
            tx:{" "}
            <a
              href={`https://sepolia.etherscan.io/tx/${hash}`}
              target="_blank"
              rel="noreferrer"
              className="underline text-gold/80"
            >
              {hash}
            </a>
          </div>
        )}
        <div className="flex justify-end gap-2">
          <button
            onClick={onClose}
            className="px-4 py-2 border border-edge text-xs uppercase tracking-widest hover:border-gold/60"
          >
            Close
          </button>
          {canReveal && (
            <button
              onClick={onSubmitReal}
              disabled={revealing}
              className="px-4 py-2 border border-green-500 text-green-300 text-xs uppercase tracking-widest hover:bg-green-900/30 disabled:opacity-30"
            >
              {revealing ? "submitting..." : "Submit real reveal"}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

function RevealingModal() {
  return (
    <div className="fixed inset-0 z-50 bg-black/85 backdrop-blur flex items-center justify-center">
      <div className="max-w-sm w-[90%] border border-edge bg-bg p-6 space-y-3">
        <div className="text-xs uppercase tracking-[0.3em] text-gold">
          Submitting honest reveal
        </div>
        <p className="text-sm text-ink/80 leading-snug">
          Sending your real hole cards. The contract should accept this one.
        </p>
      </div>
    </div>
  );
}

function RevealedModal({ onClose }: { onClose: () => void }) {
  return (
    <div className="fixed inset-0 z-50 bg-black/85 backdrop-blur flex items-center justify-center">
      <div className="max-w-sm w-[90%] border border-gold/60 bg-bg p-6 space-y-3">
        <div className="text-xs uppercase tracking-[0.3em] text-gold">
          Honest reveal submitted
        </div>
        <p className="text-sm text-ink/80 leading-snug">
          Real cards submitted. The hand settles once both players reveal.
        </p>
        <div className="flex justify-end">
          <button
            onClick={onClose}
            className="px-4 py-2 border border-edge text-xs uppercase tracking-widest hover:border-gold/60"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}

function SnuckModal({ hash, onClose }: { hash: Hex; onClose: () => void }) {
  return (
    <div className="fixed inset-0 z-50 bg-black/85 backdrop-blur flex items-center justify-center">
      <div className="max-w-md w-[90%] border border-yellow-500/60 bg-bg p-6 space-y-4">
        <div className="text-xs uppercase tracking-[0.3em] text-yellow-400">
          Unexpected: tx succeeded
        </div>
        <p className="text-sm text-ink/80 leading-snug">
          The bogus reveal was not rejected. This means either the contract
          invariants have drifted or the demoMode bypass is wider than
          expected. Worth filing.
        </p>
        <div className="text-[11px] text-ink/60 break-all">
          tx:{" "}
          <a
            href={`https://sepolia.etherscan.io/tx/${hash}`}
            target="_blank"
            rel="noreferrer"
            className="underline text-gold/80"
          >
            {hash}
          </a>
        </div>
        <div className="flex justify-end">
          <button
            onClick={onClose}
            className="px-4 py-2 border border-edge text-xs uppercase tracking-widest hover:border-gold/60"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
