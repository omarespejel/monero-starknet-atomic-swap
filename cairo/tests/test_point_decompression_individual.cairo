//! Individual point decompression tests for debugging
//! 
//! These tests isolate each point decompression to identify which one fails.
//! Per auditor guidance: test each point individually before running E2E test.

#[cfg(test)]
mod test_point_decompression_individual {
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::G1PointTrait;
    use atomic_lock::AtomicLock::is_small_order_ed25519;

    const ED25519_CURVE_INDEX: u32 = 4;

    // Test constants from test_e2e_dleq.cairo
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
        low: 0x90b1ab352981d43ec51fba0af7ab51c7,
        high: 0xc21ebc88e5e59867b280909168338026,
    };

    const TEST_R1_SQRT_HINT: u256 = u256 {
        low: 0x4cc57c2209c51618c31e258bf249b9fa,
        high: 0x434fcefc463e7d521e7ba916c7c9a970,
    };

    const TEST_R2_COMPRESSED: u256 = u256 {
        low: 0x02d386e8fd6bd85a339171211735bcba,
        high: 0x10defc0130a9f3055798b1f5a99aeb67,
    };

    const TEST_R2_SQRT_HINT: u256 = u256 {
        low: 0xc08262c204db914e54d3698364ed84a3,
        high: 0x72a1b655b77050e1f19c603bcc6c1d42,
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
        assert(!is_small_order_ed25519(point), 'Small order point rejected');
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
        assert(!is_small_order_ed25519(point), 'Small order point rejected');
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
        assert(!is_small_order_ed25519(point), 'Small order point rejected');
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
        assert(!is_small_order_ed25519(point), 'Small order point rejected');
    }
}

