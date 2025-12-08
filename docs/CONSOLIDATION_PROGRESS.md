# Test Consolidation Progress

**Date**: December 2025  
**Status**: Phase 1 Complete, Phase 2 In Progress

## ✅ Completed (Phase 1)

1. **Single Source of Truth** ✅
   - `cairo/tests/fixtures/test_vectors.cairo` - All constants centralized
   - `cairo/tests/fixtures/deployment_helpers.cairo` - Unified deployment helpers
   - Added simple `deploy()` wrapper function

2. **Deprecated Functions** ✅
   - `deploy_with_full()` marked as deprecated
   - Tests using it marked `#[ignore]` with documentation

## 🔄 In Progress (Phase 2)

### Current Status

**Test Files**: 35 files  
**Target**: ~8 files (77% reduction)  
**Security Tests**: 4 files, ~1,436 lines total

### Consolidation Strategy

Given the size and complexity of the security tests (~1,436 lines), consolidation should be done incrementally:

1. **Immediate**: Update existing files to use `fixtures::test_vectors` (remove duplicate constants)
2. **Short-term**: Consolidate security tests (4 → 1 file)
3. **Medium-term**: Consolidate unit tests (12 → 1 file)
4. **Long-term**: Consolidate integration tests (12 → 1 file)

### Next Steps

**Option A: Incremental (Recommended)**
- Update security test files to import from `fixtures::test_vectors` (removes ~200 lines of duplication)
- Keep files separate but eliminate duplication
- Consolidate later when time permits

**Option B: Full Consolidation (Auditor's Request)**
- Merge all 4 security test files into `test_security.cairo` with modules
- Estimated time: 4-6 hours
- Risk: Large merge, potential for errors

## Recommendation

**Proceed with Option A** for now:
1. Remove duplicate constants from security test files (use imports)
2. Verify all tests still pass
3. Document consolidation as future work

This achieves 80% of the benefit (removing duplication) with 20% of the effort (full consolidation).

## Files Updated

- ✅ `cairo/tests/fixtures/deployment_helpers.cairo` - Added `deploy()` wrapper
- ✅ `docs/CONSOLIDATION_PLAN.md` - Detailed plan created
- ⏸️ Security test files - Ready for constant deduplication

