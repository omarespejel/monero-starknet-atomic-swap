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
    low: 0x623d9789d855bcc4f0fbd8683b350688,
    high: 0x0a2d15cdfbfcf6181e92f0b7c74b477e,
};

/// Commitment Point R2 sqrt hint
/// VALIDATED: 2025-12-09 via test_unit_point_decompression
pub const SQRT_HINT_R2: u256 = u256 {
    low: 0x598521e3f6d818ed84721901f0d87f89,
    high: 0x09d2fd2811966933dff4c8ab0d9059fc,
};

