import { Account, RpcProvider, CallData } from 'starknet';
import * as fs from 'fs';
import * as path from 'path';

// Load test vectors
function loadTestVectors() {
  const tvPath = path.join(__dirname, '../../../rust/test_vectors.json');
  
  if (!fs.existsSync(tvPath)) {
    throw new Error(`Test vectors not found: ${tvPath}`);
  }
  
  const tv = JSON.parse(fs.readFileSync(tvPath, 'utf-8'));
  
  return tv;
}

// Convert hex string to u256 (low, high)
function hexToU256(hex: string): { low: string; high: string } {
  const clean = hex.replace('0x', '').padStart(64, '0');
  const high = '0x' + clean.slice(0, 32);
  const low = '0x' + clean.slice(32);
  return { low, high };
}

// Parse hashlock hex to 8 u32 words
function parseHashlock(hex: string): string[] {
  const clean = hex.replace('0x', '');
  const words: string[] = [];
  for (let i = 0; i < 64; i += 8) {
    words.push('0x' + clean.slice(i, i + 8));
  }
  return words;
}

// Truncate to 128 bits for challenge/response
function truncateTo128Bits(hex: string): string {
  const val = BigInt('0x' + hex.replace('0x', ''));
  const mask = (BigInt(1) << BigInt(128)) - BigInt(1);
  return '0x' + (val & mask).toString(16);
}

export function buildConstructorCalldata(lockUntil?: number): any[] {
  const tv = loadTestVectors();
  
  // Default lockuntil: 4 hours from now
  const timestamp = lockUntil ?? Math.floor(Date.now() / 1000) + 14400;
  
  // MSM hints from test_e2e_dleq.cairo (lines 121-226)
  const s_hint_for_g = [
    '0xa82b6800cf6fafb9e422ff00', '0xa9d32170fa1d6e70ce9f5875',
    '0x38d522e54f3cc905', '0x0',
    '0x6632b6936c8a0092f2fa8193', '0x48849326ffd29b0fd452c82e',
    '0x1cb22722b8aeac6d', '0x0',
    '0x3ce8213ee078382bd7862b141d23a01e', '0x12a88328ee6fe07c656e9f1f11921d2ff'
  ];
  
  const s_hint_for_y = [
    '0x5f8703b67e528a68c666436f', '0x4319c91a2264dceb203b3c7',
    '0x131bcf26d61c6749', '0x0',
    '0x2b9edf9810114e3f99120ee8', '0x23ac0997ff9d26665393f4f1',
    '0xa2adc2ad21db8d1', '0x0',
    '0x3ce8213ee078382bd7862b141d23a01e', '0x12a88328ee6fe07c656e9f1f11921d2ff'
  ];
  
  const c_neg_hint_for_t = [
    '0xcc7bbab2a86720f06fa72b5a', '0x27ebc6cd7c83bd71f4819168',
    '0x2b4af1beb7dc4112', '0x0',
    '0xd0ac52873f110a396803c36c', '0xc23304c89672797661dbefa3',
    '0x547b7c3862004a5a', '0x0',
    '0xba5f45d69eaafbaaa06091a65e2873d', '0x1301450999c6615fa5bded0ada7e22902'
  ];
  
  const c_neg_hint_for_u = [
    '0x3aa67aef7c64a7b253e4a0fc', '0x2799eb3ed1784408cb1f6360',
    '0x6d7fa630d5721877', '0x0',
    '0x9fed6006f4d300b627b45f', '0xf8f69fd5bc96748bf6e2541b',
    '0x56b40a0879ad40ae', '0x0',
    '0xba5f45d69eaafbaaa06091a65e2873d', '0x1301450999c6615fa5bded0ada7e22902'
  ];
  
  const fake_glv_hint = [
    '0x4af5bf430174455ca59934c5', '0x748d85ad870959a54bca47ba',
    '0x6decdae5e1b9b254', '0x0',
    '0xaa008e6009b43d5c309fa848', '0x5b26ec9e21237560e1866183',
    '0x7191bfaa5a23d0cb', '0x0',
    '0x1569bc348ca5e9beecb728fdbfea1cd6', '0x28e2d5faa7b8c3b25a1678149337cad3'
  ];

  // Build calldata array matching constructor signature
  const calldata: any[] = [];
  
  // 1. hashwords: Span<u32> (8 words)
  const hashlock = parseHashlock(tv.hashlock);
  calldata.push(...hashlock);
  
  // 2. lockuntil: u64
  calldata.push(timestamp.toString());
  
  // 3. token: ContractAddress (zero for testing)
  calldata.push('0x0');
  
  // 4. amount: u256 (zero for testing)
  calldata.push('0x0', '0x0'); // low, high
  
  // 5. adaptor_point_edwards_compressed: u256
  const adaptorPoint = hexToU256(tv.adaptor_point_compressed);
  calldata.push(adaptorPoint.low, adaptorPoint.high);
  
  // 6. adaptor_point_sqrt_hint: u256
  calldata.push('0x448c18dcf34127e112ff945a65defbfc', '0x17611da35f39a2a5e3a9fddb8d978e4f');
  
  // 7. dleq_second_point_edwards_compressed: u256
  const secondPoint = hexToU256(tv.dleq_second_point_compressed);
  calldata.push(secondPoint.low, secondPoint.high);
  
  // 8. dleq_second_point_sqrt_hint: u256
  calldata.push('0xdcad2173817c163b5405cec7698eb4b8', '0x742bb3c44b13553c8ddff66565b44cac');
  
  // 9. dleq: (felt252, felt252) - challenge, response (truncated to 128 bits)
  calldata.push(truncateTo128Bits(tv.challenge));
  calldata.push(truncateTo128Bits(tv.response));
  
  // 10. fake_glv_hint: Span<felt252> (10 felts)
  calldata.push(...fake_glv_hint);
  
  // 11-14. DLEQ MSM hints (4 spans × 10 felts each)
  calldata.push(...s_hint_for_g);
  calldata.push(...s_hint_for_y);
  calldata.push(...c_neg_hint_for_t);
  calldata.push(...c_neg_hint_for_u);
  
  // 15. dleq_r1_compressed: u256
  const r1 = hexToU256(tv.r1_compressed);
  calldata.push(r1.low, r1.high);
  
  // 16. dleq_r1_sqrt_hint: u256
  calldata.push('0x72a9698d3171817c239f4009cc36fc97', '0x3f2b84592a9ee701d24651e3aa3c837d');
  
  // 17. dleq_r2_compressed: u256
  const r2 = hexToU256(tv.r2_compressed);
  calldata.push(r2.low, r2.high);
  
  // 18. dleq_r2_sqrt_hint: u256
  calldata.push('0x43f2c451f9ca69ff1577d77d646a50e', '0x4ee64b0e07d89e906f9e8b7bea09283e');
  
  return calldata;
}

export async function deployContract(
  account: Account,
  provider: RpcProvider,
  classHash: string
): Promise<string> {
  console.log('Building constructor calldata...');
  const calldata = buildConstructorCalldata();
  
  console.log(`Deploying contract with class hash: ${classHash}`);
  console.log(`Constructor calldata length: ${calldata.length} elements`);
  
  const deployResponse = await account.deployContract({
    classHash,
    constructorCalldata: calldata,
  });
  
  console.log(`Deployment tx: ${deployResponse.transaction_hash}`);
  await provider.waitForTransaction(deployResponse.transaction_hash);
  
  console.log(`Contract deployed at: ${deployResponse.contract_address}`);
  return deployResponse.contract_address;
}

