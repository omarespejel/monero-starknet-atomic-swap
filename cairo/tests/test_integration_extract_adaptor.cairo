/// Extract adaptor point coordinates for fake-GLV hint generation
/// This test decompresses the adaptor point and shows its x,y coordinates

#[cfg(test)]
mod extract_coords_tests {
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
    fn test_extract_adaptor_coordinates() {
        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_ADAPTOR_POINT_SQRT_HINT
        );
        
        let point = result.unwrap();
        point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        
        // Extract coordinates for hint generation
        // Q.x = point.x (u384 = 4×u96 limbs)
        // Q.y = point.y (u384 = 4×u96 limbs)
        // These are the first 8 felts of the fake-GLV hint
        
        // The hint format is: [Q.x.limb0, Q.x.limb1, Q.x.limb2, Q.x.limb3,
        //                      Q.y.limb0, Q.y.limb1, Q.y.limb2, Q.y.limb3,
        //                      s1, s2]
        // Where Q must equal point
        
        // For now, just verify decompression works
        // We'll need to extract the actual coordinates to generate the hint
    }
}

