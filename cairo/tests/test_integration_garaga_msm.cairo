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
        low: 0x9244eb3a3699efed3106c6ae0afdf28,
        high: 0xb6e0bfc0d9fbb8a4c8ef08cb5da2eff3,
    };
    const TEST_SECOND_POINT_SQRT_HINT: u256 = u256 {
        low: 0xcffea6b3bffe746de20fdd0734b30845,
        high: 0x5e4a3b18b41199f9389ded8696067271,
    };
    const TESTVECTOR_Y_COMPRESSED: u256 = u256 {
        low: 0x21ba32594950b67cf0d8bb8c8ac5e8c7,
        high: 0xf08df421a3209ab6373dd0ec7ef25dfd,
    };
    const TESTVECTOR_Y_SQRT_HINT: u256 = u256 {
        low: 0x928f238c602cdbb49c96ac47cbbf79d7,
        high: 0x65c31da8af8318232d04a1abf99f036e,
    };

    const RESPONSE: u256 = u256 {
        low: 0xbe3ffdd10e06b50b800feb45877b787b,
        high: 0x2f0ceba8a8c56d6f6b4ed3ae98db234,
    };
    const CHALLENGE_FELT: felt252 = 0x47c760eb9b6a8797680bef6218e06aacc6570f8be11819d2268bb024f816108;

    #[test]
    fn test_msm_sg_isolation() {
        // Test s·G MSM call (same as working isolation test)
        let G = get_G(ED25519_CURVE_INDEX);
        // Use direct full scalar (matching working test)
        let s_scalar = RESPONSE;
        
        let s_hint_for_g = array![
            0xceeec4a90f34e45c033e2ff5,
            0xb419479f38f86b2b114d2ff1,
            0x256941d7d54e7beb,
            0x0,
            0xaa6ddc025eb012317a89612a,
            0x6e9d804e52cb98594f552df2,
            0x47244d9888c072a3,
            0x0,
            0xcd234e4105b9809a3f4f0dde019dac1,
            0x1268c27967bf37239a1bdcad1722144e1
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
        // CRITICAL: Y is the domain-separated second generator, NOT U from test vectors.
        let Y = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TESTVECTOR_Y_COMPRESSED,
            TESTVECTOR_Y_SQRT_HINT
        ).unwrap();
        Y.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        
        // Use direct full scalar (matching working test)
        let s_scalar = RESPONSE;
        
        let s_hint_for_y = array![
            0x872011d1a9f20fc5fbed65ec,
            0xd36e4710d58461cfe9c9ee1d,
            0x686f29bbaf2b952f,
            0x0,
            0xf350a6f8bc8acbb1d5c40cd5,
            0x4b256a3dba76a0bc779c811,
            0x43f41814a3eefa59,
            0x0,
            0xcd234e4105b9809a3f4f0dde019dac1,
            0x1268c27967bf37239a1bdcad1722144e1
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
            0xfbeb7a88a7204a3109847933,
            0xd7bd766f54592bfb04b8a0bf,
            0x36adfbd5b292a10e,
            0x0,
            0xb1cb68d66c0170146df52bb2,
            0x7ad50b1ffcd1293f12940e01,
            0x665e063c6d4ac0f6,
            0x0,
            0x4d5cf08f2a0aee991f621d5e4e15728,
            0x1148705832ba97f2b70dec32979f4f785
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
            0x16ecdc108960cb810ed61451,
            0x28bf80201d67e2f4728ba74b,
            0x63f872f4f71e1950,
            0x0,
            0xe94caf1beb68a19f34eb98a4,
            0x48bcbcb46602eeea1b043d0d,
            0x52e390f474357096,
            0x0,
            0x4d5cf08f2a0aee991f621d5e4e15728,
            0x1148705832ba97f2b70dec32979f4f785
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
