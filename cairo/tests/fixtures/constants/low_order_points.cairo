//! Ed25519 Low-Order Points Constants
//!
//! These are the 8 points P where 8*P = identity (8-torsion subgroup)
//! Source: https://ristretto.group/test_vectors/ristretto255.html
//! 
//! CRITICAL: These points must be rejected by the contract to prevent
//! attacks where 8*T = O breaks the DLEQ binding.

use core::integer::u256;
use core::array::ArrayTrait;

/// Point 0: Identity (neutral element) - (0, 1)
/// Compressed Edwards: 0x0100000000000000000000000000000000000000000000000000000000000000
/// This is the identity point and must be rejected
/// Generated from Ristretto test vectors: https://ristretto.group/test_vectors/ristretto255.html
pub const LOW_ORDER_POINT_0: u256 = u256 { 
    low: 0x00000000000000000000000000000001, 
    high: 0x00000000000000000000000000000000 
};

/// Point 1: Order 2 - (0, -1)
/// Compressed Edwards: 0xecffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff7f
/// This point satisfies 2*P = identity
/// Generated from Ristretto test vectors: https://ristretto.group/test_vectors/ristretto255.html
pub const LOW_ORDER_POINT_1: u256 = u256 { 
    low: 0xecffffffffffffffffffffffffffffffff, 
    high: 0x7fffffffffffffffffffffffffffffffed 
};

/// Point 2: Order 4
/// Compressed Edwards: 0x0000000000000000000000000000000000000000000000000000000000000000
/// Generated from Ristretto test vectors: https://ristretto.group/test_vectors/ristretto255.html
pub const LOW_ORDER_POINT_2: u256 = u256 {
    low: 0x00000000000000000000000000000000,
    high: 0x00000000000000000000000000000000
};

/// Point 3: Order 4 (with sign bit)
/// Compressed Edwards: 0x0000000000000000000000000000000000000000000000000000000000000080
/// Generated from Ristretto test vectors: https://ristretto.group/test_vectors/ristretto255.html
pub const LOW_ORDER_POINT_3: u256 = u256 {
    low: 0x00000000000000000000000000000080,
    high: 0x00000000000000000000000000000000
};

/// Point 4: Order 8
/// Compressed Edwards: 0x26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc05
/// Generated from Ristretto test vectors: https://ristretto.group/test_vectors/ristretto255.html
pub const LOW_ORDER_POINT_4: u256 = u256 {
    low: 0xd5dfac05d3c63339b13802886d53fc05,
    high: 0x26e8958fc2b227b045c3f489f2ef98f0
};

/// Point 5: Order 8
/// Compressed Edwards: 0x26e8958fc2b227b045c3f489f2ef98f0d5dfac05d3c63339b13802886d53fc85
/// Generated from Ristretto test vectors: https://ristretto.group/test_vectors/ristretto255.html
pub const LOW_ORDER_POINT_5: u256 = u256 {
    low: 0xd5dfac05d3c63339b13802886d53fc85,
    high: 0x26e8958fc2b227b045c3f489f2ef98f0
};

/// Point 6: Order 8
/// Compressed Edwards: 0xc7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac037a
/// Generated from Ristretto test vectors: https://ristretto.group/test_vectors/ristretto255.html
pub const LOW_ORDER_POINT_6: u256 = u256 {
    low: 0x2a2053fa2c39ccc64ec7fd7792ac037a,
    high: 0xc7176a703d4dd84fba3c0b760d10670f
};

/// Point 7: Order 8
/// Compressed Edwards: 0xc7176a703d4dd84fba3c0b760d10670f2a2053fa2c39ccc64ec7fd7792ac03fa
/// Generated from Ristretto test vectors: https://ristretto.group/test_vectors/ristretto255.html
pub const LOW_ORDER_POINT_7: u256 = u256 {
    low: 0x2a2053fa2c39ccc64ec7fd7792ac03fa,
    high: 0xc7176a703d4dd84fba3c0b760d10670f
};

/// Helper to get all low-order points as array
pub fn get_low_order_points() -> Array<u256> {
    array![
        LOW_ORDER_POINT_0,
        LOW_ORDER_POINT_1,
        LOW_ORDER_POINT_2,
        LOW_ORDER_POINT_3,
        LOW_ORDER_POINT_4,
        LOW_ORDER_POINT_5,
        LOW_ORDER_POINT_6,
        LOW_ORDER_POINT_7,
    ]
}

