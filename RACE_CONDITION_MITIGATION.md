# Race Condition Mitigation Plan

## Vulnerability Summary

A protocol-level race condition exists between secret revelation on Starknet and Monero transaction confirmation. When a party reveals the secret `t` on Starknet, they immediately receive tokens. However, if the corresponding Monero transaction fails or experiences a blockchain reorganization, funds may be at risk.

**Evidence**: September 2025 Monero network experienced an 18-block reorganization (approximately 36 minutes), demonstrating this is not a theoretical concern.

## Attack Scenarios

### Scenario 1: Monero Transaction Failure

1. Alice reveals `t` on Starknet → Receives Starknet tokens immediately
2. Bob learns `t` → Attempts to spend Monero
3. Bob's Monero transaction fails or is rejected
4. Result: Alice has Starknet tokens, Bob lost Monero funds

### Scenario 2: Monero Blockchain Reorganization

1. Alice reveals `t` on Starknet → Receives Starknet tokens immediately
2. Alice's Monero is now spendable by Bob
3. Bob successfully spends Monero
4. 18-block Monero reorg occurs → Bob's transaction reverted
5. Result: Alice has both Starknet tokens and Monero (double-spend)

## Mitigation Strategy

### Priority 0: Critical for Production

**1. Grace Period After Unlock**

Implement a two-hour grace period after secret revelation. Tokens do not transfer immediately. Instead, the contract stores the unlock timestamp and enters a pending state. Only after the grace period expires can tokens be transferred.

**Implementation**:
- Add `unlock_timestamp: u64` to storage
- Add `pending_unlock: bool` to storage
- Modify `verify_and_unlock()` to set pending state instead of transferring
- Add `finalize_unlock()` function that transfers after grace period

**2. Minimum Timelock**

Enforce a minimum timelock of three hours. This ensures sufficient time for cross-chain confirmation before the swap can be unlocked.

**Implementation**:
- Add validation in constructor: `assert(lock_until >= now + 3 hours)`
- Document minimum timelock requirement

**3. Two-Phase Unlock**

Separate secret revelation from token transfer. The first phase reveals the secret and emits an event. The second phase transfers tokens after the grace period.

**Implementation**:
- Phase 1: `reveal_secret()` - Validates secret, stores timestamp, emits event
- Phase 2: `finalize_unlock()` - Transfers tokens after grace period

### Priority 1: Production Enhancements

**4. Watchtower Service**

A watchtower service monitors both chains and alerts parties if cross-chain confirmation fails. This provides additional safety for high-value swaps.

**Implementation**: External service (not contract change)

### Priority 2: Future Enhancements

**5. Insurance Pool**

An insurance pool could cover losses from race conditions. This requires significant economic design and is deferred.

**6. Multi-Signature for High Value**

High-value swaps could require multi-signature confirmation before finalization. This adds complexity and is deferred.

## Implementation Plan

### Phase 1: Grace Period (This Week)

**Effort**: 2-3 hours

1. Add storage variables: `unlock_timestamp`, `pending_unlock`
2. Modify `verify_and_unlock()` to set pending state
3. Add `finalize_unlock()` function
4. Add grace period constant (2 hours)
5. Update tests

### Phase 2: Minimum Timelock (This Week)

**Effort**: 1 hour

1. Add minimum timelock validation in constructor
2. Update documentation
3. Update tests

### Phase 3: Two-Phase Unlock (Next Week)

**Effort**: 1 day

1. Refactor unlock into two functions
2. Add comprehensive tests
3. Update documentation

### Phase 4: Watchtower Service (Future)

**Effort**: 2-3 days

1. Design watchtower architecture
2. Implement monitoring service
3. Add alerting mechanisms

## Contract Changes Required

### Storage Additions

```cairo
unlock_timestamp: u64,
pending_unlock: bool,
```

### Modified Function: verify_and_unlock()

```cairo
fn verify_and_unlock(ref self: ContractState, secret: ByteArray) -> bool {
    // ... existing verification ...
    
    // Store unlock time, but DON'T transfer tokens yet
    self.unlock_timestamp.write(get_block_timestamp());
    self.pending_unlock.write(true);
    
    // Emit event with secret (counterparty can now compute x)
    self.emit(SecretRevealed { 
        secret_hash: h0,
        unlocker: get_caller_address(),
        timestamp: get_block_timestamp()
    });
    
    true
}
```

### New Function: finalize_unlock()

```cairo
fn finalize_unlock(ref self: ContractState) -> bool {
    assert(self.pending_unlock.read(), Errors::NOT_PENDING);
    
    let now = get_block_timestamp();
    let unlock_time = self.unlock_timestamp.read();
    const GRACE_PERIOD: u64 = 7200; // 2 hours
    
    assert(now >= unlock_time + GRACE_PERIOD, Errors::GRACE_PERIOD_NOT_EXPIRED);
    
    // NOW transfer tokens
    let amount = self.amount.read();
    let token = self.token.read();
    let unlocker = get_caller_address();
    
    let ok = maybe_transfer(token, unlocker, amount);
    assert(ok, Errors::TOKEN_TRANSFER_FAILED);
    
    self.unlocked.write(true);
    self.pending_unlock.write(false);
    self.emit(Unlocked { unlocker });
    
    true
}
```

### Constructor Modification

```cairo
// Add minimum timelock validation
const MIN_TIMELOCK: u64 = 10800; // 3 hours
assert(lock_until >= get_block_timestamp() + MIN_TIMELOCK, Errors::TIMELOCK_TOO_SHORT);
```

## Testing Requirements

1. **Grace Period Test**: Verify tokens cannot transfer before grace period expires
2. **Finalization Test**: Verify tokens transfer after grace period
3. **Minimum Timelock Test**: Verify constructor rejects short timelocks
4. **Event Emission Test**: Verify SecretRevealed event is emitted correctly
5. **State Transition Test**: Verify pending → finalized state transition

## Documentation Updates

1. Update README with race condition warning
2. Update SECURITY.md with vulnerability details
3. Update protocol flow documentation
4. Add migration guide for existing contracts

## Timeline

| Phase | Timeline | Status |
|-------|----------|--------|
| Grace Period | This week | Planned |
| Minimum Timelock | This week | Planned |
| Two-Phase Unlock | Next week | Planned |
| Watchtower Service | Future | Deferred |

## Current Recommendation

**For Testnet/Demo**: Acceptable with documented warnings. Use only for swaps under $100.

**For Production**: Must implement P0 mitigations (grace period, minimum timelock, two-phase unlock) before deployment.

**Version Target**: v0.8.0

---

**Last Updated**: 2025-12-07  
**Status**: Planned for v0.8.0

