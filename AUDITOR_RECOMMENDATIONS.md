# Auditor Recommendations - Project Organization & Bug Fixes

## Executive Summary

The layered testing strategy successfully identified **2 critical cryptographic bugs** before integration testing. The current project structure is acceptable for prototyping but needs reorganization for production deployment and proper security audits.

## Critical Bugs Found (P0 - Fix Immediately)

### Bug 1: Ring Closure Computation (`compute_c1()`)

**Severity**: CRITICAL  
**Location**: `rust/src/clsag/standard.rs::compute_c1()`  
**Tests Failing**: `test_standard_clsag_sign_verify`, `test_standard_clsag_ring_sizes`

**Root Cause**: Off-by-one or wrong index in ring iteration

**Reference Formula** (from CLSAG paper MRL-0011):
```
c_{i+1} = H_s(m || ring || L_i || R_i)

where:
  L_i = s_i·G + c_i·P_i
  R_i = s_i·Hp(P_i) + c_i·I
```

**Common Bugs to Check**:
- Wrong index wraparound (`(i + 1) % n` vs `i % n`)
- Missing key image `I` in `R_i` computation
- Wrong aggregation coefficient `μ_P` application

### Bug 2: Adaptor Finalization Formula

**Severity**: CRITICAL  
**Location**: `rust/src/clsag/adaptor.rs::finalize()`  
**Tests Failing**: `test_adaptor_finalization_produces_valid_sig`, `test_same_scalar_for_dleq_and_clsag`, `test_full_atomic_swap_flow`

**Root Cause**: Sign error or missing term in `s_π - c_π · μ_P · t`

**Reference Formula**:
```
s'_π = r_π - c_π·(x_π + μ_P·z)           # Partial (without t)
s_π  = r_π - c_π·(x_π + μ_P·z + μ_P·t)  # Finalized

Therefore:
s_π = s'_π - c_π·μ_P·t
```

**Checks Required**:
- Is `μ_P` computed correctly?
- Is the sign correct?
- Is `t` being reduced mod `l` (curve order)?

## Recommended Project Structure (Cargo Workspace)

### Current Issues

```
rust/src/
├── clsag/          # Monero-specific
├── adaptor/        # Monero-specific  
├── dleq.rs         # Bridge (both domains)
├── starknet.rs     # Starknet-specific
├── monero.rs       # Monero-specific
└── lib.rs          # Mixed
```

**Problems**:
1. **Audit scope ambiguity**: Auditor can't easily say "I audited the Starknet code"
2. **Dependency leakage**: Starknet code shouldn't depend on CLSAG internals
3. **Testing confusion**: Which tests cover which domain?

### Recommended Structure

```
monero-starknet-swap/
├── Cargo.toml                    # Workspace root
├── crates/
│   ├── xmr-crypto/               # 🔴 MONERO DOMAIN
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── clsag/
│   │       │   ├── mod.rs
│   │       │   ├── hash_to_point.rs
│   │       │   ├── standard.rs
│   │       │   └── adaptor.rs
│   │       ├── key_splitting.rs
│   │       └── ring.rs
│   │
│   ├── starknet-contract/        # 🟢 STARKNET DOMAIN (Cairo)
│   │   ├── Scarb.toml
│   │   └── src/
│   │       ├── lib.cairo
│   │       ├── blake2s_challenge.cairo
│   │       ├── edwards_serialization.cairo
│   │       └── dleq_verifier.cairo
│   │
│   ├── dleq-proof/               # 🔵 BRIDGE DOMAIN
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── proof.rs          # DLEQ proof generation
│   │       ├── challenge.rs      # BLAKE2s challenge
│   │       └── serialization.rs  # Cairo-compatible formats
│   │
│   ├── swap-protocol/            # 🟣 PROTOCOL ORCHESTRATION
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── maker.rs
│   │       ├── taker.rs
│   │       └── state_machine.rs
│   │
│   └── starknet-client/          # 🟢 STARKNET RPC CLIENT
│       ├── Cargo.toml
│       └── src/
│           ├── lib.rs
│           ├── deploy.rs
│           └── events.rs
│
├── cairo/                        # Cairo contract (unchanged)
│   └── ...
│
├── tools/                        # Python tooling (unchanged)
│   └── ...
│
└── tests/                        # Integration tests at workspace level
    ├── e2e_atomic_swap.rs
    └── cross_domain_compatibility.rs
```

### Crate Dependency Graph (Auditable)

```
                    ┌─────────────────┐
                    │  swap-protocol  │  ← Orchestrates everything
                    └────────┬────────┘
                             │
            ┌────────────────┼────────────────┐
            ▼                ▼                ▼
    ┌──────────────┐  ┌─────────────┐  ┌──────────────┐
    │  xmr-crypto  │  │ dleq-proof  │  │starknet-client│
    │   (Monero)   │  │  (Bridge)   │  │  (Starknet)  │
    └──────────────┘  └─────────────┘  └──────────────┘
            │                │
            └────────────────┘
              Both use Ed25519
```

**Key Principle**: Each crate has a **single audit scope**:
- `xmr-crypto`: Auditor with Monero expertise
- `starknet-client`: Auditor with Starknet expertise  
- `dleq-proof`: Cryptographer reviews the bridge
- `swap-protocol`: Protocol security review

## Migration Path (Incremental)

### Phase 1: Extract `xmr-crypto` (Fix bugs here first) ⚠️ PRIORITY

```bash
mkdir -p crates/xmr-crypto/src
mv rust/src/clsag crates/xmr-crypto/src/
mv rust/src/adaptor/key_splitting.rs crates/xmr-crypto/src/

# Fix CLSAG bugs in isolation
cargo test -p xmr-crypto
```

**Status**: Not started - Fix bugs in current location first

### Phase 2: Extract `dleq-proof`

```bash
mkdir -p crates/dleq-proof/src
mv rust/src/dleq.rs crates/dleq-proof/src/proof.rs
# Add Cairo serialization helpers
cargo test -p dleq-proof
```

**Status**: Not started

### Phase 3: Extract `starknet-client`

```bash
mkdir -p crates/starknet-client/src
mv rust/src/starknet*.rs crates/starknet-client/src/
cargo test -p starknet-client
```

**Status**: Not started

### Phase 4: Create `swap-protocol` (orchestration)

```bash
mkdir -p crates/swap-protocol/src
mv rust/src/bin/*.rs crates/swap-protocol/src/
# Refactor to use the extracted crates
cargo test -p swap-protocol
```

**Status**: Not started

## Test Organization by Domain

```
crates/xmr-crypto/tests/
├── clsag_hash_to_point.rs    # Unit
├── clsag_standard.rs         # Unit
├── clsag_adaptor.rs          # Unit
└── clsag_integration.rs      # Integration within Monero domain

crates/dleq-proof/tests/
├── challenge_computation.rs  # Unit
├── proof_generation.rs       # Unit
└── cairo_compatibility.rs    # Cross-domain bridge test

crates/swap-protocol/tests/
├── maker_flow.rs
├── taker_flow.rs
└── state_transitions.rs

tests/                         # Workspace-level E2E
├── full_atomic_swap.rs
└── adversarial_scenarios.rs
```

## Priority Action Plan

| Priority | Action | Status |
|----------|--------|--------|
| **P0** | Fix CLSAG bugs using reference paper formulas | 🔴 IN PROGRESS |
| **P1** | Add property-based tests for ring closure | ⚪ TODO |
| **P2** | Extract `xmr-crypto` crate for isolated testing | ⚪ TODO |
| **P3** | Full workspace reorganization | ⚪ TODO |
| **P4** | Separate audits per domain | ⚪ TODO |

## Immediate Next Steps

1. **Fix Bug 1**: Ring closure computation in `compute_c1()`
   - Reference CLSAG paper MRL-0011
   - Verify index wraparound logic
   - Check aggregation coefficient application

2. **Fix Bug 2**: Adaptor finalization formula
   - Verify sign: `s_π = s'_π - c_π·μ_P·t`
   - Check `μ_P` computation
   - Verify scalar reduction mod curve order

3. **Re-run Tests**: Ensure all unit tests pass before proceeding

4. **Then**: Proceed with workspace reorganization

## Workspace Cargo.toml Template

```toml
[workspace]
resolver = "2"
members = [
    "crates/xmr-crypto",
    "crates/dleq-proof", 
    "crates/swap-protocol",
    "crates/starknet-client",
]

[workspace.dependencies]
curve25519-dalek = { version = "4", features = ["serde"] }
sha2 = "0.10"
sha3 = "0.10"
blake2 = "0.10"
monero = "0.21"
zeroize = { version = "1", features = ["derive"] }
thiserror = "1"
```

## Notes

- Current flat structure is acceptable for prototype
- Production deployment requires domain separation for proper security review
- Auditor needs to know exactly which code handles which trust boundary
- Fix bugs first, then reorganize (don't refactor broken code)

## ✅ CRITICAL UPDATE: Migration to Audited Library

**Status**: 🟡 IN PROGRESS

Following auditor recommendation, we are migrating from custom CLSAG implementation to the audited `monero-clsag-mirror` library (audited by Cypher Stack for Serai DEX).

### Changes Made

1. ✅ Added `monero-clsag-mirror = "0.1"` dependency
2. ✅ Created migration plan (`MIGRATION_TO_AUDITED_CLSAG.md`)
3. ✅ Created wrapper module structure (`adaptor_audited.rs`)

### Benefits

- **Eliminates both bugs**: `compute_c1` and finalization formula bugs are in custom code that will be removed
- **Reduces audit scope**: ~800 lines → ~50 lines of custom crypto (adaptor wrapper only)
- **Production-grade**: Uses library currently being audited for production DEX
- **Maintenance**: Less code to maintain and verify

### Next Steps

1. ⏳ Inspect `monero-clsag-mirror` API and integrate
2. ⏳ Update adaptor wrapper to use audited library
3. ⏳ Migrate tests to new API
4. ⏳ Remove custom CLSAG implementation files
5. ⏳ Verify all tests pass

### Files to Remove (After Migration)

- `rust/src/clsag/hash_to_point.rs` - Replaced by audited library
- `rust/src/clsag/standard.rs` - Replaced by audited library  
- Most of `rust/src/clsag/adaptor.rs` - Keep only adaptor wrapper (~50 lines)

### References

- [Serai DEX GitHub](https://github.com/serai-dex/serai)
- [Cypher Stack Audit](https://ccs.getmonero.org/proposals/monero-serai-wallet-audit.html)
- [monero-clsag-mirror docs](https://docs.rs/monero-clsag-mirror/0.1.0)

