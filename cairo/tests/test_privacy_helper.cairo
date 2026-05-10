//! Privacy helper integration tests.
//!
//! These tests cover the direct-to-privacy-pool settlement path:
//! AtomicLock reveal by helper -> delayed claim -> ERC20 approve to privacy pool
//! -> OpenNoteDeposit return data for StarkWare privacy `InvokeExternal`.

#[cfg(test)]
mod privacy_helper_tests {
    use atomic_lock::{
        IAtomicLockDispatcher, IAtomicLockDispatcherTrait, IAtomicSwapPrivacyHelperDispatcher,
        IAtomicSwapPrivacyHelperDispatcherTrait,
    };
    use core::array::ArrayTrait;
    use core::byte_array::{ByteArray, ByteArrayTrait};
    use core::integer::u256;
    use core::serde::Serde;
    use core::traits::TryInto;
    use snforge_std::{
        ContractClassTrait, DeclareResultTrait, declare, start_cheat_block_timestamp,
        start_cheat_caller_address, start_cheat_caller_address_global, stop_cheat_block_timestamp,
        stop_cheat_caller_address, stop_cheat_caller_address_global,
    };
    use starknet::ContractAddress;

    const TESTVECTOR_HASHLOCK: [u32; 8] = [
        0xb6acca81_u32, 0xa0939a85_u32, 0x6c35e4c4_u32, 0x188e95b9_u32, 0x1731aab1_u32,
        0xd4629a4c_u32, 0xee79dd09_u32, 0xded4fc94_u32,
    ];
    const TESTVECTOR_T_COMPRESSED: u256 = u256 {
        low: 0x54e86953e7cc99b545cfef03f63cce85, high: 0x427dde0adb325f957d29ad71e4643882,
    };
    const TESTVECTOR_U_COMPRESSED: u256 = u256 {
        low: 0x9244eb3a3699efed3106c6ae0afdf28, high: 0xb6e0bfc0d9fbb8a4c8ef08cb5da2eff3,
    };
    const TESTVECTOR_R1_COMPRESSED: u256 = u256 {
        low: 0x3cb02521d7a17fedca11c02ea41fe334, high: 0x11ef09256f90d942ca7a0e4ae05926a5,
    };
    const TESTVECTOR_R2_COMPRESSED: u256 = u256 {
        low: 0xe66ca975ef303c032fcc18a952325162, high: 0xc5d2eb608176c8b79dfa55289c35b35f,
    };
    const FUTURE_TIMESTAMP: u64 = 9999999999_u64;

    #[starknet::interface]
    trait IMockERC20<TContractState> {
        fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
        fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
        fn transfer_from(
            ref self: TContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool;
        fn mint(ref self: TContractState, to: ContractAddress, amount: u256);
        fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
        fn allowance(
            self: @TContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256;
    }

    #[starknet::contract]
    mod MockERC20 {
        use core::integer::u256;
        use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
        use starknet::{ContractAddress, get_caller_address};

        #[storage]
        struct Storage {
            balances: Map<ContractAddress, u256>,
            allowances: Map<(ContractAddress, ContractAddress), u256>,
        }

        #[constructor]
        fn constructor(ref self: ContractState) {}

        #[abi(embed_v0)]
        impl MockERC20Impl of super::IMockERC20<ContractState> {
            fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
                self.balances.read(account)
            }

            fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
                let sender = get_caller_address();
                let sender_balance = self.balances.read(sender);
                assert(sender_balance >= amount, 'Insufficient balance');
                self.balances.write(sender, sender_balance - amount);
                self.balances.write(recipient, self.balances.read(recipient) + amount);
                true
            }

            fn transfer_from(
                ref self: ContractState,
                sender: ContractAddress,
                recipient: ContractAddress,
                amount: u256,
            ) -> bool {
                let caller = get_caller_address();
                let allowance = self.allowances.read((sender, caller));
                assert(allowance >= amount, 'Insufficient allowance');
                let sender_balance = self.balances.read(sender);
                assert(sender_balance >= amount, 'Insufficient balance');
                self.allowances.write((sender, caller), allowance - amount);
                self.balances.write(sender, sender_balance - amount);
                self.balances.write(recipient, self.balances.read(recipient) + amount);
                true
            }

            fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
                self.balances.write(to, self.balances.read(to) + amount);
            }

            fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
                let owner = get_caller_address();
                self.allowances.write((owner, spender), amount);
                true
            }

            fn allowance(
                self: @ContractState, owner: ContractAddress, spender: ContractAddress,
            ) -> u256 {
                self.allowances.read((owner, spender))
            }
        }
    }

    fn get_valid_secret() -> ByteArray {
        let mut secret: ByteArray = Default::default();
        let mut i: u32 = 0;
        while i < 32 {
            secret.append_byte(0x12_u8);
            i += 1;
        }
        secret
    }

    fn build_atomic_lock_calldata(
        token: ContractAddress, amount: u256, depositor: ContractAddress,
    ) -> Array<felt252> {
        const TEST_VECTOR_C_FULL: felt252 =
            0x47c760eb9b6a8797680bef6218e06aacc6570f8be11819d2268bb024f816108;
        const TEST_VECTOR_S_FULL: u256 = u256 {
            low: 0xbe3ffdd10e06b50b800feb45877b787b, high: 0x2f0ceba8a8c56d6f6b4ed3ae98db234,
        };
        const TEST_ADAPTOR_POINT_SQRT_HINT: u256 = u256 {
            low: 0x448c18dcf34127e112ff945a65defbfc, high: 0x17611da35f39a2a5e3a9fddb8d978e4f,
        };
        const TEST_SECOND_POINT_SQRT_HINT: u256 = u256 {
            low: 0xcffea6b3bffe746de20fdd0734b30845, high: 0x5e4a3b18b41199f9389ded8696067271,
        };
        const TEST_R1_SQRT_HINT: u256 = u256 {
            low: 0x623d9789d855bcc4f0fbd8683b350688, high: 0x0a2d15cdfbfcf6181e92f0b7c74b477e,
        };
        const TEST_R2_SQRT_HINT: u256 = u256 {
            low: 0xd8b08d5ec3d265b83e5e333d750d6b37, high: 0x0e41fbdbbf62b47c511e0a5aa04059de,
        };

        let hashlock = TESTVECTOR_HASHLOCK.span();
        let fake_glv_hint = array![
            0x4af5bf430174455ca59934c5, 0x748d85ad870959a54bca47ba, 0x6decdae5e1b9b254, 0x0,
            0xaa008e6009b43d5c309fa848, 0x5b26ec9e21237560e1866183, 0x7191bfaa5a23d0cb, 0x0,
            0x1569bc348ca5e9beecb728fdbfea1cd6, 0x28e2d5faa7b8c3b25a1678149337cad3,
        ]
            .span();
        let s_hint_for_g = array![
            0xceeec4a90f34e45c033e2ff5, 0xb419479f38f86b2b114d2ff1, 0x256941d7d54e7beb, 0x0,
            0xaa6ddc025eb012317a89612a, 0x6e9d804e52cb98594f552df2, 0x47244d9888c072a3, 0x0,
            0xcd234e4105b9809a3f4f0dde019dac1, 0x1268c27967bf37239a1bdcad1722144e1,
        ]
            .span();
        let s_hint_for_y = array![
            0x872011d1a9f20fc5fbed65ec, 0xd36e4710d58461cfe9c9ee1d, 0x686f29bbaf2b952f, 0x0,
            0xf350a6f8bc8acbb1d5c40cd5, 0x4b256a3dba76a0bc779c811, 0x43f41814a3eefa59, 0x0,
            0xcd234e4105b9809a3f4f0dde019dac1, 0x1268c27967bf37239a1bdcad1722144e1,
        ]
            .span();
        let c_neg_hint_for_t = array![
            0xfbeb7a88a7204a3109847933, 0xd7bd766f54592bfb04b8a0bf, 0x36adfbd5b292a10e, 0x0,
            0xb1cb68d66c0170146df52bb2, 0x7ad50b1ffcd1293f12940e01, 0x665e063c6d4ac0f6, 0x0,
            0x4d5cf08f2a0aee991f621d5e4e15728, 0x1148705832ba97f2b70dec32979f4f785,
        ]
            .span();
        let c_neg_hint_for_u = array![
            0x16ecdc108960cb810ed61451, 0x28bf80201d67e2f4728ba74b, 0x63f872f4f71e1950, 0x0,
            0xe94caf1beb68a19f34eb98a4, 0x48bcbcb46602eeea1b043d0d, 0x52e390f474357096, 0x0,
            0x4d5cf08f2a0aee991f621d5e4e15728, 0x1148705832ba97f2b70dec32979f4f785,
        ]
            .span();

        let mut calldata = ArrayTrait::new();
        hashlock.serialize(ref calldata);
        Serde::serialize(@FUTURE_TIMESTAMP, ref calldata);
        Serde::serialize(@depositor, ref calldata);
        Serde::serialize(@token, ref calldata);
        Serde::serialize(@amount, ref calldata);
        Serde::serialize(@TESTVECTOR_T_COMPRESSED, ref calldata);
        Serde::serialize(@TEST_ADAPTOR_POINT_SQRT_HINT, ref calldata);
        Serde::serialize(@TESTVECTOR_U_COMPRESSED, ref calldata);
        Serde::serialize(@TEST_SECOND_POINT_SQRT_HINT, ref calldata);
        Serde::serialize(@TEST_VECTOR_C_FULL, ref calldata);
        Serde::serialize(@TEST_VECTOR_S_FULL, ref calldata);
        Serde::serialize(@fake_glv_hint, ref calldata);
        Serde::serialize(@s_hint_for_g, ref calldata);
        Serde::serialize(@s_hint_for_y, ref calldata);
        Serde::serialize(@c_neg_hint_for_t, ref calldata);
        Serde::serialize(@c_neg_hint_for_u, ref calldata);
        Serde::serialize(@TESTVECTOR_R1_COMPRESSED, ref calldata);
        Serde::serialize(@TEST_R1_SQRT_HINT, ref calldata);
        Serde::serialize(@TESTVECTOR_R2_COMPRESSED, ref calldata);
        Serde::serialize(@TEST_R2_SQRT_HINT, ref calldata);
        calldata
    }

    fn deploy_atomic_lock(
        token: ContractAddress, amount: u256,
    ) -> (IAtomicLockDispatcher, ContractAddress) {
        let depositor: ContractAddress = 0x123.try_into().unwrap();
        start_cheat_caller_address_global(depositor);
        let lock_class = declare("AtomicLock").unwrap().contract_class();
        let calldata = build_atomic_lock_calldata(token, amount, depositor);
        let (addr, _) = lock_class.deploy(@calldata).unwrap();
        stop_cheat_caller_address_global();
        (IAtomicLockDispatcher { contract_address: addr }, depositor)
    }

    fn deploy_helper() -> IAtomicSwapPrivacyHelperDispatcher {
        let helper_class = declare("AtomicSwapPrivacyHelper").unwrap().contract_class();
        let (helper_address, _) = helper_class.deploy(@ArrayTrait::new()).unwrap();
        IAtomicSwapPrivacyHelperDispatcher { contract_address: helper_address }
    }

    fn deploy_token() -> IMockERC20Dispatcher {
        let token_class = declare("MockERC20").unwrap().contract_class();
        let (token_address, _) = token_class.deploy(@ArrayTrait::new()).unwrap();
        IMockERC20Dispatcher { contract_address: token_address }
    }

    fn bind_reveal_ready(
        lock: IAtomicLockDispatcher,
        helper: IAtomicSwapPrivacyHelperDispatcher,
        token_address: ContractAddress,
        amount: u256,
        privacy_contract: ContractAddress,
        note_id: felt252,
    ) {
        let secret = get_valid_secret();
        assert(
            helper
                .bind_and_reveal(
                    lock.contract_address, token_address, amount, privacy_contract, note_id, secret,
                ),
            'Bind reveal failed',
        );
        assert(lock.is_secret_revealed(), 'Lock not revealed');
        assert(helper.is_bound(lock.contract_address), 'Helper not bound');
    }

    #[test]
    fn test_privacy_helper_claims_and_approves_open_note_deposit() {
        let token = deploy_token();
        let amount: u256 = u256 { low: 1000, high: 0 };
        let (lock, _) = deploy_atomic_lock(token.contract_address, amount);
        let helper = deploy_helper();
        let privacy_contract: ContractAddress = 0x777.try_into().unwrap();
        let note_id: felt252 = 0xabc;

        token.mint(lock.contract_address, amount);
        bind_reveal_ready(lock, helper, token.contract_address, amount, privacy_contract, note_id);

        let claimable_after = lock.get_claimable_after();
        start_cheat_block_timestamp(lock.contract_address, claimable_after + 1);
        start_cheat_caller_address(helper.contract_address, privacy_contract);
        let deposits = helper.privacy_invoke(lock.contract_address, note_id);
        stop_cheat_caller_address(helper.contract_address);
        stop_cheat_block_timestamp(lock.contract_address);

        assert(deposits.len() == 1, 'Bad deposit count');
        let deposit = *deposits.at(0);
        assert(deposit.note_id == note_id, 'Bad note id');
        assert(deposit.token == token.contract_address, 'Bad token');
        assert(deposit.amount == amount.low, 'Bad amount');
        assert(lock.is_unlocked(), 'Lock not unlocked');
        assert(helper.is_settled(lock.contract_address), 'Helper not settled');
        assert(
            token.allowance(helper.contract_address, privacy_contract) == amount, 'Bad allowance',
        );
        assert(token.balance_of(helper.contract_address) == amount, 'Helper balance');

        start_cheat_caller_address(token.contract_address, privacy_contract);
        assert(
            token.transfer_from(helper.contract_address, privacy_contract, amount),
            'Pool pull failed',
        );
        stop_cheat_caller_address(token.contract_address);
        assert(token.balance_of(helper.contract_address) == u256 { low: 0, high: 0 }, 'Dust');
        assert(token.balance_of(privacy_contract) == amount, 'Pool balance');
    }

    #[test]
    #[should_panic(expected: ('WRONG_PRIVACY',))]
    fn test_privacy_helper_rejects_wrong_privacy_caller() {
        let token = deploy_token();
        let amount: u256 = u256 { low: 1000, high: 0 };
        let (lock, _) = deploy_atomic_lock(token.contract_address, amount);
        let helper = deploy_helper();
        let privacy_contract: ContractAddress = 0x777.try_into().unwrap();
        let attacker: ContractAddress = 0x778.try_into().unwrap();
        let note_id: felt252 = 0xabc;

        token.mint(lock.contract_address, amount);
        bind_reveal_ready(lock, helper, token.contract_address, amount, privacy_contract, note_id);

        let claimable_after = lock.get_claimable_after();
        start_cheat_block_timestamp(lock.contract_address, claimable_after + 1);
        start_cheat_caller_address(helper.contract_address, attacker);
        helper.privacy_invoke(lock.contract_address, note_id);
    }

    #[test]
    #[should_panic(expected: ('NOTE_MISMATCH',))]
    fn test_privacy_helper_rejects_wrong_note_id() {
        let token = deploy_token();
        let amount: u256 = u256 { low: 1000, high: 0 };
        let (lock, _) = deploy_atomic_lock(token.contract_address, amount);
        let helper = deploy_helper();
        let privacy_contract: ContractAddress = 0x777.try_into().unwrap();
        let note_id: felt252 = 0xabc;

        token.mint(lock.contract_address, amount);
        bind_reveal_ready(lock, helper, token.contract_address, amount, privacy_contract, note_id);

        let claimable_after = lock.get_claimable_after();
        start_cheat_block_timestamp(lock.contract_address, claimable_after + 1);
        start_cheat_caller_address(helper.contract_address, privacy_contract);
        helper.privacy_invoke(lock.contract_address, 0xabd);
    }

    #[test]
    #[should_panic(expected: ('ALREADY_SETTLED',))]
    fn test_privacy_helper_blocks_double_settlement() {
        let token = deploy_token();
        let amount: u256 = u256 { low: 1000, high: 0 };
        let (lock, _) = deploy_atomic_lock(token.contract_address, amount);
        let helper = deploy_helper();
        let privacy_contract: ContractAddress = 0x777.try_into().unwrap();
        let note_id: felt252 = 0xabc;

        token.mint(lock.contract_address, amount);
        bind_reveal_ready(lock, helper, token.contract_address, amount, privacy_contract, note_id);

        let claimable_after = lock.get_claimable_after();
        start_cheat_block_timestamp(lock.contract_address, claimable_after + 1);
        start_cheat_caller_address(helper.contract_address, privacy_contract);
        helper.privacy_invoke(lock.contract_address, note_id);
        helper.privacy_invoke(lock.contract_address, note_id);
    }

    #[test]
    #[should_panic(expected: ('Grace period not expired',))]
    fn test_privacy_helper_claim_before_grace_fails() {
        let token = deploy_token();
        let amount: u256 = u256 { low: 1000, high: 0 };
        let (lock, _) = deploy_atomic_lock(token.contract_address, amount);
        let helper = deploy_helper();
        let privacy_contract: ContractAddress = 0x777.try_into().unwrap();
        let note_id: felt252 = 0xabc;

        token.mint(lock.contract_address, amount);
        bind_reveal_ready(lock, helper, token.contract_address, amount, privacy_contract, note_id);

        start_cheat_caller_address(helper.contract_address, privacy_contract);
        helper.privacy_invoke(lock.contract_address, note_id);
    }
}
