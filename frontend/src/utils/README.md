# Utils

Helper functions for the frontend.

## Files to Build

| File | Purpose |
|------|---------|
| `noir.ts` | Initializes Noir WASM backend, loads compiled circuits, provides `generateProof(circuitName, inputs)` function |
| `cards.ts` | Card value encoding/decoding (uint8 <-> suit/rank), display name helpers ("Ace of Spades"), card image mapping |
| `contracts.ts` | Contract addresses per network, ABI imports, provider/signer initialization |
| `crypto.ts` | Client-side Pedersen commitment generation to match what the circuits expect |
