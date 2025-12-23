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
            low: 0x90b1ab352981d43ec51fba0af7ab51c7,
            high: 0xc21ebc88e5e59867b280909168338026,
        };
        let r1_sqrt_hint: u256 = u256 {
            low: 0x72a9698d3171817c239f4009cc36fc97,
            high: 0x3f2b84592a9ee701d24651e3aa3c837d,
        };

        let r2_compressed: u256 = u256 {
            low: 0x02d386e8fd6bd85a339171211735bcba,
            high: 0x10defc0130a9f3055798b1f5a99aeb67,
        };
        let r2_sqrt_hint: u256 = u256 {
            low: 0x043f2c451f9ca69ff1577d77d646a50e,
            high: 0x4ee64b0e07d89e906f9e8b7bea09283e,
        };

        let challenge: felt252 = 0xff93d53eda6f2910e3a1313a226533c5;
        let response: felt252 = 0xc09b9a31d72db277d1bb402e80ef5008;

        let fake_glv_hint = array![
            0x4af5bf430174455ca59934c5, 0x748d85ad870959a54bca47ba,
            0x6decdae5e1b9b254, 0x0,
            0xaa008e6009b43d5c309fa848, 0x5b26ec9e21237560e1866183,
            0x7191bfaa5a23d0cb, 0x0,
            0x1569bc348ca5e9beecb728fdbfea1cd6, 0x28e2d5faa7b8c3b25a1678149337cad3
        ].span();

        let s_hint_for_g = array![
            0xa82b6800cf6fafb9e422ff00, 0xa9d32170fa1d6e70ce9f5875,
            0x38d522e54f3cc905, 0x0,
            0x6632b6936c8a0092f2fa8193, 0x48849326ffd29b0fd452c82e,
            0x1cb22722b8aeac6d, 0x0,
            0x3ce8213ee078382bd7862b141d23a01e, 0x12a88328ee6fe07c656e9f1f11921d2ff
        ].span();

        let s_hint_for_y = array![
            0x5f8703b67e528a68c666436f, 0x4319c91a2264dceb203b3c7,
            0x131bcf26d61c6749, 0x0,
            0x2b9edf9810114e3f99120ee8, 0x23ac0997ff9d26665393f4f1,
            0xa2adc2ad21db8d1, 0x0,
            0x3ce8213ee078382bd7862b141d23a01e, 0x12a88328ee6fe07c656e9f1f11921d2ff
        ].span();

        let c_neg_hint_for_t = array![
            0xcc7bbab2a86720f06fa72b5a, 0x27ebc6cd7c83bd71f4819168,
            0x2b4af1beb7dc4112, 0x0,
            0xd0ac52873f110a396803c36c, 0xc23304c89672797661dbefa3,
            0x547b7c3862004a5a, 0x0,
            0xba5f45d69eaafbaaa06091a65e2873d, 0x1301450999c6615fa5bded0ada7e22902
        ].span();

        let c_neg_hint_for_u = array![
            0x3aa67aef7c64a7b253e4a0fc, 0x2799eb3ed1784408cb1f6360,
            0x6d7fa630d5721877, 0x0,
            0x9fed6006f4d300b627b45f, 0xf8f69fd5bc96748bf6e2541b,
            0x56b40a0879ad40ae, 0x0,
            0xba5f45d69eaafbaaa06091a65e2873d, 0x1301450999c6615fa5bded0ada7e22902
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

