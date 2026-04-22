set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

SEPOLIA_RPC := env_var_or_default("SEPOLIA_RPC_URL", "")
REVEAL_VERIFIER := env_var_or_default("REVEAL_VERIFIER_ADDRESS", "0x8A6e6fb6e795a22d6eD4cB3922bDE5164B03BB51")

default:
    @just --list

# Regenerate the prover fixture from the canonical Prover.toml sample.
fixture:
    cd prover && node prove-reveal.mjs --out fixture.json

# Run the Foundry RevealVerifier tests against the local fixture.
test-reveal:
    cd contracts && forge test --match-contract RevealVerifierTest -vv

# End-to-end ZK pipeline verification for demo day. Proves the SNARK is real
# across all three boundaries: (1) bb.js self-verify, (2) Foundry against the
# local fixture, (3) Sepolia verifier for both honest and tampered inputs.
# Prints PASS/FAIL for each step. Any failure aborts.
verify-e2e:
    @./scripts/verify-e2e.sh

# Deploy the standalone RevealVerifier to Sepolia. Requires PRIVATE_KEY env.
deploy-reveal-verifier:
    @if [ -z "{{SEPOLIA_RPC}}" ]; then echo "ERROR: SEPOLIA_RPC_URL not set." >&2; exit 1; fi
    cd contracts && forge script script/DeployRevealVerifier.s.sol --rpc-url "{{SEPOLIA_RPC}}" --broadcast -vvv
