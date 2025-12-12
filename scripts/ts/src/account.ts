import { Account, RpcProvider, stark, ec, hash, CallData } from 'starknet';
import * as fs from 'fs';
import * as path from 'path';
import * as dotenv from 'dotenv';

dotenv.config();

// OpenZeppelin Account class hash for Sepolia
const OZ_ACCOUNT_CLASS_HASH = '0x01bd7c78bd731400989b0f6eb4f0e0b6e471f7b5ee0030f5bca87d1e4b61c0e';

export interface AccountConfig {
  address: string;
  privateKey: string;
  publicKey: string;
}

export async function getOrCreateAccount(provider: RpcProvider): Promise<{ account: Account; config: AccountConfig }> {
  const keyFile = path.join(__dirname, '../.deployer-key.json');
  
  let config: AccountConfig;
  
  if (fs.existsSync(keyFile)) {
    // Load existing key
    config = JSON.parse(fs.readFileSync(keyFile, 'utf-8'));
    console.log(`Loaded account: ${config.address}`);
  } else {
    // Generate new keypair
    const privateKey = stark.randomAddress();
    const publicKey = ec.starkCurve.getStarkKey(privateKey);
    
    // Compute counterfactual address
    const address = hash.calculateContractAddressFromHash(
      publicKey, // salt
      OZ_ACCOUNT_CLASS_HASH,
      CallData.compile({ publicKey }),
      0 // Sepolia chain ID
    );
    
    config = { address, privateKey, publicKey };
    
    // Save to file
    fs.writeFileSync(keyFile, JSON.stringify(config, null, 2));
    fs.chmodSync(keyFile, 0o600);
    console.log(`Generated new account: ${address}`);
    console.log(`Fund this address on Sepolia faucet: https://starknet-faucet.vercel.app/`);
  }
  
  // starknet.js v8 Account constructor
  const account = new Account({
    provider,
    address: config.address,
    signer: config.privateKey,
  });
  
  return { account, config };
}

export async function deployAccountIfNeeded(
  provider: RpcProvider,
  account: Account,
  config: AccountConfig
): Promise<void> {
  try {
    // Check if account is deployed
    await provider.getClassHashAt(config.address);
    console.log('✅ Account already deployed');
  } catch (error: any) {
    // Account class not declared - cannot deploy new accounts
    if (error.message?.includes('Class hash not found') || error.message?.includes('28')) {
      console.log('⚠️  Account class not declared on Sepolia');
      console.log('   Using existing deployed account (assuming deployed)');
      console.log(`   Address: ${config.address}`);
      return;
    }
    
    console.log('Deploying account contract...');
    
    try {
      const { transaction_hash, contract_address } = await account.deployAccount({
        classHash: OZ_ACCOUNT_CLASS_HASH,
        constructorCalldata: CallData.compile({ publicKey: config.publicKey }),
        addressSalt: config.publicKey,
      });
      
      console.log(`Deployment tx: ${transaction_hash}`);
      await provider.waitForTransaction(transaction_hash);
      console.log(`Account deployed at: ${contract_address}`);
    } catch (deployError: any) {
      if (deployError.message?.includes('Class hash not found') || deployError.message?.includes('28')) {
        console.log('⚠️  Account class not declared - cannot deploy new account');
        console.log('   Proceeding with existing account (assuming deployed)');
      } else {
        throw deployError;
      }
    }
  }
}

