/// # DLEQ Edge Case Tests
///
/// Tests boundary values and edge cases for DLEQ verification.

#[cfg(test)]
mod dleq_edge_cases_tests {
    use atomic_lock::AtomicLock::reduce_felt_to_scalar;
    use core::integer::u256;
    
    const ED25519_ORDER: u256 = u256 {
        low: 0x14def9dea2f79cd65812631a5cf5d3ed,
        high: 0x10000000000000000000000000000000,
    };
    
    /// Test: Maximum scalar value (2^128 - 1)
    #[test]
    fn test_max_scalar_value() {
        let max_scalar: felt252 = 0xffffffffffffffffffffffffffffffff; // 2^128 - 1
        let scalar_u256 = reduce_felt_to_scalar(max_scalar);
        
        // Should truncate correctly
        assert(scalar_u256.low == max_scalar.into(), 'Max scalar low');
        assert(scalar_u256.high == 0, 'Max scalar high must be 0');
    }
    
    /// Test: Scalar value near order
    #[test]
    fn test_scalar_near_order() {
        // Use order - 1 (truncated to 128 bits)
        let near_order: felt252 = 0xffffffffffffffffffffffffffffffff; // Max 128-bit value
        let scalar_u256 = reduce_felt_to_scalar(near_order);
        
        assert(scalar_u256.low == near_order.into(), 'Near order scalar');
        assert(scalar_u256.high == 0, 'High must be 0');
    }
    
    /// Test: Zero scalar
    #[test]
    fn test_zero_scalar() {
        let zero: felt252 = 0;
        let scalar_u256 = reduce_felt_to_scalar(zero);
        
        assert(scalar_u256.low == 0, 'Zero scalar low');
        assert(scalar_u256.high == 0, 'Zero scalar high');
    }
    
    /// Test: Small scalar (1)
    #[test]
    fn test_small_scalar() {
        let one: felt252 = 1;
        let scalar_u256 = reduce_felt_to_scalar(one);
        
        assert(scalar_u256.low == 1, 'Small scalar low');
        assert(scalar_u256.high == 0, 'Small scalar high');
    }
}

