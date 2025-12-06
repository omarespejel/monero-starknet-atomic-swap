/// Test _verify_dleq_proof in isolation to compare with constructor context
/// This helps identify if the error is in parameter passing or MSM context

#[cfg(test)]
mod verify_dleq_proof_isolation_tests {
    use atomic_lock::blake2s_challenge::compute_dleq_challenge_blake2s;
    use core::array::ArrayTrait;
    use core::integer::u256;
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::G1PointTrait;
    use atomic_lock::AtomicLock::is_small_order_ed25519;
    use atomic_lock::AtomicLock::_verify_dleq_proof;
    
    const ED25519_CURVE_INDEX: u32 = 4;
    const ED25519_ORDER: u256 = u256 {
        low: 0x14def9dea2f79cd65812631a5cf5d3ed,
        high: 0x10000000000000000000000000000000,
    };

    // Test vector constants (from test_e2e_dleq.cairo)
    const TEST_ADAPTOR_POINT_COMPRESSED: u256 = u256 {
        low: 0x54e86953e7cc99b545cfef03f63cce85,
        high: 0x427dde0adb325f957d29ad71e4643882,
    };
    const TEST_ADAPTOR_POINT_SQRT_HINT: u256 = u256 {
        low: 0x448c18dcf34127e112ff945a65defbfc,
        high: 0x17611da35f39a2a5e3a9fddb8d978e4f,
    };

    const TEST_SECOND_POINT_COMPRESSED: u256 = u256 {
        low: 0xd893b3476bdf09770b7616f84c5c7bbe,
        high: 0x5c79d0fa84d6440908e2e2065e60d1cd,
    };
    const TEST_SECOND_POINT_SQRT_HINT: u256 = u256 {
        low: 0xdcad2173817c163b5405cec7698eb4b8,
        high: 0x742bb3c44b13553c8ddff66565b44cac,
    };

    const TEST_R1_COMPRESSED: u256 = u256 {
        low: 0x47cff7b5713428a889bfad01f6fa4e00,
        high: 0x0850ef802e40bbd177b22dd7319a9bc0,
    };
    const TEST_R1_SQRT_HINT: u256 = u256 {
        low: 0x9f3ee81fe68dcbcf9de661eedd114a9e,
        high: 0x397c8b3280ddfb2ffe72518d79cc504c,
    };

    const TEST_R2_COMPRESSED: u256 = u256 {
        low: 0x47cff7b5713428a889bfad01f6fa4e00,
        high: 0x0850ef802e40bbd177b22dd7319a9bc0,
    };
    const TEST_R2_SQRT_HINT: u256 = u256 {
        low: 0x9f3ee81fe68dcbcf9de661eedd114a9e,
        high: 0x397c8b3280ddfb2ffe72518d79cc504c,
    };

    const ED25519_BASE_POINT_COMPRESSED: u256 = u256 {
        low: 0x66666666666666666666666666666666,
        high: 0x58666666666666666666666666666666,
    };

    const ED25519_SECOND_GENERATOR_COMPRESSED: u256 = u256 {
        low: 0x0e5f46ae6af8a3c997390f5164385156,
        high: 0x5b0e5f46ae6af8a3c997390f51643851,
    };

    const TEST_VECTOR_HASHLOCK: [u32; 8] = [
        0x81caacb6_u32, 0x859a93a0_u32, 0xc4e4356c_u32, 0xb9958e18_u32,
        0xb1aa3117_u32, 0x4c9a62d4_u32, 0x09dd79ee_u32, 0x94fcd4de_u32,
    ];

    #[test]
    fn test_verify_dleq_proof_in_isolation() {
        // Decompress points (matching constructor)
        let adaptor_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_ADAPTOR_POINT_SQRT_HINT
        );
        let adaptor = adaptor_result.unwrap();
        adaptor.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(!is_small_order_ed25519(adaptor), 'Adaptor small order');

        let second_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_SECOND_POINT_COMPRESSED,
            TEST_SECOND_POINT_SQRT_HINT
        );
        let second = second_result.unwrap();
        second.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(!is_small_order_ed25519(second), 'Second small order');

        // Compute challenge (matching constructor)
        let hashlock = TEST_VECTOR_HASHLOCK.span();
        let challenge = compute_dleq_challenge_blake2s(
            ED25519_BASE_POINT_COMPRESSED,
            ED25519_SECOND_GENERATOR_COMPRESSED,
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_SECOND_POINT_COMPRESSED,
            TEST_R1_COMPRESSED,
            TEST_R2_COMPRESSED,
            hashlock,
            ED25519_ORDER,
        );

        // Get response (from test_e2e_dleq.cairo)
        // Response is reconstructed from low + high * 2^128
        const RESPONSE_LOW: felt252 = 0x47cff7b5713428a889bfad01f6fa4e00;
        const RESPONSE_HIGH: felt252 = 0x0850ef802e40bbd177b22dd7319a9bc0;
        const BASE_128: felt252 = 0x100000000000000000000000000000000;
        let response = RESPONSE_LOW + RESPONSE_HIGH * BASE_128;

        // Get hints (from test_e2e_dleq.cairo)
        let (s_hint_for_g, s_hint_for_y, c_neg_hint_for_t, c_neg_hint_for_u) = get_real_msm_hints();

        // Call _verify_dleq_proof directly (matching constructor call)
        _verify_dleq_proof(
            adaptor,
            second,
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_SECOND_POINT_COMPRESSED,
            TEST_R1_COMPRESSED,
            TEST_R2_COMPRESSED,
            hashlock,
            challenge,
            response,
            s_hint_for_g,
            s_hint_for_y,
            c_neg_hint_for_t,
            c_neg_hint_for_u,
        );

        // If we get here, _verify_dleq_proof works in isolation
        assert(true, 'verify_dleq_proof OK');
    }

    fn get_real_msm_hints() -> (Span<felt252>, Span<felt252>, Span<felt252>, Span<felt252>) {
        // Exact hints from test_e2e_dleq.cairo
        let s_hint_for_g = array![
            0xd21de05d0b4fe220a6fcca9b,
            0xa8e827ce9b59e1a5770bd9a,
            0x4e14ea0d8a7581a1,
            0x0,
            0x8cfb1d3e412e174d0ad03ad4,
            0x4417fe7cc6824de3b328f2a0,
            0x13f6f393b443ac08,
            0x0,
            0x1fd0f994a4c11a4543d86f4578e7b9ed,
            0x39099b31d1013f73ec51ebd61fdfe2ab
        ].span();

        let s_hint_for_y = array![
            0xcdb4e41a66188ec060e0e45b,
            0x1cf0f0ff51495823cad8d964,
            0x2dcda3d3bbeda8a3,
            0x0,
            0x8b8b33d4304cc1bedc45545c,
            0x5fbf8dbd7bd2029ba859c5bb,
            0x145b0ef370c62319,
            0x0,
            0x1fd0f994a4c11a4543d86f4578e7b9ed,
            0x39099b31d1013f73ec51ebd61fdfe2ab
        ].span();

        let c_neg_hint_for_t = array![
            0x959983489a84cf6bb55fde22,
            0xfbea3c47483b8fb99b0e29ef,
            0x3fe816922486f803,
            0x0,
            0x406a020256217f7a00633c4a,
            0x6b9be390479e99c682cae8f0,
            0x7b48b6a59c2c6732,
            0x0,
            0x208a4ac47d492a7b82475d0c0c798e52,
            0x29c3b379b559be107e5c78bb9abb6515
        ].span();

        let c_neg_hint_for_u = array![
            0x6bea23ab976cb56319ceb69d,
            0xba4983a65676829fc603f500,
            0x65b0b083f90952f1,
            0x0,
            0x7e7a6ae6e23418c184e6d824,
            0x119cf240405f414ec4ed2cc6,
            0x15cea0344fcb9e58,
            0x0,
            0x208a4ac47d492a7b82475d0c0c798e52,
            0x29c3b379b559be107e5c78bb9abb6515
        ].span();

        (s_hint_for_g, s_hint_for_y, c_neg_hint_for_t, c_neg_hint_for_u)
    }
}

