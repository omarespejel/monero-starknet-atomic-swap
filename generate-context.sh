#!/bin/bash
#
# Generate an LLM-friendly context bundle for the Monero secret generator
# (Rust) and the Starknet AtomicLock Cairo contracts/tests.
# Usage: ./generate-context.sh
#
set -euo pipefail
export TMPDIR="$(pwd)"

DATE="$(date '+%Y-%m-%d_%H-%M-%S_%Z')"
OUTPUT_FILE="xmr-starknet-swap-context-${DATE}.txt"

rm -f "$OUTPUT_FILE"
echo "📦 Building context bundle -> $OUTPUT_FILE"
echo ""

{
  printf '%s\n' "# XMR ↔️ Starknet Atomic Lock Context"
  printf '%s\n' ""
  printf '%s\n' "## Goal for the LLM"
  printf '%s\n' "You are reviewing a repo that:"
  printf '%s\n' "- Generates a Monero-style scalar in Rust (\`cargo run\`) and prints its SHA-256 digest as 8×u32 plus the secret as a Cairo byte string."
  printf '%s\n' "- Contains a Starknet AtomicLock contract that stores the target hash (8×u32) and enforces a MSM check against an Ed25519 adaptor point."
  printf '%s\n' "- Includes a Cairo test harness that deploys the contract and calls \`verify_and_unlock\` with Rust/Python-produced data."
  printf '%s\n' "- Provides Python tooling (uv + garaga) to generate Ed25519 adaptor points, fake-GLV hints, and Cairo-ready test vectors."
  printf '%s\n' ""
  printf '%s\n' "Focus your analysis on:"
  printf '%s\n' "- Scalar sampling, hashing, and formatting consistency between Rust and Cairo."
  printf '%s\n' "- Correct storage/layout of the SHA-256 digest (endianness and word order)."
  printf '%s\n' "- Test wiring: constructor calldata, deployment, and \`verify_and_unlock\` call."
  printf '%s\n' "- Manifest and toolchain alignment (Rust deps, Scarb/Starknet versions)."
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
  "tools/ed25519_test_data.json"
)

RUST_FILES=(
  "rust/Cargo.toml"
  "rust/Cargo.lock"
  "rust/src/lib.rs"
  "rust/src/main.rs"
)

CAIRO_FILES=(
  "cairo/Scarb.toml"
  "cairo/Scarb.lock"
  "cairo/snfoundry.toml"
  "cairo/src/lib.cairo"
  "cairo/tests/test_atomic_lock.cairo"
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

echo "✅ Context written to $OUTPUT_FILE"

