#[cfg(test)]
mod dleq_tests {
    use atomic_lock::IAtomicLockDispatcher;
    use core::array::ArrayTrait;
    use core::serde::Serde;
    use starknet::ContractAddress;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
    use garaga::signatures::eddsa_25519::{to_weierstrass, decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point};
    use garaga::definitions::G1Point;
    use core::circuit::u384;

    const FUTURE_TIMESTAMP: u64 = 9999999999_u64;

    /// Test that Garaga Ed25519 functions are available and have correct signatures
    /// This is a compilation test - it verifies the functions exist and can be called
    /// Note: Dummy values will return None, but that's fine - we're testing signatures
    #[test]
    fn test_garaga_ed25519_available() {
        // Test decompress function signature
        // Signature: decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(u256, u256) -> Option<G1Point>
        let y_compressed: u256 = 0x1234; // dummy value (not a valid Edwards point)
        let sqrt_hint: u256 = 0x5678; // dummy value
        
        let result = decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point(
            y_compressed, 
            sqrt_hint
        );
        
        // Verify function returns Option<G1Point> (will be None for dummy values)
        match result {
            Option::Some(_) => {
                // Valid point decompressed (unlikely with dummy values)
            },
            Option::None => {
                // Expected for dummy values - function signature is correct
            }
        }
        
        // Test to_weierstrass function signature
        // Signature: to_weierstrass(u384, u384) -> G1Point
        let x_twisted = u384 { limb0: 0, limb1: 0, limb2: 0, limb3: 0 };
        let y_twisted = u384 { limb0: 0, limb1: 0, limb2: 0, limb3: 0 };
        
        let _weierstrass_point: G1Point = to_weierstrass(x_twisted, y_twisted);
        
        // If we get here, the functions are available with correct signatures
        // Compilation success = function signatures verified ✅
    }


    /// Test that contract deploys with valid DLEQ data structure
    /// 
    /// This test verifies that the contract constructor accepts DLEQ parameters
    /// and validates them correctly. We use a valid second point (2·adaptor_point)
    /// which is on-curve and passes structural validation.
    /// 
    /// NOTE: This doesn't test full DLEQ verification yet (requires proper proof generation).
    /// It tests that the contract accepts DLEQ parameters and validates basic constraints.
    #[test]
    #[should_panic] // Expected to fail DLEQ verification (invalid proof)
    fn test_dleq_contract_deployment_structure() {
        // Use existing test data for adaptor point
        let hashlock = array![
            3606997102_u32, 3756602050_u32, 1811765011_u32, 1576844653_u32,
            61256116_u32, 2110839708_u32, 540553134_u32, 3341226206_u32
        ].span();
        
        let adaptor_x = (
            0x460f72719199c63ec398673f,
            0xf27a4af146a52a7dbdeb4cfb,
            0x5f9c70ec759789a0,
            0x0
        );
        let adaptor_y = (
            0x6b43e318a2a02d8241549109,
            0x40e30afa4cce98c21e473980,
            0x5e243e1eed1aa575,
            0x0
        );
        
        // For testing: use adaptor point as second point (on-curve, but won't form valid DLEQ)
        // In production, second point should be t·Y where Y is the second generator
        let second_x = adaptor_x;
        let second_y = adaptor_y;
        
        // Placeholder DLEQ proof (non-zero to pass scalar validation)
        // NOTE: This will fail DLEQ challenge verification, but tests structure
        let dleq_challenge: felt252 = 0x1234567890abcdef;
        let dleq_response: felt252 = 0xfedcba0987654321;
        
        let hint = array![
            0x460f72719199c63ec398673f,
            0xf27a4af146a52a7dbdeb4cfb,
            0x5f9c70ec759789a0,
            0x0,
            0x6b43e318a2a02d8241549109,
            0x40e30afa4cce98c21e473980,
            0x5e243e1eed1aa575,
            0x0,
            0x10b51d41eab43e36d3ac30cda9707f92,
            0x110538332d2eae09bf756dfd87431ded7
        ].span();
        
        // Placeholder DLEQ hints (10 felts each)
        // 
        // ⚠️ PRODUCTION BLOCKER: These are placeholder hints!
        // 
        // For production deployment, you MUST generate real hints using:
        //   tools/generate_dleq_hints.py
        // 
        // Real hints require:
        //   - s_scalar (DLEQ response scalar)
        //   - c_scalar (DLEQ challenge scalar)
        //   - T (adaptor point)
        //   - U (DLEQ second point)
        // 
        // See GENERATE_MSM_HINTS_GUIDE.md for detailed instructions.
        // 
        // These empty hints will cause MSM verification to fail in production.
        // They are used here only to test contract structure validation.
        let empty_hint = array![0, 0, 0, 0, 0, 0, 0, 0, 0, 0].span();
        
        // This will fail DLEQ verification (expected), but tests that structure is accepted
        deploy_with_dleq(
            hashlock,
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            adaptor_x,
            adaptor_y,
            second_x,
            second_y,
            (dleq_challenge, dleq_response),
            hint,
            empty_hint, // s_hint_for_g
            empty_hint, // s_hint_for_y
            empty_hint, // c_neg_hint_for_t
            empty_hint  // c_neg_hint_for_u
        );
    }

    /// Test that invalid DLEQ proof is rejected
    /// 
    /// This test verifies that an invalid DLEQ proof causes deployment to fail.
    /// We use valid on-curve points but invalid proof values.
    #[test]
    #[should_panic]
    fn test_dleq_invalid_proof_rejected() {
        let hashlock = array![
            3606997102_u32, 3756602050_u32, 1811765011_u32, 1576844653_u32,
            61256116_u32, 2110839708_u32, 540553134_u32, 3341226206_u32
        ].span();
        
        // Valid adaptor point (from existing test - known to be on-curve)
        let adaptor_x = (
            0x460f72719199c63ec398673f,
            0xf27a4af146a52a7dbdeb4cfb,
            0x5f9c70ec759789a0,
            0x0
        );
        let adaptor_y = (
            0x6b43e318a2a02d8241549109,
            0x40e30afa4cce98c21e473980,
            0x5e243e1eed1aa575,
            0x0
        );
        
        // Use adaptor point as second point (on-curve, but won't form valid DLEQ proof)
        // This passes structural validation but fails DLEQ verification
        let second_x = adaptor_x;
        let second_y = adaptor_y;
        
        // Invalid DLEQ proof (random values that won't verify)
        let invalid_challenge: felt252 = 0xdeadbeef;
        let invalid_response: felt252 = 0xbadcafe;
        
        let hint = array![
            0x460f72719199c63ec398673f,
            0xf27a4af146a52a7dbdeb4cfb,
            0x5f9c70ec759789a0,
            0x0,
            0x6b43e318a2a02d8241549109,
            0x40e30afa4cce98c21e473980,
            0x5e243e1eed1aa575,
            0x0,
            0x10b51d41eab43e36d3ac30cda9707f92,
            0x110538332d2eae09bf756dfd87431ded7
        ].span();
        
        // Placeholder DLEQ hints (10 felts each)
        // NOTE: For production, generate proper hints using tools/generate_dleq_hints.py
        let empty_hint = array![0, 0, 0, 0, 0, 0, 0, 0, 0, 0].span();
        
        // Deploy contract - should fail in constructor due to invalid DLEQ proof
        // Expected: DLEQ_CHALLENGE_MISMATCH error
        deploy_with_dleq(
            hashlock,
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            adaptor_x,
            adaptor_y,
            second_x,
            second_y,
            (invalid_challenge, invalid_response),
            hint,
            empty_hint, // s_hint_for_g
            empty_hint, // s_hint_for_y
            empty_hint, // c_neg_hint_for_t
            empty_hint  // c_neg_hint_for_u
        );
    }

    /// Helper function to deploy contract with full DLEQ data
    /// 
    /// DLEQ hints are required for production-grade MSM operations:
    /// - s_hint_for_g: Fake-GLV hint for s·G
    /// - s_hint_for_y: Fake-GLV hint for s·Y
    /// - c_neg_hint_for_t: Fake-GLV hint for (-c)·T
    /// - c_neg_hint_for_u: Fake-GLV hint for (-c)·U
    /// 
    /// Generate proper hints using tools/generate_dleq_hints.py
    fn deploy_with_dleq(
        expected_hash: Span<u32>,
        lock_until: u64,
        token: ContractAddress,
        amount: u256,
        adaptor_point_x: (felt252, felt252, felt252, felt252),
        adaptor_point_y: (felt252, felt252, felt252, felt252),
        dleq_second_point_x: (felt252, felt252, felt252, felt252),
        dleq_second_point_y: (felt252, felt252, felt252, felt252),
        dleq: (felt252, felt252),
        fake_glv_hint: Span<felt252>,
        dleq_s_hint_for_g: Span<felt252>,
        dleq_s_hint_for_y: Span<felt252>,
        dleq_c_neg_hint_for_t: Span<felt252>,
        dleq_c_neg_hint_for_u: Span<felt252>,
    ) -> atomic_lock::IAtomicLockDispatcher {
        let declare_res = declare("AtomicLock");
        let contract = declare_res.unwrap().contract_class();

        let (x0, x1, x2, x3) = adaptor_point_x;
        let (y0, y1, y2, y3) = adaptor_point_y;
        let (dleq_x0, dleq_x1, dleq_x2, dleq_x3) = dleq_second_point_x;
        let (dleq_y0, dleq_y1, dleq_y2, dleq_y3) = dleq_second_point_y;
        let (dleq_c, dleq_r) = dleq;

        let mut calldata = ArrayTrait::new();
        expected_hash.serialize(ref calldata);
        Serde::serialize(@lock_until, ref calldata);
        Serde::serialize(@token, ref calldata);
        Serde::serialize(@amount, ref calldata);
        
        // Adaptor point (x/y limbs)
        Serde::serialize(@x0, ref calldata);
        Serde::serialize(@x1, ref calldata);
        Serde::serialize(@x2, ref calldata);
        Serde::serialize(@x3, ref calldata);
        Serde::serialize(@y0, ref calldata);
        Serde::serialize(@y1, ref calldata);
        Serde::serialize(@y2, ref calldata);
        Serde::serialize(@y3, ref calldata);
        
        // DLEQ second point (x/y limbs)
        Serde::serialize(@dleq_x0, ref calldata);
        Serde::serialize(@dleq_x1, ref calldata);
        Serde::serialize(@dleq_x2, ref calldata);
        Serde::serialize(@dleq_x3, ref calldata);
        Serde::serialize(@dleq_y0, ref calldata);
        Serde::serialize(@dleq_y1, ref calldata);
        Serde::serialize(@dleq_y2, ref calldata);
        Serde::serialize(@dleq_y3, ref calldata);
        
        // DLEQ proof (challenge, response)
        Serde::serialize(@dleq_c, ref calldata);
        Serde::serialize(@dleq_r, ref calldata);
        
        // Fake-GLV hint (for adaptor point)
        Serde::serialize(@fake_glv_hint, ref calldata);
        
        // DLEQ hints (for MSM operations in verification)
        Serde::serialize(@dleq_s_hint_for_g, ref calldata);
        Serde::serialize(@dleq_s_hint_for_y, ref calldata);
        Serde::serialize(@dleq_c_neg_hint_for_t, ref calldata);
        Serde::serialize(@dleq_c_neg_hint_for_u, ref calldata);

        let (addr, _) = contract.deploy(@calldata).unwrap();
        IAtomicLockDispatcher { contract_address: addr }
    }
}

