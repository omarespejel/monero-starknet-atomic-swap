/// # DLEQ Challenge Computation Test (Isolated)
///
/// This test isolates the Poseidon challenge computation to verify transcript compatibility
/// without requiring point decompression or full DLEQ verification.
///
/// **Purpose**: Verify that Cairo's Poseidon challenge matches Rust's challenge computation
/// for the same inputs, confirming byte-order correctness.

#[cfg(test)]
mod dleq_challenge_only_tests {
    use atomic_lock::poseidon_challenge::compute_dleq_challenge_poseidon;
    use core::array::ArrayTrait;
    use core::integer::u256;
    // Constants from rust/test_vectors.json (match test_vectors.cairo)
    const TESTVECTOR_G_COMPRESSED: u256 = u256 {
        low: 0x66666666666666666666666666666658,
        high: 0x66666666666666666666666666666666,
    };
    const TESTVECTOR_Y_COMPRESSED: u256 = u256 {
        low: 0x21ba32594950b67cf0d8bb8c8ac5e8c7,
        high: 0xf08df421a3209ab6373dd0ec7ef25dfd,
    };
    const TESTVECTOR_T_COMPRESSED: u256 = u256 {
        low: 0x54e86953e7cc99b545cfef03f63cce85,
        high: 0x427dde0adb325f957d29ad71e4643882,
    };
    const TESTVECTOR_U_COMPRESSED: u256 = u256 {
        low: 0x9244eb3a3699efed3106c6ae0afdf28,
        high: 0xb6e0bfc0d9fbb8a4c8ef08cb5da2eff3,
    };
    const TESTVECTOR_R1_COMPRESSED: u256 = u256 {
        low: 0x3cb02521d7a17fedca11c02ea41fe334,
        high: 0x11ef09256f90d942ca7a0e4ae05926a5,
    };
    const TESTVECTOR_R2_COMPRESSED: u256 = u256 {
        low: 0xe66ca975ef303c032fcc18a952325162,
        high: 0xc5d2eb608176c8b79dfa55289c35b35f,
    };
    const ED25519_ORDER: u256 = u256 {
        low: 0x14def9dea2f79cd65812631a5cf5d3ed,
        high: 0x10000000000000000000000000000000,
    };
    const TESTVECTOR_CHALLENGE: felt252 = 0x47c760eb9b6a8797680bef6218e06aacc6570f8be11819d2268bb024f816108;

    /// Test: Compute challenge with Rust test vectors
    ///
    /// This test computes the DLEQ challenge using the exact same inputs as Rust
    /// and verifies the result. If byte-order is correct, the challenge should match.
    ///
    /// **Critical**: This test isolates challenge computation from point decompression,
    /// allowing us to verify byte-order independently.
    ///
    /// DEBUG: This test will fail intentionally to print the computed challenge value.
    /// Compare the printed value with Rust's expected challenge to identify byte-order issues.
    #[test]
    fn test_challenge_computation_with_rust_vectors() {
        // Use constants from single source of truth (test_vectors.cairo)
        // Note: Cairo doesn't support const array indexing, so use literal values
        // These match TESTVECTOR_HASHLOCK from test_vectors.cairo
        let hashlock = array![
            0xb6acca81_u32, 0xa0939a85_u32, 0x6c35e4c4_u32, 0x188e95b9_u32,
            0x1731aab1_u32, 0xd4629a4c_u32, 0xee79dd09_u32, 0xded4fc94_u32
        ].span();
        
        // Compute challenge using Cairo's Poseidon implementation
        let cairo_challenge = compute_dleq_challenge_poseidon(
            TESTVECTOR_G_COMPRESSED,
            TESTVECTOR_Y_COMPRESSED,
            TESTVECTOR_T_COMPRESSED,
            TESTVECTOR_U_COMPRESSED,
            TESTVECTOR_R1_COMPRESSED,
            TESTVECTOR_R2_COMPRESSED,
            hashlock,
            ED25519_ORDER,
        );

        assert(cairo_challenge == TESTVECTOR_CHALLENGE, 'Challenge mismatch');
        
        // Exact Rust/Cairo equality is asserted above; keep the extra checks for determinism.
        
        // Verify challenge is computed (non-zero for real inputs)
        assert(cairo_challenge != 0, 'Challenge computed');
        
        // Verify determinism (same inputs → same output)
        let cairo_challenge2 = compute_dleq_challenge_poseidon(
            TESTVECTOR_G_COMPRESSED,
            TESTVECTOR_Y_COMPRESSED,
            TESTVECTOR_T_COMPRESSED,
            TESTVECTOR_U_COMPRESSED,
            TESTVECTOR_R1_COMPRESSED,
            TESTVECTOR_R2_COMPRESSED,
            hashlock,
            ED25519_ORDER,
        );
        assert(cairo_challenge == cairo_challenge2, 'Challenge deterministic');
    }
    
    /// Test: Verify challenge changes with different inputs
    ///
    /// This ensures the challenge computation is sensitive to input changes,
    /// confirming that byte-order issues would be detected.
    #[test]
    fn test_challenge_sensitive_to_inputs() {
        let hashlock = array![
            0xd78e3502_u32, 0x108c5b5a_u32, 0x5c902f24_u32, 0x725ce15e_u32,
            0x14ab8e41_u32, 0x1b93285f_u32, 0x9c5b1405_u32, 0xf11dca4d_u32
        ].span();
        
        let point1 = u256 { low: 0x1234, high: 0 };
        let point2 = u256 { low: 0x5678, high: 0 };
        
        let challenge1 = compute_dleq_challenge_poseidon(
            TESTVECTOR_G_COMPRESSED,
            TESTVECTOR_Y_COMPRESSED,
            point1,
            point1,
            point1,
            point1,
            hashlock,
            ED25519_ORDER,
        );
        
        let challenge2 = compute_dleq_challenge_poseidon(
            TESTVECTOR_G_COMPRESSED,
            TESTVECTOR_Y_COMPRESSED,
            point2,
            point2,
            point2,
            point2,
            hashlock,
            ED25519_ORDER,
        );
        
        // Different inputs should produce different challenges
        assert(challenge1 != challenge2, 'Challenge sensitive');
    }
}
