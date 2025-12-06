/// Step-by-step constructor flow test to isolate where the error occurs
/// This mimics the exact constructor flow but with validation after each step

#[cfg(test)]
mod constructor_step_by_step_tests {
    use atomic_lock::blake2s_challenge::compute_dleq_challenge_blake2s;
    use core::array::ArrayTrait;
    use core::integer::u256;
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::{msm_g1, G1PointTrait, ec_safe_add};
    use garaga::definitions::get_G;
    use atomic_lock::AtomicLock::reduce_felt_to_scalar;

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
        low: 0x90b1ab352981d43ec51fba0af7ab51c7,
        high: 0xc21ebc88e5e59867b280909168338026,
    };
    const TEST_R1_SQRT_HINT: u256 = u256 {
        low: 0x72a9698d3171817c239f4009cc36fc97,
        high: 0x3f2b84592a9ee701d24651e3aa3c837d,
    };
    const TEST_R2_COMPRESSED: u256 = u256 {
        low: 0x02d386e8fd6bd85a339171211735bcba,
        high: 0x10defc0130a9f3055798b1f5a99aeb67,
    };
    const TEST_R2_SQRT_HINT: u256 = u256 {
        low: 0x43f2c451f9ca69ff1577d77d646a50e,
        high: 0x4ee64b0e07d89e906f9e8b7bea09283e,
    };
    const ED25519_BASE_POINT_COMPRESSED: u256 = u256 {
        low: 0x66666666666666666666666666666666,
        high: 0x58666666666666666666666666666666,
    };
    const ED25519_SECOND_GENERATOR_COMPRESSED: u256 = u256 {
        low: 0x0e5f46ae6af8a3c997390f5164385156,
        high: 0x1da25ee8c9a21f562260cdf3092329c2,
    };
    const TEST_VECTOR_HASHLOCK: [u32; 8] = [
        0x81caacb6_u32, 0x859a93a0_u32, 0xc4e4356c_u32, 0xb9958e18_u32,
        0xb1aa3117_u32, 0x4c9a62d4_u32, 0x09dd79ee_u32, 0x94fcd4de_u32,
    ];
    const BASE_128: felt252 = 0x100000000000000000000000000000000;
    const RESPONSE_LOW: felt252 = 0x47cff7b5713428a889bfad01f6fa4e00;
    const RESPONSE_HIGH: felt252 = 0x0850ef802e40bbd177b22dd7319a9bc0;
    const CHALLENGE_FELT: felt252 = 0x6212e6122afa3670f0f578dffd3b2703;

    fn get_test_dleq_response() -> felt252 {
        RESPONSE_LOW + RESPONSE_HIGH * BASE_128
    }

    fn get_real_msm_hints() -> (Span<felt252>, Span<felt252>, Span<felt252>, Span<felt252>) {
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

    #[test]
    fn test_step1_decompress_all_points() {
        // Step 1: Decompress all 4 points (matching constructor)
        let adaptor_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_ADAPTOR_POINT_SQRT_HINT
        );
        assert(adaptor_result.is_some(), 'Step 1a: adaptor decompress');
        let adaptor = adaptor_result.unwrap();
        adaptor.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);

        let second_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_SECOND_POINT_COMPRESSED,
            TEST_SECOND_POINT_SQRT_HINT
        );
        assert(second_result.is_some(), 'Step 1b: second decompress');
        let second = second_result.unwrap();
        second.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);

        let r1_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_R1_COMPRESSED,
            TEST_R1_SQRT_HINT
        );
        assert(r1_result.is_some(), 'Step 1c: R1 decompress');
        let r1 = r1_result.unwrap();
        r1.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);

        let r2_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_R2_COMPRESSED,
            TEST_R2_SQRT_HINT
        );
        assert(r2_result.is_some(), 'Step 1d: R2 decompress');
        let r2 = r2_result.unwrap();
        r2.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);

        // All points decompressed successfully
        assert(true, 'Step 1: All points OK');
    }

    #[test]
    fn test_step2_compute_challenge() {
        // Step 2: Compute challenge (matching constructor)
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
        // Challenge computed successfully (just verify it's non-zero)
        assert(challenge != 0, 'Step 2: Challenge computed');
    }

    #[test]
    fn test_step3a_msm_sg_only() {
        // Isolate: Test only s·G MSM call
        // Use EXACT same approach as test_garaga_msm_all_calls (which works)
        let G = get_G(ED25519_CURVE_INDEX);
        // Use direct truncated scalar (matching working test)
        let s_scalar = u256 {
            low: RESPONSE_LOW.try_into().unwrap(),
            high: 0
        };
        // Use hardcoded hint (matching test_garaga_msm_all_calls which works)
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
        
        let sG = msm_g1(
            array![G].span(),
            array![s_scalar].span(),
            ED25519_CURVE_INDEX,
            s_hint_for_g
        );
        sG.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(true, 'Step 3a: sG OK');
    }

    #[test]
    fn test_step3b_msm_negct_only() {
        // Isolate: Test only (-c)·T MSM call
        let adaptor = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_ADAPTOR_POINT_SQRT_HINT
        ).unwrap();
        let challenge = CHALLENGE_FELT;
        let c_scalar = reduce_felt_to_scalar(challenge);
        let c_neg_scalar = (ED25519_ORDER - (c_scalar % ED25519_ORDER)) % ED25519_ORDER;
        let (_, _, c_neg_hint_for_t, _) = get_real_msm_hints();
        
        let neg_cT = msm_g1(
            array![adaptor].span(),
            array![c_neg_scalar].span(),
            ED25519_CURVE_INDEX,
            c_neg_hint_for_t
        );
        neg_cT.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(true, 'Step 3b: -cT OK');
    }

    #[test]
    fn test_step3c_msm_sy_only() {
        // Isolate: Test only s·Y MSM call
        // Use EXACT same approach as test_garaga_msm_all_calls (which works)
        let G = get_G(ED25519_CURVE_INDEX);
        let Y = ec_safe_add(G, G, ED25519_CURVE_INDEX);
        // Use direct truncated scalar (matching working test)
        let s_scalar = u256 {
            low: RESPONSE_LOW.try_into().unwrap(),
            high: 0
        };
        // Use hardcoded hint (matching test_garaga_msm_all_calls which works)
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
        
        let sY = msm_g1(
            array![Y].span(),
            array![s_scalar].span(),
            ED25519_CURVE_INDEX,
            s_hint_for_y
        );
        sY.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(true, 'Step 3c: sY OK');
    }

    #[test]
    fn test_step3d_msm_negcu_only() {
        // Isolate: Test only (-c)·U MSM call
        let second = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_SECOND_POINT_COMPRESSED,
            TEST_SECOND_POINT_SQRT_HINT
        ).unwrap();
        let challenge = CHALLENGE_FELT;
        let c_scalar = reduce_felt_to_scalar(challenge);
        let c_neg_scalar = (ED25519_ORDER - (c_scalar % ED25519_ORDER)) % ED25519_ORDER;
        let (_, _, _, c_neg_hint_for_u) = get_real_msm_hints();
        
        let neg_cU = msm_g1(
            array![second].span(),
            array![c_neg_scalar].span(),
            ED25519_CURVE_INDEX,
            c_neg_hint_for_u
        );
        neg_cU.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(true, 'Step 3d: -cU OK');
    }

    #[test]
    fn test_step3_all_msm_calls() {
        // Step 3: Execute all MSM calls in sequence (matching _verify_dleq_proof)
        // Decompress points
        let adaptor = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_ADAPTOR_POINT_SQRT_HINT
        ).unwrap();
        let second = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_SECOND_POINT_COMPRESSED,
            TEST_SECOND_POINT_SQRT_HINT
        ).unwrap();

        // Get base points
        let G = get_G(ED25519_CURVE_INDEX);
        let Y = ec_safe_add(G, G, ED25519_CURVE_INDEX);  // Y = 2·G

        // Compute scalars
        let response = get_test_dleq_response();
        let challenge = CHALLENGE_FELT;
        let c_scalar = reduce_felt_to_scalar(challenge);
        let s_scalar = reduce_felt_to_scalar(response);
        let c_neg_scalar = (ED25519_ORDER - (c_scalar % ED25519_ORDER)) % ED25519_ORDER;

        // Get hints
        let (s_hint_for_g, s_hint_for_y, c_neg_hint_for_t, c_neg_hint_for_u) = get_real_msm_hints();

        // MSM call 1: s·G
        let sG = msm_g1(
            array![G].span(),
            array![s_scalar].span(),
            ED25519_CURVE_INDEX,
            s_hint_for_g
        );
        sG.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(true, 'Step 3a: sG OK');

        // MSM call 2: (-c)·T
        let neg_cT = msm_g1(
            array![adaptor].span(),
            array![c_neg_scalar].span(),
            ED25519_CURVE_INDEX,
            c_neg_hint_for_t
        );
        neg_cT.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(true, 'Step 3b: -cT OK');

        // MSM call 3: s·Y
        let sY = msm_g1(
            array![Y].span(),
            array![s_scalar].span(),
            ED25519_CURVE_INDEX,
            s_hint_for_y
        );
        sY.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(true, 'Step 3c: sY OK');

        // MSM call 4: (-c)·U
        let neg_cU = msm_g1(
            array![second].span(),
            array![c_neg_scalar].span(),
            ED25519_CURVE_INDEX,
            c_neg_hint_for_u
        );
        neg_cU.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(true, 'Step 3d: -cU OK');

        // All MSM calls succeeded
        assert(true, 'Step 3: All MSM OK');
    }

    #[test]
    fn test_step4_full_flow() {
        // Step 4: Full flow combining all steps
        // This mimics the exact constructor flow
        
        // Decompress all points
        let adaptor = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_ADAPTOR_POINT_SQRT_HINT
        ).unwrap();
        let second = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_SECOND_POINT_COMPRESSED,
            TEST_SECOND_POINT_SQRT_HINT
        ).unwrap();
        let _r1 = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_R1_COMPRESSED,
            TEST_R1_SQRT_HINT
        ).unwrap();
        let _r2 = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_R2_COMPRESSED,
            TEST_R2_SQRT_HINT
        ).unwrap();

        // Compute challenge
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

        // Get base points
        let G = get_G(ED25519_CURVE_INDEX);
        let Y = ec_safe_add(G, G, ED25519_CURVE_INDEX);

        // Compute scalars
        let response = get_test_dleq_response();
        let c_scalar = reduce_felt_to_scalar(challenge);
        let s_scalar = reduce_felt_to_scalar(response);
        let c_neg_scalar = (ED25519_ORDER - (c_scalar % ED25519_ORDER)) % ED25519_ORDER;

        // Get hints
        let (s_hint_for_g, s_hint_for_y, c_neg_hint_for_t, c_neg_hint_for_u) = get_real_msm_hints();

        // Execute all MSM calls
        let _sG = msm_g1(
            array![G].span(),
            array![s_scalar].span(),
            ED25519_CURVE_INDEX,
            s_hint_for_g
        );
        let _neg_cT = msm_g1(
            array![adaptor].span(),
            array![c_neg_scalar].span(),
            ED25519_CURVE_INDEX,
            c_neg_hint_for_t
        );
        let _sY = msm_g1(
            array![Y].span(),
            array![s_scalar].span(),
            ED25519_CURVE_INDEX,
            s_hint_for_y
        );
        let _neg_cU = msm_g1(
            array![second].span(),
            array![c_neg_scalar].span(),
            ED25519_CURVE_INDEX,
            c_neg_hint_for_u
        );

        // Full flow completed
        assert(true, 'Step 4: Full flow OK');
    }
}

