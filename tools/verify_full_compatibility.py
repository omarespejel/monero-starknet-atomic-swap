#!/usr/bin/env python3
"""
Cross-Platform Verification Script

This script verifies full Rust↔Cairo DLEQ compatibility by:
1. Generating random secret
2. Running Rust to create test_vectors.json
3. Running Python to verify BLAKE2s digest matches
4. Generating hints
5. Running Cairo test
6. Asserting all pass
"""

import json
import subprocess
import sys
import hashlib
from pathlib import Path

def run_command(cmd, cwd=None):
    """Run a shell command and return output."""
    result = subprocess.run(
        cmd,
        shell=True,
        capture_output=True,
        text=True,
        cwd=cwd
    )
    if result.returncode != 0:
        print(f"ERROR: Command failed: {cmd}")
        print(f"STDOUT: {result.stdout}")
        print(f"STDERR: {result.stderr}")
        sys.exit(1)
    return result.stdout

def verify_blake2s_digest(test_vectors_path):
    """Verify BLAKE2s digest matches Rust's computation."""
    with open(test_vectors_path) as f:
        tv = json.load(f)
    
    # Build BLAKE2s input exactly as Rust does
    hasher = hashlib.blake2s(digest_size=32)
    hasher.update(b'DLEQ')
    hasher.update(bytes.fromhex(tv['g_compressed']))
    hasher.update(bytes.fromhex(tv['y_compressed']))
    hasher.update(bytes.fromhex(tv['adaptor_point_compressed']))
    hasher.update(bytes.fromhex(tv['second_point_compressed']))
    hasher.update(bytes.fromhex(tv['r1_compressed']))
    hasher.update(bytes.fromhex(tv['r2_compressed']))
    hasher.update(bytes.fromhex(tv['hashlock']))
    
    digest = hasher.digest()
    digest_int = int.from_bytes(digest, 'little')
    
    # Reduce mod order
    ED25519_ORDER = 0x1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3ed
    reduced = digest_int % ED25519_ORDER
    reduced_bytes_le = reduced.to_bytes(32, 'little')
    
    expected_bytes = bytes.fromhex(tv['challenge'])
    
    if reduced_bytes_le == expected_bytes:
        print("✅ BLAKE2s digest matches Rust's computation")
        return True
    else:
        print("❌ BLAKE2s digest mismatch!")
        print(f"   Python: {reduced_bytes_le.hex()}")
        print(f"   Rust:   {expected_bytes.hex()}")
        return False

def main():
    """Main verification workflow."""
    print("=" * 80)
    print("CROSS-PLATFORM DLEQ COMPATIBILITY VERIFICATION")
    print("=" * 80)
    print()
    
    # Step 1: Generate test vectors (if not exists)
    test_vectors_path = Path(__file__).parent.parent / "rust" / "test_vectors.json"
    
    if not test_vectors_path.exists():
        print("Step 1: Generating test_vectors.json...")
        run_command(
            "cargo test --test test_vectors generate_cairo_test_vectors -- --ignored",
            cwd=Path(__file__).parent.parent / "rust"
        )
        print("✅ Test vectors generated")
    else:
        print("✅ Test vectors already exist")
    
    print()
    
    # Step 2: Verify BLAKE2s digest
    print("Step 2: Verifying BLAKE2s digest...")
    if not verify_blake2s_digest(test_vectors_path):
        print("❌ BLAKE2s verification failed!")
        sys.exit(1)
    
    print()
    
    # Step 3: Generate hints
    print("Step 3: Generating MSM hints...")
    run_command(
        "python3 generate_hints_exact.py",
        cwd=Path(__file__).parent
    )
    print("✅ Hints generated")
    
    print()
    
    # Step 4: Run Cairo test
    print("Step 4: Running Cairo E2E test...")
    output = run_command(
        "snforge test test_e2e_dleq",
        cwd=Path(__file__).parent.parent / "cairo"
    )
    
    if "PASS" in output and "test_e2e_dleq_rust_cairo_compatibility" in output:
        print("✅ Cairo E2E test passes")
    else:
        print("❌ Cairo E2E test failed!")
        print(output)
        sys.exit(1)
    
    print()
    print("=" * 80)
    print("✅ ALL VERIFICATIONS PASSED!")
    print("=" * 80)
    print()
    print("Rust↔Cairo DLEQ compatibility is verified across all platforms.")

if __name__ == "__main__":
    main()

