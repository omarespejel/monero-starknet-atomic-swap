#[cfg(test)]
mod test_scalar_debugging {
    use atomic_lock::AtomicLock;

    #[test]
    fn test_debug_scalar_values() {
        // Full response scalar from test_vectors.json
        // Response hex: 0850ef802e40bbd177b22dd7319a9bc047cff7b5713428a889bfad01f6fa4e00
        // Construct from low and high parts
        let base_128: felt252 = 0x100000000000000000000000000000000; // 2^128
        let response_low: felt252 = 0x47cff7b5713428a889bfad01f6fa4e00; // Low 128 bits
        let response_high: felt252 = 0x0850ef802e40bbd177b22dd7319a9bc0; // High 124 bits
        let response_felt = response_low + response_high * base_128; // Full reduced scalar

        // Test reduce_felt_to_scalar
        let scalar_u256 = AtomicLock::reduce_felt_to_scalar(response_felt);

        // Verify scalar extraction matches Python ground truth
        // Expected values calculated in tools/verify_exact_scalar_match.py

        // Expected values (calculated in Python)
        // response % order = 0x0850ef802e40bbd177b22dd7319a9bc047cff7b5713428a889bfad01f6fa4e00
        // scalar.low  = 0x47cff7b5713428a889bfad01f6fa4e00
        // scalar.high = 0x0850ef802e40bbd177b22dd7319a9bc0
        let expected_low: felt252 = 0x47cff7b5713428a889bfad01f6fa4e00;
        let expected_high: felt252 = 0x0850ef802e40bbd177b22dd7319a9bc0;

        // Verify it matches Python calculation
        let scalar_low_felt: felt252 = scalar_u256.low.try_into().unwrap();
        let scalar_high_felt: felt252 = scalar_u256.high.try_into().unwrap();

        assert(scalar_low_felt == expected_low, 'low mismatch');
        assert(scalar_high_felt == expected_high, 'high mismatch');
    }

    #[test]
    fn test_debug_challenge_scalar() {
        // Full challenge scalar from test_vectors.json
        // Challenge hex: c53365223a31a1e310296fda3ed593ff6212e6122afa3670f0f578dffd3b2703
        // Reduced mod order: 0x053365223a31a1e310296fda3ed593fe679f2fa2875edc64d018d3a3a1b537e7
        let base_128: felt252 = 0x100000000000000000000000000000000; // 2^128
        let challenge_low: felt252 = 0x679f2fa2875edc64d018d3a3a1b537e7; // Low 128 bits
        let challenge_high: felt252 = 0x053365223a31a1e310296fda3ed593fe; // High 124 bits
        let challenge_felt = challenge_low + challenge_high * base_128; // Full reduced scalar

        // Test reduce_felt_to_scalar
        let scalar_u256 = AtomicLock::reduce_felt_to_scalar(challenge_felt);

        // Expected values
        let expected_low: felt252 = 0x679f2fa2875edc64d018d3a3a1b537e7;
        let expected_high: felt252 = 0x053365223a31a1e310296fda3ed593fe;

        let scalar_low_felt: felt252 = scalar_u256.low.try_into().unwrap();
        let scalar_high_felt: felt252 = scalar_u256.high.try_into().unwrap();

        assert(scalar_low_felt == expected_low, 'challenge low mismatch');
        assert(scalar_high_felt == expected_high, 'challenge high mismatch');
    }
}

