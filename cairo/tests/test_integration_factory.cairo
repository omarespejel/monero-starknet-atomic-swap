#[cfg(test)]
mod factory_tests {
    use atomic_lock::{
        IAtomicLockFactoryDispatcher, IAtomicLockFactoryDispatcherTrait,
    };
    use core::array::ArrayTrait;
    use core::serde::Serde;
    use core::traits::TryInto;
    use snforge_std::{
        declare, start_cheat_caller_address, stop_cheat_caller_address, ContractClassTrait,
        DeclareResultTrait,
    };
    use starknet::contract_address::ContractAddress;

    fn deploy_factory(owner: ContractAddress) -> IAtomicLockFactoryDispatcher {
        let declare_res = declare("AtomicLockFactory");
        let contract = declare_res.unwrap().contract_class();
        let atomic_lock_class_hash = atomic_lock::AtomicLock::TEST_CLASS_HASH;

        let mut calldata = ArrayTrait::new();
        Serde::serialize(@owner, ref calldata);
        Serde::serialize(@atomic_lock_class_hash, ref calldata);

        let (address, _) = contract.deploy(@calldata).unwrap();
        IAtomicLockFactoryDispatcher { contract_address: address }
    }

    #[test]
    fn factory_constructor_sets_owner_and_atomic_lock_class_hash() {
        let owner: ContractAddress = 0x123.try_into().unwrap();
        let factory = deploy_factory(owner);

        assert(factory.get_owner() == owner, 'owner mismatch');
        assert(
            factory.get_atomic_lock_class_hash() == atomic_lock::AtomicLock::TEST_CLASS_HASH,
            'class hash mismatch',
        );
    }

    #[test]
    fn owner_can_update_class_hash_and_register_lock() {
        let owner: ContractAddress = 0x123.try_into().unwrap();
        let factory = deploy_factory(owner);
        let lock_address: ContractAddress = 0x456.try_into().unwrap();

        start_cheat_caller_address(factory.contract_address, owner);
        assert(
            factory.set_atomic_lock_class_hash(atomic_lock::AtomicLock::TEST_CLASS_HASH),
            'set class hash failed',
        );
        assert(
            factory.register_lock(lock_address, 'smoke1', 2115307, 'stagenet', 'meta'),
            'register failed',
        );
        stop_cheat_caller_address(factory.contract_address);
    }

    #[test]
    #[should_panic(expected: ('Not factory owner',))]
    fn non_owner_cannot_register_lock() {
        let owner: ContractAddress = 0x123.try_into().unwrap();
        let attacker: ContractAddress = 0x999.try_into().unwrap();
        let factory = deploy_factory(owner);
        let lock_address: ContractAddress = 0x456.try_into().unwrap();

        start_cheat_caller_address(factory.contract_address, attacker);
        factory.register_lock(lock_address, 'smoke1', 2115307, 'stagenet', 'meta');
        stop_cheat_caller_address(factory.contract_address);
    }

    #[test]
    #[should_panic(expected: ('Partial key id is zero',))]
    fn owner_cannot_register_lock_without_partial_key_id() {
        let owner: ContractAddress = 0x123.try_into().unwrap();
        let factory = deploy_factory(owner);
        let lock_address: ContractAddress = 0x456.try_into().unwrap();

        start_cheat_caller_address(factory.contract_address, owner);
        factory.register_lock(lock_address, 0, 2115307, 'stagenet', 'meta');
        stop_cheat_caller_address(factory.contract_address);
    }
}
