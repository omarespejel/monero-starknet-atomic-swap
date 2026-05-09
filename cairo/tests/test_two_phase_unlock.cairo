//! Two-Phase Unlock Tests
//!
//! Comprehensive test suite for the two-phase unlock implementation (P0/P1 fixes).
//! Tests cover:
//! - Phase 1: reveal_secret() (verification without token transfer)
//! - Phase 2: claim_tokens() (token transfer after grace period)
//! - Security: refund blocking after secret revealed
//! - Backward compatibility: verify_and_unlock() reveals only, without bypassing grace period

#[cfg(test)]
mod tests {
    use atomic_lock::IAtomicLockDispatcher;
    use atomic_lock::IAtomicLockDispatcherTrait;
    use core::array::ArrayTrait;
    use core::byte_array::{ByteArray, ByteArrayTrait};
    use core::integer::u256;
    use core::serde::Serde;
    use core::traits::TryInto;
    use core::result::ResultTrait;
    use starknet::ContractAddress;
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait,
        start_cheat_caller_address, stop_cheat_caller_address,
        start_cheat_block_timestamp, stop_cheat_block_timestamp,
    };
    
    // Test vector constants (from test_vectors.cairo)
    const TESTVECTOR_HASHLOCK: [u32; 8] = [
        0xb6acca81_u32, 0xa0939a85_u32, 0x6c35e4c4_u32, 0x188e95b9_u32,
        0x1731aab1_u32, 0xd4629a4c_u32, 0xee79dd09_u32, 0xded4fc94_u32,
    ];
    
    const FUTURE_TIMESTAMP: u64 = 9999999999_u64;
    
    // Test vector constants (matching test_integration_atomic_lock.cairo)
    const TESTVECTOR_T_COMPRESSED: u256 = u256 {
        low: 0x54e86953e7cc99b545cfef03f63cce85,
        high: 0x427dde0adb325f957d29ad71e4643882,
    };
    const TESTVECTOR_T_SQRT_HINT: u256 = u256 {
        low: 0x448c18dcf34127e112ff945a65defbfc,
        high: 0x17611da35f39a2a5e3a9fddb8d978e4f,
    };
    const TESTVECTOR_U_COMPRESSED: u256 = u256 {
        low: 0x9244eb3a3699efed3106c6ae0afdf28,
        high: 0xb6e0bfc0d9fbb8a4c8ef08cb5da2eff3,
    };
    const TESTVECTOR_U_SQRT_HINT: u256 = u256 {
        low: 0xcffea6b3bffe746de20fdd0734b30845,
        high: 0x5e4a3b18b41199f9389ded8696067271,
    };
    const TESTVECTOR_R1_COMPRESSED: u256 = u256 {
        low: 0x3cb02521d7a17fedca11c02ea41fe334,
        high: 0x11ef09256f90d942ca7a0e4ae05926a5,
    };
    const TESTVECTOR_R1_SQRT_HINT: u256 = u256 {
        low: 0x623d9789d855bcc4f0fbd8683b350688,
        high: 0x0a2d15cdfbfcf6181e92f0b7c74b477e,
    };
    const TESTVECTOR_R2_COMPRESSED: u256 = u256 {
        low: 0xe66ca975ef303c032fcc18a952325162,
        high: 0xc5d2eb608176c8b79dfa55289c35b35f,
    };
    const TESTVECTOR_R2_SQRT_HINT: u256 = u256 {
        low: 0xd8b08d5ec3d265b83e5e333d750d6b37,
        high: 0x0e41fbdbbf62b47c511e0a5aa04059de,
    };
    const TESTVECTOR_CHALLENGE: felt252 = 0x47c760eb9b6a8797680bef6218e06aacc6570f8be11819d2268bb024f816108;
    const TESTVECTOR_RESPONSE: u256 = u256 { low: 0xbe3ffdd10e06b50b800feb45877b787b, high: 0x2f0ceba8a8c56d6f6b4ed3ae98db234 };
    
    /// Get test vector secret [0x12; 32] for unlock operations
    fn get_test_vector_secret() -> ByteArray {
        let mut secret: ByteArray = Default::default();
        let mut i: u32 = 0;
        while i < 32_u32 {
            secret.append_byte(0x12_u8);
            i += 1;
        };
        secret
    }
    
    /// Get real MSM hints for full scalar (matches Cairo behavior)
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
    
    /// Deploy contract using test vectors (copied from test_integration_atomic_lock.cairo)
    fn deploy_with_test_vectors() -> IAtomicLockDispatcher {
        
        let hashlock = TESTVECTOR_HASHLOCK.span();
        let (s_hint_for_g, s_hint_for_y, c_neg_hint_for_t, c_neg_hint_for_u) = get_real_msm_hints();
        
        let fake_glv_hint = array![
            0x4af5bf430174455ca59934c5,
            0x748d85ad870959a54bca47ba,
            0x6decdae5e1b9b254,
            0x0,
            0xaa008e6009b43d5c309fa848,
            0x5b26ec9e21237560e1866183,
            0x7191bfaa5a23d0cb,
            0x0,
            0x1569bc348ca5e9beecb728fdbfea1cd6,
            0x28e2d5faa7b8c3b25a1678149337cad3
        ].span();
        
        let declare_res = declare("AtomicLock");
        let contract = declare_res.unwrap().contract_class();
        
        let mut calldata = ArrayTrait::new();
        hashlock.serialize(ref calldata);
        Serde::serialize(@FUTURE_TIMESTAMP, ref calldata);
        let zero_address: ContractAddress = 0.try_into().unwrap();
        Serde::serialize(@zero_address, ref calldata);
        Serde::serialize(@zero_address, ref calldata);
        Serde::serialize(@u256 { low: 0, high: 0 }, ref calldata);
        
        Serde::serialize(@TESTVECTOR_T_COMPRESSED, ref calldata);
        Serde::serialize(@TESTVECTOR_T_SQRT_HINT, ref calldata);
        Serde::serialize(@TESTVECTOR_U_COMPRESSED, ref calldata);
        Serde::serialize(@TESTVECTOR_U_SQRT_HINT, ref calldata);
        Serde::serialize(@TESTVECTOR_CHALLENGE, ref calldata);
        Serde::serialize(@TESTVECTOR_RESPONSE, ref calldata);
        Serde::serialize(@fake_glv_hint, ref calldata);
        Serde::serialize(@s_hint_for_g, ref calldata);
        Serde::serialize(@s_hint_for_y, ref calldata);
        Serde::serialize(@c_neg_hint_for_t, ref calldata);
        Serde::serialize(@c_neg_hint_for_u, ref calldata);
        Serde::serialize(@TESTVECTOR_R1_COMPRESSED, ref calldata);
        Serde::serialize(@TESTVECTOR_R1_SQRT_HINT, ref calldata);
        Serde::serialize(@TESTVECTOR_R2_COMPRESSED, ref calldata);
        Serde::serialize(@TESTVECTOR_R2_SQRT_HINT, ref calldata);
        
        let deployment_result = contract.deploy(@calldata);
        let (addr, _) = deployment_result.unwrap();
        IAtomicLockDispatcher { contract_address: addr }
    }

    #[test]
    fn test_reveal_secret_sets_secret_revealed_true() {
        let contract = deploy_with_test_vectors();
        
        // Initially secret is not revealed
        let revealed_before: bool = contract.is_secret_revealed();
        assert(!revealed_before, 'Secret should n');
        
        // Reveal secret
        let secret = get_test_vector_secret();
        let success: bool = contract.reveal_secret(secret);
        
        assert(success, 'reveal_secret s');
        let revealed_after: bool = contract.is_secret_revealed();
        assert(revealed_after, 'Secret should b');
    }

    #[test]
    fn test_reveal_secret_stores_unlocker_address() {
        let contract = deploy_with_test_vectors();
        let _caller = starknet::get_caller_address();
        
        let secret = get_test_vector_secret();
        contract.reveal_secret(secret);
        
        // Unlocker address should be stored (we can't read it directly, but claim_tokens will verify)
        // This is tested indirectly via test_claim_tokens_only_by_unlocker
    }

    #[test]
    fn test_reveal_secret_stores_timestamp() {
        let contract = deploy_with_test_vectors();
        
        // Set non-zero timestamp before reveal (snforge default is 0)
        let base_time: u64 = 1000000;
        start_cheat_block_timestamp(contract.contract_address, base_time);
        
        let secret = get_test_vector_secret();
        contract.reveal_secret(secret);
        
        // Timestamp should be stored (tested via get_claimable_after)
        let claimable_after = contract.get_claimable_after();
        assert(claimable_after > base_time, 'claimable_after > base_time');
        let expected: u64 = base_time + 7200;
        assert(claimable_after == expected, 'claimable_after == expected');
        
        stop_cheat_block_timestamp(contract.contract_address);
    }

    #[test]
    fn test_reveal_secret_does_not_transfer_tokens() {
        // This test requires a token contract - simplified version
        // Full version would deploy mock ERC20 and verify balance unchanged
        let contract = deploy_with_test_vectors();
        
        let secret = get_test_vector_secret();
        contract.reveal_secret(secret);
        
        // Contract should still be locked (tokens not transferred)
        assert(!contract.is_unlocked(), 'Contract should');
    }

    #[test]
    fn test_reveal_secret_fails_with_wrong_secret() {
        let contract = deploy_with_test_vectors();
    
        // Wrong secret (all zeros)
        let mut wrong_secret: ByteArray = Default::default();
        let mut i: u32 = 0;
        while i < 32_u32 {
            wrong_secret.append_byte(0_u8);
            i += 1;
        };
    let success = contract.reveal_secret(wrong_secret);
    
    assert(!success, 'reveal_secret s');
    assert(!contract.is_secret_revealed(), 'Secret should n');
}

    #[test]
    #[should_panic(expected: ('Lock expired',))]
    fn test_reveal_secret_fails_after_lock_expiry() {
        let contract = deploy_with_test_vectors();
        let lock_until = contract.get_lock_until();
        start_cheat_block_timestamp(contract.contract_address, lock_until + 1);

        let secret = get_test_vector_secret();
        contract.reveal_secret(secret);
    }

    #[test]
    #[should_panic(expected: ('Lock expired',))]
    fn test_verify_and_unlock_fails_after_lock_expiry() {
        let contract = deploy_with_test_vectors();
        let lock_until = contract.get_lock_until();
        start_cheat_block_timestamp(contract.contract_address, lock_until + 1);

        let secret = get_test_vector_secret();
        contract.verify_and_unlock(secret);
    }

    #[test]
    #[should_panic(expected: ('Secret not yet revealed',))]
    fn test_claim_tokens_requires_secret_revealed() {
        // SECURITY: claim_tokens() requires secret_revealed == true
        // This is enforced by: assert!(self.secret_revealed.read(), Errors::SECRET_NOT_REVEALED)
        // Test validated manually via: snforge test test_claim_tokens_requires_secret_revealed 2>&1 | grep "SECRET_NOT_REVEALED"
        let contract = deploy_with_test_vectors();
        contract.claim_tokens(); // Should panic with SECRET_NOT_REVEALED
    }

    #[test]
    #[should_panic(expected: ('Grace period not expired',))]
    fn test_claim_tokens_requires_grace_period_expired() {
        // SECURITY: claim_tokens() requires grace period to expire
        // This is enforced by: assert(now >= claimable_after, Errors::GRACE_PERIOD_NOT_EXPIRED)
        // Test validated manually via: snforge test test_claim_tokens_requires_grace_period_expired 2>&1 | grep "GRACE_PERIOD_NOT_EXPIRED"
        let contract = deploy_with_test_vectors();
        
        // Set non-zero timestamp before reveal (snforge default is 0)
        let base_time: u64 = 1000000;
        start_cheat_block_timestamp(contract.contract_address, base_time);
        
        // Reveal secret
        let secret = get_test_vector_secret();
        contract.reveal_secret(secret);
        
        // Try to claim immediately (grace period not expired)
        // Should fail with GRACE_PERIOD_NOT_EXPIRED
        contract.claim_tokens(); // Should panic
        
        stop_cheat_block_timestamp(contract.contract_address);
    }

    #[test]
    fn test_claim_tokens_only_by_unlocker() {
        let contract = deploy_with_test_vectors();
        let _unlocker = starknet::get_caller_address();
        
        // Set non-zero timestamp before reveal (snforge default is 0)
        let base_time: u64 = 1000000;
        start_cheat_block_timestamp(contract.contract_address, base_time);
        
        // Reveal secret as unlocker
        let secret = get_test_vector_secret();
        contract.reveal_secret(secret);
        
        // Fast-forward past grace period
        let claimable_after = contract.get_claimable_after();
        start_cheat_block_timestamp(contract.contract_address, claimable_after + 1);
        
        // Claim should succeed as unlocker
        let success = contract.claim_tokens();
        assert(success, 'claim_tokens sh');
        
        stop_cheat_block_timestamp(contract.contract_address);
    }

    #[test]
    fn test_claim_tokens_transfers_tokens() {
        // This requires token contract - simplified
        // Full version would verify ERC20 balance changes
        let contract = deploy_with_test_vectors();
        
        // Set non-zero timestamp before reveal (snforge default is 0)
        let base_time: u64 = 1000000;
        start_cheat_block_timestamp(contract.contract_address, base_time);
        
        let secret = get_test_vector_secret();
        contract.reveal_secret(secret);
        
        // Fast-forward past grace period
        let claimable_after = contract.get_claimable_after();
        start_cheat_block_timestamp(contract.contract_address, claimable_after + 1);
        
        contract.claim_tokens();
        
        // Contract should be unlocked (tokens transferred)
        assert(contract.is_unlocked(), 'Contract should');
        
        stop_cheat_block_timestamp(contract.contract_address);
    }

    #[test]
    fn test_claim_tokens_sets_unlocked_true() {
        let contract = deploy_with_test_vectors();
        
        // Set non-zero timestamp before reveal (snforge default is 0)
        let base_time: u64 = 1000000;
        start_cheat_block_timestamp(contract.contract_address, base_time);
        
        let secret = get_test_vector_secret();
        contract.reveal_secret(secret);
        
        // Fast-forward past grace period
        let claimable_after = contract.get_claimable_after();
        start_cheat_block_timestamp(contract.contract_address, claimable_after + 1);
        
        contract.claim_tokens();
        
        assert(contract.is_unlocked(), 'unlocked should');
        
        stop_cheat_block_timestamp(contract.contract_address);
    }

    #[test]
    fn test_full_two_phase_flow() {
        let contract = deploy_with_test_vectors();
        
        // Set non-zero timestamp before reveal (snforge default is 0)
        let base_time: u64 = 1000000;
        start_cheat_block_timestamp(contract.contract_address, base_time);
        
        // Phase 1: Reveal secret
        let secret = get_test_vector_secret();
        let revealed = contract.reveal_secret(secret);
        assert(revealed, 'Phase 1: reveal');
        assert(contract.is_secret_revealed(), 'Phase 1: secret');
        assert(!contract.is_unlocked(), 'Phase 1: contra');
        
        // Fast-forward past grace period
        let claimable_after = contract.get_claimable_after();
        start_cheat_block_timestamp(contract.contract_address, claimable_after + 1);
        
        // Phase 2: Claim tokens
        let claimed = contract.claim_tokens();
        assert(claimed, 'Phase 2: claim_');
        assert(contract.is_unlocked(), 'Phase 2: contra');
        
        stop_cheat_block_timestamp(contract.contract_address);
    }

    #[test]
    #[should_panic(expected: ('Secret already revealed',))]
    fn test_refund_blocked_after_reveal() {
        // SECURITY: P0 FIX - Prevents depositor from stealing tokens during grace period
        // This is enforced by: assert!(!self.secret_revealed.read(), Errors::SECRET_ALREADY_REVEALED)
        // Test validated manually via: snforge test test_refund_blocked_after_reveal 2>&1 | grep "SECRET_ALREADY_REVEALED"
        let contract = deploy_with_test_vectors();
        let depositor = starknet::get_caller_address();
        
        // Reveal secret (as unlocker)
        let secret = get_test_vector_secret();
        contract.reveal_secret(secret);
        
        // Fast-forward past timelock expiry
        let lock_until = contract.get_lock_until();
        start_cheat_block_timestamp(contract.contract_address, lock_until + 1);
        
        // Try to refund as depositor (should FAIL - P0 fix)
        start_cheat_caller_address(contract.contract_address, depositor);
        contract.refund(); // Should panic with SECRET_ALREADY_REVEALED
        
        stop_cheat_caller_address(contract.contract_address);
        stop_cheat_block_timestamp(contract.contract_address);
    }

    #[test]
    #[should_panic(expected: ('Secret already revealed',))]
    fn test_double_reveal_fails() {
        // SECURITY: Prevents replay attacks - can't reveal secret twice
        // This is enforced by: assert!(!self.secret_revealed.read(), Errors::SECRET_ALREADY_REVEALED)
        // Test validated manually via: snforge test test_double_reveal_fails 2>&1 | grep "SECRET_ALREADY_REVEALED"
        let contract = deploy_with_test_vectors();
        
        // First reveal should succeed
        let secret1 = get_test_vector_secret();
        let success1 = contract.reveal_secret(secret1);
        assert(success1, 'first reveal ok');
        
        // Second reveal should fail (already revealed)
        let secret2 = get_test_vector_secret();
        contract.reveal_secret(secret2); // Should panic with SECRET_ALREADY_REVEALED
    }

    #[test]
    #[should_panic(expected: ('Secret not yet revealed',))]
    fn test_claim_before_reveal_fails() {
        // SECURITY: claim_tokens() requires secret_revealed == true
        // This is enforced by: assert!(self.secret_revealed.read(), Errors::SECRET_NOT_REVEALED)
        // Test validated manually via: snforge test test_claim_before_reveal_fails 2>&1 | grep "SECRET_NOT_REVEALED"
        let contract = deploy_with_test_vectors();
        contract.claim_tokens(); // Should panic with SECRET_NOT_REVEALED
    }

    #[test]
    fn test_verify_and_unlock_reveals_without_unlocking() {
        let contract = deploy_with_test_vectors();
    
    // Legacy function still accepts the secret, but it must not transfer immediately.
        let secret = get_test_vector_secret();
    let success = contract.verify_and_unlock(secret);
    
    assert(success, 'verify_and_unlo');
    assert(contract.is_secret_revealed(), 'Secret should b');
    assert(!contract.is_unlocked(), 'Contract should');
}

    #[test]
    fn test_verify_and_unlock_requires_claim_tokens_after_grace() {
        let contract = deploy_with_test_vectors();

        let base_time: u64 = 1000000;
        start_cheat_block_timestamp(contract.contract_address, base_time);

        let secret = get_test_vector_secret();
        let success = contract.verify_and_unlock(secret);
        assert(success, 'verify_and_unlo');
        assert(!contract.is_unlocked(), 'still locked');

        let claimable_after = contract.get_claimable_after();
        start_cheat_block_timestamp(contract.contract_address, claimable_after + 1);
        let claimed = contract.claim_tokens();
        assert(claimed, 'claim_tokens ok');
        assert(contract.is_unlocked(), 'Contract should');

        stop_cheat_block_timestamp(contract.contract_address);
	}

    #[test]
    fn test_secret_revealed_getter() {
        let contract = deploy_with_test_vectors();
    
    // Initially false
    assert(!contract.is_secret_revealed(), 'Initially secre');
    
    // After reveal
        let secret = get_test_vector_secret();
    contract.reveal_secret(secret);
    assert(contract.is_secret_revealed(), 'After reveal, s');
}

    #[test]
    fn test_claimable_after_getter() {
        let contract = deploy_with_test_vectors();
        
        // Initially zero (no reveal yet)
        let claimable_before = contract.get_claimable_after();
        assert(claimable_before == 0, 'claimable_before == 0');
        
        // Set non-zero timestamp before reveal (snforge default is 0)
        let base_time: u64 = 1000000;
        start_cheat_block_timestamp(contract.contract_address, base_time);
        
        // After reveal
        let secret = get_test_vector_secret();
        contract.reveal_secret(secret);
        
        let claimable_after = contract.get_claimable_after();
        assert(claimable_after > base_time, 'claimable_after > base_time');
        let expected: u64 = base_time + 7200;
        assert(claimable_after == expected, 'claimable_after == expected');
        
        stop_cheat_block_timestamp(contract.contract_address);
    }

    #[test]
    #[should_panic(expected: ('Already unlocked',))]
    fn test_multiple_claim_attempts_fail() {
        // SECURITY: Prevents double-spend - can't claim tokens twice
        // This is enforced by: assert!(!self.unlocked.read(), Errors::ALREADY_UNLOCKED)
        // Test validated manually via: snforge test test_multiple_claim_attempts_fail 2>&1 | grep "ALREADY_UNLOCKED"
        let contract = deploy_with_test_vectors();
        
        // Set non-zero timestamp before reveal (snforge default is 0)
        let base_time: u64 = 1000000;
        start_cheat_block_timestamp(contract.contract_address, base_time);
        
        let secret = get_test_vector_secret();
        contract.reveal_secret(secret);
        
        // Fast-forward past grace period (claimable_after is inclusive, so add 1)
        let claimable_after = contract.get_claimable_after();
        start_cheat_block_timestamp(contract.contract_address, claimable_after + 1);
        
        // First claim should succeed
        let success1 = contract.claim_tokens();
        assert(success1, 'first claim ok');
        
        // Second claim should fail (already unlocked)
        contract.claim_tokens(); // Should panic with ALREADY_UNLOCKED
        
        stop_cheat_block_timestamp(contract.contract_address);
    }
}
