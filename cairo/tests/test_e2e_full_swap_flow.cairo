/// # Full Swap Flow Test
///
/// Tests the complete atomic swap lifecycle:
/// 1. Deploy with valid DLEQ proof
/// 2. Call verify_and_unlock with correct secret
/// 3. Verify reveal state, then claim after grace period
/// 4. Test unlock with wrong secret (should fail)
/// 5. Test refund after expiry

#[cfg(test)]
mod full_swap_flow_tests {
    use atomic_lock::IAtomicLockDispatcher;
    use atomic_lock::IAtomicLockDispatcherTrait;
    use core::array::ArrayTrait;
    use core::byte_array::{ByteArray, ByteArrayTrait};
    use core::serde::Serde;
    use core::traits::TryInto;
    use starknet::ContractAddress;
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait,
        start_cheat_block_timestamp, stop_cheat_block_timestamp,
        start_cheat_caller_address, stop_cheat_caller_address,
    };
    use core::integer::u256;
    
    // Constants from test_e2e_dleq.cairo
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
    const TESTVECTOR_CHALLENGE: felt252 = 0x47c760eb9b6a8797680bef6218e06aacc6570f8be11819d2268bb024f816108;
    const TESTVECTOR_RESPONSE: u256 = u256 { low: 0xbe3ffdd10e06b50b800feb45877b787b, high: 0x2f0ceba8a8c56d6f6b4ed3ae98db234 };
    const TESTVECTOR_HASHLOCK: [u32; 8] = [
        0xb6acca81_u32, 0xa0939a85_u32, 0x6c35e4c4_u32, 0x188e95b9_u32,
        0x1731aab1_u32, 0xd4629a4c_u32, 0xee79dd09_u32, 0xded4fc94_u32,
    ];
    
    const FUTURE_TIMESTAMP: u64 = 9999999999_u64;
    
    const TEST_ADAPTOR_POINT_SQRT_HINT: u256 = u256 {
        low: 0x448c18dcf34127e112ff945a65defbfc,
        high: 0x17611da35f39a2a5e3a9fddb8d978e4f,
    };
    const TEST_SECOND_POINT_SQRT_HINT: u256 = u256 {
        low: 0xcffea6b3bffe746de20fdd0734b30845,
        high: 0x5e4a3b18b41199f9389ded8696067271,
    };
    const TEST_R1_SQRT_HINT: u256 = u256 { 
        low: 0x623d9789d855bcc4f0fbd8683b350688,
        high: 0x0a2d15cdfbfcf6181e92f0b7c74b477e,
    };
    const TEST_R2_SQRT_HINT: u256 = u256 { 
        low: 0xd8b08d5ec3d265b83e5e333d750d6b37,
        high: 0x0e41fbdbbf62b47c511e0a5aa04059de,
    };
    
    fn get_real_msm_hints() -> (
        Span<felt252>,
        Span<felt252>,
        Span<felt252>,
        Span<felt252>,
    ) {
        let s_hint_for_g = array![
            0xceeec4a90f34e45c033e2ff5,
            0xb419479f38f86b2b114d2ff1,
            0x256941d7d54e7beb,
            0x0,
            0xaa6ddc025eb012317a89612a,
            0x6e9d804e52cb98594f552df2,
            0x47244d9888c072a3,
            0x0,
            0xcd234e4105b9809a3f4f0dde019dac1,
            0x1268c27967bf37239a1bdcad1722144e1
        ].span();
        
        let s_hint_for_y = array![
            0x872011d1a9f20fc5fbed65ec,
            0xd36e4710d58461cfe9c9ee1d,
            0x686f29bbaf2b952f,
            0x0,
            0xf350a6f8bc8acbb1d5c40cd5,
            0x4b256a3dba76a0bc779c811,
            0x43f41814a3eefa59,
            0x0,
            0xcd234e4105b9809a3f4f0dde019dac1,
            0x1268c27967bf37239a1bdcad1722144e1
        ].span();
        
        let c_neg_hint_for_t = array![
            0xfbeb7a88a7204a3109847933,
            0xd7bd766f54592bfb04b8a0bf,
            0x36adfbd5b292a10e,
            0x0,
            0xb1cb68d66c0170146df52bb2,
            0x7ad50b1ffcd1293f12940e01,
            0x665e063c6d4ac0f6,
            0x0,
            0x4d5cf08f2a0aee991f621d5e4e15728,
            0x1148705832ba97f2b70dec32979f4f785
        ].span();
        
        let c_neg_hint_for_u = array![
            0x16ecdc108960cb810ed61451,
            0x28bf80201d67e2f4728ba74b,
            0x63f872f4f71e1950,
            0x0,
            0xe94caf1beb68a19f34eb98a4,
            0x48bcbcb46602eeea1b043d0d,
            0x52e390f474357096,
            0x0,
            0x4d5cf08f2a0aee991f621d5e4e15728,
            0x1148705832ba97f2b70dec32979f4f785
        ].span();
        
        (s_hint_for_g, s_hint_for_y, c_neg_hint_for_t, c_neg_hint_for_u)
    }
    
    fn deploy_contract() -> atomic_lock::IAtomicLockDispatcher {
        // Use the same validated deployment vector path as test_e2e_dleq.cairo.
        let declare_res = declare("AtomicLock");
        let contract = declare_res.unwrap().contract_class();
        
        let hashlock = TESTVECTOR_HASHLOCK.span();
        let (s_hint_for_g, s_hint_for_y, c_neg_hint_for_t, c_neg_hint_for_u) = get_real_msm_hints();
        
        // Fake-GLV hint for adaptor point MSM (from test_e2e_dleq.cairo)
        let fake_glv_hint = array![
            0x4af5bf430174455ca59934c5,           // Q.x limb0
            0x748d85ad870959a54bca47ba,           // Q.x limb1
            0x6decdae5e1b9b254,                   // Q.x limb2
            0x0,                                  // Q.x limb3
            0xaa008e6009b43d5c309fa848,           // Q.y limb0
            0x5b26ec9e21237560e1866183,           // Q.y limb1
            0x7191bfaa5a23d0cb,                   // Q.y limb2
            0x0,                                  // Q.y limb3
            0x1569bc348ca5e9beecb728fdbfea1cd6,   // s1
            0x28e2d5faa7b8c3b25a1678149337cad3   // s2_encoded
        ].span();
        
        let mut calldata = ArrayTrait::new();
        hashlock.serialize(ref calldata);
        Serde::serialize(@FUTURE_TIMESTAMP, ref calldata);
        let zero_address: ContractAddress = 0.try_into().unwrap();
        Serde::serialize(@zero_address, ref calldata);
        Serde::serialize(@zero_address, ref calldata);
        Serde::serialize(@0_u256, ref calldata);
        
        Serde::serialize(@TESTVECTOR_T_COMPRESSED, ref calldata);
        Serde::serialize(@TEST_ADAPTOR_POINT_SQRT_HINT, ref calldata);
        Serde::serialize(@TESTVECTOR_U_COMPRESSED, ref calldata);
        Serde::serialize(@TEST_SECOND_POINT_SQRT_HINT, ref calldata);
        Serde::serialize(@TESTVECTOR_CHALLENGE, ref calldata);
        Serde::serialize(@TESTVECTOR_RESPONSE, ref calldata);
        Serde::serialize(@fake_glv_hint, ref calldata);
        Serde::serialize(@s_hint_for_g, ref calldata);
        Serde::serialize(@s_hint_for_y, ref calldata);
        Serde::serialize(@c_neg_hint_for_t, ref calldata);
        Serde::serialize(@c_neg_hint_for_u, ref calldata);
        Serde::serialize(@TESTVECTOR_R1_COMPRESSED, ref calldata);
        Serde::serialize(@TEST_R1_SQRT_HINT, ref calldata);
        Serde::serialize(@TESTVECTOR_R2_COMPRESSED, ref calldata);
        Serde::serialize(@TEST_R2_SQRT_HINT, ref calldata);
        
        let (addr, _) = contract.deploy(@calldata).unwrap();
        IAtomicLockDispatcher { contract_address: addr }
    }
    
    /// Test: Full swap lifecycle - deploy and verify unlocked
    #[test]
    fn test_full_swap_lifecycle() {
        let contract = deploy_contract();
        let zero_address: ContractAddress = 0.try_into().unwrap();
        assert(contract.contract_address != zero_address, 'Contract deployed');
        
        // Verify contract starts locked
        assert(!contract.is_unlocked(), 'Contract should start locked');
        
        // Secret from test_vectors.json: 1212121212121212121212121212121212121212121212121212121212121212
        // This secret's SHA-256 matches TESTVECTOR_HASHLOCK
        let mut secret: ByteArray = Default::default();
        // Append all 32 bytes (0x12 repeated 32 times)
        secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8);
        secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8);
        secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8);
        secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8);
        secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8);
        secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8);
        secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8);
        secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8); secret.append_byte(0x12_u8);
        
        // Call legacy reveal alias with correct secret. It must not bypass the grace period.
        let success = contract.verify_and_unlock(secret);
        assert(success, 'Unlock should succeed');
        assert(contract.is_secret_revealed(), 'Secret revealed');
        assert(!contract.is_unlocked(), 'Grace period enforced');

        let claimable_after = contract.get_claimable_after();
        start_cheat_block_timestamp(contract.contract_address, claimable_after + 1);
        contract.claim_tokens();
        stop_cheat_block_timestamp(contract.contract_address);
        assert(contract.is_unlocked(), 'Contract should be unlocked');
    }
    
    /// Test: Unlock with wrong secret should fail
    #[test]
    fn test_unlock_with_wrong_secret() {
        let contract = deploy_contract();
        
        // Create wrong secret (different from test_vectors.json)
        let mut wrong_secret: ByteArray = Default::default();
        // Append wrong bytes (0x00 repeated 32 times instead of 0x12)
        wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8);
        wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8);
        wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8);
        wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8);
        wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8);
        wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8);
        wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8);
        wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8); wrong_secret.append_byte(0x00_u8);
        
        // Call verify_and_unlock with wrong secret - should return false (not panic)
        // The function returns false if hashlock doesn't match
        let success = contract.verify_and_unlock(wrong_secret);
        assert(!success, 'Unlock should fail');
        assert(!contract.is_unlocked(), 'Contract should remain locked');
    }
    
    /// Test: Refund after expiry
    #[test]
    fn test_refund_after_expiry() {
        let contract = deploy_contract();
        assert(!contract.is_unlocked(), 'start locked');

        start_cheat_block_timestamp(contract.contract_address, FUTURE_TIMESTAMP + 1);
        let depositor: ContractAddress = 0.try_into().unwrap();
        start_cheat_caller_address(contract.contract_address, depositor);
        let success = contract.refund();
        stop_cheat_caller_address(contract.contract_address);
        stop_cheat_block_timestamp(contract.contract_address);

        assert(success, 'refund ok');
        assert(contract.is_unlocked(), 'refunded');
    }
}
