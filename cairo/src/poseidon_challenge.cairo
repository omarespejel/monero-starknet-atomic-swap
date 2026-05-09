/// # Poseidon Challenge Computation Module
///
/// Production-grade Poseidon-based Fiat-Shamir challenge for DLEQ proofs.
/// Uses compressed Edwards points (u256) to avoid Weierstrass conversion.
///
/// **Status**: Uses Cairo core Poseidon (allowed on Starknet)
/// **Transcript**: Poseidon("DLEQ" || G || Y || T || U || R1 || R2 || hashlock)
///
/// Points are serialized as compressed Edwards u256 values using:
/// - low 128 bits, then high 128 bits (little-endian limb order)
/// Hashlock is serialized as 8 u32 words (big-endian SHA-256 words).
use core::hash::HashStateTrait;
use core::integer::u256;
use core::poseidon::{HashState, PoseidonTrait};

/// Compute DLEQ challenge using Poseidon with compressed Edwards points.
///
/// @param G_compressed Standard Ed25519 generator (compressed Edwards, u256)
/// @param Y_compressed Second generator for DLEQ (compressed Edwards, u256)
/// @param T_compressed Adaptor point (compressed Edwards, u256)
/// @param U_compressed DLEQ second point (compressed Edwards, u256)
/// @param R1_compressed First commitment point (compressed Edwards, u256)
/// @param R2_compressed Second commitment point (compressed Edwards, u256)
/// @param hashlock SHA-256 hash of secret (Span<u32> - 8 words, big-endian)
/// @param ed25519_order Ed25519 curve order for reduction. Unused for Poseidon because a Stark
/// field element is already below the Ed25519 group order.
/// @return Challenge scalar c as a full felt252, not truncated to 128 bits.
pub fn compute_dleq_challenge_poseidon(
    G_compressed: u256,
    Y_compressed: u256,
    T_compressed: u256,
    U_compressed: u256,
    R1_compressed: u256,
    R2_compressed: u256,
    hashlock: Span<u32>,
    _ed25519_order: u256,
) -> felt252 {
    let mut state = PoseidonTrait::new();
    let dleq_tag: felt252 = 0x444c4551; // "DLEQ"
    state = state.update(dleq_tag);
    state = state.update(dleq_tag);

    state = update_compressed_point(state, G_compressed);
    state = update_compressed_point(state, Y_compressed);
    state = update_compressed_point(state, T_compressed);
    state = update_compressed_point(state, U_compressed);
    state = update_compressed_point(state, R1_compressed);
    state = update_compressed_point(state, R2_compressed);

    let mut i = 0;
    while i < hashlock.len() {
        let word = *hashlock.at(i);
        state = state.update(word.into());
        i += 1;
    }

    state.finalize()
}

fn update_compressed_point(mut state: HashState, point: u256) -> HashState {
    let low: felt252 = point.low.into();
    let high: felt252 = point.high.into();
    state = state.update(low);
    state = state.update(high);
    state
}
