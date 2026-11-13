import { deflateRawSync, inflateRawSync } from 'node:zlib';
import { randomBytes } from 'node:crypto';

export const BOOT_ID = process.env.MP_BOOT_ID && /^[A-Za-z0-9_-]{1,32}$/.test(process.env.MP_BOOT_ID) ? process.env.MP_BOOT_ID : randomBytes(6).toString('hex');
export const BOOT_AT = Date.now();

export const handoverTiming = {
  ttlMs: 15 * 60_000,
  partBytes: 700_000,
  retryMs: 8_000,
  retryStepMs: 400,
  retryWindowMs: 10 * 60_000,
  writeBudgetMs: 25_000,
  closeDelayMs: 400,
};

export type HandoverKind = 'room' | 'party';

export interface HandoverEntry {
  code: string;
  kind: HandoverKind;
  tokens: string[];
  at: number;
  boot: string;
  body: Record<string, unknown>;
}

export function pack(v: unknown): unknown {
  if (v === undefined || typeof v === 'function') return undefined;
  if (v === null || typeof v !== 'object') return typeof v === 'number' && !Number.isFinite(v) ? null : v;
  if (v instanceof Map) return { $map: [...v.entries()].map(([k, x]) => [pack(k), pack(x)]) };
  if (v instanceof Set) return { $set: [...v].map(pack) };
  if (Array.isArray(v)) return v.map(x => { const p = pack(x); return p === undefined ? null : p; });
  const out: Record<string, unknown> = {};
  for (const [k, x] of Object.entries(v as Record<string, unknown>)) {
    const p = pack(x);
    if (p !== undefined) out[k] = p;
  }
  return out;
}

export function unpack(v: unknown): unknown {
  if (v === null || typeof v !== 'object') return v;
  if (Array.isArray(v)) return v.map(unpack);
  const o = v as Record<string, unknown>;
  if (Array.isArray(o.$map) && Object.keys(o).length === 1) return new Map((o.$map as unknown[][]).map(([k, x]) => [unpack(k), unpack(x)]));
  if (Array.isArray(o.$set) && Object.keys(o).length === 1) return new Set((o.$set as unknown[]).map(unpack));
  const out: Record<string, unknown> = {};
  for (const [k, x] of Object.entries(o)) out[k] = unpack(x);
  return out;
}

export function encodeEntry(e: HandoverEntry): string {
  return Buffer.from(deflateRawSync(Buffer.from(JSON.stringify(pack(e)), 'utf8'))).toString('base64');
}

export function decodeEntry(data: string): HandoverEntry | null {
  try {
    const e = unpack(JSON.parse(Buffer.from(inflateRawSync(Buffer.from(data, 'base64'), { maxOutputLength: 64 * 1024 * 1024 })).toString('utf8'))) as HandoverEntry;
    if (!e || typeof e.code !== 'string' || (e.kind !== 'room' && e.kind !== 'party') || !Array.isArray(e.tokens) || !e.body) return null;
    return e;
  } catch {
    return null;
  }
}

export function msLeft(deadline: number | null | undefined, now: number): number | null {
  return typeof deadline === 'number' && Number.isFinite(deadline) ? Math.max(0, deadline - now) : null;
}

export interface HandoverStore {
  kind: string;
  init(): Promise<void>;
  put(entries: HandoverEntry[], now?: number): Promise<number>;
  find(code: string, now?: number): Promise<HandoverEntry | null>;
  codes(now?: number): Promise<string[]>;
  drop(code: string): Promise<void>;
}

export class MemoryHandoverStore implements HandoverStore {
  readonly kind = 'memory';
  rows = new Map<string, { data: string; expires: number }>();
  async init(): Promise<void> { return; }
  async put(entries: HandoverEntry[], now = Date.now()): Promise<number> {
    for (const e of entries) this.rows.set(e.code, { data: encodeEntry(e), expires: now + handoverTiming.ttlMs });
    return entries.length;
  }
  async find(code: string, now = Date.now()): Promise<HandoverEntry | null> {
    const r = this.rows.get(code);
    if (!r) return null;
    if (r.expires <= now) { this.rows.delete(code); return null; }
    return decodeEntry(r.data);
  }
  async codes(now = Date.now()): Promise<string[]> { return [...this.rows].filter(([, r]) => r.expires > now).map(([c]) => c); }
  async drop(code: string): Promise<void> { this.rows.delete(code); }
}

type QueryFn = (sql: string, params?: unknown[]) => Promise<Record<string, unknown>[]>;

export const HANDOVER_SCHEMA = [
  `CREATE TABLE IF NOT EXISTS room_handover (code TEXT NOT NULL, part INTEGER NOT NULL, parts INTEGER NOT NULL, kind TEXT NOT NULL, boot TEXT NOT NULL, data TEXT NOT NULL, written_at INTEGER NOT NULL, expires_at INTEGER NOT NULL, PRIMARY KEY (code, part))`,
];

export class D1HandoverStore implements HandoverStore {
  readonly kind = 'd1';
  private ready: Promise<void> | null = null;
  constructor(private q: QueryFn) {}

  init(): Promise<void> {
    if (!this.ready) {
      this.ready = (async () => { for (const sql of HANDOVER_SCHEMA) await this.q(sql); })();
      this.ready.catch(() => { this.ready = null; });
    }
    return this.ready;
  }

  async put(entries: HandoverEntry[], now = Date.now()): Promise<number> {
    await this.init();
    const expires = now + handoverTiming.ttlMs;
    const one = async (e: HandoverEntry): Promise<boolean> => {
      const data = encodeEntry(e);
      const size = handoverTiming.partBytes;
      const parts = Math.max(1, Math.ceil(data.length / size));
      await this.q('DELETE FROM room_handover WHERE code = ?', [e.code]);
      for (let i = 0; i < parts; i++) {
        await this.q('INSERT OR REPLACE INTO room_handover (code, part, parts, kind, boot, data, written_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          [e.code, i, parts, e.kind, e.boot, data.slice(i * size, (i + 1) * size), now, expires]);
      }
      return true;
    };
    const done = await Promise.allSettled(entries.map(one));
    return done.filter(r => r.status === 'fulfilled').length;
  }

  async find(code: string, now = Date.now()): Promise<HandoverEntry | null> {
    await this.init();
    const rows = await this.q('SELECT part, parts, boot, data FROM room_handover WHERE code = ? AND expires_at > ? ORDER BY part', [code, now]);
    if (!rows.length) return null;
    const parts = Number(rows[0].parts);
    const boot = rows[0].boot;
    if (rows.length !== parts || rows.some((r, i) => Number(r.part) !== i || r.boot !== boot)) return null;
    return decodeEntry(rows.map(r => String(r.data)).join(''));
  }

  async codes(now = Date.now()): Promise<string[]> {
    await this.init();
    const rows = await this.q('SELECT DISTINCT code FROM room_handover WHERE expires_at > ?', [now]);
    return rows.map(r => String(r.code));
  }

  async drop(code: string): Promise<void> {
    await this.init();
    await this.q('DELETE FROM room_handover WHERE code = ? OR expires_at <= ?', [code, Date.now()]);
  }
}

export function handoverStoreFor(store: unknown): HandoverStore {
  const s = store as { kind?: string; query?: QueryFn } | null;
  if (s && s.kind === 'd1' && typeof s.query === 'function') return new D1HandoverStore(s.query.bind(s));
  return new MemoryHandoverStore();
}

export function withBudget<T>(p: Promise<T>, ms: number, fallback: T): Promise<T> {
  return new Promise(resolve => {
    const t = setTimeout(() => resolve(fallback), ms);
    p.then(v => { clearTimeout(t); resolve(v); }, () => { clearTimeout(t); resolve(fallback); });
  });
}
