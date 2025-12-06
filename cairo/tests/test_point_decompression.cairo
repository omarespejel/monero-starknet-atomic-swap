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
        low: 0xe060b8e02062c970e2a230bd7b352952,
        high: 0x107170f6564a9d32c73f9428ae5a145d,
    };

    const TEST_SECOND_POINT_COMPRESSED: u256 = u256 {
        low: 0xd893b3476bdf09770b7616f84c5c7bbe,
        high: 0x5c79d0fa84d6440908e2e2065e60d1cd,
    };

    const TEST_SECOND_POINT_SQRT_HINT: u256 = u256 {
        low: 0x579c34966ca8c7813ce1b4c42b94eb8d,
        high: 0x617cc305f988451439d44d17c4d0c210,
    };

    const TEST_R1_COMPRESSED: u256 = u256 {
        low: 0x9c289904f3df85b691d32a931f4d239,
        high: 0xf7926242a14aef11d6c54224331717ae,
    };

    const TEST_R1_SQRT_HINT: u256 = u256 { 
        low: 0x6df0c4dede706b328e6600feba46530d,
        high: 0x088944eb1010f08e943db84f8ddd3ad3,
    };
    
    const TEST_R2_COMPRESSED: u256 = u256 {
        low: 0x2a8dcb3f7f2fdfac40805970f83a3577,
        high: 0xde953c10ba21a6970b15ecdc1a8d404,
    };
    
    const TEST_R2_SQRT_HINT: u256 = u256 { 
        low: 0x250c4f56970b928e5e65f8a7e607fadf,
        high: 0x472b8e7d01324de31b540f88af07aeb4,
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

