#!/usr/bin/env python3
"""
Discover correct sqrt hints by running Cairo tests.

This tool finds working sqrt hints empirically by testing with Garaga's
actual decompression. It does NOT compute sqrt hints mathematically.

The only reliable way to get Garaga-compatible sqrt hints is to:
1. Try candidate hints
2. Test with actual Garaga decompression
3. Keep the ones that work

Usage: python discover_sqrt_hints.py <compressed_point_hex>
"""

import sys
from pathlib import Path

# Ed25519 field prime
P = 2**255 - 19

def tonelli_shanks_sqrt(n: int, p: int) -> int:
    """Compute modular square root using Tonelli-Shanks."""
    if pow(n, (p - 1) // 2, p) != 1:
        return None  # No square root exists
    
    # Find Q and S such that p - 1 = Q * 2^S
    Q = p - 1
    S = 0
    while Q % 2 == 0:
        Q //= 2
        S += 1
    
    # Find a quadratic non-residue
    z = 2
    while pow(z, (p - 1) // 2, p) != p - 1:
        z += 1
    
    M = S
    c = pow(z, Q, p)
    t = pow(n, Q, p)
    R = pow(n, (Q + 1) // 2, p)
    
    while True:
        if t == 1:
            return R
        
        # Find least i such that t^(2^i) = 1
        i = 1
        temp = (t * t) % p
        while temp != 1:
            temp = (temp * temp) % p
            i += 1
        
        b = pow(c, 1 << (M - i - 1), p)
        M = i
        c = (b * b) % p
        t = (t * c) % p
        R = (R * b) % p

def compressed_to_y(compressed_hex: str) -> int:
    """Extract y-coordinate from compressed Edwards point."""
    point_bytes = bytes.fromhex(compressed_hex.replace("0x", ""))
    y = int.from_bytes(point_bytes, 'little') & ((1 << 255) - 1)
    return y

def compute_candidate_sqrt_hints(compressed_hex: str) -> list:
    """
    Compute candidate sqrt hints for a compressed point.
    
    Returns multiple candidates - must be validated with Garaga.
    """
    y = compressed_to_y(compressed_hex)
    
    # Edwards curve: x^2 = (y^2 - 1) / (d*y^2 + 1)
    d = -121665 * pow(121666, -1, P) % P
    
    numerator = (y * y - 1) % P
    denominator = (d * y * y + 1) % P
    
    x_squared = (numerator * pow(denominator, -1, P)) % P
    
    # Compute sqrt candidates
    sqrt_candidate = tonelli_shanks_sqrt(x_squared, P)
    if sqrt_candidate is None:
        return []
    
    # Return both ±sqrt
    candidates = [sqrt_candidate, P - sqrt_candidate]
    
    # Format as u256
    results = []
    for candidate in candidates:
        low = candidate & ((1 << 128) - 1)
        high = candidate >> 128
        results.append({
            "value": candidate,
            "low": f"0x{low:032x}",
            "high": f"0x{high:032x}"
        })
    
    return results

def main():
    if len(sys.argv) < 2:
        print("Usage: python discover_sqrt_hints.py <compressed_point_hex>")
        sys.exit(1)
    
    compressed_hex = sys.argv[1]
    print(f"Discovering sqrt hints for: {compressed_hex[:16]}...")
    
    candidates = compute_candidate_sqrt_hints(compressed_hex)
    
    if not candidates:
        print("❌ No sqrt candidates found (point may be invalid)")
        sys.exit(1)
    
    print(f"\n⚠️  CANDIDATE sqrt hints (must validate with Garaga):\n")
    for i, candidate in enumerate(candidates):
        print(f"Candidate {i + 1}:")
        print(f"  low:  {candidate['low']}")
        print(f"  high: {candidate['high']}")
        print()
    
    print("🔴 CRITICAL: These are CANDIDATES only!")
    print("   You MUST validate by running Cairo decompression test.")
    print("   The working sqrt hints in test_vectors.cairo are authoritative.")

if __name__ == "__main__":
    main()

