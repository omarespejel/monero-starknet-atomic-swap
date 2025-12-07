/// # BLAKE2s State Debug Test
///
/// This test prints Cairo's BLAKE2s state words to compare with Rust's output.
/// The test will fail intentionally to show the actual state values.

#[cfg(test)]
mod blake2s_state_debug_tests {
    use atomic_lock::blake2s_challenge::compute_dleq_challenge_blake2s;
    use core::array::ArrayTrait;
    use core::integer::u256;
    
    // Constants from test_vectors.json (match test_vectors.cairo)
    const TESTVECTOR_G_COMPRESSED: u256 = u256 {
        low: 0x66666666666666666666666666666658,
        high: 0x66666666666666666666666666666666,
    };
    const TESTVECTOR_Y_COMPRESSED: u256 = u256 {
        low: 0x97390f51643851560e5f46ae6af8a3c9,
        high: 0x2260cdf3092329c21da25ee8c9a21f56,
    };
    const TESTVECTOR_T_COMPRESSED: u256 = u256 {
        low: 0x54e86953e7cc99b545cfef03f63cce85,
        high: 0x427dde0adb325f957d29ad71e4643882,
    };
    const TESTVECTOR_U_COMPRESSED: u256 = u256 {
        low: 0xd893b3476bdf09770b7616f84c5c7bbe,
        high: 0x5c79d0fa84d6440908e2e2065e60d1cd,
    };
    const TESTVECTOR_R1_COMPRESSED: u256 = u256 {
        low: 0x90b1ab352981d43ec51fba0af7ab51c7,
        high: 0xc21ebc88e5e59867b280909168338026,
    };
    const TESTVECTOR_R2_COMPRESSED: u256 = u256 {
        low: 0x02d386e8fd6bd85a339171211735bcba,
        high: 0x10defc0130a9f3055798b1f5a99aeb67,
    };
    const ED25519_ORDER: u256 = u256 {
        low: 0x14def9dea2f79cd65812631a5cf5d3ed,
        high: 0x10000000000000000000000000000000,
    };
    const TESTVECTOR_HASHLOCK: [u32; 8] = [
        0xb6acca81_u32,
        0xa0939a85_u32,
        0x6c35e4c4_u32,
        0x188e95b9_u32,
        0x1731aab1_u32,
        0xd4629a4c_u32,
        0xee79dd09_u32,
        0xded4fc94_u32,
    ];

    #[test]
    fn test_print_blake2s_state() {
        let hashlock_span = TESTVECTOR_HASHLOCK.span();
        
        // Compute challenge - this will trigger BLAKE2s computation
        let challenge = compute_dleq_challenge_blake2s(
            TESTVECTOR_G_COMPRESSED,
            TESTVECTOR_Y_COMPRESSED,
            TESTVECTOR_T_COMPRESSED,
            TESTVECTOR_U_COMPRESSED,
            TESTVECTOR_R1_COMPRESSED,
            TESTVECTOR_R2_COMPRESSED,
            hashlock_span,
            ED25519_ORDER,
        );
        
        // Convert challenge to u256 to extract low/high parts
        let challenge_u256: u256 = challenge.into();
        
        // Expected challenge from test_vectors.json (reduced scalar, LE bytes)
        // Challenge: 0xff93d53eda6f2910e3a1313a226533c503273bfddf78f5f07036fa2a12e61262
        // Convert to u256 (little-endian bytes)
        let expected_low: u128 = 0xff93d53eda6f2910e3a1313a226533c5;
        let expected_high: u128 = 0x03273bfddf78f5f07036fa2a12e61262;
        
        // Verify challenge matches expected (after reduction mod order)
        // The challenge is reduced in compute_dleq_challenge_blake2s
        assert(challenge_u256.low == expected_low, 'Challenge low mismatch');
        assert(challenge_u256.high == expected_high, 'Challenge high mismatch');
    }
}

