/// # DLEQ Negative Tests
///
/// Tests that verify invalid DLEQ proofs are correctly rejected.
/// These tests ensure the contract properly validates proofs and rejects tampered data.

#[cfg(test)]
mod dleq_negative_tests {
    use core::array::ArrayTrait;
    use core::serde::Serde;
    use core::traits::TryInto;
    use starknet::{ContractAddress, SyscallResult};
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
    use core::integer::u256;
    
    // Constants from test_vectors.json (match test_e2e_dleq.cairo)
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
    const TESTVECTOR_CHALLENGE: felt252 = 0x47c760eb9b6a8797680bef6218e06aacc6570f8be11819d2268bb024f816108;
    const TESTVECTOR_RESPONSE: u256 = u256 { low: 0xbe3ffdd10e06b50b800feb45877b787b, high: 0x2f0ceba8a8c56d6f6b4ed3ae98db234 };
    const ERR_DLEQ_CHALLENGE_MISMATCH: felt252 = 'DLEQ: challenge mismatch';
    const ERR_WRONG_FAKE_GLV: felt252 = 'Wrong FakeGLV decomposition';
    const ERR_HINT_Q_MISMATCH: felt252 = 'Hint Q mismatch adaptor';
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
    
    const FUTURE_TIMESTAMP: u64 = 9999999999_u64;
    
    // Sqrt hints (from test_e2e_dleq.cairo)
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
    
    // MSM hints (from test_e2e_dleq.cairo)
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
    
    fn deploy_with_dleq(
        hashlock: Span<u32>,
        challenge: felt252,
        response: u256,
    ) -> SyscallResult<(ContractAddress, Span<felt252>)> {
        deploy_with_dleq_custom_points(
            hashlock,
            challenge,
            response,
            TESTVECTOR_T_COMPRESSED,
            TEST_ADAPTOR_POINT_SQRT_HINT,
            TESTVECTOR_U_COMPRESSED,
            TEST_SECOND_POINT_SQRT_HINT,
        )
    }

    fn deploy_with_dleq_custom_points(
        hashlock: Span<u32>,
        challenge: felt252,
        response: u256,
        adaptor_point: u256,
        adaptor_sqrt_hint: u256,
        second_point: u256,
        second_sqrt_hint: u256,
    ) -> SyscallResult<(ContractAddress, Span<felt252>)> {
        let declare_res = declare("AtomicLock");
        let contract = declare_res.unwrap().contract_class();
        
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
        
        Serde::serialize(@adaptor_point, ref calldata);
        Serde::serialize(@adaptor_sqrt_hint, ref calldata);
        Serde::serialize(@second_point, ref calldata);
        Serde::serialize(@second_sqrt_hint, ref calldata);
        Serde::serialize(@challenge, ref calldata);
        Serde::serialize(@response, ref calldata);
        Serde::serialize(@fake_glv_hint, ref calldata);  // CRITICAL: Missing fake-GLV hint!
        Serde::serialize(@s_hint_for_g, ref calldata);
        Serde::serialize(@s_hint_for_y, ref calldata);
        Serde::serialize(@c_neg_hint_for_t, ref calldata);
        Serde::serialize(@c_neg_hint_for_u, ref calldata);
        Serde::serialize(@TESTVECTOR_R1_COMPRESSED, ref calldata);
        Serde::serialize(@TEST_R1_SQRT_HINT, ref calldata);
        Serde::serialize(@TESTVECTOR_R2_COMPRESSED, ref calldata);
        Serde::serialize(@TEST_R2_SQRT_HINT, ref calldata);
        
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
    
    /// Test: Wrong challenge should be rejected.
    #[test]
    fn test_wrong_challenge_rejected() {
        let hashlock = TESTVECTOR_HASHLOCK.span();
        let wrong_challenge: felt252 = 0x1234567890abcdef1234567890abcdef; // Wrong challenge
        let response = TESTVECTOR_RESPONSE; // Correct response
        
        assert_deploy_failed_with(
            deploy_with_dleq(hashlock, wrong_challenge, response),
            ERR_DLEQ_CHALLENGE_MISMATCH,
        );
    }
    
    /// Test: Wrong response should cause MSM verification to fail.
    #[test]
    fn test_wrong_response_rejected() {
        let hashlock = TESTVECTOR_HASHLOCK.span();
        let challenge = TESTVECTOR_CHALLENGE; // Correct challenge
        let wrong_response: u256 = u256 { low: 0x1234567890abcdef1234567890abcdef, high: 0 }; // Wrong response
        
        assert_deploy_failed_with(
            deploy_with_dleq(hashlock, challenge, wrong_response),
            ERR_WRONG_FAKE_GLV,
        );
    }
    
    /// Test: Wrong hashlock should cause challenge mismatch.
    #[test]
    fn test_wrong_hashlock_rejected() {
        let wrong_hashlock = array![
            0x11111111_u32, 0x22222222_u32, 0x33333333_u32, 0x44444444_u32,
            0x55555555_u32, 0x66666666_u32, 0x77777777_u32, 0x88888888_u32
        ].span();
        let challenge = TESTVECTOR_CHALLENGE;
        let response = TESTVECTOR_RESPONSE;
        
        assert_deploy_failed_with(
            deploy_with_dleq(wrong_hashlock, challenge, response),
            ERR_DLEQ_CHALLENGE_MISMATCH,
        );
    }
    
    /// Test: Swapped T/U points should cause verification failure.
    #[test]
    fn test_swapped_t_u_points_rejected() {
        assert_deploy_failed_with(
            deploy_with_dleq_custom_points(
                TESTVECTOR_HASHLOCK.span(),
                TESTVECTOR_CHALLENGE,
                TESTVECTOR_RESPONSE,
                TESTVECTOR_U_COMPRESSED,
                TEST_SECOND_POINT_SQRT_HINT,
                TESTVECTOR_T_COMPRESSED,
                TEST_ADAPTOR_POINT_SQRT_HINT,
            ),
            ERR_HINT_Q_MISMATCH,
        );
    }
}
