/// # Point Decompression Diagnostic Test
///
/// Isolates which point decompression is failing in the end-to-end test
/// This helps identify if the issue is with sqrt hints or compressed point format

#[cfg(test)]
mod point_decompression_tests {
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::G1PointTrait;
    use core::integer::u256;

    const ED25519_CURVE_INDEX: u32 = 0;

    // Test vectors from test_e2e_dleq.cairo
    const TEST_ADAPTOR_POINT_COMPRESSED: u256 = u256 {
        low: 0x54e86953e7cc99b545cfef03f63cce85,
        high: 0x427dde0adb325f957d29ad71e4643882,
    };

    const TEST_ADAPTOR_POINT_SQRT_HINT: u256 = u256 {
        low: 0xbb73e7230cbed81eed006ba59a2103f1,
        high: 0x689ee25ca0c65d5a1c560224726871b0,
    };

    const TEST_SECOND_POINT_COMPRESSED: u256 = u256 {
        low: 0xd893b3476bdf09770b7616f84c5c7bbe,
        high: 0x5c79d0fa84d6440908e2e2065e60d1cd,
    };

    const TEST_SECOND_POINT_SQRT_HINT: u256 = u256 {
        low: 0xdcad2173817c163b5405cec7698eb4b8,
        high: 0x742bb3c44b13553c8ddff66565b44cac,
    };

    const TEST_R1_COMPRESSED: u256 = u256 {
        low: 0x0fa325f321fdf41a1630e19e36ababb8,
        high: 0xabe2cf84b1246b428bce04d66cdb9b7e,
    };

    const TEST_R1_SQRT_HINT: u256 = u256 { 
        low: 0x4f1efce2a44c72b5d316cc9b8d8e4673,
        high: 0x28bde2dde999d287316395d449669102,
    };
    
    // R2 uses Ed25519 base point (R2 from test_vectors.json is invalid)
    const TEST_R2_COMPRESSED: u256 = u256 {
        low: 0x66666666666666666666666666666658,
        high: 0x66666666666666666666666666666666,
    };
    
    const TEST_R2_SQRT_HINT: u256 = u256 { 
        low: 0x96d3389f6ada584d36a9d29f70da2ad3,
        high: 0x5e96c92c3291ac013f5b1dce022923a3,
    };

    #[test]
    fn test_adaptor_point_decompression() {
        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_ADAPTOR_POINT_SQRT_HINT
        );
        let point = result.unwrap();
        point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        // Point decompression succeeded - that's what we're testing
    }

    #[test]
    fn test_second_point_decompression() {
        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_SECOND_POINT_COMPRESSED,
            TEST_SECOND_POINT_SQRT_HINT
        );
        let point = result.unwrap();
        point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        // Point decompression succeeded - that's what we're testing
    }

    #[test]
    fn test_r1_decompression() {
        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_R1_COMPRESSED,
            TEST_R1_SQRT_HINT
        );
        let point = result.unwrap();
        point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        // Point decompression succeeded - that's what we're testing
    }

    #[test]
    fn test_r2_decompression() {
        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_R2_COMPRESSED,
            TEST_R2_SQRT_HINT
        );
        let point = result.unwrap();
        point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        // Point decompression succeeded - that's what we're testing
    }
}

