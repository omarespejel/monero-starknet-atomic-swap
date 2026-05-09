/// Minimal test to verify s·G MSM call works without blake2s_challenge import
/// This tests if the import is causing the issue

#[cfg(test)]
mod msm_sg_minimal_tests {
    use core::array::ArrayTrait;
    use core::integer::u256;
    use garaga::definitions::get_G;
    use garaga::ec_ops::{msm_g1, G1PointTrait};

    const ED25519_CURVE_INDEX: u32 = 4;
    const RESPONSE: u256 = u256 {
        low: 0xbe3ffdd10e06b50b800feb45877b787b,
        high: 0x2f0ceba8a8c56d6f6b4ed3ae98db234,
    };

    #[test]
    fn test_msm_sg_minimal() {
        // EXACT same code as test_garaga_msm_all_calls::test_msm_sg_isolation
        // But WITHOUT any blake2s_challenge import
        let G = get_G(ED25519_CURVE_INDEX);
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
}
