# Test Consolidation Plan

**Date**: December 2025  
**Status**: Phase 1 Complete, Phase 2-4 Pending  
**Auditor Assessment**: ✅ Confirmed - 35 test files need consolidation

## Current State

### ✅ Already Completed (Phase 1)

1. **Single Source of Truth for Test Vectors** ✅
   - `cairo/tests/fixtures/test_vectors.cairo` - All test constants centralized
   - Used by most tests via imports

2. **Unified Deployment Helper** ✅
   - `cairo/tests/fixtures/deployment_helpers.cairo` - Main deployment function
   - `deploy_with_test_vectors()` - Uses real DLEQ proof data
   - `deploy_with_dleq_proof()` - Low-level helper for custom deployments

3. **Deprecated Functions Marked** ✅
   - `deploy_with_full()` - Marked as deprecated, tests using it marked `#[ignore]`

### ⚠️ Remaining Work

**Test File Count**: 35 files (target: ~8 files, 77% reduction)

**Current Structure**:
```
cairo/tests/
├── fixtures/                    ✅ Good
│   ├── test_vectors.cairo      ✅ Single source of truth
│   └── deployment_helpers.cairo ✅ Unified helpers
│
├── test_e2e_*.cairo             (2 files) - Keep as-is
├── test_security_*.cairo        (4 files) - Consolidate to 1
├── test_integration_*.cairo     (12 files) - Consolidate to 1
├── test_unit_*.cairo            (12 files) - Consolidate to 1
└── test_debug_*.cairo           (5 files) - Mark all #[ignore]
```

## Phase 2: Test File Consolidation

### Target Structure

```
cairo/tests/
├── fixtures/
│   ├── mod.cairo                # NEW - Module exports
│   ├── test_vectors.cairo       ✅ Exists
│   └── deployment_helpers.cairo ✅ Exists (add deploy() wrapper)
│
├── test_e2e.cairo               # Keep (2 modules)
│   ├── mod full_swap_flow
│   └── mod dleq_verification
│
├── test_security.cairo          # NEW - Merge 4 files
│   ├── mod dleq_negative
│   ├── mod audit
│   ├── mod tokens
│   └── mod edge_cases
│
├── test_unit.cairo              # NEW - Merge 12 files
│   ├── mod blake2s              # Merge: test_unit_blake2s_*
│   ├── mod point_decompression  # Merge: test_unit_point_decompression_*
│   ├── mod msm                  # Merge: test_unit_msm_*, test_unit_garaga_*
│   ├── mod dleq                 # Merge: test_unit_dleq.cairo
│   └── mod ed25519              # Merge: test_unit_ed25519_base_point.cairo
│
└── test_integration.cairo       # NEW - Merge 12 files
    ├── mod constructor          # Merge: test_integration_constructor.cairo
    ├── mod atomic_lock          # Merge: test_integration_atomic_lock.cairo
    ├── mod dleq                 # Merge: test_integration_dleq_*.cairo (5 files)
    ├── mod adaptor_hint         # Merge: test_integration_adaptor_hint.cairo
    ├── mod extract_coords       # Merge: test_integration_extract_*.cairo (2 files)
    ├── mod serde                # Merge: test_integration_*_serde.cairo (3 files)
    └── mod gas                  # Merge: test_integration_gas.cairo
```

### Files to Consolidate

#### Security Tests (4 → 1)
- `test_security_dleq_negative.cairo` → `test_security.cairo::dleq_negative`
- `test_security_audit.cairo` → `test_security.cairo::audit`
- `test_security_tokens.cairo` → `test_security.cairo::tokens`
- `test_security_edge_cases.cairo` → `test_security.cairo::edge_cases`

#### Unit Tests (12 → 1)
- `test_unit_blake2s_*.cairo` (3 files) → `test_unit.cairo::blake2s`
- `test_unit_point_decompression*.cairo` (3 files) → `test_unit.cairo::point_decompression`
- `test_unit_msm_*.cairo` (2 files) → `test_unit.cairo::msm`
- `test_unit_garaga_*.cairo` (3 files) → `test_unit.cairo::msm`
- `test_unit_dleq.cairo` → `test_unit.cairo::dleq`
- `test_unit_ed25519_base_point.cairo` → `test_unit.cairo::ed25519`
- `test_unit_rfc7693_vectors.cairo` → `test_unit.cairo::blake2s`
- `test_unit_decompression_formats.cairo` → `test_unit.cairo::point_decompression`

#### Integration Tests (12 → 1)
- `test_integration_constructor.cairo` → `test_integration.cairo::constructor`
- `test_integration_atomic_lock.cairo` → `test_integration.cairo::atomic_lock`
- `test_integration_dleq_*.cairo` (5 files) → `test_integration.cairo::dleq`
- `test_integration_adaptor_hint.cairo` → `test_integration.cairo::adaptor_hint`
- `test_integration_extract_*.cairo` (2 files) → `test_integration.cairo::extract_coords`
- `test_integration_*_serde.cairo` (3 files) → `test_integration.cairo::serde`
- `test_integration_gas.cairo` → `test_integration.cairo::gas`

#### Debug Tests (5 files)
- Mark all `#[ignore]` - Keep for development use
- `test_debug_*.cairo` (5 files) - No consolidation needed

## Phase 3: Simplify Deployment API

### Current API
```cairo
use fixtures::deployment_helpers::deploy_with_test_vectors;

let dispatcher = deploy_with_test_vectors(
    FUTURE_TIMESTAMP,
    0.try_into().unwrap(),
    u256 { low: 0, high: 0 },
);
```

### Proposed Simplified API
```cairo
use fixtures::deploy;  // Simple wrapper

// Default deployment (most tests)
let dispatcher = deploy();

// Custom parameters (when needed)
let dispatcher = deploy()
    .with_timestamp(FUTURE_TIMESTAMP)
    .with_token(token_address)
    .with_amount(amount);
```

**Note**: Cairo doesn't support method chaining like Rust. Keep current API but add simple `deploy()` wrapper.

## Phase 4: Documentation Cleanup

### Current Docs (15+ files)
- `docs/ARCHITECTURE.md` ✅ Keep
- `docs/SECURITY.md` ✅ Keep
- `docs/PROTOCOL.md` ✅ Keep
- `docs/CONTEXT_GENERATION.md` ✅ Keep
- `docs/TEST_STATUS.md` ✅ Keep (recent)
- `docs/CONSOLIDATION_PLAN.md` ✅ This file

### Archive (Move to `docs/archive/`)
- Historical migration docs (if any exist)
- Old test documentation

## Execution Timeline

### ✅ Phase 1: Infrastructure (COMPLETE)
- [x] Create `test_vectors.cairo`
- [x] Create `deployment_helpers.cairo`
- [x] Mark deprecated functions

### 🔄 Phase 2: Consolidation (ESTIMATE: 4-6 hours)
- [ ] Create `test_security.cairo` (merge 4 files)
- [ ] Create `test_unit.cairo` (merge 12 files)
- [ ] Create `test_integration.cairo` (merge 12 files)
- [ ] Mark debug tests as `#[ignore]`
- [ ] Update imports in all tests
- [ ] Verify all tests still pass

### 🔄 Phase 3: API Simplification (ESTIMATE: 1 hour)
- [ ] Add simple `deploy()` wrapper function
- [ ] Update documentation
- [ ] Update example tests

### 🔄 Phase 4: Documentation (ESTIMATE: 1 hour)
- [ ] Archive old docs
- [ ] Update README.md
- [ ] Create CHANGELOG.md

## Benefits

1. **Maintainability**: Single file per test category = easier to navigate
2. **Consistency**: All tests use same fixtures and helpers
3. **Reduced Duplication**: 35 files → ~8 files (77% reduction)
4. **Faster CI**: Fewer files to compile
5. **Better Organization**: Logical grouping by test type

## Risks & Mitigation

| Risk | Mitigation |
|------|------------|
| Large merge conflicts | Do consolidation incrementally, one category at a time |
| Tests break during merge | Run tests after each consolidation step |
| Hard to find specific tests | Use module structure with clear names |
| Git history lost | Use `git mv` to preserve history where possible |

## Next Steps

1. **Immediate** (This Weekend):
   - Add `deploy()` wrapper function
   - Consolidate security tests (4 → 1)
   - Verify tests pass

2. **Next Week**:
   - Consolidate unit tests (12 → 1)
   - Consolidate integration tests (12 → 1)
   - Update CI/CD

3. **Follow-up**:
   - Documentation cleanup
   - Final verification

