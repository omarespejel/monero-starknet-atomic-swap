#!/usr/bin/env python3
"""
Generate constructor calldata for AtomicLock contract deployment.

Usage:
    python generate_deploy_calldata.py <test_vectors.json> <deployer_address> [lock_until]

Output:
    Prints calldata array suitable for starkli deploy command.
"""

import json
import sys
from pathlib import Path

def u256_to_felts(u256_value):
    """Convert u256 (low, high) to two felt252 values."""
    if isinstance(u256_value, dict):
        low_val = u256_value.get('low', 0)
        high_val = u256_value.get('high', 0)
        low = int(low_val, 16) if isinstance(low_val, str) else low_val
        high = int(high_val, 16) if isinstance(high_val, str) else high_val
    elif isinstance(u256_value, str):
        # Hex string - convert to int, then split
        hex_clean = u256_value.replace('0x', '')
        u256_int = int(hex_clean, 16)
        low = u256_int & ((1 << 128) - 1)
        high = u256_int >> 128
    else:
        # Integer
        low = u256_value & ((1 << 128) - 1)
        high = u256_value >> 128
    return [f"0x{low:032x}", f"0x{high:032x}"]

def span_to_felts(span_array):
    """Convert span array to list of felt252 hex strings."""
    result = []
    for item in span_array:
        if isinstance(item, str):
            # Already hex string
            result.append(item if item.startswith('0x') else f"0x{item}")
        else:
            # Integer
            result.append(f"0x{item:032x}")
    return result

def main():
    if len(sys.argv) < 3:
        print("Usage: python generate_deploy_calldata.py <test_vectors.json> <deployer_address> [lock_until]")
        sys.exit(1)
    
    test_vectors_path = Path(sys.argv[1])
    deployer_address = sys.argv[2]
    lock_until = int(sys.argv[3]) if len(sys.argv) > 3 else None
    
    # Load test vectors
    with open(test_vectors_path, 'r') as f:
        tv = json.load(f)
    
    # Load hints
    hints_path = Path(__file__).parent.parent / "cairo" / "adaptor_point_hint.json"
    with open(hints_path, 'r') as f:
        hints = json.load(f)
    
    # Calculate lock_until if not provided (current time + 4 hours)
    if lock_until is None:
        import time
        lock_until = int(time.time()) + 14400  # 4 hours
    
    # Ensure lock_until is reasonable (not too small)
    if lock_until < 1000000000:
        lock_until = 9999999999  # Use a far future timestamp for testing
    
    calldata = []
    
    # 1. Hashlock (8 u32 words)
    hashlock = tv['hashlock']
    # Parse hashlock - can be hex string or array
    if isinstance(hashlock, str):
        # Convert hex string to bytes, then to u32 array
        hashlock_bytes = bytes.fromhex(hashlock.replace('0x', ''))
        hashlock_words = []
        for i in range(0, len(hashlock_bytes), 4):
            word_bytes = hashlock_bytes[i:i+4]
            # Pad if needed
            while len(word_bytes) < 4:
                word_bytes = word_bytes + b'\x00'
            word = int.from_bytes(word_bytes, 'little')
            hashlock_words.append(word)
        hashlock = hashlock_words
    for word in hashlock:
        if isinstance(word, str):
            word = int(word, 16) if word.startswith('0x') else int(word)
        calldata.append(f"0x{word:08x}")
    
    # 2. lock_until (u64)
    calldata.append(f"0x{lock_until:x}")
    
    # 3. token (ContractAddress) - zero for testnet
    calldata.append("0x0")
    
    # 4. amount (u256) - zero for testnet
    calldata.extend(["0x0", "0x0"])
    
    # 5. adaptor_point_edwards_compressed (u256)
    adaptor_point = tv['adaptor_point_compressed']
    calldata.extend(u256_to_felts(adaptor_point))
    
    # 6. adaptor_point_sqrt_hint (u256)
    # Use sqrt hint from test vectors or hints file
    sqrt_hint_t = hints.get('adaptor_point_sqrt_hint', tv.get('adaptor_point_sqrt_hint'))
    if sqrt_hint_t:
        calldata.extend(u256_to_felts(sqrt_hint_t))
    else:
        # Fallback to test_e2e_dleq.cairo constants
        calldata.extend(["0x448c18dcf34127e112ff945a65defbfc", "0x17611da35f39a2a5e3a9fddb8d978e4f"])
    
    # 7. dleq_second_point_edwards_compressed (u256)
    second_point = tv['dleq_second_point_compressed']
    calldata.extend(u256_to_felts(second_point))
    
    # 8. dleq_second_point_sqrt_hint (u256)
    sqrt_hint_u = hints.get('second_point_sqrt_hint', tv.get('dleq_second_point_sqrt_hint'))
    if sqrt_hint_u:
        calldata.extend(u256_to_felts(sqrt_hint_u))
    else:
        # Fallback to test_e2e_dleq.cairo constants
        calldata.extend(["0xdcad2173817c163b5405cec7698eb4b8", "0x742bb3c44b13553c8ddff66565b44cac"])
    
    # 9. DLEQ proof (challenge, response) - 2 felt252
    challenge = tv.get('dleq_challenge', tv.get('challenge'))
    response = tv.get('dleq_response', tv.get('response'))
    
    # Handle truncated values (low 128 bits)
    if isinstance(challenge, str):
        # Remove 0x prefix if present, then parse as hex
        challenge_hex = challenge.replace('0x', '')
        challenge_val = int(challenge_hex, 16)
    else:
        challenge_val = challenge
    # Truncate to 128 bits (matching test_e2e_dleq.cairo)
    challenge_val = challenge_val & ((1 << 128) - 1)
    calldata.append(f"0x{challenge_val:032x}")
    
    if isinstance(response, str):
        # Remove 0x prefix if present, then parse as hex
        response_hex = response.replace('0x', '')
        response_val = int(response_hex, 16)
    else:
        response_val = response
    # Truncate to 128 bits
    response_val = response_val & ((1 << 128) - 1)
    calldata.append(f"0x{response_val:032x}")
    
    # 10. fake_glv_hint (Span<felt252> - 10 felts)
    fake_glv = hints.get('fake_glv_hint', [])
    if not fake_glv:
        # Fallback to test_e2e_dleq.cairo constants
        fake_glv = [
            "0x4af5bf430174455ca59934c5",
            "0x748d85ad870959a54bca47ba",
            "0x6decdae5e1b9b254",
            "0x0",
            "0xaa008e6009b43d5c309fa848",
            "0x5b26ec9e21237560e1866183",
            "0x7191bfaa5a23d0cb",
            "0x0",
            "0x1569bc348ca5e9beecb728fdbfea1cd6",
            "0x28e2d5faa7b8c3b25a1678149337cad3"
        ]
    calldata.extend(span_to_felts(fake_glv))
    
    # 11-14. DLEQ MSM hints (4 spans of 10 felts each)
    msm_hints = hints.get('msm_hints', {})
    
    # s_hint_for_g
    s_hint_g = msm_hints.get('s_hint_for_g', [])
    if not s_hint_g:
        # Fallback to test_e2e_dleq.cairo
        s_hint_g = [
            "0xa82b6800cf6fafb9e422ff00",
            "0xa9d32170fa1d6e70ce9f5875",
            "0x38d522e54f3cc905",
            "0x0",
            "0x6632b6936c8a0092f2fa8193",
            "0x48849326ffd29b0fd452c82e",
            "0x1cb22722b8aeac6d",
            "0x0",
            "0x3ce8213ee078382bd7862b141d23a01e",
            "0x12a88328ee6fe07c656e9f1f11921d2ff"
        ]
    calldata.extend(span_to_felts(s_hint_g))
    
    # s_hint_for_y
    s_hint_y = msm_hints.get('s_hint_for_y', [])
    if not s_hint_y:
        s_hint_y = [
            "0x5f8703b67e528a68c666436f",
            "0x4319c91a2264dceb203b3c7",
            "0x131bcf26d61c6749",
            "0x0",
            "0x2b9edf9810114e3f99120ee8",
            "0x23ac0997ff9d26665393f4f1",
            "0xa2adc2ad21db8d1",
            "0x0",
            "0x3ce8213ee078382bd7862b141d23a01e",
            "0x12a88328ee6fe07c656e9f1f11921d2ff"
        ]
    calldata.extend(span_to_felts(s_hint_y))
    
    # c_neg_hint_for_t
    c_neg_t = msm_hints.get('c_neg_hint_for_t', [])
    if not c_neg_t:
        c_neg_t = [
            "0xcc7bbab2a86720f06fa72b5a",
            "0x27ebc6cd7c83bd71f4819168",
            "0x2b4af1beb7dc4112",
            "0x0",
            "0xd0ac52873f110a396803c36c",
            "0xc23304c89672797661dbefa3",
            "0x547b7c3862004a5a",
            "0x0",
            "0xba5f45d69eaafbaaa06091a65e2873d",
            "0x1301450999c6615fa5bded0ada7e22902"
        ]
    calldata.extend(span_to_felts(c_neg_t))
    
    # c_neg_hint_for_u
    c_neg_u = msm_hints.get('c_neg_hint_for_u', [])
    if not c_neg_u:
        c_neg_u = [
            "0x3aa67aef7c64a7b253e4a0fc",
            "0x2799eb3ed1784408cb1f6360",
            "0x6d7fa630d5721877",
            "0x0",
            "0x9fed6006f4d300b627b45f",
            "0xf8f69fd5bc96748bf6e2541b",
            "0x56b40a0879ad40ae",
            "0x0",
            "0xba5f45d69eaafbaaa06091a65e2873d",
            "0x1301450999c6615fa5bded0ada7e22902"
        ]
    calldata.extend(span_to_felts(c_neg_u))
    
    # 15. dleq_r1_compressed (u256)
    r1_compressed = tv.get('dleq_r1_compressed', tv.get('r1_compressed'))
    if r1_compressed:
        calldata.extend(u256_to_felts(r1_compressed))
    else:
        # Fallback
        calldata.extend(["0x90b1ab352981d43ec51fba0af7ab51c7", "0xc21ebc88e5e59867b280909168338026"])
    
    # 16. dleq_r1_sqrt_hint (u256)
    r1_sqrt = hints.get('r1_sqrt_hint', tv.get('dleq_r1_sqrt_hint'))
    if r1_sqrt:
        calldata.extend(u256_to_felts(r1_sqrt))
    else:
        calldata.extend(["0x72a9698d3171817c239f4009cc36fc97", "0x3f2b84592a9ee701d24651e3aa3c837d"])
    
    # 17. dleq_r2_compressed (u256)
    r2_compressed = tv.get('dleq_r2_compressed', tv.get('r2_compressed'))
    if r2_compressed:
        calldata.extend(u256_to_felts(r2_compressed))
    else:
        calldata.extend(["0x02d386e8fd6bd85a339171211735bcba", "0x10defc0130a9f3055798b1f5a99aeb67"])
    
    # 18. dleq_r2_sqrt_hint (u256)
    r2_sqrt = hints.get('r2_sqrt_hint', tv.get('dleq_r2_sqrt_hint'))
    if r2_sqrt:
        calldata.extend(u256_to_felts(r2_sqrt))
    else:
        calldata.extend(["0x43f2c451f9ca69ff1577d77d646a50e", "0x4ee64b0e07d89e906f9e8b7bea09283e"])
    
    # Output calldata
    print(" ".join(calldata))
    
    # Also save to file for reference
    output_file = Path(__file__).parent.parent / "deployments" / "sepolia" / "latest_calldata.txt"
    output_file.parent.mkdir(parents=True, exist_ok=True)
    with open(output_file, 'w') as f:
        f.write(" ".join(calldata))
    print(f"\n# Calldata saved to: {output_file}", file=sys.stderr)

if __name__ == "__main__":
    main()

