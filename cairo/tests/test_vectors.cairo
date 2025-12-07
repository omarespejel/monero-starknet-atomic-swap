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
    low: 0x90b1ab352981d43ec51fba0af7ab51c7,
    high: 0xc21ebc88e5e59867b280909168338026,
};

/// Second Commitment Point R2 (compressed Edwards format)
pub const TESTVECTOR_R2_COMPRESSED: u256 = u256 {
    low: 0x02d386e8fd6bd85a339171211735bcba,
    high: 0x10defc0130a9f3055798b1f5a99aeb67,
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
/// Full challenge: 0xc53365223a31a1e310296fda3ed593ff6212e6122afa3670f0f578dffd3b2703
/// Low 128 bits:   0x6212e6122afa3670f0f578dffd3b2703
pub const TESTVECTOR_CHALLENGE_LOW: felt252 = 0x6212e6122afa3670f0f578dffd3b2703;

/// Challenge scalar (high 124 bits)
pub const TESTVECTOR_CHALLENGE_HIGH: felt252 = 0xc53365223a31a1e310296fda3ed593ff;

/// Response scalar (low 128 bits)
pub const TESTVECTOR_RESPONSE_LOW: felt252 = 0xc09b9a31d72db277d1bb402e80ef5008;

/// Response scalar (high 124 bits)
pub const TESTVECTOR_RESPONSE_HIGH: felt252 = 0x004efaf601adbf89a8283471b5f7cf47;
}

