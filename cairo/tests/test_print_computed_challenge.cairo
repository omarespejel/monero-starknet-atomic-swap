#[cfg(test)]
mod print_challenge_tests {
    use atomic_lock::blake2s_challenge::compute_dleq_challenge_blake2s;
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
        low: 0x90b1ab352981d43ec51fba0af7ab51c7,
        high: 0xc21ebc88e5e59867b280909168338026,
    };

    const TEST_VECTOR_R2_COMPRESSED: u256 = u256 {
        low: 0x02d386e8fd6bd85a339171211735bcba,
        high: 0x10defc0130a9f3055798b1f5a99aeb67,
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

        let challenge = compute_dleq_challenge_blake2s(
            ED25519_BASE_POINT_COMPRESSED,
            ED25519_SECOND_GENERATOR_COMPRESSED, // From lib.cairo
            TEST_VECTOR_T_COMPRESSED,
            TEST_VECTOR_U_COMPRESSED,
            TEST_VECTOR_R1_COMPRESSED,
            TEST_VECTOR_R2_COMPRESSED,
            hashlock,
            ED25519_ORDER,
        );

        // Truncate to 128 bits (what MSM uses)
        let challenge_low: u128 = challenge.try_into().unwrap_or(0);

        // Expected truncated challenge from test_vectors.json
        let expected_low: u128 = 0x6212e6122afa3670f0f578dffd3b2703;

        // Compare - if mismatch, the test will fail and show values
        // This helps debug what challenge Cairo actually computes
        assert(challenge_low == expected_low, 'Mismatch');
    }
}

