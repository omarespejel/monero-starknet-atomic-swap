# BLAKE2s Implementation Notes

## Critical Serialization Issue

**Problem**: Rust uses compressed Edwards points (32 bytes), Cairo uses Weierstrass points (u384 = 48 bytes per coordinate).

**Current Status**: 
- ✅ Rust: BLAKE2s implemented with compressed Edwards format
- ⚠️ Cairo: BLAKE2s implementation needs proper point serialization

**Solution Required**:
1. **Option A**: Convert Weierstrass to compressed Edwards in Cairo (complex)
2. **Option B**: Convert Edwards to Weierstrass in Rust, serialize Weierstrass in both (simpler)
3. **Option C**: Use canonical byte serialization that works for both (needs research)

## Recommended Approach: Option B

Convert Edwards to Weierstrass in Rust, then serialize Weierstrass coordinates as bytes in both:

1. **Rust**: 
   - Convert Edwards points to Weierstrass
   - Serialize Weierstrass coordinates (x, y) as 48 bytes each (big-endian)
   - Total: 96 bytes per point

2. **Cairo**:
   - Serialize Weierstrass coordinates directly (already have u384)
   - Serialize as 48 bytes per coordinate (big-endian)
   - Total: 96 bytes per point

## Implementation Steps

### Phase 1: Rust Edwards→Weierstrass Conversion
- Add conversion function: `edwards_to_weierstrass(edwards_point) -> (u384, u384)`
- Use birational map from Ed25519 Edwards to Weierstrass
- Update `compute_challenge()` to convert points before serialization

### Phase 2: Cairo Serialization
- Update `serialize_point_to_bytes()` to serialize u384 coordinates as 48 bytes each
- Ensure big-endian byte order matches Rust
- Test with known points

### Phase 3: Integration Test
- Generate proof in Rust with Weierstrass serialization
- Verify in Cairo with same serialization
- Ensure challenges match exactly

## Current Workaround

For now, we can:
1. Keep Rust using compressed Edwards (32 bytes)
2. Keep Cairo using Weierstrass serialization (96 bytes)
3. Document that they won't match until conversion is implemented
4. Add TODO comments in code

## References

- Ed25519 Edwards to Weierstrass conversion: RFC 8032
- BLAKE2s specification: RFC 7693
- Cairo BLAKE2s API: `core::blake`

