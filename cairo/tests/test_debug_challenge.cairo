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
        low: 0x97390f51643851560e5f46ae6af8a3c9,
        high: 0x2260cdf3092329c21da25ee8c9a21f56,
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
        low: 0xd893b3476bdf09770b7616f84c5c7bbe,
        high: 0x5c79d0fa84d6440908e2e2065e60d1cd,
    };

    const TEST_VECTOR_R1_COMPRESSED: u256 = u256 {
        low: 0x3cb02521d7a17fedca11c02ea41fe334,
        high: 0x11ef09256f90d942ca7a0e4ae05926a5,
    };

    const TEST_VECTOR_R2_COMPRESSED: u256 = u256 {
        low: 0xb4fb26c272cbe6b84d65d4f908aff02f,
        high: 0xf58498fd33c0fbca066f3fdff2f49225,
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

        // Convert to u256 to extract low/high parts
        let challenge_u256: u256 = challenge.into();
        
        // Expected challenge from test_vectors.json (reduced scalar, LE bytes)
        // Challenge truncated (low 128 bits): 0x8d664bb70810bdab323a44354d98f94a
        let expected_low: u128 = 0x8d664bb70810bdab323a44354d98f94a;

        // Verify truncated challenge matches expected
        assert(challenge_u256.low == expected_low, 'Challenge mismatch');
    }
}

