import { Account, RpcProvider } from 'starknet';
import * as fs from 'fs';
import * as path from 'path';

const repoRoot = path.join(__dirname, '../../..');
const MASK_128 = (BigInt(1) << BigInt(128)) - BigInt(1);

function normalizeHex(value: string | number | bigint): string {
  if (typeof value === 'bigint') return `0x${value.toString(16)}`;
  if (typeof value === 'number') return `0x${BigInt(value).toString(16)}`;
  const trimmed = value.trim();
  if (trimmed.startsWith('0x')) return `0x${BigInt(trimmed).toString(16)}`;
  return `0x${BigInt(trimmed).toString(16)}`;
}

function loadJson(relativePath: string): any {
  return JSON.parse(fs.readFileSync(path.join(repoRoot, relativePath), 'utf-8'));
}

function leHexToBigInt(hex: string): bigint {
  const bytes = hex.replace(/^0x/, '').match(/../g) ?? [];
  return BigInt(`0x${bytes.reverse().join('') || '0'}`);
}

function leHexToU256(hex: string): string[] {
  const clean = hex.replace(/^0x/, '').padStart(64, '0');
  const low = leHexToBigInt(clean.slice(0, 32));
  const high = leHexToBigInt(clean.slice(32, 64));
  return [normalizeHex(low), normalizeHex(high)];
}

function bigintToU256(value: bigint): string[] {
  return [normalizeHex(value & MASK_128), normalizeHex(value >> BigInt(128))];
}

function u256Parts(value: { low: string; high: string }): string[] {
  return [normalizeHex(value.low), normalizeHex(value.high)];
}

function parseHashlock(hex: string): string[] {
  const clean = hex.replace(/^0x/, '');
  if (clean.length !== 64) throw new Error('hashlock must be 32 bytes');
  const words: string[] = [];
  for (let i = 0; i < clean.length; i += 8) words.push(`0x${clean.slice(i, i + 8)}`);
  return words;
}

function parseHint(cairoArray: string): string[] {
  const values = cairoArray.match(/0x[0-9a-fA-F]+/g);
  if (!values || values.length !== 10) throw new Error(`expected 10 hint felts, got ${values?.length ?? 0}`);
  return values.map(normalizeHex);
}

function pushSpan(calldata: string[], values: string[]): void {
  calldata.push(normalizeHex(values.length));
  calldata.push(...values.map(normalizeHex));
}

export function buildConstructorCalldata(lockUntil?: number): string[] {
  const tv = loadJson('rust/test_vectors.json');
  const generated = loadJson('cairo/generated_dleq_vectors.json');
  const hints = loadJson('cairo/test_hints.json');
  const adaptorHint = loadJson('cairo/adaptor_point_hint.json');

  const timestamp = lockUntil ?? Math.floor(Date.now() / 1000) + 14400;
  const token = normalizeHex(process.env.ATOMIC_SWAP_TOKEN_ADDRESS ?? '0x0');
  const amount = BigInt(process.env.ATOMIC_SWAP_AMOUNT ?? '0');
  const depositor = normalizeHex(
    process.env.ATOMIC_SWAP_DEPOSITOR ?? process.env.STARKNET_ACCOUNT_ADDRESS ?? '0x0'
  );
  if (process.env.ATOMIC_SWAP_ALLOW_ZERO_LOCK !== '1' && (token === '0x0' || amount === BigInt(0))) {
    throw new Error('Set ATOMIC_SWAP_TOKEN_ADDRESS and ATOMIC_SWAP_AMOUNT, or ATOMIC_SWAP_ALLOW_ZERO_LOCK=1 for a zero-value test deployment');
  }
  if (amount !== BigInt(0) && depositor === '0x0') {
    throw new Error('Set ATOMIC_SWAP_DEPOSITOR or STARKNET_ACCOUNT_ADDRESS for non-zero token locks');
  }

  const calldata: string[] = [];
  pushSpan(calldata, parseHashlock(tv.hashlock));
  calldata.push(normalizeHex(timestamp));
  calldata.push(depositor);
  calldata.push(token);
  calldata.push(...bigintToU256(amount));

  calldata.push(...leHexToU256(tv.adaptor_point_compressed));
  calldata.push(...u256Parts(generated.sqrt_hints.adaptor_point_sqrt_hint));
  calldata.push(...leHexToU256(tv.second_point_compressed));
  calldata.push(...u256Parts(generated.sqrt_hints.second_point_sqrt_hint));
  calldata.push(normalizeHex(generated.challenge));
  calldata.push(...u256Parts(generated.response));

  pushSpan(calldata, parseHint(adaptorHint.cairo_format));
  pushSpan(calldata, parseHint(hints.cairo_hints.s_hint_for_g));
  pushSpan(calldata, parseHint(hints.cairo_hints.s_hint_for_y));
  pushSpan(calldata, parseHint(hints.cairo_hints.c_neg_hint_for_t));
  pushSpan(calldata, parseHint(hints.cairo_hints.c_neg_hint_for_u));

  calldata.push(...leHexToU256(tv.r1_compressed));
  calldata.push(...u256Parts(generated.sqrt_hints.r1_sqrt_hint));
  calldata.push(...leHexToU256(tv.r2_compressed));
  calldata.push(...u256Parts(generated.sqrt_hints.r2_sqrt_hint));
  return calldata;
}

export async function deployContract(
  account: Account,
  provider: RpcProvider,
  classHash: string
): Promise<string> {
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
