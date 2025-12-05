/// Atomic Lock Contract for XMR-Starknet Swaps
///
/// Stores a SHA-256 hash and unlocks when the correct preimage is provided.
/// Supports a timelock-based refund and optional ERC20 token payout.
#[starknet::interface]
pub trait IAtomicLock<TContractState> {
    /// Verify the secret and unlock the contract (one-time only).
    fn verify_and_unlock(ref self: TContractState, secret: ByteArray) -> bool;
    /// Get the stored target hash as 8 u32 words.
    fn get_target_hash(self: @TContractState) -> Span<u32>;
    /// Check if the contract has been unlocked.
    fn is_unlocked(self: @TContractState) -> bool;
    /// Get the timelock expiry (block timestamp).
    fn get_lock_until(self: @TContractState) -> u64;
    /// Refund to the depositor after expiry if not unlocked.
    fn refund(ref self: TContractState) -> bool;
    /// Optional: pull tokens from depositor (requires prior approval).
    fn deposit(ref self: TContractState) -> bool;
}

#[starknet::interface]
pub trait IERC20<TContractState> {
    fn transfer(ref self: TContractState, recipient: starknet::ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState,
        sender: starknet::ContractAddress,
        recipient: starknet::ContractAddress,
        amount: u256,
    ) -> bool;
}

#[starknet::contract]
pub mod AtomicLock {
    use core::array::ArrayTrait;
    use core::byte_array::ByteArray;
    use core::integer::u256;
    use core::sha256::compute_sha256_byte_array;
    use starknet::contract_address::ContractAddress;
    use starknet::get_contract_address;
    use starknet::get_block_timestamp;
    use starknet::get_caller_address;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};

    /// Emitted when the lock is successfully unlocked.
    #[derive(Drop, starknet::Event)]
    pub struct Unlocked {
        #[key]
        pub unlocker: starknet::ContractAddress,
        pub secret_hash: u32,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Refunded {
        #[key]
        pub depositor: starknet::ContractAddress,
        pub amount: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Unlocked: Unlocked,
        Refunded: Refunded,
    }

    #[storage]
    struct Storage {
        /// SHA-256 hash as 8 × u32 (big-endian words).
        h0: u32,
        h1: u32,
        h2: u32,
        h3: u32,
        h4: u32,
        h5: u32,
        h6: u32,
        h7: u32,
        /// Whether the lock has been opened.
        unlocked: bool,
        /// Timelock expiry (block timestamp).
        lock_until: u64,
        /// Depositor address.
        depositor: ContractAddress,
        /// ERC20 token to release (optional).
        token: ContractAddress,
        /// Amount to release (optional; 0 means no token transfer).
        amount: u256,
    }

    pub mod Errors {
        pub const INVALID_HASH_LENGTH: felt252 = 'Hash must be 8 u32 words';
        pub const ALREADY_UNLOCKED: felt252 = 'Already unlocked';
        pub const NOT_EXPIRED: felt252 = 'Lock not expired';
        pub const NOT_DEPOSITOR: felt252 = 'Not depositor';
        pub const TOKEN_TRANSFER_FAILED: felt252 = 'Token transfer failed';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        hash_words: Span<u32>,
        lock_until: u64,
        token: ContractAddress,
        amount: u256,
    ) {
        assert(hash_words.len() == 8, Errors::INVALID_HASH_LENGTH);

        self.h0.write(*hash_words.at(0));
        self.h1.write(*hash_words.at(1));
        self.h2.write(*hash_words.at(2));
        self.h3.write(*hash_words.at(3));
        self.h4.write(*hash_words.at(4));
        self.h5.write(*hash_words.at(5));
        self.h6.write(*hash_words.at(6));
        self.h7.write(*hash_words.at(7));
        self.unlocked.write(false);
        self.lock_until.write(lock_until);
        self.depositor.write(get_caller_address());
        self.token.write(token);
        self.amount.write(amount);
    }

    fn is_zero(amount: u256) -> bool {
        amount.low == 0 && amount.high == 0
    }

    fn maybe_transfer(token: ContractAddress, recipient: ContractAddress, amount: u256) -> bool {
        if is_zero(amount) {
            return true;
        }
        let dispatcher = IERC20Dispatcher { contract_address: token };
        dispatcher.transfer(recipient, amount)
    }

    fn pull_from_depositor(token: ContractAddress, depositor: ContractAddress, amount: u256) -> bool {
        if is_zero(amount) {
            return true;
        }
        let dispatcher = IERC20Dispatcher { contract_address: token };
        dispatcher.transfer_from(depositor, get_contract_address(), amount)
    }

    #[abi(embed_v0)]
    impl AtomicLockImpl of super::IAtomicLock<ContractState> {
        fn get_target_hash(self: @ContractState) -> Span<u32> {
            let mut arr: Array<u32> = ArrayTrait::new();
            arr.append(self.h0.read());
            arr.append(self.h1.read());
            arr.append(self.h2.read());
            arr.append(self.h3.read());
            arr.append(self.h4.read());
            arr.append(self.h5.read());
            arr.append(self.h6.read());
            arr.append(self.h7.read());
            arr.span()
        }

        fn is_unlocked(self: @ContractState) -> bool {
            self.unlocked.read()
        }

        fn get_lock_until(self: @ContractState) -> u64 {
            self.lock_until.read()
        }

        fn verify_and_unlock(ref self: ContractState, secret: ByteArray) -> bool {
            // Prevent re-unlocking.
            assert(!self.unlocked.read(), Errors::ALREADY_UNLOCKED);

            // Compute SHA-256 of provided secret.
            let computed_hash = compute_sha256_byte_array(@secret);
            let [h0, h1, h2, h3, h4, h5, h6, h7] = computed_hash;

            // Compare against stored hash.
            if h0 != self.h0.read() { return false; }
            if h1 != self.h1.read() { return false; }
            if h2 != self.h2.read() { return false; }
            if h3 != self.h3.read() { return false; }
            if h4 != self.h4.read() { return false; }
            if h5 != self.h5.read() { return false; }
            if h6 != self.h6.read() { return false; }
            if h7 != self.h7.read() { return false; }

            // Transfer tokens to caller if configured.
            let amount = self.amount.read();
            let token = self.token.read();
            let caller = get_caller_address();
            let ok = maybe_transfer(token, caller, amount);
            assert(ok, Errors::TOKEN_TRANSFER_FAILED);

            self.unlocked.write(true);
            self.emit(Unlocked { unlocker: caller, secret_hash: h0 });
            true
        }

        fn refund(ref self: ContractState) -> bool {
            assert(!self.unlocked.read(), Errors::ALREADY_UNLOCKED);
            let now = get_block_timestamp();
            assert(now >= self.lock_until.read(), Errors::NOT_EXPIRED);
            let caller = get_caller_address();
            assert(caller == self.depositor.read(), Errors::NOT_DEPOSITOR);

            let amount = self.amount.read();
            let token = self.token.read();
            let ok = maybe_transfer(token, caller, amount);
            assert(ok, Errors::TOKEN_TRANSFER_FAILED);

            self.unlocked.write(true);
            self.emit(Refunded { depositor: caller, amount });
            true
        }

        fn deposit(ref self: ContractState) -> bool {
            let caller = get_caller_address();
            assert(caller == self.depositor.read(), Errors::NOT_DEPOSITOR);

            let amount = self.amount.read();
            let token = self.token.read();
            let ok = pull_from_depositor(token, caller, amount);
            assert(ok, Errors::TOKEN_TRANSFER_FAILED);
            true
        }
    }
}
