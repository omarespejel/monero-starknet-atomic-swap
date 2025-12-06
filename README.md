<div align="center">
  <img src="assets/project-banner.png" alt="Monero Atomic Swap" width="800"/>
</div>

# Monero Atomic Swap

Prototype implementation of a trustless atomic swap protocol between Monero and Starknet. 
Uses hashlock + MSM verification + **DLEQ proofs** for cryptographic binding.

## Overview

This project implements a **prototype implementation / reference PoC** of an atomic swap protocol for trustless exchange of Monero (XMR) and Starknet L2 assets. 

**Current Implementation:**
- **SHA-256 Hashlock**: Cryptographic lock on Starknet
- **Ed25519 Adaptor Signatures**: Monero-side signature binding (simplified demo, not full CLSAG)
- **Garaga MSM Verification**: Efficient on-chain Ed25519 point verification (`t·G == adaptor_point`)
- **DLEQ Proofs**: Cryptographic binding between hashlock and adaptor point (implemented)

**DLEQ Implementation Status:**
- **Cairo**: DLEQ verification implemented using BLAKE2s (gas-optimized)
- **Rust**: DLEQ proof generation implemented using BLAKE2s
- **Compatibility**: Hash functions aligned (both BLAKE2s)
- **Current Blocker**: Compressed Edwards point decompression failing in tests (investigating)

**Technical Details**: DLEQ proofs bind hashlock (H) and adaptor point (T) by proving ∃t: SHA-256(t) = H ∧ t·G = T. Challenge computation uses BLAKE2s in both implementations. See `TECHNICAL.md` for implementation details.

## Architecture

### Components

1. **Cairo Contract** (`cairo/src/lib.cairo`): `AtomicLock` contract on Starknet with DLEQ verification
2. **Rust Library** (`rust/src/lib.rs`): Secret generation, DLEQ proof generation, and adaptor signature logic
3. **Python Tool** (`tools/generate_ed25519_test_data.py`): Test data generation using Garaga
4. **CLI Tools** (`rust/src/bin/`): Maker and taker commands for end-to-end swaps
5. **Documentation**: Technical documentation (`TECHNICAL.md`, `AUDIT.md`, `SECURITY.md`)

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

**Important**: The Monero integration is a **minimal adaptor-signature demo**, not a production wallet integration. It does not implement full CLSAG, key image handling, change outputs, or multi-output transactions. This is a proof-of-concept demonstration, not a drop-in module for production wallets.

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
│   ├── generate_hints_from_test_vectors.py
│   ├── garaga_conversion.py
│   └── verify_rust_cairo_equivalence.py
├── AUDIT.md            # Audit documentation and findings
├── TECHNICAL.md        # Technical implementation details
├── SECURITY.md         # Security architecture
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

## Implementation Status

**Current State**: Prototype implementation with DLEQ verification. Not production-ready.

### Completed Components

**Cairo Contract:**
- AtomicLock contract with DLEQ verification
- BLAKE2s challenge computation (gas-optimized)
- MSM verification using Garaga v1.0.0
- Point validation (on-curve, small-order checks)
- Reentrancy protection (OpenZeppelin)

**Rust Library:**
- DLEQ proof generation (BLAKE2s)
- Compressed Edwards point handling
- Test vector generation
- Conversion utilities (Garaga-compatible)

**Testing Infrastructure:**
- Unit tests for DLEQ verification
- Byte-order verification tests
- Challenge computation tests
- CI/CD workflow for automated testing

### Current Blockers

**Compressed Point Decompression:**
- All Edwards points fail decompression in Cairo tests
- Hex→u256 conversion verified correct (matches Garaga pattern)
- Issue likely in sqrt hints or decompression function usage
- Blocks end-to-end test execution

**End-to-End Testing:**
- Test infrastructure created but blocked by decompression issue
- Rust↔Cairo compatibility verified for challenge computation
- Full DLEQ verification pending decompression fix

### Known Limitations

**Monero Integration:**
- Minimal adaptor-signature demo (not full CLSAG)
- No key image handling, change outputs, or multi-output transactions
- Proof-of-concept only, not production wallet integration

**Production Readiness:**
- Security audit required
- End-to-end testing incomplete
- Account signing implementation pending

### Security Architecture

**Implemented Security Measures:**
- Point validation (on-curve, small-order checks)
- Scalar range validation (mod Ed25519 order)
- Reentrancy protection (OpenZeppelin ReentrancyGuard)
- Timelock enforcement
- Access control (depositor-only refund)

**Audited Components:**
- Garaga v1.0.0 (elliptic curve operations)
- OpenZeppelin v2.0.0 (security primitives)
- Cairo stdlib (BLAKE2s, SHA-256)

**Security Documentation:**
- See `SECURITY.md` for threat model and security properties
- See `AUDIT.md` for audit findings and verification status

## Technical Documentation

- **`TECHNICAL.md`**: Architecture, module structure, DLEQ implementation, gas benchmarks
- **`AUDIT.md`**: Audit findings, byte-order verification, critical issues
- **`SECURITY.md`**: Security architecture, threat model, security properties

## Development Status

**Completed:**
- DLEQ proof implementation (Rust + Cairo, BLAKE2s)
- Byte-order verification (confirmed correct)
- Test infrastructure (unit tests, integration tests)
- CI/CD workflow

**In Progress:**
- Compressed point decompression fix (blocking end-to-end tests)
- End-to-end test execution

**Pending:**
- Security audit
- Account signing implementation
- Production deployment

## License

MIT
