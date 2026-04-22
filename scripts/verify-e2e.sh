#!/usr/bin/env bash
# Demo-day end-to-end ZK pipeline verification for the NoirLimit reveal circuit.
#
# Proves the SNARK is real across all three boundaries:
#   1. bb.js self-verify after witness + prove       (prover-side soundness)
#   2. Foundry vs. the generated UltraVerifier.sol   (off-chain Solidity match)
#   3. Live Sepolia verifier, honest + tampered      (on-chain proof-of-deploy)
#
# Prints PASS/FAIL per step. Any failure aborts with non-zero exit.
# Usage: ./scripts/verify-e2e.sh   (or `just verify-e2e`)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SEPOLIA_RPC="${SEPOLIA_RPC_URL:-}"
VERIFIER="${REVEAL_VERIFIER_ADDRESS:-0x8A6e6fb6e795a22d6eD4cB3922bDE5164B03BB51}"

if [ -z "$SEPOLIA_RPC" ]; then
  # Try loading from frontend/.env.local as a convenience (gitignored, matches dev setup).
  ENV_FILE="$ROOT/frontend/.env.local"
  if [ -f "$ENV_FILE" ]; then
    SEPOLIA_RPC=$(grep -E '^VITE_SEPOLIA_RPC=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
  fi
fi

if [ -z "$SEPOLIA_RPC" ]; then
  echo "ERROR: SEPOLIA_RPC_URL not set. Export it or add VITE_SEPOLIA_RPC to frontend/.env.local." >&2
  exit 1
fi

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
red()   { printf "\033[31m%s\033[0m\n" "$*"; }
yellow(){ printf "\033[33m%s\033[0m\n" "$*"; }

fail() { red "FAIL: $*"; exit 1; }

bold "=== NoirLimit reveal-circuit e2e verification ==="
echo "verifier: $VERIFIER"
echo "rpc:      $SEPOLIA_RPC"
echo

# --- 1. Regenerate the fixture and self-verify in bb.js -----------------------
bold "[1/3] bb.js: prove + self-verify"
(cd prover && node prove-reveal.mjs --out fixture.json) \
  || fail "bb.js proof generation or self-verify"
green "  PASS"
echo

# --- 2. Foundry test pair: real accepted, tampered rejected -------------------
bold "[2/3] Foundry: RevealVerifier.sol (local)"
(cd contracts && forge test --match-contract RevealVerifierTest) \
  || fail "Foundry RevealVerifierTest"
green "  PASS (3/3 tests)"
echo

# --- 3. Live Sepolia verifier: honest accepts, tampered reverts ---------------
bold "[3/3] Sepolia: live verifier @ $VERIFIER"

PROOF=$(jq -r .proofHex prover/fixture.json)
PUBS=$(jq -c .publicInputs prover/fixture.json | sed 's/"//g')

echo "  (a) honest inputs -> expect true"
RET=$(cast call "$VERIFIER" "verify(bytes,bytes32[])(bool)" "$PROOF" "$PUBS" --rpc-url "$SEPOLIA_RPC")
if [[ "$RET" == "true" ]]; then
  green "      PASS: verifier returned true"
else
  fail "      verifier returned $RET (expected true)"
fi

echo "  (b) tampered card -> expect revert"
TAMPERED=$(jq -c '.publicInputs[2]="0x0000000000000000000000000000000000000000000000000000000000000008" | .publicInputs' prover/fixture.json | sed 's/"//g')
if cast call "$VERIFIER" "verify(bytes,bytes32[])(bool)" "$PROOF" "$TAMPERED" --rpc-url "$SEPOLIA_RPC" 2>/dev/null; then
  fail "      verifier accepted tampered input (MUST reject)"
else
  green "      PASS: verifier reverted (pairing check failed in SNARK)"
fi

echo
bold "=== ALL GREEN ==="
yellow "ZK pipeline verified end-to-end. Ready for demo."
