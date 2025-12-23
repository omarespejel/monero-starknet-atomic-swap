"""Tests for Ed25519 → BN254 hint generation"""

import pytest
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from generate_monero_starknet_hints import (
    ed25519_scalar_to_bn254_context,
    verify_scalar_safe_for_bn254,
    ED25519_ORDER,
    BN254_PRIME,
)


class TestEd25519ToBN254Conversion:
    """Test Ed25519 → BN254 scalar conversion"""
    
    def test_ed25519_order_less_than_bn254_prime(self):
        """Fundamental safety property: Ed25519 order < BN254 prime"""
        assert ED25519_ORDER < BN254_PRIME, \
            "CRITICAL: Ed25519 order must be < BN254 prime"
    
    def test_conversion_validates_input(self):
        """Conversion should reject invalid inputs"""
        # 33 bytes - invalid
        with pytest.raises(ValueError):
            ed25519_scalar_to_bn254_context(bytes(33))
        
        # 31 bytes - invalid
        with pytest.raises(ValueError):
            ed25519_scalar_to_bn254_context(bytes(31))
    
    def test_conversion_logs_warning_for_large_scalars(self):
        """Large scalars should log warning but still convert"""
        # Near Ed25519 order (but valid after reduction)
        large_scalar = (2**251).to_bytes(32, 'little')
        
        # Should not raise
        result = ed25519_scalar_to_bn254_context(large_scalar)
        assert len(result) == 32
    
    def test_small_scalar_unchanged(self):
        """Small scalars remain unchanged after conversion"""
        small_value = 42
        scalar_bytes = small_value.to_bytes(32, 'little')
        
        result = ed25519_scalar_to_bn254_context(scalar_bytes)
        restored = int.from_bytes(result, 'little')
        
        assert restored == small_value, "Small scalars must be unchanged"
    
    def test_conversion_deterministic(self):
        """Conversion is deterministic"""
        scalar_bytes = (12345).to_bytes(32, 'little')
        
        result1 = ed25519_scalar_to_bn254_context(scalar_bytes)
        result2 = ed25519_scalar_to_bn254_context(scalar_bytes)
        
        assert result1 == result2, "Conversion must be deterministic"
    
    def test_verify_scalar_safe(self):
        """verify_scalar_safe_for_bn254 works correctly"""
        # Valid scalar (small)
        small_scalar = (100).to_bytes(32, 'little')
        assert verify_scalar_safe_for_bn254(small_scalar)
        
        # Valid scalar (near Ed25519 order, but still < BN254 prime)
        large_scalar = (ED25519_ORDER - 1).to_bytes(32, 'little')
        assert verify_scalar_safe_for_bn254(large_scalar)
        
        # Invalid scalar (>= BN254 prime) - should return False
        invalid_scalar = (BN254_PRIME).to_bytes(32, 'little')
        assert not verify_scalar_safe_for_bn254(invalid_scalar)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])

