# Sqrt Hint Prevention Strategy

## The Golden Rule

```
🔴 NEVER generate sqrt hints from Python/Rust mathematical computation.
✅ ALWAYS validate sqrt hints through Cairo/Garaga decompression tests.
✅ ALWAYS use the empirically-validated hints from AUTHORITATIVE_SQRT_HINTS.cairo.
```

## Protection Layers

| Layer | Protection | File |
|-------|------------|------|
| **Source Control** | Pre-commit hook validates sqrt hints | `.git/hooks/pre-commit` |
| **CI/CD** | GitHub Actions validates on every PR | `.github/workflows/validate-vectors.yml` |
| **Documentation** | Authoritative hints documented | `cairo/tests/fixtures/AUTHORITATIVE_SQRT_HINTS.cairo` |
| **Validation Scripts** | Manual validation tools | `tools/validate_sqrt_hints.py` |
| **Discovery Tool** | Candidate hint generator | `tools/discover_sqrt_hints.py` |

## How to Update Sqrt Hints

### Step 1: Generate Candidates (Optional)
```bash
python tools/discover_sqrt_hints.py <compressed_point_hex>
```

### Step 2: Test in Cairo
Update `test_unit_point_decompression.cairo` with candidate hint and run:
```bash
cd cairo
snforge test test_unit_point_decompression --exact
```

### Step 3: If Test Passes
Copy the working hint to `AUTHORITATIVE_SQRT_HINTS.cairo`:
```cairo
pub const SQRT_HINT_T: u256 = u256 {
    low: 0x<working_low>,
    high: 0x<working_high>,
};
```

### Step 4: Validate
```bash
python tools/validate_sqrt_hints.py rust/test_vectors.json
```

## Root Cause (2025-12-09)

**Problem:** `deployment_vector.json` contained sqrt hints generated with Python's `fix_hints.py`, which uses a different algorithm than Garaga expects.

**Solution:** Use empirically-validated sqrt hints from passing Cairo tests.

**Prevention:** All new sqrt hints must pass Cairo decompression tests before being used.

