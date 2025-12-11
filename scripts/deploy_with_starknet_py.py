#!/usr/bin/env python3
"""
Deploy AtomicLock contract using starknet.py

Bypasses starkli CASM hash issues by using starknet.py's internal computation.
Uses uv for dependency management.
"""

import asyncio
import json
import sys
from pathlib import Path

try:
    from starknet_py.contract import Contract
    from starknet_py.net.account.account import Account
    from starknet_py.net.full_node_client import FullNodeClient
    from starknet_py.net.models import StarknetChainId
    from starknet_py.net.signer.stark_curve_signer import KeyPair
    from starknet_py.net.client_models import ResourceBounds, ResourceBoundsMapping
except ImportError:
    print("ERROR: starknet-py not installed")
    print("Install with: uv pip install starknet-py")
    sys.exit(1)

# Configuration
RPC_URL = "https://api.zan.top/public/starknet-sepolia"
# Alternative: "https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_7/cf52O0RwFy1mEB0uoYsel"

async def main():
    # === 1. Setup Client and Account ===
    print("=== Connecting to Starknet Sepolia ===")
    client = FullNodeClient(node_url=RPC_URL)
    
    # Try to auto-detect account address from account.json
    account_json_path = Path.home() / ".starkli-wallets" / "deployer" / "account.json"
    ACCOUNT_ADDRESS = None
    
    if account_json_path.exists():
        try:
            with open(account_json_path, "r") as f:
                account_data = json.load(f)
                if "deployment" in account_data and "address" in account_data["deployment"]:
                    ACCOUNT_ADDRESS = account_data["deployment"]["address"]
                    print(f"✅ Auto-detected account address: {ACCOUNT_ADDRESS}")
        except Exception as e:
            print(f"⚠️ Could not auto-detect account address: {e}")
    
    # Get account details
    print("\nEnter deployer account details:")
    print("(You can extract private key with: starkli signer keystore inspect ~/.starkli-wallets/deployer/keystore.json --raw)")
    PRIVATE_KEY = input("Enter deployer private key (hex, without 0x): ").strip().replace("0x", "")
    
    if not ACCOUNT_ADDRESS:
        ACCOUNT_ADDRESS = input("Enter deployer account address (hex, without 0x): ").strip().replace("0x", "")
    
    if not PRIVATE_KEY or not ACCOUNT_ADDRESS:
        print("ERROR: Private key and account address are required")
        return
    
    try:
        key_pair = KeyPair.from_private_key(int(PRIVATE_KEY, 16))
        account = Account(
            client=client,
            address=int(ACCOUNT_ADDRESS, 16),
            key_pair=key_pair,
            chain=StarknetChainId.SEPOLIA,
        )
        
        print(f"✅ Account configured: {hex(account.address)}")
    except Exception as e:
        print(f"❌ Failed to setup account: {e}")
        return
    
    # === 2. Load Compiled Contract ===
    script_dir = Path(__file__).parent
    cairo_dir = script_dir.parent / "cairo" / "target" / "dev"
    
    sierra_path = cairo_dir / "atomic_lock_AtomicLock.contract_class.json"
    casm_path = cairo_dir / "atomic_lock_AtomicLock.compiled_contract_class.json"
    
    if not sierra_path.exists():
        print(f"❌ ERROR: Sierra file not found: {sierra_path}")
        print("Run: cd cairo && scarb build")
        return
    
    if not casm_path.exists():
        print(f"❌ ERROR: CASM file not found: {casm_path}")
        print("Run: cd cairo && scarb build")
        return
    
    print(f"\n✅ Loaded Sierra: {sierra_path}")
    print(f"✅ Loaded CASM: {casm_path}")
    
    with open(sierra_path, "r") as f:
        sierra_compiled = f.read()
    
    with open(casm_path, "r") as f:
        casm_compiled = f.read()
    
    # === 3. Declare Contract ===
    print("\n=== Declaring contract... ===")
    
    # Resource bounds for Sepolia
    resource_bounds = ResourceBoundsMapping(
        l1_gas=ResourceBounds(max_amount=50000, max_price_per_unit=100000000000),
        l2_gas=ResourceBounds(max_amount=0, max_price_per_unit=0),
        l1_data_gas=ResourceBounds(max_amount=50000, max_price_per_unit=100000000000),
    )
    
    try:
        declare_result = await Contract.declare_v3(
            account=account,
            compiled_contract=sierra_compiled,
            compiled_contract_casm=casm_compiled,
            resource_bounds=resource_bounds,
        )
        
        print(f"⏳ Waiting for transaction acceptance...")
        await declare_result.wait_for_acceptance()
        
        class_hash = declare_result.class_hash
        print(f"\n✅ Contract declared successfully!")
        print(f"   Class hash: {hex(class_hash)}")
        print(f"   Transaction hash: {hex(declare_result.hash)}")
        
    except Exception as e:
        error_str = str(e)
        print(f"\n❌ Declaration failed: {e}")
        
        if "already declared" in error_str.lower():
            print("\n⚠️ Contract already declared, computing class hash...")
            try:
                from starknet_py.hash.class_hash import compute_class_hash
                sierra_json = json.loads(sierra_compiled)
                class_hash = compute_class_hash(sierra_json)
                print(f"✅ Class hash: {hex(class_hash)}")
            except Exception as compute_error:
                print(f"❌ Failed to compute class hash: {compute_error}")
                return
        else:
            print(f"\nFull error details:")
            import traceback
            traceback.print_exc()
            return
    
    # === 4. Save Results ===
    result = {
        "class_hash": hex(class_hash),
        "rpc_url": RPC_URL,
        "status": "declared",
        "account_address": hex(account.address),
    }
    
    output_path = script_dir.parent / "deployments" / "starknet_py_result.json"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_path, "w") as f:
        json.dump(result, f, indent=2)
    
    print(f"\n✅ Result saved to: {output_path}")
    print("\n📋 Next steps:")
    print(f"1. Class hash: {hex(class_hash)}")
    print("2. Generate deployment calldata:")
    print("   python3 tools/generate_deploy_calldata.py")
    print("3. Deploy contract instance using the class hash and calldata")

if __name__ == "__main__":
    asyncio.run(main())

