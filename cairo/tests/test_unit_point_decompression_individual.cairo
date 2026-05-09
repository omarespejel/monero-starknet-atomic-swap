//! Individual point decompression tests for debugging
//! 
//! These tests isolate each point decompression to identify which one fails.
//! Test each point individually before running E2E test.

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
        low: 0x9244eb3a3699efed3106c6ae0afdf28,
        high: 0xb6e0bfc0d9fbb8a4c8ef08cb5da2eff3,
    };

    // Regenerated using Garaga's exact algorithm
    const TEST_SECOND_POINT_SQRT_HINT: u256 = u256 {
        low: 0xcffea6b3bffe746de20fdd0734b30845,
        high: 0x5e4a3b18b41199f9389ded8696067271,
    };

    const TEST_R1_COMPRESSED: u256 = u256 {
        low: 0x3cb02521d7a17fedca11c02ea41fe334,
        high: 0x11ef09256f90d942ca7a0e4ae05926a5,
    };

    // Regenerated using Garaga's exact algorithm
    const TEST_R1_SQRT_HINT: u256 = u256 {
        low: 0x623d9789d855bcc4f0fbd8683b350688,
        high: 0x0a2d15cdfbfcf6181e92f0b7c74b477e,
    };

    const TEST_R2_COMPRESSED: u256 = u256 {
        low: 0xe66ca975ef303c032fcc18a952325162,
        high: 0xc5d2eb608176c8b79dfa55289c35b35f,
    };

    // Regenerated using Garaga's exact algorithm
    const TEST_R2_SQRT_HINT: u256 = u256 {
        low: 0xd8b08d5ec3d265b83e5e333d750d6b37,
        high: 0x0e41fbdbbf62b47c511e0a5aa04059de,
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

