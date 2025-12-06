/// Test decompression of Ed25519 base point (known-good point)
/// This helps isolate if the issue is with sqrt hints or decompression function

#[cfg(test)]
mod ed25519_base_point_tests {
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::G1PointTrait;
    use core::integer::u256;

    const ED25519_CURVE_INDEX: u32 = 0;

    // Ed25519 base point (generator G) - guaranteed valid
    const ED25519_BASE_POINT_COMPRESSED: u256 = u256 {
        low: 0x66666666666666666666666666666658,
        high: 0x66666666666666666666666666666666,
    };

    // Twisted Edwards sqrt hint (from Python RFC 8032)
    const ED25519_BASE_POINT_SQRT_HINT: u256 = u256 {
        low: 0x9f3ee81fe68dcbcf9de661eedd114a9e,
        high: 0x397c8b3280ddfb2ffe72518d79cc504c,
    };

    #[test]
    fn test_ed25519_base_point_decompression() {
        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            ED25519_BASE_POINT_COMPRESSED,
            ED25519_BASE_POINT_SQRT_HINT
        );
        
        // This should succeed - base point is guaranteed valid
        let point = result.unwrap();
        point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
    }
}

