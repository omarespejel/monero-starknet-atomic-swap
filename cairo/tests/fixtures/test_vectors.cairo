/// # Test Vector Constants (Single Source of Truth)
///
/// This file contains all test vector constants from `rust/test_vectors.json`.
/// All test files should import from here to ensure consistency.
///
/// **CRITICAL**: These constants are regenerated from Rust whenever test_vectors.json changes.
/// Do not modify these values manually - always regenerate from Rust.

#[cfg(test)]
mod test_vectors {
    use core::integer::u256;

/// Ed25519 order (from RFC 8032)
pub const ED25519_ORDER: u256 = u256 {
    low: 0x14def9dea2f79cd65812631a5cf5d3ed,
    high: 0x10000000000000000000000000000000,
};

/// Ed25519 Base Point G (compressed Edwards format)
/// RFC 8032: G_compressed = 0x5866666666666666666666666666666666666666666666666666666666666666
pub const TESTVECTOR_G_COMPRESSED: u256 = u256 {
    low: 0x66666666666666666666666666666658,
    high: 0x66666666666666666666666666666666,
};

/// Ed25519 Second Generator Y = 2·G (compressed Edwards format)
pub const TESTVECTOR_Y_COMPRESSED: u256 = u256 {
    low: 0x97390f51643851560e5f46ae6af8a3c9,
    high: 0x2260cdf3092329c21da25ee8c9a21f56,
};

/// Adaptor Point T (compressed Edwards format)
pub const TESTVECTOR_T_COMPRESSED: u256 = u256 {
    low: 0x54e86953e7cc99b545cfef03f63cce85,
    high: 0x427dde0adb325f957d29ad71e4643882,
};

/// Second Point U (compressed Edwards format)
pub const TESTVECTOR_U_COMPRESSED: u256 = u256 {
    low: 0xd893b3476bdf09770b7616f84c5c7bbe,
    high: 0x5c79d0fa84d6440908e2e2065e60d1cd,
};

/// First Commitment Point R1 (compressed Edwards format)
pub const TESTVECTOR_R1_COMPRESSED: u256 = u256 {
    low: 0x3cb02521d7a17fedca11c02ea41fe334,
    high: 0x11ef09256f90d942ca7a0e4ae05926a5,
};

/// Second Commitment Point R2 (compressed Edwards format)
pub const TESTVECTOR_R2_COMPRESSED: u256 = u256 {
    low: 0xb4fb26c272cbe6b84d65d4f908aff02f,
    high: 0xf58498fd33c0fbca066f3fdff2f49225,
};

/// Hashlock (SHA-256 hash as 8 u32 words, big-endian from SHA-256)
pub const TESTVECTOR_HASHLOCK: [u32; 8] = [
    0xb6acca81_u32,
    0xa0939a85_u32,
    0x6c35e4c4_u32,
    0x188e95b9_u32,
    0x1731aab1_u32,
    0xd4629a4c_u32,
    0xee79dd09_u32,
    0xded4fc94_u32,
];

/// Challenge scalar (low 128 bits) - truncated from full challenge
/// Full challenge (reduced scalar, LE bytes): 0x4af9984d35443a32abbd1008b74b668d00000000000000000000000000000000
/// Low 128 bits:   0x8d664bb70810bdab323a44354d98f94a
pub const TESTVECTOR_CHALLENGE_LOW: felt252 = 0x8d664bb70810bdab323a44354d98f94a;

/// Challenge scalar (high 124 bits)
pub const TESTVECTOR_CHALLENGE_HIGH: felt252 = 0x0;

/// Response scalar (low 128 bits)
pub const TESTVECTOR_RESPONSE_LOW: felt252 = 0x1e741f8fec4161ea41b23ce6d007ba12;

/// Response scalar (high 124 bits)
pub const TESTVECTOR_RESPONSE_HIGH: felt252 = 0x026ed77551e578013227c9b98bd25c66;

/// Sqrt hints for point decompression (Garaga format)
/// CRITICAL: These must match the compressed points exactly
/// Generated using tools/generate_sqrt_hints.py with Garaga's exact decompression format

/// Adaptor Point T sqrt hint (CORRECT - matches test_e2e_dleq.cairo)
pub const TESTVECTOR_T_SQRT_HINT: u256 = u256 {
    low: 0x448c18dcf34127e112ff945a65defbfc,
    high: 0x17611da35f39a2a5e3a9fddb8d978e4f,
};

/// Second Point U sqrt hint (CORRECT - matches test_e2e_dleq.cairo)
pub const TESTVECTOR_U_SQRT_HINT: u256 = u256 {
    low: 0xdcad2173817c163b5405cec7698eb4b8,
    high: 0x742bb3c44b13553c8ddff66565b44cac,
};

/// R1 Commitment Point sqrt hint (CORRECT - matches test_e2e_dleq.cairo)
pub const TESTVECTOR_R1_SQRT_HINT: u256 = u256 {
    low: 0x623d9789d855bcc4f0fbd8683b350688,
    high: 0x0a2d15cdfbfcf6181e92f0b7c74b477e,
};

/// R2 Commitment Point sqrt hint (CORRECT - matches test_e2e_dleq.cairo)
pub const TESTVECTOR_R2_SQRT_HINT: u256 = u256 {
    low: 0x598521e3f6d818ed84721901f0d87f89,
    high: 0x09d2fd2811966933dff4c8ab0d9059fc,
};
}

