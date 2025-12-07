/// Diagnostic test to extract Weierstrass coordinates from decompressed points
/// This helps regenerate hints using the ACTUAL coordinates Cairo uses

#[cfg(test)]
mod extract_coordinates_tests {
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::G1PointTrait;
    use core::integer::u256;

    const ED25519_CURVE_INDEX: u32 = 4;

    // Test vector constants (from test_e2e_dleq.cairo)
    const TEST_ADAPTOR_POINT_COMPRESSED: u256 = u256 {
        low: 0x47cff7b5713428a889bfad01f6fa4e00,
        high: 0x0850ef802e40bbd177b22dd7319a9bc0,
    };
    const TEST_ADAPTOR_POINT_SQRT_HINT: u256 = u256 {
        low: 0x9f3ee81fe68dcbcf9de661eedd114a9e,
        high: 0x397c8b3280ddfb2ffe72518d79cc504c,
    };

    const TEST_SECOND_POINT_COMPRESSED: u256 = u256 {
        low: 0x47cff7b5713428a889bfad01f6fa4e00,
        high: 0x0850ef802e40bbd177b22dd7319a9bc0,
    };
    const TEST_SECOND_POINT_SQRT_HINT: u256 = u256 {
        low: 0x9f3ee81fe68dcbcf9de661eedd114a9e,
        high: 0x397c8b3280ddfb2ffe72518d79cc504c,
    };

    #[test]
    fn extract_adaptor_point_coordinates() {
        // Decompress adaptor point (T)
        let adaptor_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_ADAPTOR_POINT_SQRT_HINT
        );
        
        if adaptor_result.is_none() {
            assert(false, 'Adaptor decompress failed');
        }
        
        let adaptor = adaptor_result.unwrap();
        adaptor.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        
        // Extract u384 limbs for x and y coordinates
        // u384 is stored as 4 u96 limbs: [limb0, limb1, limb2, limb3]
        // These can be accessed directly: point.x.limb0, point.x.limb1, etc.
        // The actual extraction will be done in Python using Garaga's decompression
        // This test just verifies decompression works
        assert(true, 'Extract coords');
    }
    
    #[test]
    fn extract_second_point_coordinates() {
        // Decompress second point (U)
        let second_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_SECOND_POINT_COMPRESSED,
            TEST_SECOND_POINT_SQRT_HINT
        );
        
        if second_result.is_none() {
            assert(false, 'Second decompress failed');
        }
        
        let second = second_result.unwrap();
        second.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        
        assert(true, 'Extract coords');
    }
}

