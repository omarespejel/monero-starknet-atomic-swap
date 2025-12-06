# Release v0.4.0

## Summary

This release includes significant infrastructure improvements, documentation consolidation, and BLAKE2s migration completion. The codebase is now better organized and includes automated testing infrastructure.

## Major Changes

### Infrastructure
- ✅ **CI/CD Workflow**: Added GitHub Actions workflow for automated testing
- ✅ **Conversion Utilities**: Added Garaga-compatible hex→u256 conversion tools
- ✅ **Automated Verification**: Created Rust↔Cairo equivalence verification tool

### Documentation
- ✅ **Consolidation**: Reduced 18 markdown files to 5 essential documents
- ✅ **Accuracy**: Updated README with current accurate status
- ✅ **Audit Documentation**: Consolidated all audit findings into `AUDIT.md`
- ✅ **Technical Docs**: Consolidated technical details into `TECHNICAL.md`

### Cryptographic Implementation
- ✅ **BLAKE2s Migration**: Completed migration from Poseidon to BLAKE2s
- ✅ **Byte-Order Verification**: Confirmed byte-order correctness (tests pass)
- ✅ **Challenge Computation**: Verified Rust↔Cairo compatibility

### Testing
- ✅ **Diagnostic Tests**: Added point decompression diagnostic tests
- ✅ **Byte-Order Tests**: Comprehensive byte-order verification suite
- ✅ **Challenge Tests**: Isolated challenge computation tests

## Known Issues

- ⚠️ **Compressed Point Decompression**: All Edwards points fail decompression in tests
  - Hex→u256 conversion verified correct
  - Issue likely in sqrt hints or decompression function usage
  - Blocks end-to-end test execution

## Breaking Changes

None. This is a backwards-compatible release.

## Migration Notes

- Repository references renamed from "xmr-starknet" to "monero"
- Documentation structure simplified (see `TECHNICAL.md` and `AUDIT.md`)
- CI/CD now runs automatically on push/PR

## Next Steps

1. Fix compressed point decompression issue
2. Complete end-to-end testing
3. Security audit preparation

## Contributors

- Omar Espejel (@omarespejel)

## Full Changelog

See git log: `git log v0.3.0-production-ready..v0.4.0`

