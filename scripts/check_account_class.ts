#!/usr/bin/env bun
/**
 * Check if Account class is declared on Sepolia
 */
import { RpcProvider } from "starknet";

const OZ_ACCOUNT_CLASS_HASH = "0x01bd7c78bd731400989b0f6eb4f0e0b6e471f7b5ee0030f5bca87d1e4b61c0e";
const RPC_URL = "https://api.zan.top/public/starknet-sepolia";

async function main() {
  console.log("Checking Account class status on Sepolia...\n");
  
  const provider = new RpcProvider({ nodeUrl: RPC_URL });
  
  try {
    const accountClass = await provider.getClassByHash(OZ_ACCOUNT_CLASS_HASH);
    console.log("✅ Account class IS declared on Sepolia!");
    console.log(`   Class hash: ${OZ_ACCOUNT_CLASS_HASH}`);
    console.log("   You can proceed with account deployment.");
  } catch (error: any) {
    console.log("❌ Account class NOT declared on Sepolia");
    console.log(`   Class hash: ${OZ_ACCOUNT_CLASS_HASH}`);
    console.log(`   Error: ${error.message}`);
    console.log("\n💡 Solutions:");
    console.log("   1. Use a pre-deployed account");
    console.log("   2. Wait for Account class to be declared");
    console.log("   3. Use a different Account implementation");
  }
}

main();

