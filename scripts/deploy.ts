#!/usr/bin/env bun

/**
 * AtomicLock Deployment Script - Starknet.js + Bun
 * 
 * Modern deployment using:
 * - starknet.js v6 (most stable for Sepolia)
 * - Bun runtime (fast TypeScript execution)
 * - Direct private key management (no keystore issues)
 * 
 * Usage:
 *   export STARKNET_PRIVATE_KEY="your_hex_key_without_0x"
 *   bun run scripts/deploy.ts
 */

import {
  Account,
  CallData,
  Contract,
  RpcProvider,
  cairo,
  hash,
  ec,
  num,
  stark,
  constants,
} from "starknet";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const rootDir = join(__dirname, "..");

// RPC Configuration - Multiple endpoints for reliability
// Alchemy v0.10 RPC (compatible with sncast and starknet.js v6)
const RPC_URLS = [
  "https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_10/cf52O0RwFy1mEB0uoYsel",
  "https://api.zan.top/public/starknet-sepolia",
  "https://free-rpc.nethermind.io/sepolia-juno",
];

// OpenZeppelin Account class hash for Sepolia
// Note: If this class is not declared, use a pre-deployed account instead
const OZ_ACCOUNT_CLASS_HASH =
  "0x01bd7c78bd731400989b0f6eb4f0e0b6e471f7b5ee0030f5bca87d1e4b61c0e";

interface DeploymentConfig {
  provider: RpcProvider;
  account: Account;
  accountAddress: string;
  privateKey: string;
}

/**
 * Initialize RPC provider with fallback endpoints
 */
async function initializeProvider(): Promise<RpcProvider> {
  for (const rpcUrl of RPC_URLS) {
    try {
      console.log(`Trying RPC: ${rpcUrl}...`);
      const provider = new RpcProvider({ nodeUrl: rpcUrl });

      // Test connection
      const chainId = await provider.getChainId();
      console.log(`✅ Connected to ${rpcUrl} (Chain ID: ${chainId})`);
      return provider;
    } catch (error: any) {
      console.log(`❌ Failed: ${error.message?.substring(0, 100) || error}`);
      if (rpcUrl === RPC_URLS[RPC_URLS.length - 1]) {
        throw new Error("All RPC endpoints failed");
      }
    }
  }
  throw new Error("Failed to initialize provider");
}

/**
 * Load or generate private key
 * Also supports using a pre-deployed account address
 */
function getPrivateKey(): string | null {
  const keyFile = join(rootDir, ".deployer_key");

  // Try environment variable first
  let privateKey = process.env.STARKNET_PRIVATE_KEY?.replace("0x", "");

  // Try saved key file
  if (!privateKey && existsSync(keyFile)) {
    try {
      privateKey = readFileSync(keyFile, "utf-8").trim().replace("0x", "");
      console.log("📄 Loaded private key from .deployer_key");
    } catch (error: any) {
      console.log("⚠️  Could not load saved key");
    }
  }

  // If no private key and user wants to use pre-deployed account
  if (!privateKey && process.env.STARKNET_ACCOUNT_ADDRESS) {
    console.log("📋 Using pre-deployed account from STARKNET_ACCOUNT_ADDRESS");
    return null; // Signal to use pre-deployed account
  }

  // Generate new key if needed
  if (!privateKey) {
    console.log("🔑 Generating new private key...");
    // Generate a valid Starknet private key using starknet.js
    // randomPrivateKey() returns Uint8Array, convert to hex
    const keyBytes = ec.starkCurve.utils.randomPrivateKey();
    privateKey = Array.from(keyBytes)
      .map((b) => b.toString(16).padStart(2, "0"))
      .join("");

    // Save with restricted permissions
    try {
      writeFileSync(keyFile, privateKey, { mode: 0o600 });
      console.log(`✅ Saved private key to ${keyFile}`);
      console.log("⚠️  IMPORTANT: Keep this key secure!");
    } catch (error: any) {
      console.log(`⚠️  Could not save key: ${error.message}`);
      console.log(`💾 Save manually: ${privateKey}`);
    }
  }

  return privateKey;
}

/**
 * Compute counterfactual account address
 */
function computeAccountAddress(publicKey: string): string {
  const constructorCalldata = CallData.compile({
    public_key: publicKey,
  });

  const address = hash.calculateContractAddressFromHash(
    publicKey, // salt
    OZ_ACCOUNT_CLASS_HASH,
    constructorCalldata,
    constants.StarknetChainId.SN_SEPOLIA
  );

  return address;
}

/**
 * Initialize account (counterfactual or deployed)
 * Supports both new account deployment and pre-deployed accounts
 */
async function initializeAccount(
  provider: RpcProvider,
  privateKey: string | null
): Promise<DeploymentConfig> {
  let accountAddress: string;
  let publicKey: string;
  let privateKeyHex: string;

  // Check if using pre-deployed account
  if (process.env.STARKNET_ACCOUNT_ADDRESS) {
    accountAddress = process.env.STARKNET_ACCOUNT_ADDRESS.replace("0x", "");
    if (!accountAddress.startsWith("0x")) {
      accountAddress = `0x${accountAddress}`;
    }
    
    // For pre-deployed account, we still need private key for signing
    const envKey = process.env.STARKNET_PRIVATE_KEY?.replace("0x", "") || privateKey;
    if (!envKey) {
      throw new Error("STARKNET_ACCOUNT_ADDRESS provided but STARKNET_PRIVATE_KEY is required for signing");
    }
    privateKeyHex = envKey.startsWith("0x") ? envKey : `0x${envKey}`;
    publicKey = ec.starkCurve.getStarkKey(privateKeyHex);
    
    console.log("📋 Using pre-deployed account");
  } else {
    if (!privateKey) {
      throw new Error("Private key is required");
    }
    // Ensure private key has 0x prefix for starknet.js
    privateKeyHex = privateKey.startsWith("0x") ? privateKey : `0x${privateKey}`;
    publicKey = ec.starkCurve.getStarkKey(privateKeyHex);
    accountAddress = computeAccountAddress(publicKey);
  }

  const account = new Account(provider, accountAddress, privateKeyHex, "1");

  console.log("\n📍 Account Configuration:");
  console.log(`   Address: ${accountAddress}`);
  console.log(`   Public Key: ${publicKey.startsWith("0x") ? publicKey : `0x${publicKey}`}`);

  // Check if account is deployed by trying to get balance
  let accountDeployed = false;
  const isPreDeployed = !!process.env.STARKNET_ACCOUNT_ADDRESS;
  
  try {
    const balance = await provider.getBalance(accountAddress);
    const balanceInEth = Number(balance) / 1e18;

    console.log(`✅ Account deployed! Balance: ${balanceInEth.toFixed(6)} ETH`);
    accountDeployed = true;

    if (balanceInEth < 0.001) {
      console.log("⚠️  Low balance! Fund at https://starknet-faucet.vercel.app");
    }
  } catch (error: any) {
    // If using pre-deployed account, assume it's deployed even if balance check fails
    if (isPreDeployed) {
      console.log("📋 Using pre-deployed account (assuming deployed)");
      console.log(`   Address: ${accountAddress}`);
      accountDeployed = true;
    } else {
      // Account contract not deployed - need to deploy it
      console.log("📋 Account contract needs deployment");
      console.log(`   Address: ${accountAddress}`);
      console.log("   Attempting to deploy account contract...");
      
      try {
      // Deploy OpenZeppelin account contract
      // deployAccount() works even if account isn't deployed yet (counterfactual deployment)
      const deployAccountResponse = await account.deployAccount({
        classHash: OZ_ACCOUNT_CLASS_HASH,
        constructorCalldata: CallData.compile({
          public_key: publicKey,
        }),
        addressSalt: publicKey,
      });
      
      console.log(`📤 Account deployment TX: ${deployAccountResponse.transaction_hash}`);
      console.log("⏳ Waiting for account deployment...");
      
      await provider.waitForTransaction(deployAccountResponse.transaction_hash);
      
      console.log(`✅ Account contract deployed!`);
      accountDeployed = true;
    } catch (deployError: any) {
      const errorMsg = deployError.message?.toLowerCase() || "";
      if (errorMsg.includes("insufficient") || errorMsg.includes("balance")) {
        console.log("\n❌ Insufficient balance to deploy account contract");
        console.log(`   Account address: ${accountAddress}`);
        console.log(`   Please fund this address and re-run the script`);
        console.log(`   Faucet: https://starknet-faucet.vercel.app`);
        process.exit(0);
      } else if (errorMsg.includes("already deployed") || errorMsg.includes("contract already exists")) {
        console.log("✅ Account contract already deployed");
        accountDeployed = true;
      } else if (errorMsg.includes("class") && (errorMsg.includes("not declared") || errorMsg.includes("is not declared"))) {
        console.log("\n❌ Account class not declared on Sepolia");
        console.log("   This is a network requirement - the Account class must be declared first");
        console.log("\n💡 SOLUTION: Use a pre-deployed account");
        console.log("   1. Get an account address that's already deployed on Sepolia");
        console.log("   2. Set environment variables:");
        console.log("      export STARKNET_ACCOUNT_ADDRESS=0x<your_deployed_account>");
        console.log("      export STARKNET_PRIVATE_KEY=0x<private_key_for_that_account>");
        console.log("   3. Run: bun run deploy");
        console.log("\n   Or wait for the Account class to be declared on Sepolia");
        throw new Error("Account class not declared. Use a pre-deployed account or declare Account class first.");
      } else {
        console.log(`❌ Account deployment failed: ${deployError.message}`);
        throw deployError;
      }
      }
    }
  }
  
  if (!accountDeployed) {
    console.log("\n❌ Could not verify or deploy account contract");
    process.exit(1);
  }

  return {
    provider,
    account,
    accountAddress,
    privateKey: privateKeyHex.replace("0x", ""),
  };
}

/**
 * Declare contract
 */
async function declareContract(config: DeploymentConfig): Promise<string> {
  console.log("\n📄 Declaring contract...");

  const sierraPath = join(
    rootDir,
    "cairo/target/dev/atomic_lock_AtomicLock.contract_class.json"
  );
  const casmPath = join(
    rootDir,
    "cairo/target/dev/atomic_lock_AtomicLock.compiled_contract_class.json"
  );

  if (!existsSync(sierraPath) || !existsSync(casmPath)) {
    throw new Error("Contract not compiled. Run: cd cairo && scarb build");
  }

  const sierraCode = JSON.parse(readFileSync(sierraPath, "utf-8"));
  const casmCode = JSON.parse(readFileSync(casmPath, "utf-8"));

  console.log("✅ Loaded Sierra and CASM");

  try {
    // Declare contract with explicit fee settings to avoid fee estimation issues
    // Try declaring without explicit version first (let starknet.js handle it)
    const declareResponse = await config.account.declare({
      contract: sierraCode,
      casm: casmCode,
    });

    console.log(`📤 Declaration TX: ${declareResponse.transaction_hash}`);
    console.log("⏳ Waiting for acceptance...");

    await config.provider.waitForTransaction(declareResponse.transaction_hash);

    const classHash = declareResponse.class_hash;
    console.log(`✅ Contract declared! Class Hash: ${classHash}`);

    // Save class hash
    const resultPath = join(rootDir, "deployments/starknetjs_result.json");
    const resultDir = dirname(resultPath);
    if (!existsSync(resultDir)) {
      const { mkdirSync } = await import("fs");
      mkdirSync(resultDir, { recursive: true });
    }

    writeFileSync(
      resultPath,
      JSON.stringify(
        {
          classHash,
          transactionHash: declareResponse.transaction_hash,
          rpcUrl: (config.provider as any).nodeUrl,
          accountAddress: config.accountAddress,
          timestamp: new Date().toISOString(),
        },
        null,
        2
      )
    );

    console.log(`💾 Saved to ${resultPath}`);

    return classHash;
  } catch (error: any) {
    if (error.message?.includes("already declared")) {
      console.log("⚠️  Contract already declared");
      // Compute class hash manually
      const classHash = hash.computeContractClassHash(sierraCode);
      console.log(`📋 Class Hash: ${classHash}`);
      return classHash;
    }
    throw error;
  }
}

/**
 * Deploy contract instance (requires calldata)
 */
async function deployContract(
  config: DeploymentConfig,
  classHash: string
): Promise<string> {
  console.log("\n🚀 Deploying contract instance...");

  // Load test vectors for constructor
  // Try multiple possible paths
  const testVectorsPaths = [
    join(rootDir, "rust/test_vectors.json"),
    join(rootDir, "rust/deployment_vector.json"),
  ];
  
  let testVectors: any = null;
  for (const path of testVectorsPaths) {
    if (existsSync(path)) {
      testVectors = JSON.parse(readFileSync(path, "utf-8"));
      console.log(`✅ Loaded test vectors from ${path}`);
      break;
    }
  }
  
  if (!testVectors) {
    throw new Error("Test vectors not found. Generate with: cd rust && cargo run --bin generate_test_vector");
  }

  // Prepare constructor calldata
  const lockUntil = Math.floor(Date.now() / 1000) + 3600 * 4; // 4 hours

  // Handle different test vector formats
  const hashlock = testVectors.hashlock || testVectors.hashlock_words;
  const adaptorPointCompressed = testVectors.adaptor_point_compressed || testVectors.adaptor_point;
  const adaptorPointHint = testVectors.adaptor_point_sqrt_hint || testVectors.adaptor_point_hint;
  const challenge = testVectors.challenge || testVectors.challenge_low;
  const response = testVectors.response || testVectors.response_low;

  const constructorCalldata = CallData.compile({
    hashlock: hashlock,
    lock_until: cairo.uint256(lockUntil),
    token: "0x0", // Zero address for testing
    amount: cairo.uint256(0), // Zero amount for testing
    adaptor_point_compressed: adaptorPointCompressed,
    adaptor_point_hint: adaptorPointHint,
    challenge: challenge,
    response: response,
  });

  try {
    const deployResponse = await config.account.deployContract({
      classHash,
      constructorCalldata,
    });

    console.log(`📤 Deployment TX: ${deployResponse.transaction_hash}`);
    console.log("⏳ Waiting for acceptance...");

    await config.provider.waitForTransaction(deployResponse.transaction_hash);

    const contractAddress = deployResponse.contract_address;
    console.log(`✅ Contract deployed! Address: ${contractAddress}`);

    // Save deployment info
    const deploymentPath = join(
      rootDir,
      "deployments/starknetjs_deployment.json"
    );
    const deploymentDir = dirname(deploymentPath);
    if (!existsSync(deploymentDir)) {
      const { mkdirSync } = await import("fs");
      mkdirSync(deploymentDir, { recursive: true });
    }

    writeFileSync(
      deploymentPath,
      JSON.stringify(
        {
          contractAddress,
          classHash,
          transactionHash: deployResponse.transaction_hash,
          lockUntil,
          network: "sepolia",
          timestamp: new Date().toISOString(),
        },
        null,
        2
      )
    );

    console.log(`💾 Saved to ${deploymentPath}`);

    return contractAddress;
  } catch (error: any) {
    console.error("❌ Deployment failed:", error.message);
    throw error;
  }
}

/**
 * Main deployment flow
 */
async function main() {
  console.log("=".repeat(70));
  console.log("XMR↔Starknet Atomic Swap - Deployment (starknet.js + Bun)");
  console.log("=".repeat(70));

  try {
    // 1. Initialize provider
    const provider = await initializeProvider();

    // 2. Get/generate private key
    const privateKey = getPrivateKey();

    // 3. Initialize account
    const config = await initializeAccount(provider, privateKey);

    // 4. Declare contract
    const classHash = await declareContract(config);

    // 5. Deploy contract
    const contractAddress = await deployContract(config, classHash);

    console.log("\n" + "=".repeat(70));
    console.log("✅ DEPLOYMENT COMPLETE!");
    console.log("=".repeat(70));
    console.log(`Contract Address: ${contractAddress}`);
    console.log(`Class Hash: ${classHash}`);
    console.log(`Explorer: https://sepolia.starkscan.co/contract/${contractAddress}`);
    console.log("=".repeat(70));
  } catch (error: any) {
    console.error("\n❌ Deployment failed:", error.message);
    if (error.stack) {
      console.error(error.stack);
    }
    process.exit(1);
  }
}

// Run main
main();

