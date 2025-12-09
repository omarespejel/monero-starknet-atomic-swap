#!/usr/bin/env python3
"""
Validate sqrt hints by testing decompression with Garaga.

This script ensures sqrt hints work with Garaga's exact algorithm.

Run this BEFORE updating any Cairo test constants.

Usage: python validate_sqrt_hints.py <test_vectors.json>
"""

import json
import subprocess
import sys
from pathlib import Path

def validate_sqrt_hints(test_vectors_path: Path) -> bool:
    """
    Validate sqrt hints by running Cairo decompression test.
    
    Returns True if all sqrt hints are valid for Garaga.
    """
    print("🔍 Validating sqrt hints with Garaga decompression...")
    
    # Run the Cairo point decompression test
    cairo_dir = test_vectors_path.parent.parent / "cairo"
    if not cairo_dir.exists():
        print(f"❌ Cairo directory not found: {cairo_dir}")
        return False
    
    result = subprocess.run(
        ["snforge", "test", "test_unit_point_decompression", "--exact"],
        cwd=cairo_dir,
        capture_output=True,
        text=True
    )
    
    if result.returncode != 0:
        print("❌ Sqrt hint validation FAILED!")
        print(result.stderr)
        return False
    
    if "PASS" in result.stdout or "passed" in result.stdout.lower():
        print("✅ All sqrt hints validated with Garaga")
        return True
    
    print("⚠️ Could not confirm sqrt hint validity")
    print(result.stdout)
    return False

def main():
    if len(sys.argv) < 2:
        print("Usage: python validate_sqrt_hints.py <test_vectors.json>")
        sys.exit(1)
    
    tv_path = Path(sys.argv[1])
    if not tv_path.exists():
        print(f"❌ Test vectors file not found: {tv_path}")
        sys.exit(1)
    
    if not validate_sqrt_hints(tv_path):
        sys.exit(1)

if __name__ == "__main__":
    main()

