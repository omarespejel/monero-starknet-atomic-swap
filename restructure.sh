#!/bin/bash
set -euo pipefail

echo "🔄 Restructuring repository..."

# 1. Clean up root directory
echo "📁 Cleaning root..."
rm -f monero-swap-context-*.txt 2>/dev/null || true
rm -f xmr-starknet-swap-context-*.txt 2>/dev/null || true
rm -f context*.xml 2>/dev/null || true
# Keep generate-context.sh for now (user requested not to delete)

# 2. Create new directories
echo "📁 Creating new structure..."
mkdir -p .cursor/rules
mkdir -p docs/decisions
mkdir -p docs/archive
mkdir -p rust/crates/dleq/src
mkdir -p rust/crates/monero-keys/src
mkdir -p rust/crates/swap-cli/src
mkdir -p cairo/tests/security
mkdir -p cairo/tests/e2e
mkdir -p cairo/tests/integration
mkdir -p cairo/tests/unit
mkdir -p cairo/tests/fixtures/mocks
mkdir -p tools/hints
mkdir -p tools/verify
mkdir -p tools/convert
mkdir -p tools/archive

# 3. Move documentation
echo "📄 Organizing documentation..."
# Move existing docs to archive if they exist
[ -f TECHNICAL.md ] && mv TECHNICAL.md docs/ 2>/dev/null || true
[ -f VERSIONING.md ] && mv VERSIONING.md docs/archive/ 2>/dev/null || true
[ -f FORMATTING.md ] && mv FORMATTING.md docs/archive/ 2>/dev/null || true
[ -f DEBUG_STATUS.md ] && mv DEBUG_STATUS.md docs/archive/ 2>/dev/null || true
mv RELEASE_NOTES_*.md docs/archive/ 2>/dev/null || true
mv AUDITOR_*.md docs/archive/ 2>/dev/null || true
mv PROTOCOL_*.md docs/archive/ 2>/dev/null || true
mv CONTEXT_GENERATION.md docs/archive/ 2>/dev/null || true

# 4. Organize Cairo tests
echo "🧪 Organizing Cairo tests..."
cd cairo/tests

# Security tests
for f in test_security_*.cairo; do
    [ -f "$f" ] && mv "$f" "security/${f#test_security_}" 2>/dev/null || true
done

# E2E tests
for f in test_e2e_*.cairo; do
    [ -f "$f" ] && mv "$f" "e2e/${f#test_e2e_}" 2>/dev/null || true
done

# Unit tests
for f in test_unit_*.cairo; do
    [ -f "$f" ] && mv "$f" "unit/${f#test_unit_}" 2>/dev/null || true
done

# Integration tests
for f in test_integration_*.cairo; do
    [ -f "$f" ] && mv "$f" "integration/${f#test_integration_}" 2>/dev/null || true
done

# Debug tests (archive - not needed in production)
mkdir -p debug_archive
for f in test_debug_*.cairo; do
    [ -f "$f" ] && mv "$f" "debug_archive/" 2>/dev/null || true
done

cd ../..

# 5. Organize Python tools
echo "🐍 Organizing Python tools..."
cd tools

# Hint generation scripts
[ -f generate_dleq_hints.py ] && mv generate_dleq_hints.py hints/ 2>/dev/null || true
[ -f generate_hints_exact.py ] && mv generate_hints_exact.py hints/ 2>/dev/null || true
[ -f generate_hints_from_test_vectors.py ] && mv generate_hints_from_test_vectors.py hints/ 2>/dev/null || true
[ -f generate_sqrt_hints.py ] && mv generate_sqrt_hints.py hints/ 2>/dev/null || true
[ -f generate_adaptor_hint.py ] && mv generate_adaptor_hint.py hints/ 2>/dev/null || true
[ -f generate_adaptor_point_hint.py ] && mv generate_adaptor_point_hint.py hints/ 2>/dev/null || true

# Verification scripts
[ -f verify_full_compatibility.py ] && mv verify_full_compatibility.py verify/rust_cairo_compatibility.py 2>/dev/null || true
[ -f verify_challenge_computation.py ] && mv verify_challenge_computation.py verify/ 2>/dev/null || true
[ -f verify_rust_cairo_equivalence.py ] && mv verify_rust_cairo_equivalence.py verify/ 2>/dev/null || true

# Conversion utilities
[ -f hex_to_cairo_u256.py ] && mv hex_to_cairo_u256.py convert/ 2>/dev/null || true
[ -f garaga_conversion.py ] && mv garaga_conversion.py convert/ 2>/dev/null || true

# Archive one-off scripts (move common ones, keep rest for manual review)
[ -f debug_hints.py ] && mv debug_hints.py archive/ 2>/dev/null || true
[ -f fix_hints.py ] && mv fix_hints.py archive/ 2>/dev/null || true
[ -f fix_all_hints.py ] && mv fix_all_hints.py archive/ 2>/dev/null || true
[ -f fix_compressed_points.py ] && mv fix_compressed_points.py archive/ 2>/dev/null || true
mv regenerate_*.py archive/ 2>/dev/null || true
[ -f verify_exact_scalar_match.py ] && mv verify_exact_scalar_match.py archive/ 2>/dev/null || true
[ -f verify_fake_glv_decomposition.py ] && mv verify_fake_glv_decomposition.py archive/ 2>/dev/null || true
[ -f verify_hint.py ] && mv verify_hint.py archive/ 2>/dev/null || true
[ -f verify_hint_scalars.py ] && mv verify_hint_scalars.py archive/ 2>/dev/null || true
[ -f generate_ed25519_test_data.py ] && mv generate_ed25519_test_data.py archive/ 2>/dev/null || true
[ -f generate_second_base.py ] && mv generate_second_base.py archive/ 2>/dev/null || true
[ -f generate_test_hints.py ] && mv generate_test_hints.py archive/ 2>/dev/null || true
[ -f generate_correct_sqrt_hints.py ] && mv generate_correct_sqrt_hints.py archive/ 2>/dev/null || true
[ -f generate_dleq_for_adaptor_point.py ] && mv generate_dleq_for_adaptor_point.py archive/ 2>/dev/null || true
[ -f generate_hints_from_decompressed_points.py ] && mv generate_hints_from_decompressed_points.py archive/ 2>/dev/null || true

cd ..

echo "✅ Restructuring complete!"
echo ""
echo "Next steps:"
echo "1. Review moved files and update imports"
echo "2. Update snfoundry.toml for new test paths"
echo "3. Create AI tooling files (.cursorrules, etc.)"
echo "4. Update Rust workspace structure"
echo "5. Test everything: make test"

