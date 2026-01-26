/// Test all 4 MSM calls in isolation to identify which one fails
/// This helps pinpoint the exact failing MSM call

#[cfg(test)]
mod garaga_msm_all_calls_tests {
    use core::array::ArrayTrait;
    use core::integer::u256;
    use garaga::definitions::get_G;
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::{msm_g1, G1PointTrait, ec_safe_add};
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
    const RESPONSE_LOW: felt252 = 0x1e741f8fec4161ea41b23ce6d007ba12;
    const RESPONSE_HIGH: felt252 = 0x026ed77551e578013227c9b98bd25c66;
    const CHALLENGE_FELT: felt252 = 0x8d664bb70810bdab323a44354d98f94a;

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

        
            0x52f522935135e7c5474d3b99,

        
            0x7ff7e65231c434008a0c02f8,

        
            0x41a3962ca5bba9db,

        
            0x0,

        
            0xa144206dc24b7180d05200e0,

        
            0xe8a798301a354777473cd98e,

        
            0x7ca5add375ea088,

        
            0x0,

        
            0x1e741f8fec4161ea41b23ce6d007ba12,

        
            0x100000000000000000000000000000001

        
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
        // CRITICAL: Y is the second generator (2·G), NOT the second_point (U) from test vectors
        // The hint is generated for s·(2·G), so we must compute 2·G directly
        let G = get_G(ED25519_CURVE_INDEX);
        let Y = ec_safe_add(G, G, ED25519_CURVE_INDEX);  // Y = 2·G
        Y.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        
        // Use direct truncated scalar (matching working test)
        let s_scalar = u256 {
            low: RESPONSE_LOW.try_into().unwrap(),
            high: 0
        };
        
        let s_hint_for_y = array![

        
            0x3b81c211fd322bb7dbcb711c,

        
            0x2082c0dd34f9225f2eb5e0b0,

        
            0x311b02be49202932,

        
            0x0,

        
            0x18c0245425f95187b10e1913,

        
            0x922be9d1d5313d1c7a4cb499,

        
            0x51d9b0eb8a969e37,

        
            0x0,

        
            0x1e741f8fec4161ea41b23ce6d007ba12,

        
            0x100000000000000000000000000000001

        
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

        
            0xcb63575f3729fe6cbe7f8496,

        
            0x9dc314d92447fddbfc1be6cd,

        
            0x7d6caff1e7cdaa02,

        
            0x0,

        
            0x78dc46b41742aa135083e2da,

        
            0xecafad9bd49fe98686457cc6,

        
            0x592bb6f3eaf7ca3,

        
            0x0,

        
            0x34a3efff5488d0dfc135bf37e3357b53,

        
            0x1cf7b1760ae5d3463a08a196fd625720

        
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

        
            0x61ebcae684d8530622e29b45,

        
            0x694dbc34734f56c0e29f5240,

        
            0x1913755501e61b9a,

        
            0x0,

        
            0x2a37ba10878046ff378a7d73,

        
            0x25857fe5ce7f65cea1bbc1e0,

        
            0xca82b2053c5e43e,

        
            0x0,

        
            0x34a3efff5488d0dfc135bf37e3357b53,

        
            0x1cf7b1760ae5d3463a08a196fd625720

        
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

