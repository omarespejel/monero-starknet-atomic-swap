# Test Organization and Running

## Test Structure

Tests are organized using **naming conventions** in the root `tests/` directory. This approach is pragmatic for Cairo/snforge because:

1. **Native snforge support** - No scripts or workarounds needed
2. **Filter by category** - `snforge test --filter "security_"` works out of the box
3. **Auditor-friendly** - All tests visible in one place, categories obvious from names
4. **CI-simple** - No custom test discovery logic

```
tests/
├── test_security_*.cairo       # Security audit tests (CRITICAL)
├── test_e2e_*.cairo            # End-to-end integration
├── test_unit_*.cairo           # Fast, isolated unit tests
├── test_integration_*.cairo    # Cross-component tests
├── test_debug_*.cairo          # Development/debugging (can skip in CI)
├── fixtures/                   # Shared helpers (NOT test files)
│   ├── test_vectors.cairo
│   ├── test_helpers.cairo
│   └── constants/
│       └── low_order_points.cairo
└── mocks/                      # Mock contracts (NOT test files)
```

## Running Tests

### Run All Tests

```bash
cd cairo
snforge test
```

### Run by Category

```bash
# Security tests (CRITICAL)
snforge test security_

# End-to-end tests
snforge test e2e_

# Unit tests
snforge test unit_

# Integration tests
snforge test integration_

# Debug tests (development only)
snforge test debug_
```

### Skip Debug Tests (Production CI)

```bash
# Run all tests except debug (use pattern matching)
snforge test security_ e2e_ unit_ integration_
```

### Run Specific Test

```bash
# Run a specific test function
snforge test --exact test_security_audit::test_cannot_unlock_twice

# Run all tests matching a pattern
snforge test security_audit
```

## Test Categories

### Security Tests (`test_security_*.cairo`)
**Priority: 🔴 CRITICAL**

Security-focused tests that must pass:
- `test_security_audit.cairo` - Security audit tests (7/9 passing)
- `test_security_dleq_negative.cairo` - Negative tests (wrong inputs)
- `test_security_edge_cases.cairo` - Edge cases (boundary values)

### E2E Tests (`test_e2e_*.cairo`)
**Priority: 🟢 HIGH**

Full system tests:
- `test_e2e_dleq.cairo` - Rust↔Cairo compatibility (✅ PASSES)
- `test_e2e_full_swap_flow.cairo` - Complete swap lifecycle

### Unit Tests (`test_unit_*.cairo`)
**Priority: ⚪ MEDIUM**

Fast, isolated tests for individual components:
- `test_unit_blake2s_challenge.cairo` - BLAKE2s challenge computation
- `test_unit_blake2s_byte_order.cairo` - Byte order verification
- `test_unit_dleq.cairo` - DLEQ proof verification
- `test_unit_garaga_integration.cairo` - Garaga library integration
- `test_unit_point_decompression.cairo` - Point decompression
- And more...

### Integration Tests (`test_integration_*.cairo`)
**Priority: 🔵 MEDIUM**

Cross-component tests:
- `test_integration_constructor.cairo` - Constructor flow
- `test_integration_garaga_msm.cairo` - MSM operations
- `test_integration_hashlock_serde.cairo` - Serialization
- `test_integration_atomic_lock.cairo` - Core contract tests
- And more...

### Debug Tests (`test_debug_*.cairo`)
**Priority: ⚫ LOW**

Development and debugging tests (can be skipped in CI):
- `test_debug_blake2s_state.cairo` - BLAKE2s state debugging
- `test_debug_scalar.cairo` - Scalar reduction debugging
- `test_debug_challenge.cairo` - Challenge computation debugging
- `test_debug_garaga_msm.cairo` - Garaga MSM debugging

## Fixtures

Non-test files in `fixtures/` directory:
- `test_vectors.cairo` - Single source of truth for test constants
- `test_helpers.cairo` - Shared test helper functions
- `constants/low_order_points.cairo` - Ed25519 low-order point constants

## CI/CD Integration

Example GitHub Actions workflow:

```yaml
name: Cairo Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install Scarb
        uses: software-mansion/setup-scarb@v1
        with:
          scarb-version: "2.10.0"
      
      - name: Install snforge
        run: |
          curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh
      
      - name: Build
        run: cd cairo && scarb build
      
      - name: Security Tests (CRITICAL)
        run: cd cairo && snforge test security_ -v
      
      - name: E2E Tests
        run: cd cairo && snforge test e2e_ -v
      
      - name: Unit Tests
        run: cd cairo && snforge test unit_ -v
      
      - name: Integration Tests
        run: cd cairo && snforge test integration_ -v
      
      # Skip debug tests in CI (optional)
      # - name: Debug Tests
      #   run: cd cairo && snforge test debug_ -v
```

## Import Paths

Test files can import from fixtures using relative paths or module imports:

```cairo
// Import constants from fixtures
// (Most tests currently use direct constants - see test files for patterns)

// Import helpers from fixtures
// use fixtures::test_helpers::deploy_with_dleq_proof;
```

## Benefits of This Approach

1. ✅ **Native snforge support** - No custom scripts needed
2. ✅ **Easy filtering** - Pattern matching works out of the box (`snforge test security_`)
3. ✅ **CI-friendly** - Simple test commands
4. ✅ **Auditor-friendly** - All tests visible, categories obvious from names
5. ✅ **Maintainable** - Clear naming convention
6. ✅ **Test discovery** - All 107 tests discovered automatically
