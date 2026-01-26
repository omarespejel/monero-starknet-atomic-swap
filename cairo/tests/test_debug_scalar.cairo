#[cfg(test)]
mod test_scalar_debugging {
    use atomic_lock::AtomicLock;

    #[test]
    #[ignore] // Debug test - edge case conversion
    fn test_debug_scalar_values() {
        // Full response scalar from test_vectors.json (reduced scalar, LE bytes)
        // Response hex: 0x026ed77551e578013227c9b98bd25c661e741f8fec4161ea41b23ce6d007ba12
        // Construct from low and high parts
        let base_128: felt252 = 0x100000000000000000000000000000000; // 2^128
        let response_low: felt252 = 0x1e741f8fec4161ea41b23ce6d007ba12; // Low 128 bits
        let response_high: felt252 = 0x026ed77551e578013227c9b98bd25c66; // High 124 bits
        let response_felt = response_low + response_high * base_128; // Full reduced scalar

        // Test reduce_felt_to_scalar (truncates to 128 bits)
        let scalar_u256 = AtomicLock::reduce_felt_to_scalar(response_felt);

        // Expected truncated values (low 128 bits only)
        let expected_low: felt252 = 0x1e741f8fec4161ea41b23ce6d007ba12;

        // Verify truncation works correctly
        let scalar_low_felt: felt252 = scalar_u256.low.try_into().unwrap();
        let scalar_high_felt: felt252 = scalar_u256.high.try_into().unwrap();

        assert(scalar_low_felt == expected_low, 'response low mismatch');
        assert(scalar_high_felt == 0, 'response high must be 0');
    }

    #[test]
    #[ignore] // Debug test - edge case conversion
    fn test_debug_challenge_scalar() {
        // Full challenge scalar from test_vectors.json (reduced scalar, LE bytes)
        // Challenge hex: 0x000000000000000000000000000000008d664bb70810bdab323a44354d98f94a
        let base_128: felt252 = 0x100000000000000000000000000000000; // 2^128
        let challenge_low: felt252 = 0x8d664bb70810bdab323a44354d98f94a; // Low 128 bits
        let challenge_high: felt252 = 0x0; // High 124 bits
        let challenge_felt = challenge_low + challenge_high * base_128; // Full reduced scalar

        // Test reduce_felt_to_scalar (truncates to 128 bits)
        let scalar_u256 = AtomicLock::reduce_felt_to_scalar(challenge_felt);

        // Expected truncated values (low 128 bits only)
        let expected_low: felt252 = 0x8d664bb70810bdab323a44354d98f94a;

        let scalar_low_felt: felt252 = scalar_u256.low.try_into().unwrap();
        let scalar_high_felt: felt252 = scalar_u256.high.try_into().unwrap();

        assert(scalar_low_felt == expected_low, 'challenge low mismatch');
        assert(scalar_high_felt == 0, 'challenge high must be 0');
    }
}

