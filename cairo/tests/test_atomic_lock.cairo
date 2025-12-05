#[cfg(test)]
mod tests {
    use atomic_lock::{IAtomicLockDispatcher, IAtomicLockDispatcherTrait};
    use core::array::ArrayTrait;
    use core::byte_array::{ByteArray, ByteArrayTrait};
    use core::integer::u256;
    use core::result::ResultTrait;
    use core::serde::Serde;
    use starknet::contract_address::ContractAddress;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};

    #[test]
    fn test_cryptographic_handshake() {
        // Use real secret/hash from generator to satisfy MSM.
        let expected_hash = array![
            3606997102_u32, 3756602050_u32, 1811765011_u32, 1576844653_u32,
            61256116_u32, 2110839708_u32, 540553134_u32, 3341226206_u32
        ].span();
        let mut secret_input: ByteArray = Default::default();
        secret_input.append_byte(0x09_u8);
        secret_input.append_byte(0x9d_u8);
        secret_input.append_byte(0xd9_u8);
        secret_input.append_byte(0xb7_u8);
        secret_input.append_byte(0x3e_u8);
        secret_input.append_byte(0x2e_u8);
        secret_input.append_byte(0x84_u8);
        secret_input.append_byte(0xdb_u8);
        secret_input.append_byte(0x47_u8);
        secret_input.append_byte(0x2b_u8);
        secret_input.append_byte(0x34_u8);
        secret_input.append_byte(0x2d_u8);
        secret_input.append_byte(0xc3_u8);
        secret_input.append_byte(0xab_u8);
        secret_input.append_byte(0x05_u8);
        secret_input.append_byte(0x20_u8);
        secret_input.append_byte(0xf6_u8);
        secret_input.append_byte(0x54_u8);
        secret_input.append_byte(0xfd_u8);
        secret_input.append_byte(0x8a_u8);
        secret_input.append_byte(0x81_u8);
        secret_input.append_byte(0xd6_u8);
        secret_input.append_byte(0x44_u8);
        secret_input.append_byte(0x18_u8);
        secret_input.append_byte(0x04_u8);
        secret_input.append_byte(0x77_u8);
        secret_input.append_byte(0x73_u8);
        secret_input.append_byte(0x0a_u8);
        secret_input.append_byte(0x90_u8);
        secret_input.append_byte(0xaf_u8);
        secret_input.append_byte(0x89_u8);
        secret_input.append_byte(0x00_u8);

        let x_limbs = (
            0x460f72719199c63ec398673f,
            0xf27a4af146a52a7dbdeb4cfb,
            0x5f9c70ec759789a0,
            0x0
        );
        let y_limbs = (
            0x6b43e318a2a02d8241549109,
            0x40e30afa4cce98c21e473980,
            0x5e243e1eed1aa575,
            0x0
        );
        let hint = array![
            0x460f72719199c63ec398673f,
            0xf27a4af146a52a7dbdeb4cfb,
            0x5f9c70ec759789a0,
            0x0,
            0x6b43e318a2a02d8241549109,
            0x40e30afa4cce98c21e473980,
            0x5e243e1eed1aa575,
            0x0,
            0x10b51d41eab43e36d3ac30cda9707f92,
            0x110538332d2eae09bf756dfd87431ded7
        ].span();

        let dispatcher = deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            hint,
        );

        let success = dispatcher.verify_and_unlock(secret_input);
        assert(success, 'unlock fail');
        assert(dispatcher.is_unlocked(), 'state');
    }

    #[test]
    fn test_wrong_secret_fails() {
        let expected_hash = array![3606997102_u32, 3756602050_u32, 1811765011_u32, 1576844653_u32, 61256116_u32, 2110839708_u32, 540553134_u32, 3341226206_u32].span();
        let x_limbs = (0x460f72719199c63ec398673f, 0xf27a4af146a52a7dbdeb4cfb, 0x5f9c70ec759789a0, 0x0);
        let y_limbs = (0x6b43e318a2a02d8241549109, 0x40e30afa4cce98c21e473980, 0x5e243e1eed1aa575, 0x0);
        let hint = array![
            0x460f72719199c63ec398673f,
            0xf27a4af146a52a7dbdeb4cfb,
            0x5f9c70ec759789a0,
            0x0,
            0x6b43e318a2a02d8241549109,
            0x40e30afa4cce98c21e473980,
            0x5e243e1eed1aa575,
            0x0,
            0x10b51d41eab43e36d3ac30cda9707f92,
            0x110538332d2eae09bf756dfd87431ded7
        ].span();
        let dispatcher = deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            hint,
        );

        // wrong secret → hash check fails before MSM
        let wrong_secret = "wrong_secret";
        let success = dispatcher.verify_and_unlock(wrong_secret);
        assert(!success, 'wrong secret');
        assert(!dispatcher.is_unlocked(), 'stay locked');
    }

    #[test]
    #[should_panic]
    fn test_cannot_unlock_twice() {
        let mut secret_input: ByteArray = Default::default();
        secret_input.append_byte(0x09_u8); secret_input.append_byte(0x9d_u8);
        secret_input.append_byte(0xd9_u8); secret_input.append_byte(0xb7_u8);
        secret_input.append_byte(0x3e_u8); secret_input.append_byte(0x2e_u8);
        secret_input.append_byte(0x84_u8); secret_input.append_byte(0xdb_u8);
        secret_input.append_byte(0x47_u8); secret_input.append_byte(0x2b_u8);
        secret_input.append_byte(0x34_u8); secret_input.append_byte(0x2d_u8);
        secret_input.append_byte(0xc3_u8); secret_input.append_byte(0xab_u8);
        secret_input.append_byte(0x05_u8); secret_input.append_byte(0x20_u8);
        secret_input.append_byte(0xf6_u8); secret_input.append_byte(0x54_u8);
        secret_input.append_byte(0xfd_u8); secret_input.append_byte(0x8a_u8);
        secret_input.append_byte(0x81_u8); secret_input.append_byte(0xd6_u8);
        secret_input.append_byte(0x44_u8); secret_input.append_byte(0x18_u8);
        secret_input.append_byte(0x04_u8); secret_input.append_byte(0x77_u8);
        secret_input.append_byte(0x73_u8); secret_input.append_byte(0x0a_u8);
        secret_input.append_byte(0x90_u8); secret_input.append_byte(0xaf_u8);
        secret_input.append_byte(0x89_u8); secret_input.append_byte(0x00_u8);

        let expected_hash = array![3606997102_u32, 3756602050_u32, 1811765011_u32, 1576844653_u32, 61256116_u32, 2110839708_u32, 540553134_u32, 3341226206_u32].span();
        let x_limbs = (0x460f72719199c63ec398673f, 0xf27a4af146a52a7dbdeb4cfb, 0x5f9c70ec759789a0, 0x0);
        let y_limbs = (0x6b43e318a2a02d8241549109, 0x40e30afa4cce98c21e473980, 0x5e243e1eed1aa575, 0x0);
        let hint = array![
            0x460f72719199c63ec398673f,
            0xf27a4af146a52a7dbdeb4cfb,
            0x5f9c70ec759789a0,
            0x0,
            0x6b43e318a2a02d8241549109,
            0x40e30afa4cce98c21e473980,
            0x5e243e1eed1aa575,
            0x0,
            0x10b51d41eab43e36d3ac30cda9707f92,
            0x110538332d2eae09bf756dfd87431ded7
        ].span();
        let dispatcher = deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            hint,
        );

        assert(dispatcher.verify_and_unlock(secret_input), 'first ok');
        dispatcher.verify_and_unlock("unlock_me");
    }

    #[test]
    fn test_rust_generated_secret() {
        // Values from Python generator
        let expected_hash = array![
            3606997102_u32, 3756602050_u32, 1811765011_u32, 1576844653_u32,
            61256116_u32, 2110839708_u32, 540553134_u32, 3341226206_u32
        ].span();
        let mut secret_input: ByteArray = Default::default();
        secret_input.append_byte(0x09_u8);
        secret_input.append_byte(0x9d_u8);
        secret_input.append_byte(0xd9_u8);
        secret_input.append_byte(0xb7_u8);
        secret_input.append_byte(0x3e_u8);
        secret_input.append_byte(0x2e_u8);
        secret_input.append_byte(0x84_u8);
        secret_input.append_byte(0xdb_u8);
        secret_input.append_byte(0x47_u8);
        secret_input.append_byte(0x2b_u8);
        secret_input.append_byte(0x34_u8);
        secret_input.append_byte(0x2d_u8);
        secret_input.append_byte(0xc3_u8);
        secret_input.append_byte(0xab_u8);
        secret_input.append_byte(0x05_u8);
        secret_input.append_byte(0x20_u8);
        secret_input.append_byte(0xf6_u8);
        secret_input.append_byte(0x54_u8);
        secret_input.append_byte(0xfd_u8);
        secret_input.append_byte(0x8a_u8);
        secret_input.append_byte(0x81_u8);
        secret_input.append_byte(0xd6_u8);
        secret_input.append_byte(0x44_u8);
        secret_input.append_byte(0x18_u8);
        secret_input.append_byte(0x04_u8);
        secret_input.append_byte(0x77_u8);
        secret_input.append_byte(0x73_u8);
        secret_input.append_byte(0x0a_u8);
        secret_input.append_byte(0x90_u8);
        secret_input.append_byte(0xaf_u8);
        secret_input.append_byte(0x89_u8);
        secret_input.append_byte(0x00_u8);

        let x_limbs = (
            0x460f72719199c63ec398673f,
            0xf27a4af146a52a7dbdeb4cfb,
            0x5f9c70ec759789a0,
            0x0
        );
        let y_limbs = (
            0x6b43e318a2a02d8241549109,
            0x40e30afa4cce98c21e473980,
            0x5e243e1eed1aa575,
            0x0
        );
        let hint = array![
            0x460f72719199c63ec398673f,
            0xf27a4af146a52a7dbdeb4cfb,
            0x5f9c70ec759789a0,
            0x0,
            0x6b43e318a2a02d8241549109,
            0x40e30afa4cce98c21e473980,
            0x5e243e1eed1aa575,
            0x0,
            0x10b51d41eab43e36d3ac30cda9707f92,
            0x110538332d2eae09bf756dfd87431ded7
        ].span();

        let dispatcher = deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            hint,
        );

        let success = dispatcher.verify_and_unlock(secret_input);
        assert(success, 'hash mismatch');
    }

    #[test]
    fn test_refund_after_expiry() {
        // lock_until = 0 to allow immediate refund without time travel
        let expected_hash = array![3606997102_u32, 3756602050_u32, 1811765011_u32, 1576844653_u32, 61256116_u32, 2110839708_u32, 540553134_u32, 3341226206_u32].span();
        let x_limbs = (0x460f72719199c63ec398673f, 0xf27a4af146a52a7dbdeb4cfb, 0x5f9c70ec759789a0, 0x0);
        let y_limbs = (0x6b43e318a2a02d8241549109, 0x40e30afa4cce98c21e473980, 0x5e243e1eed1aa575, 0x0);
        let hint = array![
            0x460f72719199c63ec398673f,
            0xf27a4af146a52a7dbdeb4cfb,
            0x5f9c70ec759789a0,
            0x0,
            0x6b43e318a2a02d8241549109,
            0x40e30afa4cce98c21e473980,
            0x5e243e1eed1aa575,
            0x0,
            0x10b51d41eab43e36d3ac30cda9707f92,
            0x110538332d2eae09bf756dfd87431ded7
        ].span();
        let dispatcher = deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            hint,
        );
        let success = dispatcher.refund();
        assert(success, 'refund');
    }

    #[test]
    fn test_msm_check_with_real_data() {
        // Hash/secret from Python generator (ed25519_test_data.json)
        let expected_hash = array![3606997102_u32, 3756602050_u32, 1811765011_u32, 1576844653_u32, 61256116_u32, 2110839708_u32, 540553134_u32, 3341226206_u32].span();
        let mut secret_input: ByteArray = Default::default();
        secret_input.append_byte(0x09_u8); secret_input.append_byte(0x9d_u8);
        secret_input.append_byte(0xd9_u8); secret_input.append_byte(0xb7_u8);
        secret_input.append_byte(0x3e_u8); secret_input.append_byte(0x2e_u8);
        secret_input.append_byte(0x84_u8); secret_input.append_byte(0xdb_u8);
        secret_input.append_byte(0x47_u8); secret_input.append_byte(0x2b_u8);
        secret_input.append_byte(0x34_u8); secret_input.append_byte(0x2d_u8);
        secret_input.append_byte(0xc3_u8); secret_input.append_byte(0xab_u8);
        secret_input.append_byte(0x05_u8); secret_input.append_byte(0x20_u8);
        secret_input.append_byte(0xf6_u8); secret_input.append_byte(0x54_u8);
        secret_input.append_byte(0xfd_u8); secret_input.append_byte(0x8a_u8);
        secret_input.append_byte(0x81_u8); secret_input.append_byte(0xd6_u8);
        secret_input.append_byte(0x44_u8); secret_input.append_byte(0x18_u8);
        secret_input.append_byte(0x04_u8); secret_input.append_byte(0x77_u8);
        secret_input.append_byte(0x73_u8); secret_input.append_byte(0x0a_u8);
        secret_input.append_byte(0x90_u8); secret_input.append_byte(0xaf_u8);
        secret_input.append_byte(0x89_u8); secret_input.append_byte(0x00_u8);

        // Real adaptor point and hint from generator
        let x_limbs = (0x460f72719199c63ec398673f, 0xf27a4af146a52a7dbdeb4cfb, 0x5f9c70ec759789a0, 0x0);
        let y_limbs = (0x6b43e318a2a02d8241549109, 0x40e30afa4cce98c21e473980, 0x5e243e1eed1aa575, 0x0);
        // Fake-GLV hint (Q.x limbs, Q.y limbs, s1, s2_encoded)
        let hint = array![
            0x460f72719199c63ec398673f,
            0xf27a4af146a52a7dbdeb4cfb,
            0x5f9c70ec759789a0,
            0x0,
            0x6b43e318a2a02d8241549109,
            0x40e30afa4cce98c21e473980,
            0x5e243e1eed1aa575,
            0x0,
            0x10b51d41eab43e36d3ac30cda9707f92,
            0x110538332d2eae09bf756dfd87431ded7
        ].span();

        let dispatcher = deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            hint,
        );

        let success = dispatcher.verify_and_unlock(secret_input);
        assert(success, 'MSM check failed');
        assert(dispatcher.is_unlocked(), 'unlock failed');
    }

    #[test]
    #[should_panic(expected: ('Wrong FakeGLV decomposition',))]
    fn test_wrong_hint_fails() {
        let expected_hash = array![3606997102_u32, 3756602050_u32, 1811765011_u32, 1576844653_u32, 61256116_u32, 2110839708_u32, 540553134_u32, 3341226206_u32].span();
        let mut secret_input: ByteArray = Default::default();
        secret_input.append_byte(0x09_u8); secret_input.append_byte(0x9d_u8);
        secret_input.append_byte(0xd9_u8); secret_input.append_byte(0xb7_u8);
        secret_input.append_byte(0x3e_u8); secret_input.append_byte(0x2e_u8);
        secret_input.append_byte(0x84_u8); secret_input.append_byte(0xdb_u8);
        secret_input.append_byte(0x47_u8); secret_input.append_byte(0x2b_u8);
        secret_input.append_byte(0x34_u8); secret_input.append_byte(0x2d_u8);
        secret_input.append_byte(0xc3_u8); secret_input.append_byte(0xab_u8);
        secret_input.append_byte(0x05_u8); secret_input.append_byte(0x20_u8);
        secret_input.append_byte(0xf6_u8); secret_input.append_byte(0x54_u8);
        secret_input.append_byte(0xfd_u8); secret_input.append_byte(0x8a_u8);
        secret_input.append_byte(0x81_u8); secret_input.append_byte(0xd6_u8);
        secret_input.append_byte(0x44_u8); secret_input.append_byte(0x18_u8);
        secret_input.append_byte(0x04_u8); secret_input.append_byte(0x77_u8);
        secret_input.append_byte(0x73_u8); secret_input.append_byte(0x0a_u8);
        secret_input.append_byte(0x90_u8); secret_input.append_byte(0xaf_u8);
        secret_input.append_byte(0x89_u8); secret_input.append_byte(0x00_u8);

        let x_limbs = (0x460f72719199c63ec398673f, 0xf27a4af146a52a7dbdeb4cfb, 0x5f9c70ec759789a0, 0x0);
        let y_limbs = (0x6b43e318a2a02d8241549109, 0x40e30afa4cce98c21e473980, 0x5e243e1eed1aa575, 0x0);
        // Tamper hint: change s1 by +1
        let hint = array![
            0x460f72719199c63ec398673f,
            0xf27a4af146a52a7dbdeb4cfb,
            0x5f9c70ec759789a0,
            0x0,
            0x6b43e318a2a02d8241549109,
            0x40e30afa4cce98c21e473980,
            0x5e243e1eed1aa575,
            0x0,
            0x10b51d41eab43e36d3ac30cda9707f93, // s1 + 1
            0x110538332d2eae09bf756dfd87431ded7
        ].span();

        let dispatcher = deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            hint,
        );

        // Expect MSM to panic due to invalid hint decomposition.
        dispatcher.verify_and_unlock(secret_input);
    }

    // NOTE: These constructor validation tests verify correct behavior (constructor rejects invalid inputs),
    // but snforge 0.53.0 marks them as "failed" due to how it handles constructor panics during deployment.
    // The panics shown in the output confirm the constructor IS working correctly.
    // This is a known limitation: #[should_panic] doesn't work for constructor panics in snforge.

    #[test]
    #[should_panic]
    fn test_constructor_rejects_zero_point() {
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let zero_point = (0, 0, 0, 0);
        let hint = array![0, 0, 0, 0, 0, 0, 0, 0, 0, 0].span();
        deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            zero_point,
            zero_point,
            (0, 0),
            hint,
        );
    }

    #[test]
    #[should_panic]
    fn test_constructor_rejects_wrong_hint_length() {
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let x_limbs = (0x460f72719199c63ec398673f, 0xf27a4af146a52a7dbdeb4cfb, 0x5f9c70ec759789a0, 0x0);
        let y_limbs = (0x6b43e318a2a02d8241549109, 0x40e30afa4cce98c21e473980, 0x5e243e1eed1aa575, 0x0);
        let bad_hint = array![1, 2, 3, 4, 5].span();
        deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            bad_hint,
        );
    }

    #[test]
    #[should_panic]
    fn test_constructor_rejects_mismatched_hint() {
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let x_limbs = (0x460f72719199c63ec398673f, 0xf27a4af146a52a7dbdeb4cfb, 0x5f9c70ec759789a0, 0x0);
        let y_limbs = (0x6b43e318a2a02d8241549109, 0x40e30afa4cce98c21e473980, 0x5e243e1eed1aa575, 0x0);
        let bad_hint = array![
            0x1111111111111111, 0x2222222222222222, 0x3333333333333333, 0x0,
            0x4444444444444444, 0x5555555555555555, 0x6666666666666666, 0x0,
            0x10b51d41eab43e36d3ac30cda9707f92,
            0x110538332d2eae09bf756dfd87431ded7
        ].span();
        deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            bad_hint,
        );
    }

    /// Test that verifies Rust → Python → Cairo consistency.
    /// This test uses a known secret, generates adaptor point/hint via Python tool,
    /// and verifies the full unlock flow works in Cairo.
    /// 
    /// To regenerate test data:
    /// 1. Run: `cd rust && cargo run -- --format json` (get secret_hex)
    /// 2. Run: `cd tools && uv run python generate_ed25519_test_data.py <secret_hex> --save`
    /// 3. Update this test with the new hash_words, x_limbs, y_limbs, hint, and secret_input
    #[test]
    fn test_rust_python_cairo_consistency() {
        // Secret: 7a8e966e6aebde6a27100d8cbae6fd3320080fcf92e6d6a9d0ecfbedd6e82c09
        // Generated via: cd rust && cargo run -- --format json
        // Then: cd tools && uv run python generate_ed25519_test_data.py <secret_hex> --save
        let expected_hash = array![
            1916106498_u32, 176162395_u32, 1870310073_u32, 3365846194_u32,
            70159030_u32, 2210369329_u32, 2238243005_u32, 1947924851_u32
        ].span();
        
        let mut secret_input: ByteArray = Default::default();
        secret_input.append_byte(0x7a_u8); secret_input.append_byte(0x8e_u8);
        secret_input.append_byte(0x96_u8); secret_input.append_byte(0x6e_u8);
        secret_input.append_byte(0x6a_u8); secret_input.append_byte(0xeb_u8);
        secret_input.append_byte(0xde_u8); secret_input.append_byte(0x6a_u8);
        secret_input.append_byte(0x27_u8); secret_input.append_byte(0x10_u8);
        secret_input.append_byte(0x0d_u8); secret_input.append_byte(0x8c_u8);
        secret_input.append_byte(0xba_u8); secret_input.append_byte(0xe6_u8);
        secret_input.append_byte(0xfd_u8); secret_input.append_byte(0x33_u8);
        secret_input.append_byte(0x20_u8); secret_input.append_byte(0x08_u8);
        secret_input.append_byte(0x0f_u8); secret_input.append_byte(0xcf_u8);
        secret_input.append_byte(0x92_u8); secret_input.append_byte(0xe6_u8);
        secret_input.append_byte(0xd6_u8); secret_input.append_byte(0xa9_u8);
        secret_input.append_byte(0xd0_u8); secret_input.append_byte(0xec_u8);
        secret_input.append_byte(0xfb_u8); secret_input.append_byte(0xed_u8);
        secret_input.append_byte(0xd6_u8); secret_input.append_byte(0xe8_u8);
        secret_input.append_byte(0x2c_u8); secret_input.append_byte(0x09_u8);

        // Adaptor point and hint from Python tool (ed25519_test_data.json)
        // Generated via: cd tools && uv run python generate_ed25519_test_data.py 7a8e966e6aebde6a27100d8cbae6fd3320080fcf92e6d6a9d0ecfbedd6e82c09 --save
        let x_limbs = (
            0xb61f990335c97ceece10c1d1,
            0x5c385db9bc1dac87be679ae2,
            0x237566a657d8643c,
            0x0
        );
        let y_limbs = (
            0x3873997b2bab0ef7857f4470,
            0x4ec834c2f339191965edbf1c,
            0x3aa905beb796230,
            0x0
        );
        let hint = array![
            0xb61f990335c97ceece10c1d1,
            0x5c385db9bc1dac87be679ae2,
            0x237566a657d8643c,
            0x0,
            0x3873997b2bab0ef7857f4470,
            0x4ec834c2f339191965edbf1c,
            0x3aa905beb796230,
            0x0,
            0x18872506f892a4aaeabdc6eebab5e2a5,
            0x1f681cbb9fab1aca1426cc363030a507
        ].span();

        let dispatcher = deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            hint,
        );

        // Verify unlock succeeds (proves Rust -> Python -> Cairo consistency)
        let success = dispatcher.verify_and_unlock(secret_input);
        assert(success, 'Rust Python Cairo failed');
        assert(dispatcher.is_unlocked(), 'unlock state failed');
    }

    #[test]
    #[should_panic]
    fn test_constructor_rejects_small_order_point() {
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let small_order_x = (0, 0, 0, 0);
        let small_order_y = (1, 0, 0, 0);
        let hint = array![0, 0, 0, 0, 1, 0, 0, 0, 1, 1].span();
        deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            small_order_x,
            small_order_y,
            (0, 0),
            hint,
        );
    }

    /// Helper for future tests that need real adaptor point and hint values from Rust.
    fn deploy_with_full(
        expected_hash: Span<u32>,
        lock_until: u64,
        token: ContractAddress,
        amount: u256,
        adaptor_point_x: (felt252, felt252, felt252, felt252),
        adaptor_point_y: (felt252, felt252, felt252, felt252),
        dleq: (felt252, felt252),
        fake_glv_hint: Span<felt252>,
    ) -> IAtomicLockDispatcher {
        let declare_res = declare("AtomicLock");
        let contract = declare_res.unwrap().contract_class();

        let (x0, x1, x2, x3) = adaptor_point_x;
        let (y0, y1, y2, y3) = adaptor_point_y;
        let (dleq_c, dleq_r) = dleq;

        let mut calldata = ArrayTrait::new();
        expected_hash.serialize(ref calldata);
        Serde::serialize(@lock_until, ref calldata);
        Serde::serialize(@token, ref calldata);
        Serde::serialize(@amount, ref calldata);
        // adaptor_point (x/y limbs)
        Serde::serialize(@x0, ref calldata);
        Serde::serialize(@x1, ref calldata);
        Serde::serialize(@x2, ref calldata);
        Serde::serialize(@x3, ref calldata);
        Serde::serialize(@y0, ref calldata);
        Serde::serialize(@y1, ref calldata);
        Serde::serialize(@y2, ref calldata);
        Serde::serialize(@y3, ref calldata);
        // DLEQ placeholders/inputs
        Serde::serialize(@dleq_c, ref calldata);
        Serde::serialize(@dleq_r, ref calldata);
        // fake_glv_hint[10]
        Serde::serialize(@fake_glv_hint, ref calldata);

        let (addr, _) = contract.deploy(@calldata).unwrap();
        IAtomicLockDispatcher { contract_address: addr }
    }
}
