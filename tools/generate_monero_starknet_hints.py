#!/usr/bin/env python3
"""
Generate Garaga hints for Monero-Starknet atomic swaps.

SECURITY: Implements Ed25519 → BN254 conversion with explicit verification.
Reference: https://github.com/Lightprotocol/light-protocol/issues/237
"""

import hashlib
import json
import logging
import sys
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Curve constants
ED25519_ORDER = 2**252 + 27742317777372353535851937790883648493
BN254_PRIME = 21888242871839275222246405745257275088696311157297823662689037894645226208583

# Verify fundamental safety property at import time
assert ED25519_ORDER < BN254_PRIME, \
    "CRITICAL: Ed25519 order must be < BN254 prime for safe conversion"


def ed25519_scalar_to_bn254_context(ed25519_scalar: bytes) -> bytes:
    """
    Convert Ed25519 scalar for use in BN254 Garaga context.
    
    SECURITY NOTE:
    - Ed25519 scalar order: l ≈ 2^252
    - BN254 field prime:    p ≈ 2^254
    - Conversion is SAFE because l < p (no modular reduction needed)
    
    Args:
        ed25519_scalar: 32-byte Ed25519 scalar in little-endian
        
    Returns:
        32-byte scalar suitable for BN254 operations
        
    Raises:
        ValueError: If input is not exactly 32 bytes
    """
    if len(ed25519_scalar) != 32:
        raise ValueError(f"Expected 32 bytes, got {len(ed25519_scalar)}")
    
    scalar_int = int.from_bytes(ed25519_scalar, 'little')
    
    # Defensive check: scalar should be < Ed25519 order
    if scalar_int >= ED25519_ORDER:
        logger.warning(
            f"Scalar {scalar_int} >= Ed25519 order. "
            "This may indicate unreduced scalar input."
        )
    
    # Reduce modulo BN254 prime (usually no-op since Ed25519 order < BN254 prime)
    bn254_scalar = scalar_int % BN254_PRIME
    
    # Verify no reduction actually occurred (defense in depth)
    if bn254_scalar != scalar_int:
        logger.error(
            f"UNEXPECTED: Scalar reduced during BN254 conversion! "
            f"Original: {scalar_int}, Reduced: {bn254_scalar}"
        )
    
    return bn254_scalar.to_bytes(32, 'little')


def verify_scalar_safe_for_bn254(scalar_bytes: bytes) -> bool:
    """
    Verify a scalar is safe for BN254 operations.
    
    Returns True if scalar < BN254 prime (should always be true for Ed25519).
    """
    scalar_int = int.from_bytes(scalar_bytes, 'little')
    return scalar_int < BN254_PRIME


def generate_monero_starknet_hints(
    bob_secret: bytes,
    adaptor_point_compressed: bytes
) -> Dict[str, Any]:
    """
    Generate all hints needed for Cairo DLEQ verification.
    
    Args:
        bob_secret: Bob's secret scalar s_b (32 bytes, little-endian)
        adaptor_point_compressed: Compressed Ed25519 point T = s_b * G
    
    Returns:
        Dictionary containing all hints for Cairo verification
        
    Raises:
        ValueError: If inputs are invalid or unsafe
    """
    # Validate inputs
    if len(bob_secret) != 32:
        raise ValueError(f"bob_secret must be 32 bytes, got {len(bob_secret)}")
    
    # SECURITY: Verify scalar is safe for BN254
    if not verify_scalar_safe_for_bn254(bob_secret):
        raise ValueError("SECURITY: bob_secret is not safe for BN254 conversion")
    
    # 1. Compute hashlock
    hashlock = hashlib.sha256(bob_secret).digest()
    
    # 2. Convert Ed25519 scalar to BN254 context
    bn254_scalar = ed25519_scalar_to_bn254_context(bob_secret)
    
    # 3. Generate Garaga hints (if available)
    try:
        from garaga.hints import io
        from garaga.definitions import CURVES, CurveID
        
        curve = CURVES[CurveID.BN254]
        scalar_decomp = io.decompose_scalar_to_limbs(bn254_scalar, curve)
        
        msm_hint = io.generate_msm_hint(
            scalars=[bn254_scalar],
            points=[curve.G],
            curve_id=CurveID.BN254
        )
        
        derive_hints = io.generate_derive_point_hints(
            points=[curve.G],
            curve_id=CurveID.BN254
        )
        
        garaga_available = True
        
    except ImportError:
        logger.warning("Garaga not installed. Using stub hints.")
        scalar_decomp = {"stub": True, "warning": "Garaga not available"}
        msm_hint = {"stub": True}
        derive_hints = {"stub": True}
        garaga_available = False
    
    return {
        "scalar_decomposition": scalar_decomp,
        "msm_hint": msm_hint,
        "derive_hints": derive_hints,
        "hashlock": hashlock.hex(),
        "adaptor_point": adaptor_point_compressed.hex(),
        "bn254_scalar": bn254_scalar.hex(),
        "bn254_compatible": True,
        "garaga_available": garaga_available,
        "security_checks": {
            "ed25519_order_lt_bn254_prime": ED25519_ORDER < BN254_PRIME,
            "scalar_lt_bn254_prime": verify_scalar_safe_for_bn254(bob_secret),
        }
    }


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python generate_monero_starknet_hints.py <test_vector.json>")
        sys.exit(1)
    
    with open(sys.argv[1]) as f:
        vector = json.load(f)
    
    hints = generate_monero_starknet_hints(
        bytes.fromhex(vector["secret"]),
        bytes.fromhex(vector.get("adaptor_point_compressed", "00" * 32))
    )
    
    print(json.dumps(hints, indent=2, default=str))

