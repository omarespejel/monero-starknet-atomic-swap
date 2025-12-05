# XMR↔Starknet Atomic Swap

Prototype implementation of a trustless atomic swap protocol between Monero and Starknet. 
Currently uses hashlock + MSM verification (DLEQ proofs planned for future version).

## Overview

This project implements a **prototype implementation / reference PoC** of an atomic swap protocol for trustless exchange of Monero (XMR) and Starknet L2 assets. 

**Current Implementation:**
- **SHA-256 Hashlock**: Cryptographic lock on Starknet
- **Ed25519 Adaptor Signatures**: Monero-side signature binding (simplified demo, not full CLSAG)
- **Garaga MSM Verification**: Efficient on-chain Ed25519 point verification (`t·G == adaptor_point`)

**Important**: The current version does **NOT** bind the hashlock and adaptor point via a cryptographic proof. DLEQ (Discrete Logarithm Equality) proofs are planned for a future version but are not yet implemented. The protocol currently relies on hashlock + MSM verification, which provides strong security guarantees but does not cryptographically prove the relationship between the hashlock and adaptor point.

## Architecture

### Components

1. **Cairo Contract** (`cairo/src/lib.cairo`): `AtomicLock` contract on Starknet
2. **Rust Library** (`rust/src/lib.rs`): Secret generation and adaptor signature logic
3. **Python Tool** (`tools/generate_ed25519_test_data.py`): Test data generation using Garaga
4. **CLI Tools** (`rust/src/bin/`): Maker and taker commands for end-to-end swaps

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
│   │   └── lib.cairo   # Main contract
│   └── tests/
│       └── test_atomic_lock.cairo
├── rust/               # Rust library and CLI
│   ├── src/
│   │   ├── lib.rs      # Core library
│   │   ├── adaptor/    # Adaptor signature logic
│   │   ├── starknet.rs # Starknet integration
│   │   ├── monero.rs   # Monero integration
│   │   └── bin/
│   │       ├── maker.rs # Maker CLI
│   │       └── taker.rs # Taker CLI
│   └── tests/
│       └── integration_test.rs
├── tools/              # Python tooling
│   └── generate_ed25519_test_data.py
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
- ⚠️ DLEQ proof implementation (planned but not yet implemented)
- ⚠️ Full end-to-end testing on testnets
- ⚠️ Complete integration with Starknet and Monero networks

**Important Note on DLEQ**: DLEQ proofs are advertised as part of the protocol design but are **not yet implemented**. The current version does not cryptographically bind the hashlock and adaptor point via a proof. This is explicitly deferred to a post-audit phase. The protocol currently provides strong security through hashlock + MSM verification, but lacks the cryptographic proof that the same secret `t` generates both the hashlock and adaptor point.

### Current Implementation Status

**Completed:**
- ✅ Cairo contract with hard invariants (MSM verification, timelock, refund rules)
- ✅ Rust adaptor signature logic
- ✅ Integration scaffold for Starknet and Monero
- ✅ Comprehensive test suite

**In Progress:**
- ⚠️ Account signing implementation
- ⚠️ Monero transaction serialization (minimal demo, not production wallet)
- ⚠️ End-to-end testnet testing

**Monero Integration Status:**
- ⚠️ **Current**: Minimal adaptor-signature demo (simplified, not full CLSAG)
- ⚠️ **Not Implemented**: Full CLSAG, key image handling, change outputs, multi-output transactions
- ⚠️ **Purpose**: Proof-of-concept demonstration, not production wallet integration

**Deferred:**
- ⚠️ DLEQ proof implementation (explicitly deferred to post-audit phase)
  - **Current limitation**: The hashlock (H) and adaptor point (T) are not cryptographically bound via a proof
  - **Impact**: Protocol relies on hashlock + MSM verification, which is strong but does not prove ∃t: SHA-256(t) = H ∧ t·G = T
  - **Future**: DLEQ proofs will provide cryptographic binding between H and T

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
- **DLEQ Proofs**: Not yet implemented (deferred to post-audit phase)
  - **Current state**: DLEQ is mentioned in protocol design but not implemented
  - **What's missing**: No cryptographic proof binding hashlock (H) and adaptor point (T)
  - **Current security**: Relies on hashlock + MSM verification (strong, but not cryptographically bound)
  - **Future**: DLEQ will prove ∃t: SHA-256(t) = H ∧ t·G = T

## Roadmap

- [x] Phase 1: Starknet EC Sanity (MSM verification)
- [x] Phase 2: Monero Adaptor Signatures
- [x] Phase 3: Pre-audit Hardening
- [x] Phase 4: On-chain Protocol Lock-in
- [x] Phase 5: Full Integration Scaffold (v0.4.0)
- [ ] Phase 6: Account Signing Implementation
- [ ] Phase 7: DLEQ Proof Implementation
- [ ] Phase 8: End-to-End Testing on Testnets
- [ ] Phase 9: Security Audit
- [ ] Phase 10: Mainnet Deployment

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
