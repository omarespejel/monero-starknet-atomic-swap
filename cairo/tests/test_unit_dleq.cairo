#[cfg(test)]
mod dleq_tests {
    use atomic_lock::IAtomicLockDispatcher;
    use core::array::ArrayTrait;
    use core::serde::Serde;
    use starknet::ContractAddress;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
    use core::traits::TryInto;
    use core::integer::u256;

    const FUTURE_TIMESTAMP: u64 = 9999999999_u64;

    // ============================================================
    // VALIDATED TEST VECTORS - From test_e2e_dleq.cairo
    // ============================================================
    
    fn get_validated_test_data() -> (
        Span<u32>,           // hashlock
        u256, u256,          // adaptor point + sqrt hint
        u256, u256,          // second point + sqrt hint
        u256, u256,          // R1 + sqrt hint
        u256, u256,          // R2 + sqrt hint
        felt252, u256,       // challenge, response
        Span<felt252>,       // fake_glv_hint
        Span<felt252>,       // s_hint_for_g
        Span<felt252>,       // s_hint_for_y
        Span<felt252>,       // c_neg_hint_for_t
        Span<felt252>,       // c_neg_hint_for_u
    ) {
        let hashlock = array![
            0xb6acca81_u32, 0xa0939a85_u32, 0x6c35e4c4_u32, 0x188e95b9_u32,
            0x1731aab1_u32, 0xd4629a4c_u32, 0xee79dd09_u32, 0xded4fc94_u32
        ].span();

        let adaptor_point_compressed: u256 = u256 {
            low: 0x54e86953e7cc99b545cfef03f63cce85,
            high: 0x427dde0adb325f957d29ad71e4643882,
        };
        let adaptor_point_sqrt_hint: u256 = u256 {
            low: 0x448c18dcf34127e112ff945a65defbfc,
            high: 0x17611da35f39a2a5e3a9fddb8d978e4f,
        };

        let second_point_compressed: u256 = u256 {
            low: 0x9244eb3a3699efed3106c6ae0afdf28,
            high: 0xb6e0bfc0d9fbb8a4c8ef08cb5da2eff3,
        };
        let second_point_sqrt_hint: u256 = u256 {
            low: 0xcffea6b3bffe746de20fdd0734b30845,
            high: 0x5e4a3b18b41199f9389ded8696067271,
        };

        let r1_compressed: u256 = u256 {
            low: 0x3cb02521d7a17fedca11c02ea41fe334,
            high: 0x11ef09256f90d942ca7a0e4ae05926a5,
        };
        let r1_sqrt_hint: u256 = u256 {
            low: 0x623d9789d855bcc4f0fbd8683b350688,
            high: 0x0a2d15cdfbfcf6181e92f0b7c74b477e,
        };

        let r2_compressed: u256 = u256 {
            low: 0xe66ca975ef303c032fcc18a952325162,
            high: 0xc5d2eb608176c8b79dfa55289c35b35f,
        };
        let r2_sqrt_hint: u256 = u256 {
            low: 0xd8b08d5ec3d265b83e5e333d750d6b37,
            high: 0x0e41fbdbbf62b47c511e0a5aa04059de,
        };

        let challenge: felt252 = 0x47c760eb9b6a8797680bef6218e06aacc6570f8be11819d2268bb024f816108;
        let response: u256 = u256 { low: 0xbe3ffdd10e06b50b800feb45877b787b, high: 0x2f0ceba8a8c56d6f6b4ed3ae98db234 };

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

        (
            hashlock,
            adaptor_point_compressed, adaptor_point_sqrt_hint,
            second_point_compressed, second_point_sqrt_hint,
            r1_compressed, r1_sqrt_hint,
            r2_compressed, r2_sqrt_hint,
            challenge, response,
            fake_glv_hint,
            s_hint_for_g, s_hint_for_y,
            c_neg_hint_for_t, c_neg_hint_for_u,
        )
    }

    /// Test that contract deploys with valid DLEQ data
    #[test]
    fn test_dleq_contract_deployment_structure() {
        let (
            hashlock,
            adaptor_point_compressed, adaptor_point_sqrt_hint,
            second_point_compressed, second_point_sqrt_hint,
            r1_compressed, r1_sqrt_hint,
            r2_compressed, r2_sqrt_hint,
            challenge, response,
            fake_glv_hint,
            s_hint_for_g, s_hint_for_y,
            c_neg_hint_for_t, c_neg_hint_for_u,
        ) = get_validated_test_data();

        let contract = deploy_with_dleq(
            hashlock,
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            adaptor_point_compressed,
            adaptor_point_sqrt_hint,
            second_point_compressed,
            second_point_sqrt_hint,
            (challenge, response),
            fake_glv_hint,
            s_hint_for_g,
            s_hint_for_y,
            c_neg_hint_for_t,
            c_neg_hint_for_u,
            r1_compressed,
            r1_sqrt_hint,
            r2_compressed,
            r2_sqrt_hint
        );

        let zero_address: ContractAddress = 0.try_into().unwrap();
        assert(contract.contract_address != zero_address, 'Contract deployed');
    }

    /// Test that invalid DLEQ proof is rejected.
    #[test]
    #[should_panic]
    fn test_dleq_invalid_proof_rejected() {
        let (
            hashlock,
            adaptor_point_compressed, adaptor_point_sqrt_hint,
            second_point_compressed, second_point_sqrt_hint,
            r1_compressed, r1_sqrt_hint,
            r2_compressed, r2_sqrt_hint,
            _challenge, response,  // Ignore correct challenge
            fake_glv_hint,
            s_hint_for_g, s_hint_for_y,
            c_neg_hint_for_t, c_neg_hint_for_u,
        ) = get_validated_test_data();

        // Use WRONG challenge - should cause deployment to fail
        let wrong_challenge: felt252 = 0xdeadbeefcafebabe;

        deploy_with_dleq(
            hashlock,
            FUTURE_TIMESTAMP,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            adaptor_point_compressed,
            adaptor_point_sqrt_hint,
            second_point_compressed,
            second_point_sqrt_hint,
            (wrong_challenge, response),
            fake_glv_hint,
            s_hint_for_g,
            s_hint_for_y,
            c_neg_hint_for_t,
            c_neg_hint_for_u,
            r1_compressed,
            r1_sqrt_hint,
            r2_compressed,
            r2_sqrt_hint
        );
    }

    fn deploy_with_dleq(
        expected_hash: Span<u32>,
        lock_until: u64,
        token: ContractAddress,
        amount: u256,
        adaptor_point_edwards_compressed: u256,
        adaptor_point_sqrt_hint: u256,
        dleq_second_point_edwards_compressed: u256,
        dleq_second_point_sqrt_hint: u256,
        dleq: (felt252, u256),
        fake_glv_hint: Span<felt252>,
        dleq_s_hint_for_g: Span<felt252>,
        dleq_s_hint_for_y: Span<felt252>,
        dleq_c_neg_hint_for_t: Span<felt252>,
        dleq_c_neg_hint_for_u: Span<felt252>,
        r1_edwards_compressed: u256,
        r1_edwards_sqrt_hint: u256,
        r2_edwards_compressed: u256,
        r2_edwards_sqrt_hint: u256,
    ) -> atomic_lock::IAtomicLockDispatcher {
        let declare_res = declare("AtomicLock");
        let contract = declare_res.unwrap().contract_class();

        let (dleq_c, dleq_r) = dleq;

        let mut calldata = ArrayTrait::new();
        expected_hash.serialize(ref calldata);
        Serde::serialize(@lock_until, ref calldata);
        let constructor_depositor = starknet::get_caller_address();
        Serde::serialize(@constructor_depositor, ref calldata);
        Serde::serialize(@token, ref calldata);
        Serde::serialize(@amount, ref calldata);
        Serde::serialize(@adaptor_point_edwards_compressed, ref calldata);
        Serde::serialize(@adaptor_point_sqrt_hint, ref calldata);
        Serde::serialize(@dleq_second_point_edwards_compressed, ref calldata);
        Serde::serialize(@dleq_second_point_sqrt_hint, ref calldata);
        Serde::serialize(@dleq_c, ref calldata);
        Serde::serialize(@dleq_r, ref calldata);
        Serde::serialize(@fake_glv_hint, ref calldata);
        Serde::serialize(@dleq_s_hint_for_g, ref calldata);
        Serde::serialize(@dleq_s_hint_for_y, ref calldata);
        Serde::serialize(@dleq_c_neg_hint_for_t, ref calldata);
        Serde::serialize(@dleq_c_neg_hint_for_u, ref calldata);
        Serde::serialize(@r1_edwards_compressed, ref calldata);
        Serde::serialize(@r1_edwards_sqrt_hint, ref calldata);
        Serde::serialize(@r2_edwards_compressed, ref calldata);
        Serde::serialize(@r2_edwards_sqrt_hint, ref calldata);

        let (addr, _) = contract.deploy(@calldata).unwrap();
        IAtomicLockDispatcher { contract_address: addr }
    }
}
