import { inflateSync } from 'node:zlib';

export const SPEEDRUN_TYPES = ['speedrun_submit', 'speedrun_board', 'speedrun_replay_put', 'speedrun_replay_get'];
export const SPEEDRUN_BIG_TYPES = ['speedrun_replay_put'];

export const SR_CATS: Record<string, number> = { ante2: 2, ante4: 4, any: 8 };
export const SR_DECKS = ['b_red', 'b_blue', 'b_yellow', 'b_green', 'b_black', 'b_magic', 'b_nebula', 'b_ghost', 'b_abandoned',
  'b_checkered', 'b_zodiac', 'b_painted', 'b_anaglyph', 'b_plasma', 'b_erratic'];
export const SR_MIN_SEGMENT = 12;
export const SR_MIN_HAND = 0.8;
export const SR_MIN_BLIND = 1.5;
export const SR_MAX_BLINDS_PER_ANTE = 6;
export const SR_MAX_TIME = 6 * 3600;
export const SR_SUBMITS_PER_HOUR = 30;
export const SR_BOARD_MAX = 100;
export const SR_REPLAY_SLACK = 2;
export const SR_REPLAY_MAX_B64 = 256 * 1024;
export const SR_REPLAY_MAX_RAW = 2 * 1024 * 1024;
export const SR_REPLAY_MSG_BYTES = SR_REPLAY_MAX_B64 + 2048;
export const SR_REPLAY_PUTS_PER_HOUR = 30;
export const SR_REPLAY_GETS_PER_HOUR = 60;
export const SR_RECENT_MS = 10 * 60_000;

const SEED_RE = /^[0-9A-Z]{1,8}$/;
const RUN_ID_RE = /^[A-Za-z0-9]{8,32}$/;
const PKEY_RE = /^[A-Za-z0-9]{24}$/;
const SEED_CHARS = '123456789ABCDEFGHIJKLMNPQRSTUVWXYZ';
const B64_RE = /^[A-Za-z0-9+/]+={0,2}$/;

export interface SpeedrunRow {
  id: string;
  pkey: string;
  name: string;
  cat: string;
  deck: string;
  stake: number;
  seed_type: string;
  seed: string;
  time: number;
  splits: number[];
  at: number;
  v: number;
}

export interface BoardFilter { cat: string; deck?: string; stake?: number; seed_type?: string }

export interface ReplayRow { pkey: string; id: string; cat: string; deck: string; stake: number; seed_type: string; bytes: number; at: number; z: string }

export interface ReplayHit { id: string; z: string; bytes: number; name: string; time: number }

export function weekId(ms: number): number {
  return Math.floor((Math.floor(ms / 86_400_000) + 3) / 7);
}

export function weekSeed(w: number): string {
  let x = (w * 7919 + 104729) % 2147483647;
  let out = '';
  for (let i = 0; i < 8; i++) {
    x = (x * 48271) % 2147483647;
    out += SEED_CHARS[x % SEED_CHARS.length];
  }
  return out;
}

function isNum(v: unknown): v is number { return typeof v === 'number' && Number.isFinite(v); }
function isInt(v: unknown, lo: number, hi: number): boolean { return Number.isInteger(v) && (v as number) >= lo && (v as number) <= hi; }

export function validateSpeedrun(msg: Record<string, unknown>): string | null {
  const t = msg.type;
  if (t === 'speedrun_submit') {
    const r = msg.run as Record<string, unknown> | undefined;
    if (!r || typeof r !== 'object' || Array.isArray(r)) return 'speedrun_submit: invalid run';
    if (typeof r.id !== 'string' || !RUN_ID_RE.test(r.id)) return 'speedrun_submit: invalid id';
    if (typeof r.cat !== 'string' || !(r.cat in SR_CATS)) return 'speedrun_submit: invalid cat';
    if (typeof r.deck !== 'string' || !SR_DECKS.includes(r.deck)) return 'speedrun_submit: invalid deck';
    if (!isInt(r.stake, 1, 12)) return 'speedrun_submit: invalid stake';
    if (r.seed_type !== 'random' && r.seed_type !== 'weekly') return 'speedrun_submit: invalid seed_type';
    if (typeof r.seed !== 'string' || !SEED_RE.test(r.seed)) return 'speedrun_submit: invalid seed';
    if (!isNum(r.time) || r.time <= 0 || r.time > SR_MAX_TIME) return 'speedrun_submit: invalid time';
    if (!Array.isArray(r.splits) || r.splits.length !== SR_CATS[r.cat] || !r.splits.every(isNum)) return 'speedrun_submit: invalid splits';
    if (!Array.isArray(r.blinds) || r.blinds.length !== SR_CATS[r.cat] || !r.blinds.every(x => isInt(x, 0, 10_000))) return 'speedrun_submit: invalid blinds';
    if (!Array.isArray(r.hands) || r.hands.length !== SR_CATS[r.cat] || !r.hands.every(x => isInt(x, 0, 100_000))) return 'speedrun_submit: invalid hands';
    if (r.v !== undefined && !isInt(r.v, 1, 1000)) return 'speedrun_submit: invalid v';
    if (msg.pkey !== undefined && (typeof msg.pkey !== 'string' || !PKEY_RE.test(msg.pkey))) return 'speedrun_submit: invalid pkey';
    if (msg.name !== undefined && (typeof msg.name !== 'string' || msg.name.length > 40)) return 'speedrun_submit: invalid name';
  }
  if (t === 'speedrun_board') {
    if (typeof msg.cat !== 'string' || !(msg.cat in SR_CATS)) return 'speedrun_board: invalid cat';
    if (msg.deck !== undefined && msg.deck !== 'all' && (typeof msg.deck !== 'string' || !SR_DECKS.includes(msg.deck))) return 'speedrun_board: invalid deck';
    if (msg.stake !== undefined && !isInt(msg.stake, 0, 12)) return 'speedrun_board: invalid stake';
    if (msg.seed_type !== undefined && msg.seed_type !== 'all' && msg.seed_type !== 'random' && msg.seed_type !== 'weekly') return 'speedrun_board: invalid seed_type';
    if (msg.limit !== undefined && !isInt(msg.limit, 1, SR_BOARD_MAX)) return 'speedrun_board: invalid limit';
    if (msg.pkey !== undefined && (typeof msg.pkey !== 'string' || !PKEY_RE.test(msg.pkey))) return 'speedrun_board: invalid pkey';
  }
  if (t === 'speedrun_replay_put') {
    if (typeof msg.id !== 'string' || !RUN_ID_RE.test(msg.id)) return 'speedrun_replay_put: invalid id';
    if (typeof msg.z !== 'string' || msg.z.length === 0 || msg.z.length > SR_REPLAY_MAX_B64 || msg.z.length % 4 !== 0 || !B64_RE.test(msg.z)) return 'speedrun_replay_put: invalid z';
    if (!isInt(msg.n, 1, SR_REPLAY_MAX_RAW)) return 'speedrun_replay_put: invalid n';
    if (msg.pkey !== undefined && (typeof msg.pkey !== 'string' || !PKEY_RE.test(msg.pkey))) return 'speedrun_replay_put: invalid pkey';
  }
  if (t === 'speedrun_replay_get') {
    if (typeof msg.id !== 'string' || !RUN_ID_RE.test(msg.id)) return 'speedrun_replay_get: invalid id';
    if (msg.pkey !== undefined && (typeof msg.pkey !== 'string' || !PKEY_RE.test(msg.pkey))) return 'speedrun_replay_get: invalid pkey';
  }
  return null;
}

export function readReplay(z: string, n: number): { entries: unknown[]; time: number | null } | null {
  let raw: Buffer;
  try { raw = inflateSync(Buffer.from(z, 'base64'), { maxOutputLength: SR_REPLAY_MAX_RAW }); } catch { return null; }
  if (raw.length !== n) return null;
  let t: unknown;
  try { t = JSON.parse(raw.toString('utf8')); } catch { return null; }
  if (!t || typeof t !== 'object' || Array.isArray(t)) return null;
  const o = t as Record<string, unknown>;
  if (!Array.isArray(o.entries) || o.entries.length === 0) return null;
  const x = o.x as Record<string, unknown> | undefined;
  const sr = x && typeof x === 'object' ? x.sr as Record<string, unknown> | undefined : undefined;
  const time = sr && typeof sr === 'object' && isNum(sr.time) ? sr.time : null;
  return { entries: o.entries, time };
}

export interface ReplayDigest { n: number; pl: number[]; bs: number[]; fb: number[]; lp: number[] }

export interface RunData { cat: string; seed_type: string; seed: string; time: number; splits: number[]; blinds: number[]; hands: number[]; rp?: ReplayDigest }

export function parseDigest(v: unknown, target: number): ReplayDigest | null {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return null;
  const d = v as Record<string, unknown>;
  const ints = (a: unknown) => Array.isArray(a) && a.length === target && a.every(x => isInt(x, 0, 100_000));
  const nums = (a: unknown) => Array.isArray(a) && a.length === target && a.every(x => isNum(x) && x >= 0 && x <= SR_MAX_TIME);
  if (!isInt(d.n, 0, 1_000_000) || !ints(d.pl) || !ints(d.bs) || !nums(d.fb) || !nums(d.lp)) return null;
  return { n: d.n as number, pl: d.pl as number[], bs: d.bs as number[], fb: d.fb as number[], lp: d.lp as number[] };
}

export function replayFits(r: RunData): boolean {
  const d = r.rp;
  if (!d) return true;
  const target = r.splits.length;
  let pb = 0;
  let ph = 0;
  let acts = 0;
  for (let i = 0; i < target; i++) {
    if (d.pl[i] !== r.hands[i] - ph || d.bs[i] !== r.blinds[i] - pb) return false;
    if (d.fb[i] > d.lp[i] || d.lp[i] > r.splits[i] + SR_REPLAY_SLACK) return false;
    if (i > 0 && d.fb[i] < r.splits[i - 1] - SR_REPLAY_SLACK) return false;
    acts += d.pl[i] + d.bs[i];
    pb = r.blinds[i];
    ph = r.hands[i];
  }
  return d.n >= acts;
}

export function plausible(r: RunData, now: number): string | null {
  const target = SR_CATS[r.cat];
  if (!target || r.splits.length !== target || r.blinds.length !== target || r.hands.length !== target) return 'splits';
  let prev = 0;
  let pb = 0;
  let ph = 0;
  for (let i = 0; i < target; i++) {
    const s = r.splits[i];
    const db = r.blinds[i] - pb;
    const dh = r.hands[i] - ph;
    if (s - prev < SR_MIN_SEGMENT) return 'too_fast';
    if (db < 1 || db > SR_MAX_BLINDS_PER_ANTE || dh < 1) return 'run_data';
    if (s - prev < dh * SR_MIN_HAND + db * SR_MIN_BLIND) return 'too_fast';
    prev = s;
    pb = r.blinds[i];
    ph = r.hands[i];
  }
  if (Math.abs(prev - r.time) > 0.25) return 'time_mismatch';
  if (!replayFits(r)) return 'replay';
  if (r.seed_type === 'weekly') {
    const w = weekId(now);
    if (r.seed !== weekSeed(w) && r.seed !== weekSeed(w - 1)) return 'weekly_seed';
  }
  return null;
}

export function bestPerPlayer(rows: SpeedrunRow[]): SpeedrunRow[] {
  const sorted = [...rows].sort((a, b) => a.time - b.time || a.at - b.at);
  const seen = new Set<string>();
  const out: SpeedrunRow[] = [];
  for (const r of sorted) {
    if (seen.has(r.pkey)) continue;
    seen.add(r.pkey);
    out.push(r);
  }
  return out;
}

function matches(r: SpeedrunRow, f: BoardFilter): boolean {
  if (r.cat !== f.cat) return false;
  if (f.deck && f.deck !== 'all' && r.deck !== f.deck) return false;
  if (f.stake && r.stake !== f.stake) return false;
  if (f.seed_type && f.seed_type !== 'all' && r.seed_type !== f.seed_type) return false;
  return true;
}

export interface SpeedrunStore {
  readonly kind: string;
  ensure(): Promise<void>;
  has(pkey: string, id: string): Promise<boolean>;
  get(pkey: string, id: string): Promise<SpeedrunRow | null>;
  add(r: SpeedrunRow): void;
  board(f: BoardFilter, scan: number): Promise<SpeedrunRow[]>;
  putReplay(r: ReplayRow): void;
  dropReplays(r: ReplayRow): void;
  replayKeys(ids: string[]): Promise<Set<string>>;
  getReplay(id: string): Promise<ReplayHit | null>;
}

export class MemorySpeedrunStore implements SpeedrunStore {
  readonly kind = 'memory';
  rows: SpeedrunRow[] = [];
  replays = new Map<string, ReplayRow>();
  async ensure(): Promise<void> { return; }
  async has(pkey: string, id: string): Promise<boolean> { return this.rows.some(r => r.pkey === pkey && r.id === id); }
  async get(pkey: string, id: string): Promise<SpeedrunRow | null> {
    const r = this.rows.find(x => x.pkey === pkey && x.id === id);
    return r ? { ...r, splits: [...r.splits] } : null;
  }
  add(r: SpeedrunRow): void { this.rows.push({ ...r, splits: [...r.splits] }); }
  async board(f: BoardFilter, scan: number): Promise<SpeedrunRow[]> {
    return this.rows.filter(r => matches(r, f)).sort((a, b) => a.time - b.time || a.at - b.at).slice(0, scan).map(r => ({ ...r, splits: [...r.splits] }));
  }
  putReplay(r: ReplayRow): void { this.replays.set(`${r.pkey}:${r.id}`, { ...r }); }
  dropReplays(r: ReplayRow): void {
    for (const [k, x] of this.replays) {
      if (x.pkey === r.pkey && x.id !== r.id && x.cat === r.cat && x.deck === r.deck && x.stake === r.stake && x.seed_type === r.seed_type) this.replays.delete(k);
    }
  }
  async replayKeys(ids: string[]): Promise<Set<string>> {
    const want = new Set(ids);
    const out = new Set<string>();
    for (const x of this.replays.values()) if (want.has(x.id)) out.add(`${x.pkey}:${x.id}`);
    return out;
  }
  async getReplay(id: string): Promise<ReplayHit | null> {
    for (const x of this.replays.values()) {
      if (x.id !== id) continue;
      const r = this.rows.find(y => y.pkey === x.pkey && y.id === x.id);
      return { id: x.id, z: x.z, bytes: x.bytes, name: r?.name ?? '', time: r?.time ?? 0 };
    }
    return null;
  }
}

interface D1Like {
  query(sql: string, params?: unknown[]): Promise<Record<string, unknown>[]>;
  write(sql: string, params: unknown[]): void;
}

export const SPEEDRUN_SCHEMA = [
  `CREATE TABLE IF NOT EXISTS speedruns (
  id TEXT NOT NULL,
  pkey TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  cat TEXT NOT NULL,
  deck TEXT NOT NULL,
  stake INTEGER NOT NULL,
  seed_type TEXT NOT NULL,
  seed TEXT NOT NULL,
  time REAL NOT NULL,
  splits TEXT NOT NULL,
  at INTEGER NOT NULL,
  v INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (pkey, id)
)`,
  'CREATE INDEX IF NOT EXISTS speedruns_board ON speedruns (cat, time)',
  `CREATE TABLE IF NOT EXISTS speedrun_replays (
  pkey TEXT NOT NULL,
  id TEXT NOT NULL,
  cat TEXT NOT NULL,
  deck TEXT NOT NULL,
  stake INTEGER NOT NULL,
  seed_type TEXT NOT NULL,
  bytes INTEGER NOT NULL,
  at INTEGER NOT NULL,
  z TEXT NOT NULL,
  PRIMARY KEY (pkey, id)
)`,
  'CREATE INDEX IF NOT EXISTS speedrun_replays_id ON speedrun_replays (id)',
];

function rowOf(r: Record<string, unknown>): SpeedrunRow | null {
  let splits: number[] = [];
  try { splits = (JSON.parse(String(r.splits)) as unknown[]).map(Number); } catch { return null; }
  return {
    id: String(r.id), pkey: String(r.pkey), name: String(r.name ?? ''), cat: String(r.cat), deck: String(r.deck), stake: Number(r.stake),
    seed_type: String(r.seed_type), seed: String(r.seed), time: Number(r.time), splits, at: Number(r.at), v: Number(r.v) || 1,
  };
}

export class D1SpeedrunStore implements SpeedrunStore {
  readonly kind = 'd1';
  constructor(private d1: D1Like) {}
  async ensure(): Promise<void> { for (const sql of SPEEDRUN_SCHEMA) await this.d1.query(sql); }
  async has(pkey: string, id: string): Promise<boolean> {
    const rows = await this.d1.query('SELECT id FROM speedruns WHERE pkey = ? AND id = ?', [pkey, id]);
    return rows.length > 0;
  }
  add(r: SpeedrunRow): void {
    this.d1.write(`INSERT INTO speedruns (id, pkey, name, cat, deck, stake, seed_type, seed, time, splits, at, v) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (pkey, id) DO NOTHING`,
    [r.id, r.pkey, r.name, r.cat, r.deck, r.stake, r.seed_type, r.seed, r.time, JSON.stringify(r.splits), r.at, r.v]);
  }
  async board(f: BoardFilter, scan: number): Promise<SpeedrunRow[]> {
    const where = ['cat = ?'];
    const args: unknown[] = [f.cat];
    if (f.deck && f.deck !== 'all') { where.push('deck = ?'); args.push(f.deck); }
    if (f.stake) { where.push('stake = ?'); args.push(f.stake); }
    if (f.seed_type && f.seed_type !== 'all') { where.push('seed_type = ?'); args.push(f.seed_type); }
    args.push(scan);
    const rows = await this.d1.query(`SELECT * FROM speedruns WHERE ${where.join(' AND ')} ORDER BY time ASC, at ASC LIMIT ?`, args);
    const out: SpeedrunRow[] = [];
    for (const r of rows) {
      const x = rowOf(r);
      if (x) out.push(x);
    }
    return out;
  }
  async get(pkey: string, id: string): Promise<SpeedrunRow | null> {
    const rows = await this.d1.query('SELECT * FROM speedruns WHERE pkey = ? AND id = ?', [pkey, id]);
    return rows[0] ? rowOf(rows[0]) : null;
  }
  putReplay(r: ReplayRow): void {
    this.d1.write(`INSERT INTO speedrun_replays (pkey, id, cat, deck, stake, seed_type, bytes, at, z) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (pkey, id) DO UPDATE SET bytes = excluded.bytes, at = excluded.at, z = excluded.z`,
    [r.pkey, r.id, r.cat, r.deck, r.stake, r.seed_type, r.bytes, r.at, r.z]);
  }
  dropReplays(r: ReplayRow): void {
    this.d1.write('DELETE FROM speedrun_replays WHERE pkey = ? AND cat = ? AND deck = ? AND stake = ? AND seed_type = ? AND id <> ?',
      [r.pkey, r.cat, r.deck, r.stake, r.seed_type, r.id]);
  }
  async replayKeys(ids: string[]): Promise<Set<string>> {
    const out = new Set<string>();
    const list = ids.slice(0, 90);
    if (list.length === 0) return out;
    const rows = await this.d1.query(`SELECT pkey, id FROM speedrun_replays WHERE id IN (${list.map(() => '?').join(', ')})`, list);
    for (const r of rows) out.add(`${String(r.pkey)}:${String(r.id)}`);
    return out;
  }
  async getReplay(id: string): Promise<ReplayHit | null> {
    const rows = await this.d1.query(`SELECT r.id AS id, r.z AS z, r.bytes AS bytes, s.name AS name, s.time AS time FROM speedrun_replays r
      LEFT JOIN speedruns s ON s.pkey = r.pkey AND s.id = r.id WHERE r.id = ? LIMIT 1`, [id]);
    const r = rows[0];
    if (!r) return null;
    return { id: String(r.id), z: String(r.z), bytes: Number(r.bytes) || 0, name: String(r.name ?? ''), time: Number(r.time) || 0 };
  }
}

export function speedrunStoreFor(store: unknown): SpeedrunStore {
  const s = store as Partial<D1Like> & { kind?: string } | null;
  if (s && s.kind === 'd1' && typeof s.query === 'function' && typeof s.write === 'function') return new D1SpeedrunStore(s as D1Like);
  return new MemorySpeedrunStore();
}

export interface SpeedrunDeps<W> {
  store: () => unknown;
  send: (ws: W, data: object) => void;
  keyOf: (ws: W, msg: Record<string, unknown>) => string | undefined;
  nameOf: (ws: W) => string;
  now?: () => number;
  log?: (level: string, msg: string) => void;
}

export class SpeedrunService<W> {
  private st: SpeedrunStore | null = null;
  private ready: Promise<void> | null = null;
  private submits = new Map<string, number[]>();
  private puts = new Map<string, number[]>();
  private gets = new Map<string, number[]>();
  private recent = new Map<string, SpeedrunRow>();
  constructor(private deps: SpeedrunDeps<W>) {}

  private now(): number { return this.deps.now ? this.deps.now() : Date.now(); }

  store(): SpeedrunStore {
    const want = speedrunStoreFor(this.deps.store());
    if (!this.st || this.st.kind !== want.kind) {
      this.st = want;
      this.ready = want.ensure().catch(e => { this.deps.log?.('WARN', `SPEEDRUN store not ready: ${String(e).slice(0, 120)}`); });
    }
    return this.st;
  }

  private async open(): Promise<SpeedrunStore> {
    const s = this.store();
    if (this.ready) await this.ready;
    return s;
  }

  private limited(pkey: string, map = this.submits, max = SR_SUBMITS_PER_HOUR): boolean {
    const now = this.now();
    const list = (map.get(pkey) ?? []).filter(t => now - t < 3_600_000);
    if (list.length >= max) { map.set(pkey, list); return true; }
    list.push(now);
    map.set(pkey, list);
    return false;
  }

  private remember(r: SpeedrunRow): void {
    const now = this.now();
    for (const [k, x] of this.recent) if (now - x.at > SR_RECENT_MS) this.recent.delete(k);
    this.recent.set(`${r.pkey}:${r.id}`, { ...r, splits: [...r.splits] });
  }

  handle(ws: W, msg: Record<string, unknown>): Promise<void> {
    if (msg.type === 'speedrun_submit') return this.submit(ws, msg);
    if (msg.type === 'speedrun_board') return this.board(ws, msg);
    if (msg.type === 'speedrun_replay_put') return this.putReplay(ws, msg);
    if (msg.type === 'speedrun_replay_get') return this.getReplay(ws, msg);
    return Promise.resolve();
  }

  async putReplay(ws: W, msg: Record<string, unknown>): Promise<void> {
    const id = String(msg.id);
    const reply = (ok: boolean, extra: object = {}) => this.deps.send(ws, { type: 'speedrun_replay_saved', id, ok, ...extra });
    const pkey = this.deps.keyOf(ws, msg);
    if (!pkey) { reply(false, { reason: 'no_identity' }); return; }
    const z = String(msg.z);
    const n = Number(msg.n);
    try {
      const s = await this.open();
      const row = this.recent.get(`${pkey}:${id}`) ?? await s.get(pkey, id);
      if (!row) { reply(false, { reason: 'no_run' }); return; }
      const rp = readReplay(z, n);
      if (!rp || (rp.time !== null && Math.abs(rp.time - row.time) > 0.5)) { reply(false, { reason: 'replay_data' }); return; }
      const mine = bestPerPlayer(await s.board({ cat: row.cat, deck: row.deck, stake: row.stake, seed_type: row.seed_type }, 2000)).find(x => x.pkey === pkey);
      if (mine && mine.id !== id && mine.time < row.time) { reply(false, { reason: 'not_best' }); return; }
      if (this.limited(pkey, this.puts, SR_REPLAY_PUTS_PER_HOUR)) { reply(false, { reason: 'rate_limited' }); return; }
      const rec: ReplayRow = { pkey, id, cat: row.cat, deck: row.deck, stake: row.stake, seed_type: row.seed_type, bytes: n, at: this.now(), z };
      s.putReplay(rec);
      s.dropReplays(rec);
      reply(true);
    } catch (e) {
      this.deps.log?.('WARN', `SPEEDRUN replay put failed: ${String(e).slice(0, 120)}`);
      reply(false, { reason: 'unavailable' });
    }
  }

  async getReplay(ws: W, msg: Record<string, unknown>): Promise<void> {
    const id = String(msg.id);
    const reply = (ok: boolean, extra: object = {}) => this.deps.send(ws, { type: 'speedrun_replay', id, ok, ...extra });
    const who = this.deps.keyOf(ws, msg) ?? 'anon';
    if (this.limited(who, this.gets, SR_REPLAY_GETS_PER_HOUR)) { reply(false, { reason: 'rate_limited' }); return; }
    try {
      const s = await this.open();
      const hit = await s.getReplay(id);
      if (!hit) { reply(false, { reason: 'missing' }); return; }
      reply(true, { z: hit.z, n: hit.bytes, name: hit.name, time: hit.time });
    } catch (e) {
      this.deps.log?.('WARN', `SPEEDRUN replay get failed: ${String(e).slice(0, 120)}`);
      reply(false, { reason: 'unavailable' });
    }
  }

  async submit(ws: W, msg: Record<string, unknown>): Promise<void> {
    const r = msg.run as Record<string, unknown>;
    const id = String(r.id);
    const reply = (ok: boolean, extra: object = {}) => this.deps.send(ws, { type: 'speedrun_submitted', id, ok, ...extra });
    const pkey = this.deps.keyOf(ws, msg);
    if (!pkey) { reply(false, { reason: 'no_identity' }); return; }
    const run: RunData = { cat: String(r.cat), seed_type: String(r.seed_type), seed: String(r.seed), time: Number(r.time), splits: (r.splits as number[]).map(Number),
      blinds: (r.blinds as number[]).map(Number), hands: (r.hands as number[]).map(Number) };
    if (r.rp !== undefined) {
      const rp = parseDigest(r.rp, SR_CATS[run.cat] || 0);
      if (!rp) { reply(false, { reason: 'replay' }); return; }
      run.rp = rp;
    }
    const bad = plausible(run, this.now());
    if (bad) { reply(false, { reason: bad }); return; }
    try {
      const s = await this.open();
      if (await s.has(pkey, id)) { reply(true, { duplicate: true }); return; }
      if (this.limited(pkey)) { reply(false, { reason: 'rate_limited' }); return; }
      const name = (this.deps.nameOf(ws) || 'Player').slice(0, 24);
      const row: SpeedrunRow = { id, pkey, name, cat: run.cat, deck: String(r.deck), stake: Number(r.stake), seed_type: run.seed_type, seed: run.seed,
        time: run.time, splits: run.splits, at: this.now(), v: Number(r.v) || 1 };
      s.add(row);
      this.remember(row);
      const rows = bestPerPlayer(await s.board({ cat: run.cat, deck: String(r.deck), stake: Number(r.stake), seed_type: run.seed_type }, 2000));
      const rank = rows.findIndex(x => x.pkey === pkey) + 1;
      reply(true, { rank: rank > 0 ? rank : undefined });
    } catch (e) {
      this.deps.log?.('WARN', `SPEEDRUN submit failed: ${String(e).slice(0, 120)}`);
      reply(false, { reason: 'unavailable' });
    }
  }

  async board(ws: W, msg: Record<string, unknown>): Promise<void> {
    const f: BoardFilter = {
      cat: String(msg.cat),
      deck: typeof msg.deck === 'string' ? msg.deck : undefined,
      stake: typeof msg.stake === 'number' ? msg.stake : undefined,
      seed_type: typeof msg.seed_type === 'string' ? msg.seed_type : undefined,
    };
    const limit = typeof msg.limit === 'number' ? msg.limit : 50;
    const pkey = this.deps.keyOf(ws, msg);
    try {
      const s = await this.open();
      const rows = bestPerPlayer(await s.board(f, 2000));
      const mine = pkey ? rows.findIndex(x => x.pkey === pkey) + 1 : 0;
      const top = rows.slice(0, limit);
      let rps = new Set<string>();
      try { rps = await s.replayKeys(top.map(x => x.id)); } catch { rps = new Set<string>(); }
      const shown = top.map((x, i) => ({
        rank: i + 1, name: x.name, time: x.time, deck: x.deck, stake: x.stake, seed_type: x.seed_type, seed: x.seed, at: x.at, splits: x.splits, mine: x.pkey === pkey,
        id: x.id, rp: rps.has(`${x.pkey}:${x.id}`),
      }));
      this.deps.send(ws, { type: 'speedrun_board', cat: f.cat, deck: f.deck ?? 'all', stake: f.stake ?? 0, seed_type: f.seed_type ?? 'all', rows: shown, total: rows.length, my_rank: mine > 0 ? mine : undefined });
    } catch (e) {
      this.deps.log?.('WARN', `SPEEDRUN board failed: ${String(e).slice(0, 120)}`);
      this.deps.send(ws, { type: 'speedrun_board', cat: f.cat, rows: [], total: 0, error: 'unavailable' });
    }
  }
}
