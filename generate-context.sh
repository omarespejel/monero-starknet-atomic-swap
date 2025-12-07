#!/bin/bash
#
# Generate an LLM-friendly context bundle for the Monero secret generator
# (Rust) and the Starknet AtomicLock Cairo contracts/tests.
# Usage: ./generate-context.sh
#
set -euo pipefail
export TMPDIR="$(pwd)"

DATE="$(date '+%Y-%m-%d_%H-%M-%S_%Z')"
OUTPUT_FILE="monero-swap-context-${DATE}.txt"

rm -f "$OUTPUT_FILE"
echo "📦 Building context bundle -> $OUTPUT_FILE"
echo ""

{
  printf '%s\n' "# Monero↔Starknet Atomic Swap - Complete Context"
  printf '%s\n' ""
  printf '%s\n' "## Project Overview"
  printf '%s\n' "This repository implements a cryptographic atomic swap protocol between Monero (XMR) and Starknet tokens."
  printf '%s\n' "The core innovation is using DLEQ (Discrete Logarithm Equality) proofs to cryptographically bind a hashlock"
  printf '%s\n' "to an Ed25519 adaptor point, enabling trustless cross-chain swaps."
  printf '%s\n' ""
  printf '%s\n' "## Current Status & Debugging Context"
  printf '%s\n' "**Release**: v0.7.0 (2025-12-06) - Key Splitting Approach Implemented"
  printf '%s\n' "**MAJOR ACHIEVEMENT**: E2E DLEQ test PASSES - Rust↔Cairo compatibility verified!"
  printf '%s\n' "**NEW APPROACH**: Key splitting for Monero atomic swaps (replaces custom CLSAG)"
  printf '%s\n' "**Progress Made**:"
  printf '%s\n' "- ✅ Fixed sequential MSM call issue by replacing reduce_felt_to_scalar() with direct scalar construction"
  printf '%s\n' "- ✅ Fixed double consumption bug: removed redundant challenge recomputation from _verify_dleq_proof()"
  printf '%s\n' "- ✅ Fixed endianness bug: added byte_swap_u32() to hashlock_to_u256() for BLAKE2s compatibility"
  printf '%s\n' "- ✅ Fixed BLAKE2s initialization vector: replaced zero initialization with RFC 7693 IV constants (CRITICAL FIX)"
  printf '%s\n' "- ✅ Fixed DLEQ tag byte order: changed from 0x444c4551 to 0x51454c44 (produces \"DLEQ\" correctly)"
  printf '%s\n' "- ✅ Fixed BLAKE2s block accumulation: refactored to accumulate bytes before compressing (matches Rust)"
  printf '%s\n' "- ✅ Fixed Y constant byte order bug: corrected ED25519_SECOND_GENERATOR_COMPRESSED in lib.cairo"
  printf '%s\n' "- ✅ Created hex_to_cairo_u256.py helper script to prevent future byte-order bugs"
  printf '%s\n' "- ✅ Generated correct sqrt hints using Python (fix_hints.py)"
  printf '%s\n' "- ✅ Verified byte-swap produces same bytes as Rust (BLAKE2s hashes match)"
  printf '%s\n' "- ✅ Verified scalar interpretation: Rust and Cairo compute same challenge with same inputs"
  printf '%s\n' "- ✅ Added debug assertions: hashlock values verified (all 8 words match expected)"
  printf '%s\n' "- ✅ Added debug assertions: points verified (T, U, R1, R2 all match expected)"
  printf '%s\n' "- ✅ Added serialization round-trip test: test_hashlock_serde_roundtrip passes"
  printf '%s\n' "- ✅ Regenerated MSM hints using Python tooling (garaga module)"
  printf '%s\n' "- ✅ Fixed double-swap bug: test_e2e_dleq.cairo now uses original SHA-256 words (not pre-swapped)"
  printf '%s\n' "- ✅ Hashlock constants standardized: all tests use original SHA-256 big-endian words"
  printf '%s\n' "- ✅ Fixed all base point constants: ED25519_BASE_POINT_COMPRESSED now correct everywhere (RFC 8032)"
  printf '%s\n' "- ✅ Fixed G and Y constant assertions in constructor to match test vectors"
  printf '%s\n' "- ✅ Created test_vectors.cairo as single source of truth for all test constants"
  printf '%s\n' "- ✅ Updated all test files to use synchronized constants from test_vectors.cairo"
  printf '%s\n' "- ✅ test_step3_all_msm_calls passes (all 4 MSM calls work in isolation)"
  printf '%s\n' "- ✅ Regenerated test_vectors.json with correct Y constant (was stale)"
  printf '%s\n' "- ✅ Updated Cairo constants from regenerated test_vectors.json"
  printf '%s\n' "- ✅ Fixed scalar truncation: MSM hints now generated with 128-bit truncated scalars"
  printf '%s\n' "- ✅ Used exact Garaga decompression for T/U points in hint generation"
  printf '%s\n' "- ✅ E2E test PASSES: test_e2e_dleq_rust_cairo_compatibility verified!"
  printf '%s\n' "- ✅ Added comprehensive test suite: negative tests, edge cases, multiple vectors, full swap flow"
  printf '%s\n' "- ✅ Added cross-platform verification script (verify_full_compatibility.py)"
  printf '%s\n' "- ✅ Implemented verify_and_unlock tests: full swap lifecycle with correct/wrong secrets"
  printf '%s\n' "- ✅ Added fake_glv_hint to deployment: required for MSM verification in unlock"
  printf '%s\n' "- ✅ Fixed type conversion errors: edge case tests now pass (felt252 → u256 conversion)"
  printf '%s\n' "- ✅ All comprehensive tests PASSING: edge cases, full swap flow, negative tests"
  printf '%s\n' "- ✅ Added security audit test suite: critical security properties (9/9 tests working correctly)"
  printf '%s\n' "- ✅ Security tests: double-unlock prevention, state transitions, hint validation, point rejection"
  printf '%s\n' "- ✅ Fixed point rejection tests: zero and low-order point rejection verified (CRITICAL security invariant)"
  printf '%s\n' "- ✅ Updated low-order point constants: correct compressed Edwards format with proper byte order"
  printf '%s\n' "- ✅ Added security invariant documentation: @custom:security-invariant comments for auditors"
  printf '%s\n' "- ✅ Added token security tests: test_security_tokens.cairo with mock ERC20 and reentrancy tests (6/6 tests passing)"
  printf '%s\n' "- ✅ Fixed depositor address tracking: deploy_contract_with_token now uses get_contract_address() for correct depositor"
  printf '%s\n' "- ✅ Fixed refund tests: test_refund_returns_exact_amount and test_refund_fails_with_insufficient_balance now pass"
  printf '%s\n' "- ✅ Fixed unlock tests: test_unlock_fails_with_insufficient_balance expects correct ERC20 error message"
  printf '%s\n' "- ✅ Fixed reentrancy test: test_reentrancy_attack_blocked properly tests ReentrancyGuard protection"
  printf '%s\n' "- ✅ Version 0.7.0: Key splitting approach implemented (replaces custom CLSAG)"
  printf '%s\n' "- ✅ Key splitting module: Implemented SwapKeyPair for Monero atomic swaps"
  printf '%s\n' "  * SwapKeyPair::generate() - Creates key pair with x = x_partial + t"
  printf '%s\n' "  * SwapKeyPair::recover() - Recovers full key when t is revealed on Starknet"
  printf '%s\n' "  * SwapKeyPair::verify() - Verifies key splitting math (T + partial·G = X)"
  printf '%s\n' "  * SwapKeyPair::adaptor_scalar_bytes() - Gets bytes for hashlock computation"
  printf '%s\n' "- ✅ Removed custom CLSAG code: Deleted ~500 lines of buggy custom implementation"
  printf '%s\n' "- ✅ Updated dependencies: Added keccak (Monero Keccak256), bs58, getrandom"
  printf '%s\n' "- ✅ Removed unnecessary deps: num-bigint, num-traits (not needed for key splitting)"
  printf '%s\n' "- ✅ Key splitting tests: All 4 tests passing (math, recovery, adaptor point, public key)"
  printf '%s\n' "- ✅ Approach: Uses only audited libraries (curve25519-dalek, RustCrypto)"
  printf '%s\n' "- ✅ Matches Serai DEX pattern: Same approach used by audited Serai DEX (Cypher Stack audit)"
  printf '%s\n' ""
  printf '%s\n' "## Architecture Components"
  printf '%s\n' ""
  printf '%s\n' "### Rust Side (Secret Generation & Proof Generation)"
  printf '%s\n' "- Generates Monero-style scalars and computes SHA-256 hashlock"
  printf '%s\n' "- Generates DLEQ proofs using BLAKE2s for challenge computation"
  printf '%s\n' "- Produces Ed25519 adaptor points, fake-GLV hints, and DLEQ hints"
  printf '%s\n' "- Outputs test vectors in JSON format for Cairo consumption"
  printf '%s\n' "- **NEW**: Key splitting for Monero atomic swaps"
  printf '%s\n' "  * SwapKeyPair generation with x = x_partial + t"
  printf '%s\n' "  * Key recovery when adaptor scalar t is revealed"
  printf '%s\n' "  * Uses standard Monero transactions (no custom CLSAG modification)"
  printf '%s\n' ""
  printf '%s\n' "### Cairo Side (Contract & Verification)"
  printf '%s\n' "- AtomicLock contract: Stores hashlock, verifies DLEQ proof in constructor"
  printf '%s\n' "- Uses Garaga library for Ed25519 MSM operations (fake-GLV optimization)"
  printf '%s\n' "- BLAKE2s challenge computation module (audited Cairo core)"
  printf '%s\n' "- Edwards point serialization/deserialization"
  printf '%s\n' "- Comprehensive test suite covering all components"
  printf '%s\n' ""
  printf '%s\n' "### Python Tooling"
  printf '%s\n' "- Generates fake-GLV hints for MSM operations"
  printf '%s\n' "- Generates DLEQ hints for proof verification"
  printf '%s\n' "- Converts between Edwards and Weierstrass point formats"
  printf '%s\n' "- Validates Rust↔Cairo compatibility"
  printf '%s\n' ""
  printf '%s\n' "## Key Technical Details"
  printf '%s\n' ""
  printf '%s\n' "### DLEQ Proof Protocol"
  printf '%s\n' "- Proves: ∃t such that T = t·G and U = t·Y without revealing t"
  printf '%s\n' "- Challenge: c = BLAKE2s(\"DLEQ\" || G || Y || T || U || R1 || R2 || hashlock) mod n"
  printf '%s\n' "- Response: s = k + c·t mod n"
  printf '%s\n' "- Verification: Check that s·G - c·T = R1 and s·Y - c·U = R2"
  printf '%s\n' ""
  printf '%s\n' "### MSM Operations (4 sequential calls in _verify_dleq_proof)"
  printf '%s\n' "1. s·G (using s_hint_for_g)"
  printf '%s\n' "2. (-c)·T (using c_neg_hint_for_t)"
  printf '%s\n' "3. s·Y (using s_hint_for_y)"
  printf '%s\n' "4. (-c)·U (using c_neg_hint_for_u)"
  printf '%s\n' ""
  printf '%s\n' "### Critical Fixes Applied (v0.5.2)"
  printf '%s\n' "- Replaced reduce_felt_to_scalar() with direct scalar construction in _verify_dleq_proof() and validate_dleq_inputs()"
  printf '%s\n' "- Fixed double consumption bug: removed challenge recomputation from _verify_dleq_proof(), added validation in constructor"
  printf '%s\n' "- Fixed endianness bug: added byte_swap_u32() function to swap Big-Endian u32 words to Little-Endian before BLAKE2s hashing"
  printf '%s\n' "- Fixed BLAKE2s initialization vector (CRITICAL): replaced zero initialization with RFC 7693 IV constants"
  printf '%s\n' "  * IV[0] = 0x6B08E647 (0x6A09E667 ^ 0x01010020), IV[1-7] = standard RFC 7693 constants"
  printf '%s\n' "  * Without correct IV, BLAKE2s produces completely different output regardless of input"
  printf '%s\n' "- Fixed DLEQ tag byte order: changed from 0x444c4551 to 0x51454c44 (produces \"DLEQ\" correctly in BLAKE2s)"
  printf '%s\n' "- Fixed BLAKE2s block accumulation: refactored compute_dleq_challenge_blake2s() to accumulate all input bytes"
  printf '%s\n' "  * Cairo now processes continuous 64-byte blocks (matches Rust behavior)"
  printf '%s\n' "  * Previously called blake2s_compress separately for each item, padding each to 64 bytes"
  printf '%s\n' "- Fixed Y constant byte order bug: corrected ED25519_SECOND_GENERATOR_COMPRESSED in lib.cairo"
  printf '%s\n' "  * Was: low: 0x0e5f46ae6af8a3c997390f5164385156, high: 0x1da25ee8c9a21f562260cdf3092329c2"
  printf '%s\n' "  * Now: low: 0x97390f51643851560e5f46ae6af8a3c9, high: 0x2260cdf3092329c21da25ee8c9a21f56"
  printf '%s\n' "- Created tools/hex_to_cairo_u256.py helper script to prevent future byte-order bugs"
  printf '%s\n' "  * Converts 64-character hex strings to Cairo u256 format correctly"
  printf '%s\n' "  * Always use this script when adding constants from test_vectors.json"
  printf '%s\n' "- Updated hashlock_to_u256() to byte-swap each u32 word before packing into u256"
  printf '%s\n' "- Added span length validation in hashlock_to_u256() and compute_dleq_challenge_blake2s()"
  printf '%s\n' "- Added fallback handling for scalar-to-felt252 conversion"
  printf '%s\n' "- Generated correct sqrt hints using Python script (fix_hints.py) with standard Ed25519 arithmetic"
  printf '%s\n' "- Added debug assertions in constructor to verify hashlock values (all 8 words)"
  printf '%s\n' "- Added debug assertions in constructor to verify points (T, U, R1, R2)"
  printf '%s\n' "- Added verification assertions for base point constants (G and Y) - RFC 8032 compliance"
  printf '%s\n' "- Added serialization round-trip test (test_hashlock_serde_roundtrip) to verify Serde integrity"
  printf '%s\n' "- Regenerated MSM hints using Python tooling with garaga module"
  printf '%s\n' "- Fixed double-swap bug: Updated test_e2e_dleq.cairo to use original SHA-256 words (not pre-swapped)"
  printf '%s\n' "- Standardized hashlock constants: All tests now use original SHA-256 big-endian words"
  printf '%s\n' "- Fixed all base point constants: ED25519_BASE_POINT_COMPRESSED corrected in all test files (RFC 8032)"
  printf '%s\n' "- Updated constructor debug assertions to expect original SHA-256 words"
  printf '%s\n' "- Created test_vectors.cairo as single source of truth for all test constants"
  printf '%s\n' "- Updated all test files to import constants from test_vectors.cairo (removed duplicate definitions)"
  printf '%s\n' "- Fixed G and Y constant assertions in constructor to match test vectors"
  printf '%s\n' "- Regenerated test_vectors.json after all fixes to ensure cryptographic consistency"
  printf '%s\n' ""
  printf '%s\n' "## Files Organization"
  printf '%s\n' ""
  printf '%s\n' "### Core Contract Files"
  printf '%s\n' "- cairo/src/lib.cairo: Main AtomicLock contract with constructor and DLEQ verification"
  printf '%s\n' "- cairo/src/blake2s_challenge.cairo: BLAKE2s challenge computation module"
  printf '%s\n' "- cairo/src/edwards_serialization.cairo: Point serialization utilities"
  printf '%s\n' ""
  printf '%s\n' "### Test Files (Organized by Category)"
  printf '%s\n' ""
  printf '%s\n' "**E2E Tests** (e2e/):"
  printf '%s\n' "- test_e2e_dleq.cairo: ✅ CRITICAL - End-to-end test (PASSES - Rust↔Cairo compatibility verified)"
  printf '%s\n' "- test_full_swap_flow.cairo: ✅ Full swap lifecycle tests - ALL PASS"
  printf '%s\n' ""
  printf '%s\n' "**Integration Tests** (integration/):"
  printf '%s\n' "- test_constructor_step_by_step.cairo: Step-by-step constructor flow test"
  printf '%s\n' "- test_garaga_msm_all_calls.cairo: Tests all 4 MSM calls (PASSES)"
  printf '%s\n' "- test_dleq_challenge_only.cairo: DLEQ challenge computation test"
  printf '%s\n' "- test_hashlock_serde.cairo: Hashlock serialization tests"
  printf '%s\n' ""
  printf '%s\n' "**Unit Tests** (unit/):"
  printf '%s\n' "- test_blake2s_challenge.cairo: BLAKE2s challenge computation tests"
  printf '%s\n' "- test_blake2s_byte_order.cairo: Byte order tests"
  printf '%s\n' "- test_dleq.cairo: DLEQ proof verification tests"
  printf '%s\n' "- test_point_decompression.cairo: Point decompression tests"
  printf '%s\n' ""
  printf '%s\n' "**Security Tests** (security/):"
  printf '%s\n' "- test_security_audit.cairo: ✅ Security audit tests (9/9 working correctly)"
  printf '%s\n' "  * CRITICAL: Zero and low-order point rejection verified (panics correctly)"
  printf '%s\n' "  * Double-unlock prevention, state transitions, hint validation"
  printf '%s\n' "- test_security_dleq_negative.cairo: Negative tests (wrong challenge/response/hashlock rejection)"
  printf '%s\n' "- test_security_edge_cases.cairo: ✅ Edge case tests (max scalar, zero, small values) - ALL PASS"
  printf '%s\n' "- test_security_tokens.cairo: ✅ Token security tests (6/6 passing - COMPLETE)"
  printf '%s\n' "  * Mock ERC20 contract: Basic ERC20 implementation for testing token transfers"
  printf '%s\n' "  * Malicious reentrant token: Attempts reentrancy during transfer to test ReentrancyGuard"
  printf '%s\n' "  * test_unlock_transfers_exact_amount: ✅ PASSES - Verifies exact token transfer on unlock"
  printf '%s\n' "  * test_refund_returns_exact_amount: ✅ PASSES - Verifies exact token refund to depositor"
  printf '%s\n' "  * test_zero_amount_no_transfer: ✅ PASSES - Zero amount contracts don't call token"
  printf '%s\n' "  * test_unlock_fails_with_insufficient_balance: ✅ PASSES - ERC20 balance check works"
  printf '%s\n' "  * test_refund_fails_with_insufficient_balance: ✅ PASSES - Refund balance check works"
  printf '%s\n' "  * test_reentrancy_attack_blocked: ✅ PASSES - ReentrancyGuard blocks nested calls"
  printf '%s\n' ""
  printf '%s\n' "**Fixtures** (fixtures/):"
  printf '%s\n' "- test_vectors.cairo: Single source of truth for all test constants"
  printf '%s\n' "- dleq_test_helpers.cairo: Shared test helper functions"
  printf '%s\n' "- constants/low_order_points.cairo: Ed25519 low-order point constants"
  printf '%s\n' ""
  printf '%s\n' "**Debug Tests** (debug/):"
  printf '%s\n' "- test_blake2s_state_debug.cairo: BLAKE2s state debugging"
  printf '%s\n' "- test_scalar_debugging.cairo: Scalar reduction debugging"
  printf '%s\n' "- test_print_computed_challenge.cairo: Challenge computation debugging"
  printf '%s\n' ""
  printf '%s\n' "### Rust Implementation"
  printf '%s\n' "- rust/src/dleq.rs: DLEQ proof generation"
  printf '%s\n' "- rust/src/adaptor/: Adaptor signature implementation"
  printf '%s\n' "- rust/src/bin/: CLI tools for secret generation and proof creation"
  printf '%s\n' ""
  printf '%s\n' "### Python Tooling"
  printf '%s\n' "- tools/generate_dleq_hints.py: Generates MSM hints for DLEQ verification"
  printf '%s\n' "- tools/generate_hints_exact.py: Generates MSM hints with exact Garaga decompression (CRITICAL)"
  printf '%s\n' "- tools/generate_hints_from_test_vectors.py: Generates MSM hints from test_vectors.json (with truncation)"
  printf '%s\n' "- tools/generate_adaptor_point_hint.py: Generates fake-GLV hints"
  printf '%s\n' "- tools/generate_sqrt_hints.py: Generates sqrt hints for Ed25519 point decompression"
  printf '%s\n' "- tools/hex_to_cairo_u256.py: Converts hex strings to Cairo u256 format (prevents byte-order bugs)"
  printf '%s\n' "- tools/verify_challenge_computation.py: Verifies BLAKE2s challenge computation"
  printf '%s\n' "- tools/verify_full_compatibility.py: Cross-platform verification script (Rust↔Python↔Cairo)"
  printf '%s\n' "- fix_hints.py: Generates correct sqrt hints using standard Ed25519 arithmetic (replaces broken Rust tool)"
  printf '%s\n' "- tools/verify_rust_cairo_equivalence.py: Validates compatibility"
  printf '%s\n' ""
  printf '%s\n' "## Debugging Focus Areas"
  printf '%s\n' "1. BLAKE2s initialization vector (IV): ✅ FIXED - RFC 7693 compliant IV now implemented"
  printf '%s\n' "   - Root cause: initial_blake2s_state() was initializing with all zeros instead of RFC 7693 IV"
  printf '%s\n' "   - Impact: Without correct IV, BLAKE2s produces completely different output regardless of input"
  printf '%s\n' "   - Fix: Implemented standard IV constants XOR'd with parameter block (0x01010020 for 32-byte output)"
  printf '%s\n' "   - Status: IV fix applied, test vectors regenerated, constants updated"
  printf '%s\n' "2. DLEQ tag byte order: ✅ FIXED - Changed from 0x444c4551 to 0x51454c44"
  printf '%s\n' "   - Root cause: Tag was reversed, causing BLAKE2s to read \"QELD\" instead of \"DLEQ\""
  printf '%s\n' "   - Impact: Every challenge computation was wrong from the first byte"
  printf '%s\n' "   - Fix: Corrected byte order to produce \"DLEQ\" correctly"
  printf '%s\n' "3. BLAKE2s block accumulation: ✅ FIXED - Refactored to accumulate bytes before compressing"
  printf '%s\n' "   - Root cause: Cairo called blake2s_compress separately for each item, padding each to 64 bytes"
  printf '%s\n' "   - Impact: Data layout was wrong, causing different hash output than Rust"
  printf '%s\n' "   - Fix: Accumulate all input bytes into continuous 64-byte blocks before compressing"
  printf '%s\n' "4. Y constant byte order: ✅ FIXED - Corrected ED25519_SECOND_GENERATOR_COMPRESSED in lib.cairo"
  printf '%s\n' "   - Root cause: Y constant had wrong byte order (low/high swapped)"
  printf '%s\n' "   - Impact: Challenge computation used wrong Y point, causing mismatch"
  printf '%s\n' "   - Fix: Corrected to match test_vectors.json (low: 0x97390f51..., high: 0x2260cdf3...)"
  printf '%s\n' "   - Helper: Created tools/hex_to_cairo_u256.py to prevent future byte-order bugs"
  printf '%s\n' "5. Challenge mismatch: ✅ FIXED - Challenge verification now passes"
  printf '%s\n' "   - ✅ Double-swap bug FIXED: test_e2e_dleq.cairo now uses original SHA-256 words"
  printf '%s\n' "   - ✅ Hashlock verified: All 8 words match expected values (original SHA-256 BE words)"
  printf '%s\n' "   - ✅ Points verified: T, U, R1, R2 all match expected values"
  printf '%s\n' "   - ✅ Base point verified: ED25519_BASE_POINT_COMPRESSED correct everywhere (RFC 8032)"
  printf '%s\n' "   - ✅ Y point verified: ED25519_SECOND_GENERATOR_COMPRESSED corrected in lib.cairo"
  printf '%s\n' "   - ✅ Serialization verified: test_hashlock_serde_roundtrip passes"
  printf '%s\n' "   - ✅ Hashlock constants standardized: All tests use same original SHA-256 words"
  printf '%s\n' "   - ✅ Challenge computation verified: Test now passes challenge verification"
  printf '%s\n' "   - ✅ E2E test PASSES: Rust↔Cairo DLEQ compatibility verified!"
  printf '%s\n' "6. Endianness compatibility: ✅ Verified byte-swap is correct, Rust and Cairo compute same challenge"
  printf '%s\n' "7. Scalar interpretation: ✅ Verified Rust and Cairo use same scalar reduction (% ED25519_ORDER)"
  printf '%s\n' "8. Test vector synchronization: ✅ Created test_vectors.cairo as single source of truth"
  printf '%s\n' "   - All test files now import constants from test_vectors.cairo"
  printf '%s\n' "   - Regenerated test_vectors.json after all fixes"
  printf '%s\n' "9. Base point constants: ✅ FIXED - All test files now use correct constants (RFC 8032)"
  printf '%s\n' "10. MSM hints: ✅ REGENERATED - Hints generated with truncated scalars and exact Garaga decompression"
  printf '%s\n' "    - Fixed: Hints now use 128-bit truncated scalars (matching Cairo's behavior)"
  printf '%s\n' "    - Fixed: T/U points use exact Garaga decompression (not simplified conversion)"
  printf '%s\n' "    - Command: python3 tools/generate_hints_exact.py (uses exact decompression)"
  printf '%s\n' "    - Command: python3 tools/generate_hints_from_test_vectors.py (with truncation fix)"
  printf '%s\n' ""
  printf '%s\n' "11. Test vectors: ✅ REGENERATED - test_vectors.json updated with correct Y constant"
  printf '%s\n' "    - Root cause: test_vectors.json was stale (generated before Y fix)"
  printf '%s\n' "    - Fix: Regenerated with correct Y constant, updated Cairo constants"
  printf '%s\n' "    - Status: All constants synchronized, E2E test passes"
  printf '%s\n' ""
  printf '%s\n' "12. Comprehensive test suite: ✅ COMPLETE - All tests passing"
  printf '%s\n' "    - test_dleq_negative.cairo (security/): Wrong challenge/response/hashlock rejection tests"
  printf '%s\n' "    - test_dleq_multiple_vectors.cairo (integration/): Infrastructure for multiple test vectors"
  printf '%s\n' "    - test_dleq_edge_cases.cairo (security/): ✅ PASSES - Max scalar, zero, small values (4/4 tests pass)"
  printf '%s\n' "      * Fixed type conversion: felt252 → u256 → compare .low field"
  printf '%s\n' "    - test_full_swap_flow.cairo (e2e/): ✅ PASSES - Full swap lifecycle (2/2 tests pass, 1 ignored)"
  printf '%s\n' "      * test_full_swap_lifecycle: Deploys contract, unlocks with correct secret, verifies unlocked"
  printf '%s\n' "      * test_unlock_with_wrong_secret: Tests wrong secret rejection and contract remains locked"
  printf '%s\n' "      * test_refund_after_expiry: Ignored (requires time manipulation)"
  printf '%s\n' "    - tools/verify_full_compatibility.py: Cross-platform verification script"
  printf '%s\n' ""
  printf '%s\n' "13. Security audit test suite: ✅ COMPLETE - Critical security properties tested"
  printf '%s\n' "    - test_security_audit.cairo (security/): Main security tests (9/9 tests working correctly)"
  printf '%s\n' "      * test_cannot_unlock_twice: ✅ PASSES - Double-unlock prevention"
  printf '%s\n' "      * test_unlock_prevents_refund: ✅ PASSES - State transition protection"
  printf '%s\n' "      * test_refund_prevents_unlock: ✅ PASSES - State transition protection"
  printf '%s\n' "      * test_hint_validation_exists: ✅ PASSES - Hint validation"
  printf '%s\n' "      * test_contract_starts_locked: ✅ PASSES - Initial state"
  printf '%s\n' "      * test_valid_unlock_succeeds: ✅ PASSES - Valid unlock flow"
  printf '%s\n' "      * test_reject_zero_point: ✅ FIXED - Zero point rejection verified (panics correctly)"
  printf '%s\n' "      * test_reject_low_order_point_order_2: ✅ FIXED - Low-order point rejection verified (panics correctly)"
  printf '%s\n' "    - fixtures/constants/low_order_points.cairo: ✅ FIXED - Ed25519 low-order point constants (correct byte order)"
  printf '%s\n' "      * All 8 low-order points documented with correct compressed Edwards format"
  printf '%s\n' "      * LOW_ORDER_POINT_1 corrected: proper little-endian byte order, fits in u128"
  printf '%s\n' "      * Security invariant documented: @custom:security-invariant comments added"
    printf '%s\n' "    - test_security_tokens.cairo: ✅ Token security tests (6/6 passing - COMPLETE)"
    printf '%s\n' "      * Mock ERC20 contract: Basic ERC20 implementation for testing token transfers"
    printf '%s\n' "      * Malicious reentrant token: Attempts reentrancy during transfer to test ReentrancyGuard"
    printf '%s\n' "      * test_unlock_transfers_exact_amount: ✅ PASSES - Verifies exact token transfer on unlock"
    printf '%s\n' "      * test_refund_returns_exact_amount: ✅ PASSES - Verifies exact token refund to depositor"
    printf '%s\n' "      * test_zero_amount_no_transfer: ✅ PASSES - Zero amount contracts don't call token"
    printf '%s\n' "      * test_unlock_fails_with_insufficient_balance: ✅ PASSES - ERC20 balance check prevents transfer"
    printf '%s\n' "      * test_refund_fails_with_insufficient_balance: ✅ PASSES - Refund balance check prevents transfer"
    printf '%s\n' "      * test_reentrancy_attack_blocked: ✅ PASSES - ReentrancyGuard blocks nested calls to verify_and_unlock"
    printf '%s\n' "      * Fixed depositor address tracking: deploy_contract_with_token uses get_contract_address()"
    printf '%s\n' "      * Fixed expected error messages: Tests expect ERC20 errors (Insufficient balance) not contract errors"
  printf '%s\n' ""
  printf '%s\n' "14. Test organization: ✅ REFACTORED - Tests organized with naming conventions"
  printf '%s\n' "    - test_security_*.cairo: Security audit tests (CRITICAL - 3 files)"
  printf '%s\n' "    - test_e2e_*.cairo: End-to-end tests (Rust↔Cairo compatibility - 2 files)"
  printf '%s\n' "    - test_unit_*.cairo: Fast, isolated unit tests (11 files)"
  printf '%s\n' "    - test_integration_*.cairo: Cross-component tests (13 files)"
  printf '%s\n' "    - test_debug_*.cairo: Development/debugging tests (5 files)"
  printf '%s\n' "    - fixtures/: Shared test data and helpers (NOT test files)"
  printf '%s\n' "    - All tests in tests/ root for native snforge discovery (107 tests)"
  printf '%s\n' ""
  printf '%s\n' "15. Production code cleanup: ✅ COMPLETE - Debug assertions removed"
  printf '%s\n' "    - Removed hardcoded test vector assertions from lib.cairo constructor"
  printf '%s\n' "    - Removed hashlock value assertions (h0-h7 hardcoded checks)"
  printf '%s\n' "    - Removed point value assertions (T, U, R1, R2 hardcoded checks)"
  printf '%s\n' "    - Production code now validates inputs without test-specific checks"
  printf '%s\n' "    - Created INVARIANTS.md documenting all contract invariants"
  printf '%s\n' "    - Created coverage.toml for test coverage configuration"
  printf '%s\n' ""
  printf '%s\n' "---"
  printf '%s\n' ""
} >> "$OUTPUT_FILE"

{
  echo "## Directory Structure"
  if command -v tree >/dev/null 2>&1; then
    tree -L 3 -I ".git|target|node_modules|dist|.cursor|terminals|__pycache__|*.pyc" >> "$OUTPUT_FILE"
  else
    find . -maxdepth 3 \
      -not -path '*/.git/*' \
      -not -path '*/target/*' \
      -not -path '*/node_modules/*' \
      -not -path '*/dist/*' \
      -not -path '*/.cursor/*' \
      -not -path '*/terminals/*' \
      -not -path '*/__pycache__/*' \
      -not -name '*.pyc' | sort >> "$OUTPUT_FILE"
  fi
  echo ""
} >> "$OUTPUT_FILE"

add_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    echo "## FILE: $file" >> "$OUTPUT_FILE"
    cat "$file" >> "$OUTPUT_FILE"
    echo -e "\n---\n" >> "$OUTPUT_FILE"
  else
    echo "⚠️  Warning: File not found: $file" >&2
  fi
}

# Root configuration and documentation
ROOT_FILES=(
  "README.md"
  "Makefile"
  "demo.sh"
  "CONTRIBUTING.md"
  "SECURITY.md"
  "TECHNICAL.md"
  "VERSIONING.md"
  "FORMATTING.md"
  "pyproject.toml"
)

# Current debugging and analysis documents
DEBUG_DOCS=(
  "DEBUG_STATUS.md"
  "AUDITOR_UPDATE_PROTOCOL_ISSUE.md"
  "PROTOCOL_MISMATCH_ANALYSIS.md"
  "RELEASE_NOTES_v0.4.0.md"
  "RELEASE_NOTES_v0.5.0.md"
  "RELEASE_NOTES_v0.5.2.md"
  "AUDITOR_RECOMMENDATIONS.md"
)

# Cairo source files (all)
CAIRO_SOURCE=(
  "cairo/Scarb.toml"
  "cairo/Scarb.lock"
  "cairo/snfoundry.toml"
  "cairo/coverage.toml"
  "cairo/src/lib.cairo"
  "cairo/src/blake2s_challenge.cairo"
  "cairo/src/edwards_serialization.cairo"
)

# Cairo documentation files
CAIRO_DOCS=(
  "cairo/INVARIANTS.md"
  "cairo/README_TESTS.md"
)

# Cairo test files (organized by category with naming convention)
# Security tests (CRITICAL)
CAIRO_TESTS_SECURITY=(
  "cairo/tests/test_security_audit.cairo"
  "cairo/tests/test_security_dleq_negative.cairo"
  "cairo/tests/test_security_edge_cases.cairo"
  "cairo/tests/test_security_tokens.cairo"
)

# E2E tests (full system)
CAIRO_TESTS_E2E=(
  "cairo/tests/test_e2e_dleq.cairo"
  "cairo/tests/test_e2e_full_swap_flow.cairo"
)

# Unit tests (fast, isolated)
CAIRO_TESTS_UNIT=(
  "cairo/tests/test_unit_blake2s_challenge.cairo"
  "cairo/tests/test_unit_blake2s_byte_order.cairo"
  "cairo/tests/test_unit_rfc7693_vectors.cairo"
  "cairo/tests/test_unit_dleq.cairo"
  "cairo/tests/test_unit_garaga_integration.cairo"
  "cairo/tests/test_unit_garaga_minimal.cairo"
  "cairo/tests/test_unit_msm_sg_minimal.cairo"
  "cairo/tests/test_unit_point_decompression.cairo"
  "cairo/tests/test_unit_point_decompression_individual.cairo"
  "cairo/tests/test_unit_decompression_formats.cairo"
  "cairo/tests/test_unit_ed25519_base_point.cairo"
)

# Integration tests (cross-component)
CAIRO_TESTS_INTEGRATION=(
  "cairo/tests/test_integration_constructor.cairo"
  "cairo/tests/test_integration_dleq_challenge.cairo"
  "cairo/tests/test_integration_garaga_msm.cairo"
  "cairo/tests/test_integration_dleq_hint.cairo"
  "cairo/tests/test_integration_hashlock_serde.cairo"
  "cairo/tests/test_integration_serde_hint.cairo"
  "cairo/tests/test_integration_atomic_lock.cairo"
  "cairo/tests/test_integration_dleq_multiple.cairo"
  "cairo/tests/test_integration_extract_adaptor.cairo"
  "cairo/tests/test_integration_extract_coords.cairo"
  "cairo/tests/test_integration_gas.cairo"
  "cairo/tests/test_integration_adaptor_hint.cairo"
  "cairo/tests/test_integration_hint_serde.cairo"
)

# Debug tests (development/debugging)
CAIRO_TESTS_DEBUG=(
  "cairo/tests/test_debug_blake2s_state.cairo"
  "cairo/tests/test_debug_scalar.cairo"
  "cairo/tests/test_debug_coordinates.cairo"
  "cairo/tests/test_debug_challenge.cairo"
  "cairo/tests/test_debug_garaga_msm.cairo"
)

# Fixtures (shared test data and helpers - NOT test files)
CAIRO_TESTS_FIXTURES=(
  "cairo/tests/fixtures/test_vectors.cairo"
  "cairo/tests/fixtures/dleq_test_helpers.cairo"
  "cairo/tests/fixtures/constants/low_order_points.cairo"
)

# Combine all test files for context bundle
CAIRO_TESTS=(
  "${CAIRO_TESTS_SECURITY[@]}"
  "${CAIRO_TESTS_E2E[@]}"
  "${CAIRO_TESTS_UNIT[@]}"
  "${CAIRO_TESTS_INTEGRATION[@]}"
  "${CAIRO_TESTS_DEBUG[@]}"
  "${CAIRO_TESTS_FIXTURES[@]}"
)

# Cairo test data files
CAIRO_DATA=(
  "cairo/adaptor_point_hint.json"
  "cairo/test_hints.json"
)

# Cairo test constants
CAIRO_TEST_CONSTANTS=(
  "cairo/tests/constants/low_order_points.cairo"
)

# Rust source files (all)
RUST_SOURCE=(
  "rust/Cargo.toml"
  "rust/Cargo.lock"
  "rust/src/lib.rs"
  "rust/src/main.rs"
  "rust/src/dleq.rs"
  "rust/src/poseidon.rs"
  "rust/src/monero.rs"
  "rust/src/monero_full.rs"
  "rust/src/starknet.rs"
  "rust/src/starknet_full.rs"
)

# Rust adaptor module
RUST_ADAPTOR=(
  "rust/src/adaptor/mod.rs"
  "rust/src/adaptor/adaptor_sig.rs"
  "rust/src/adaptor/key_splitting.rs"
)

# Rust Monero module (v0.7.0 - Key Splitting Approach)
# NOTE: Custom CLSAG code removed - using key splitting instead
RUST_MONERO=(
  "rust/src/monero/mod.rs"
  "rust/src/monero/key_splitting.rs"
  "rust/src/monero/transaction.rs"
)

# Rust documentation
RUST_DOCS=(
  "rust/AUDIT_DEPENDENCIES.md"
)

# Rust binary tools (all)
RUST_BIN=(
  "rust/src/bin/maker.rs"
  "rust/src/bin/taker.rs"
  "rust/src/bin/generate_second_base.rs"
  "rust/src/bin/generate_all_sqrt_hints.rs"
  "rust/src/bin/generate_sqrt_hints.rs"
  "rust/src/bin/generate_test_vector.rs"
  "rust/src/bin/get_all_sqrt_hints.rs"
  "rust/src/bin/get_constants.rs"
  "rust/src/bin/regenerate_r1.rs"
)

# Rust test files
RUST_TESTS=(
  "rust/tests/integration_test.rs"
  "rust/tests/test_vectors.rs"
  "rust/test_vectors.json"
)

# Rust Monero test files (v0.7.0 - Key Splitting)
# NOTE: Old CLSAG tests removed - key splitting tests are in key_splitting.rs module tests
RUST_MONERO_TESTS=(
  "rust/tests/integration_test.rs"
)

# Python tooling (all)
TOOLS_PYTHON=(
  "tools/pyproject.toml"
  "tools/README.md"
  "tools/uv.lock"
  "tools/debug_hints.py"
  "tools/fix_compressed_points.py"
  "tools/garaga_conversion.py"
  "tools/generate_adaptor_hint.py"
  "tools/generate_adaptor_point_hint.py"
  "tools/generate_dleq_for_adaptor_point.py"
  "tools/generate_dleq_hints.py"
  "tools/generate_ed25519_test_data.py"
  "tools/generate_hints_exact.py"
  "tools/generate_hints_from_decompressed_points.py"
  "tools/generate_hints_from_test_vectors.py"
  "tools/generate_second_base.py"
  "tools/generate_sqrt_hints.py"
  "tools/generate_test_hints.py"
  "tools/regenerate_dleq_hints.py"
  "tools/regenerate_garaga_hints.py"
  "tools/verify_challenge_computation.py"
  "tools/verify_exact_scalar_match.py"
  "tools/verify_fake_glv_decomposition.py"
  "tools/verify_full_compatibility.py"
  "tools/verify_hint.py"
  "tools/verify_rust_cairo_equivalence.py"
)

# Root-level Python scripts
ROOT_PYTHON=(
  "fix_hints.py"
)

# Python tooling data files
TOOLS_DATA=(
  "tools/ed25519_test_data.json"
)

echo "📝 Adding files to context bundle..."

# Add files in logical order
for path in "${ROOT_FILES[@]}"; do
  add_file "$path"
done

for path in "${DEBUG_DOCS[@]}"; do
  add_file "$path"
done

for path in "${CAIRO_SOURCE[@]}"; do
  add_file "$path"
done

for path in "${CAIRO_DOCS[@]}"; do
  add_file "$path"
done

for path in "${CAIRO_TESTS[@]}"; do
  add_file "$path"
done

for path in "${CAIRO_DATA[@]}"; do
  add_file "$path"
done

for path in "${CAIRO_TEST_CONSTANTS[@]}"; do
  add_file "$path"
done

for path in "${RUST_SOURCE[@]}"; do
  add_file "$path"
done

for path in "${RUST_ADAPTOR[@]}"; do
  add_file "$path"
done

for path in "${RUST_MONERO[@]}"; do
  add_file "$path"
done

for path in "${RUST_DOCS[@]}"; do
  add_file "$path"
done

for path in "${RUST_BIN[@]}"; do
  add_file "$path"
done

for path in "${RUST_TESTS[@]}"; do
  add_file "$path"
done

for path in "${RUST_MONERO_TESTS[@]}"; do
  add_file "$path"
done

for path in "${TOOLS_PYTHON[@]}"; do
  add_file "$path"
done

for path in "${ROOT_PYTHON[@]}"; do
  add_file "$path"
done

for path in "${TOOLS_DATA[@]}"; do
  add_file "$path"
done

# Count files included
TOTAL_FILES=$((
  ${#ROOT_FILES[@]} +
  ${#DEBUG_DOCS[@]} +
  ${#CAIRO_SOURCE[@]} +
  ${#CAIRO_DOCS[@]} +
  ${#CAIRO_TESTS[@]} +
  ${#CAIRO_DATA[@]} +
  ${#CAIRO_TEST_CONSTANTS[@]} +
  ${#RUST_SOURCE[@]} +
  ${#RUST_ADAPTOR[@]} +
  ${#RUST_MONERO[@]} +
  ${#RUST_DOCS[@]} +
  ${#RUST_BIN[@]} +
  ${#RUST_TESTS[@]} +
  ${#RUST_MONERO_TESTS[@]} +
  ${#TOOLS_PYTHON[@]} +
  ${#ROOT_PYTHON[@]} +
  ${#TOOLS_DATA[@]}
))

echo ""
echo "📊 Summary:"
echo "  - Root files: ${#ROOT_FILES[@]}"
echo "  - Debug documentation: ${#DEBUG_DOCS[@]}"
echo "  - Cairo source files: ${#CAIRO_SOURCE[@]}"
echo "  - Cairo documentation: ${#CAIRO_DOCS[@]}"
echo "  - Cairo test files: ${#CAIRO_TESTS[@]}"
echo "  - Cairo data files: ${#CAIRO_DATA[@]}"
echo "  - Cairo test constants: ${#CAIRO_TEST_CONSTANTS[@]}"
echo "  - Rust source files: ${#RUST_SOURCE[@]}"
echo "  - Rust adaptor module: ${#RUST_ADAPTOR[@]}"
echo "  - Rust Monero module: ${#RUST_MONERO[@]}"
echo "  - Rust documentation: ${#RUST_DOCS[@]}"
echo "  - Rust binary tools: ${#RUST_BIN[@]}"
echo "  - Rust test files: ${#RUST_TESTS[@]}"
echo "  - Rust Monero test files: ${#RUST_MONERO_TESTS[@]}"
echo "  - Python tooling: ${#TOOLS_PYTHON[@]}"
echo "  - Root Python scripts: ${#ROOT_PYTHON[@]}"
echo "  - Tooling data files: ${#TOOLS_DATA[@]}"
echo "  - Total files: $TOTAL_FILES"
echo ""
echo "✅ Context written to $OUTPUT_FILE"
echo ""
echo "💡 This context bundle includes:"
echo "   - All Cairo source and test files (including debugging tests)"
echo "   - Cairo documentation (INVARIANTS.md, README_TESTS.md)"
echo "   - All Rust source, adaptor, and binary files"
echo "   - Rust Monero key splitting module"
echo "   - All Python tooling scripts (including fix_hints.py)"
echo "   - Current debugging status and analysis documents"
echo "   - Auditor recommendations and feedback (AUDITOR_RECOMMENDATIONS.md)"
echo "   - Test data files (JSON vectors, hints)"
echo "   - Configuration files (Scarb.toml, Cargo.toml, pyproject.toml, coverage.toml)"
echo ""
echo "🎯 Use this context to understand:"
echo "   - The complete DLEQ proof protocol implementation"
echo "   - Current state: v0.7.0 - Key splitting approach implemented"
echo "   - E2E DLEQ test PASSES (Rust↔Cairo compatibility verified!)"
echo "   - Recent fixes: double consumption bug, endianness bug, double-swap bug, BLAKE2s IV, base point constants"
echo "   - BLAKE2s initialization: RFC 7693 compliant IV implementation (critical cryptographic fix)"
echo "   - Scalar truncation: MSM hints use 128-bit truncated scalars (matching Cairo's reduce_felt_to_scalar)"
echo "   - Exact Garaga decompression: T/U points use exact decompression for hint generation"
echo "   - Test patterns and how they differ from constructor flow"
echo "   - Rust↔Cairo compatibility and data flow"
echo "   - BLAKE2s challenge computation with byte-swapped hashlock words and correct IV"
echo "   - Debug assertions verifying hashlock and points match expected values"
echo "   - Serialization round-trip testing for calldata integrity"
echo "   - Hashlock constants standardization: all tests use original SHA-256 big-endian words"
echo "   - Base point constant fixes: ED25519_BASE_POINT_COMPRESSED corrected across all files"
echo "   - Comprehensive test suite: negative tests, edge cases, multiple vectors, full swap flow"
  echo "   - Security audit tests: double-unlock prevention, state transitions, point rejection (ALL FIXED)"
  echo "   - Point rejection tests: zero and low-order point rejection verified (CRITICAL security invariant)"
echo "   - Cross-platform verification: tools/verify_full_compatibility.py"
echo "   - Key splitting approach: Monero atomic swap cryptographic core (v0.7.0)"
echo "     * SwapKeyPair::generate() - Split key: x = x_partial + t"
echo "     * Send T = t·G to Starknet with DLEQ proof"
echo "     * When t revealed, recover x = x_partial + t"
echo "     * Create standard Monero transaction with full key (using Serai's audited code)"
echo "   - Key splitting migration: ✅ COMPLETE - Custom CLSAG removed"
echo "     * ✅ Deleted all custom CLSAG code (~500 lines of buggy code)"
echo "     * ✅ Implemented key splitting module (~50 lines of correct code)"
echo "     * ✅ Uses only audited libraries (curve25519-dalek, RustCrypto)"
echo "     * ✅ Matches Serai DEX approach (audited by Cypher Stack)"
echo "     * ✅ All 4 key splitting tests passing"
echo "     * ✅ Reduced audit scope: No custom cryptographic primitives"
echo "     * ✅ Clear audit trail: Only scalar addition (x = a + b)"
echo "     * Benefits: Eliminates ~500 lines of buggy code, uses \$100k+ of community audits"
echo "     * Architecture: Key splitting + DLEQ proofs (Cairo tests unchanged - 107 tests)"
echo "   - Key splitting test suite: Simple and correct"
echo "     * test_key_splitting_math: Verifies T + partial·G = X"
echo "     * test_key_recovery: Verifies x_partial + t = x_full"
echo "     * test_adaptor_point_derivation: Verifies T = t·G"
echo "     * test_public_key_derivation: Verifies X = x·G"
echo "     * Status: 4/4 tests passing - all cryptographic properties verified"
