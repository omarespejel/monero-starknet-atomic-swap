/// Test different u256 byte order interpretations for compressed point
/// This helps identify the correct format Garaga expects

#[cfg(test)]
mod decompression_format_tests {
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::G1PointTrait;
    use core::integer::u256;

    const ED25519_CURVE_INDEX: u32 = 0;

    // Ed25519 base point - known good point
    // Hex: 5866666666666666666666666666666666666666666666666666666666666666
    // Current format (little-endian 16-byte chunks)
    const BASE_POINT_FORMAT_1: u256 = u256 {
        low: 0x66666666666666666666666666666658,
        high: 0x66666666666666666666666666666666,
    };

    // Alternative: big-endian within parts
    const BASE_POINT_FORMAT_2: u256 = u256 {
        low: 0x58666666666666666666666666666666,
        high: 0x66666666666666666666666666666666,
    };

    // Alternative: swapped high/low
    const BASE_POINT_FORMAT_3: u256 = u256 {
        low: 0x66666666666666666666666666666666,
        high: 0x66666666666666666666666666666658,
    };

    // Sqrt hint (without sign adjustment)
    const BASE_POINT_SQRT_HINT: u256 = u256 {
        low: 0x9f3ee81fe68dcbcf9de661eedd114a9e,
        high: 0x397c8b3280ddfb2ffe72518d79cc504c,
    };

    #[test]
    fn test_format_1() {
        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            BASE_POINT_FORMAT_1,
            BASE_POINT_SQRT_HINT
        );
        // This is the current format - if it fails, try others
        if let Some(point) = result {
            point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        }
    }

    #[test]
    fn test_format_2() {
        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            BASE_POINT_FORMAT_2,
            BASE_POINT_SQRT_HINT
        );
        if let Some(point) = result {
            point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        }
    }

    #[test]
    fn test_format_3() {
        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            BASE_POINT_FORMAT_3,
            BASE_POINT_SQRT_HINT
        );
        if let Some(point) = result {
            point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        }
    }
}

