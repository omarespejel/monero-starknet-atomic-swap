/// Diagnostic test to extract Weierstrass coordinates from decompressed points
/// This helps regenerate hints using the ACTUAL coordinates Cairo uses

#[cfg(test)]
mod extract_coordinates_tests {
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::G1PointTrait;
    use core::integer::u256;

    const ED25519_CURVE_INDEX: u32 = 4;

    // ✅ VALIDATED sqrt hints from test_e2e_dleq.cairo (single source of truth)

    // Adaptor Point T (compressed)
    const TEST_ADAPTOR_POINT_COMPRESSED: u256 = u256 {
        low: 0x54e86953e7cc99b545cfef03f63cce85,
        high: 0x427dde0adb325f957d29ad71e4643882,
    };

    const TEST_ADAPTOR_POINT_SQRT_HINT: u256 = u256 {
        low: 0x448c18dcf34127e112ff945a65defbfc,
        high: 0x17611da35f39a2a5e3a9fddb8d978e4f,
    };

    // Second Point U (compressed) - DIFFERENT point, DIFFERENT hint
    const TEST_SECOND_POINT_COMPRESSED: u256 = u256 {
        low: 0xd893b3476bdf09770b7616f84c5c7bbe,
        high: 0x5c79d0fa84d6440908e2e2065e60d1cd,
    };

    const TEST_SECOND_POINT_SQRT_HINT: u256 = u256 {
        low: 0xdcad2173817c163b5405cec7698eb4b8,
        high: 0x742bb3c44b13553c8ddff66565b44cac,
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

