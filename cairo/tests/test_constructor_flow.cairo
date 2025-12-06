/// Test that mimics constructor flow to isolate the error
/// This helps identify which specific step fails

#[cfg(test)]
mod constructor_flow_tests {
    use atomic_lock::blake2s_challenge::compute_dleq_challenge_blake2s;
    use core::array::ArrayTrait;
    use core::integer::u256;
    use garaga::signatures::eddsa_25519::decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point;
    use garaga::ec_ops::G1PointTrait;
    use atomic_lock::AtomicLock::{is_small_order_ed25519, ED25519_CURVE_INDEX, ED25519_ORDER};

    // Test vector constants (from test_e2e_dleq.cairo)
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

    const TEST_R1_COMPRESSED: u256 = u256 {
        low: 0x47cff7b5713428a889bfad01f6fa4e00,
        high: 0x0850ef802e40bbd177b22dd7319a9bc0,
    };
    const TEST_R1_SQRT_HINT: u256 = u256 {
        low: 0x9f3ee81fe68dcbcf9de661eedd114a9e,
        high: 0x397c8b3280ddfb2ffe72518d79cc504c,
    };

    const TEST_R2_COMPRESSED: u256 = u256 {
        low: 0x47cff7b5713428a889bfad01f6fa4e00,
        high: 0x0850ef802e40bbd177b22dd7319a9bc0,
    };
    const TEST_R2_SQRT_HINT: u256 = u256 {
        low: 0x9f3ee81fe68dcbcf9de661eedd114a9e,
        high: 0x397c8b3280ddfb2ffe72518d79cc504c,
    };

    const ED25519_BASE_POINT_COMPRESSED: u256 = u256 {
        low: 0x66666666666666666666666666666666,
        high: 0x58666666666666666666666666666666,
    };

    const ED25519_SECOND_GENERATOR_COMPRESSED: u256 = u256 {
        low: 0x66666666666666666666666666666666,
        high: 0x58666666666666666666666666666666,
    };

    const TEST_VECTOR_HASHLOCK: [u32; 8] = [
        0x81caacb6_u32, 0x859a93a0_u32, 0xc4e4356c_u32, 0xb9958e18_u32,
        0xb1aa3117_u32, 0x4c9a62d4_u32, 0x09dd79ee_u32, 0x94fcd4de_u32,
    ];

    #[test]
    fn test_step_by_step_constructor_flow() {
        // Step 1: Decompress adaptor point
        let adaptor_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_ADAPTOR_POINT_SQRT_HINT
        );
        if adaptor_result.is_none() {
            assert(false, 'Step 1 failed: adaptor decompress');
        }
        let adaptor = adaptor_result.unwrap();
        adaptor.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(!is_small_order_ed25519(adaptor), 'Step 1: small order');
        
        // Step 2: Decompress second point
        let second_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_SECOND_POINT_COMPRESSED,
            TEST_SECOND_POINT_SQRT_HINT
        );
        if second_result.is_none() {
            assert(false, 'Step 2 failed: second decompress');
        }
        let second = second_result.unwrap();
        second.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(!is_small_order_ed25519(second), 'Step 2: small order');
        
        // Step 3: Decompress R1
        let r1_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_R1_COMPRESSED,
            TEST_R1_SQRT_HINT
        );
        if r1_result.is_none() {
            assert(false, 'Step 3 failed: R1 decompress');
        }
        let r1 = r1_result.unwrap();
        r1.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(!is_small_order_ed25519(r1), 'Step 3: small order');
        
        // Step 4: Decompress R2
        let r2_result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            TEST_R2_COMPRESSED,
            TEST_R2_SQRT_HINT
        );
        if r2_result.is_none() {
            assert(false, 'Step 4 failed: R2 decompress');
        }
        let r2 = r2_result.unwrap();
        r2.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(!is_small_order_ed25519(r2), 'Step 4: small order');
        
        // Step 5: Compute challenge
        let hashlock = TEST_VECTOR_HASHLOCK.span();
        let challenge = compute_dleq_challenge_blake2s(
            ED25519_BASE_POINT_COMPRESSED,
            ED25519_SECOND_GENERATOR_COMPRESSED,
            TEST_ADAPTOR_POINT_COMPRESSED,
            TEST_SECOND_POINT_COMPRESSED,
            TEST_R1_COMPRESSED,
            TEST_R2_COMPRESSED,
            hashlock,
            ED25519_ORDER,
        );
        
        // Step 6: All steps passed
        assert(true, 'All steps OK');
    }
}

