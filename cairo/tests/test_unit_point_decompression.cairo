/// # Point Decompression Diagnostic Test
///
/// Isolates which point decompression is failing in the end-to-end test
/// This helps identify if the issue is with sqrt hints or compressed point format

#[cfg(test)]
mod point_decompression_tests {
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::G1PointTrait;
    use core::integer::u256;

    const ED25519_CURVE_INDEX: u32 = 4;  // Ed25519 uses curve index 4 in Garaga

    // Test vectors from test_e2e_dleq.cairo
    const TEST_ADAPTOR_POINT_COMPRESSED: u256 = u256 {
        low: 0x54e86953e7cc99b545cfef03f63cce85,
        high: 0x427dde0adb325f957d29ad71e4643882,
    };

    // CORRECT sqrt hint - matches test_e2e_dleq.cairo (PASSING TESTS)
    // Updated from wrong value: 0xbb73e7230cbed81eed006ba59a2103f1/0x689ee25ca0c65d5a1c560224726871b0
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

    // CORRECT R1 from test_vectors.cairo (matches test_e2e_dleq.cairo)
    const TEST_R1_COMPRESSED: u256 = u256 {
        low: 0x90b1ab352981d43ec51fba0af7ab51c7,
        high: 0xc21ebc88e5e59867b280909168338026,
    };

    // CORRECT R1 sqrt hint (matches test_e2e_dleq.cairo)
    const TEST_R1_SQRT_HINT: u256 = u256 { 
        low: 0x72a9698d3171817c239f4009cc36fc97,
        high: 0x3f2b84592a9ee701d24651e3aa3c837d,
    };
    
    // CORRECT R2 from test_vectors.cairo (matches test_e2e_dleq.cairo)
    const TEST_R2_COMPRESSED: u256 = u256 {
        low: 0x02d386e8fd6bd85a339171211735bcba,
        high: 0x10defc0130a9f3055798b1f5a99aeb67,
    };
    
    // CORRECT R2 sqrt hint (matches test_e2e_dleq.cairo)
    const TEST_R2_SQRT_HINT: u256 = u256 { 
        low: 0x43f2c451f9ca69ff1577d77d646a50e,
        high: 0x4ee64b0e07d89e906f9e8b7bea09283e,
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

