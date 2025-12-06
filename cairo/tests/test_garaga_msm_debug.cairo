/// Debug test to isolate Garaga msm_g1 issues
/// This test helps identify which specific MSM call fails

#[cfg(test)]
mod garaga_msm_debug_tests {
    use core::array::ArrayTrait;
    use garaga::definitions::{get_G, G1Point};
    use garaga::ec_ops::{msm_g1, G1PointTrait};
    use core::integer::u256;

    const ED25519_CURVE_INDEX: u32 = 4;
    const ED25519_ORDER: u256 = u256 {
        low: 0x14def9dea2f79cd65812631a5cf5d3ed,
        high: 0x10000000000000000000000000000000,
    };

    #[test]
    fn test_msm_with_generator_scalar_one() {
        // Simplest possible test: G * 1 = G
        let G = get_G(ED25519_CURVE_INDEX);
        G.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        
        let scalar_one = u256 { low: 1, high: 0 };
        
        // Create minimal hint (10 felts, all zeros for now)
        // This will likely fail, but will show us Garaga's error format
        let empty_hint = array![0, 0, 0, 0, 0, 0, 0, 0, 0, 0].span();
        
        // This should work if hint is correct, or fail with specific error
        let result = msm_g1(
            array![G].span(),
            array![scalar_one].span(),
            ED25519_CURVE_INDEX,
            empty_hint
        );
        
        // If this passes, we know the issue is with hint format
        assert(result == G, 'MSM 1*G = G');
    }
    
    #[test]
    fn test_msm_array_lengths() {
        // Verify array length requirements
        let G = get_G(ED25519_CURVE_INDEX);
        let scalar_one = u256 { low: 1, high: 0 };
        
        let points = array![G].span();
        let scalars = array![scalar_one].span();
        let hint = array![0, 0, 0, 0, 0, 0, 0, 0, 0, 0].span();
        
        // Verify lengths match expectations
        assert(points.len() == 1, 'points len 1');
        assert(scalars.len() == 1, 'scalars len 1');
        assert(hint.len() == 10, 'hint len 10');
        assert(points.len() == scalars.len(), 'same len');
        assert(hint.len() == points.len() * 10, 'hint 10x');
        
        // Try MSM call
        let _result = msm_g1(points, scalars, ED25519_CURVE_INDEX, hint);
    }
    
    #[test]
    fn test_msm_with_actual_scalar_from_test() {
        // Use actual scalar from test vectors (truncated)
        // This matches what Cairo actually passes to Garaga
        let G = get_G(ED25519_CURVE_INDEX);
        
        // Truncated response scalar (matching reduce_felt_to_scalar)
        let s_scalar = u256 {
            low: 0x47cff7b5713428a889bfad01f6fa4e00,
            high: 0x0
        };
        
        // Verify scalar is in valid range
        assert(s_scalar < ED25519_ORDER, 'scalar < order');
        
        // Use hint from test (s_hint_for_g)
        let hint = array![
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
        
        // This is the exact call from _verify_dleq_proof
        // If this fails, we know the issue is with this specific call
        let result = msm_g1(
            array![G].span(),
            array![s_scalar].span(),
            ED25519_CURVE_INDEX,
            hint
        );
        
        // Verify result is on curve
        result.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
    }
}

