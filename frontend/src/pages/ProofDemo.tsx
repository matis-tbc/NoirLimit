import { useMemo, useState } from "react";
import { useReadContract } from "wagmi";
import { sepolia } from "wagmi/chains";
import type { Hex } from "viem";
import {
  REVEAL_VERIFIER_ABI,
  REVEAL_VERIFIER_ADDRESS,
} from "../utils/contracts";

type Stage =
  | "idle"
  | "loadingCircuit"
  | "executingWitness"
  | "initializingBackend"
  | "generatingProof"
  | "selfVerifying"
  | "ready"
  | "error";

type ProofArtifact = {
  proofHex: Hex;
  publicInputs: Hex[];
  witnessMs: number;
  proveMs: number;
};

// Canonical sample matches circuits/reveal/Prover.toml and the Foundry fixture.
// Keeping the commitments pre-computed avoids needing pedersen_hash in the
// browser (bb.js 0.63.1 does not expose it).
const SAMPLE = {
  cards: [7, 42] as [number, number],
  nonces: ["111", "222"] as [string, string],
  commitments: [
    "0x160793b515d0d1131a79dc717a10b37f7d6036dc9a7766d41e63b5e7f98c6315",
    "0x167c2ea7d291dd3daef806a5d01512eb0d85eef5edc6f8802b45d4a7f1206529",
  ] as [Hex, Hex],
};

function toHex32(n: number | bigint): Hex {
  const h = typeof n === "bigint" ? n.toString(16) : BigInt(n).toString(16);
  return ("0x" + h.padStart(64, "0")) as Hex;
}

function bytesToHex(bytes: Uint8Array): Hex {
  let s = "0x";
  for (let i = 0; i < bytes.length; i++) {
    s += bytes[i].toString(16).padStart(2, "0");
  }
  return s as Hex;
}

const STAGE_LABEL: Record<Stage, string> = {
  idle: "Idle",
  loadingCircuit: "Loading circuit",
  executingWitness: "Executing witness",
  initializingBackend: "Initializing backend (wasm)",
  generatingProof: "Generating proof",
  selfVerifying: "Self-verifying",
  ready: "Proof ready",
  error: "Error",
};

export default function ProofDemo() {
  const [stage, setStage] = useState<Stage>("idle");
  const [artifact, setArtifact] = useState<ProofArtifact | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [tamper, setTamper] = useState(false);
  const [logs, setLogs] = useState<string[]>([]);
  // Remember which tamper state was in effect when the last on-chain verify
  // ran, so toggling the switch doesn't leave a stale result+label pair on
  // screen (which would invert "expected"/"unexpected" misleadingly).
  const [verifiedAtTamper, setVerifiedAtTamper] = useState<boolean | null>(null);

  const log = (line: string) =>
    setLogs((l) => [...l, `[${new Date().toISOString().slice(11, 19)}] ${line}`]);

  const verifierConfigured =
    REVEAL_VERIFIER_ADDRESS !== "0x0000000000000000000000000000000000000000";

  const onChainInputs = useMemo(() => {
    if (!artifact) return null;
    const inputs = [...artifact.publicInputs] as Hex[];
    if (tamper) {
      // Swap revealed_cards[0] from 7 to 8. The circuit commitment binds
      // card|nonce, so the pedersen check fails inside the SNARK and the
      // verifier MUST reject.
      inputs[2] = toHex32(8);
    }
    return inputs;
  }, [artifact, tamper]);

  const {
    data: verifyOk,
    error: verifyErr,
    isFetching: verifying,
    refetch: refetchVerify,
  } = useReadContract({
    address: REVEAL_VERIFIER_ADDRESS,
    abi: REVEAL_VERIFIER_ABI,
    functionName: "verify",
    args: artifact && onChainInputs ? [artifact.proofHex, onChainInputs] : undefined,
    chainId: sepolia.id,
    query: {
      enabled: false, // manual trigger only
      retry: false,
    },
  });

  async function generate() {
    setErr(null);
    setArtifact(null);
    setLogs([]);
    try {
      setStage("loadingCircuit");
      log("fetching /reveal.json");
      const res = await fetch("/reveal.json");
      if (!res.ok) throw new Error(`failed to load circuit: ${res.status}`);
      const circuit = await res.json();
      log(`loaded circuit (${circuit.bytecode?.length ?? 0} chars of bytecode)`);

      setStage("executingWitness");
      // Vite dev server returns the SPA fallback for wasm URLs unless we
      // resolve them explicitly via ?url. Noir.execute() calls initAbi() +
      // initACVM() internally with no args, which then tries
      // `new URL('*_bg.wasm', import.meta.url)` and hits the HTML fallback.
      // Pre-init with explicit URLs to side-step that.
      const [
        { Noir },
        { default: initACVM },
        acvmWasmUrl,
        { default: initAbi },
        abiWasmUrl,
      ] = await Promise.all([
        import("@noir-lang/noir_js"),
        import("@noir-lang/acvm_js"),
        import("@noir-lang/acvm_js/web/acvm_js_bg.wasm?url"),
        import("@noir-lang/noirc_abi"),
        import("@noir-lang/noirc_abi/web/noirc_abi_wasm_bg.wasm?url"),
      ]);
      await Promise.all([
        initACVM((acvmWasmUrl as unknown as { default: string }).default ?? acvmWasmUrl),
        initAbi((abiWasmUrl as unknown as { default: string }).default ?? abiWasmUrl),
      ]);
      log("acvm + noirc_abi wasm initialized");
      const noir = new Noir(circuit);
      const witnessInput = {
        card_commitments: SAMPLE.commitments,
        revealed_cards: SAMPLE.cards.map((c) => c.toString()),
        commitment_randomness: SAMPLE.nonces,
      };
      const t0 = performance.now();
      const { witness } = await noir.execute(witnessInput);
      const tExec = Math.round(performance.now() - t0);
      log(`witness executed in ${tExec}ms`);

      setStage("initializingBackend");
      const { UltraPlonkBackend } = await import("@aztec/bb.js");
      const backend = new UltraPlonkBackend(circuit.bytecode, { threads: 2 });
      log("UltraPlonkBackend ready");

      setStage("generatingProof");
      const t1 = performance.now();
      const { proof, publicInputs } = await backend.generateProof(witness);
      const tProve = Math.round(performance.now() - t1);
      log(`proof generated in ${tProve}ms (${proof.length} bytes)`);

      setStage("selfVerifying");
      const ok = await backend.verifyProof({ proof, publicInputs });
      log(`bb.js self-verify: ${ok}`);
      if (!ok) throw new Error("bb.js self-verify failed");

      const proofHex = bytesToHex(proof);
      // On-chain order must match the Solidity verifier: [c0, c1, card0, card1].
      const pubs: Hex[] = [
        SAMPLE.commitments[0],
        SAMPLE.commitments[1],
        toHex32(SAMPLE.cards[0]),
        toHex32(SAMPLE.cards[1]),
      ];

      setArtifact({
        proofHex,
        publicInputs: pubs,
        witnessMs: tExec,
        proveMs: tProve,
      });
      setStage("ready");

      // Best-effort cleanup; bb.js 0.63.1 has destroy on the backend.
      await (backend as unknown as { destroy?: () => Promise<void> }).destroy?.();
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      setErr(msg);
      log(`ERROR: ${msg}`);
      setStage("error");
    }
  }

  async function verifyOnChain() {
    if (!verifierConfigured) {
      setErr(
        "RevealVerifier address not configured. Set VITE_REVEAL_VERIFIER_ADDRESS in .env.local."
      );
      return;
    }
    setErr(null);
    log(
      tamper
        ? "calling verifier.verify with TAMPERED card (expect reject)"
        : "calling verifier.verify with honest inputs (expect accept)"
    );
    const r = await refetchVerify();
    setVerifiedAtTamper(tamper);
    if (r.error) {
      log(`verifier reverted: ${r.error.message?.split("\n")[0] ?? r.error}`);
    } else {
      log(`verifier returned: ${String(r.data)}`);
    }
  }

  const busy =
    stage !== "idle" &&
    stage !== "ready" &&
    stage !== "error";

  return (
    <div className="max-w-4xl mx-auto px-6 py-8 space-y-6">
      <section className="space-y-2">
        <h1 className="text-2xl font-bold tracking-widest">PROOF DEMO</h1>
        <p className="text-sm text-ink/80 max-w-2xl">
          Live zero-knowledge proof pipeline. The reveal circuit (3.1k gates)
          binds two cards to their pedersen commitments. We generate a real
          UltraPlonk proof in your browser, then verify it against the
          Solidity verifier deployed on Sepolia.
        </p>
        <p className="text-xs text-ink/50">
          Sample inputs match <code className="font-mono">circuits/reveal/Prover.toml</code>
          . Flip the tamper switch to swap a revealed card — the SNARK will
          reject before any Solidity require runs.
        </p>
      </section>

      <section className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div className="border border-edge rounded p-4 space-y-3 bg-black/20">
          <h2 className="text-xs tracking-widest text-ink/60">1. GENERATE</h2>
          <div className="text-xs space-y-1">
            <div>cards: [{SAMPLE.cards.join(", ")}]</div>
            <div>nonces: [{SAMPLE.nonces.join(", ")}]</div>
            <div className="text-ink/50 break-all">
              c0: {SAMPLE.commitments[0]}
            </div>
            <div className="text-ink/50 break-all">
              c1: {SAMPLE.commitments[1]}
            </div>
          </div>
          <button
            onClick={generate}
            disabled={busy}
            className="w-full bg-gold text-black font-bold tracking-widest text-xs py-2 disabled:opacity-50"
          >
            {busy ? STAGE_LABEL[stage].toUpperCase() + "..." : "GENERATE PROOF"}
          </button>
          {artifact && (
            <div className="text-xs text-ink/70 space-y-1 pt-2 border-t border-edge">
              <div>witness: {artifact.witnessMs}ms</div>
              <div>prove: {artifact.proveMs}ms</div>
              <div>proof size: {(artifact.proofHex.length - 2) / 2} bytes</div>
            </div>
          )}
        </div>

        <div className="border border-edge rounded p-4 space-y-3 bg-black/20">
          <h2 className="text-xs tracking-widest text-ink/60">2. VERIFY ON SEPOLIA</h2>
          {!verifierConfigured && (
            <div className="text-xs text-yellow-300/80">
              RevealVerifier address not set. Add
              <code className="font-mono"> VITE_REVEAL_VERIFIER_ADDRESS </code>
              to <code className="font-mono">.env.local</code>.
            </div>
          )}
          {verifierConfigured && (
            <div className="text-xs text-ink/70 break-all">
              verifier:{" "}
              <a
                className="underline hover:text-gold"
                href={`https://sepolia.etherscan.io/address/${REVEAL_VERIFIER_ADDRESS}`}
                target="_blank"
                rel="noreferrer"
              >
                {REVEAL_VERIFIER_ADDRESS}
              </a>
            </div>
          )}
          <label className="flex items-center gap-2 text-xs cursor-pointer">
            <input
              type="checkbox"
              checked={tamper}
              onChange={(e) => {
                setTamper(e.target.checked);
                setVerifiedAtTamper(null);
              }}
            />
            Tamper: swap revealed card 7 → 8 (expect reject)
          </label>
          <button
            onClick={verifyOnChain}
            disabled={!artifact || verifying || !verifierConfigured}
            className="w-full border border-gold text-gold font-bold tracking-widest text-xs py-2 disabled:opacity-30"
          >
            {verifying ? "VERIFYING..." : "VERIFY ON SEPOLIA"}
          </button>
          {verifyOk !== undefined && verifiedAtTamper !== null && (
            <div
              className={
                "text-sm font-bold " +
                (Boolean(verifyOk) === !verifiedAtTamper
                  ? "text-green-400"
                  : "text-red-400")
              }
            >
              verifier returned: {String(verifyOk)}{" "}
              {verifiedAtTamper
                ? Boolean(verifyOk)
                  ? "(unexpected! tamper should reject)"
                  : ", tampered input rejected, as expected"
                : Boolean(verifyOk)
                  ? ", honest proof accepted"
                  : "(unexpected! honest proof should pass)"}
            </div>
          )}
          {verifyErr && verifiedAtTamper !== null && (
            <div className="text-xs text-red-400 break-all">
              revert: {verifyErr.message?.split("\n")[0] ?? String(verifyErr)}
              {verifiedAtTamper && (
                <div className="text-green-400 pt-1">
                  revert counts as rejection, pairing check failed inside the
                  SNARK. This is the value prop of ZK.
                </div>
              )}
            </div>
          )}
        </div>
      </section>

      {err && (
        <div className="border border-red-800 bg-red-900/20 text-red-300 text-xs p-3 rounded">
          {err}
        </div>
      )}

      <section className="border border-edge rounded p-3 bg-black/30">
        <h2 className="text-xs tracking-widest text-ink/60 mb-2">LOGS</h2>
        <pre className="text-[11px] font-mono text-ink/80 whitespace-pre-wrap max-h-64 overflow-auto">
          {logs.length === 0 ? "(idle)" : logs.join("\n")}
        </pre>
      </section>
    </div>
  );
}
