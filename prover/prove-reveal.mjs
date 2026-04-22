// NoirLimit reveal-circuit prover.
// UltraPlonk, matching the generated RevealVerifier.sol.
//
// For the sample fixture (cards=[7,42], nonces=[111,222]) we use the commitments
// pre-computed in circuits/reveal/Prover.toml. For custom inputs, callers must
// supply pre-computed commitments (see --commit0 --commit1). This is because
// @aztec/bb.js@0.63.1 does not expose pedersen_hash; the canonical path to compute
// commitments in Node is `nargo execute` — we rely on circuit-computed fixtures.
//
// Usage:
//   node prove-reveal.mjs                       -> prove Prover.toml sample
//   node prove-reveal.mjs --out fixture.json    -> write proof+pubs to JSON
//
// Writes Solidity-consumable fixture: proofHex + publicInputs[] as bytes32[].

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Noir } from "@noir-lang/noir_js";
import { UltraPlonkBackend } from "@aztec/bb.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REVEAL_JSON = path.resolve(__dirname, "../circuits/target/reveal.json");

// Canonical sample matches circuits/reveal/Prover.toml.
const SAMPLE = {
  cards: [7, 42],
  nonces: ["111", "222"],
  commitments: [
    "0x160793b515d0d1131a79dc717a10b37f7d6036dc9a7766d41e63b5e7f98c6315",
    "0x167c2ea7d291dd3daef806a5d01512eb0d85eef5edc6f8802b45d4a7f1206529",
  ],
};

function parseArgs(argv) {
  const out = { ...SAMPLE, outFile: null };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--out") out.outFile = argv[++i];
    else if (a === "--cards") out.cards = argv[++i].split(",").map((n) => parseInt(n, 10));
    else if (a === "--nonces") out.nonces = argv[++i].split(",");
    else if (a === "--commit0") out.commitments[0] = argv[++i];
    else if (a === "--commit1") out.commitments[1] = argv[++i];
  }
  return out;
}

function toHex32(v) {
  const h = typeof v === "bigint" ? v.toString(16) : BigInt(v).toString(16);
  return "0x" + h.padStart(64, "0");
}

async function main() {
  const args = parseArgs(process.argv);
  const raw = JSON.parse(fs.readFileSync(REVEAL_JSON, "utf8"));

  console.log("[prove-reveal] inputs:", {
    cards: args.cards,
    nonces: args.nonces,
    commit0: args.commitments[0],
    commit1: args.commitments[1],
  });

  const witnessInput = {
    card_commitments: args.commitments,
    revealed_cards: args.cards.map((c) => c.toString()),
    commitment_randomness: args.nonces,
  };

  const noir = new Noir(raw);
  const t0 = Date.now();
  const { witness } = await noir.execute(witnessInput);
  const tExec = Date.now() - t0;
  console.log(`[prove-reveal] witness executed in ${tExec}ms`);

  const backend = new UltraPlonkBackend(raw.bytecode, { threads: 2 });
  const t1 = Date.now();
  const { proof, publicInputs } = await backend.generateProof(witness);
  const tProve = Date.now() - t1;
  console.log(`[prove-reveal] proof generated in ${tProve}ms, proof bytes: ${proof.length}`);
  console.log(`[prove-reveal] public inputs from bb.js: ${publicInputs.length}`);
  publicInputs.forEach((p, i) => console.log(`  pub[${i}] = ${p}`));

  const t2 = Date.now();
  const ok = await backend.verifyProof({ proof, publicInputs });
  console.log(`[prove-reveal] self-verify: ${ok} (${Date.now() - t2}ms)`);
  if (!ok) {
    console.error("[prove-reveal] bb.js self-verify failed — aborting");
    process.exit(2);
  }

  const proofHex = "0x" + Buffer.from(proof).toString("hex");
  // On-chain order: [c0, c1, card0, card1] as bytes32 (matches PokerTable.sol:398-402).
  const pubs = [
    args.commitments[0],
    args.commitments[1],
    toHex32(args.cards[0]),
    toHex32(args.cards[1]),
  ];

  const fixture = {
    circuit: "reveal",
    cards: args.cards,
    nonces: args.nonces,
    commitments: args.commitments,
    publicInputs: pubs,
    proofHex,
    timings: { witnessMs: tExec, proveMs: tProve },
  };

  if (args.outFile) {
    const out = path.resolve(args.outFile);
    fs.writeFileSync(out, JSON.stringify(fixture, null, 2));
    console.log(`[prove-reveal] wrote fixture to ${out}`);
  }

  await backend.destroy?.();
  console.log("[prove-reveal] done.");
}

main().catch((e) => {
  console.error("[prove-reveal] FAILED:", e);
  process.exit(1);
});
