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
  printf '%s\n' "**Release**: v0.5.2 (2025-12-06) - Critical Cryptographic Fixes"
  printf '%s\n' "**CRITICAL**: Fixed BLAKE2s initialization vector (IV) - RFC 7693 compliant initialization now implemented."
  printf '%s\n' "**Progress Made**:"
  printf '%s\n' "- ✅ Fixed sequential MSM call issue by replacing reduce_felt_to_scalar() with direct scalar construction"
  printf '%s\n' "- ✅ Fixed double consumption bug: removed redundant challenge recomputation from _verify_dleq_proof()"
  printf '%s\n' "- ✅ Fixed endianness bug: added byte_swap_u32() to hashlock_to_u256() for BLAKE2s compatibility"
  printf '%s\n' "- ✅ Fixed BLAKE2s initialization vector: replaced zero initialization with RFC 7693 IV constants (CRITICAL FIX)"
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
  printf '%s\n' "- ✅ test_step3_all_msm_calls passes (all 4 MSM calls work in isolation)"
  printf '%s\n' "- ⏳ End-to-end test (test_e2e_dleq_rust_cairo_compatibility): Testing after IV fix"
  printf '%s\n' "- 🔍 Current state: IV fix applied, test vectors regenerated, constants updated"
  printf '%s\n' "- 🔍 Next: Verify test passes with correct BLAKE2s initialization"
  printf '%s\n' ""
  printf '%s\n' "## Architecture Components"
  printf '%s\n' ""
  printf '%s\n' "### Rust Side (Secret Generation & Proof Generation)"
  printf '%s\n' "- Generates Monero-style scalars and computes SHA-256 hashlock"
  printf '%s\n' "- Generates DLEQ proofs using BLAKE2s for challenge computation"
  printf '%s\n' "- Produces Ed25519 adaptor points, fake-GLV hints, and DLEQ hints"
  printf '%s\n' "- Outputs test vectors in JSON format for Cairo consumption"
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
  printf '%s\n' "- Updated hashlock_to_u256() to byte-swap each u32 word before packing into u256"
  printf '%s\n' "- Added span length validation in hashlock_to_u256() and compute_dleq_challenge_blake2s()"
  printf '%s\n' "- Added fallback handling for scalar-to-felt252 conversion"
  printf '%s\n' "- Generated correct sqrt hints using Python script (fix_hints.py) with standard Ed25519 arithmetic"
  printf '%s\n' "- Added debug assertions in constructor to verify hashlock values (all 8 words)"
  printf '%s\n' "- Added debug assertions in constructor to verify points (T, U, R1, R2)"
  printf '%s\n' "- Added verification assertions for base point constant (RFC 8032 compliance)"
  printf '%s\n' "- Added serialization round-trip test (test_hashlock_serde_roundtrip) to verify Serde integrity"
  printf '%s\n' "- Regenerated MSM hints using Python tooling with garaga module"
  printf '%s\n' "- Fixed double-swap bug: Updated test_e2e_dleq.cairo to use original SHA-256 words (not pre-swapped)"
  printf '%s\n' "- Standardized hashlock constants: All tests now use original SHA-256 big-endian words"
  printf '%s\n' "- Fixed all base point constants: ED25519_BASE_POINT_COMPRESSED corrected in all test files (RFC 8032)"
  printf '%s\n' "- Updated constructor debug assertions to expect original SHA-256 words"
  printf '%s\n' "- Regenerated test_vectors.json after IV fix to ensure cryptographic consistency"
  printf '%s\n' ""
  printf '%s\n' "## Files Organization"
  printf '%s\n' ""
  printf '%s\n' "### Core Contract Files"
  printf '%s\n' "- cairo/src/lib.cairo: Main AtomicLock contract with constructor and DLEQ verification"
  printf '%s\n' "- cairo/src/blake2s_challenge.cairo: BLAKE2s challenge computation module"
  printf '%s\n' "- cairo/src/edwards_serialization.cairo: Point serialization utilities"
  printf '%s\n' ""
  printf '%s\n' "### Test Files (Critical for Understanding)"
  printf '%s\n' "- test_e2e_dleq.cairo: End-to-end test (currently failing)"
  printf '%s\n' "- test_constructor_step_by_step.cairo: Step-by-step constructor flow test"
  printf '%s\n' "- test_garaga_msm_all_calls.cairo: Tests all 4 MSM calls (PASSES)"
  printf '%s\n' "- test_dleq.cairo: DLEQ proof verification tests"
  printf '%s\n' "- test_blake2s_challenge.cairo: BLAKE2s challenge computation tests"
  printf '%s\n' ""
  printf '%s\n' "### Rust Implementation"
  printf '%s\n' "- rust/src/dleq.rs: DLEQ proof generation"
  printf '%s\n' "- rust/src/adaptor/: Adaptor signature implementation"
  printf '%s\n' "- rust/src/bin/: CLI tools for secret generation and proof creation"
  printf '%s\n' ""
  printf '%s\n' "### Python Tooling"
  printf '%s\n' "- tools/generate_dleq_hints.py: Generates MSM hints for DLEQ verification"
  printf '%s\n' "- tools/generate_adaptor_point_hint.py: Generates fake-GLV hints"
  printf '%s\n' "- tools/generate_sqrt_hints.py: Generates sqrt hints for Ed25519 point decompression"
  printf '%s\n' "- fix_hints.py: Generates correct sqrt hints using standard Ed25519 arithmetic (replaces broken Rust tool)"
  printf '%s\n' "- tools/verify_rust_cairo_equivalence.py: Validates compatibility"
  printf '%s\n' ""
  printf '%s\n' "## Debugging Focus Areas"
  printf '%s\n' "1. BLAKE2s initialization vector (IV): ✅ FIXED - RFC 7693 compliant IV now implemented"
  printf '%s\n' "   - Root cause: initial_blake2s_state() was initializing with all zeros instead of RFC 7693 IV"
  printf '%s\n' "   - Impact: Without correct IV, BLAKE2s produces completely different output regardless of input"
  printf '%s\n' "   - Fix: Implemented standard IV constants XOR'd with parameter block (0x01010020 for 32-byte output)"
  printf '%s\n' "   - Status: IV fix applied, test vectors regenerated, constants updated"
  printf '%s\n' "2. Challenge mismatch: Testing after IV fix"
  printf '%s\n' "   - ✅ Double-swap bug FIXED: test_e2e_dleq.cairo now uses original SHA-256 words"
  printf '%s\n' "   - ✅ Hashlock verified: All 8 words match expected values (original SHA-256 BE words)"
  printf '%s\n' "   - ✅ Points verified: T, U, R1, R2 all match expected values"
  printf '%s\n' "   - ✅ Base point verified: ED25519_BASE_POINT_COMPRESSED correct everywhere (RFC 8032)"
  printf '%s\n' "   - ✅ Serialization verified: test_hashlock_serde_roundtrip passes"
  printf '%s\n' "   - ✅ Hashlock constants standardized: All tests use same original SHA-256 words"
  printf '%s\n' "   - ⏳ Testing: Verifying challenge computation with correct IV"
  printf '%s\n' "3. Endianness compatibility: ✅ Verified byte-swap is correct, Rust and Cairo compute same challenge"
  printf '%s\n' "4. Scalar interpretation: ✅ Verified Rust and Cairo use same scalar reduction (% ED25519_ORDER)"
  printf '%s\n' "5. Test vector synchronization: ✅ Regenerated test_vectors.json and MSM hints after IV fix"
  printf '%s\n' "6. Base point constants: ✅ FIXED - All test files now use correct ED25519_BASE_POINT_COMPRESSED (RFC 8032)"
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
)

# Current debugging and analysis documents
DEBUG_DOCS=(
  "DEBUG_STATUS.md"
  "AUDITOR_UPDATE_PROTOCOL_ISSUE.md"
  "PROTOCOL_MISMATCH_ANALYSIS.md"
  "RELEASE_NOTES_v0.4.0.md"
  "RELEASE_NOTES_v0.5.0.md"
  "RELEASE_NOTES_v0.5.2.md"
)

# Cairo source files (all)
CAIRO_SOURCE=(
  "cairo/Scarb.toml"
  "cairo/Scarb.lock"
  "cairo/snfoundry.toml"
  "cairo/src/lib.cairo"
  "cairo/src/blake2s_challenge.cairo"
  "cairo/src/edwards_serialization.cairo"
)

# Cairo test files (all - critical for understanding)
CAIRO_TESTS=(
  "cairo/tests/test_atomic_lock.cairo"
  "cairo/tests/test_blake2s_byte_order.cairo"
  "cairo/tests/test_blake2s_challenge.cairo"
  "cairo/tests/test_constructor_step_by_step.cairo"
  "cairo/tests/test_decompression_formats.cairo"
  "cairo/tests/test_dleq_challenge_only.cairo"
  "cairo/tests/test_dleq_hint_verification.cairo"
  "cairo/tests/test_dleq.cairo"
  "cairo/tests/test_e2e_dleq.cairo"
  "cairo/tests/test_ed25519_base_point.cairo"
  "cairo/tests/test_extract_adaptor_coords.cairo"
  "cairo/tests/test_extract_coordinates.cairo"
  "cairo/tests/test_garaga_integration.cairo"
  "cairo/tests/test_garaga_minimal.cairo"
  "cairo/tests/test_garaga_msm_all_calls.cairo"
  "cairo/tests/test_garaga_msm_debug.cairo"
  "cairo/tests/test_gas_benchmark.cairo"
  "cairo/tests/test_get_adaptor_hint.cairo"
  "cairo/tests/test_hashlock_serde.cairo"
  "cairo/tests/test_msm_sg_minimal.cairo"
  "cairo/tests/test_output_coordinates.cairo"
  "cairo/tests/test_point_decompression_individual.cairo"
  "cairo/tests/test_point_decompression.cairo"
  "cairo/tests/test_rfc7693_vectors.cairo"
  "cairo/tests/test_scalar_debugging.cairo"
  "cairo/tests/test_serde_hint_roundtrip.cairo"
  "cairo/tests/dleq_test_helpers.cairo"
)

# Cairo test data files
CAIRO_DATA=(
  "cairo/adaptor_point_hint.json"
  "cairo/test_hints.json"
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
  "tools/generate_hints_from_decompressed_points.py"
  "tools/generate_hints_from_test_vectors.py"
  "tools/generate_second_base.py"
  "tools/generate_sqrt_hints.py"
  "tools/generate_test_hints.py"
  "tools/regenerate_dleq_hints.py"
  "tools/regenerate_garaga_hints.py"
  "tools/verify_exact_scalar_match.py"
  "tools/verify_fake_glv_decomposition.py"
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

for path in "${CAIRO_TESTS[@]}"; do
  add_file "$path"
done

for path in "${CAIRO_DATA[@]}"; do
  add_file "$path"
done

for path in "${RUST_SOURCE[@]}"; do
  add_file "$path"
done

for path in "${RUST_ADAPTOR[@]}"; do
  add_file "$path"
done

for path in "${RUST_BIN[@]}"; do
  add_file "$path"
done

for path in "${RUST_TESTS[@]}"; do
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
  ${#CAIRO_TESTS[@]} +
  ${#CAIRO_DATA[@]} +
  ${#RUST_SOURCE[@]} +
  ${#RUST_ADAPTOR[@]} +
  ${#RUST_BIN[@]} +
  ${#RUST_TESTS[@]} +
  ${#TOOLS_PYTHON[@]} +
  ${#ROOT_PYTHON[@]} +
  ${#TOOLS_DATA[@]}
))

echo ""
echo "📊 Summary:"
echo "  - Root files: ${#ROOT_FILES[@]}"
echo "  - Debug documentation: ${#DEBUG_DOCS[@]}"
echo "  - Cairo source files: ${#CAIRO_SOURCE[@]}"
echo "  - Cairo test files: ${#CAIRO_TESTS[@]}"
echo "  - Cairo data files: ${#CAIRO_DATA[@]}"
echo "  - Rust source files: ${#RUST_SOURCE[@]}"
echo "  - Rust adaptor module: ${#RUST_ADAPTOR[@]}"
echo "  - Rust binary tools: ${#RUST_BIN[@]}"
echo "  - Rust test files: ${#RUST_TESTS[@]}"
echo "  - Python tooling: ${#TOOLS_PYTHON[@]}"
echo "  - Root Python scripts: ${#ROOT_PYTHON[@]}"
echo "  - Tooling data files: ${#TOOLS_DATA[@]}"
echo "  - Total files: $TOTAL_FILES"
echo ""
echo "✅ Context written to $OUTPUT_FILE"
echo ""
echo "💡 This context bundle includes:"
echo "   - All Cairo source and test files (including debugging tests)"
echo "   - All Rust source, adaptor, and binary files"
echo "   - All Python tooling scripts (including fix_hints.py)"
echo "   - Current debugging status and analysis documents"
echo "   - Test data files (JSON vectors, hints)"
echo ""
echo "🎯 Use this context to understand:"
echo "   - The complete DLEQ proof protocol implementation"
echo "   - Current debugging state: v0.5.2 released, BLAKE2s IV fix applied, testing in progress"
echo "   - Recent fixes: double consumption bug, endianness bug, double-swap bug, BLAKE2s IV, base point constants"
echo "   - BLAKE2s initialization: RFC 7693 compliant IV implementation (critical cryptographic fix)"
echo "   - Test patterns and how they differ from constructor flow"
echo "   - Rust↔Cairo compatibility and data flow"
echo "   - BLAKE2s challenge computation with byte-swapped hashlock words and correct IV"
echo "   - Debug assertions verifying hashlock and points match expected values"
echo "   - Serialization round-trip testing for calldata integrity"
echo "   - Hashlock constants standardization: all tests use original SHA-256 big-endian words"
echo "   - Base point constant fixes: ED25519_BASE_POINT_COMPRESSED corrected across all files"
