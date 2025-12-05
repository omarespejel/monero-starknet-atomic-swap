/// # AtomicLock Contract - Phase 1 Complete
///
/// Starknet contract for XMR↔️Starknet swaps with Garaga MSM verification on
/// Ed25519 (Weierstrass form, curve_index=4).
///
/// Hard invariants:
/// - Constructor: adaptor point must be non-zero, on-curve, not small-order; FakeGLV
///   hint must be 10 felts [Qx4, Qy4, s1, s2] matching the adaptor point with s1/s2
///   non-zero.
/// - verify_and_unlock: mandatory MSM assert on SHA-256(secret) reduced scalar;
///   cannot be bypassed.
///
/// Future: add DLEQ verification and Edwards/Weierstrass conversion.
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
    use core::num::traits::Zero;
    use core::sha256::compute_sha256_byte_array;
    use starknet::contract_address::ContractAddress;
    use starknet::get_contract_address;
    use starknet::get_block_timestamp;
    use starknet::get_caller_address;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};
    use garaga::definitions::{deserialize_u384, G1Point, G1PointZero, get_G};
    use garaga::definitions::types::u384;
    use garaga::ec_ops::{ec_safe_add, msm_g1, G1PointTrait};

    const ED25519_ORDER: u256 = u256 {
        low: 0x14def9dea2f79cd65812631a5cf5d3ed,
        high: 0x10000000000000000000000000000000,
    };

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
        /// Ed25519 adaptor point (Weierstrass coordinates, 4-limb x/y)
        adaptor_point_x0: felt252,
        adaptor_point_x1: felt252,
        adaptor_point_x2: felt252,
        adaptor_point_x3: felt252,
        adaptor_point_y0: felt252,
        adaptor_point_y1: felt252,
        adaptor_point_y2: felt252,
        adaptor_point_y3: felt252,
        /// DLEQ proof components (placeholders until wired)
        dleq_challenge: felt252,
        dleq_response: felt252,
        /// Fake-GLV hint for single-scalar MSM on Ed25519 (Qx, Qy limbs, s1, s2_encoded)
        fake_glv_hint0: felt252,
        fake_glv_hint1: felt252,
        fake_glv_hint2: felt252,
        fake_glv_hint3: felt252,
        fake_glv_hint4: felt252,
        fake_glv_hint5: felt252,
        fake_glv_hint6: felt252,
        fake_glv_hint7: felt252,
        fake_glv_hint8: felt252,
        fake_glv_hint9: felt252,
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
        pub const ZERO_ADAPTOR_POINT: felt252 = 'Zero adaptor point rejected';
        pub const INVALID_HINT_LENGTH: felt252 = 'Hint must be 10 felts';
        pub const HINT_Q_MISMATCH: felt252 = 'Hint Q mismatch adaptor';
        pub const ZERO_HINT_SCALARS: felt252 = 'Hint s1/s2 cannot be zero';
        pub const SMALL_ORDER_POINT: felt252 = 'Small order point rejected';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        hash_words: Span<u32>,
        lock_until: u64,
        token: ContractAddress,
        amount: u256,
        adaptor_point_x0: felt252,
        adaptor_point_x1: felt252,
        adaptor_point_x2: felt252,
        adaptor_point_x3: felt252,
        adaptor_point_y0: felt252,
        adaptor_point_y1: felt252,
        adaptor_point_y2: felt252,
        adaptor_point_y3: felt252,
        dleq_challenge: felt252,
        dleq_response: felt252,
        fake_glv_hint: Span<felt252>,
    ) {
        assert(hash_words.len() == 8, Errors::INVALID_HASH_LENGTH);
        assert(fake_glv_hint.len() == 10, Errors::INVALID_HINT_LENGTH);

        // Validate adaptor point not zero.
        let x_is_zero =
            adaptor_point_x0 == 0 && adaptor_point_x1 == 0 && adaptor_point_x2 == 0 && adaptor_point_x3 == 0;
        let y_is_zero =
            adaptor_point_y0 == 0 && adaptor_point_y1 == 0 && adaptor_point_y2 == 0 && adaptor_point_y3 == 0;
        assert(!x_is_zero && !y_is_zero, Errors::ZERO_ADAPTOR_POINT);

        // Reconstruct point and validate curve/small-order.
        let point = G1Point {
            x: u384 { limb0: adaptor_point_x0, limb1: adaptor_point_x1, limb2: adaptor_point_x2, limb3: adaptor_point_x3 },
            y: u384 { limb0: adaptor_point_y0, limb1: adaptor_point_y1, limb2: adaptor_point_y2, limb3: adaptor_point_y3 },
        };
        point.assert_on_curve_excluding_infinity(4);
        assert(!is_small_order_ed25519(point), Errors::SMALL_ORDER_POINT);

        // Validate hint shape and match to adaptor point.
        let hint_q = G1Point {
            x: u384 {
                limb0: *fake_glv_hint.at(0),
                limb1: *fake_glv_hint.at(1),
                limb2: *fake_glv_hint.at(2),
                limb3: *fake_glv_hint.at(3),
            },
            y: u384 {
                limb0: *fake_glv_hint.at(4),
                limb1: *fake_glv_hint.at(5),
                limb2: *fake_glv_hint.at(6),
                limb3: *fake_glv_hint.at(7),
            },
        };
        assert(hint_q == point, Errors::HINT_Q_MISMATCH);

        let s1 = *fake_glv_hint.at(8);
        let s2 = *fake_glv_hint.at(9);
        assert(s1 != 0 && s2 != 0, Errors::ZERO_HINT_SCALARS);

        self.h0.write(*hash_words.at(0));
        self.h1.write(*hash_words.at(1));
        self.h2.write(*hash_words.at(2));
        self.h3.write(*hash_words.at(3));
        self.h4.write(*hash_words.at(4));
        self.h5.write(*hash_words.at(5));
        self.h6.write(*hash_words.at(6));
        self.h7.write(*hash_words.at(7));
        self.adaptor_point_x0.write(adaptor_point_x0);
        self.adaptor_point_x1.write(adaptor_point_x1);
        self.adaptor_point_x2.write(adaptor_point_x2);
        self.adaptor_point_x3.write(adaptor_point_x3);
        self.adaptor_point_y0.write(adaptor_point_y0);
        self.adaptor_point_y1.write(adaptor_point_y1);
        self.adaptor_point_y2.write(adaptor_point_y2);
        self.adaptor_point_y3.write(adaptor_point_y3);
        self.dleq_challenge.write(dleq_challenge);
        self.dleq_response.write(dleq_response);
        self.fake_glv_hint0.write(*fake_glv_hint.at(0));
        self.fake_glv_hint1.write(*fake_glv_hint.at(1));
        self.fake_glv_hint2.write(*fake_glv_hint.at(2));
        self.fake_glv_hint3.write(*fake_glv_hint.at(3));
        self.fake_glv_hint4.write(*fake_glv_hint.at(4));
        self.fake_glv_hint5.write(*fake_glv_hint.at(5));
        self.fake_glv_hint6.write(*fake_glv_hint.at(6));
        self.fake_glv_hint7.write(*fake_glv_hint.at(7));
        self.fake_glv_hint8.write(*fake_glv_hint.at(8));
        self.fake_glv_hint9.write(*fake_glv_hint.at(9));
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

            // Reconstruct adaptor point and MSM hint from storage.
            let adaptor_point = storage_adaptor_point(@self);
            let fake_glv_hint: Array<felt252> = array![
                self.fake_glv_hint0.read(),
                self.fake_glv_hint1.read(),
                self.fake_glv_hint2.read(),
                self.fake_glv_hint3.read(),
                self.fake_glv_hint4.read(),
                self.fake_glv_hint5.read(),
                self.fake_glv_hint6.read(),
                self.fake_glv_hint7.read(),
                self.fake_glv_hint8.read(),
                self.fake_glv_hint9.read(),
            ];

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

            // Mandatory MSM check: t·G must equal stored adaptor point.
            let mut scalar = hash_to_scalar_u256(h0, h1, h2, h3, h4, h5, h6, h7);
            scalar = reduce_scalar_ed25519(scalar);
            let computed = msm_g1(array![get_G(4)].span(), array![scalar].span(), 4, fake_glv_hint.span());
            assert(computed == adaptor_point, 'MSM verification failed');

            // TODO: DLEQ verification (placeholder for now)
            // let dleq_ok = verify_dleq_stub();
            // if !dleq_ok { return false; }

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

    /// Derive a scalar from SHA-256 words (little endian over 4 limbs).
    fn hash_to_scalar_u256(h0: u32, h1: u32, h2: u32, h3: u32, h4: u32, h5: u32, h6: u32, h7: u32) -> u256 {
        let base: u256 = u256 { low: 0x1_0000_0000, high: 0 };
        let low = u256 { low: h0.into(), high: 0 }
            + base * u256 { low: h1.into(), high: 0 }
            + base * base * u256 { low: h2.into(), high: 0 }
            + base * base * base * u256 { low: h3.into(), high: 0 };
        let high = u256 { low: h4.into(), high: 0 }
            + base * u256 { low: h5.into(), high: 0 }
            + base * base * u256 { low: h6.into(), high: 0 }
            + base * base * base * u256 { low: h7.into(), high: 0 };
        u256 { low: low.low, high: high.low }
    }

    fn reduce_scalar_ed25519(scalar: u256) -> u256 {
        scalar % ED25519_ORDER
    }

    fn storage_adaptor_point(self: @ContractState) -> G1Point {
        let mut xs = array![
            self.adaptor_point_x0.read(),
            self.adaptor_point_x1.read(),
            self.adaptor_point_x2.read(),
            self.adaptor_point_x3.read()
        ];
        let mut xs_span = xs.span();
        let x = deserialize_u384(ref xs_span);

        let mut ys = array![
            self.adaptor_point_y0.read(),
            self.adaptor_point_y1.read(),
            self.adaptor_point_y2.read(),
            self.adaptor_point_y3.read()
        ];
        let mut ys_span = ys.span();
        let y = deserialize_u384(ref ys_span);
        G1Point { x, y }
    }

    fn is_zero_point(p: @G1Point) -> bool {
        *p == G1PointZero::zero()
    }

    fn is_zero_hint(hint: Span<felt252>) -> bool {
        let len = hint.len();
        let mut all_zero = true;
        let mut i = 0;
        while i < len {
            if *hint.at(i) != 0 {
                all_zero = false;
            }
            i += 1;
        };
        all_zero
    }

    fn is_small_order_ed25519(p: G1Point) -> bool {
        // Checks if [8]P = O by three doublings using safe addition.
        let curve_idx = 4;
        let p2 = ec_safe_add(p, p, curve_idx);
        if p2.is_zero() {
            return true;
        }
        let p4 = ec_safe_add(p2, p2, curve_idx);
        if p4.is_zero() {
            return true;
        }
        let p8 = ec_safe_add(p4, p4, curve_idx);
        p8.is_zero()
    }
}
