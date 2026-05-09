/// # Deployment Helpers with Test Vectors
///
/// This module provides deployment helpers that use real DLEQ proof data from test vectors.
/// All successful-deployment tests should use these helpers instead of invalid
/// rejection-test data.

use atomic_lock::IAtomicLockDispatcher;
use core::array::ArrayTrait;
use core::integer::u256;
use starknet::ContractAddress;
use super::dleq_test_helpers::deploy_with_dleq_proof;

// Import test vector constants directly (they're in #[cfg(test)] mod, so accessible in tests)
// Note: Cairo's module system requires direct access - we'll use constants directly
// These match test_vectors.cairo values
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

/// Deploy contract with test vector data (recommended for most tests).
///
/// This helper uses authoritative test vectors and real MSM hints to ensure
/// DLEQ verification succeeds. Uses the test vector hashlock and secret [0x12; 32].
pub fn deploy_with_test_vectors(
    lock_until: u64,
    token: ContractAddress,
    amount: u256,
) -> IAtomicLockDispatcher {
    // Use hashlock from test vectors
    let hashlock = array![
        0xb6acca81_u32, 0xa0939a85_u32, 0x6c35e4c4_u32, 0x188e95b9_u32,
        0x1731aab1_u32, 0xd4629a4c_u32, 0xee79dd09_u32, 0xded4fc94_u32,
    ].span();
    
    // Get real MSM hints (from test_e2e_dleq.cairo pattern)
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
    
    deploy_with_dleq_proof(
        hashlock,
        lock_until,
        token,
        amount,
        TESTVECTOR_T_COMPRESSED,
        TESTVECTOR_T_SQRT_HINT,
        TESTVECTOR_U_COMPRESSED,
        TESTVECTOR_U_SQRT_HINT,
        TESTVECTOR_CHALLENGE,  // Full Poseidon challenge felt
        TESTVECTOR_RESPONSE,   // Full Ed25519 response scalar
        fake_glv_hint,
        s_hint_for_g,
        s_hint_for_y,
        c_neg_hint_for_t,
        c_neg_hint_for_u,
        TESTVECTOR_R1_COMPRESSED,
        TESTVECTOR_R1_SQRT_HINT,
        TESTVECTOR_R2_COMPRESSED,
        TESTVECTOR_R2_SQRT_HINT,
    )
}

/// Get real MSM hints generated from test vectors.
///
/// These hints are production-grade and match the full scalars used in Cairo.
/// CRITICAL: Hints are generated from the full challenge/response, not legacy 128-bit truncations.
fn get_real_msm_hints() -> (
    Span<felt252>,
    Span<felt252>,
    Span<felt252>,
    Span<felt252>,
) {
    // s_hint_for_g: Fake-GLV hint for s·G (with full s)
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

    // s_hint_for_y: Fake-GLV hint for s·Y (with full s)
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

    // c_neg_hint_for_t: Fake-GLV hint for (-c)·T (with full c)
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

    // c_neg_hint_for_u: Fake-GLV hint for (-c)·U (with full c)
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
