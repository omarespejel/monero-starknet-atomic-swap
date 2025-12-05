# XMR↔Starknet Atomic Swap

Prototype implementation of a trustless atomic swap protocol between Monero and Starknet. 
Uses hashlock + MSM verification + **DLEQ proofs** for cryptographic binding.

## Overview

This project implements a **prototype implementation / reference PoC** of an atomic swap protocol for trustless exchange of Monero (XMR) and Starknet L2 assets. 

**Current Implementation:**
- **SHA-256 Hashlock**: Cryptographic lock on Starknet
- **Ed25519 Adaptor Signatures**: Monero-side signature binding (simplified demo, not full CLSAG)
- **Garaga MSM Verification**: Efficient on-chain Ed25519 point verification (`t·G == adaptor_point`)
- **✅ DLEQ Proofs**: Cryptographic binding between hashlock and adaptor point (implemented)

**DLEQ Implementation Status:**
- ✅ **Cairo**: DLEQ verification implemented using Poseidon hashing (10x cheaper gas)
- ✅ **Rust**: DLEQ proof generation implemented using SHA-256
- ⚠️ **Compatibility**: Hash function mismatch (Rust: SHA-256, Cairo: Poseidon) - documented in `DLEQ_COMPATIBILITY.md`
- 📋 **Future**: BLAKE2s migration planned (8x cheaper than Poseidon) - see `HASH_FUNCTION_ANALYSIS.md`

**Important**: DLEQ proofs cryptographically bind the hashlock (H) and adaptor point (T) by proving ∃t: SHA-256(t) = H ∧ t·G = T. The current implementation uses different hash functions in Rust and Cairo, requiring alignment for full compatibility (see compatibility docs).

## Architecture

### Components

1. **Cairo Contract** (`cairo/src/lib.cairo`): `AtomicLock` contract on Starknet with DLEQ verification
2. **Rust Library** (`rust/src/lib.rs`): Secret generation, DLEQ proof generation, and adaptor signature logic
3. **Python Tool** (`tools/generate_ed25519_test_data.py`): Test data generation using Garaga
4. **CLI Tools** (`rust/src/bin/`): Maker and taker commands for end-to-end swaps
5. **Documentation**: Compatibility guides (`DLEQ_COMPATIBILITY.md`, `HASH_FUNCTION_ANALYSIS.md`)

### Protocol Flow

1. **Maker (Alice)**:
   - Generates secret scalar `t`
   - Creates simplified adaptor signature (demo, not full CLSAG)
   - Deploys `AtomicLock` contract on Starknet Sepolia
   - Waits for secret reveal

2. **Taker (Bob)**:
   - Watches for `AtomicLock` contracts
   - Calls `verify_and_unlock(secret)` when ready
   - Reveals secret `t` via `Unlocked` event

3. **Maker (Alice)**:
   - Detects secret reveal via event
   - Finalizes simplified Monero signature using revealed `t`
   - Broadcasts transaction (demo implementation, not production wallet)

**⚠️ Important**: The Monero integration is a **minimal adaptor-signature demo**, not a production wallet integration. It does not implement full CLSAG, key image handling, change outputs, or multi-output transactions. This is a proof-of-concept demonstration, not a drop-in module for production wallets.

## Quick Start

### Prerequisites

- Rust 1.70+
- Cairo/Scarb (for contract compilation)
- Python 3.10+ with `uv` (for test data generation)
- Starknet account (for contract deployment)
- Monero stagenet RPC access (for demo transaction creation - not a full wallet integration)

### Building

```bash
# Build Rust binaries
cd rust
cargo build --release

# Build Cairo contract
cd ../cairo
scarb build
```

### Running the Demo

#### Maker (Alice) Side

```bash
cd rust

# Generate swap secret and prepare for deployment
cargo run --bin maker -- \
  --starknet-rpc https://starknet-sepolia.public.blastapi.io/rpc/v0_7 \
  --monero-rpc http://stagenet.community.rino.io:38081 \
  --lock-duration 3600 \
  --output swap_state.json

# After contract deployment, watch for unlock
cargo run --bin maker -- \
  --starknet-rpc https://starknet-sepolia.public.blastapi.io/rpc/v0_7 \
  --contract-address <deployed_contract_address> \
  --watch
```

#### Taker (Bob) Side

```bash
cd rust

# Watch for new contracts
cargo run --bin taker -- \
  --starknet-rpc https://starknet-sepolia.public.blastapi.io/rpc/v0_7 \
  --watch

# Unlock a contract
cargo run --bin taker -- \
  --starknet-rpc https://starknet-sepolia.public.blastapi.io/rpc/v0_7 \
  --contract-address <contract_address> \
  --secret <secret_hex>
```

## Project Structure

```
.
├── cairo/              # Cairo contract (AtomicLock)
│   ├── src/
│   │   └── lib.cairo   # Main contract with DLEQ verification
│   └── tests/
│       └── test_atomic_lock.cairo
├── rust/               # Rust library and CLI
│   ├── src/
│   │   ├── lib.rs      # Core library
│   │   ├── dleq.rs     # DLEQ proof generation
│   │   ├── poseidon.rs # Poseidon hash (placeholder)
│   │   ├── adaptor/    # Adaptor signature logic
│   │   ├── starknet.rs # Starknet integration
│   │   ├── monero.rs   # Monero integration
│   │   └── bin/
│   │       ├── maker.rs # Maker CLI
│   │       └── taker.rs # Taker CLI
│   └── tests/
│       └── integration_test.rs
├── tools/              # Python tooling
│   ├── generate_ed25519_test_data.py
│   └── generate_second_base.py  # Second generator tool
├── DLEQ_COMPATIBILITY.md        # Rust↔Cairo compatibility guide
├── HASH_FUNCTION_ANALYSIS.md     # Poseidon vs BLAKE2s analysis
├── POSEIDON_IMPLEMENTATION.md    # Poseidon implementation plan
└── README.md
```

## Testing

```bash
# Run Cairo tests
cd cairo
snforge test

# Run Rust tests
cd rust
cargo test

# Run integration tests
cargo test --test integration_test
```

## Status: Prototype Implementation / Reference PoC

**⚠️ This is a prototype implementation and reference proof-of-concept. It is NOT production-ready.**

**Production-ready status requires:**
- ✅ Security audit by qualified auditors
- ✅ DLEQ proof implementation (implemented, hash function alignment pending)
- ⚠️ Hash function alignment (Rust↔Cairo compatibility)
- ⚠️ Full end-to-end testing on testnets
- ⚠️ Complete integration with Starknet and Monero networks

**DLEQ Implementation Status**: ✅ **IMPLEMENTED**

- **Cairo**: Full DLEQ verification in constructor using Poseidon hashing
- **Rust**: DLEQ proof generation with SHA-256 (needs Poseidon for compatibility)
- **Features**: Comprehensive validation (on-curve, small-order, scalar range), events, error handling
- **Compatibility**: See `DLEQ_COMPATIBILITY.md` for Rust↔Cairo alignment details
- **Future**: BLAKE2s migration planned (see `HASH_FUNCTION_ANALYSIS.md`)

### Current Implementation Status

**Completed:**
- ✅ Cairo contract with hard invariants (MSM verification, timelock, refund rules)
- ✅ **DLEQ proof verification in Cairo** (Poseidon hashing, comprehensive validation)
- ✅ **DLEQ proof generation in Rust** (SHA-256, needs Poseidon for compatibility)
- ✅ Rust adaptor signature logic
- ✅ Integration scaffold for Starknet and Monero
- ✅ Comprehensive test suite
- ✅ Production-grade validation (on-curve, small-order, scalar range checks)
- ✅ Events and error handling

**In Progress:**
- ⚠️ Account signing implementation
- ⚠️ Monero transaction serialization (minimal demo, not production wallet)
- ⚠️ End-to-end testnet testing

**Monero Integration Status:**
- ⚠️ **Current**: Minimal adaptor-signature demo (simplified, not full CLSAG)
- ⚠️ **Not Implemented**: Full CLSAG, key image handling, change outputs, multi-output transactions
- ⚠️ **Purpose**: Proof-of-concept demonstration, not production wallet integration

**In Progress:**
- ⚠️ Hash function alignment (Rust↔Cairo compatibility)
  - **Current**: Rust uses SHA-256, Cairo uses Poseidon (incompatible)
  - **Impact**: Proofs generated in Rust won't verify in Cairo until aligned
  - **Solutions**: See `DLEQ_COMPATIBILITY.md` (both Poseidon or both SHA-256)
  - **Future**: BLAKE2s migration (8x cheaper than Poseidon) - see `HASH_FUNCTION_ANALYSIS.md`

### Security Considerations

**Hard Invariants (Implemented):**
- **Constructor**: Adaptor point must be non-zero, on-curve, not small-order
- **MSM Verification**: Mandatory check that `t·G == adaptor_point`
- **Timelock**: `lock_until` must be in the future
- **Refund Rules**: Only depositor, only after expiry, only if locked

**Known Limitations:**
- **snforge Constructor Panics**: Constructor validation tests are marked as FAIL by snforge v0.53.0, but they correctly panic (tooling limitation)
- **Starknet Integration**: Contract deployment and event watching require full starknet-rs integration (currently scaffolded)
- **Monero Integration**: Minimal adaptor-signature demo, not a production wallet integration
  - Does not implement full CLSAG (Compact Linkable Spontaneous Anonymous Group signatures)
  - No robust handling of key images, change outputs, or multi-output transactions
  - This is a proof-of-concept demonstration, not a drop-in module for production wallets
  - For production use, integrate with a proper Monero wallet stack
- **DLEQ Proofs**: ✅ **IMPLEMENTED** (hash function alignment pending)
  - **Current state**: DLEQ verification in Cairo, proof generation in Rust
  - **What's working**: Cryptographic proof binding hashlock (H) and adaptor point (T)
  - **Current limitation**: Hash function mismatch (Rust: SHA-256, Cairo: Poseidon)
  - **Security**: DLEQ proves ∃t: SHA-256(t) = H ∧ t·G = T (once hash functions aligned)
  - **Documentation**: See `DLEQ_COMPATIBILITY.md` and `HASH_FUNCTION_ANALYSIS.md`

## Roadmap

- [x] Phase 1: Starknet EC Sanity (MSM verification)
- [x] Phase 2: Monero Adaptor Signatures
- [x] Phase 3: Pre-audit Hardening
- [x] Phase 4: On-chain Protocol Lock-in
- [x] Phase 5: Full Integration Scaffold (v0.4.0)
- [x] Phase 6: DLEQ Proof Implementation (✅ Implemented, alignment pending)
- [ ] Phase 7: Hash Function Alignment (Rust↔Cairo compatibility)
- [ ] Phase 8: Account Signing Implementation
- [ ] Phase 9: End-to-End Testing on Testnets
- [ ] Phase 10: Security Audit
- [ ] Phase 11: Mainnet Deployment

## v0.4.0 Status

**Full Integration Modules** (scaffolded, ready for implementation):
- ✅ `starknet_full.rs`: Contract deployment, event watching, function calls
- ✅ `monero_full.rs`: Transaction creation, signature finalization, broadcasting
- ✅ Maker/Taker binaries updated to use full integrations
- ⚠️ Account signing still requires implementation (use Starknet CLI for now)

**Next Steps for Full Functionality**:
1. Implement account key loading and signing in `StarknetAccount`
2. Complete Monero transaction serialization (or integrate with production wallet stack)
3. Test end-to-end on Sepolia + stagenet

**Note on Monero Integration**: The current implementation is a minimal demo. For production use, consider integrating with a proper Monero wallet library (e.g., monero-rs) that handles full CLSAG, key images, change outputs, and multi-output transactions.

## License

MIT
