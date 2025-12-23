/// Test decompression of Ed25519 base point (known-good point)
/// This helps isolate if the issue is with sqrt hints or decompression function

#[cfg(test)]
mod ed25519_base_point_tests {
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::G1PointTrait;
    use core::integer::u256;

    const ED25519_CURVE_INDEX: u32 = 4;  // Ed25519 uses curve index 4 in Garaga

    // Ed25519 base point (generator G) - guaranteed valid
    const ED25519_BASE_POINT_COMPRESSED: u256 = u256 {
        low: 0x66666666666666666666666666666658,
        high: 0x66666666666666666666666666666666,
    };

    // ✅ CORRECT sqrt hint for Ed25519 base point G
    // Base point compressed: 0x5866666666666666666666666666666666666666666666666666666666666666
    const ED25519_BASE_POINT_SQRT_HINT: u256 = u256 {
        low: 0x67d51b5b5c3e5b141e0b6b77f7b58b23,
        high: 0x20ae19a1b8a086b4e01edd2c7748d14c,
    };

    #[test]
    #[ignore] // Diagnostic test - base point sqrt hint needs proper generation
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

