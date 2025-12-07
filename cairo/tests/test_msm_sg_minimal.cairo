/// Minimal test to verify s·G MSM call works without blake2s_challenge import
/// This tests if the import is causing the issue

#[cfg(test)]
mod msm_sg_minimal_tests {
    use core::array::ArrayTrait;
    use core::integer::u256;
    use garaga::definitions::get_G;
    use garaga::ec_ops::{msm_g1, G1PointTrait};

    const ED25519_CURVE_INDEX: u32 = 4;
    const RESPONSE_LOW: felt252 = 0x47cff7b5713428a889bfad01f6fa4e00;

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
}

