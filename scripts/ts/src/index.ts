import { RpcProvider } from 'starknet';
import { getOrCreateAccount, deployAccountIfNeeded } from './account';
import { declareContract } from './declare';
import { deployContract } from './deploy';
import * as fs from 'fs';
import * as path from 'path';

const RPC_URLS = [
  'https://api.zan.top/public/starknet-sepolia/rpc/v0_10',
  'https://free-rpc.nethermind.io/sepolia-juno',
];

function redactRpcUrl(raw: string): string {
  try {
    const url = new URL(raw);
    const pathParts = url.pathname.split('/');
    const last = pathParts[pathParts.length - 1];
    if (/^[A-Za-z0-9_-]{20,}$/.test(last)) {
      pathParts[pathParts.length - 1] = '<redacted>';
      url.pathname = pathParts.join('/');
    }
    if (url.search) {
      url.search = '?<redacted>';
    }
    return url.toString();
  } catch {
    return raw;
  }
}

async function main() {
  // Try RPC endpoints (v8 uses object parameters)
  let provider: RpcProvider | null = null;
  for (const url of RPC_URLS) {
    const safeUrl = redactRpcUrl(url);
    try {
      console.log(`Trying RPC: ${safeUrl}`);
      provider = new RpcProvider({ nodeUrl: url });
      const chainId = await provider.getChainId();
      console.log(`✅ Connected to ${safeUrl} (Chain ID: ${chainId})`);
      break;
    } catch (e: any) {
      console.log(`❌ Failed: ${safeUrl} - ${e.message?.substring(0, 100) || e}`);
    }
  }
  
  if (!provider) throw new Error('All RPC endpoints failed');
  
  // Setup account
  const { account, config } = await getOrCreateAccount(provider);
  
  // Check if account is deployed
  try {
    // Try to get class hash - if it works, account is deployed
    await provider.getClassHashAt(config.address);
    console.log('✅ Account is deployed');
  } catch {
    // Account might not be deployed yet
    console.log('Account not deployed, attempting deployment...');
    await deployAccountIfNeeded(provider, account, config);
  }
  
  console.log(`Account address: ${config.address}`);
  console.log('⚠️  Ensure account has sufficient balance for deployment');
  
  // Declare contract
  const classHash = await declareContract(account, provider);
  
  // Deploy contract
  const contractAddress = await deployContract(account, provider, classHash);
  
  // Save results
  const result = {
    classHash,
    contractAddress,
    accountAddress: config.address,
    timestamp: new Date().toISOString(),
  };
  
  const outputDir = path.join(__dirname, '../../../deployments');
  fs.mkdirSync(outputDir, { recursive: true });
  fs.writeFileSync(
    path.join(outputDir, 'starknetjs-result.json'),
    JSON.stringify(result, null, 2)
  );
  
  console.log('\n✅ Deployment complete!');
  console.log(JSON.stringify(result, null, 2));
}

main().catch(console.error);
