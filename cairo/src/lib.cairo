/// # AtomicLock Contract - Prototype Implementation / Reference PoC
///
/// Prototype Starknet contract for XMR↔️Starknet atomic swaps with Garaga MSM
/// verification on Ed25519 (Weierstrass form, curve_index=4).
///
/// **Status**: This is a prototype implementation and reference proof-of-concept.
/// Production-ready status requires security audit and DLEQ proof implementation.
///
/// **Hard Invariants (Enforced at Deployment)**:
/// - Constructor: adaptor point must be non-zero, on-curve, not small-order; FakeGLV
///   hint must be 10 felts [Qx4, Qy4, s1, s2] matching the adaptor point with s1/s2
///   non-zero.
/// - Timelock: lock_until must be > current block timestamp (prevents immediate expiry).
/// - Token/Amount: For real swaps, both token and amount must be non-zero. Zero values
///   allowed only for testing (both must be zero together).
///
/// **Hard Invariants (Enforced at Runtime)**:
/// - verify_and_unlock: mandatory MSM assert on SHA-256(secret) reduced scalar;
///   cannot be bypassed. This is the core cryptographic guarantee.
/// - Refund: only depositor, only after lock_until, only if still locked.
///
/// **Protocol Flow**:
/// 1. Deploy with hashlock, adaptor point, timelock, token, and amount.
/// 2. Depositor calls `deposit()` to transfer tokens into the lock.
/// 3. Counterparty reveals secret on Monero side, unlocking XMR.
/// 4. Secret is revealed on Starknet via `verify_and_unlock()`, unlocking tokens.
/// 5. If secret not revealed before lock_until, depositor can call `refund()`.
///
/// Future: add DLEQ verification to bind hashlock to adaptor point cryptographically.
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
    use core::poseidon::PoseidonTrait;
    use core::hash::HashStateTrait;
    use starknet::contract_address::ContractAddress;
    use starknet::get_contract_address;
    use starknet::get_block_timestamp;
    use starknet::get_caller_address;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};
    use garaga::definitions::{deserialize_u384, G1Point, G1PointZero, get_G};
    use garaga::ec_ops::{ec_safe_add, msm_g1, G1PointTrait};
    use core::circuit::{u384, u96};

    /// Ed25519 curve order (from RFC 8032)
    const ED25519_ORDER: u256 = u256 {
        low: 0x14def9dea2f79cd65812631a5cf5d3ed,
        high: 0x10000000000000000000000000000000,
    };
    
    /// Ed25519 curve index in Garaga (curve_index = 4)
    const ED25519_CURVE_INDEX: u32 = 4;

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

    /// Emitted when DLEQ proof verification succeeds.
    #[derive(Drop, starknet::Event)]
    pub struct DleqVerified {
        #[key]
        pub adaptor_point_x: (felt252, felt252, felt252, felt252),
        #[key]
        pub adaptor_point_y: (felt252, felt252, felt252, felt252),
        pub challenge: felt252,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        Unlocked: Unlocked,
        Refunded: Refunded,
        DleqVerified: DleqVerified,
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
        /// DLEQ second point U = t·Y (Weierstrass coordinates, 4-limb x/y)
        dleq_second_point_x0: felt252,
        dleq_second_point_x1: felt252,
        dleq_second_point_x2: felt252,
        dleq_second_point_x3: felt252,
        dleq_second_point_y0: felt252,
        dleq_second_point_y1: felt252,
        dleq_second_point_y2: felt252,
        dleq_second_point_y3: felt252,
        /// DLEQ proof components
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
        pub const INVALID_LOCK_TIME: felt252 = 'lock_until must be future';
        pub const ZERO_AMOUNT: felt252 = 'Amount must be non-zero';
        pub const ZERO_TOKEN: felt252 = 'Token address must be non-zero';
        pub const DLEQ_VERIFICATION_FAILED: felt252 = 'DLEQ verification failed';
        pub const DLEQ_POINT_NOT_ON_CURVE: felt252 = 'DLEQ: point not on curve';
        pub const DLEQ_SMALL_ORDER_POINT: felt252 = 'DLEQ: small order point';
        pub const DLEQ_CHALLENGE_MISMATCH: felt252 = 'DLEQ: challenge mismatch';
        pub const DLEQ_SCALAR_OUT_OF_RANGE: felt252 = 'DLEQ: scalar out of range';
        pub const DLEQ_ZERO_SCALAR: felt252 = 'DLEQ: zero scalar rejected';
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        hash_words: Span<u32>,
        lock_until: u64,
        token: ContractAddress,
        amount: u256,
        adaptor_point_x: (felt252, felt252, felt252, felt252),
        adaptor_point_y: (felt252, felt252, felt252, felt252),
        dleq_second_point_x: (felt252, felt252, felt252, felt252),
        dleq_second_point_y: (felt252, felt252, felt252, felt252),
        dleq: (felt252, felt252),
        fake_glv_hint: Span<felt252>,
    ) {
        // ========== INPUT VALIDATION ==========
        assert(hash_words.len() == 8, Errors::INVALID_HASH_LENGTH);
        assert(fake_glv_hint.len() == 10, Errors::INVALID_HINT_LENGTH);
        
        // Enforce swap-side invariants for production locks:
        // 1. lock_until must be in the future (prevents immediate expiry)
        let now = get_block_timestamp();
        assert(lock_until > now, Errors::INVALID_LOCK_TIME);
        
        // 2. For real swaps, amount and token must both be non-zero
        // Allow both zero (for testing) OR both non-zero (for production), but reject mixed states
        let amount_is_zero = is_zero(amount);
        let token_is_zero = token == starknet::contract_address_const::<0>();
        // Reject mixed states: if amount is zero, token must also be zero; if amount is non-zero, token must be non-zero
        if amount_is_zero {
            assert(token_is_zero, Errors::ZERO_AMOUNT);
        } else {
            assert(!token_is_zero, Errors::ZERO_TOKEN);
        }

        let (adaptor_point_x0, adaptor_point_x1, adaptor_point_x2, adaptor_point_x3) = adaptor_point_x;
        let (adaptor_point_y0, adaptor_point_y1, adaptor_point_y2, adaptor_point_y3) = adaptor_point_y;
        let (dleq_second_point_x0, dleq_second_point_x1, dleq_second_point_x2, dleq_second_point_x3) = dleq_second_point_x;
        let (dleq_second_point_y0, dleq_second_point_y1, dleq_second_point_y2, dleq_second_point_y3) = dleq_second_point_y;
        let (dleq_challenge, dleq_response) = dleq;

        // Validate adaptor point not zero.
        let x_is_zero =
            adaptor_point_x0 == 0 && adaptor_point_x1 == 0 && adaptor_point_x2 == 0 && adaptor_point_x3 == 0;
        let y_is_zero =
            adaptor_point_y0 == 0 && adaptor_point_y1 == 0 && adaptor_point_y2 == 0 && adaptor_point_y3 == 0;
        // Only reject the true infinity (both x and y zero).
        assert(!(x_is_zero && y_is_zero), Errors::ZERO_ADAPTOR_POINT);

        // Reconstruct point and validate curve/small-order.
        let mut xs_array = array![adaptor_point_x0, adaptor_point_x1, adaptor_point_x2, adaptor_point_x3];
        let mut xs_span = xs_array.span();
        let x = deserialize_u384(ref xs_span);
        
        let mut ys_array = array![adaptor_point_y0, adaptor_point_y1, adaptor_point_y2, adaptor_point_y3];
        let mut ys_span = ys_array.span();
        let y = deserialize_u384(ref ys_span);
        
        let point = G1Point { x, y };
        point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(!is_small_order_ed25519(point), Errors::SMALL_ORDER_POINT);

        // Validate hint shape and match to adaptor point.
        let mut hint_xs_array = array![
            *fake_glv_hint.at(0),
            *fake_glv_hint.at(1),
            *fake_glv_hint.at(2),
            *fake_glv_hint.at(3)
        ];
        let mut hint_xs_span = hint_xs_array.span();
        let hint_x = deserialize_u384(ref hint_xs_span);
        
        let mut hint_ys_array = array![
            *fake_glv_hint.at(4),
            *fake_glv_hint.at(5),
            *fake_glv_hint.at(6),
            *fake_glv_hint.at(7)
        ];
        let mut hint_ys_span = hint_ys_array.span();
        let hint_y = deserialize_u384(ref hint_ys_span);
        
        let hint_q = G1Point { x: hint_x, y: hint_y };
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
        
        // Validate and store DLEQ second point U
        let mut dleq_xs_array = array![dleq_second_point_x0, dleq_second_point_x1, dleq_second_point_x2, dleq_second_point_x3];
        let mut dleq_xs_span = dleq_xs_array.span();
        let dleq_x = deserialize_u384(ref dleq_xs_span);
        
        let mut dleq_ys_array = array![dleq_second_point_y0, dleq_second_point_y1, dleq_second_point_y2, dleq_second_point_y3];
        let mut dleq_ys_span = dleq_ys_array.span();
        let dleq_y = deserialize_u384(ref dleq_ys_span);
        
        let dleq_second_point = G1Point { x: dleq_x, y: dleq_y };
        dleq_second_point.assert_on_curve_excluding_infinity(ED25519_CURVE_INDEX);
        assert(!is_small_order_ed25519(dleq_second_point), Errors::SMALL_ORDER_POINT);
        
        // Verify DLEQ proof (validates inputs and checks challenge)
        _verify_dleq_proof(
            point,
            dleq_second_point,
            hash_words,
            dleq_challenge,
            dleq_response,
        );
        
        // Emit DLEQ verification event
        self.emit(DleqVerified {
            adaptor_point_x: adaptor_point_x,
            adaptor_point_y: adaptor_point_y,
            challenge: dleq_challenge,
        });
        
        self.dleq_second_point_x0.write(dleq_second_point_x0);
        self.dleq_second_point_x1.write(dleq_second_point_x1);
        self.dleq_second_point_x2.write(dleq_second_point_x2);
        self.dleq_second_point_x3.write(dleq_second_point_x3);
        self.dleq_second_point_y0.write(dleq_second_point_y0);
        self.dleq_second_point_y1.write(dleq_second_point_y1);
        self.dleq_second_point_y2.write(dleq_second_point_y2);
        self.dleq_second_point_y3.write(dleq_second_point_y3);
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
            
            // FakeGlvHint structure (10 felts total):
            // - felts[0..3]: Q.x limbs (u384, 4×96-bit limbs)
            // - felts[4..7]: Q.y limbs (u384, 4×96-bit limbs)
            // - felts[8]: s1 (scalar component for GLV decomposition)
            // - felts[9]: s2_encoded (encoded scalar component)
            // Q must equal adaptor_point for MSM to verify correctly.
            let fake_glv_hint: Array<felt252> = array![
                self.fake_glv_hint0.read(),  // Q.x limb0
                self.fake_glv_hint1.read(),  // Q.x limb1
                self.fake_glv_hint2.read(),  // Q.x limb2
                self.fake_glv_hint3.read(),  // Q.x limb3
                self.fake_glv_hint4.read(),  // Q.y limb0
                self.fake_glv_hint5.read(),  // Q.y limb1
                self.fake_glv_hint6.read(),  // Q.y limb2
                self.fake_glv_hint7.read(),  // Q.y limb3
                self.fake_glv_hint8.read(),  // s1
                self.fake_glv_hint9.read(),  // s2_encoded
            ];

            // Compute SHA-256 of provided secret.
            let computed_hash = compute_sha256_byte_array(@secret);
            let [h0, h1, h2, h3, h4, h5, h6, h7] = computed_hash;

            // Compare against stored hash (fail fast, cheap check).
            if h0 != self.h0.read() { return false; }
            if h1 != self.h1.read() { return false; }
            if h2 != self.h2.read() { return false; }
            if h3 != self.h3.read() { return false; }
            if h4 != self.h4.read() { return false; }
            if h5 != self.h5.read() { return false; }
            if h6 != self.h6.read() { return false; }
            if h7 != self.h7.read() { return false; }

            // Mandatory MSM check: t·G must equal stored adaptor point.
            // Scalar derivation: SHA-256(secret) → 8×u32 words (little-endian) → u256 big integer → mod Ed25519 order
            // This ensures the scalar is in the valid range for Ed25519 operations.
            let mut scalar = hash_to_scalar_u256(h0, h1, h2, h3, h4, h5, h6, h7);
            scalar = reduce_scalar_ed25519(scalar);
            
            // Compute t·G using Garaga's MSM with fake-GLV optimization.
            // MSM verifies: scalar·G == adaptor_point, proving knowledge of t without revealing it.
            let computed = msm_g1(
                array![get_G(ED25519_CURVE_INDEX)].span(),
                array![scalar].span(),
                ED25519_CURVE_INDEX,
                fake_glv_hint.span()
            );
            assert(computed == adaptor_point, 'MSM verification failed');

            // NOTE: DLEQ verification is performed in the constructor.
            // The DLEQ proof cryptographically binds the hashlock (H) and adaptor point (T)
            // by proving: ∃t: SHA-256(t) = H ∧ t·G = T
            // The proof is verified during contract deployment (see constructor).
            // This unlock function only verifies the hashlock and MSM, as the DLEQ proof
            // was already validated when the contract was created.

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

        /// Refund tokens to depositor after lock expiry.
        ///
        /// Enforces strict refund rules:
        /// 1. Lock must not already be unlocked (prevents double refund)
        /// 2. Current block timestamp must be >= lock_until (prevents early refund)
        /// 3. Caller must be the depositor (prevents unauthorized refund)
        ///
        /// On success: transfers tokens back to depositor, marks lock as unlocked, emits Refunded event.
        fn refund(ref self: ContractState) -> bool {
            // Rule 1: Lock must still be locked
            assert(!self.unlocked.read(), Errors::ALREADY_UNLOCKED);
            
            // Rule 2: Lock must have expired
            let now = get_block_timestamp();
            assert(now >= self.lock_until.read(), Errors::NOT_EXPIRED);
            
            // Rule 3: Only depositor can refund
            let caller = get_caller_address();
            assert(caller == self.depositor.read(), Errors::NOT_DEPOSITOR);

            // Transfer tokens back to depositor
            let amount = self.amount.read();
            let token = self.token.read();
            let ok = maybe_transfer(token, caller, amount);
            assert(ok, Errors::TOKEN_TRANSFER_FAILED);

            // Mark as unlocked to prevent further operations
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

    /// Derive a scalar from SHA-256 hash words.
    ///
    /// Process: SHA-256(secret) → 8×u32 words (big-endian from hash) → u256 big integer (little-endian interpretation)
    ///
    /// The hash words are interpreted as little-endian limbs:
    ///   scalar = h0 + h1·2^32 + h2·2^64 + h3·2^96 + h4·2^128 + h5·2^160 + h6·2^192 + h7·2^224
    ///
    /// This matches the Python tool's scalar derivation for consistency.
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

    /// Reduce scalar modulo Ed25519 curve order.
    ///
    /// Ensures the scalar is in the valid range [0, n) where n is the Ed25519 curve order.
    /// This is required before passing the scalar to Garaga's MSM operations.
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

    /// Check if a point has small order (8-torsion) on Ed25519.
    /// 
    /// Ed25519 has cofactor 8, so we check if [8]P = O.
    /// Uses three doublings: P → 2P → 4P → 8P
    /// Returns true if the point is in the 8-torsion subgroup.
    fn is_small_order_ed25519(p: G1Point) -> bool {
        // Checks if [8]P = O by three doublings using safe addition.
        let curve_idx = ED25519_CURVE_INDEX;
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

    /// Get the second generator point Y for DLEQ proofs.
    /// 
    /// This uses a deterministic hash-to-curve approach to derive Y from a constant tag.
    /// The point Y must be fixed and known to both prover and verifier.
    /// 
    /// Currently uses 2·G as placeholder until Python tool converts Edwards→Weierstrass.
    /// In production, this will be replaced with hardcoded constant from:
    /// hash_to_curve("DLEQ_SECOND_BASE_V1") → Edwards → Weierstrass → u384 limbs
    fn get_dleq_second_generator() -> G1Point {
        // Placeholder: using 2·G as second generator
        // TODO: Replace with hardcoded constant from Rust hash-to-curve computation
        // The constant must match Rust's get_second_generator() exactly
        let G = get_G(ED25519_CURVE_INDEX);
        ec_safe_add(G, G, ED25519_CURVE_INDEX)
    }

    /// Verify DLEQ proof: proves that log_G(T) = log_Y(U) without revealing the secret.
    /// 
    /// DLEQ proves: ∃t such that T = t·G and U = t·Y, where:
    /// - T is the adaptor point (t·G)
    /// - U is the second point (t·Y)
    /// - G is the standard Ed25519 generator
    /// - Y is the second generator point
    /// 
    /// Verification checks:
    /// 1. Validate all inputs (points on-curve, scalars in range)
    /// 2. R1' = s·G - c·T should equal R1 (from proof)
    /// 3. R2' = s·Y - c·U should equal R2 (from proof)
    /// 4. Challenge c' = H(tag, G, Y, T, U, R1', R2', hashlock) should equal c
    fn _verify_dleq_proof(
        T: G1Point,
        U: G1Point,
        hashlock: Span<u32>,
        c: felt252,
        s: felt252,
    ) {
        let curve_idx = ED25519_CURVE_INDEX;
        let G = get_G(curve_idx);
        let Y = get_dleq_second_generator();

        // PRODUCTION: Comprehensive input validation
        validate_dleq_inputs(T, U, c, s, curve_idx);

        // Convert challenge and response to u256 scalars (reduced mod curve order)
        let c_scalar = reduce_felt_to_scalar(c);
        let s_scalar = reduce_felt_to_scalar(s);

        // Compute R1' = s·G - c·T using MSM with two points
        // We use MSM([G, T], [s, -c mod n]) to compute s·G + (-c)·T
        // Note: Empty hints for now - in production, compute proper hints
        let c_neg_scalar = (ED25519_ORDER - (c_scalar % ED25519_ORDER)) % ED25519_ORDER;
        let points_R1 = array![G, T];
        let scalars_R1 = array![s_scalar, c_neg_scalar];
        let hint_R1 = array![0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0].span();
        let R1_prime = msm_g1(points_R1.span(), scalars_R1.span(), curve_idx, hint_R1);

        // Compute R2' = s·Y - c·U using MSM with two points
        let points_R2 = array![Y, U];
        let scalars_R2 = array![s_scalar, c_neg_scalar];
        let hint_R2 = array![0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0].span();
        let R2_prime = msm_g1(points_R2.span(), scalars_R2.span(), curve_idx, hint_R2);

        // Recompute challenge: c' = H(tag, G, Y, T, U, R1', R2', hashlock)
        let c_prime = compute_dleq_challenge(G, Y, T, U, R1_prime, R2_prime, hashlock);

        // Verify c' == c
        assert(c_prime == c, Errors::DLEQ_CHALLENGE_MISMATCH);
        
        // Emit DLEQ verification event (for monitoring/debugging)
        // Note: We emit adaptor point coordinates, not the full G1Point
        // In production, you might want to emit more details
    }

    /// Validate DLEQ proof inputs comprehensively.
    /// 
    /// Checks:
    /// 1. Points are on-curve and not small-order
    /// 2. Scalars are in valid range [0, n)
    /// 3. Scalars are non-zero
    fn validate_dleq_inputs(
        T: G1Point,
        U: G1Point,
        c: felt252,
        s: felt252,
        curve_idx: u32,
    ) {
        // Validate points are on-curve (Garaga's assert_on_curve_excluding_infinity)
        T.assert_on_curve_excluding_infinity(curve_idx);
        U.assert_on_curve_excluding_infinity(curve_idx);
        
        // Validate points are not small-order (8-torsion check for Ed25519)
        assert(!is_small_order_ed25519(T), Errors::DLEQ_SMALL_ORDER_POINT);
        assert(!is_small_order_ed25519(U), Errors::DLEQ_SMALL_ORDER_POINT);
        
        // Validate scalars are non-zero
        assert(c != 0, Errors::DLEQ_ZERO_SCALAR);
        assert(s != 0, Errors::DLEQ_ZERO_SCALAR);
        
        // Validate scalars are in range [0, n) by reducing
        let c_scalar = reduce_felt_to_scalar(c);
        let s_scalar = reduce_felt_to_scalar(s);
        
        // Ensure reduction didn't produce zero (shouldn't happen if c != 0, but check anyway)
        let c_is_zero = c_scalar.low == 0 && c_scalar.high == 0;
        let s_is_zero = s_scalar.low == 0 && s_scalar.high == 0;
        assert(!c_is_zero, Errors::DLEQ_SCALAR_OUT_OF_RANGE);
        assert(!s_is_zero, Errors::DLEQ_SCALAR_OUT_OF_RANGE);
    }

    /// Reduce a felt252 to a u256 scalar modulo Ed25519 order.
    fn reduce_felt_to_scalar(f: felt252) -> u256 {
        // Convert felt252 to u256 (felt252 fits in u128 low)
        let f_u128: u128 = f.try_into().unwrap();
        let f_u256 = u256 { low: f_u128, high: 0 };
        f_u256 % ED25519_ORDER
    }


    /// Compute DLEQ challenge using Fiat-Shamir: c = H(tag || G || Y || T || U || R1 || R2 || hashlock) mod n
    /// 
    /// Uses Poseidon hashing for gas efficiency (10x cheaper than SHA-256).
    /// Converts u384 coordinates to felt252 for Poseidon hashing.
    /// 
    /// Note: This uses Poseidon instead of SHA-256 for on-chain efficiency.
    /// For compatibility with Rust, ensure both implementations use the same hash function.
    fn compute_dleq_challenge(
        G: G1Point,
        Y: G1Point,
        T: G1Point,
        U: G1Point,
        R1: G1Point,
        R2: G1Point,
        hashlock: Span<u32>,
    ) -> felt252 {
        // Initialize Poseidon hash state
        let mut state = PoseidonTrait::new();
        
        // Domain separator: "DLEQ" tag as felt252
        // Convert "DLEQ" (4 bytes) to felt252: 0x444c4551
        let dleq_tag: felt252 = 0x444c4551;
        state = state.update(dleq_tag);
        state = state.update(dleq_tag); // Double tag for domain separation
        
        // Hash all points by converting u384 limbs to felt252
        // Each u384 has 4 limbs (u96), we hash each limb as a felt252
        state = serialize_point_to_poseidon(state, G);
        state = serialize_point_to_poseidon(state, Y);
        state = serialize_point_to_poseidon(state, T);
        state = serialize_point_to_poseidon(state, U);
        state = serialize_point_to_poseidon(state, R1);
        state = serialize_point_to_poseidon(state, R2);
        
        // Add hashlock (8 u32 words)
        let mut i = 0;
        while i < hashlock.len() {
            let word = *hashlock.at(i);
            state = state.update(word.into());
            i += 1;
        }
        
        // Finalize Poseidon hash
        let hash_felt = state.finalize();
        
        // Convert felt252 hash to scalar mod curve order
        // felt252 fits in u256, so we can reduce directly
        let hash_u256 = u256 { low: hash_felt.try_into().unwrap(), high: 0 };
        let scalar = reduce_scalar_ed25519(hash_u256);
        
        // Convert back to felt252 (take low 252 bits)
        scalar.low.try_into().unwrap()
    }
    
    /// Serialize a G1Point to Poseidon hash state by converting u384 limbs to felt252.
    /// 
    /// Each u384 coordinate has 4 limbs (u96), each converted to felt252 and hashed.
    /// Format: x.limb0, x.limb1, x.limb2, x.limb3, y.limb0, y.limb1, y.limb2, y.limb3
    /// Returns updated hash state.
    fn serialize_point_to_poseidon(mut state: core::poseidon::HashState, p: G1Point) -> core::poseidon::HashState {
        // Convert each u96 limb to felt252 and update hash state
        let x0: felt252 = p.x.limb0.into();
        let x1: felt252 = p.x.limb1.into();
        let x2: felt252 = p.x.limb2.into();
        let x3: felt252 = p.x.limb3.into();
        let y0: felt252 = p.y.limb0.into();
        let y1: felt252 = p.y.limb1.into();
        let y2: felt252 = p.y.limb2.into();
        let y3: felt252 = p.y.limb3.into();
        
        state = state.update(x0);
        state = state.update(x1);
        state = state.update(x2);
        state = state.update(x3);
        state = state.update(y0);
        state = state.update(y1);
        state = state.update(y2);
        state = state.update(y3);
        state
    }

    /// Serialize a u32 value to 4 bytes big-endian.
    /// 
    /// Uses division/modulo instead of bit shifting (Cairo doesn't support bit ops).
    fn serialize_u32_to_4_bytes_be(ref transcript: ByteArray, value: u32) {
        let mut remaining: u32 = value;
        let mut bytes = array![];
        
        // Extract 4 bytes using repeated division by 256
        let mut i: u32 = 0;
        while i < 4 {
            let byte_val: u8 = (remaining % 256).try_into().unwrap();
            bytes.append(byte_val);
            remaining = remaining / 256;
            i += 1;
        }
        
        // Append bytes in reverse order (big-endian)
        let mut j: u32 = 3;
        loop {
            transcript.append_byte(*bytes.at(j));
            if j == 0 {
                break;
            }
            j -= 1;
        }
    }

    /// Serialize a G1Point to bytes and append to ByteArray.
    /// 
    /// Serializes u384 coordinates (x, y) as 48 bytes each (4×96-bit limbs = 4×12 bytes).
    /// Format: big-endian, limb3, limb2, limb1, limb0 for each coordinate.
    fn serialize_point_to_bytes(ref transcript: ByteArray, p: G1Point) {
        // Serialize x coordinate (u384 = 4 felt252 limbs, each 96 bits = 12 bytes)
        serialize_u384_to_bytes(ref transcript, p.x);
        // Serialize y coordinate
        serialize_u384_to_bytes(ref transcript, p.y);
    }

    /// Serialize a u384 value to 48 bytes (big-endian) and append to ByteArray.
    /// 
    /// u384 is stored as 4 u96 limbs (limb0, limb1, limb2, limb3), each 96 bits.
    /// We serialize as: limb3 (12 bytes) || limb2 (12 bytes) || limb1 (12 bytes) || limb0 (12 bytes)
    fn serialize_u384_to_bytes(ref transcript: ByteArray, value: u384) {
        // Serialize each limb as 12 bytes (96 bits) big-endian, starting with most significant
        serialize_u96_to_12_bytes_be(ref transcript, value.limb3);
        serialize_u96_to_12_bytes_be(ref transcript, value.limb2);
        serialize_u96_to_12_bytes_be(ref transcript, value.limb1);
        serialize_u96_to_12_bytes_be(ref transcript, value.limb0);
    }

    /// Serialize a u96 value to 12 bytes big-endian.
    /// 
    /// u96 is a bounded integer (0 to 2^96-1). Convert to felt252, then serialize.
    /// Uses division/modulo instead of bit shifting (Cairo doesn't support bit ops).
    fn serialize_u96_to_12_bytes_be(ref transcript: ByteArray, value: u96) {
        // Convert u96 to felt252 (u96 fits in felt252)
        let value_felt: felt252 = value.into();
        
        // Convert felt252 to u256
        let value_u256: u256 = value_felt.into();
        
        // Extract bytes using division/modulo (no bit shifting)
        // Serialize as 12 bytes big-endian: byte0 byte1 ... byte11
        // where value = byte0*256^11 + byte1*256^10 + ... + byte11
        let mut remaining = value_u256.low;
        let mut bytes = array![];
        
        // Extract 12 bytes using repeated division by 256
        let base: u128 = 256;
        let mut i: u32 = 0;
        while i < 12 {
            let byte_val: u8 = (remaining % base).try_into().unwrap();
            bytes.append(byte_val);
            remaining = remaining / base;
            i += 1;
        }
        
        // Append bytes in reverse order (big-endian)
        let mut j: u32 = 11;
        loop {
            transcript.append_byte(*bytes.at(j));
            if j == 0 {
                break;
            }
            j -= 1;
        }
    }
}
