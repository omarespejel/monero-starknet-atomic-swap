//! Individual point decompression tests for debugging
//! 
//! These tests isolate each point decompression to identify which one fails.
//! Per auditor guidance: test each point individually before running E2E test.

#[cfg(test)]
mod test_point_decompression_individual {
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::G1PointTrait;

    const ED25519_CURVE_INDEX: u32 = 4;

    // Test constants from test_e2e_dleq.cairo
    const TEST_ADAPTOR_POINT_COMPRESSED: u256 = u256 {
        low: 0x54e86953e7cc99b545cfef03f63cce85,
        high: 0x427dde0adb325f957d29ad71e4643882,
    };

    // Regenerated using Garaga's exact algorithm
    const TEST_ADAPTOR_POINT_SQRT_HINT: u256 = u256 {
        low: 0x448c18dcf34127e112ff945a65defbfc,
        high: 0x17611da35f39a2a5e3a9fddb8d978e4f,
    };

    const TEST_SECOND_POINT_COMPRESSED: u256 = u256 {
        low: 0xd893b3476bdf09770b7616f84c5c7bbe,
        high: 0x5c79d0fa84d6440908e2e2065e60d1cd,
    };

    // Regenerated using Garaga's exact algorithm
    const TEST_SECOND_POINT_SQRT_HINT: u256 = u256 {
        low: 0xdcad2173817c163b5405cec7698eb4b8,
        high: 0x742bb3c44b13553c8ddff66565b44cac,
    };

    const TEST_R1_COMPRESSED: u256 = u256 {
        low: 0x90b1ab352981d43ec51fba0af7ab51c7,
        high: 0xc21ebc88e5e59867b280909168338026,
    };

    // Regenerated using Garaga's exact algorithm
    const TEST_R1_SQRT_HINT: u256 = u256 {
        low: 0x72a9698d3171817c239f4009cc36fc97,
        high: 0x3f2b84592a9ee701d24651e3aa3c837d,
    };

    const TEST_R2_COMPRESSED: u256 = u256 {
        low: 0x02d386e8fd6bd85a339171211735bcba,
        high: 0x10defc0130a9f3055798b1f5a99aeb67,
    };

    // Regenerated using Garaga's exact algorithm
    const TEST_R2_SQRT_HINT: u256 = u256 {
        low: 0x43f2c451f9ca69ff1577d77d646a50e,
        high: 0x4ee64b0e07d89e906f9e8b7bea09283e,
    };

    #[test]
    fn test_adaptor_point_decompression_only() {
        let compressed = TEST_ADAPTOR_POINT_COMPRESSED;
        let hint = TEST_ADAPTOR_POINT_SQRT_HINT;

        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            compressed, hint
        );

        assert(result.is_some(), 'Adaptor point decompress failed');
        let point = result.unwrap();

        // Verify point is on curve
        point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        // Note: Small order check omitted (function not visible in test context)
    }

    #[test]
    fn test_second_point_decompression_only() {
        let compressed = TEST_SECOND_POINT_COMPRESSED;
        let hint = TEST_SECOND_POINT_SQRT_HINT;

        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            compressed, hint
        );

        assert(result.is_some(), 'Second point decompress failed');
        let point = result.unwrap();

        // Verify point is on curve
        point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        // Note: Small order check omitted (function not visible in test context)
    }

    #[test]
    fn test_r1_decompression_only() {
        let compressed = TEST_R1_COMPRESSED;
        let hint = TEST_R1_SQRT_HINT;

        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            compressed, hint
        );

        assert(result.is_some(), 'R1 decompress failed');
        let point = result.unwrap();

        // Verify point is on curve
        point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        // Note: Small order check omitted (function not visible in test context)
    }

    #[test]
    fn test_r2_decompression_only() {
        let compressed = TEST_R2_COMPRESSED;
        let hint = TEST_R2_SQRT_HINT;

        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            compressed, hint
        );

        assert(result.is_some(), 'R2 decompress failed');
        let point = result.unwrap();

        // Verify point is on curve
        point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        // Note: Small order check omitted (function not visible in test context)
    }
}

