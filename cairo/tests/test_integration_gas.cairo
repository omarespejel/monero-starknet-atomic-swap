/// # Gas Benchmarking Tests
///
/// Measures and documents gas costs for critical operations:
/// - DLEQ verification (constructor)
/// - BLAKE2s challenge computation
/// - MSM operations
///
/// These benchmarks help understand production costs and optimize where needed.

#[cfg(test)]
mod gas_benchmark_tests {
    use atomic_lock::IAtomicLockDispatcher;
    use core::array::ArrayTrait;
    use core::serde::Serde;
    use core::traits::TryInto;
    use starknet::ContractAddress;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
    use core::integer::u256;

    const FUTURE_TIMESTAMP: u64 = 9999999999_u64;

    /// Benchmark: DLEQ verification gas cost
    ///
    /// This test measures the gas cost of deploying a contract with DLEQ verification.
    /// The cost includes:
    /// - BLAKE2s challenge computation (228 bytes input)
    /// - 4 MSM operations (s·G, s·Y, (-c)·T, (-c)·U)
    /// - Point decompression (Edwards → Weierstrass)
    /// - DLEQ proof verification
    ///
    /// Expected: ~200k-400k gas (depending on MSM complexity)
    /// Benchmark DLEQ verification gas usage with real test vectors
    #[test]
    fn benchmark_dleq_verification_gas() {
        // Use EXACT validated vectors from test_e2e_dleq.cairo
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
            0x4af5bf430174455ca59934c5, 0x748d85ad870959a54bca47ba,
            0x6decdae5e1b9b254, 0x0,
            0xaa008e6009b43d5c309fa848, 0x5b26ec9e21237560e1866183,
            0x7191bfaa5a23d0cb, 0x0,
            0x1569bc348ca5e9beecb728fdbfea1cd6, 0x28e2d5faa7b8c3b25a1678149337cad3
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

        // Deploy contract - gas will be measured by snforge
        let declare_res = declare("AtomicLock");
        let contract_class = declare_res.unwrap().contract_class();

        let mut calldata = ArrayTrait::new();
        hashlock.serialize(ref calldata);
        Serde::serialize(@FUTURE_TIMESTAMP, ref calldata);
        let zero_address: ContractAddress = 0.try_into().unwrap();
        Serde::serialize(@zero_address, ref calldata);
        Serde::serialize(@u256 { low: 0, high: 0 }, ref calldata);
        Serde::serialize(@adaptor_point_compressed, ref calldata);
        Serde::serialize(@adaptor_point_sqrt_hint, ref calldata);
        Serde::serialize(@second_point_compressed, ref calldata);
        Serde::serialize(@second_point_sqrt_hint, ref calldata);
        Serde::serialize(@challenge, ref calldata);
        Serde::serialize(@response, ref calldata);
        Serde::serialize(@fake_glv_hint, ref calldata);
        Serde::serialize(@s_hint_for_g, ref calldata);
        Serde::serialize(@s_hint_for_y, ref calldata);
        Serde::serialize(@c_neg_hint_for_t, ref calldata);
        Serde::serialize(@c_neg_hint_for_u, ref calldata);
        Serde::serialize(@r1_compressed, ref calldata);
        Serde::serialize(@r1_sqrt_hint, ref calldata);
        Serde::serialize(@r2_compressed, ref calldata);
        Serde::serialize(@r2_sqrt_hint, ref calldata);

        let (addr, _) = contract_class.deploy(@calldata).unwrap();
        let contract = IAtomicLockDispatcher { contract_address: addr };

        // Verify deployment succeeded
        assert(contract.contract_address != zero_address, 'Gas benchmark deployed');
    }
}

