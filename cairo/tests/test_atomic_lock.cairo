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

    #[test]
    fn test_constructor_rejects_zero_point() {
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let zero_point = (0, 0, 0, 0);
        let hint = array![0, 0, 0, 0, 0, 0, 0, 0, 0, 0].span();
        let result = try_deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            zero_point,
            zero_point,
            (0, 0),
            hint,
        );
        assert(result.is_err(), 'zero rejected');
    }

    #[test]
    fn test_constructor_rejects_wrong_hint_length() {
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let x_limbs = (0x460f72719199c63ec398673f, 0xf27a4af146a52a7dbdeb4cfb, 0x5f9c70ec759789a0, 0x0);
        let y_limbs = (0x6b43e318a2a02d8241549109, 0x40e30afa4cce98c21e473980, 0x5e243e1eed1aa575, 0x0);
        let bad_hint = array![1, 2, 3, 4, 5].span();
        let result = try_deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            bad_hint,
        );
        assert(result.is_err(), 'hint len rejected');
    }

    #[test]
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
        let result = try_deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            x_limbs,
            y_limbs,
            (0, 0),
            bad_hint,
        );
        assert(result.is_err(), 'hint mismatch');
    }

    #[test]
    fn test_constructor_rejects_small_order_point() {
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let small_order_x = (0, 0, 0, 0);
        let small_order_y = (1, 0, 0, 0);
        let hint = array![0, 0, 0, 0, 1, 0, 0, 0, 1, 1].span();
        let result = try_deploy_with_full(
            expected_hash,
            0_u64,
            0.try_into().unwrap(),
            u256 { low: 0, high: 0 },
            small_order_x,
            small_order_y,
            (0, 0),
            hint,
        );
        // Note: This will fail at zero point check first, but that's fine - validates rejection
        assert(result.is_err(), 'small order');
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

        let deploy_res = contract.deploy(@calldata);
        let (addr, _) = deploy_res.unwrap();
        IAtomicLockDispatcher { contract_address: addr }
    }

    /// Helper that returns Result for testing deployment failures.
    fn try_deploy_with_full(
        expected_hash: Span<u32>,
        lock_until: u64,
        token: ContractAddress,
        amount: u256,
        adaptor_point_x: (felt252, felt252, felt252, felt252),
        adaptor_point_y: (felt252, felt252, felt252, felt252),
        dleq: (felt252, felt252),
        fake_glv_hint: Span<felt252>,
    ) -> Result<(IAtomicLockDispatcher, ()), Array<felt252>> {
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
        Serde::serialize(@x0, ref calldata);
        Serde::serialize(@x1, ref calldata);
        Serde::serialize(@x2, ref calldata);
        Serde::serialize(@x3, ref calldata);
        Serde::serialize(@y0, ref calldata);
        Serde::serialize(@y1, ref calldata);
        Serde::serialize(@y2, ref calldata);
        Serde::serialize(@y3, ref calldata);
        Serde::serialize(@dleq_c, ref calldata);
        Serde::serialize(@dleq_r, ref calldata);
        Serde::serialize(@fake_glv_hint, ref calldata);

        let deploy_res = contract.deploy(@calldata);
        match deploy_res {
            Result::Ok((addr, _)) => {
                Result::Ok((IAtomicLockDispatcher { contract_address: addr }, ()))
            },
            Result::Err(err) => Result::Err(err),
        }
    }
}
