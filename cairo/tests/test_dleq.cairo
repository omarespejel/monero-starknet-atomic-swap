#[cfg(test)]
mod dleq_tests {
    use atomic_lock::{IAtomicLockDispatcher, IAtomicLockDispatcherTrait};
    use core::array::ArrayTrait;
    use core::serde::Serde;
    use starknet::ContractAddress;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};

    const FUTURE_TIMESTAMP: u64 = 9999999999_u64;


    /// Test that contract deploys with valid DLEQ data structure
    /// 
    /// This test verifies that the contract constructor accepts DLEQ parameters
    /// and validates them correctly. For now, we use placeholder values that pass
    /// structural validation (on-curve points, non-zero scalars).
    /// 
    /// NOTE: This doesn't test full DLEQ verification yet (requires proper proof generation).
    /// It tests that the contract accepts DLEQ parameters and validates basic constraints.
    #[test]
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
        
        // Use same point for second point (placeholder - should be t·Y)
        // This will pass structural validation but fail DLEQ verification
        let second_x = adaptor_x;
        let second_y = adaptor_y;
        
        // Placeholder DLEQ proof (non-zero to pass validation)
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
        
        // This will fail DLEQ verification, but tests that structure is accepted
        // We expect it to panic with DLEQ_CHALLENGE_MISMATCH
        let result = deploy_with_dleq(
            hashlock,
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            adaptor_x,
            adaptor_y,
            second_x,
            second_y,
            (dleq_challenge, dleq_response),
            hint
        );
        
        // If we get here, the structure was accepted (but DLEQ verification should have failed)
        // This test mainly verifies that the contract accepts DLEQ parameters
    }

    /// Test that invalid DLEQ proof is rejected
    /// 
    /// This test verifies that an invalid DLEQ proof causes deployment to fail.
    /// We use placeholder values that don't form a valid proof.
    #[test]
    #[should_panic]
    fn test_dleq_invalid_proof_rejected() {
        let hashlock = array![
            3606997102_u32, 3756602050_u32, 1811765011_u32, 1576844653_u32,
            61256116_u32, 2110839708_u32, 540553134_u32, 3341226206_u32
        ].span();
        
        // Valid adaptor point (from existing test)
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
        
        // Use same point for second point (won't form valid DLEQ proof)
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
        
        // Deploy contract - should fail in constructor due to invalid DLEQ proof
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
            hint
        );
    }

    /// Helper function to deploy contract with full DLEQ data
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
        
        // Fake-GLV hint
        Serde::serialize(@fake_glv_hint, ref calldata);

        let (addr, _) = contract.deploy(@calldata).unwrap();
        IAtomicLockDispatcher { contract_address: addr }
    }
}

