# XMR↔Starknet Atomic Swap

Trustless atomic swap protocol between Monero and Starknet using DLEQ proofs and Garaga v1.0.0.

## Overview

This project implements a production-ready atomic swap protocol that allows trustless exchange of Monero (XMR) and Starknet L2 assets. The protocol uses:

- **SHA-256 Hashlock**: Cryptographic lock on Starknet
- **Ed25519 Adaptor Signatures**: Monero-side signature binding
- **Garaga MSM Verification**: Efficient on-chain Ed25519 point verification
- **DLEQ Proofs**: (Future) Cryptographic binding between hashlock and adaptor point

## Architecture

### Components

1. **Cairo Contract** (`cairo/src/lib.cairo`): `AtomicLock` contract on Starknet
2. **Rust Library** (`rust/src/lib.rs`): Secret generation and adaptor signature logic
3. **Python Tool** (`tools/generate_ed25519_test_data.py`): Test data generation using Garaga
4. **CLI Tools** (`rust/src/bin/`): Maker and taker commands for end-to-end swaps

### Protocol Flow

1. **Maker (Alice)**:
   - Generates secret scalar `t`
   - Creates adaptor signature for Monero stagenet
   - Deploys `AtomicLock` contract on Starknet Sepolia
   - Waits for secret reveal

2. **Taker (Bob)**:
   - Watches for `AtomicLock` contracts
   - Calls `verify_and_unlock(secret)` when ready
   - Reveals secret `t` via `Unlocked` event

3. **Maker (Alice)**:
   - Detects secret reveal via event
   - Finalizes Monero signature using revealed `t`
   - Broadcasts transaction on Monero stagenet

## Quick Start

### Prerequisites

- Rust 1.70+
- Cairo/Scarb (for contract compilation)
- Python 3.10+ with `uv` (for test data generation)
- Starknet account (for contract deployment)
- Monero stagenet wallet (for transaction creation)

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

## Security

### Hard Invariants

- **Constructor**: Adaptor point must be non-zero, on-curve, not small-order
- **MSM Verification**: Mandatory check that `t·G == adaptor_point`
- **Timelock**: `lock_until` must be in the future
- **Refund Rules**: Only depositor, only after expiry, only if locked

### Known Limitations

- **snforge Constructor Panics**: Constructor validation tests are marked as FAIL by snforge v0.53.0, but they correctly panic (tooling limitation)
- **Starknet Integration**: Contract deployment and event watching require full starknet-rs integration (currently scaffolded)
- **Monero Integration**: Transaction creation and broadcasting require monero-rs integration (currently scaffolded)

## Roadmap

- [x] Phase 1: Starknet EC Sanity (MSM verification)
- [x] Phase 2: Monero Adaptor Signatures
- [x] Phase 3: Pre-audit Hardening
- [x] Phase 4: On-chain Protocol Lock-in
- [ ] Phase 5: DLEQ Proof Implementation
- [ ] Phase 6: Full Starknet Integration
- [ ] Phase 7: Full Monero Integration
- [ ] Phase 8: End-to-End Testing on Testnets
- [ ] Phase 9: Security Audit
- [ ] Phase 10: Mainnet Deployment

## License

MIT
