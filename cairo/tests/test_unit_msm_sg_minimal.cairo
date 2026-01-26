/// Minimal test to verify s·G MSM call works without blake2s_challenge import
/// This tests if the import is causing the issue

#[cfg(test)]
mod msm_sg_minimal_tests {
    use core::array::ArrayTrait;
    use core::integer::u256;
    use garaga::definitions::get_G;
    use garaga::ec_ops::{msm_g1, G1PointTrait};

    const ED25519_CURVE_INDEX: u32 = 4;
    const RESPONSE_LOW: felt252 = 0x1e741f8fec4161ea41b23ce6d007ba12;

    #[test]
    fn test_msm_sg_minimal() {
        // EXACT same code as test_garaga_msm_all_calls::test_msm_sg_isolation
        // But WITHOUT any blake2s_challenge import
        let G = get_G(ED25519_CURVE_INDEX);
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
}

