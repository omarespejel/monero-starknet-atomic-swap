# Versioning Strategy

## Semantic Versioning

This project follows [Semantic Versioning 2.0.0](https://semver.org/):

- **MAJOR.MINOR.PATCH** (e.g., `v0.5.0`)
- **MAJOR**: Breaking changes (incompatible API changes)
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

## Current Version: v0.5.2

**Status**: Pre-1.0.0 (development phase)

During pre-1.0.0:
- Minor versions can include breaking changes
- Patch versions are for bug fixes and non-breaking changes
- Major version increments are for major milestones

## Release Tags

### v0.5.2 - Critical Cryptographic Fixes (Current)
- **Date**: 2025-12-06
- **Milestone**: Fixed endianness, double consumption, and scalar interpretation bugs
- **Status**: Cryptographic fixes complete, integration testing ongoing
- **Key Fixes**:
  - Endianness bug in BLAKE2s challenge computation: FIXED
  - Double consumption bug in DLEQ verification: FIXED
  - Scalar interpretation alignment: FIXED
  - Sequential MSM call failures: FIXED

### v0.5.0 - Cryptography Milestone
- **Date**: 2024-01-XX
- **Milestone**: Hardest cryptography parts cleared
- **Status**: 90% production-ready
- **Key Achievements**:
  - Point decompression: COMPLETE
  - Fake-GLV hint generation: RESOLVED
  - Sqrt hint generation: FIXED
  - Curve index: CORRECTED

### v0.4.0 - Infrastructure & BLAKE2s Migration
- **Date**: 2024-01-XX
- **Focus**: CI/CD, documentation consolidation, BLAKE2s migration
- **Status**: Infrastructure complete, cryptography issues remaining

### v0.3.0 - Production Ready (Initial)
- **Date**: 2024-01-XX
- **Focus**: Initial production-ready milestone

## When to Create a New Release

### Minor Version (v0.X.0)
Create when:
- ✅ **Major milestone achieved** (e.g., cryptography cleared)
- ✅ **Significant new features added**
- ✅ **Multiple critical fixes bundled together**
- ✅ **Production readiness milestone**

### Patch Version (v0.X.Y)
Create when:
- ✅ **Critical bug fix** (security or correctness)
- ✅ **Small fixes** that don't warrant minor version
- ✅ **Documentation updates** (if significant)

### Major Version (v1.0.0)
Create when:
- ✅ **Production deployment**
- ✅ **API stability guaranteed**
- ✅ **Security audit complete**
- ✅ **All critical features implemented**

## Release Process

1. **Create Release Notes**
   ```bash
   # Create RELEASE_NOTES_vX.Y.Z.md
   # Document all changes, fixes, and achievements
   ```

2. **Commit Release Notes**
   ```bash
   git add RELEASE_NOTES_vX.Y.Z.md
   git commit -m "docs: add release notes for vX.Y.Z"
   ```

3. **Create Annotated Tag**
   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z: [Brief Description]

   Key changes:
   - Change 1
   - Change 2
   - Change 3
   
   Status: [Production-ready / Development]"
   ```

4. **Push Tag and Commits**
   ```bash
   git push origin main
   git push origin vX.Y.Z
   ```

5. **Verify Tag**
   ```bash
   git tag --list | sort -V | tail -3
   git show vX.Y.Z
   ```

## Branch Protection Strategy

### Main Branch
- ✅ **Protected**: No direct pushes (use PRs)
- ✅ **Requires**: All tests passing
- ✅ **Requires**: Code review (if team grows)
- ✅ **Tags**: Created from main branch only

### Feature Branches
- ✅ **Naming**: `feat/description` or `fix/description`
- ✅ **Merged**: Via PR to main
- ✅ **Deleted**: After merge

### Release Branches (Future)
- ✅ **Naming**: `release/vX.Y.Z`
- ✅ **Purpose**: Final testing before tag
- ✅ **Merged**: To main and develop (if using git-flow)

## Best Practices

### ✅ DO
- Tag releases after major milestones
- Create comprehensive release notes
- Use annotated tags (not lightweight)
- Push tags immediately after creation
- Document breaking changes clearly
- Include migration notes if needed

### ❌ DON'T
- Tag every commit (only meaningful releases)
- Create tags from feature branches
- Delete tags after creation (they're permanent)
- Skip release notes for significant releases
- Mix breaking and non-breaking changes in same minor version

## Future Release Planning

### v0.6.0 (Next Planned)
- **Goal**: Complete end-to-end DLEQ verification
- **Status**: In progress
- **Timeline**: After remaining test debugging

### v1.0.0 (Production Release)
- **Goal**: Production deployment
- **Requirements**:
  - Complete security audit
  - All tests passing
  - Gas optimization complete
  - Documentation finalized
  - Mainnet deployment tested

## Version History

| Version | Date | Milestone | Status |
|---------|------|-----------|--------|
| v0.5.2 | 2025-12-06 | Critical cryptographic fixes | ✅ Released |
| v0.5.0 | 2024-01-XX | Cryptography cleared | ✅ Released |
| v0.4.0 | 2024-01-XX | Infrastructure complete | ✅ Released |
| v0.3.0 | 2024-01-XX | Initial production-ready | ✅ Released |

## References

- [Semantic Versioning 2.0.0](https://semver.org/)
- [Git Tagging Best Practices](https://git-scm.com/book/en/v2/Git-Basics-Tagging)
- [Keep a Changelog](https://keepachangelog.com/)

