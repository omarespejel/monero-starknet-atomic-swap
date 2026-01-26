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
        felt252, felt252,    // challenge, response
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
            low: 0xd893b3476bdf09770b7616f84c5c7bbe,
            high: 0x5c79d0fa84d6440908e2e2065e60d1cd,
        };
        let second_point_sqrt_hint: u256 = u256 {
            low: 0xdcad2173817c163b5405cec7698eb4b8,
            high: 0x742bb3c44b13553c8ddff66565b44cac,
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
            low: 0xb4fb26c272cbe6b84d65d4f908aff02f,
            high: 0xf58498fd33c0fbca066f3fdff2f49225,
        };
        let r2_sqrt_hint: u256 = u256 {
            low: 0x598521e3f6d818ed84721901f0d87f89,
            high: 0x09d2fd2811966933dff4c8ab0d9059fc,
        };

        let challenge: felt252 = 0x8d664bb70810bdab323a44354d98f94a;
        let response: felt252 = 0x1e741f8fec4161ea41b23ce6d007ba12;

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

    /// Test that invalid DLEQ proof is rejected
    /// Note: This test is marked #[ignore] due to snforge constructor panic limitation
    /// (see foundry-rs/starknet-foundry#3974)
    #[test]
    #[ignore]
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
        dleq: (felt252, felt252),
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
