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
        low: 0x3cb02521d7a17fedca11c02ea41fe334,
        high: 0x11ef09256f90d942ca7a0e4ae05926a5,
    };
    const TESTVECTOR_R2_COMPRESSED: u256 = u256 {
        low: 0xb4fb26c272cbe6b84d65d4f908aff02f,
        high: 0xf58498fd33c0fbca066f3fdff2f49225,
    };
    const TESTVECTOR_CHALLENGE_LOW: felt252 = 0x8d664bb70810bdab323a44354d98f94a;
    const TESTVECTOR_RESPONSE_LOW: felt252 = 0x1e741f8fec4161ea41b23ce6d007ba12;
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
        low: 0x623d9789d855bcc4f0fbd8683b350688,
        high: 0x0a2d15cdfbfcf6181e92f0b7c74b477e,
    };
    const TEST_R2_SQRT_HINT: u256 = u256 { 
        low: 0x598521e3f6d818ed84721901f0d87f89,
        high: 0x09d2fd2811966933dff4c8ab0d9059fc,
    };
    
    fn get_real_msm_hints() -> (
        Span<felt252>,
        Span<felt252>,
        Span<felt252>,
        Span<felt252>,
    ) {
        let s_hint_for_g = array![

            0x52f522935135e7c5474d3b99,

            0x7ff7e65231c434008a0c02f8,

            0x41a3962ca5bba9db,

            0x0,

            0xa144206dc24b7180d05200e0,

            0xe8a798301a354777473cd98e,

            0x7ca5add375ea088,

            0x0,

            0x1e741f8fec4161ea41b23ce6d007ba12,

            0x100000000000000000000000000000001

        ].span();
        
        let s_hint_for_y = array![

        
            0x3b81c211fd322bb7dbcb711c,

        
            0x2082c0dd34f9225f2eb5e0b0,

        
            0x311b02be49202932,

        
            0x0,

        
            0x18c0245425f95187b10e1913,

        
            0x922be9d1d5313d1c7a4cb499,

        
            0x51d9b0eb8a969e37,

        
            0x0,

        
            0x1e741f8fec4161ea41b23ce6d007ba12,

        
            0x100000000000000000000000000000001

        
        ].span();
        
        let c_neg_hint_for_t = array![

        
            0xcb63575f3729fe6cbe7f8496,

        
            0x9dc314d92447fddbfc1be6cd,

        
            0x7d6caff1e7cdaa02,

        
            0x0,

        
            0x78dc46b41742aa135083e2da,

        
            0xecafad9bd49fe98686457cc6,

        
            0x592bb6f3eaf7ca3,

        
            0x0,

        
            0x34a3efff5488d0dfc135bf37e3357b53,

        
            0x1cf7b1760ae5d3463a08a196fd625720

        
        ].span();
        
        let c_neg_hint_for_u = array![

        
            0x61ebcae684d8530622e29b45,

        
            0x694dbc34734f56c0e29f5240,

        
            0x1913755501e61b9a,

        
            0x0,

        
            0x2a37ba10878046ff378a7d73,

        
            0x25857fe5ce7f65cea1bbc1e0,

        
            0xca82b2053c5e43e,

        
            0x0,

        
            0x34a3efff5488d0dfc135bf37e3357b53,

        
            0x1cf7b1760ae5d3463a08a196fd625720

        
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

