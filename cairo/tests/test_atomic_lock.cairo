#[cfg(test)]
mod tests {
    use atomic_lock::{IAtomicLockDispatcher, IAtomicLockDispatcherTrait};
    use core::array::ArrayTrait;
    use core::byte_array::{ByteArray, ByteArrayTrait};
    use core::integer::u256;
    use core::result::ResultTrait;
    use core::serde::Serde;
    use core::sha256::compute_sha256_byte_array;
    use starknet::contract_address::ContractAddress;
    use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};

    #[test]
    fn test_cryptographic_handshake() {
        let secret_input: ByteArray = "test_secret";
        let hash_words = compute_sha256_byte_array(@secret_input);
        let [h0, h1, h2, h3, h4, h5, h6, h7] = hash_words;
        let expected_hash = array![h0, h1, h2, h3, h4, h5, h6, h7].span();

        let dispatcher = deploy_with(expected_hash, 0_u64, 0.try_into().unwrap(), u256 { low: 0, high: 0 });

        // Call verify_and_unlock with the exact secret from Rust.
        let success = dispatcher.verify_and_unlock(secret_input);

        assert(success, 'unlock fail');
        assert(dispatcher.is_unlocked(), 'state');
    }

    #[test]
    fn test_wrong_secret_fails() {
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let dispatcher = deploy_with(expected_hash, 0_u64, 0.try_into().unwrap(), u256 { low: 0, high: 0 });

        let wrong_secret = "wrong_secret";
        let success = dispatcher.verify_and_unlock(wrong_secret);
        assert(!success, 'wrong secret');
        assert(!dispatcher.is_unlocked(), 'stay locked');
    }

    #[test]
    #[should_panic]
    fn test_cannot_unlock_twice() {
        let secret_input: ByteArray = "unlock_me";
        let hash_words = compute_sha256_byte_array(@secret_input);
        let [h0, h1, h2, h3, h4, h5, h6, h7] = hash_words;
        let expected_hash = array![h0, h1, h2, h3, h4, h5, h6, h7].span();
        let dispatcher = deploy_with(expected_hash, 0_u64, 0.try_into().unwrap(), u256 { low: 0, high: 0 });

        assert(dispatcher.verify_and_unlock(secret_input), 'first ok');
        // Second attempt should panic.
        dispatcher.verify_and_unlock("unlock_me");
    }

    #[test]
    fn test_rust_generated_secret() {
        // Values from: cd rust && cargo run -- --format json
        let expected_hash = array![
            3566193431_u32,
            2923666528_u32,
            179944073_u32,
            541302880_u32,
            2559354097_u32,
            2501894999_u32,
            3870367010_u32,
            4173040258_u32
        ].span();
        let mut secret_input: ByteArray = Default::default();
        secret_input.append_byte(0x99_u8);
        secret_input.append_byte(0xdd_u8);
        secret_input.append_byte(0x9b_u8);
        secret_input.append_byte(0x73_u8);
        secret_input.append_byte(0xe2_u8);
        secret_input.append_byte(0xe8_u8);
        secret_input.append_byte(0x4d_u8);
        secret_input.append_byte(0xb4_u8);
        secret_input.append_byte(0x72_u8);
        secret_input.append_byte(0xb3_u8);
        secret_input.append_byte(0x42_u8);
        secret_input.append_byte(0xdc_u8);
        secret_input.append_byte(0x3a_u8);
        secret_input.append_byte(0xb0_u8);
        secret_input.append_byte(0x52_u8);
        secret_input.append_byte(0x0f_u8);
        secret_input.append_byte(0x65_u8);
        secret_input.append_byte(0x4f_u8);
        secret_input.append_byte(0xd8_u8);
        secret_input.append_byte(0xa8_u8);
        secret_input.append_byte(0x1d_u8);
        secret_input.append_byte(0x64_u8);
        secret_input.append_byte(0x41_u8);
        secret_input.append_byte(0x80_u8);
        secret_input.append_byte(0x47_u8);
        secret_input.append_byte(0x77_u8);
        secret_input.append_byte(0xb3_u8);
        secret_input.append_byte(0x0a_u8);
        secret_input.append_byte(0x90_u8);
        secret_input.append_byte(0xaf_u8);
        secret_input.append_byte(0x89_u8);
        secret_input.append_byte(0x00_u8);

        let dispatcher = deploy_with(expected_hash, 0_u64, 0.try_into().unwrap(), u256 { low: 0, high: 0 });

        // Verify
        let success = dispatcher.verify_and_unlock(secret_input);
        assert(success, 'hash mismatch');
    }

    #[test]
    fn test_refund_after_expiry() {
        // lock_until = 0 to allow immediate refund without time travel
        let expected_hash = array![1_u32, 2_u32, 3_u32, 4_u32, 5_u32, 6_u32, 7_u32, 8_u32].span();
        let dispatcher = deploy_with(expected_hash, 0_u64, 0.try_into().unwrap(), u256 { low: 0, high: 0 });
        let success = dispatcher.refund();
        assert(success, 'refund');
    }

    fn deploy_with(
        expected_hash: Span<u32>,
        lock_until: u64,
        token: ContractAddress,
        amount: u256,
    ) -> IAtomicLockDispatcher {
        let declare_res = declare("AtomicLock");
        let contract = declare_res.unwrap().contract_class();

        let mut calldata = ArrayTrait::new();
        expected_hash.serialize(ref calldata);
        Serde::serialize(@lock_until, ref calldata);
        Serde::serialize(@token, ref calldata);
        Serde::serialize(@amount, ref calldata);

        let deploy_res = contract.deploy(@calldata);
        let (addr, _) = deploy_res.unwrap();
        IAtomicLockDispatcher { contract_address: addr }
    }
}

