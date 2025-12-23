import { RpcProvider, Account, ec, hash, CallData } from 'starknet';
import { declareContract } from './declare';
import { deployContract } from './deploy';
import * as fs from 'fs';
import * as path from 'path';

// Devnet configuration (from snfoundry.toml)
const DEVNET_RPC_URL = 'http://127.0.0.1:5050';
const DEVNET_ACCOUNT_ADDRESS = '0x049a5a5c30836ff78b3f9a2c0868eaabeeb1ca8ea049d2ed435ad42fd6315fba';
const DEVNET_PRIVATE_KEY = '0x000000000000000000000000000000001e010f076fad70290a3d89c1ec9dd269';

async function main() {
  console.log('=== Deploy AtomicLock to Devnet ===\n');

  // Connect to devnet
  console.log(`Connecting to devnet: ${DEVNET_RPC_URL}`);
  const provider = new RpcProvider({ nodeUrl: DEVNET_RPC_URL });
  
  try {
    const chainId = await provider.getChainId();
    console.log(`✅ Connected (Chain ID: ${chainId})\n`);
  } catch (e: any) {
    console.error(`❌ Failed to connect to devnet: ${e.message}`);
    console.error('Make sure devnet is running: ./scripts/devnet.sh start');
    process.exit(1);
  }

  // Create account from devnet pre-funded account
  console.log(`Using devnet account: ${DEVNET_ACCOUNT_ADDRESS}`);
  const account = new Account({
    provider,
    address: DEVNET_ACCOUNT_ADDRESS,
    signer: DEVNET_PRIVATE_KEY,
  });

  // Check if account is deployed
  let accountDeployed = false;
  try {
    await provider.getClassHashAt(DEVNET_ACCOUNT_ADDRESS);
    accountDeployed = true;
    console.log('✅ Account is deployed\n');
  } catch (error: any) {
    console.log('⚠️  Account not deployed on devnet');
    console.log('Attempting to deploy account...\n');
    
    try {
      // For devnet, we need to deploy the account contract
      // Use OpenZeppelin account class hash (same as Sepolia for devnet)
      const OZ_ACCOUNT_CLASS_HASH = '0x01bd7c78bd731400989b0f6eb4f0e0b6e471f7b5ee0030f5bca87d1e4b61c0e';
      
      // Get public key from private key
      const publicKey = ec.starkCurve.getStarkKey(DEVNET_PRIVATE_KEY);
      
      const { transaction_hash, contract_address } = await account.deployAccount({
        classHash: OZ_ACCOUNT_CLASS_HASH,
        constructorCalldata: CallData.compile({ publicKey }),
        addressSalt: publicKey,
      });
      
      console.log(`Account deployment tx: ${transaction_hash}`);
      await provider.waitForTransaction(transaction_hash);
      console.log(`✅ Account deployed at: ${contract_address}\n`);
      accountDeployed = true;
    } catch (deployError: any) {
      if (deployError.message?.includes('Class hash not found') || deployError.message?.includes('28')) {
        console.log('⚠️  Account class not declared on devnet');
        console.log('   Devnet might use different account class. Trying to proceed...\n');
      } else {
        console.error('❌ Account deployment failed:', deployError.message);
        console.log('\nTrying to proceed anyway - devnet might handle accounts differently\n');
      }
    }
  }

  // Note: Devnet accounts are pre-funded with 1000000000000000000000 WEI
  console.log('ℹ️  Devnet accounts are pre-funded\n');

  // Build contract first
  console.log('📦 Building contract...');
  const cairoDir = path.join(__dirname, '../../../cairo');
  const buildProcess = require('child_process').spawn('scarb', ['build'], {
    cwd: cairoDir,
    stdio: 'inherit',
  });

  await new Promise<void>((resolve, reject) => {
    buildProcess.on('close', (code: number) => {
      if (code === 0) {
        console.log('✅ Contract built\n');
        resolve();
      } else {
        reject(new Error(`Build failed with code ${code}`));
      }
    });
  });

  // Run golden rule test
  console.log('🧪 Running golden rule test...');
  const testProcess = require('child_process').spawn('snforge', ['test', 'test_e2e_dleq'], {
    cwd: cairoDir,
    stdio: 'pipe',
  });

  let testOutput = '';
  testProcess.stdout.on('data', (data: Buffer) => {
    testOutput += data.toString();
  });
  testProcess.stderr.on('data', (data: Buffer) => {
    testOutput += data.toString();
  });

  await new Promise<void>((resolve, reject) => {
    testProcess.on('close', (code: number) => {
      // Check if test passed (look for "Tests: X passed" with 0 failed)
      const passedMatch = testOutput.match(/Tests:\s*(\d+)\s+passed/);
      const failedMatch = testOutput.match(/Tests:.*?(\d+)\s+failed/);
      const passed = passedMatch ? parseInt(passedMatch[1]) > 0 : false;
      const failed = failedMatch ? parseInt(failedMatch[1]) > 0 : false;
      
      if (passed && !failed) {
        console.log('✅ Golden rule test passed\n');
        resolve();
      } else {
        console.error('❌ Golden rule test failed - DO NOT DEPLOY');
        console.error(testOutput);
        reject(new Error('Golden rule test failed'));
      }
    });
  });

  // Declare contract
  console.log('📄 Declaring contract...');
  const classHash = await declareContract(account, provider);
  console.log(`✅ Contract declared! Class Hash: ${classHash}\n`);

  // Deploy contract instance
  console.log('🚀 Deploying contract instance...');
  const contractAddress = await deployContract(account, provider, classHash);
  console.log(`✅ Contract deployed! Address: ${contractAddress}\n`);

  // Save results
  const result = {
    classHash,
    contractAddress,
    accountAddress: DEVNET_ACCOUNT_ADDRESS,
    rpcUrl: DEVNET_RPC_URL,
    timestamp: new Date().toISOString(),
  };

  const outputDir = path.join(__dirname, '../../../deployments');
  fs.mkdirSync(outputDir, { recursive: true });
  const outputFile = path.join(outputDir, 'devnet-result.json');
  fs.writeFileSync(outputFile, JSON.stringify(result, null, 2));

  console.log('✅ Deployment complete!');
  console.log('\n📋 Deployment Summary:');
  console.log(JSON.stringify(result, null, 2));
  console.log(`\n💾 Saved to: ${outputFile}`);
}

main().catch((error) => {
  console.error('\n❌ Deployment failed:');
  console.error(error);
  process.exit(1);
});

