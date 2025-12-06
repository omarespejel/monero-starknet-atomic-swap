/// Extract adaptor point coordinates to generate fake-GLV hint
/// This test decompresses the adaptor point and shows its x,y limbs

#[cfg(test)]
mod get_adaptor_hint_tests {
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::G1PointTrait;
    use core::integer::u256;

    const ED25519_CURVE_INDEX: u32 = 4;

    const TEST_ADAPTOR_POINT_COMPRESSED: u256 = u256 {
        low: 0x54e86953e7cc99b545cfef03f63cce85,
        high: 0x427dde0adb325f957d29ad71e4643882,
    };

    const TEST_ADAPTOR_POINT_SQRT_HINT: u256 = u256 {
        low: 0xbb73e7230cbed81eed006ba59a2103f1,
        high: 0x689ee25ca0c65d5a1c560224726871b0,
    };

    #[test]
    fn test_get_adaptor_point_coordinates() {
        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_ADAPTOR_POINT_SQRT_HINT
        );
        
        let point = result.unwrap();
        point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        
        // Extract x and y coordinates (u384 = 4×u96 limbs each)
        // These will be used to create the fake-GLV hint
        // Hint format: [Q.x.limb0, Q.x.limb1, Q.x.limb2, Q.x.limb3,
        //               Q.y.limb0, Q.y.limb1, Q.y.limb2, Q.y.limb3,
        //               s1, s2]
        // Where Q must equal point
        
        let x0: felt252 = point.x.limb0.into();
        let x1: felt252 = point.x.limb1.into();
        let x2: felt252 = point.x.limb2.into();
        let x3: felt252 = point.x.limb3.into();
        let y0: felt252 = point.y.limb0.into();
        let y1: felt252 = point.y.limb1.into();
        let y2: felt252 = point.y.limb2.into();
        let y3: felt252 = point.y.limb3.into();
        
        // For now, just verify we can extract the coordinates
        // The actual hint generation with s1/s2 requires Garaga's get_fake_glv_hint
        // But for testing, we can use Q = point and arbitrary non-zero s1/s2
        
        // Verify coordinates are non-zero (point is valid)
        assert(x0 != 0 || x1 != 0 || x2 != 0 || x3 != 0, 'x is zero');
        assert(y0 != 0 || y1 != 0 || y2 != 0 || y3 != 0, 'y is zero');
    }
}

