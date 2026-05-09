//! Token Transfer Security Tests
//!
//! Tests economic invariants and token handling security properties.
//! Priority: 🔴 Critical | 🟠 High | 🟡 Medium
//!
//! **Security Properties Tested:**
//! - Token transfer integrity (exact amounts)
//! - Refund vs unlock amount verification
//! - Reentrancy attack prevention (with malicious ERC20 mock)
//! - Token balance checks before/after operations
//! - Zero amount handling edge cases

#[cfg(test)]
mod token_security_tests {
    use atomic_lock::{IAtomicLockDispatcher, IAtomicLockDispatcherTrait};
    use core::array::ArrayTrait;
    use core::byte_array::{ByteArray, ByteArrayTrait};
    use core::integer::u256;
    use core::serde::Serde;
    use core::traits::TryInto;
    use starknet::ContractAddress;
    use snforge_std::{
        declare, ContractClassTrait, DeclareResultTrait,
        start_cheat_caller_address, stop_cheat_caller_address,
        start_cheat_block_timestamp, stop_cheat_block_timestamp,
        start_cheat_caller_address_global, stop_cheat_caller_address_global,
    };
    
    // Import test constants (define locally to avoid module import issues)
    const TESTVECTOR_HASHLOCK: [u32; 8] = [
        0xb6acca81_u32, 0xa0939a85_u32, 0x6c35e4c4_u32, 0x188e95b9_u32,
        0x1731aab1_u32, 0xd4629a4c_u32, 0xee79dd09_u32, 0xded4fc94_u32,
    ];
    const TESTVECTOR_T_COMPRESSED: u256 = u256 {
        low: 0x54e86953e7cc99b545cfef03f63cce85,
        high: 0x427dde0adb325f957d29ad71e4643882,
    };
    const TESTVECTOR_U_COMPRESSED: u256 = u256 {
        low: 0x9244eb3a3699efed3106c6ae0afdf28,
        high: 0xb6e0bfc0d9fbb8a4c8ef08cb5da2eff3,
    };
    const TESTVECTOR_R1_COMPRESSED: u256 = u256 {
        low: 0x3cb02521d7a17fedca11c02ea41fe334,
        high: 0x11ef09256f90d942ca7a0e4ae05926a5,
    };
    const TESTVECTOR_R2_COMPRESSED: u256 = u256 {
        low: 0xe66ca975ef303c032fcc18a952325162,
        high: 0xc5d2eb608176c8b79dfa55289c35b35f,
    };
    const TESTVECTOR_CHALLENGE: felt252 = 0x47c760eb9b6a8797680bef6218e06aacc6570f8be11819d2268bb024f816108;
    const TESTVECTOR_RESPONSE: u256 = u256 { low: 0xbe3ffdd10e06b50b800feb45877b787b, high: 0x2f0ceba8a8c56d6f6b4ed3ae98db234 };
    
    // ============================================================================
    // Mock ERC20 Token Contract (for testing)
    // ============================================================================
    
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
        fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    }
    
    #[starknet::contract]
    mod MockERC20 {
        use starknet::{ContractAddress, get_caller_address};
        use starknet::storage::{Map, StorageMapReadAccess, StorageMapWriteAccess};
        use core::integer::u256;
        
        #[storage]
        struct Storage {
            balances: Map<ContractAddress, u256>,
            allowances: Map<(ContractAddress, ContractAddress), u256>,
        }
        
        #[constructor]
        fn constructor(ref self: ContractState) {
            // Initialize with zero balances
        }
        
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
            
            fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
                self.allowances.read((owner, spender))
            }
        }
    }
    
    // ============================================================================
    // Malicious Reentrant ERC20 Token (for reentrancy attack testing)
    // ============================================================================
    
    #[starknet::contract]
    mod MaliciousReentrantToken {
        use starknet::{ContractAddress, get_caller_address};
        use starknet::storage::{
            Map, StorageMapReadAccess, StorageMapWriteAccess,
            StoragePointerReadAccess, StoragePointerWriteAccess
        };
        use atomic_lock::{IAtomicLockDispatcher, IAtomicLockDispatcherTrait};
        use core::integer::u256;
        use core::byte_array::{ByteArray, ByteArrayTrait};
        
        #[storage]
        struct Storage {
            balances: Map<ContractAddress, u256>,
            allowances: Map<(ContractAddress, ContractAddress), u256>,
            target_contract: ContractAddress,
            attack_triggered: bool,
        }
        
        #[constructor]
        fn constructor(ref self: ContractState, target: ContractAddress) {
            self.target_contract.write(target);
            self.attack_triggered.write(false);
        }
        
        #[abi(embed_v0)]
        impl MaliciousReentrantTokenImpl of super::IMockERC20<ContractState> {
            fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
                let sender = get_caller_address();
                let sender_balance = self.balances.read(sender);
                assert(sender_balance >= amount, 'Insufficient balance');
                
                // Attempt reentrancy attack during transfer
                if !self.attack_triggered.read() {
                    self.attack_triggered.write(true);
                    let target = IAtomicLockDispatcher {
                        contract_address: self.target_contract.read(),
                    };

                    // Try to call verify_and_unlock again (should fail due to ReentrancyGuard)
                    let mut attack_secret: ByteArray = Default::default();
                    // Use dummy secret (will fail hashlock check, but reentrancy should be blocked first)
                    let mut i: u32 = 0;
                    while i < 32 {
                        attack_secret.append_byte(0x00_u8);
                        i += 1;
                    }

                    // This should fail due to ReentrancyGuard, not hashlock mismatch
                    target.verify_and_unlock(attack_secret);
                }
                
                // Complete transfer
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
                let sender_balance = self.balances.read(sender);
                assert(sender_balance >= amount, 'Insufficient balance');
                
                if !self.attack_triggered.read() {
                    self.attack_triggered.write(true);
                    let target = IAtomicLockDispatcher {
                        contract_address: self.target_contract.read(),
                    };

                    let mut attack_secret: ByteArray = Default::default();
                    let mut i: u32 = 0;
                    while i < 32 {
                        attack_secret.append_byte(0x00_u8);
                        i += 1;
                    }

                    target.verify_and_unlock(attack_secret);
                }
                
                self.balances.write(sender, sender_balance - amount);
                self.balances.write(recipient, self.balances.read(recipient) + amount);
                true
            }

            fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
                self.balances.read(account)
            }

            fn mint(ref self: ContractState, to: ContractAddress, amount: u256) {
                self.balances.write(to, self.balances.read(to) + amount);
            }

            fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
                let owner = get_caller_address();
                self.allowances.write((owner, spender), amount);
                true
            }
            
            fn allowance(self: @ContractState, owner: ContractAddress, spender: ContractAddress) -> u256 {
                self.allowances.read((owner, spender))
            }
        }
    }
    
    // ============================================================================
    // Test Constants and Helpers
    // ============================================================================
    
    const FUTURE_TIMESTAMP: u64 = 9999999999_u64;
    
    // Valid secret from test_vectors.json (SHA-256 matches TESTVECTOR_HASHLOCK)
    fn get_valid_secret() -> ByteArray {
        let mut secret: ByteArray = Default::default();
        // Secret: 1212121212121212121212121212121212121212121212121212121212121212
        let mut i: u32 = 0;
        while i < 32 {
            secret.append_byte(0x12_u8);
            i += 1;
        }
        secret
    }
    
    fn build_atomic_lock_calldata(
        token: ContractAddress,
        amount: u256,
        depositor: ContractAddress,
    ) -> Array<felt252> {
        // Use full challenge/response (matching test_e2e_dleq.cairo)
        const TEST_VECTOR_C_FULL: felt252 = 0x47c760eb9b6a8797680bef6218e06aacc6570f8be11819d2268bb024f816108;
        const TEST_VECTOR_S_FULL: u256 = u256 { low: 0xbe3ffdd10e06b50b800feb45877b787b, high: 0x2f0ceba8a8c56d6f6b4ed3ae98db234 };

        // Use deploy_with_real_dleq pattern from test_e2e_dleq.cairo
        let hashlock_array = TESTVECTOR_HASHLOCK;
        let hashlock = hashlock_array.span();

        // Sqrt hints (from test_e2e_dleq.cairo)
        const TEST_ADAPTOR_POINT_SQRT_HINT: u256 = u256 {
            low: 0x448c18dcf34127e112ff945a65defbfc,
            high: 0x17611da35f39a2a5e3a9fddb8d978e4f,
        };
        const TEST_SECOND_POINT_SQRT_HINT: u256 = u256 {
            low: 0xcffea6b3bffe746de20fdd0734b30845,
            high: 0x5e4a3b18b41199f9389ded8696067271,
        };
        const TEST_R1_SQRT_HINT: u256 = u256 { 
            low: 0x623d9789d855bcc4f0fbd8683b350688,
            high: 0x0a2d15cdfbfcf6181e92f0b7c74b477e,
        };
        const TEST_R2_SQRT_HINT: u256 = u256 { 
            low: 0xd8b08d5ec3d265b83e5e333d750d6b37,
            high: 0x0e41fbdbbf62b47c511e0a5aa04059de,
        };
        
        // Fake-GLV hint (from test_e2e_dleq.cairo - correct for secret scalar)
        let fake_glv_hint = array![
            0x4af5bf430174455ca59934c5,
            0x748d85ad870959a54bca47ba,
            0x6decdae5e1b9b254,
            0x0,
            0xaa008e6009b43d5c309fa848,
            0x5b26ec9e21237560e1866183,
            0x7191bfaa5a23d0cb,
            0x0,
            0x1569bc348ca5e9beecb728fdbfea1cd6,
            0x28e2d5faa7b8c3b25a1678149337cad3
        ].span();
        
        // Get real MSM hints (from test_e2e_dleq.cairo - these are correct)
        // These match the DLEQ proof in test_vectors.json
        let s_hint_for_g = array![
            0xceeec4a90f34e45c033e2ff5,
            0xb419479f38f86b2b114d2ff1,
            0x256941d7d54e7beb,
            0x0,
            0xaa6ddc025eb012317a89612a,
            0x6e9d804e52cb98594f552df2,
            0x47244d9888c072a3,
            0x0,
            0xcd234e4105b9809a3f4f0dde019dac1,
            0x1268c27967bf37239a1bdcad1722144e1
        ].span();
        
        let s_hint_for_y = array![
            0x872011d1a9f20fc5fbed65ec,
            0xd36e4710d58461cfe9c9ee1d,
            0x686f29bbaf2b952f,
            0x0,
            0xf350a6f8bc8acbb1d5c40cd5,
            0x4b256a3dba76a0bc779c811,
            0x43f41814a3eefa59,
            0x0,
            0xcd234e4105b9809a3f4f0dde019dac1,
            0x1268c27967bf37239a1bdcad1722144e1
        ].span();
        
        let c_neg_hint_for_t = array![
            0xfbeb7a88a7204a3109847933,
            0xd7bd766f54592bfb04b8a0bf,
            0x36adfbd5b292a10e,
            0x0,
            0xb1cb68d66c0170146df52bb2,
            0x7ad50b1ffcd1293f12940e01,
            0x665e063c6d4ac0f6,
            0x0,
            0x4d5cf08f2a0aee991f621d5e4e15728,
            0x1148705832ba97f2b70dec32979f4f785
        ].span();
        
        let c_neg_hint_for_u = array![
            0x16ecdc108960cb810ed61451,
            0x28bf80201d67e2f4728ba74b,
            0x63f872f4f71e1950,
            0x0,
            0xe94caf1beb68a19f34eb98a4,
            0x48bcbcb46602eeea1b043d0d,
            0x52e390f474357096,
            0x0,
            0x4d5cf08f2a0aee991f621d5e4e15728,
            0x1148705832ba97f2b70dec32979f4f785
        ].span();
        
        // Build constructor calldata
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

    // Helper to deploy AtomicLock contract with token
    // Returns (contract, depositor_address)
    //
    // **CRITICAL**: The production constructor takes an explicit depositor so
    // UDC deployment cannot accidentally record UDC as depositor. This helper
    // returns that explicit depositor address for refund operations.
    fn deploy_contract_with_token(
        token: ContractAddress,
        amount: u256,
    ) -> (IAtomicLockDispatcher, ContractAddress) {
        let deployer: ContractAddress = 0x123.try_into().unwrap();
        start_cheat_caller_address_global(deployer);

        let declare_res = declare("AtomicLock");
        let contract = declare_res.unwrap().contract_class();
        let calldata = build_atomic_lock_calldata(token, amount, deployer);

        // Deploy with explicit depositor calldata.
        let (addr, _) = contract.deploy(@calldata).unwrap();

        stop_cheat_caller_address_global();

        (IAtomicLockDispatcher { contract_address: addr }, deployer)
    }

    fn deploy_contract_with_token_at(
        token: ContractAddress,
        amount: u256,
        contract_address: ContractAddress,
    ) -> (IAtomicLockDispatcher, ContractAddress) {
        let deployer: ContractAddress = 0x123.try_into().unwrap();
        start_cheat_caller_address_global(deployer);

        let declare_res = declare("AtomicLock");
        let contract = declare_res.unwrap().contract_class();
        let calldata = build_atomic_lock_calldata(token, amount, deployer);
        let (addr, _) = contract.deploy_at(@calldata, contract_address).unwrap();
        assert(addr == contract_address, 'Unexpected lock address');

        stop_cheat_caller_address_global();

        (IAtomicLockDispatcher { contract_address: addr }, deployer)
    }
    
    // ============================================================================
    // 🔴 CRITICAL: Token Transfer Integrity Tests
    // ============================================================================
    
    /// Test that unlock transfers exact amount to unlocker
    /// 
    /// **Security Property**: Token transfers must be exact - no more, no less.
    /// This prevents economic attacks where incorrect amounts are transferred.
    #[test]
    fn test_unlock_transfers_exact_amount() {
        // Deploy mock token
        let token_class = declare("MockERC20").unwrap().contract_class();
        let (token_address, _) = token_class.deploy(@ArrayTrait::new()).unwrap();
        let token = IMockERC20Dispatcher { contract_address: token_address };
        
        // Deploy AtomicLock contract
        let amount: u256 = u256 { low: 1000, high: 0 };
        let (contract, _depositor) = deploy_contract_with_token(token_address, amount);
        
        // Mint tokens to contract (simulating deposit)
        token.mint(contract.contract_address, amount);
        
        // Get unlocker address (using constant address for test)
        let unlocker: ContractAddress = 0x456.try_into().unwrap();
        start_cheat_caller_address(contract.contract_address, unlocker);
        
        // Record balances before unlock
        let contract_balance_before = token.balance_of(contract.contract_address);
        let unlocker_balance_before = token.balance_of(unlocker);
        
        assert(contract_balance_before == amount, 'Contract should have tokens');
        
        // Reveal with correct secret, then claim after grace.
        let secret = get_valid_secret();
        let success = contract.verify_and_unlock(secret);
        assert(success, 'Unlock should succeed');

        let claimable_after = contract.get_claimable_after();
        start_cheat_block_timestamp(contract.contract_address, claimable_after + 1);
        contract.claim_tokens();
        stop_cheat_block_timestamp(contract.contract_address);
        
        stop_cheat_caller_address(contract.contract_address);
        
        // Verify exact transfer
        let contract_balance_after = token.balance_of(contract.contract_address);
        let unlocker_balance_after = token.balance_of(unlocker);
        
        assert(contract_balance_after == u256 { low: 0, high: 0 }, 'Contract should be empty');
        assert(unlocker_balance_after == unlocker_balance_before + amount, 'Exact amount');
    }
    
    /// Test that refund returns exact amount to depositor
    /// 
    /// **Security Property**: Refund must return exact locked amount.
    /// This ensures depositor gets back exactly what they locked.
    #[test]
    fn test_refund_returns_exact_amount() {
        // Deploy mock token
        let token_class = declare("MockERC20").unwrap().contract_class();
        let (token_address, _) = token_class.deploy(@ArrayTrait::new()).unwrap();
        let token = IMockERC20Dispatcher { contract_address: token_address };
        
        // Deploy AtomicLock contract
        let amount: u256 = u256 { low: 5000, high: 0 };
        let (contract, depositor) = deploy_contract_with_token(token_address, amount);
        
        // Mint tokens to contract (simulating deposit)
        token.mint(contract.contract_address, amount);
        
        // Record balance before refund
        let depositor_balance_before = token.balance_of(depositor);
        
        // Fast-forward past expiry
        let lock_until = contract.get_lock_until();
        start_cheat_block_timestamp(contract.contract_address, lock_until + 1);
        
        // Refund as depositor
        start_cheat_caller_address(contract.contract_address, depositor);
        let success = contract.refund();
        assert(success, 'Refund should succeed');
        stop_cheat_caller_address(contract.contract_address);
        stop_cheat_block_timestamp(contract.contract_address);
        
        // Verify refund
        let depositor_balance_after = token.balance_of(depositor);
        assert(depositor_balance_after == depositor_balance_before + amount, 'Should refund exact amount');
        
        // Verify contract is empty
        let contract_balance_after = token.balance_of(contract.contract_address);
        assert(contract_balance_after == u256 { low: 0, high: 0 }, 'Empty after refund');
    }
    
    /// Test that zero amount contracts don't attempt token transfers
    /// 
    /// **Security Property**: Contracts with amount = 0 should not call token contract.
    /// This prevents unnecessary external calls and potential failures.
    #[test]
    fn test_zero_amount_no_transfer() {
        // Deploy contract with zero amount
        let zero_token: ContractAddress = 0.try_into().unwrap();
        let zero_amount: u256 = u256 { low: 0, high: 0 };
        let (contract, _depositor) = deploy_contract_with_token(zero_token, zero_amount);
        
        // Reveal and claim should succeed without token transfer
        let secret = get_valid_secret();
        let unlocker: ContractAddress = 0x456.try_into().unwrap();
        start_cheat_caller_address(contract.contract_address, unlocker);
        
        let success = contract.verify_and_unlock(secret);
        assert(success, 'Unlock succeeds');
        let claimable_after = contract.get_claimable_after();
        start_cheat_block_timestamp(contract.contract_address, claimable_after + 1);
        contract.claim_tokens();
        stop_cheat_block_timestamp(contract.contract_address);
        
        stop_cheat_caller_address(contract.contract_address);
        assert(contract.is_unlocked(), 'Contract should be unlocked');
    }
    
    // ============================================================================
    // 🔴 CRITICAL: Reentrancy Attack Prevention Tests
    // ============================================================================
    
    /// Test that ReentrancyGuard blocks recursive calls during token claim.
    ///
    /// The malicious token is constructed with the exact AtomicLock address and
    /// AtomicLock is deployed at that address with the malicious token configured.
    #[test]
    #[should_panic(expected: 'ReentrancyGuard: reentrant call')]
    fn test_reentrancy_attack_blocked() {
        let target_lock_address: ContractAddress = 0xabc123.try_into().unwrap();

        let malicious_token_class = declare("MaliciousReentrantToken").unwrap().contract_class();
        let mut malicious_calldata = ArrayTrait::new();
        Serde::serialize(@target_lock_address, ref malicious_calldata);
        let (malicious_token_address, _) = malicious_token_class.deploy(@malicious_calldata).unwrap();

        let amount: u256 = u256 { low: 1000, high: 0 };
        let (contract, _depositor) = deploy_contract_with_token_at(
            malicious_token_address, amount, target_lock_address
        );

        let malicious_token = IMockERC20Dispatcher { contract_address: malicious_token_address };
        malicious_token.mint(contract.contract_address, amount);

        let unlocker: ContractAddress = 0x456.try_into().unwrap();
        start_cheat_caller_address(contract.contract_address, unlocker);
        
        assert(contract.verify_and_unlock(get_valid_secret()), 'Reveal should succeed');
        let claimable_after = contract.get_claimable_after();
        start_cheat_block_timestamp(contract.contract_address, claimable_after + 1);

        contract.claim_tokens();
    }
    
    // ============================================================================
    // 🟠 HIGH: Token Balance Verification Tests
    // ============================================================================
    
    /// Test that contract balance is checked before transfer
    /// 
    /// **Security Property**: Contract must have sufficient balance before transferring.
    /// This prevents partial transfers or failed transfers that could leave contract in inconsistent state.
    /// 
    /// **Note**: The contract calls `token.transfer()` which will fail with "Insufficient balance"
    /// from the ERC20 contract, not "Token transfer failed" from AtomicLock.
    #[test]
    #[should_panic(expected: ('Insufficient balance',))]
    fn test_unlock_fails_with_insufficient_balance() {
        // Deploy mock token
        let token_class = declare("MockERC20").unwrap().contract_class();
        let (token_address, _) = token_class.deploy(@ArrayTrait::new()).unwrap();
        
        // Deploy AtomicLock contract with amount > 0
        let amount: u256 = u256 { low: 1000, high: 0 };
        let (contract, _depositor) = deploy_contract_with_token(token_address, amount);
        
        // Don't mint tokens to contract (insufficient balance)
        
        // Attempt claim after reveal - should fail due to insufficient balance
        // The ERC20 transfer will fail with "Insufficient balance"
        let unlocker: ContractAddress = 0x456.try_into().unwrap();
        start_cheat_caller_address(contract.contract_address, unlocker);
        
        let secret = get_valid_secret();
        contract.verify_and_unlock(secret);
        let claimable_after = contract.get_claimable_after();
        start_cheat_block_timestamp(contract.contract_address, claimable_after + 1);
        contract.claim_tokens();
        
        stop_cheat_caller_address(contract.contract_address);
    }
    
    /// Test that refund fails with insufficient balance
    /// 
    /// **Security Property**: Refund must have sufficient balance before transferring.
    /// 
    /// **Note**: The contract calls `token.transfer()` which will fail with "Insufficient balance"
    /// from the ERC20 contract, not "Token transfer failed" from AtomicLock.
    #[test]
    #[should_panic(expected: ('Insufficient balance',))]
    fn test_refund_fails_with_insufficient_balance() {
        // Deploy mock token
        let token_class = declare("MockERC20").unwrap().contract_class();
        let (token_address, _) = token_class.deploy(@ArrayTrait::new()).unwrap();
        
        // Deploy AtomicLock contract
        let amount: u256 = u256 { low: 1000, high: 0 };
        let (contract, depositor) = deploy_contract_with_token(token_address, amount);
        
        // Don't mint tokens to contract (insufficient balance)
        
        // Fast-forward past expiry
        let lock_until = contract.get_lock_until();
        start_cheat_block_timestamp(contract.contract_address, lock_until + 1);
        
        // Attempt refund - should fail due to insufficient balance
        // The ERC20 transfer will fail with "Insufficient balance"
        start_cheat_caller_address(contract.contract_address, depositor);
        
        contract.refund();
        
        stop_cheat_caller_address(contract.contract_address);
        stop_cheat_block_timestamp(contract.contract_address);
    }
}
