# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.8.0-alpha] - 2025-12-09

### Added
- **Monero Wallet RPC Integration**: Production-grade wallet RPC client based on COMIT Network's battle-tested patterns
  - Complete wallet RPC client implementation (`rust/src/monero_wallet/`)
  - Locked transaction creation (core atomic swap function)
  - 10-confirmation safety (COMIT standard)
  - Key image verification (prevents double-spending)
  - Comprehensive integration tests
  - Docker setup for easy testing
  - Published Docker image: `espejelomar/monero-wallet-rpc` on Docker Hub

- **Docker Support**: Custom Dockerfile and docker-compose setup for Monero wallet-rpc
  - Custom `Dockerfile.wallet-rpc` with official Monero v0.18.3.1 binaries
  - ARM64/x86_64 architecture support
  - Health checks and proper configuration
  - Published to Docker Hub and GitHub Container Registry

- **Deployment Pipeline**: Auditor-approved deployment script with golden rule enforcement
  - `scripts/deploy.sh` with mandatory sqrt hint validation
  - Phase 0: Golden Rule Gate (cannot be skipped)
  - Automated validation gates (Rust compatibility, Cairo E2E, contract build)
  - Deployment manifest with audit trail

- **Sqrt Hint Prevention System**: Comprehensive protection against sqrt hint mismatches
  - `cairo/tests/fixtures/AUTHORITATIVE_SQRT_HINTS.cairo` - Single source of truth
  - `tools/validate_sqrt_hints.py` - Validation script
  - `tools/discover_sqrt_hints.py` - Discovery tool
  - Pre-commit hooks for validation
  - CI/CD workflows for vector validation
  - Documentation: `docs/SQRT_HINT_PREVENTION.md`

- **Documentation Consolidation**: Streamlined documentation structure
  - Consolidated setup guides into `docs/SETUP.md`
  - Docker setup guide: `docs/DOCKER_SETUP.md`
  - Docker publishing guide: `docs/DOCKER_PUBLISHING.md`
  - Monero wallet integration guide: `rust/docs/MONERO_WALLET_INTEGRATION.md`
  - Updated all internal references

### Changed
- **Version**: Updated from v0.7.1-alpha to v0.8.0-alpha
- **Test Status**: Updated to reflect actual test results (81/105 Cairo tests passing, 21/22 Rust tests passing)
- **README**: Updated with Docker image references and accurate status
- **Dependencies**: Updated to production-grade Monero integration libraries
  - `monero = "0.12"`
  - `jsonrpc_client = "0.7"`
  - `monero-epee-bin-serde = "1"`
  - `rust_decimal = "1"`
  - `curve25519-dalek = "4.1"` (upgraded from v3.1 for better security)

### Fixed
- **E2E DLEQ Test**: Fixed sqrt hints, compressed points, and challenge/response values
- **Docker Setup**: Fixed entrypoint and command configuration for monero-wallet-rpc
- **Test Vectors**: Corrected field names in hint generation scripts
- **Deployment Script**: Removed unsupported `--release` flag from scarb build

### Security
- **Golden Rule Enforcement**: Programmatic enforcement of sqrt hint validation in deployment pipeline
- **Input Validation**: Added validation to `generate_dleq_proof()` function
- **Domain Separation**: Added domain separation prefixes to all hash functions
- **Zeroize Secrets**: All `Scalar` types derive `Zeroize, ZeroizeOnDrop`

### Documentation
- **Setup Guides**: Complete setup documentation for Docker and local binary installation
- **Docker Publishing**: Guide for publishing Docker images to Docker Hub and GHCR
- **Monero Integration**: Comprehensive guide for Monero wallet RPC integration
- **Version References**: Updated all version references across documentation

### Known Issues
- Some Cairo tests failing (24 tests) - depositor validation, coordinate extraction issues
- One Rust timing test failing (`test_recover_constant_time`) - coefficient of variation too high
- Race condition mitigation pending (planned for v0.8.0)

## [0.7.1-alpha] - 2025-12-08

### Added
- **DLEQ Proof Implementation**: Complete DLEQ proof generation and verification
  - Rust: DLEQ proof generation using BLAKE2s
  - Cairo: DLEQ verification using BLAKE2s (RFC 7693 compliant)
  - Rust↔Cairo compatibility verified (E2E test passes)

- **BLAKE2s Migration**: Migrated from Poseidon to BLAKE2s for gas efficiency
  - 8x gas savings for challenge computation
  - RFC 7693 compliant implementation
  - Verified byte-order compatibility

- **Security Test Suite**: Comprehensive security audit tests
  - Point validation tests
  - Small-order point rejection tests
  - Scalar range validation tests
  - Reentrancy protection tests

- **Test Organization**: Organized tests into logical categories
  - Security tests (`test_security_*.cairo`)
  - E2E tests (`test_e2e_*.cairo`)
  - Unit tests (`test_unit_*.cairo`)
  - Integration tests (`test_integration_*.cairo`)

### Fixed
- BLAKE2s initialization vector (RFC 7693 compliant)
- DLEQ tag byte order
- BLAKE2s block accumulation
- Y constant byte order
- Scalar truncation (128-bit matching)
- Sqrt hints (Montgomery vs. Twisted Edwards)
- MSM hints (exact Garaga decompression)

### Security
- Key splitting approach validated against Serai DEX pattern
- All cryptographic operations use audited libraries (Garaga, OpenZeppelin)
- Zero custom cryptography implementation

## [0.7.0-alpha] - Initial Release

### Added
- **Core Protocol**: Atomic swap protocol between Monero and Starknet
  - SHA-256 Hashlock on Starknet
  - Key splitting on Monero side (`x = x_partial + t`)
  - Garaga MSM verification for Ed25519 point verification
  - Adaptor signature logic

- **Cairo Contract**: AtomicLock contract with hashlock verification
  - Point validation (on-curve, small-order checks)
  - Reentrancy protection (OpenZeppelin ReentrancyGuard)
  - Timelock support for refunds

- **Rust Library**: Secret generation and cryptographic primitives
  - DLEQ proof generation
  - Compressed Edwards point handling
  - Test vector generation

- **Python Tooling**: Test data generation and compatibility verification
  - MSM hint generation
  - Sqrt hint discovery
  - Cross-platform verification

- **CLI Tools**: Maker and taker commands for end-to-end swaps

---

## Release Notes Format

Each release includes:
- **Added**: New features
- **Changed**: Changes in existing functionality
- **Deprecated**: Soon-to-be removed features
- **Removed**: Removed features
- **Fixed**: Bug fixes
- **Security**: Security improvements and fixes

