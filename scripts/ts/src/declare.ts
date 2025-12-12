import { Account, RpcProvider, json, DeclareContractPayload } from 'starknet';
import * as fs from 'fs';
import * as path from 'path';

export async function declareContract(
  account: Account,
  provider: RpcProvider
): Promise<string> {
  const cairoDir = path.join(__dirname, '../../../cairo/target/dev');
  
  const sierraPath = path.join(cairoDir, 'atomic_lock_AtomicLock.contract_class.json');
  const casmPath = path.join(cairoDir, 'atomic_lock_AtomicLock.compiled_contract_class.json');
  
  if (!fs.existsSync(sierraPath) || !fs.existsSync(casmPath)) {
    throw new Error('Contract not compiled. Run: cd cairo && scarb build');
  }
  
  // Load pre-compiled artifacts (bypasses server-side recompilation!)
  const sierra = json.parse(fs.readFileSync(sierraPath, 'utf-8'));
  const casm = json.parse(fs.readFileSync(casmPath, 'utf-8'));
  
  console.log('Declaring contract with pre-compiled CASM...');
  
  try {
    const declarePayload: DeclareContractPayload = {
      contract: sierra,
      casm: casm,  // KEY: Providing CASM bypasses blake2s_compress libfunc issue!
    };
    
    const declareResponse = await account.declare(declarePayload);
    
    console.log(`Declaration tx: ${declareResponse.transaction_hash}`);
    await provider.waitForTransaction(declareResponse.transaction_hash);
    
    console.log(`Class hash: ${declareResponse.class_hash}`);
    return declareResponse.class_hash;
    
  } catch (error: any) {
    // Check if already declared
    if (error.message?.includes('already declared') || error.message?.includes('StarknetErrorCode.CLASS_ALREADY_DECLARED')) {
      console.log('Contract already declared, computing class hash...');
      const { hash: classHashModule } = await import('starknet');
      const classHash = classHashModule.computeContractClassHash(sierra);
      console.log(`Class hash: ${classHash}`);
      return classHash;
    }
    throw error;
  }
}

