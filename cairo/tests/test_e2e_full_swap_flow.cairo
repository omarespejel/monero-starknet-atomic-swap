/// # Full Swap Flow Test
///
/// Tests the complete atomic swap lifecycle:
/// 1. Deploy with valid DLEQ proof
/// 2. Call verify_and_unlock with correct secret
/// 3. Verify unlocked == true
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
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
    use core::integer::u256;
    
    // Constants from test_e2e_dleq.cairo
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
    const TESTVECTOR_CHALLENGE_LOW: felt252 = 0xff93d53eda6f2910e3a1313a226533c5;
    const TESTVECTOR_RESPONSE_LOW: felt252 = 0xc09b9a31d72db277d1bb402e80ef5008;
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
        low: 0xdcad2173817c163b5405cec7698eb4b8,
        high: 0x742bb3c44b13553c8ddff66565b44cac,
    };
    const TEST_R1_SQRT_HINT: u256 = u256 { 
        low: 0x72a9698d3171817c239f4009cc36fc97,
        high: 0x3f2b84592a9ee701d24651e3aa3c837d,
    };
    const TEST_R2_SQRT_HINT: u256 = u256 { 
        low: 0x43f2c451f9ca69ff1577d77d646a50e,
        high: 0x4ee64b0e07d89e906f9e8b7bea09283e,
    };
    
    fn get_real_msm_hints() -> (
        Span<felt252>,
        Span<felt252>,
        Span<felt252>,
        Span<felt252>,
    ) {
        let s_hint_for_g = array![
            0xa82b6800cf6fafb9e422ff00,
            0xa9d32170fa1d6e70ce9f5875,
            0x38d522e54f3cc905,
            0x0,
            0x6632b6936c8a0092f2fa8193,
            0x48849326ffd29b0fd452c82e,
            0x1cb22722b8aeac6d,
            0x0,
            0x3ce8213ee078382bd7862b141d23a01e,
            0x12a88328ee6fe07c656e9f1f11921d2ff
        ].span();
        
        let s_hint_for_y = array![
            0x5f8703b67e528a68c666436f,
            0x4319c91a2264dceb203b3c7,
            0x131bcf26d61c6749,
            0x0,
            0x2b9edf9810114e3f99120ee8,
            0x23ac0997ff9d26665393f4f1,
            0xa2adc2ad21db8d1,
            0x0,
            0x3ce8213ee078382bd7862b141d23a01e,
            0x12a88328ee6fe07c656e9f1f11921d2ff
        ].span();
        
        let c_neg_hint_for_t = array![
            0xcc7bbab2a86720f06fa72b5a,
            0x27ebc6cd7c83bd71f4819168,
            0x2b4af1beb7dc4112,
            0x0,
            0xd0ac52873f110a396803c36c,
            0xc23304c89672797661dbefa3,
            0x547b7c3862004a5a,
            0x0,
            0xba5f45d69eaafbaaa06091a65e2873d,
            0x1301450999c6615fa5bded0ada7e22902
        ].span();
        
        let c_neg_hint_for_u = array![
            0x3aa67aef7c64a7b253e4a0fc,
            0x2799eb3ed1784408cb1f6360,
            0x6d7fa630d5721877,
            0x0,
            0x9fed6006f4d300b627b45f,
            0xf8f69fd5bc96748bf6e2541b,
            0x56b40a0879ad40ae,
            0x0,
            0xba5f45d69eaafbaaa06091a65e2873d,
            0x1301450999c6615fa5bded0ada7e22902
        ].span();
        
        (s_hint_for_g, s_hint_for_y, c_neg_hint_for_t, c_neg_hint_for_u)
    }
    
    fn deploy_contract() -> atomic_lock::IAtomicLockDispatcher {
        // Use the same deployment logic as test_e2e_dleq.cairo
        // This is a placeholder - full implementation would use deploy_with_real_dleq
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
        Serde::serialize(@0_u256, ref calldata);
        
        Serde::serialize(@TESTVECTOR_T_COMPRESSED, ref calldata);
        Serde::serialize(@TEST_ADAPTOR_POINT_SQRT_HINT, ref calldata);
        Serde::serialize(@TESTVECTOR_U_COMPRESSED, ref calldata);
        Serde::serialize(@TEST_SECOND_POINT_SQRT_HINT, ref calldata);
        Serde::serialize(@TESTVECTOR_CHALLENGE_LOW, ref calldata);
        Serde::serialize(@TESTVECTOR_RESPONSE_LOW, ref calldata);
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
        
        // Call verify_and_unlock with correct secret
        // Note: This will fail if token transfer is required (amount > 0)
        // For now, we test with amount = 0 (no token transfer)
        let success = contract.verify_and_unlock(secret);
        assert(success, 'Unlock should succeed');
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
    #[ignore] // Requires time manipulation in test environment
    fn test_refund_after_expiry() {
        // TODO: Deploy contract, wait for expiry, call refund
        // Verify refund succeeds
    }
}

