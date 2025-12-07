#[cfg(test)]
mod test_scalar_debugging {
    use atomic_lock::AtomicLock;

    #[test]
    fn test_debug_scalar_values() {
        // Full response scalar from test_vectors.json (reduced scalar, LE bytes)
        // Response hex: 0xc09b9a31d72db277d1bb402e80ef5008004efaf601adbf89a8283471b5f7cf47
        // Construct from low and high parts
        let base_128: felt252 = 0x100000000000000000000000000000000; // 2^128
        let response_low: felt252 = 0xc09b9a31d72db277d1bb402e80ef5008; // Low 128 bits
        let response_high: felt252 = 0x004efaf601adbf89a8283471b5f7cf47; // High 124 bits
        let response_felt = response_low + response_high * base_128; // Full reduced scalar

        // Test reduce_felt_to_scalar (truncates to 128 bits)
        let scalar_u256 = AtomicLock::reduce_felt_to_scalar(response_felt);

        // Expected truncated values (low 128 bits only)
        let expected_low: felt252 = 0xc09b9a31d72db277d1bb402e80ef5008;

        // Verify truncation works correctly
        let scalar_low_felt: felt252 = scalar_u256.low.try_into().unwrap();
        let scalar_high_felt: felt252 = scalar_u256.high.try_into().unwrap();

        assert(scalar_low_felt == expected_low, 'response low mismatch');
        assert(scalar_high_felt == 0, 'response high must be 0');
    }

    #[test]
    fn test_debug_challenge_scalar() {
        // Full challenge scalar from test_vectors.json (reduced scalar, LE bytes)
        // Challenge hex: 0xff93d53eda6f2910e3a1313a226533c503273bfddf78f5f07036fa2a12e61262
        let base_128: felt252 = 0x100000000000000000000000000000000; // 2^128
        let challenge_low: felt252 = 0xff93d53eda6f2910e3a1313a226533c5; // Low 128 bits
        let challenge_high: felt252 = 0x03273bfddf78f5f07036fa2a12e61262; // High 124 bits
        let challenge_felt = challenge_low + challenge_high * base_128; // Full reduced scalar

        // Test reduce_felt_to_scalar (truncates to 128 bits)
        let scalar_u256 = AtomicLock::reduce_felt_to_scalar(challenge_felt);

        // Expected truncated values (low 128 bits only)
        let expected_low: felt252 = 0xff93d53eda6f2910e3a1313a226533c5;

        let scalar_low_felt: felt252 = scalar_u256.low.try_into().unwrap();
        let scalar_high_felt: felt252 = scalar_u256.high.try_into().unwrap();

        assert(scalar_low_felt == expected_low, 'challenge low mismatch');
        assert(scalar_high_felt == 0, 'challenge high must be 0');
    }
}

