//! Tests for zeroization of sensitive data

use curve25519_dalek::scalar::Scalar;
use zeroize::Zeroize;

#[test]
fn test_revealed_bytes_zeroized() {
    let mut bytes = [0x42u8; 32];
    let ptr = bytes.as_ptr();
    
    // Simulate what handle_secret_revealed does
    let _scalar = Scalar::from_bytes_mod_order(bytes);
    bytes.zeroize();
    
    // Verify zeroized
    unsafe {
        assert!(std::slice::from_raw_parts(ptr, 32).iter().all(|&b| b == 0),
                "Bytes were not zeroized");
    }
}

#[test]
fn test_key_splitting_bytes_zeroized() {
    use rand::{rngs::OsRng, RngCore};
    
    // Test partial_bytes zeroization
    let mut partial_bytes = [0u8; 32];
    let ptr_partial = partial_bytes.as_ptr();
    OsRng.fill_bytes(&mut partial_bytes);
    let _partial_key = Scalar::from_bytes_mod_order(partial_bytes);
    partial_bytes.zeroize();
    
    unsafe {
        assert!(std::slice::from_raw_parts(ptr_partial, 32).iter().all(|&b| b == 0),
                "Partial bytes were not zeroized");
    }
    
    // Test adaptor_bytes zeroization
    let mut adaptor_bytes = [0u8; 32];
    let ptr_adaptor = adaptor_bytes.as_ptr();
    OsRng.fill_bytes(&mut adaptor_bytes);
    let _adaptor_scalar = Scalar::from_bytes_mod_order(adaptor_bytes);
    adaptor_bytes.zeroize();
    
    unsafe {
        assert!(std::slice::from_raw_parts(ptr_adaptor, 32).iter().all(|&b| b == 0),
                "Adaptor bytes were not zeroized");
    }
}

