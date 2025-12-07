/// Test to verify DLEQ hints match exactly between test construction and MSM usage
/// This helps identify if hint structure is corrupted during parameter passing

#[cfg(test)]
mod dleq_hint_verification_tests {
    use core::array::ArrayTrait;
    use garaga::definitions::get_G;
    use garaga::ec_ops::{msm_g1, G1PointTrait};
    use core::integer::u256;
    const ED25519_CURVE_INDEX: u32 = 4;

    const ED25519_ORDER: u256 = u256 {
        low: 0x14def9dea2f79cd65812631a5cf5d3ed,
        high: 0x10000000000000000000000000000000,
    };

    #[test]
    fn test_dleq_hint_structure_matches_msm_expectation() {
        // Use exact hints from test_e2e_dleq.cairo
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
        
        // Use exact scalar from test (truncated)
        let s_scalar = u256 {
            low: 0x47cff7b5713428a889bfad01f6fa4e00,
            high: 0x0
        };
        
        // Verify hint structure
        assert(s_hint_for_g.len() == 10, 'Hint len 10');
        
        // Extract Q point from hint
        // Format: [Q.x[4], Q.y[4], s1, s2]
        let _q_x_limb0 = *s_hint_for_g.at(0);
        let _q_x_limb1 = *s_hint_for_g.at(1);
        let _q_x_limb2 = *s_hint_for_g.at(2);
        let _q_x_limb3 = *s_hint_for_g.at(3);
        let _q_y_limb0 = *s_hint_for_g.at(4);
        let _q_y_limb1 = *s_hint_for_g.at(5);
        let _q_y_limb2 = *s_hint_for_g.at(6);
        let _q_y_limb3 = *s_hint_for_g.at(7);
        let s1 = *s_hint_for_g.at(8);
        let s2_encoded = *s_hint_for_g.at(9);
        
        // Verify hint scalars are non-zero
        assert(s1 != 0, 's1 non-zero');
        assert(s2_encoded != 0, 's2 non-zero');
        
        // Verify scalar is in valid range
        assert(s_scalar != u256 { low: 0, high: 0 }, 'scalar non-zero');
        assert(s_scalar < ED25519_ORDER, 'scalar < order');
        
        // Test MSM call with exact same setup as constructor
        let G = get_G(ED25519_CURVE_INDEX);
        let result = msm_g1(
            array![G].span(),
            array![s_scalar].span(),
            ED25519_CURVE_INDEX,
            s_hint_for_g
        );
        
        // Verify result is on curve
        result.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        
        // If we get here, the hint structure is correct
        assert(true, 'Hint structure OK');
    }
    
    #[test]
    fn test_span_construction_preserves_hint_values() {
        // Test that creating array then .span() preserves values
        let hint_array = array![
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
        ];
        
        let hint_span = hint_array.span();
        
        // Verify span preserves array values
        assert(hint_span.len() == 10, 'Span len 10');
        assert(*hint_span.at(0) == 0xd21de05d0b4fe220a6fcca9b, 'Value 0 match');
        assert(*hint_span.at(8) == 0x1fd0f994a4c11a4543d86f4578e7b9ed, 'Value 8 match');
        assert(*hint_span.at(9) == 0x39099b31d1013f73ec51ebd61fdfe2ab, 'Value 9 match');
    }
}

