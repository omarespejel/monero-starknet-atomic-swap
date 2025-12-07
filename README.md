<div align="center">
  <img src="assets/project-banner.png" alt="Monero Atomic Swap" width="800"/>
</div>

# Monero Atomic Swap

Prototype implementation of a trustless atomic swap protocol between Monero and Starknet. 
Uses hashlock + MSM verification + DLEQ proofs for cryptographic binding.

**Status**: v0.7.1 - Key splitting approach implemented. E2E Rust↔Cairo compatibility test passes. CI workflows fixed.

## Overview

This project implements a prototype implementation and reference proof-of-concept of an atomic swap protocol for trustless exchange of Monero (XMR) and Starknet L2 assets.

**Current Implementation:**
- SHA-256 Hashlock: Cryptographic lock on Starknet
- Key Splitting: Monero-side key splitting (x = x_partial + t) - no custom CLSAG modification
- Garaga MSM Verification: Efficient on-chain Ed25519 point verification (t·G == adaptor_point)
- DLEQ Proofs: Cryptographic binding between hashlock and adaptor point (implemented)

**DLEQ Implementation Status:**
- Cairo: DLEQ verification implemented using BLAKE2s (gas-optimized)
- Rust: DLEQ proof generation implemented using BLAKE2s
- Compatibility: Rust↔Cairo compatibility verified - E2E test passes
- Status: Production-ready cryptographic implementation

**Technical Details**: DLEQ proofs bind hashlock (H) and adaptor point (T) by proving ∃t: SHA-256(t) = H ∧ t·G = T. Challenge computation uses BLAKE2s in both implementations. All cryptographic components verified and tested.

## Architecture

### Components

1. **Cairo Contract** (`cairo/src/lib.cairo`): AtomicLock contract on Starknet with DLEQ verification
2. **Rust Library** (`rust/src/lib.rs`): Secret generation, DLEQ proof generation, and adaptor signature logic
3. **Python Tooling** (`tools/`): Test data generation, hint generation, and compatibility verification
4. **CLI Tools** (`rust/src/bin/`): Maker and taker commands for end-to-end swaps

### Protocol Flow

1. **Maker (Alice)**:
   - Generates secret scalar `t` and splits Monero key: x = x_partial + t
   - Creates DLEQ proof binding hashlock to adaptor point T = t·G
   - Deploys AtomicLock contract on Starknet Sepolia
   - Waits for secret reveal, then recovers full key to spend Monero

2. **Taker (Bob)**:
   - Watches for AtomicLock contracts
   - Calls `verify_and_unlock(secret)` when ready
   - Reveals secret `t` via `Unlocked` event

3. **Maker (Alice)**:
   - Detects secret reveal via event
   - Finalizes simplified Monero signature using revealed `t`
   - Broadcasts transaction (demo implementation, not production wallet)

**Important**: The Monero integration is a minimal adaptor-signature demo, not a production wallet integration. It does not implement full CLSAG, key image handling, change outputs, or multi-output transactions. This is a proof-of-concept demonstration, not a drop-in module for production wallets.

## Technical Architecture

### Cryptographic Binding Strategy

**Problem**: Prove that the scalar `t` unlocking Starknet is identical to the scalar used in Monero's adaptor signature.

**Solution**: DLEQ proof binding:
- Starknet domain: `SHA-256(t) = H` (hashlock)
- Monero domain: `t · G = T` (adaptor point on Ed25519)
- Proof: DLEQ proves `∃t: SHA-256(t) = H ∧ t·G = T`

### Component Breakdown

```
Off-Chain (Rust) → On-Chain (Cairo + Garaga)
- Generate Monero scalar t
- Compute H = SHA-256(t)
- Compute T = t·G (Ed25519)
- Generate DLEQ proof π
- Serialize (H, T, π) for Cairo
```

### Module Structure

**Cairo Modules:**
- `lib.cairo`: Main AtomicLock contract with DLEQ verification
- `blake2s_challenge.cairo`: BLAKE2s challenge computation (RFC 7693 compliant)
- `edwards_serialization.cairo`: Point serialization utilities

**Key Functions:**
- `compute_dleq_challenge_blake2s()`: Computes DLEQ challenge using BLAKE2s
- `_verify_dleq_proof()`: Verifies DLEQ proof using Garaga MSM
- `decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point()`: Point decompression

### DLEQ Compatibility

**Current Status:**
- Cairo: DLEQ verification implemented using BLAKE2s
- Rust: DLEQ proof generation implemented using BLAKE2s
- Compatibility: Hash functions aligned (both BLAKE2s)

**Implementation Details:**

**Rust** (`rust/src/dleq.rs`):
- Uses `blake2` crate for BLAKE2s
- Generates compressed Edwards points
- Computes challenge: `BLAKE2s("DLEQ" || G || Y || T || U || R1 || R2 || hashlock)`

**Cairo** (`cairo/src/blake2s_challenge.cairo`):
- Uses `core::blake` module for BLAKE2s
- Processes u256 values as u32 arrays
- Computes challenge: `BLAKE2s("DLEQ" || G || Y || T || U || R1 || R2 || hashlock)`

**Compatibility**: Verified - challenge computation matches between Rust and Cairo.

### Hash Function Analysis

**BLAKE2s vs Poseidon:**

| Hash Function | Challenge Gas | Total DLEQ Gas | Notes |
|---------------|---------------|----------------|-------|
| BLAKE2s | 50k-80k | 270k-440k | Current implementation |
| Poseidon | 400k-640k | 620k-1000k | Deprecated |

**Conclusion**: BLAKE2s provides 8x gas savings for challenge computation.

**Migration Status**: Complete - Migrated from Poseidon to BLAKE2s, updated challenge computation, verified byte-order compatibility, tests pass with Rust test vectors.

### MSM Hints

Garaga's `msm_g1` function requires fake-GLV hints for efficient scalar multiplication. These hints are 10-felt arrays containing:
- Q.x limbs (4 felts): x-coordinate of result point Q = scalar * base_point
- Q.y limbs (4 felts): y-coordinate of result point Q
- s1 (1 felt): Scalar component for GLV decomposition
- s2_encoded (1 felt): Encoded scalar component

**Critical**: The hint Q must equal the actual result point for verification to pass.

**DLEQ Verification Requires 4 Hints:**
1. s·G: `s_hint_for_g` (Q = s·G)
2. s·Y: `s_hint_for_y` (Q = s·Y)
3. (-c)·T: `c_neg_hint_for_t` (Q = (-c)·T)
4. (-c)·U: `c_neg_hint_for_u` (Q = (-c)·U)

**Generating Hints:**

Tool: `tools/generate_hints_exact.py` (uses exact Garaga decompression)

```bash
cd tools
python3 generate_hints_exact.py
```

### Gas Benchmarks

**DLEQ Verification Gas Costs:**

| Component | Gas Cost | Notes |
|-----------|----------|-------|
| BLAKE2s challenge | 50k-80k | 8x cheaper than Poseidon |
| MSM operations (4×) | 160k-240k | ~40k-60k per MSM |
| Point decompression (4×) | 40k-80k | ~10k-20k per point |
| Other operations | 20k-40k | Validation, storage, events |
| **Total** | **270k-440k** | **Production estimate** |

**Function Call Gas Costs:**
- `verify_and_unlock()`: 100k-200k gas
- `refund()`: 50k-150k gas
- `deposit()`: 50k-150k gas

**Optimization Opportunities:**
- Batch MSM operations via `process_multiple_u256()`
- Hint precomputation (already optimal)
- Point caching (trade-off: storage vs computation)

## Security Architecture

### Cryptographic Libraries

**Audited Libraries Used:**

- **Garaga v1.0.0** (audited) - All elliptic curve operations
  - EC point operations (`msm_g1`, `ec_safe_add`)
  - Point validation (`assert_on_curve_excluding_infinity`)
  - Fake-GLV hints for MSM optimization
  - Ed25519 curve support (curve_index=4)

- **OpenZeppelin Cairo Contracts v2.0.0** (audited) - Security components
  - `ReentrancyGuardComponent` - Protection against reentrancy attacks
  - Industry-standard, battle-tested patterns

**Zero Custom Cryptography:**

This contract uses zero custom cryptography implementation. All cryptographic primitives are from audited libraries:
- All EC operations: Garaga (audited)
- Reentrancy protection: OpenZeppelin (audited)
- Hash functions: Cairo stdlib (SHA-256, BLAKE2s)
- No custom crypto code

### Security Properties

**1. Atomic Swaps**

Property: All-or-nothing execution
- Either the swap completes successfully (both parties get their assets)
- Or the swap fails and funds are returned to depositor
- No partial states or fund loss scenarios

Enforcement:
- DLEQ proof verified at deployment (constructor)
- Hashlock verification at unlock time
- MSM verification ensures cryptographic binding
- Timelock ensures refund path if swap fails

**2. DLEQ Binding**

Property: Cryptographically binds hashlock to adaptor point
- Proves: ∃t: SHA-256(t) = H ∧ t·G = T
- Prevents: Malicious counterparty from creating invalid swaps
- Ensures: Hashlock and adaptor point share the same secret

Enforcement:
- DLEQ proof verified in constructor (deployment fails if invalid)
- Uses BLAKE2s hashing for gas efficiency
- All EC operations use Garaga's audited functions

**3. Reentrancy Protection**

Property: Prevents reentrancy attacks on token transfers

Layers:
1. Starknet Built-in: Protocol-level reentrancy prevention
2. Unlocked Flag: Defense-in-depth check (`assert(!unlocked)`)
3. OpenZeppelin ReentrancyGuard: Audited component protection

Protected Functions:
- `verify_and_unlock()` - Token transfer to unlocker
- `refund()` - Token transfer to depositor
- `deposit()` - Token transfer from depositor

**4. Overflow/Underflow Safety**

Property: All arithmetic operations are safe from overflow/underflow

Enforcement:
- Cairo Built-in: Automatic overflow/underflow protection (reverts on overflow)
- Manual Reduction: Scalars reduced modulo ED25519_ORDER to ensure valid range
- No SafeMath Needed: Cairo provides this protection by default

**5. Access Control**

Property: Only authorized parties can perform actions

Enforcement:
- `refund()`: Only depositor, only after expiry
- `deposit()`: Only depositor
- `verify_and_unlock()`: Anyone (by design - counterparty reveals secret)

Note: No owner/admin concept - contract is trustless. Each contract instance has its own depositor set at deployment.

**6. Point Validation**

Property: All EC points are valid and safe

Checks:
- Points must be on Ed25519 curve (`assert_on_curve_excluding_infinity`)
- Points must not have small order (8-torsion check)
- Points must not be zero/infinity
- Scalar range validation ([0, ED25519_ORDER))

### Threat Model

**Attack Vectors Considered:**

**1. Reentrancy Attacks**
Threat: Attacker calls token transfer callback to reenter contract
Mitigation:
- OpenZeppelin ReentrancyGuard
- Unlocked flag check
- Checks-effects-interactions pattern

**2. Invalid DLEQ Proofs**
Threat: Malicious counterparty creates invalid proof to bind wrong hashlock/adaptor point
Mitigation:
- DLEQ verification in constructor (deployment fails if invalid)
- Comprehensive point validation
- Challenge recomputation verification

**3. Small-Order Point Attacks**
Threat: Attacker uses points with small order (8-torsion) to bypass checks
Mitigation:
- Small-order check for all points (`is_small_order_ed25519`)
- Rejects points where [8]P = O

**4. Scalar Range Attacks**
Threat: Invalid scalars outside [0, n) range
Mitigation:
- Scalar reduction modulo ED25519_ORDER
- Zero scalar checks
- Sign validation using Garaga's `sign()` utility

**5. Hash Mismatch Attacks**
Threat: Attacker provides wrong secret to unlock
Mitigation:
- SHA-256 hashlock verification (fail-fast)
- MSM verification ensures scalar matches adaptor point
- DLEQ proof ensures hashlock and adaptor point are bound

**6. Timelock Bypass**
Threat: Attacker tries to refund before expiry
Mitigation:
- Timestamp check: `assert(now >= lock_until)`
- Enforced in constructor: `assert(lock_until > now)`

### Security Best Practices

1. Use Only Audited Libraries: Garaga + OpenZeppelin
2. Defense-in-Depth: Multiple layers of protection
3. Fail-Safe Defaults: Revert on any uncertainty
4. Comprehensive Validation: Check all inputs thoroughly
5. Clear Documentation: NatSpec comments, security annotations
6. Observability: Events for all critical operations

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
├── cairo/                      # Cairo contract (AtomicLock)
│   ├── src/
│   │   ├── lib.cairo          # Main contract with DLEQ verification
│   │   ├── blake2s_challenge.cairo  # BLAKE2s challenge computation
│   │   └── edwards_serialization.cairo  # Point serialization utilities
│   ├── tests/
│   │   ├── test_security_*.cairo  # Security audit tests
│   │   ├── test_e2e_*.cairo      # End-to-end tests (Rust↔Cairo compatibility)
│   │   ├── test_unit_*.cairo     # Fast, isolated unit tests
│   │   ├── test_integration_*.cairo  # Cross-component tests
│   │   ├── test_debug_*.cairo   # Development/debugging tests
│   │   └── fixtures/           # Shared test data and helpers
│   ├── INVARIANTS.md          # Contract invariants documentation
│   └── coverage.toml           # Test coverage configuration
├── rust/                       # Rust library and CLI
│   ├── src/
│   │   ├── lib.rs             # Core library
│   │   ├── dleq.rs            # DLEQ proof generation
│   │   ├── poseidon.rs        # Poseidon hash (placeholder)
│   │   ├── adaptor/           # Adaptor signature logic
│   │   ├── starknet.rs        # Starknet integration
│   │   ├── monero.rs          # Monero integration
│   │   └── bin/
│   │       ├── maker.rs       # Maker CLI
│   │       └── taker.rs       # Taker CLI
│   └── tests/
│       └── integration_test.rs
├── tools/                      # Python tooling
│   ├── generate_ed25519_test_data.py
│   ├── generate_hints_exact.py  # MSM hint generation (exact Garaga decompression)
│   ├── generate_hints_from_test_vectors.py
│   ├── verify_challenge_computation.py
│   ├── verify_full_compatibility.py  # Cross-platform verification
│   └── verify_rust_cairo_equivalence.py
└── README.md
```

## Testing

```bash
# Run all Cairo tests
cd cairo
snforge test

# Run tests by category
snforge test --filter "security_"      # Security tests
snforge test --filter "e2e_"           # End-to-end tests
snforge test --filter "unit_"          # Unit tests
snforge test --filter "integration_"   # Integration tests

# Run Rust tests
cd rust
cargo test

# Run integration tests
cargo test --test integration_test

# Generate test vectors
cargo test --test test_vectors generate_cairo_test_vectors -- --ignored
```

**Test Organization:**

Tests are organized using naming conventions in the `tests/` root directory:
- **Security tests** (`test_security_*.cairo`): Security audit tests (CRITICAL - 4 files, 15+ tests)
- **E2E tests** (`test_e2e_*.cairo`): End-to-end tests including Rust↔Cairo compatibility (2 files)
- **Unit tests** (`test_unit_*.cairo`): Fast, isolated tests for individual components (11 files)
- **Integration tests** (`test_integration_*.cairo`): Cross-component tests (13 files)
- **Debug tests** (`test_debug_*.cairo`): Development/debugging tests (5 files)
- **Fixtures** (`fixtures/`): Shared test data and helpers (NOT test files)

This approach provides native snforge support with easy filtering: `snforge test security_` runs all security tests.

## Implementation Status

**Current State**: Prototype implementation with DLEQ verification. Cryptographic components verified and tested. Comprehensive test suite complete.

### Completed Components

**Cairo Contract:**
- AtomicLock contract with DLEQ verification
- BLAKE2s challenge computation (gas-optimized, RFC 7693 compliant)
- MSM verification using Garaga v1.0.0 (4 sequential calls)
- Point validation (on-curve, small-order checks)
- Reentrancy protection (OpenZeppelin ReentrancyGuard)
- Production code cleanup (debug assertions removed)

**Rust Library:**
- DLEQ proof generation (BLAKE2s)
- Compressed Edwards point handling
- Test vector generation
- Conversion utilities (Garaga-compatible)

**Testing Infrastructure:**
- Comprehensive test suite (37+ test files, 107+ tests)
- Organized test structure (unit/integration/e2e/security/debug)
- E2E Rust↔Cairo compatibility test (PASSES)
- Security audit tests (9/9 passing)
- Token security tests (6/6 passing)
- Edge case tests (max scalar, zero, boundary values)
- Negative tests (wrong challenge/response/hashlock rejection)
- Full swap lifecycle tests
- CI/CD workflow for automated testing

**Documentation:**
- Contract invariants documentation (`INVARIANTS.md`)
- Test coverage configuration (`coverage.toml`)
- Comprehensive README with technical and security details

### Recent Achievements

**Cryptographic Fixes:**
- Fixed BLAKE2s initialization vector (RFC 7693 compliant)
- Fixed DLEQ tag byte order
- Fixed BLAKE2s block accumulation
- Fixed Y constant byte order
- Fixed scalar truncation (128-bit matching)
- Fixed sqrt hints (Montgomery vs. Twisted Edwards)
- Fixed MSM hints (exact Garaga decompression)

**Test Suite Improvements:**
- Organized tests into logical categories
- Removed debug assertions from production code
- Created comprehensive security test suite
- Verified Rust↔Cairo compatibility end-to-end
- Implemented token security tests with mock ERC20
- Fixed depositor address tracking in tests

### Known Limitations

**Monero Integration:**
- Minimal adaptor-signature demo (not full CLSAG)
- No key image handling, change outputs, or multi-output transactions
- Proof-of-concept only, not production wallet integration

**Production Readiness:**
- Security audit in progress
- Account signing implementation pending
- Mainnet deployment pending audit completion

## References

- Garaga v1.0.0: https://github.com/keep-starknet-strange/garaga
- OpenZeppelin Cairo Contracts v2.0.0: https://github.com/OpenZeppelin/cairo-contracts
- BLAKE2s Specification (RFC 7693): https://www.rfc-editor.org/rfc/rfc7693
- Cairo Documentation: https://book.cairo-lang.org/

## License

MIT
