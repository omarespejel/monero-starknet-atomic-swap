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

import { Account, CallData, RpcProvider, hash, ec, constants } from "starknet";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const rootDir = join(__dirname, "..");

type NetworkName = "sepolia" | "mainnet";

const NETWORK = (process.env.STARKNET_NETWORK || "sepolia") as NetworkName;
if (NETWORK !== "sepolia" && NETWORK !== "mainnet") {
  throw new Error("STARKNET_NETWORK must be 'sepolia' or 'mainnet'");
}

const RPC_URLS =
  process.env.STARKNET_RPC_URL
    ? [process.env.STARKNET_RPC_URL]
    : NETWORK === "sepolia"
      ? [
          "https://api.zan.top/public/starknet-sepolia/rpc/v0_10",
          "https://free-rpc.nethermind.io/sepolia-juno",
        ]
      : [];

if (NETWORK === "mainnet" && RPC_URLS.length === 0) {
  throw new Error("Mainnet deployment requires STARKNET_RPC_URL");
}

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

interface AtomicLockConfig {
  token: string;
  amount: bigint;
  depositor: string;
  allowZeroLock: boolean;
}

interface DeploymentResult {
  contractAddress: string;
  lockUntil: number;
}

const PUBLIC_CANONICAL_TEST_SECRET =
  "1212121212121212121212121212121212121212121212121212121212121212";

function redactRpcUrl(raw: string): string {
  try {
    const url = new URL(raw);
    const pathParts = url.pathname.split("/");
    const last = pathParts[pathParts.length - 1];
    if (/^[A-Za-z0-9_-]{20,}$/.test(last)) {
      pathParts[pathParts.length - 1] = "<redacted>";
      url.pathname = pathParts.join("/");
    }
    if (url.search) {
      url.search = "?<redacted>";
    }
    return url.toString();
  } catch {
    return raw;
  }
}

function parseBoolEnv(name: string): boolean {
  return process.env[name] === "1" || process.env[name]?.toLowerCase() === "true";
}

/**
 * Initialize RPC provider with fallback endpoints
 */
async function initializeProvider(): Promise<RpcProvider> {
  for (const rpcUrl of RPC_URLS) {
    const safeRpcUrl = redactRpcUrl(rpcUrl);
    try {
      console.log(`Trying RPC: ${safeRpcUrl}...`);
      const provider = new RpcProvider({ nodeUrl: rpcUrl });

      // Test connection
      const chainId = await provider.getChainId();
      console.log(`✅ Connected to ${safeRpcUrl} (Chain ID: ${chainId})`);
      return provider;
    } catch (error: any) {
      console.log(`❌ Failed via ${safeRpcUrl}: ${error.message?.substring(0, 100) || error}`);
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

  // Generate new key only when explicitly requested. Silent deployer-key
  // generation is risky for production rehearsals and can leave secrets on disk.
  if (!privateKey) {
    if (!parseBoolEnv("STARKNET_GENERATE_DEPLOYER")) {
      throw new Error(
        "Set STARKNET_ACCOUNT_ADDRESS and STARKNET_PRIVATE_KEY for signing, or set STARKNET_GENERATE_DEPLOYER=1 to create a new unfunded deployer key."
      );
    }
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
    "0x0"
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

  const account = new Account(
    provider,
    accountAddress,
    privateKeyHex,
    "1",
    constants.TRANSACTION_VERSION.V3
  );

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

function normalizeHex(value: string | number | bigint): string {
  if (typeof value === "bigint") {
    return `0x${value.toString(16)}`;
  }
  if (typeof value === "number") {
    return `0x${BigInt(value).toString(16)}`;
  }
  const trimmed = value.trim();
  if (trimmed.startsWith("0x")) {
    return `0x${BigInt(trimmed).toString(16)}`;
  }
  return `0x${BigInt(trimmed).toString(16)}`;
}

function leBytesHexToBigInt(hexValue: string): bigint {
  const clean = hexValue.replace(/^0x/, "");
  const bytes = clean.match(/../g) || [];
  return BigInt(`0x${bytes.reverse().join("") || "0"}`);
}

function leBytesHexToU256Felts(hexValue: string): [string, string] {
  const clean = hexValue.replace(/^0x/, "").padStart(64, "0");
  const low = leBytesHexToBigInt(clean.slice(0, 32));
  const high = leBytesHexToBigInt(clean.slice(32, 64));
  return [normalizeHex(low), normalizeHex(high)];
}

function u256FromParts(value: { low: string; high: string }): [string, string] {
  return [normalizeHex(value.low), normalizeHex(value.high)];
}

function bigintToU256(value: bigint): [string, string] {
  const mask128 = (1n << 128n) - 1n;
  return [normalizeHex(value & mask128), normalizeHex(value >> 128n)];
}

function parseHashlockWords(hashlockHex: string): string[] {
  const clean = hashlockHex.replace(/^0x/, "");
  if (clean.length !== 64) {
    throw new Error("hashlock must be 32 bytes");
  }
  const words: string[] = [];
  for (let i = 0; i < clean.length; i += 8) {
    words.push(`0x${clean.slice(i, i + 8)}`);
  }
  return words;
}

function parseHintArray(cairoArray: string): string[] {
  const values = cairoArray.match(/0x[0-9a-fA-F]+/g);
  if (!values || values.length !== 10) {
    throw new Error(`expected 10 hint felts, got ${values?.length ?? 0}`);
  }
  return values.map(normalizeHex);
}

function loadJson(relativePath: string): any {
  const fullPath = join(rootDir, relativePath);
  if (!existsSync(fullPath)) {
    throw new Error(`Missing ${relativePath}. Run: uv run --project tools python tools/regenerate_dleq_hints.py`);
  }
  return JSON.parse(readFileSync(fullPath, "utf-8"));
}

function getAtomicLockConfig(defaultDepositor = "0x0"): AtomicLockConfig {
  const token = normalizeHex(process.env.ATOMIC_SWAP_TOKEN_ADDRESS || "0x0");
  const amount = BigInt(process.env.ATOMIC_SWAP_AMOUNT || "0");
  const depositor = normalizeHex(process.env.ATOMIC_SWAP_DEPOSITOR || defaultDepositor);
  const allowZeroLock = parseBoolEnv("ATOMIC_SWAP_ALLOW_ZERO_LOCK");
  return { token, amount, depositor, allowZeroLock };
}

function buildAtomicLockConstructorCalldata(lockUntil: number, depositor: string): string[] {
  const testVectors = loadJson("rust/test_vectors.json");
  const generated = loadJson("cairo/generated_dleq_vectors.json");
  const hints = loadJson("cairo/test_hints.json");
  const adaptorHint = loadJson("cairo/adaptor_point_hint.json");

  const { token, amount, allowZeroLock } = getAtomicLockConfig(depositor);
  if (!allowZeroLock && (token === "0x0" || amount === 0n)) {
    throw new Error(
      "Set ATOMIC_SWAP_TOKEN_ADDRESS and ATOMIC_SWAP_AMOUNT, or set ATOMIC_SWAP_ALLOW_ZERO_LOCK=1 for a zero-value test deployment"
    );
  }

  const calldata: string[] = [];
  const pushSpan = (values: string[]) => {
    calldata.push(normalizeHex(values.length));
    calldata.push(...values.map(normalizeHex));
  };
  const pushU256 = ([low, high]: [string, string]) => {
    calldata.push(normalizeHex(low), normalizeHex(high));
  };

  pushSpan(parseHashlockWords(testVectors.hashlock));
  calldata.push(normalizeHex(lockUntil));
  calldata.push(normalizeHex(depositor));
  calldata.push(token);
  pushU256(bigintToU256(amount));

  pushU256(leBytesHexToU256Felts(testVectors.adaptor_point_compressed));
  pushU256(u256FromParts(generated.sqrt_hints.adaptor_point_sqrt_hint));
  pushU256(leBytesHexToU256Felts(testVectors.second_point_compressed));
  pushU256(u256FromParts(generated.sqrt_hints.second_point_sqrt_hint));

  calldata.push(normalizeHex(generated.challenge));
  pushU256(u256FromParts(generated.response));

  pushSpan(parseHintArray(adaptorHint.cairo_format));
  pushSpan(parseHintArray(hints.cairo_hints.s_hint_for_g));
  pushSpan(parseHintArray(hints.cairo_hints.s_hint_for_y));
  pushSpan(parseHintArray(hints.cairo_hints.c_neg_hint_for_t));
  pushSpan(parseHintArray(hints.cairo_hints.c_neg_hint_for_u));

  pushU256(leBytesHexToU256Felts(testVectors.r1_compressed));
  pushU256(u256FromParts(generated.sqrt_hints.r1_sqrt_hint));
  pushU256(leBytesHexToU256Felts(testVectors.r2_compressed));
  pushU256(u256FromParts(generated.sqrt_hints.r2_sqrt_hint));

  return calldata;
}

function u256FeltsToBigint(values: string[]): bigint {
  if (values.length < 2) {
    throw new Error(`expected u256 response, got ${values.length} felts`);
  }
  return BigInt(values[0]) + (BigInt(values[1]) << 128n);
}

async function erc20BalanceOf(
  provider: RpcProvider,
  token: string,
  account: string
): Promise<bigint> {
  const result = await provider.callContract({
    contractAddress: token,
    entrypoint: "balance_of",
    calldata: [account],
  });
  return u256FeltsToBigint(result as string[]);
}

function byteArrayCalldataFromHex(secretHex: string): string[] {
  const clean = secretHex.replace(/^0x/, "").toLowerCase();
  if (!/^[0-9a-f]+$/.test(clean) || clean.length !== 64) {
    throw new Error("ATOMIC_SWAP_SECRET_HEX must be exactly 32 bytes / 64 hex chars");
  }

  const fullWord = `0x${clean.slice(0, 62)}`;
  const pendingWord = `0x${clean.slice(62)}`;
  return ["0x1", normalizeHex(fullWord), normalizeHex(pendingWord), "0x1"];
}

function deploymentJsonPath(): string {
  return join(rootDir, "deployments/starknetjs_deployment.json");
}

function mergeDeploymentInfo(extra: Record<string, any>) {
  const deploymentPath = deploymentJsonPath();
  const current = existsSync(deploymentPath)
    ? JSON.parse(readFileSync(deploymentPath, "utf-8"))
    : {};
  writeFileSync(deploymentPath, JSON.stringify({ ...current, ...extra }, null, 2));
}

/**
 * Deploy contract instance (requires calldata)
 */
async function deployContract(
  config: DeploymentConfig,
  classHash: string
): Promise<DeploymentResult> {
  console.log("\n🚀 Deploying contract instance...");

  const lockUntil = Math.floor(Date.now() / 1000) + 3600 * 4; // 4 hours
  const depositor = getAtomicLockConfig(config.accountAddress).depositor;
  const constructorCalldata = buildAtomicLockConstructorCalldata(lockUntil, depositor);
  console.log(`✅ Built constructor calldata (${constructorCalldata.length} felts) for ${NETWORK}`);

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
    const deploymentPath = deploymentJsonPath();
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
          network: NETWORK,
          depositor,
          token: getAtomicLockConfig().token,
          amount: getAtomicLockConfig().amount.toString(),
          timestamp: new Date().toISOString(),
        },
        null,
        2
      )
    );

    console.log(`💾 Saved to ${deploymentPath}`);

    return { contractAddress, lockUntil };
  } catch (error: any) {
    console.error("❌ Deployment failed:", error.message);
    throw error;
  }
}

async function approveAndDepositIfRequested(
  config: DeploymentConfig,
  contractAddress: string
): Promise<Record<string, any> | null> {
  if (!parseBoolEnv("ATOMIC_SWAP_DEPOSIT")) {
    return null;
  }

  const { token, amount } = getAtomicLockConfig();
  if (token === "0x0" || amount === 0n) {
    throw new Error("ATOMIC_SWAP_DEPOSIT=1 requires non-zero ATOMIC_SWAP_TOKEN_ADDRESS and ATOMIC_SWAP_AMOUNT");
  }

  console.log("\n💰 Approving and depositing tokens...");
  console.log(`   Token: ${token}`);
  console.log(`   Amount: ${amount.toString()}`);

  const balanceBefore = await erc20BalanceOf(config.provider, token, config.accountAddress);
  console.log(`   Account token balance before: ${balanceBefore.toString()}`);
  if (balanceBefore < amount) {
    throw new Error(`insufficient token balance for deposit: have ${balanceBefore}, need ${amount}`);
  }

  const approveTx = await config.account.execute({
    contractAddress: token,
    entrypoint: "approve",
    calldata: [contractAddress, ...bigintToU256(amount)],
  });
  console.log(`📤 Approve TX: ${approveTx.transaction_hash}`);
  await config.provider.waitForTransaction(approveTx.transaction_hash);

  const depositTx = await config.account.execute({
    contractAddress,
    entrypoint: "deposit",
    calldata: [],
  });
  console.log(`📤 Deposit TX: ${depositTx.transaction_hash}`);
  await config.provider.waitForTransaction(depositTx.transaction_hash);

  const contractBalance = await erc20BalanceOf(config.provider, token, contractAddress);
  console.log(`✅ Contract token balance after deposit: ${contractBalance.toString()}`);

  return {
    deposit: {
      approveTx: approveTx.transaction_hash,
      depositTx: depositTx.transaction_hash,
      token,
      amount: amount.toString(),
      contractTokenBalance: contractBalance.toString(),
    },
  };
}

async function revealIfRequested(
  config: DeploymentConfig,
  contractAddress: string
): Promise<Record<string, any> | null> {
  if (!parseBoolEnv("ATOMIC_SWAP_REVEAL")) {
    return null;
  }

  const secretHex = (process.env.ATOMIC_SWAP_SECRET_HEX || PUBLIC_CANONICAL_TEST_SECRET).replace(/^0x/, "");
  console.log("\n🔓 Revealing secret on Starknet...");
  const revealTx = await config.account.execute({
    contractAddress,
    entrypoint: "reveal_secret",
    calldata: byteArrayCalldataFromHex(secretHex),
  });
  console.log(`📤 Reveal TX: ${revealTx.transaction_hash}`);
  await config.provider.waitForTransaction(revealTx.transaction_hash);

  const revealed = await config.provider.callContract({
    contractAddress,
    entrypoint: "is_secret_revealed",
    calldata: [],
  });
  const claimableAfter = await config.provider.callContract({
    contractAddress,
    entrypoint: "get_claimable_after",
    calldata: [],
  });
  console.log(`✅ Secret revealed. claimable_after=${claimableAfter[0]}`);

  return {
    reveal: {
      revealTx: revealTx.transaction_hash,
      secretHex,
      isSecretRevealed: revealed[0],
      claimableAfter: claimableAfter[0],
    },
  };
}

function enforcePublicTestSecretGuard() {
  const { amount } = getAtomicLockConfig();
  const secretHex = (process.env.ATOMIC_SWAP_SECRET_HEX || PUBLIC_CANONICAL_TEST_SECRET).replace(/^0x/, "");
  const usesPublicSecret = secretHex === PUBLIC_CANONICAL_TEST_SECRET;
  const touchesTokens = amount > 0n || parseBoolEnv("ATOMIC_SWAP_DEPOSIT");
  if (usesPublicSecret && touchesTokens && !parseBoolEnv("ATOMIC_SWAP_CONFIRM_PUBLIC_TEST_SECRET")) {
    throw new Error(
      "This deployment uses the public canonical test secret. For any non-zero token rehearsal, set ATOMIC_SWAP_CONFIRM_PUBLIC_TEST_SECRET=1 and use only a tiny test amount, or provide ATOMIC_SWAP_SECRET_HEX with a private per-swap vector package."
    );
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
    enforcePublicTestSecretGuard();

    // 1. Initialize provider
    const provider = await initializeProvider();

    // 2. Get/generate private key
    const privateKey = getPrivateKey();

    // 3. Initialize account
    const config = await initializeAccount(provider, privateKey);

    // 4. Declare contract
    const classHash = await declareContract(config);

    // 5. Deploy contract
    const deployment = await deployContract(config, classHash);

    const postDeploy: Record<string, any> = {};
    Object.assign(postDeploy, await approveAndDepositIfRequested(config, deployment.contractAddress));
    Object.assign(postDeploy, await revealIfRequested(config, deployment.contractAddress));
    if (Object.keys(postDeploy).length > 0) {
      mergeDeploymentInfo({ postDeploy });
    }

    console.log("\n" + "=".repeat(70));
    console.log("✅ DEPLOYMENT COMPLETE!");
    console.log("=".repeat(70));
    console.log(`Contract Address: ${deployment.contractAddress}`);
    console.log(`Class Hash: ${classHash}`);
    const explorerPrefix = NETWORK === "mainnet" ? "https://starkscan.co" : "https://sepolia.starkscan.co";
    console.log(`Explorer: ${explorerPrefix}/contract/${deployment.contractAddress}`);
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
