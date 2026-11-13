import { countD1 } from './traffic';
import { localD1Fetch } from './d1_local';
export interface PlayerRow {
  pkey: string;
  name: string;
  rp: number;
  rank: number;
  peak_rp: number;
  best_rank: number;
  season: string;
  xp: number;
  level: number;
  packs: number;
  streak: number;
  recovery: string;
  created: number;
  last_seen: number;
  matches: number;
  wins: number;
}

export interface MatchRow {
  id: string;
  mode: string;
  at: number;
  season: string;
}

export interface MatchPlayerRow {
  match_id: string;
  pkey: string;
  placement: number;
  players: number;
  result: string;
  ante: number;
  score: number;
  rp_delta: number;
  xp: number;
  bot_factor: number;
}

export interface HistoryRow extends MatchPlayerRow {
  mode: string;
  at: number;
}

export interface UnlockRow {
  item: string;
  source: string;
  at: number;
}

export interface SocialPlayerRow {
  pkey: string;
  code: string;
  name: string;
  last_seen: number;
}

export type SocialStatus = 'pending' | 'incoming' | 'accepted';

export interface SocialLinkRow {
  player: SocialPlayerRow;
  status: SocialStatus;
}

export const SOCIAL_SCHEMA = [
  `CREATE TABLE IF NOT EXISTS social_players (
  pkey TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL DEFAULT '',
  last_seen INTEGER NOT NULL
)`,
  `CREATE TABLE IF NOT EXISTS social_links (
  pkey TEXT NOT NULL,
  other TEXT NOT NULL,
  status TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (pkey, other)
)`,
  'CREATE INDEX IF NOT EXISTS social_links_other ON social_links (other)',
];

export interface RankedStore {
  readonly kind: string;
  socialInit(): Promise<void>;
  socialUpsert(p: SocialPlayerRow): void;
  socialByCode(code: string): Promise<SocialPlayerRow | null>;
  socialLinks(pkey: string): Promise<SocialLinkRow[]>;
  socialSetLink(pkey: string, other: string, status: SocialStatus, at: number): void;
  socialDeleteLink(pkey: string, other: string): void;
  getPlayer(pkey: string): Promise<PlayerRow | null>;
  findRecovery(code: string): Promise<PlayerRow | null>;
  getUnlocks(pkey: string): Promise<UnlockRow[]>;
  getEquipped(pkey: string): Promise<Record<string, string>>;
  history(pkey: string, limit: number): Promise<HistoryRow[]>;
  leaderboard(season: string, limit: number): Promise<PlayerRow[]>;
  position(season: string, rp: number): Promise<number>;
  savePlayer(p: PlayerRow): void;
  saveMatch(m: MatchRow, rows: MatchPlayerRow[]): void;
  addUnlock(pkey: string, item: string, source: string, at: number): void;
  setEquipped(pkey: string, slot: string, item: string | null): void;
  ensureSeason(id: string, starts: number, ends: number, name: string): void;
  pending(): number;
}

export class MemoryStore implements RankedStore {
  readonly kind = 'memory';
  players = new Map<string, PlayerRow>();
  matches = new Map<string, MatchRow>();
  matchPlayers: MatchPlayerRow[] = [];
  unlocks = new Map<string, UnlockRow[]>();
  equipped = new Map<string, Record<string, string>>();
  seasons = new Map<string, { starts: number; ends: number; name: string }>();
  socialPlayers = new Map<string, SocialPlayerRow>();
  socialLinkRows = new Map<string, Map<string, SocialStatus>>();

  async socialInit(): Promise<void> { return; }
  socialUpsert(p: SocialPlayerRow): void {
    const old = this.socialPlayers.get(p.pkey);
    this.socialPlayers.set(p.pkey, { ...p, name: p.name || old?.name || '' });
  }
  async socialByCode(code: string): Promise<SocialPlayerRow | null> {
    for (const p of this.socialPlayers.values()) if (p.code === code) return { ...p };
    return null;
  }
  async socialLinks(pkey: string): Promise<SocialLinkRow[]> {
    const out: SocialLinkRow[] = [];
    for (const [other, status] of this.socialLinkRows.get(pkey) ?? []) {
      const player = this.socialPlayers.get(other);
      if (player) out.push({ player: { ...player }, status });
    }
    return out;
  }
  socialSetLink(pkey: string, other: string, status: SocialStatus, _at: number): void {
    let m = this.socialLinkRows.get(pkey);
    if (!m) { m = new Map(); this.socialLinkRows.set(pkey, m); }
    m.set(other, status);
  }
  socialDeleteLink(pkey: string, other: string): void { this.socialLinkRows.get(pkey)?.delete(other); }

  async getPlayer(pkey: string): Promise<PlayerRow | null> {
    const p = this.players.get(pkey);
    return p ? { ...p } : null;
  }
  async findRecovery(code: string): Promise<PlayerRow | null> {
    for (const p of this.players.values()) if (p.recovery === code) return { ...p };
    return null;
  }
  async getUnlocks(pkey: string): Promise<UnlockRow[]> { return [...(this.unlocks.get(pkey) ?? [])]; }
  async getEquipped(pkey: string): Promise<Record<string, string>> { return { ...(this.equipped.get(pkey) ?? {}) }; }
  async history(pkey: string, limit: number): Promise<HistoryRow[]> {
    return this.matchPlayers
      .filter(r => r.pkey === pkey)
      .map(r => { const m = this.matches.get(r.match_id); return { ...r, mode: m?.mode ?? '', at: m?.at ?? 0 }; })
      .sort((a, b) => b.at - a.at)
      .slice(0, limit);
  }
  async leaderboard(season: string, limit: number): Promise<PlayerRow[]> {
    return [...this.players.values()]
      .filter(p => p.season === season && p.matches > 0)
      .sort((a, b) => b.rp - a.rp || a.created - b.created)
      .slice(0, limit)
      .map(p => ({ ...p }));
  }
  async position(season: string, rp: number): Promise<number> {
    let n = 1;
    for (const p of this.players.values()) if (p.season === season && p.matches > 0 && p.rp > rp) n++;
    return n;
  }
  savePlayer(p: PlayerRow): void { this.players.set(p.pkey, { ...p }); }
  saveMatch(m: MatchRow, rows: MatchPlayerRow[]): void {
    this.matches.set(m.id, { ...m });
    for (const r of rows) this.matchPlayers.push({ ...r });
  }
  addUnlock(pkey: string, item: string, source: string, at: number): void {
    const list = this.unlocks.get(pkey) ?? [];
    if (!list.some(u => u.item === item)) list.push({ item, source, at });
    this.unlocks.set(pkey, list);
  }
  setEquipped(pkey: string, slot: string, item: string | null): void {
    const e = this.equipped.get(pkey) ?? {};
    if (item) e[slot] = item; else delete e[slot];
    this.equipped.set(pkey, e);
  }
  ensureSeason(id: string, starts: number, ends: number, name: string): void {
    if (!this.seasons.has(id)) this.seasons.set(id, { starts, ends, name });
  }
  pending(): number { return 0; }
}

type FetchFn = (url: string, init: { method: string; headers: Record<string, string>; body: string }) => Promise<{ ok: boolean; status: number; json(): Promise<unknown> }>;

interface Write { sql: string; params: unknown[]; tries: number; bytes: number }

function writeBytes(sql: string, params: unknown[]): number {
  let n = sql.length;
  for (const p of params) n += typeof p === 'string' ? p.length : 8;
  return n;
}

class D1Error extends Error { constructor(msg: string, public status: number) { super(msg); } }

export interface D1Options {
  accountId: string;
  databaseId: string;
  token: string;
  fetch?: FetchFn;
  log?: (level: string, msg: string) => void;
  setTimer?: (fn: () => void, ms: number) => unknown;
  maxQueue?: number;
  maxQueueBytes?: number;
}

const PLAYER_COLS = ['pkey', 'name', 'rp', 'rank', 'peak_rp', 'best_rank', 'season', 'xp', 'level', 'packs', 'streak', 'recovery', 'created', 'last_seen', 'matches', 'wins'] as const;

function num(v: unknown): number { const n = Number(v); return Number.isFinite(n) ? n : 0; }

function toPlayer(r: Record<string, unknown>): PlayerRow {
  return {
    pkey: String(r.pkey), name: String(r.name ?? ''), rp: num(r.rp), rank: num(r.rank), peak_rp: num(r.peak_rp), best_rank: num(r.best_rank),
    season: String(r.season ?? ''), xp: num(r.xp), level: num(r.level) || 1, packs: num(r.packs), streak: num(r.streak),
    recovery: String(r.recovery ?? ''), created: num(r.created), last_seen: num(r.last_seen), matches: num(r.matches), wins: num(r.wins),
  };
}

export class D1Store implements RankedStore {
  readonly kind = 'd1';
  private queue: Write[] = [];
  private flushing = false;
  private failures = 0;
  private timerSet = false;
  private url: string;
  private fetchFn: FetchFn;
  private log: (level: string, msg: string) => void;
  private setTimer: (fn: () => void, ms: number) => unknown;
  private maxQueue: number;
  private maxQueueBytes: number;
  queueBytes = 0;
  dropped = 0;

  constructor(private opts: D1Options) {
    this.url = `https://api.cloudflare.com/client/v4/accounts/${opts.accountId}/d1/database/${opts.databaseId}/query`;
    this.fetchFn = opts.fetch ?? ((u, i) => fetch(u, i) as unknown as ReturnType<FetchFn>);
    this.log = opts.log ?? (() => undefined);
    this.setTimer = opts.setTimer ?? ((fn, ms) => setTimeout(fn, ms));
    this.maxQueue = opts.maxQueue ?? 5000;
    this.maxQueueBytes = opts.maxQueueBytes ?? 24 * 1048576;
  }

  private takeFirst(): void {
    const w = this.queue.shift();
    if (w) this.queueBytes = Math.max(0, this.queueBytes - w.bytes);
  }

  async query(sql: string, params: unknown[] = []): Promise<Record<string, unknown>[]> {
    const res = await this.fetchFn(this.url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${this.opts.token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ sql, params }),
    });
    const body = await res.json().catch(() => null) as { success?: boolean; result?: { results?: Record<string, unknown>[]; meta?: { rows_read?: number; rows_written?: number } }[]; errors?: unknown } | null;
    const ok = !!(res.ok && body && body.success !== false);
    countD1(sql, body?.result?.[0]?.meta, ok);
    if (!ok) throw new D1Error(`d1 ${res.status} ${JSON.stringify(body?.errors ?? null).slice(0, 200)}`, res.status);
    return body?.result?.[0]?.results ?? [];
  }

  enqueue(sql: string, params: unknown[]): void {
    const bytes = writeBytes(sql, params);
    this.queue.push({ sql, params, tries: 0, bytes });
    this.queueBytes += bytes;
    if (this.queue.length > this.maxQueue || (this.queueBytes > this.maxQueueBytes && this.queue.length > 1)) {
      const keep = this.flushing ? 1 : 0;
      while (this.queue.length > keep + 1 && (this.queue.length > this.maxQueue || this.queueBytes > this.maxQueueBytes)) {
        const [w] = this.queue.splice(keep, 1);
        this.queueBytes = Math.max(0, this.queueBytes - w.bytes);
        this.dropped++;
      }
      this.log('WARN', `D1 queue full, dropped the oldest writes (${this.dropped} so far)`);
    }
    if (!this.timerSet) void this.flush();
  }

  async flush(): Promise<boolean> {
    if (this.flushing) return false;
    this.flushing = true;
    try {
      while (this.queue.length > 0) {
        const w = this.queue[0];
        try {
          await this.query(w.sql, w.params);
        } catch (e) {
          w.tries++;
          const st = e instanceof D1Error ? e.status : 0;
          if (st >= 400 && st < 500 && st !== 429 && w.tries >= 3) {
            this.takeFirst();
            this.dropped++;
            this.log('WARN', `D1 refused a write ${w.tries} times (${String(e).slice(0, 120)}), dropped it`);
            continue;
          }
          this.failures++;
          const wait = Math.min(120_000, 2000 * 2 ** Math.min(6, this.failures - 1));
          this.log('WARN', `D1 write failed (${String(e).slice(0, 120)}), ${this.queue.length} queued, retry in ${wait} ms`);
          this.timerSet = true;
          this.setTimer(() => { this.timerSet = false; void this.flush(); }, wait);
          return false;
        }
        this.takeFirst();
        this.failures = 0;
      }
      return true;
    } finally {
      this.flushing = false;
    }
  }

  pending(): number { return this.queue.length; }

  write(sql: string, params: unknown[]): void { this.enqueue(sql, params); }

  async socialInit(): Promise<void> {
    for (const sql of SOCIAL_SCHEMA) await this.query(sql);
  }

  socialUpsert(p: SocialPlayerRow): void {
    this.enqueue(`INSERT INTO social_players (pkey, code, name, last_seen) VALUES (?, ?, ?, ?)
      ON CONFLICT (pkey) DO UPDATE SET name = CASE WHEN excluded.name = '' THEN social_players.name ELSE excluded.name END, last_seen = excluded.last_seen`,
      [p.pkey, p.code, p.name, p.last_seen]);
  }

  async socialByCode(code: string): Promise<SocialPlayerRow | null> {
    const rows = await this.query('SELECT pkey, code, name, last_seen FROM social_players WHERE code = ?', [code]);
    return (rows[0] as unknown as SocialPlayerRow) ?? null;
  }

  async socialLinks(pkey: string): Promise<SocialLinkRow[]> {
    const rows = await this.query(`SELECT p.pkey AS pkey, p.code AS code, p.name AS name, p.last_seen AS last_seen, l.status AS status
      FROM social_links l JOIN social_players p ON p.pkey = l.other WHERE l.pkey = ?`, [pkey]);
    return rows.map(r => ({
      player: { pkey: String(r.pkey), code: String(r.code), name: String(r.name), last_seen: Number(r.last_seen) },
      status: r.status as SocialStatus,
    }));
  }

  socialSetLink(pkey: string, other: string, status: SocialStatus, at: number): void {
    this.enqueue(`INSERT INTO social_links (pkey, other, status, at) VALUES (?, ?, ?, ?)
      ON CONFLICT (pkey, other) DO UPDATE SET status = excluded.status, at = excluded.at`, [pkey, other, status, at]);
  }

  socialDeleteLink(pkey: string, other: string): void {
    this.enqueue('DELETE FROM social_links WHERE pkey = ? AND other = ?', [pkey, other]);
  }

  async getPlayer(pkey: string): Promise<PlayerRow | null> {
    const rows = await this.query('SELECT * FROM players WHERE pkey = ?', [pkey]);
    return rows[0] ? toPlayer(rows[0]) : null;
  }
  async findRecovery(code: string): Promise<PlayerRow | null> {
    const rows = await this.query('SELECT * FROM players WHERE recovery = ?', [code]);
    return rows[0] ? toPlayer(rows[0]) : null;
  }
  async getUnlocks(pkey: string): Promise<UnlockRow[]> {
    const rows = await this.query('SELECT item, source, at FROM unlocks WHERE pkey = ?', [pkey]);
    return rows.map(r => ({ item: String(r.item), source: String(r.source ?? ''), at: num(r.at) }));
  }
  async getEquipped(pkey: string): Promise<Record<string, string>> {
    const rows = await this.query('SELECT slot, item FROM equipped WHERE pkey = ?', [pkey]);
    const out: Record<string, string> = {};
    for (const r of rows) out[String(r.slot)] = String(r.item);
    return out;
  }
  async history(pkey: string, limit: number): Promise<HistoryRow[]> {
    const rows = await this.query(
      'SELECT mp.*, m.mode AS mode, m.at AS at FROM match_players mp JOIN matches m ON m.id = mp.match_id WHERE mp.pkey = ? ORDER BY m.at DESC LIMIT ?',
      [pkey, limit]);
    return rows.map(r => ({
      match_id: String(r.match_id), pkey, placement: num(r.placement), players: num(r.players), result: String(r.result ?? ''),
      ante: num(r.ante), score: num(r.score), rp_delta: num(r.rp_delta), xp: num(r.xp), bot_factor: num(r.bot_factor), mode: String(r.mode ?? ''), at: num(r.at),
    }));
  }
  async leaderboard(season: string, limit: number): Promise<PlayerRow[]> {
    const rows = await this.query('SELECT * FROM players WHERE season = ? AND matches > 0 ORDER BY rp DESC, created ASC LIMIT ?', [season, limit]);
    return rows.map(toPlayer);
  }
  async position(season: string, rp: number): Promise<number> {
    const rows = await this.query('SELECT COUNT(*) AS n FROM players WHERE season = ? AND matches > 0 AND rp > ?', [season, rp]);
    return num(rows[0]?.n) + 1;
  }
  savePlayer(p: PlayerRow): void {
    const cols = PLAYER_COLS.join(', ');
    const marks = PLAYER_COLS.map(() => '?').join(', ');
    const sets = PLAYER_COLS.filter(c => c !== 'pkey').map(c => `${c} = excluded.${c}`).join(', ');
    this.enqueue(`INSERT INTO players (${cols}) VALUES (${marks}) ON CONFLICT(pkey) DO UPDATE SET ${sets}`, PLAYER_COLS.map(c => p[c]));
  }
  saveMatch(m: MatchRow, rows: MatchPlayerRow[]): void {
    this.enqueue('INSERT OR IGNORE INTO matches (id, mode, at, season) VALUES (?, ?, ?, ?)', [m.id, m.mode, m.at, m.season]);
    for (const r of rows) {
      this.enqueue('INSERT OR IGNORE INTO match_players (match_id, pkey, placement, players, result, ante, score, rp_delta, xp, bot_factor) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [r.match_id, r.pkey, r.placement, r.players, r.result, r.ante, r.score, r.rp_delta, r.xp, r.bot_factor]);
    }
  }
  addUnlock(pkey: string, item: string, source: string, at: number): void {
    this.enqueue('INSERT OR IGNORE INTO unlocks (pkey, item, source, at) VALUES (?, ?, ?, ?)', [pkey, item, source, at]);
  }
  setEquipped(pkey: string, slot: string, item: string | null): void {
    if (item) this.enqueue('INSERT INTO equipped (pkey, slot, item) VALUES (?, ?, ?) ON CONFLICT(pkey, slot) DO UPDATE SET item = excluded.item', [pkey, slot, item]);
    else this.enqueue('DELETE FROM equipped WHERE pkey = ? AND slot = ?', [pkey, slot]);
  }
  ensureSeason(id: string, starts: number, ends: number, name: string): void {
    this.enqueue('INSERT OR IGNORE INTO seasons (id, starts, ends, name) VALUES (?, ?, ?, ?)', [id, starts, ends, name]);
  }
}

export function storeFromEnv(env: Record<string, string | undefined>, log?: (level: string, msg: string) => void): RankedStore {
  const accountId = env.CF_ACCOUNT_ID, databaseId = env.CF_D1_DATABASE_ID, token = env.CF_API_TOKEN;
  if (env.D1_LOCAL_FILE) return new D1Store({ accountId: 'local', databaseId: 'local', token: 'local', log, fetch: localD1Fetch(env.D1_LOCAL_FILE) as unknown as FetchFn });
  if (accountId && databaseId && token) return new D1Store({ accountId, databaseId, token, log });
  return new MemoryStore();
}

export const DATA_EPOCH = '2026-11-07-clean-launch';
export const WIPE_KEEP = new Set(['data_meta', 'seasons', 'd1_migrations']);

type QueryFn = (sql: string, params?: unknown[]) => Promise<Record<string, unknown>[]>;

export async function wipeForEpoch(store: { kind: string; query?: QueryFn }, epoch = DATA_EPOCH, log: (level: string, msg: string) => void = () => undefined): Promise<string[]> {
  if (store.kind !== 'd1' || typeof store.query !== 'function') return [];
  const q = store.query.bind(store) as QueryFn;
  await q('CREATE TABLE IF NOT EXISTS data_meta (k TEXT PRIMARY KEY, v TEXT NOT NULL)');
  const cur = await q('SELECT v FROM data_meta WHERE k = ?', ['epoch']);
  if (cur[0] && String(cur[0].v) === epoch) return [];
  const rows = await q("SELECT name FROM sqlite_master WHERE type = 'table'");
  const tables = rows.map(r => String(r.name)).filter(n => !n.startsWith('_cf_') && !n.startsWith('sqlite_') && !WIPE_KEEP.has(n) && /^[a-z0-9_]+$/i.test(n));
  for (const t of tables) await q(`DELETE FROM "${t}"`);
  await q('INSERT OR REPLACE INTO data_meta (k, v) VALUES (?, ?)', ['epoch', epoch]);
  log('WARN', `data epoch ${epoch}: emptied ${tables.join(', ') || 'nothing'}`);
  return tables;
}
