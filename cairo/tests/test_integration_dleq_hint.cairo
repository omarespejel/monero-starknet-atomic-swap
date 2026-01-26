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
        
        // Use exact scalar from test (truncated)
        let s_scalar = u256 {
            low: 0x1e741f8fec4161ea41b23ce6d007ba12,
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
        ];
        
        let hint_span = hint_array.span();
        
        // Verify span preserves array values
        assert(hint_span.len() == 10, 'Span len 10');
        assert(*hint_span.at(0) == 0x52f522935135e7c5474d3b99, 'Value 0 match');
        assert(*hint_span.at(8) == 0x1e741f8fec4161ea41b23ce6d007ba12, 'Value 8 match');
        assert(*hint_span.at(9) == 0x100000000000000000000000000000001, 'Value 9 match');
    }
}

