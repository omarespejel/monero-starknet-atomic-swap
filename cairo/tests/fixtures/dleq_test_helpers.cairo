/// # DLEQ Test Helpers
///
/// Helper functions for generating and using DLEQ proofs in tests.
/// This module enables testing with various adaptor points to discover vulnerabilities.
///
/// **Usage:**
/// 1. Generate DLEQ proof using `tools/generate_dleq_for_adaptor_point.py <secret_hex>`
/// 2. Use the generated proof data in tests with `deploy_with_dleq_proof`
///
/// **Security Note:**
/// These helpers use pre-generated DLEQ proofs. For production, proofs must be
/// generated securely using the Rust implementation.

use atomic_lock::IAtomicLockDispatcher;
use core::array::ArrayTrait;
use core::integer::u256;
use core::serde::Serde;
use starknet::ContractAddress;
use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};

/// Deploy contract with pre-generated DLEQ proof.
///
/// This helper allows tests to use arbitrary adaptor points by providing
/// pre-generated DLEQ proofs. The proofs should be generated using
/// `tools/generate_dleq_for_adaptor_point.py`.
///
/// **Example:**
/// ```cairo
/// // Generate proof: python tools/generate_dleq_for_adaptor_point.py <secret_hex> > proof.json
/// // Then use the proof data:
/// let proof = DleqProofData {
///     hashlock: hashlock_array.span(),
///     adaptor_point_compressed: ...,
///     // ... (from generated proof.json)
/// };
/// let contract = deploy_with_dleq_proof(
///     proof.hashlock,
///     FUTURE_TIMESTAMP,
///     token,
///     amount,
///     proof,
///     fake_glv_hint,
/// );
/// ```
pub fn deploy_with_dleq_proof(
    hashlock: Span<u32>,
    lock_until: u64,
    token: ContractAddress,
    amount: u256,
    adaptor_point_compressed: u256,
    adaptor_point_sqrt_hint: u256,
    second_point_compressed: u256,
    second_point_sqrt_hint: u256,
    challenge: felt252,
    response: felt252,
    fake_glv_hint: Span<felt252>,
    s_hint_for_g: Span<felt252>,
    s_hint_for_y: Span<felt252>,
    c_neg_hint_for_t: Span<felt252>,
    c_neg_hint_for_u: Span<felt252>,
    r1_compressed: u256,
    r1_sqrt_hint: u256,
    r2_compressed: u256,
    r2_sqrt_hint: u256,
) -> IAtomicLockDispatcher {
    let declare_res = declare("AtomicLock");
    let contract = declare_res.unwrap().contract_class();

    let mut calldata = ArrayTrait::new();
    hashlock.serialize(ref calldata);
    Serde::serialize(@lock_until, ref calldata);
    Serde::serialize(@token, ref calldata);
    Serde::serialize(@amount, ref calldata);
    
    // Adaptor point (compressed Edwards + sqrt hint)
    Serde::serialize(@adaptor_point_compressed, ref calldata);
    Serde::serialize(@adaptor_point_sqrt_hint, ref calldata);
    
    // DLEQ second point (compressed Edwards + sqrt hint)
    Serde::serialize(@second_point_compressed, ref calldata);
    Serde::serialize(@second_point_sqrt_hint, ref calldata);
    
    // DLEQ proof (challenge, response)
    Serde::serialize(@challenge, ref calldata);
    Serde::serialize(@response, ref calldata);
    
    // Fake-GLV hint (for adaptor point)
    Serde::serialize(@fake_glv_hint, ref calldata);
    
    // DLEQ hints (for MSM operations in verification)
    Serde::serialize(@s_hint_for_g, ref calldata);
    Serde::serialize(@s_hint_for_y, ref calldata);
    Serde::serialize(@c_neg_hint_for_t, ref calldata);
    Serde::serialize(@c_neg_hint_for_u, ref calldata);
    
    // R1 and R2 commitment points
    Serde::serialize(@r1_compressed, ref calldata);
    Serde::serialize(@r1_sqrt_hint, ref calldata);
    Serde::serialize(@r2_compressed, ref calldata);
    Serde::serialize(@r2_sqrt_hint, ref calldata);

    let (addr, _) = contract.deploy(@calldata).unwrap();
    IAtomicLockDispatcher { contract_address: addr }
}

