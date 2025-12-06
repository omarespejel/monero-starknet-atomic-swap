# Recommended Cairo Module Structure

## Current Structure
```
cairo/src/
└── lib.cairo (1,097 lines - everything in one file)
```

## Recommended Structure
```
cairo/src/
├── lib.cairo                    # Main entry point, interfaces, contract module declaration
├── interfaces.cairo             # IAtomicLock, IERC20 interfaces
├── atomic_lock/
│   ├── mod.cairo               # Contract module (storage, events, errors)
│   ├── constructor.cairo      # Constructor logic
│   ├── functions.cairo        # Public functions (verify_and_unlock, refund, deposit)
│   ├── dleq.cairo             # DLEQ verification functions
│   ├── scalar_ops.cairo       # Scalar operations (hash_to_scalar, reduce_scalar)
│   ├── storage_helpers.cairo  # Storage read/write helpers
│   └── serialization.cairo    # Point/serialization utilities
└── utils/
    └── ed25519.cairo          # Ed25519-specific utilities (small order check, etc.)
```

## Module Breakdown

### `lib.cairo` (~50 lines)
- Module declarations
- Re-export public interfaces
- Contract module declaration

### `interfaces.cairo` (~50 lines)
- `IAtomicLock` trait
- `IERC20` trait

### `atomic_lock/mod.cairo` (~200 lines)
- Storage struct
- Events enum and structs
- Errors module
- Constants (ED25519_ORDER, ED25519_CURVE_INDEX)
- Component declarations

### `atomic_lock/constructor.cairo` (~200 lines)
- Constructor function
- Input validation
- DLEQ proof verification call

### `atomic_lock/functions.cairo` (~200 lines)
- `verify_and_unlock`
- `refund`
- `deposit`
- `get_target_hash`, `is_unlocked`, `get_lock_until`

### `atomic_lock/dleq.cairo` (~250 lines)
- `_verify_dleq_proof`
- `validate_dleq_inputs`
- `compute_dleq_challenge`
- `get_dleq_second_generator`

### `atomic_lock/scalar_ops.cairo` (~100 lines)
- `hash_to_scalar_u256`
- `reduce_scalar_ed25519`
- `reduce_felt_to_scalar`

### `atomic_lock/storage_helpers.cairo` (~50 lines)
- `storage_adaptor_point`
- `is_zero_point`
- `is_zero_hint`

### `atomic_lock/serialization.cairo` (~150 lines)
- `serialize_point_to_poseidon`
- `serialize_point_to_bytes`
- `serialize_u384_to_bytes`
- `serialize_u96_to_12_bytes_be`
- `serialize_u32_to_4_bytes_be`

### `utils/ed25519.cairo` (~50 lines)
- `is_small_order_ed25519`
- Ed25519-specific constants and utilities

## Benefits

1. **Auditor-Friendly**: Each module has a single responsibility
2. **Maintainability**: Easier to locate and modify specific functionality
3. **Testability**: Can test modules independently
4. **Readability**: Smaller files are easier to understand
5. **Reusability**: Utility functions can be reused across projects

## Migration Path

1. **Phase 1**: Extract interfaces to `interfaces.cairo`
2. **Phase 2**: Extract DLEQ functions to `atomic_lock/dleq.cairo`
3. **Phase 3**: Extract serialization to `atomic_lock/serialization.cairo`
4. **Phase 4**: Extract scalar operations to `atomic_lock/scalar_ops.cairo`
5. **Phase 5**: Split remaining functions

## Alternative: Keep Current Structure

If you prefer to keep everything in one file:
- ✅ **Acceptable** for auditors (many prefer single-file contracts)
- ✅ **Simpler** deployment and review
- ⚠️ **Harder** to navigate (use good IDE navigation)
- ⚠️ **Harder** to maintain as it grows

**Recommendation**: For a 1,097-line contract, splitting is beneficial but not critical. The current structure is acceptable for an audit if well-documented.

