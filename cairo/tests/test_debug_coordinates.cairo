/// Diagnostic test to verify decompressed Weierstrass coordinates
/// This test verifies decompression works correctly.
/// To extract coordinates for hint regeneration, use regenerate_dleq_hints.py
/// which already decompresses from test vectors.

#[cfg(test)]
mod output_coordinates_tests {
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::G1PointTrait;
    use core::integer::u256;

    const ED25519_CURVE_INDEX: u32 = 4;

    // Test vector constants (from test_e2e_dleq.cairo - MUST MATCH EXACTLY)
    const TEST_ADAPTOR_POINT_COMPRESSED: u256 = u256 {
        low: 0x54e86953e7cc99b545cfef03f63cce85,
        high: 0x427dde0adb325f957d29ad71e4643882,
    };
    const TEST_ADAPTOR_POINT_SQRT_HINT: u256 = u256 {
        low: 0x448c18dcf34127e112ff945a65defbfc,
        high: 0x17611da35f39a2a5e3a9fddb8d978e4f,
    };

    const TEST_SECOND_POINT_COMPRESSED: u256 = u256 {
        low: 0xd893b3476bdf09770b7616f84c5c7bbe,
        high: 0x5c79d0fa84d6440908e2e2065e60d1cd,
    };
    const TEST_SECOND_POINT_SQRT_HINT: u256 = u256 {
        low: 0xdcad2173817c163b5405cec7698eb4b8,
        high: 0x742bb3c44b13553c8ddff66565b44cac,
    };

    #[test]
    fn verify_adaptor_point_decompression() {
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
        
        // Verify decompression succeeded
        // Coordinates can be accessed via: adaptor.x.limb0, adaptor.x.limb1, etc.
        // To extract for hint regeneration, use regenerate_dleq_hints.py
        assert(true, 'Decompress OK');
    }
    
    #[test]
    fn verify_second_point_decompression() {
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
        
        // Verify decompression succeeded
        assert(true, 'Decompress OK');
    }
}

