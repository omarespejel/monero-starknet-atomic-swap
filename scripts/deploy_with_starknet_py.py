#!/usr/bin/env python3
"""
Deploy AtomicLock contract using starknet.py

Bypasses starkli CASM hash issues by using starknet.py's internal computation.
Uses uv for dependency management.

RECOMMENDED APPROACH (OpenZeppelin pattern):
  - Uses direct private key (no keystore password issues)
  - Standard for CI/CD and programmatic deployment
  - Matches production patterns used by OpenZeppelin Cairo contracts
  - Counterfactual account deployment (compute address before funding)

Usage:
  # Generate new key or use existing
  export STARKNET_PRIVATE_KEY=$(openssl rand -hex 32)
  
  # Or set existing key
  export STARKNET_PRIVATE_KEY='your_hex_key_without_0x'
  
  # Run deployment
  uv run python3 scripts/deploy_with_starknet_py.py
  
The script will compute the account address from the private key and prompt
you to fund it before deploying the contract.
"""

import asyncio
import json
import os
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
# Try multiple RPC endpoints for reliability
RPC_URLS = [
    "https://starknet-sepolia.public.blastapi.io",
    "https://api.zan.top/public/starknet-sepolia",
    "https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_7/cf52O0RwFy1mEB0uoYsel",
]
RPC_URL = RPC_URLS[0]  # Default to Blast API (most reliable)

async def main():
    # === 1. Setup Client and Account ===
    print("=== Connecting to Starknet Sepolia ===")
    print(f"Using RPC: {RPC_URL}")
    
    # Try to connect to RPC (simplified - just create client, test during actual operations)
    client = None
    for rpc_url in RPC_URLS:
        try:
            print(f"Trying RPC: {rpc_url}...")
            client = FullNodeClient(node_url=rpc_url)
            # Simple test - just try to get chain ID
            chain_id = await client.get_chain_id()
            print(f"✅ Connected to {rpc_url} (Chain ID: {chain_id})")
            break
        except Exception as e:
            print(f"⚠️ Failed to connect to {rpc_url}: {str(e)[:100]}...")
            if rpc_url != RPC_URLS[-1]:
                print("Trying next RPC endpoint...")
                continue
            else:
                print("❌ All RPC endpoints failed")
                print("\nTrying to proceed anyway - RPC may work for actual operations...")
                # Use the first RPC anyway - sometimes get_block fails but other operations work
                client = FullNodeClient(node_url=RPC_URLS[0])
                break
    
    if client is None:
        print("❌ Could not create RPC client")
        return
    
    # === 2. Get Private Key (Direct Approach - No Keystore) ===
    # Recommended by auditor: Use direct private key (matches OpenZeppelin's sncast pattern)
    # This avoids keystore password HMAC mismatch issues
    
    # Check for saved key file first
    script_dir = Path(__file__).parent
    key_file = script_dir.parent / ".deployer_key"
    
    PRIVATE_KEY = os.environ.get("STARKNET_PRIVATE_KEY", "").strip().replace("0x", "")
    
    # If no env var, try to load from saved file
    if not PRIVATE_KEY and key_file.exists():
        try:
            PRIVATE_KEY = key_file.read_text().strip().replace("0x", "")
            print(f"✅ Loaded private key from {key_file}")
        except Exception as e:
            print(f"⚠️ Could not load saved key: {e}")
    
    # If still no key, generate new one
    if not PRIVATE_KEY:
        print("\n" + "="*70)
        print("GENERATING NEW PRIVATE KEY")
        print("="*70)
        import secrets
        PRIVATE_KEY = secrets.token_hex(32)
        print(f"\n✅ Generated new private key")
        
        # Save key to file (with restricted permissions)
        try:
            key_file.write_text(PRIVATE_KEY)
            os.chmod(key_file, 0o600)  # Read/write for owner only
            print(f"✅ Saved private key to {key_file} (restricted permissions)")
            print(f"\n⚠️  IMPORTANT: Keep this key secure!")
            print(f"   Key file: {key_file}")
        except Exception as e:
            print(f"⚠️ Could not save key to file: {e}")
            print(f"   Please save this key manually: {PRIVATE_KEY}")
    
    if not PRIVATE_KEY:
        print("ERROR: Could not get or generate private key")
        return
    
    # === 3. Derive Account Address from Private Key ===
    # Compute account address from private key (counterfactual deployment pattern)
    try:
        key_pair = KeyPair.from_private_key(int(PRIVATE_KEY, 16))
        
        # For OpenZeppelin account, compute address from public key
        # This matches the counterfactual deployment pattern
        from starknet_py.net.account.account import compute_address
        from starknet_py.net.models import StarknetChainId
        
        # Use OpenZeppelin account class hash (standard for Sepolia)
        # This is the class hash for OpenZeppelin's Account contract
        OZ_ACCOUNT_CLASS_HASH = 0x01bd7c78bd731400989b0f6eb4f0e0b6e471f7b5ee0030f5bca87d1e4b61c0e
        
        # Compute address from public key (counterfactual)
        account_address = compute_address(
            class_hash=OZ_ACCOUNT_CLASS_HASH,
            constructor_calldata=[],
            salt=key_pair.public_key,
        )
        
        account = Account(
            client=client,
            address=account_address,
            key_pair=key_pair,
            chain=StarknetChainId.SEPOLIA,
        )
        
        print(f"✅ Account configured (counterfactual address): {hex(account.address)}")
        print(f"   Public key: {hex(key_pair.public_key)}")
        
        # Check if account is deployed by trying to get balance
        account_deployed = False
        try:
            account_balance = await account.get_balance()
            print(f"✅ Account is deployed! Balance: {account_balance / 1e18} ETH")
            account_deployed = True
        except Exception as balance_error:
            error_str = str(balance_error).lower()
            if "not found" in error_str or "not deployed" in error_str or "contract not found" in error_str:
                print(f"\n⚠️  Account contract not deployed yet.")
                print(f"   Account address: {hex(account.address)}")
                print(f"   Public key: {hex(key_pair.public_key)}")
                print(f"\n📋 NEXT STEPS:")
                print(f"   1. Fund this address: {hex(account.address)}")
                print(f"      Faucet: https://starknet-faucet.vercel.app/")
                print(f"   2. After funding, re-run this script to deploy account contract")
                print(f"   3. Then deploy AtomicLock contract")
                print(f"\n💾 Private key saved to: {key_file}")
                return
            else:
                # Account might be deployed but RPC issue - try to proceed
                print(f"⚠️  Could not check balance: {balance_error}")
                print(f"   Assuming account is deployed and proceeding...")
                account_deployed = True
        
        # If account not deployed but we have balance, deploy it
        if not account_deployed:
            try:
                # Try to deploy account contract
                print(f"\n🚀 Deploying account contract...")
                from starknet_py.net.account.account import deploy_account
                
                deploy_result = await deploy_account(
                    account=account,
                    class_hash=OZ_ACCOUNT_CLASS_HASH,
                    salt=key_pair.public_key,
                )
                print(f"⏳ Waiting for account deployment...")
                await deploy_result.wait_for_acceptance()
                print(f"✅ Account deployed! Transaction: {hex(deploy_result.hash)}")
                account_deployed = True
            except Exception as deploy_error:
                error_str = str(deploy_error).lower()
                if "insufficient" in error_str or "balance" in error_str:
                    print(f"\n❌ Insufficient balance to deploy account contract")
                    print(f"   Account address: {hex(account.address)}")
                    print(f"   Please fund this address and re-run the script")
                    return
                else:
                    print(f"⚠️  Account deployment failed: {deploy_error}")
                    print(f"   Account may already be deployed, proceeding...")
                    account_deployed = True
        
    except Exception as e:
        print(f"❌ Failed to setup account: {e}")
        print("\nTroubleshooting:")
        print("1. Ensure private key is valid hex (64 characters)")
        print("2. Check that account is deployed on Sepolia")
        print("3. Verify account has sufficient balance")
        import traceback
        traceback.print_exc()
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

