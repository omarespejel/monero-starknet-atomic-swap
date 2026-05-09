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

/// Ed25519 second generator Y (domain-separated compressed Edwards format)
pub const TESTVECTOR_Y_COMPRESSED: u256 = u256 {
    low: 0x21ba32594950b67cf0d8bb8c8ac5e8c7,
    high: 0xf08df421a3209ab6373dd0ec7ef25dfd,
};

/// Adaptor Point T (compressed Edwards format)
pub const TESTVECTOR_T_COMPRESSED: u256 = u256 {
    low: 0x54e86953e7cc99b545cfef03f63cce85,
    high: 0x427dde0adb325f957d29ad71e4643882,
};

/// Second Point U (compressed Edwards format)
pub const TESTVECTOR_U_COMPRESSED: u256 = u256 {
    low: 0x9244eb3a3699efed3106c6ae0afdf28,
    high: 0xb6e0bfc0d9fbb8a4c8ef08cb5da2eff3,
};

/// First Commitment Point R1 (compressed Edwards format)
pub const TESTVECTOR_R1_COMPRESSED: u256 = u256 {
    low: 0x3cb02521d7a17fedca11c02ea41fe334,
    high: 0x11ef09256f90d942ca7a0e4ae05926a5,
};

/// Second Commitment Point R2 (compressed Edwards format)
pub const TESTVECTOR_R2_COMPRESSED: u256 = u256 {
    low: 0xe66ca975ef303c032fcc18a952325162,
    high: 0xc5d2eb608176c8b79dfa55289c35b35f,
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

/// Full Poseidon challenge felt used by Cairo and Rust.
pub const TESTVECTOR_CHALLENGE: felt252 = 0x47c760eb9b6a8797680bef6218e06aacc6570f8be11819d2268bb024f816108;

/// Response scalar (full scalar)
pub const TESTVECTOR_RESPONSE: u256 = u256 { low: 0xbe3ffdd10e06b50b800feb45877b787b, high: 0x2f0ceba8a8c56d6f6b4ed3ae98db234 };

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
    low: 0xcffea6b3bffe746de20fdd0734b30845,
    high: 0x5e4a3b18b41199f9389ded8696067271,
};

/// R1 Commitment Point sqrt hint (CORRECT - matches test_e2e_dleq.cairo)
pub const TESTVECTOR_R1_SQRT_HINT: u256 = u256 {
    low: 0x623d9789d855bcc4f0fbd8683b350688,
    high: 0x0a2d15cdfbfcf6181e92f0b7c74b477e,
};

/// R2 Commitment Point sqrt hint (CORRECT - matches test_e2e_dleq.cairo)
pub const TESTVECTOR_R2_SQRT_HINT: u256 = u256 {
    low: 0xd8b08d5ec3d265b83e5e333d750d6b37,
    high: 0x0e41fbdbbf62b47c511e0a5aa04059de,
};
}
