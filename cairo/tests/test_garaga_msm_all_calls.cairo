/// Test all 4 MSM calls in isolation to identify which one fails
/// This helps pinpoint the exact failing MSM call

#[cfg(test)]
mod garaga_msm_all_calls_tests {
    use core::array::ArrayTrait;
    use core::integer::u256;
    use garaga::definitions::get_G;
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::{msm_g1, G1PointTrait};
    use atomic_lock::AtomicLock::reduce_felt_to_scalar;

    const ED25519_CURVE_INDEX: u32 = 4;
    const ED25519_ORDER: u256 = u256 {
        low: 0x14def9dea2f79cd65812631a5cf5d3ed,
        high: 0x10000000000000000000000000000000,
    };

    // Test vector constants
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

    const BASE_128: felt252 = 0x100000000000000000000000000000000;
    const RESPONSE_LOW: felt252 = 0x47cff7b5713428a889bfad01f6fa4e00;
    const RESPONSE_HIGH: felt252 = 0x0850ef802e40bbd177b22dd7319a9bc0;
    const CHALLENGE_FELT: felt252 = 0x6212e6122afa3670f0f578dffd3b2703;

    #[test]
    fn test_msm_sg_isolation() {
        // Test s·G MSM call (same as working isolation test)
        let G = get_G(ED25519_CURVE_INDEX);
        // Use direct truncated scalar (matching working test)
        let s_scalar = u256 {
            low: RESPONSE_LOW.try_into().unwrap(),
            high: 0
        };
        
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
    }

    #[test]
    fn test_msm_sy_isolation() {
        // Test s·Y MSM call
        let Y_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_SECOND_POINT_COMPRESSED,
            TEST_SECOND_POINT_SQRT_HINT
        );
        let Y = Y_result.unwrap();
        Y.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        
        // Use direct truncated scalar (matching working test)
        let s_scalar = u256 {
            low: RESPONSE_LOW.try_into().unwrap(),
            high: 0
        };
        
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
    }

    #[test]
    fn test_msm_negct_isolation() {
        // Test (-c)·T MSM call
        let T_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_ADAPTOR_POINT_SQRT_HINT
        );
        let T = T_result.unwrap();
        T.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        
        let c_scalar = reduce_felt_to_scalar(CHALLENGE_FELT);
        let c_neg_scalar = (ED25519_ORDER - (c_scalar % ED25519_ORDER)) % ED25519_ORDER;
        
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
        
        let neg_cT = msm_g1(
            array![T].span(),
            array![c_neg_scalar].span(),
            ED25519_CURVE_INDEX,
            c_neg_hint_for_t
        );
        neg_cT.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
    }

    #[test]
    fn test_msm_negcu_isolation() {
        // Test (-c)·U MSM call
        let U_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_SECOND_POINT_COMPRESSED,
            TEST_SECOND_POINT_SQRT_HINT
        );
        let U = U_result.unwrap();
        U.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        
        let c_scalar = reduce_felt_to_scalar(CHALLENGE_FELT);
        let c_neg_scalar = (ED25519_ORDER - (c_scalar % ED25519_ORDER)) % ED25519_ORDER;
        
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
        
        let neg_cU = msm_g1(
            array![U].span(),
            array![c_neg_scalar].span(),
            ED25519_CURVE_INDEX,
            c_neg_hint_for_u
        );
        neg_cU.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
    }
}

