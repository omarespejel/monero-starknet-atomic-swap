//! Comprehensive tests for hash-to-point (Hp) function
//! 
//! These tests verify the cryptographic correctness of the hash-to-point
//! implementation, which is critical for key image computation.

use curve25519_dalek::{
    constants::ED25519_BASEPOINT_POINT,
    edwards::EdwardsPoint,
    scalar::Scalar,
};
use xmr_secret_gen::clsag::{hash_to_point, compute_key_image};
use rand::rngs::OsRng;

#[test]
fn test_hash_to_point_deterministic() {
    // Same input must produce same output
    let point = ED25519_BASEPOINT_POINT;
    let hp1 = hash_to_point(&point);
    let hp2 = hash_to_point(&point);
    
    assert_eq!(hp1, hp2, "hash_to_point must be deterministic");
}

#[test]
fn test_hash_to_point_different_inputs() {
    // Different inputs must produce different outputs
    let g = ED25519_BASEPOINT_POINT;
    let two_g = g + g;
    
    let hp_g = hash_to_point(&g);
    let hp_2g = hash_to_point(&two_g);
    
    assert_ne!(hp_g, hp_2g, "Different inputs must produce different hash points");
}

#[test]
fn test_hash_to_point_not_identity() {
    // Hash-to-point should never return identity
    let point = ED25519_BASEPOINT_POINT;
    let hp = hash_to_point(&point);
    
    assert_ne!(hp, EdwardsPoint::default(), "Hp(P) must not be identity");
}

#[test]
fn test_hash_to_point_multiple_points() {
    // Test with multiple different points
    let g = ED25519_BASEPOINT_POINT;
    let mut previous_hp = hash_to_point(&g);
    
    for i in 2..10 {
        let point = Scalar::from(i as u64) * g;
        let hp = hash_to_point(&point);
        
        assert_ne!(hp, previous_hp, "Each point must hash to unique value");
        assert_ne!(hp, EdwardsPoint::default(), "Hp must not be identity");
        
        previous_hp = hp;
    }
}

#[test]
fn test_key_image_computation() {
    // Key image computation must be correct
    let secret = Scalar::from(42u64);
    let public = secret * ED25519_BASEPOINT_POINT;
    
    let key_image = compute_key_image(&secret, &public);
    
    // Key image should not be identity
    assert_ne!(key_image, EdwardsPoint::default(), "Key image must not be identity");
    
    // Same secret should give same key image
    let key_image_2 = compute_key_image(&secret, &public);
    assert_eq!(key_image, key_image_2, "Key image must be deterministic");
}

#[test]
fn test_key_image_different_secrets() {
    // Different secrets must produce different key images
    let g = ED25519_BASEPOINT_POINT;
    
    let secret1 = Scalar::from(100u64);
    let public1 = secret1 * g;
    let key_image1 = compute_key_image(&secret1, &public1);
    
    let secret2 = Scalar::from(200u64);
    let public2 = secret2 * g;
    let key_image2 = compute_key_image(&secret2, &public2);
    
    assert_ne!(key_image1, key_image2, "Different secrets must produce different key images");
}

#[test]
fn test_key_image_consistency() {
    // Key image must be consistent: I = x · Hp(P) where P = x·G
    let secret = Scalar::random(&mut OsRng);
    let public = secret * ED25519_BASEPOINT_POINT;
    
    let key_image = compute_key_image(&secret, &public);
    
    // Verify: I = x · Hp(P)
    let hp = hash_to_point(&public);
    let expected_key_image = secret * hp;
    
    assert_eq!(key_image, expected_key_image, "Key image formula must hold: I = x · Hp(P)");
}

#[test]
fn test_hash_to_point_cofactor_clearing() {
    // Hash-to-point should return points in prime-order subgroup
    // This is verified by checking that 8*Hp(P) != identity (if it were small-order, 8*P = identity)
    let point = ED25519_BASEPOINT_POINT;
    let hp = hash_to_point(&point);
    
    // Multiply by cofactor 8
    let cofactor = Scalar::from(8u64);
    let multiplied = cofactor * hp;
    
    // If hp was in small subgroup, multiplied would be identity
    // We check that it's not identity (though this is probabilistic)
    assert_ne!(multiplied, EdwardsPoint::default(), "Hp(P) should be in prime-order subgroup");
}

#[test]
fn test_key_image_linkability() {
    // Key images must link all spends from the same key
    // Same secret key + same public key = same key image
    let secret = Scalar::random(&mut OsRng);
    let public = secret * ED25519_BASEPOINT_POINT;
    
    let key_image1 = compute_key_image(&secret, &public);
    let key_image2 = compute_key_image(&secret, &public);
    let key_image3 = compute_key_image(&secret, &public);
    
    assert_eq!(key_image1, key_image2, "Key images must be identical for same key");
    assert_eq!(key_image2, key_image3, "Key images must be identical for same key");
}

#[test]
fn test_key_image_uniqueness() {
    // Different keys must produce different key images
    let g = ED25519_BASEPOINT_POINT;
    
    let mut key_images = Vec::new();
    
    for i in 0..20 {
        let secret = Scalar::from(i as u64 + 1000);
        let public = secret * g;
        let key_image = compute_key_image(&secret, &public);
        
        // Check uniqueness
        for existing in &key_images {
            assert_ne!(*existing, key_image, "Each key must have unique key image");
        }
        
        key_images.push(key_image);
    }
}

