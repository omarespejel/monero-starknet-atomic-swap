#[cfg(test)]
mod print_challenge_tests {
    use atomic_lock::poseidon_challenge::compute_dleq_challenge_poseidon;
    use core::array::ArrayTrait;
    use core::integer::u256;

    // Constants from lib.cairo (must match exactly)
    const ED25519_BASE_POINT_COMPRESSED: u256 = u256 {
        low: 0x66666666666666666666666666666658,
        high: 0x66666666666666666666666666666666,
    };

    const ED25519_SECOND_GENERATOR_COMPRESSED: u256 = u256 {
        low: 0x21ba32594950b67cf0d8bb8c8ac5e8c7,
        high: 0xf08df421a3209ab6373dd0ec7ef25dfd,
    };

    const ED25519_ORDER: u256 = u256 {
        low: 0x14def9dea2f79cd65812631a5cf5d3ed,
        high: 0x10000000000000000000000000000000,
    };

    // Test vectors from test_vectors.json
    const TEST_VECTOR_T_COMPRESSED: u256 = u256 {
        low: 0x54e86953e7cc99b545cfef03f63cce85,
        high: 0x427dde0adb325f957d29ad71e4643882,
    };

    const TEST_VECTOR_U_COMPRESSED: u256 = u256 {
        low: 0x9244eb3a3699efed3106c6ae0afdf28,
        high: 0xb6e0bfc0d9fbb8a4c8ef08cb5da2eff3,
    };

    const TEST_VECTOR_R1_COMPRESSED: u256 = u256 {
        low: 0x3cb02521d7a17fedca11c02ea41fe334,
        high: 0x11ef09256f90d942ca7a0e4ae05926a5,
    };

    const TEST_VECTOR_R2_COMPRESSED: u256 = u256 {
        low: 0xe66ca975ef303c032fcc18a952325162,
        high: 0xc5d2eb608176c8b79dfa55289c35b35f,
    };

    const TESTVECTOR_HASHLOCK: [u32; 8] = [
        0xb6acca81_u32,
        0xa0939a85_u32,
        0x6c35e4c4_u32,
        0x188e95b9_u32,
        0x1731aab1_u32,
        0xd4629a4c_u32,
        0xee79dd09_u32,
        0xded4fc94_u32,
    ];

    #[test]
    fn test_print_computed_challenge() {
        let hashlock = TESTVECTOR_HASHLOCK.span();

        let challenge = compute_dleq_challenge_poseidon(
            ED25519_BASE_POINT_COMPRESSED,
            ED25519_SECOND_GENERATOR_COMPRESSED, // From lib.cairo
            TEST_VECTOR_T_COMPRESSED,
            TEST_VECTOR_U_COMPRESSED,
            TEST_VECTOR_R1_COMPRESSED,
            TEST_VECTOR_R2_COMPRESSED,
            hashlock,
            ED25519_ORDER,
        );

        // Expected challenge from test_vectors.json (reduced scalar, LE bytes)
        // Challenge full (full scalar): 0x47c760eb9b6a8797680bef6218e06aacc6570f8be11819d2268bb024f816108
        let expected_challenge: felt252 = 0x47c760eb9b6a8797680bef6218e06aacc6570f8be11819d2268bb024f816108;

        // Verify full challenge matches expected
        assert(challenge == expected_challenge, 'Challenge mismatch');
    }
}
