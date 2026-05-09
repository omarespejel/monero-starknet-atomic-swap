#[cfg(test)]
mod test_scalar_debugging {
    use atomic_lock::AtomicLock;

    #[test]
    fn test_debug_scalar_values() {
        // Full response scalar from test_vectors.json (reduced scalar, LE bytes)
        let base_128: felt252 = 0x100000000000000000000000000000000; // 2^128
        let response_low: felt252 = 0xbe3ffdd10e06b50b800feb45877b787b;
        let response_high: felt252 = 0x2f0ceba8a8c56d6f6b4ed3ae98db234;
        let response_felt = response_low + response_high * base_128; // Full reduced scalar

        // Test reduce_felt_to_scalar preserves the full felt before reducing modulo Ed25519 order.
        let scalar_u256 = AtomicLock::reduce_felt_to_scalar(response_felt);

        let scalar_low_felt: felt252 = scalar_u256.low.try_into().unwrap();
        let scalar_high_felt: felt252 = scalar_u256.high.try_into().unwrap();

        assert(scalar_low_felt == response_low, 'response low mismatch');
        assert(scalar_high_felt == response_high, 'response high mismatch');
    }

    #[test]
    fn test_debug_challenge_scalar() {
        // Full challenge scalar from test_vectors.json (reduced scalar, LE bytes)
        let base_128: felt252 = 0x100000000000000000000000000000000; // 2^128
        let challenge_low: felt252 = 0xcc6570f8be11819d2268bb024f816108;
        let challenge_high: felt252 = 0x47c760eb9b6a8797680bef6218e06aa;
        let challenge_felt = challenge_low + challenge_high * base_128; // Full reduced scalar

        // Test reduce_felt_to_scalar preserves the full felt before reducing modulo Ed25519 order.
        let scalar_u256 = AtomicLock::reduce_felt_to_scalar(challenge_felt);

        let scalar_low_felt: felt252 = scalar_u256.low.try_into().unwrap();
        let scalar_high_felt: felt252 = scalar_u256.high.try_into().unwrap();

        assert(scalar_low_felt == challenge_low, 'challenge low mismatch');
        assert(scalar_high_felt == challenge_high, 'challenge high mismatch');
    }
}
