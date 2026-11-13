import { createHash } from 'node:crypto';

const KEY_RE = /^[A-Za-z0-9]{24}$/;
const HASH_RE = /^[0-9a-f]{64}$/;

const BUILT_IN = [
  '9cf0542b966afd32b6ef517babab27ea726d7c0dba9fbce05c503b59f69a5fb9',
  '08a1bf8d173ffa440a0aded50b368b2cc0ab81b0cb0c6fc3bd9fa8e8fe01c693',
  'ae94cbe95a3f3ed86ac0d00621b13e6884beb58052d7b0c197c238af63c9df4e',
];

function parse(list: string | undefined): string[] {
  return (list ?? '').split(/[\s,]+/).map(s => s.trim().toLowerCase()).filter(s => HASH_RE.test(s));
}

let hashes = new Set<string>([...BUILT_IN, ...parse(process.env.DEV_KEY_SHA256)]);
const memo = new Map<string, boolean>();

export function devKeyHash(pkey: string): string {
  return createHash('sha256').update(pkey).digest('hex');
}

export function isDevKey(pkey: unknown): boolean {
  if (typeof pkey !== 'string' || !KEY_RE.test(pkey)) return false;
  let v = memo.get(pkey);
  if (v === undefined) {
    v = hashes.has(devKeyHash(pkey));
    if (memo.size > 4096) memo.clear();
    memo.set(pkey, v);
  }
  return v;
}

export function devMark(pkey: unknown): { dev?: true } {
  return isDevKey(pkey) ? { dev: true } : {};
}

export function setDevHashes(list: string[] | null): void {
  hashes = new Set(list === null ? [...BUILT_IN, ...parse(process.env.DEV_KEY_SHA256)] : parse(list.join(',')));
  memo.clear();
}
