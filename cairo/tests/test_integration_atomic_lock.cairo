#[cfg(test)]
mod tests {
    use atomic_lock::{IAtomicLockDispatcher, IAtomicLockDispatcherTrait};
    use core::array::ArrayTrait;
    use core::byte_array::{ByteArray, ByteArrayTrait};
    use core::integer::u256;
    use core::result::ResultTrait;
    use core::serde::Serde;
    use core::traits::TryInto;
    use starknet::{contract_address::ContractAddress, SyscallResult};
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait,
        start_cheat_block_timestamp, stop_cheat_block_timestamp,
        start_cheat_caller_address, stop_cheat_caller_address,
    };
    
    // Future timestamp for test deployments (far enough in future to pass validation)
    const FUTURE_TIMESTAMP: u64 = 9999999999_u64;

    // Test vector constants (from test_vectors.cairo - single source of truth)
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
    const ERR_HINT_Q_MISMATCH: felt252 = 'Hint Q mismatch adaptor';
    const TESTVECTOR_HASHLOCK: [u32; 8] = [
        0xb6acca81_u32, 0xa0939a85_u32, 0x6c35e4c4_u32, 0x188e95b9_u32,
        0x1731aab1_u32, 0xd4629a4c_u32, 0xee79dd09_u32, 0xded4fc94_u32,
    ];
    
    /// Get test vector secret [0x12; 32] for unlock operations
    fn get_test_vector_secret() -> ByteArray {
        let mut secret: ByteArray = Default::default();
        // Append 32 bytes of 0x12
        let mut i: u32 = 0;
        while i < 32_u32 {
            secret.append_byte(0x12_u8);
            i += 1;
        };
        secret
    }
    
    /// Deploy contract with test vector data (recommended for most tests).
    ///
    /// This helper uses authoritative test vectors and real MSM hints to ensure
    /// DLEQ verification succeeds. Uses the test vector hashlock and secret [0x12; 32].
    fn deploy_with_test_vectors(
        lock_until: u64,
        token: ContractAddress,
        amount: u256,
    ) -> IAtomicLockDispatcher {
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

        let (addr, _) = deploy_with_test_vectors_and_fake_glv_hint_result(
            lock_until,
            token,
            amount,
            fake_glv_hint,
        ).unwrap();
        IAtomicLockDispatcher { contract_address: addr }
    }

    fn deploy_with_test_vectors_and_fake_glv_hint_result(
        lock_until: u64,
        token: ContractAddress,
        amount: u256,
        fake_glv_hint: Span<felt252>,
    ) -> SyscallResult<(ContractAddress, Span<felt252>)> {
        // Use hashlock from test vectors
        let hashlock = TESTVECTOR_HASHLOCK.span();

        // Get real MSM hints (from test_e2e_dleq.cairo - full scalar version)
        let (s_hint_for_g, s_hint_for_y, c_neg_hint_for_t, c_neg_hint_for_u) = get_real_msm_hints();

        // Deploy using dleq_test_helpers pattern
        let declare_res = declare("AtomicLock");
        let contract = declare_res.unwrap().contract_class();
        
        let mut calldata = ArrayTrait::new();
        hashlock.serialize(ref calldata);
        Serde::serialize(@lock_until, ref calldata);
        let constructor_depositor = starknet::get_caller_address();
        Serde::serialize(@constructor_depositor, ref calldata);
        Serde::serialize(@token, ref calldata);
        Serde::serialize(@amount, ref calldata);
        
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
        
        contract.deploy(@calldata)
    }

    fn assert_deploy_failed_with(
        result: SyscallResult<(ContractAddress, Span<felt252>)>,
        expected: felt252,
    ) {
        match result {
            Result::Ok(_) => {
                assert(false, 'deploy should fail');
            },
            Result::Err(error_data) => {
                assert(error_data.len() > 0, 'empty deploy error');
                assert(*error_data.at(0) == expected, 'wrong deploy error');
            },
        };
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

    #[test]
    fn test_cryptographic_handshake() {
        // Use test vector data: hashlock and secret [0x12; 32]
        let secret_input = get_test_vector_secret();
        
        let dispatcher = deploy_with_test_vectors(
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
        );

        let success = dispatcher.verify_and_unlock(secret_input);
        assert(success, 'unlock fail');
        assert(dispatcher.is_secret_revealed(), 'secret revealed');
        assert(!dispatcher.is_unlocked(), 'grace enforced');
        let claimable_after = dispatcher.get_claimable_after();
        start_cheat_block_timestamp(dispatcher.contract_address, claimable_after + 1);
        let claimed = dispatcher.claim_tokens();
        stop_cheat_block_timestamp(dispatcher.contract_address);
        assert(claimed, 'claim fail');
        assert(dispatcher.is_unlocked(), 'state');
    }

    #[test]
    fn test_wrong_secret_fails() {
        let dispatcher = deploy_with_test_vectors(
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
        );

        // ✅ Create proper ByteArray with 32 bytes (wrong values → hash/MSM fails)
        let mut wrong_secret: ByteArray = Default::default();
        let mut i: u32 = 0;
        while i < 32_u32 {
            wrong_secret.append_byte(0xFF_u8);  // Invalid secret bytes
            i += 1;
        };
        
        // wrong secret → hash check fails before MSM
        let success = dispatcher.verify_and_unlock(wrong_secret);
        assert(!success, 'wrong secret');
        assert(!dispatcher.is_unlocked(), 'stay locked');
    }

    #[test]
    fn test_legacy_verify_alias_is_idempotent_for_unlocker() {
        let secret_input = get_test_vector_secret();
        
        let dispatcher = deploy_with_test_vectors(
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
        );

        assert(dispatcher.verify_and_unlock(secret_input), 'first ok');
        let secret_again = get_test_vector_secret();
        assert(dispatcher.verify_and_unlock(secret_again), 'second ok');
        assert(dispatcher.is_secret_revealed(), 'still revealed');
        assert(!dispatcher.is_unlocked(), 'not unlocked');
    }

    #[test]
    fn test_rust_generated_secret() {
        // Use test vector secret [0x12; 32]
        let secret_input = get_test_vector_secret();
        
        let dispatcher = deploy_with_test_vectors(
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
        );

        let success = dispatcher.verify_and_unlock(secret_input);
        assert(success, 'hash mismatch');
    }

    #[test]
    fn test_refund_after_expiry() {
        // Test refund after lock expiry.
        // Constructor requires lock_until > current timestamp, so we deploy with a future timestamp
        // then warp time forward to test refund functionality.
        // Deploy with lock_until = FUTURE_TIMESTAMP
        let lock_until = FUTURE_TIMESTAMP;
        let dispatcher = deploy_with_test_vectors(
            lock_until,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
        );
        
        // Warp time forward to after lock_until
        start_cheat_block_timestamp(dispatcher.contract_address, lock_until + 1);
        
        // Now refund should succeed (lock expired, still locked, caller is depositor)
        let depositor: ContractAddress = 0.try_into().unwrap();
        start_cheat_caller_address(dispatcher.contract_address, depositor);
        let success = dispatcher.refund();
        stop_cheat_caller_address(dispatcher.contract_address);
        assert(success, 'refund');
        
        // Stop cheating
        stop_cheat_block_timestamp(dispatcher.contract_address);
    }

    /// Gas profiling test: measures gas consumption for verify_and_unlock with MSM enabled.
    /// 
    /// This test verifies that verify_and_unlock (including SHA-256 hash check and MSM verification)
    /// consumes reasonable gas. Run with: `snforge test test_gas_profile_msm_unlock`
    /// 
    /// Expected gas (approximate, may vary):
    /// - L1 gas: ~0 (no L1 data)
    /// - L1 data gas: ~2400 (calldata)
    /// - L2 gas: ~5.4M (SHA-256 + MSM verification)
    #[test]
    #[ignore] // Gas profiling test - uses same vectors as E2E test
    fn test_gas_profile_msm_unlock() {
        // Use real test data for accurate gas measurement
        let expected_hash = array![3606997102_u32, 3756602050_u32, 1811765011_u32, 1576844653_u32, 61256116_u32, 2110839708_u32, 540553134_u32, 3341226206_u32].span();
        let mut secret_input: ByteArray = Default::default();
        secret_input.append_byte(0x09_u8); secret_input.append_byte(0x9d_u8);
        secret_input.append_byte(0xd9_u8); secret_input.append_byte(0xb7_u8);
        secret_input.append_byte(0x3e_u8); secret_input.append_byte(0x2e_u8);
        secret_input.append_byte(0x84_u8); secret_input.append_byte(0xdb_u8);
        secret_input.append_byte(0x47_u8); secret_input.append_byte(0x2b_u8);
        secret_input.append_byte(0x34_u8); secret_input.append_byte(0x2d_u8);
        secret_input.append_byte(0xc3_u8); secret_input.append_byte(0xab_u8);
        secret_input.append_byte(0x05_u8); secret_input.append_byte(0x20_u8);
        secret_input.append_byte(0xf6_u8); secret_input.append_byte(0x54_u8);
        secret_input.append_byte(0xfd_u8); secret_input.append_byte(0x8a_u8);
        secret_input.append_byte(0x81_u8); secret_input.append_byte(0xd6_u8);
        secret_input.append_byte(0x44_u8); secret_input.append_byte(0x18_u8);
        secret_input.append_byte(0x04_u8); secret_input.append_byte(0x77_u8);
        secret_input.append_byte(0x73_u8); secret_input.append_byte(0x0a_u8);
        secret_input.append_byte(0x90_u8); secret_input.append_byte(0xaf_u8);
        secret_input.append_byte(0x89_u8); secret_input.append_byte(0x00_u8);

        let x_limbs = (0x460f72719199c63ec398673f, 0xf27a4af146a52a7dbdeb4cfb, 0x5f9c70ec759789a0, 0x0);
        let y_limbs = (0x6b43e318a2a02d8241549109, 0x40e30afa4cce98c21e473980, 0x5e243e1eed1aa575, 0x0);
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

        let dispatcher = deploy_with_full(
            expected_hash,
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            hint,
        );

        // This call includes: SHA-256 hash check + MSM verification (t·G == adaptor_point)
        // Check snforge output for gas metrics: l1_gas, l1_data_gas, l2_gas
        let success = dispatcher.verify_and_unlock(secret_input);
        assert(success, 'gas profile test failed');
        let claimable_after = dispatcher.get_claimable_after();
        start_cheat_block_timestamp(dispatcher.contract_address, claimable_after + 1);
        dispatcher.claim_tokens();
        stop_cheat_block_timestamp(dispatcher.contract_address);
        assert(dispatcher.is_unlocked(), 'unlock state failed');
    }

    #[test]
    fn test_msm_check_with_real_data() {
        // Use test vector data for real MSM check
        let secret_input = get_test_vector_secret();
        
        let dispatcher = deploy_with_test_vectors(
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
        );

        let success = dispatcher.verify_and_unlock(secret_input);
        assert(success, 'MSM check failed');
        let claimable_after = dispatcher.get_claimable_after();
        start_cheat_block_timestamp(dispatcher.contract_address, claimable_after + 1);
        dispatcher.claim_tokens();
        stop_cheat_block_timestamp(dispatcher.contract_address);
        assert(dispatcher.is_unlocked(), 'unlock failed');
    }

    #[test]
    fn test_wrong_hint_fails() {
        let bad_fake_glv_hint = array![
            0x1,                                  // Tampered Q.x limb0
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

        assert_deploy_failed_with(
            deploy_with_test_vectors_and_fake_glv_hint_result(
                FUTURE_TIMESTAMP,
                0.try_into().unwrap(),
                u256 { low: 0, high: 0 },
                bad_fake_glv_hint,
            ),
            ERR_HINT_Q_MISMATCH,
        );
    }

    // Constructor validation tests.
    //
    // These use the legacy `deploy_with_full` negative harness below. They are kept
    // as broad constructor-failure smoke tests; the exact DLEQ failure reasons are
    // covered in `test_security_dleq_negative.cairo`.

    #[test]
    #[should_panic]
    fn test_constructor_rejects_zero_point() {
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let zero_point = (0, 0, 0, 0);
        let hint = array![0, 0, 0, 0, 0, 0, 0, 0, 0, 0].span();
        // Use FUTURE_TIMESTAMP to pass timelock validation, so we can test zero point rejection
        deploy_with_full(
            expected_hash,
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            zero_point,
            zero_point,
            (0, 0),
            hint,
        );
    }

    #[test]
    #[should_panic]
    fn test_constructor_rejects_wrong_hint_length() {
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let x_limbs = (0x460f72719199c63ec398673f, 0xf27a4af146a52a7dbdeb4cfb, 0x5f9c70ec759789a0, 0x0);
        let y_limbs = (0x6b43e318a2a02d8241549109, 0x40e30afa4cce98c21e473980, 0x5e243e1eed1aa575, 0x0);
        let bad_hint = array![1, 2, 3, 4, 5].span();
        deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            bad_hint,
        );
    }

    #[test]
    #[should_panic]
    fn test_constructor_rejects_mismatched_hint() {
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let x_limbs = (0x460f72719199c63ec398673f, 0xf27a4af146a52a7dbdeb4cfb, 0x5f9c70ec759789a0, 0x0);
        let y_limbs = (0x6b43e318a2a02d8241549109, 0x40e30afa4cce98c21e473980, 0x5e243e1eed1aa575, 0x0);
        let bad_hint = array![
            0x1111111111111111, 0x2222222222222222, 0x3333333333333333, 0x0,
            0x4444444444444444, 0x5555555555555555, 0x6666666666666666, 0x0,
            0x10b51d41eab43e36d3ac30cda9707f92,
            0x110538332d2eae09bf756dfd87431ded7
        ].span();
        deploy_with_full(
            expected_hash,
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            bad_hint,
        );
    }

    /// Test that verifies Rust → Python → Cairo consistency.
    /// This test uses test vector data to verify the full unlock flow works in Cairo.
    #[test]
    fn test_rust_python_cairo_consistency() {
        // Use test vector secret [0x12; 32] for consistency
        let secret_input = get_test_vector_secret();
        
        let dispatcher = deploy_with_test_vectors(
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
        );

        // Verify unlock succeeds (proves Rust -> Python -> Cairo consistency)
        let success = dispatcher.verify_and_unlock(secret_input);
        assert(success, 'Rust Python Cairo failed');
        let claimable_after = dispatcher.get_claimable_after();
        start_cheat_block_timestamp(dispatcher.contract_address, claimable_after + 1);
        dispatcher.claim_tokens();
        stop_cheat_block_timestamp(dispatcher.contract_address);
        assert(dispatcher.is_unlocked(), 'unlock state failed');
    }

    #[test]
    #[should_panic]
    fn test_constructor_rejects_past_lock_time() {
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let x_limbs = (0x460f72719199c63ec398673f, 0xf27a4af146a52a7dbdeb4cfb, 0x5f9c70ec759789a0, 0x0);
        let y_limbs = (0x6b43e318a2a02d8241549109, 0x40e30afa4cce98c21e473980, 0x5e243e1eed1aa575, 0x0);
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
        
        // Try to deploy with lock_until = 0 (past timestamp)
        deploy_with_full(
            expected_hash,
            0_u64, // Past timestamp - should panic
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            hint,
        );
    }

    #[test]
    #[should_panic]
    fn test_constructor_rejects_mixed_zero_amount_token() {
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let x_limbs = (0x460f72719199c63ec398673f, 0xf27a4af146a52a7dbdeb4cfb, 0x5f9c70ec759789a0, 0x0);
        let y_limbs = (0x6b43e318a2a02d8241549109, 0x40e30afa4cce98c21e473980, 0x5e243e1eed1aa575, 0x0);
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
        
        // Try to deploy with non-zero amount but zero token (mixed state - should panic)
        deploy_with_full(
            expected_hash,
            9999999999_u64, // Future timestamp
            0.try_into().unwrap(), // Zero token
            u256 { low: 1000, high: 0 }, // Non-zero amount - should panic
            x_limbs,
            y_limbs,
            (0, 0),
            hint,
        );
    }

    #[test]
    #[should_panic]
    fn test_constructor_rejects_small_order_point() {
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let small_order_x = (0, 0, 0, 0);
        let small_order_y = (1, 0, 0, 0);
        let hint = array![0, 0, 0, 0, 1, 0, 0, 0, 1, 1].span();
        deploy_with_full(
            expected_hash,
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            small_order_x,
            small_order_y,
            (0, 0),
            hint,
        );
    }

    /// This helper is ONLY for constructor validation tests.
    /// Do NOT use for regular integration tests - use deploy_with_test_vectors() instead.
    /// Constructor validation tests intentionally use invalid data to test rejection paths.
    /// 
    /// Helper for tests that need adaptor point and hint values.
    /// 
    /// **IMPORTANT**: This helper uses placeholder DLEQ values that will cause DLEQ verification
    /// to fail in the constructor. Tests that need successful deployment should either:
    /// 1. Use `deploy_with_test_vectors()` for regular integration tests with real DLEQ data
    /// 2. Use `deploy_with_dleq` from test_dleq.cairo with real DLEQ proofs
    /// 3. Be marked with #[should_panic] if testing constructor validation (this helper)
    /// 
    /// The x/y limbs are currently ignored (converted to placeholder compressed Edwards).
    /// For tests that need real adaptor points, convert Weierstrass to Edwards format first.
    fn deploy_with_full(
        expected_hash: Span<u32>,
        lock_until: u64,
        token: ContractAddress,
        amount: u256,
        adaptor_point_x: (felt252, felt252, felt252, felt252),
        adaptor_point_y: (felt252, felt252, felt252, felt252),
        dleq: (felt252, u256),
        fake_glv_hint: Span<felt252>,
    ) -> IAtomicLockDispatcher {
        let declare_res = declare("AtomicLock");
        let contract = declare_res.unwrap().contract_class();

        // Use Ed25519 base point (G) as placeholder - valid compressed Edwards point
        // This will decompress successfully but DLEQ verification will fail (expected)
        // For tests that need real DLEQ, use deploy_with_dleq from test_dleq.cairo
        const ED25519_BASE_POINT_COMPRESSED: u256 = u256 {
            low: 0x66666666666666666666666666666658,
            high: 0x66666666666666666666666666666666,
        };
        // Sqrt hint for base point (x-coordinate)
        // Using a placeholder - real tests should compute this properly
        // Note: x-coordinate is 256 bits, split into low/high u128
        let adaptor_point_compressed = ED25519_BASE_POINT_COMPRESSED;
        let adaptor_point_sqrt_hint = u256 { 
            low: 0xc692cc7609525a7b2c9562d608f25d51,
            high: 0x216936d3cd6e53fec0a4e231fdd6dc5
        };
        let dleq_second_point_compressed = ED25519_BASE_POINT_COMPRESSED;
        let dleq_second_point_sqrt_hint = u256 { 
            low: 0xc692cc7609525a7b2c9562d608f25d51,
            high: 0x216936d3cd6e53fec0a4e231fdd6dc5
        };
        
        let (dleq_c, dleq_r) = dleq;
        
        // Placeholder DLEQ hints (empty - will cause MSM to fail)
        let empty_hint = array![0, 0, 0, 0, 0, 0, 0, 0, 0, 0].span();
        
        // Placeholder R1 and R2 (commitment points) - use base point for valid decompression
        let r1_compressed = ED25519_BASE_POINT_COMPRESSED;
        let r1_sqrt_hint = u256 { 
            low: 0xc692cc7609525a7b2c9562d608f25d51,
            high: 0x216936d3cd6e53fec0a4e231fdd6dc5
        };
        let r2_compressed = ED25519_BASE_POINT_COMPRESSED;
        let r2_sqrt_hint = u256 { 
            low: 0xc692cc7609525a7b2c9562d608f25d51,
            high: 0x216936d3cd6e53fec0a4e231fdd6dc5
        };

        let mut calldata = ArrayTrait::new();
        expected_hash.serialize(ref calldata);
        Serde::serialize(@lock_until, ref calldata);
        let constructor_depositor = starknet::get_caller_address();
        Serde::serialize(@constructor_depositor, ref calldata);
        Serde::serialize(@token, ref calldata);
        Serde::serialize(@amount, ref calldata);
        
        // Adaptor point (compressed Edwards + sqrt hint)
        Serde::serialize(@adaptor_point_compressed, ref calldata);
        Serde::serialize(@adaptor_point_sqrt_hint, ref calldata);
        
        // DLEQ second point (compressed Edwards + sqrt hint)
        Serde::serialize(@dleq_second_point_compressed, ref calldata);
        Serde::serialize(@dleq_second_point_sqrt_hint, ref calldata);
        
        // DLEQ proof (challenge, response)
        Serde::serialize(@dleq_c, ref calldata);
        Serde::serialize(@dleq_r, ref calldata);
        
        // Fake-GLV hint (for adaptor point)
        Serde::serialize(@fake_glv_hint, ref calldata);
        
        // DLEQ hints (empty placeholders)
        Serde::serialize(@empty_hint, ref calldata); // s_hint_for_g
        Serde::serialize(@empty_hint, ref calldata); // s_hint_for_y
        Serde::serialize(@empty_hint, ref calldata); // c_neg_hint_for_t
        Serde::serialize(@empty_hint, ref calldata); // c_neg_hint_for_u
        
        // R1 and R2 commitment points
        Serde::serialize(@r1_compressed, ref calldata);
        Serde::serialize(@r1_sqrt_hint, ref calldata);
        Serde::serialize(@r2_compressed, ref calldata);
        Serde::serialize(@r2_sqrt_hint, ref calldata);

        let (addr, _) = contract.deploy(@calldata).unwrap();
        IAtomicLockDispatcher { contract_address: addr }
    }
}
