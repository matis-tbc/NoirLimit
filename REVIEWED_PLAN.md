# NoirLimit - Reviewed & Comprehensive Plan

Last updated: 2024-03-24

## Table of Contents

1. [Review Summary](#review-summary)
2. [Critical Protocol Fixes](#critical-protocol-fixes)
3. [Revised Architecture](#revised-architecture)
4. [MVP Scope (Heads-Up, 2 Players)](#mvp-scope)
5. [Revised Timeline](#revised-timeline)
6. [Circuit Design (Revised)](#circuit-design-revised)
7. [Contract Design (Revised)](#contract-design-revised)
8. [Frontend Plan](#frontend-plan)
9. [Open Questions](#open-questions)
10. [Research Links & References](#research-links--references)
11. [Ideas & Future Work](#ideas--future-work)

---

## Review Summary

The initial outline had a solid project structure but several protocol-level issues that would block implementation. The main problems:

1. **Shuffle protocol is broken** - last player knows the deck
2. **No mechanism for private card delivery** - Pedersen commitments hide from everyone, including the recipient
3. **Community card reveals require all players** - disconnection kills the hand entirely
4. **No timeout mechanism** - a stalling player locks funds forever
5. **Gas costs are 10-25x what the outline estimated**

This document incorporates fixes for all of the above.

---

## Critical Protocol Fixes

### Fix 1: Mental Poker Protocol for Shuffling

**Problem**: A simple "each player permutes and commits" scheme lets the last shuffler know the full deck order.

**Solution**: Use an **encrypt-shuffle (re-encryption mixnet)** protocol:

1. Start with a public ordered deck where each card is encrypted under a shared key
2. Each player:
   a. Re-encrypts every card with fresh randomness
   b. Shuffles (permutes) the re-encrypted deck
   c. Generates a ZK proof that the shuffle is a valid re-encryption permutation
3. After all players shuffle, the deck is encrypted under all players' combined randomness
4. No single player knows the card ordering because they can't undo other players' re-encryption

**Research to do**: Look into the ROYALE protocol (Aztec's mental poker design) and Barnett & Smart 2003 for the cryptographic foundations. The Aztec team has published notes on exactly this problem.

**Circuit change**: The shuffle circuit needs to prove a valid re-encryption shuffle, not just a permutation. This is more constraint-heavy but necessary.

### Fix 2: Threshold Decryption for Card Dealing

**Problem**: Pedersen commitments hide card values from everyone. There's no way for only one player to learn their card.

**Solution**: Use **threshold decryption** with player key shares:

1. Each player generates a keypair at table join and publishes their public key
2. Cards are encrypted under a combined public key (sum of all player public keys)
3. To deal a card to Player A, all *other* players provide partial decryption shares for that card position
4. Player A combines the partial decryptions with their own key to recover the card value
5. A ZK proof ensures each partial decryption is correct without revealing the decryption key

**Flow for dealing 2 hole cards to Player A in a 2-player game**:
- Player B provides partial decryption for positions 0 and 1
- Player A uses their own key + Player B's partial decryption to decrypt cards 0 and 1
- Player A now knows their hand; Player B does not

**Circuit change**: Need a new `decrypt` circuit that proves partial decryption was done correctly.

### Fix 3: Community Card Reveal Protocol

**Problem**: Revealing flop/turn/river requires all players to cooperate. If one player disconnects, community cards can't be revealed.

**Solution for 2-player MVP**: In heads-up, if one player disconnects, the hand is over anyway (forced fold). So community card reveal just needs both players to submit partial decryptions for the community card positions.

**Flow for revealing the flop (3 community cards)**:
1. Both players submit partial decryption shares for positions 4, 5, 6 (after dealing 2 cards each)
2. Contract combines shares to reveal the 3 community cards publicly
3. If either player doesn't submit within the timeout, they forfeit

**For future multi-player**: Consider a 2-of-N threshold scheme or a designated "revealer" role with a backup mechanism.

### Fix 4: Timeout/Clock System

**Problem**: No mechanism to handle stalling players.

**Solution**: Add a `TurnClock.sol` contract/module:

- Each action has a configurable timeout (e.g., 60 seconds for betting, 120 seconds for proof submission)
- When it's a player's turn, the clock starts
- If the clock expires, the contract can be called by anyone to force-fold the stalling player
- For shuffle/deal phases, timeout means the stalling player forfeits their buy-in
- Clock uses `block.timestamp` (good enough for 60+ second timeouts)

---

## MVP Scope

### 2 Players (Heads-Up) Only

Multi-player poker exponentially increases complexity:
- Shuffle protocol: N sequential shuffle proofs instead of 2
- Deal protocol: N-1 partial decryptions per card instead of 1
- Gas: scales linearly with player count per phase
- Disconnection: much harder to handle with 3+ players

**MVP is strictly heads-up Texas Hold'em.** Multi-player is a post-MVP goal.

### What's In Scope for MVP

- [x] 2-player heads-up No-Limit Texas Hold'em
- [x] ZK-private hole cards via encrypt-shuffle + threshold decryption
- [x] Public community card reveals (flop, turn, river)
- [x] Full betting rounds (pre-flop, flop, turn, river)
- [x] Showdown with ZK proof of hand
- [x] Automatic pot payout
- [x] Turn clock / timeout mechanism
- [x] One spectator wager type (winner prediction)
- [x] Basic web UI (desktop only)
- [x] Deploy on EVM testnet (Sepolia)

### What's Out of Scope for MVP

- Multi-player tables (3+ players)
- Side pots (only relevant with 3+ players)
- Multiple wager types
- Mobile UI
- Production L1 deployment (gas too high)
- Chat/social features
- Tournament mode

---

## Revised Architecture

```
                        +------------------+
                        |    Frontend      |
                        |  (React + Vite)  |
                        +--------+---------+
                                 |
                    wallet connect + proof submission
                                 |
                 +---------------+----------------+
                 |                                |
        +--------v---------+           +----------v----------+
        |   PokerTable.sol |           | SpectatorMarket.sol |
        |                  |           |                     |
        | - join/leave     |<----------| - placeWager()      |
        | - submitShuffle  |  reads    | - resolveWagers()   |
        | - submitDecrypt  |  state    |                     |
        | - placeBet       |           +---------------------+
        | - revealHand     |
        | - timeout/clock  |
        +--------+---------+
                 |
        delegates verification
                 |
    +------------+------------+
    |            |            |
+---v---+  +----v----+  +----v----+
|Shuffle|  | Decrypt |  | Reveal  |
|Verify |  | Verify  |  | Verify  |
+-------+  +---------+  +---------+
```

### Key Changes from Original

1. **Added `Decrypt` verifier** for threshold decryption proofs (new circuit)
2. **Removed `Bet` verifier** - bet validity enforced on-chain, no ZK needed
3. **Added `Deal` renamed to `Decrypt`** - the "dealing" is really "decrypting a card for one player"
4. **Timeout logic built into PokerTable** rather than a separate contract (simpler for MVP)

---

## Revised Timeline

### Week 3 (Mar 25 - Mar 31): Protocol Research & Prototyping

This is the most critical week. Do not write production code until the protocol is understood.

**Tasks**:
- [ ] Research ROYALE protocol and Barnett & Smart mental poker
- [ ] Research Noir's encryption primitives (ElGamal? Poseidon-based?)
- [ ] Prototype a 2-card encrypt-shuffle in Noir (just prove re-encryption + permutation)
- [ ] Prototype threshold decryption for 2 players in Noir
- [ ] Decide: Pedersen vs Poseidon for commitments (Poseidon is more SNARK-friendly)
- [ ] Benchmark proof generation time in browser for a simple circuit
- [ ] Set up Foundry project with `foundry.toml`
- [ ] Set up Nargo workspace with `common` as a dependency

**Assigned research**:
- Protocol design & circuit prototyping: ___
- Foundry + contract scaffolding: ___
- Frontend scaffolding + Noir WASM test: ___

### Week 4 (Apr 1 - Apr 7): Core Circuits & Contracts

**Tasks**:
- [ ] Implement shuffle circuit (re-encryption shuffle proof)
- [ ] Implement decrypt circuit (partial decryption proof)
- [ ] Implement reveal circuit (showdown card opening proof)
- [ ] Implement `PokerTable.sol` state machine (no proof verification yet, just the flow)
- [ ] Implement `TurnClock` logic in PokerTable
- [ ] Generate Solidity verifiers from circuits
- [ ] Write contract tests with mock proofs

### Week 5 (Apr 8 - Apr 14): Integration & Spectator Market

**Tasks**:
- [ ] Wire proof verification into PokerTable contract
- [ ] Implement `SpectatorMarket.sol` (winner prediction wagers)
- [ ] Build frontend: wallet connect, lobby, table view
- [ ] Integrate Noir WASM proof generation in frontend
- [ ] Test full hand lifecycle on local Anvil chain
- [ ] Test spectator wager flow

### Week 6 (Apr 15 - Apr 20): Deploy & Polish

**Tasks**:
- [ ] Deploy to Sepolia (or Aztec testnet if gas is prohibitive)
- [ ] End-to-end testing on testnet
- [ ] Fix bugs from testnet testing
- [ ] Write deployment documentation
- [ ] Record demo / prepare presentation
- [ ] Final deliverables (code repo, technical docs, web app)

---

## Circuit Design (Revised)

### Circuit 1: Shuffle (encrypt-shuffle proof)

```
Public inputs:
  - previous_deck_commitment: Field    (hash of encrypted deck before shuffle)
  - new_deck_commitment: Field         (hash of encrypted deck after shuffle)

Private inputs:
  - permutation: [u8; 52]             (shuffle permutation)
  - re_encryption_randomness: [Field; 52]  (fresh randomness per card)
  - previous_deck: [EncryptedCard; 52] (the deck before this player shuffled)
  - new_deck: [EncryptedCard; 52]      (the deck after this player shuffled)

Constraints:
  1. new_deck is a valid permutation of previous_deck (no cards added/removed)
  2. Each card in new_deck is a re-encryption of the corresponding permuted card
  3. hash(previous_deck) == previous_deck_commitment
  4. hash(new_deck) == new_deck_commitment
```

### Circuit 2: Decrypt (partial decryption proof)

```
Public inputs:
  - encrypted_card: EncryptedCard      (the encrypted card being partially decrypted)
  - partial_decryption: Field          (the partial decryption share)
  - player_public_key: Field           (the decrypting player's public key)

Private inputs:
  - player_secret_key: Field           (the decrypting player's secret key)

Constraints:
  1. partial_decryption is the correct partial decryption of encrypted_card using player_secret_key
  2. player_public_key corresponds to player_secret_key
```

### Circuit 3: Reveal (showdown proof)

```
Public inputs:
  - card_commitments: [Field; 2]       (commitments from the deal phase)
  - revealed_cards: [Card; 2]          (the actual card values)

Private inputs:
  - commitment_randomness: [Field; 2]  (opening values for the commitments)

Constraints:
  1. commit(revealed_cards[i], commitment_randomness[i]) == card_commitments[i] for each card
```

### Removed: Bet Circuit

Bet validity (legal actions, amounts) is fully enforceable on-chain since:
- Stack sizes are public
- Bet amounts are public
- Game phase is public
- Previous actions are public

No private information is needed to validate a bet. Removing this circuit simplifies the project significantly.

---

## Contract Design (Revised)

### PokerTable.sol - State Machine

```
States:
  WAITING          - Table created, waiting for 2nd player
  SHUFFLE_P1       - Player 1 submits shuffle proof
  SHUFFLE_P2       - Player 2 submits shuffle proof
  DEAL_HOLE        - Both players submit partial decryptions for opponent's hole cards
  BET_PREFLOP      - Pre-flop betting round
  REVEAL_FLOP      - Both players submit partial decryptions for flop (3 cards)
  BET_FLOP         - Flop betting round
  REVEAL_TURN      - Both players submit partial decryptions for turn (1 card)
  BET_TURN         - Turn betting round
  REVEAL_RIVER     - Both players submit partial decryptions for river (1 card)
  BET_RIVER        - River betting round
  SHOWDOWN         - Players reveal hands via ZK proofs
  PAYOUT           - Winner determined, pot distributed
  CANCELLED        - Hand cancelled (timeout/disconnect)
```

### Key Contract Functions

```solidity
// Table management
function createTable(uint256 buyIn, uint256 bigBlind) external payable;
function joinTable(uint256 tableId) external payable;
function leaveTable(uint256 tableId) external;

// Shuffle phase
function submitShuffleProof(uint256 tableId, bytes calldata proof, bytes32 newDeckCommitment) external;

// Deal phase (partial decryption)
function submitPartialDecryption(uint256 tableId, uint256 cardIndex, bytes calldata proof, uint256 partialDecrypt) external;

// Betting
function bet(uint256 tableId, uint8 action, uint256 amount) external;
// action: 0=fold, 1=check, 2=call, 3=raise

// Showdown
function revealHand(uint256 tableId, bytes calldata proof, uint8[2] calldata cards) external;

// Timeout
function claimTimeout(uint256 tableId) external;

// Events
event TableCreated(uint256 indexed tableId, address player, uint256 buyIn);
event PlayerJoined(uint256 indexed tableId, address player);
event ShuffleSubmitted(uint256 indexed tableId, address player);
event CardDealt(uint256 indexed tableId, uint256 cardIndex);
event CommunityCardRevealed(uint256 indexed tableId, uint256 cardIndex, uint8 cardValue);
event BetPlaced(uint256 indexed tableId, address player, uint8 action, uint256 amount);
event HandRevealed(uint256 indexed tableId, address player, uint8[2] cards);
event HandWon(uint256 indexed tableId, address winner, uint256 pot);
event PlayerTimedOut(uint256 indexed tableId, address player);
```

### SpectatorMarket.sol

```solidity
function placeWager(uint256 tableId, address predictedWinner) external payable;
function resolveWagers(uint256 tableId) external;
function claimWinnings(uint256 tableId) external;

event WagerPlaced(uint256 indexed tableId, address spectator, address predictedWinner, uint256 amount);
event WagersResolved(uint256 indexed tableId, address winner);
```

### Foundry Project Config

```
contracts/
  foundry.toml           # Foundry config
  remappings.txt         # Import remappings
  src/
    PokerTable.sol
    SpectatorMarket.sol
    HandEvaluator.sol
    TurnClock.sol        # Could be a library or built into PokerTable
    libraries/
      CardLib.sol
      BettingLib.sol
    interfaces/
      IPokerTable.sol
      ISpectatorMarket.sol
      IVerifier.sol
    verifiers/           # Auto-generated, gitignored except for a README
      ShuffleVerifier.sol
      DecryptVerifier.sol
      RevealVerifier.sol
  test/
    PokerTable.t.sol
    SpectatorMarket.t.sol
    HandEvaluator.t.sol
  script/
    Deploy.s.sol
```

Note: this follows standard Foundry layout (`src/`, `test/`, `script/`) instead of the original flat structure.

---

## Frontend Plan

### Tech Stack (Decided)

- **React** + TypeScript
- **Vite** bundler
- **viem** for contract interaction (not ethers.js - lighter, better typed)
- **wagmi** for wallet connection hooks
- **@noir-lang/noir_js** + **@noir-lang/backend_barretenberg** for proof generation
- **Web Workers** for proof generation (keeps UI responsive)

### Pages

1. **Lobby** (`/`) - Connect wallet, see open tables, create a table
2. **Table** (`/table/:id`) - Play poker, see your cards, bet
3. **Spectator** (`/spectator/:id`) - Watch game, place wagers

### Proof Generation Strategy

Proof generation is CPU-heavy and blocks the main thread. Strategy:
1. Load compiled circuit WASM on app startup
2. When a proof is needed, spawn a Web Worker
3. Worker generates the proof and posts it back
4. Show a "Generating proof..." spinner to the user
5. Submit the proof to the contract

Estimated proof generation time: 3-10 seconds per proof in browser (needs benchmarking).

---

## Open Questions

These need answers before or during Week 3:

1. **Which encryption scheme in Noir?** ElGamal is the standard for mental poker, but does Noir have efficient elliptic curve operations for it? Or should we use a Poseidon-based symmetric scheme with key exchange?

2. **Aztec from day one or Sepolia first?** Given gas estimates (5M+ per hand), it might make more sense to target Aztec testnet directly. But Aztec's developer tooling is less mature.

3. **How to handle the dealer button / blinds?** In heads-up, the dealer posts the small blind and acts first pre-flop, then last post-flop. This needs to alternate each hand. Should be simple state in the contract.

4. **Card encoding**: 52 cards as uint8 (0-51) with suit = value / 13 and rank = value % 13? Or 4 bits suit + 4 bits rank? The circuit and contract need to agree on encoding.

5. **How much of the hand evaluator can we offload?** On-chain evaluation of 7-choose-5 is expensive. Alternative: the winner submits a proof that their hand beats the opponent's hand. This moves computation to the client but saves gas.

---

## Research Links & References

- **ROYALE Protocol** - Aztec's mental poker design (search Aztec forums/blog)
- **Barnett & Smart 2003** - "Mental Poker Revisited" - foundational paper on ZK mental poker
- **Geometry Research mental poker** - Open-source ZK poker implementation to study
- **Noir docs** - https://noir-lang.org/docs
- **Nargo CLI reference** - check for current verifier generation commands
- **Foundry book** - https://book.getfoundry.sh/
- **Aztec testnet docs** - for potential L2 deployment

---

## Ideas & Future Work

### Post-MVP Features (Priority Order)

1. **Multi-player tables (3-6 players)** - requires N-party threshold decryption, side pot logic
2. **Multiple wager types** - hand type prediction, pot size over/under
3. **Hand history** - store completed hands on-chain or in a subgraph for review
4. **Mobile UI** - responsive design or native app
5. **Tournament mode** - multi-table tournaments with increasing blinds
6. **Chat** - in-game chat between players / spectators
7. **Reputation/stats** - player win rates, spectator wagering performance

### Performance Optimization Ideas

- **Recursive proofs** - batch multiple proof verifications into a single recursive proof to save gas
- **Aztec native deployment** - Noir proofs verify natively on Aztec, dramatically reducing costs
- **Circuit optimization** - reduce constraint count through careful Noir programming
- **Proof caching** - cache intermediate witness computations for faster subsequent proofs

### Alternative Protocol Ideas

- **Commit-reveal with hash chains** instead of full threshold encryption (simpler but weaker security model)
- **Trusted shuffler with slashing** - a designated shuffler posts a bond; if they cheat, they're slashed. Simpler protocol but introduces a trust assumption
- **Optimistic approach** - assume honest behavior, only generate ZK proofs if someone challenges (fraud proof model)

---

## Notes & Scratchpad

*Use this section for quick notes, meeting decisions, and brainstorming during development.*
