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
  printf '%s\n' "# Monero Atomic Swap Context"
  printf '%s\n' ""
  printf '%s\n' "## Goal for the LLM"
  printf '%s\n' "You are reviewing a repo that:"
  printf '%s\n' "- Generates a Monero-style scalar in Rust (\`cargo run\`) and prints its SHA-256 digest as 8×u32 plus the secret as a Cairo byte string."
  printf '%s\n' "- Contains a Starknet AtomicLock contract that stores the target hash (8×u32) and enforces a MSM check against an Ed25519 adaptor point."
  printf '%s\n' "- ✅ Implements DLEQ (Discrete Logarithm Equality) proofs to cryptographically bind the hashlock to the adaptor point (verified in constructor)."
  printf '%s\n' "- Uses BLAKE2s hashing for DLEQ challenge computation (8x cheaper than Poseidon, Starknet v0.14.1+ standard)."
  printf '%s\n' "- Production-grade cryptographic modules: blake2s_challenge (uses audited Cairo core) and edwards_serialization."
  printf '%s\n' "- Includes comprehensive Cairo test harnesses: unit tests, DLEQ tests, and Garaga integration tests."
  printf '%s\n' "- Provides Python tooling (uv + garaga) to generate Ed25519 adaptor points, fake-GLV hints, DLEQ hints, and Cairo-ready test vectors."
  printf '%s\n' "- Includes Rust modules for adaptor signatures, DLEQ proof generation, Poseidon hashing, and Monero/Starknet integration."
  printf '%s\n' "- Uses OpenZeppelin ReentrancyGuard component for audited reentrancy protection."
  printf '%s\n' ""
  printf '%s\n' "Focus your analysis on:"
  printf '%s\n' "- Scalar sampling, hashing, and formatting consistency between Rust and Cairo."
  printf '%s\n' "- Correct storage/layout of the SHA-256 digest (endianness and word order)."
  printf '%s\n' "- DLEQ proof generation (Rust) and verification (Cairo) implementation and compatibility."
  printf '%s\n' "- BLAKE2s hash function usage in DLEQ challenge computation (Cairo side, using audited Cairo core)."
  printf '%s\n' "- Modular architecture: blake2s_challenge.cairo and edwards_serialization.cairo modules."
  printf '%s\n' "- Compressed Edwards point format (RFC 8032) for efficient point serialization."
  printf '%s\n' "- Test wiring: constructor calldata, deployment, and \`verify_and_unlock\` call."
  printf '%s\n' "- Manifest and toolchain alignment (Rust deps, Scarb/Starknet versions)."
  printf '%s\n' "- Adaptor signature implementation for Monero atomic swaps."
  printf '%s\n' "- Security considerations: reentrancy protection, input validation, small-order point checks."
  printf '%s\n' ""
  printf '%s\n' "---"
  printf '%s\n' ""
} >> "$OUTPUT_FILE"

{
  echo "## Directory Structure"
  if command -v tree >/dev/null 2>&1; then
    tree -L 3 -I ".git|target|node_modules|dist|.cursor|terminals" >> "$OUTPUT_FILE"
  else
    find . -maxdepth 3 \
      -not -path '*/.git/*' \
      -not -path '*/target/*' \
      -not -path '*/node_modules/*' \
      -not -path '*/dist/*' \
      -not -path '*/.cursor/*' \
      -not -path '*/terminals/*' | sort >> "$OUTPUT_FILE"
  fi
  echo ""
} >> "$OUTPUT_FILE"

add_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    echo "## FILE: $file" >> "$OUTPUT_FILE"
    cat "$file" >> "$OUTPUT_FILE"
    echo -e "\n---\n" >> "$OUTPUT_FILE"
  fi
}

ROOT_FILES=(
  "README.md"
  "$0"
)

TOOLS_FILES=(
  "tools/pyproject.toml"
  "tools/README.md"
  "tools/generate_ed25519_test_data.py"
  "tools/generate_dleq_hints.py"
  "tools/generate_second_base.py"
  "tools/generate_test_hints.py"
  "tools/ed25519_test_data.json"
  "tools/uv.lock"
)

RUST_FILES=(
  "rust/Cargo.toml"
  "rust/Cargo.lock"
  "rust/src/lib.rs"
  "rust/src/main.rs"
  "rust/src/dleq.rs"
  "rust/src/poseidon.rs"
  "rust/src/adaptor/mod.rs"
  "rust/src/adaptor/adaptor_sig.rs"
  "rust/src/adaptor/key_splitting.rs"
  "rust/src/starknet.rs"
  "rust/src/starknet_full.rs"
  "rust/src/monero.rs"
  "rust/src/monero_full.rs"
  "rust/src/bin/maker.rs"
  "rust/src/bin/taker.rs"
  "rust/src/bin/generate_second_base.rs"
)

CAIRO_FILES=(
  "cairo/Scarb.toml"
  "cairo/Scarb.lock"
  "cairo/snfoundry.toml"
  "cairo/src/lib.cairo"
  "cairo/src/blake2s_challenge.cairo"
  "cairo/src/edwards_serialization.cairo"
  "cairo/tests/test_atomic_lock.cairo"
  "cairo/tests/test_dleq.cairo"
  "cairo/tests/test_garaga_integration.cairo"
)

RUST_TEST_FILES=(
  "rust/tests/integration_test.rs"
)

# Key documentation files that explain implementation details
DOC_FILES=(
  "SECURITY.md"
  "STATUS.md"
  "TESTING.md"
  "ANALYSIS.md"
  "DLEQ_COMPATIBILITY.md"
  "HASH_FUNCTION_ANALYSIS.md"
  "IMPLEMENTATION_SPEC.md"
  "MSM_HINTS_GUIDE.md"
  "CAIRO_MODULE_STRUCTURE.md"
  "CONTRIBUTING.md"
)

for path in "${ROOT_FILES[@]}"; do
  add_file "$path"
done

for path in "${TOOLS_FILES[@]}"; do
  add_file "$path"
done

for path in "${RUST_FILES[@]}"; do
  add_file "$path"
done

for path in "${CAIRO_FILES[@]}"; do
  add_file "$path"
done

for path in "${RUST_TEST_FILES[@]}"; do
  add_file "$path"
done

for path in "${DOC_FILES[@]}"; do
  add_file "$path"
done

# Count files included
TOTAL_FILES=$((
  ${#ROOT_FILES[@]} +
  ${#TOOLS_FILES[@]} +
  ${#RUST_FILES[@]} +
  ${#CAIRO_FILES[@]} +
  ${#RUST_TEST_FILES[@]} +
  ${#DOC_FILES[@]}
))

echo ""
echo "📊 Summary:"
echo "  - Root files: ${#ROOT_FILES[@]}"
echo "  - Tools files: ${#TOOLS_FILES[@]}"
echo "  - Rust source files: ${#RUST_FILES[@]}"
echo "  - Cairo files: ${#CAIRO_FILES[@]}"
echo "  - Rust test files: ${#RUST_TEST_FILES[@]}"
echo "  - Documentation files: ${#DOC_FILES[@]}"
echo "  - Total files: $TOTAL_FILES"
echo ""
echo "✅ Context written to $OUTPUT_FILE"

