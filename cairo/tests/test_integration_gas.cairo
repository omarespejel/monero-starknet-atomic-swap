/// # Gas Benchmarking Tests
///
/// Measures and documents gas costs for critical operations:
/// - DLEQ verification (constructor)
/// - Poseidon challenge computation
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
    /// - Poseidon challenge computation
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
            0x4af5bf430174455ca59934c5, 0x748d85ad870959a54bca47ba,
            0x6decdae5e1b9b254, 0x0,
            0xaa008e6009b43d5c309fa848, 0x5b26ec9e21237560e1866183,
            0x7191bfaa5a23d0cb, 0x0,
            0x1569bc348ca5e9beecb728fdbfea1cd6, 0x28e2d5faa7b8c3b25a1678149337cad3
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

        // Deploy contract - gas will be measured by snforge
        let declare_res = declare("AtomicLock");
        let contract_class = declare_res.unwrap().contract_class();

        let mut calldata = ArrayTrait::new();
        hashlock.serialize(ref calldata);
        Serde::serialize(@FUTURE_TIMESTAMP, ref calldata);
        let zero_address: ContractAddress = 0.try_into().unwrap();
        Serde::serialize(@zero_address, ref calldata);
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
