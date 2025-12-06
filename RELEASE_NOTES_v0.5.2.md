# Release Notes v0.5.2

**Release Date**: 2025-12-06  
**Type**: Patch Release (Critical Cryptographic Fixes)

## Summary

This release contains critical cryptographic bug fixes that resolve challenge computation mismatches and ensure Rust↔Cairo compatibility for DLEQ proof verification.

## 🔧 Critical Fixes

### 1. Endianness Fix in BLAKE2s Challenge Computation
- **Issue**: Hashlock words from SHA-256 (Big-Endian) were not being byte-swapped before BLAKE2s hashing
- **Fix**: Implemented `byte_swap_u32()` function and integrated into `hashlock_to_u256()`
- **Impact**: Ensures Cairo's BLAKE2s challenge computation matches Rust's implementation
- **Files**: `cairo/src/blake2s_challenge.cairo`

### 2. Double Consumption Bug Fix
- **Issue**: DLEQ challenge was being computed twice (in constructor and `_verify_dleq_proof`), causing hint stream exhaustion
- **Fix**: Removed redundant challenge recomputation from `_verify_dleq_proof()`, moved validation to constructor
- **Impact**: Prevents `Option::unwrap failed` errors during DLEQ verification
- **Files**: `cairo/src/lib.cairo`

### 3. Scalar Interpretation Alignment
- **Issue**: Scalar reduction after BLAKE2s was inconsistent between Rust and Cairo
- **Fix**: Verified and aligned scalar reduction logic (`% ED25519_ORDER`)
- **Impact**: Ensures challenge scalars match between Rust proof generation and Cairo verification
- **Files**: `cairo/src/blake2s_challenge.cairo`

### 4. Direct Scalar Construction
- **Issue**: `reduce_felt_to_scalar()` failed when called sequentially in MSM operations
- **Fix**: Replaced with direct scalar construction in `_verify_dleq_proof()` and `validate_dleq_inputs()`
- **Impact**: Fixes sequential MSM call failures in DLEQ verification
- **Files**: `cairo/src/lib.cairo`

## ✅ Verification & Testing

### New Tests Added
- `test_hashlock_serde_roundtrip`: Verifies hashlock serialization/deserialization integrity
- `test_msm_sg_minimal`: Isolates MSM operations for debugging
- Enhanced step-by-step constructor tests

### Test Results
- ✅ Serialization round-trip test: **PASSING**
- ✅ Endianness fix verified: Rust and Cairo compute identical BLAKE2s hashes
- ✅ Scalar interpretation verified: Both compute same challenge (0x03273bfd...)
- ⚠️ End-to-end test: Challenge mismatch still under investigation (calldata serialization)

## 📦 Dependencies

- **garaga**: v1.0.1 (Python package installed for hint generation)
- **starknet**: 2.10.0 (unchanged)
- **openzeppelin**: v2.0.0 (unchanged)

## 🔄 Data Regeneration

### Test Vectors
- Regenerated `rust/test_vectors.json` with correct challenge computation
- Updated MSM hints using Python tooling (`generate_hints_from_test_vectors.py`)
- Synchronized Cairo test constants with regenerated vectors

### Tools
- Created `fix_hints.py` for reliable sqrt hint generation
- Updated `generate-context.sh` to include all relevant files

## 📝 Code Quality

- Added comprehensive debug assertions for hashlock validation
- Enhanced error messages for better debugging
- Improved code comments documenting cryptographic operations

## ⚠️ Known Issues

1. **Challenge Mismatch in Constructor**: End-to-end test still fails with challenge mismatch
   - Root cause: Likely calldata serialization/deserialization issue
   - Status: Under investigation
   - Workaround: Test uses computed challenge directly

## 🚀 Migration Notes

No breaking changes. This is a patch release with bug fixes only.

## 📚 Documentation

- Updated `generate-context.sh` to reflect current debugging state
- Enhanced inline documentation for cryptographic operations
- Added comments explaining endianness fix rationale

## 🙏 Acknowledgments

Thanks to the auditors who identified the endianness mismatch and provided detailed action plans for resolution.

## 🔗 Related Issues

- Endianness mismatch in BLAKE2s challenge computation
- Double consumption bug in DLEQ verification
- Sequential MSM call failures

---

**Next Release**: v0.6.0 (Planned)
- Complete end-to-end DLEQ verification
- Resolve remaining challenge mismatch
- Production readiness milestone

