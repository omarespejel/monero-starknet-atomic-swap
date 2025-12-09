//! AUTHORITATIVE SQRT HINTS - DO NOT MODIFY
//!
//! These sqrt hints are empirically validated to work with Garaga's
//! decompress_edwards_pt_from_y_compressed_le_into_weirstrasspoint function.
//!
//! HISTORY:
//! - 2025-12-09: Fixed after deployment_vector.json sqrt hints failed
//!               Root cause: Python-generated hints used different algorithm
//!               Solution: Use Cairo-validated hints from passing tests
//!
//! HOW TO UPDATE:
//! 1. NEVER compute sqrt hints in Python/Rust
//! 2. Run Cairo point decompression test with candidate hint
//! 3. If test passes, the hint is valid
//! 4. Copy the working hint here

use core::integer::u256;

/// Adaptor Point T sqrt hint
/// VALIDATED: 2025-12-09 via test_unit_point_decompression
pub const SQRT_HINT_T: u256 = u256 {
    low: 0x448c18dcf34127e112ff945a65defbfc,
    high: 0x17611da35f39a2a5e3a9fddb8d978e4f,
};

/// Second Point U sqrt hint
/// VALIDATED: 2025-12-09 via test_unit_point_decompression
pub const SQRT_HINT_U: u256 = u256 {
    low: 0xdcad2173817c163b5405cec7698eb4b8,
    high: 0x742bb3c44b13553c8ddff66565b44cac,
};

/// Commitment Point R1 sqrt hint
/// VALIDATED: 2025-12-09 via test_unit_point_decompression
pub const SQRT_HINT_R1: u256 = u256 {
    low: 0x72a9698d3171817c239f4009cc36fc97,
    high: 0x3f2b84592a9ee701d24651e3aa3c837d,
};

/// Commitment Point R2 sqrt hint
/// VALIDATED: 2025-12-09 via test_unit_point_decompression
pub const SQRT_HINT_R2: u256 = u256 {
    low: 0x43f2c451f9ca69ff1577d77d646a50e,
    high: 0x4ee64b0e07d89e906f9e8b7bea09283e,
};

