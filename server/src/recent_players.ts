import { D1Store, type RankedStore } from './ranked_store';

export const RECENT_TYPES = ['social_recent', 'social_h2h'];
export const RECENT_SCHEMA = [
  `CREATE TABLE IF NOT EXISTS recent_players (
  pkey TEXT NOT NULL,
  other TEXT NOT NULL,
  name TEXT NOT NULL,
  mode TEXT NOT NULL,
  ranked INTEGER NOT NULL DEFAULT 0,
  at INTEGER NOT NULL,
  PRIMARY KEY (pkey, other)
)`,
  'CREATE INDEX IF NOT EXISTS recent_players_at ON recent_players (pkey, at)',
  `CREATE TABLE IF NOT EXISTS head_to_head (
  pkey TEXT NOT NULL,
  other TEXT NOT NULL,
  wins INTEGER NOT NULL DEFAULT 0,
  losses INTEGER NOT NULL DEFAULT 0,
  draws INTEGER NOT NULL DEFAULT 0,
  at INTEGER NOT NULL,
  PRIMARY KEY (pkey, other)
)`,
];
export const RECENT_KEEP = 20;
export const RECENT_GAP_MS = 2000;
export const RECENT_SEATS_MAX = 8;
export const MODE_RE = /^[a-z][a-z0-9_]{0,23}$/;
const PKEY_RE = /^[A-Za-z0-9]{24}$/;

export interface MetRow { pkey: string; other: string; name: string; mode: string; ranked: boolean; at: number }
export interface MetSeat { pkey: string; name: string }
export interface Record3 { w: number; l: number; d: number }
export interface H2hRow { pkey: string; other: string; w: number; l: number; d: number; at: number }
export interface ResultSeat { pkey?: string; bot?: boolean; result: string }

export interface RecentStore {
  init(): Promise<void>;
  list(pkey: string): Promise<MetRow[]>;
  put(rows: MetRow[]): void;
  records(pkey: string, others: string[]): Promise<H2hRow[]>;
  bump(rows: H2hRow[]): void;
}

function newestFirst(a: MetRow, b: MetRow): number {
  return b.at - a.at || a.other.localeCompare(b.other);
}

export class MemoryRecent implements RecentStore {
  rows = new Map<string, Map<string, MetRow>>();
  h2h = new Map<string, H2hRow>();
  async records(pkey: string, others: string[]): Promise<H2hRow[]> {
    const out: H2hRow[] = [];
    for (const o of others) { const r = this.h2h.get(`${pkey}|${o}`); if (r) out.push({ ...r }); }
    return out;
  }
  bump(rows: H2hRow[]): void {
    for (const r of rows) {
      const k = `${r.pkey}|${r.other}`;
      const old = this.h2h.get(k) ?? { pkey: r.pkey, other: r.other, w: 0, l: 0, d: 0, at: 0 };
      this.h2h.set(k, { ...old, w: old.w + r.w, l: old.l + r.l, d: old.d + r.d, at: r.at });
    }
  }
  async init(): Promise<void> { return; }
  async list(pkey: string): Promise<MetRow[]> {
    return [...(this.rows.get(pkey)?.values() ?? [])].sort(newestFirst).slice(0, RECENT_KEEP).map(r => ({ ...r }));
  }
  put(rows: MetRow[]): void {
    for (const r of rows) {
      let mine = this.rows.get(r.pkey);
      if (!mine) { mine = new Map(); this.rows.set(r.pkey, mine); }
      mine.set(r.other, { ...r });
      if (mine.size > RECENT_KEEP) {
        const keep = new Set([...mine.values()].sort(newestFirst).slice(0, RECENT_KEEP).map(x => x.other));
        for (const k of [...mine.keys()]) if (!keep.has(k)) mine.delete(k);
      }
    }
  }
}

export class D1Recent implements RecentStore {
  constructor(private d1: D1Store) {}
  async init(): Promise<void> {
    for (const sql of RECENT_SCHEMA) await this.d1.query(sql);
  }
  async list(pkey: string): Promise<MetRow[]> {
    const rows = await this.d1.query('SELECT pkey, other, name, mode, ranked, at FROM recent_players WHERE pkey = ? ORDER BY at DESC LIMIT ?', [pkey, RECENT_KEEP]);
    return rows.map(r => ({ pkey: String(r.pkey), other: String(r.other), name: String(r.name), mode: String(r.mode), ranked: Number(r.ranked) === 1, at: Number(r.at) }));
  }
  async records(pkey: string, others: string[]): Promise<H2hRow[]> {
    const out: H2hRow[] = [];
    for (let i = 0; i < others.length; i += 50) {
      const chunk = others.slice(i, i + 50);
      const rows = await this.d1.query(`SELECT pkey, other, wins, losses, draws, at FROM head_to_head WHERE pkey = ? AND other IN (${chunk.map(() => '?').join(', ')})`, [pkey, ...chunk]);
      for (const r of rows) out.push({ pkey: String(r.pkey), other: String(r.other), w: Number(r.wins), l: Number(r.losses), d: Number(r.draws), at: Number(r.at) });
    }
    return out;
  }
  bump(rows: H2hRow[]): void {
    for (const r of rows) {
      this.d1.enqueue(`INSERT INTO head_to_head (pkey, other, wins, losses, draws, at) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (pkey, other) DO UPDATE SET wins = wins + excluded.wins, losses = losses + excluded.losses, draws = draws + excluded.draws, at = excluded.at`,
      [r.pkey, r.other, r.w, r.l, r.d, r.at]);
    }
  }
  put(rows: MetRow[]): void {
    const owners = new Set<string>();
    for (const r of rows) {
      this.d1.enqueue(`INSERT INTO recent_players (pkey, other, name, mode, ranked, at) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (pkey, other) DO UPDATE SET name = excluded.name, mode = excluded.mode, ranked = excluded.ranked, at = excluded.at`,
      [r.pkey, r.other, r.name, r.mode, r.ranked ? 1 : 0, r.at]);
      owners.add(r.pkey);
    }
    for (const pkey of owners) {
      this.d1.enqueue(`DELETE FROM recent_players WHERE pkey = ? AND other NOT IN
        (SELECT other FROM recent_players WHERE pkey = ? ORDER BY at DESC LIMIT ?)`, [pkey, pkey, RECENT_KEEP]);
    }
  }
}

export function recentStoreFor(store: RankedStore): RecentStore {
  if (store instanceof D1Store) return new D1Recent(store);
  return new MemoryRecent();
}

export interface RecentSocket { data: { recentAt?: number; h2hAt?: number } }

export interface RecentLink { code: string; name: string; online: boolean; friend: boolean; pending: boolean; incoming: boolean; rank?: unknown; dev?: true }

export interface RecentDeps<WS> {
  send(ws: WS, data: object): void;
  describe(me: string, others: string[]): Promise<Map<string, RecentLink>>;
  friends?(me: string): Promise<{ pkey: string; code: string }[]>;
  log?(level: string, msg: string): void;
}

export function cleanMode(v: unknown): string {
  return typeof v === 'string' && MODE_RE.test(v) ? v : 'match';
}

export class RecentPlayers<WS extends RecentSocket> {
  private ready: Promise<void> | null = null;

  constructor(private store: RecentStore, private deps: RecentDeps<WS>, private now: () => number = Date.now) {}

  ensure(): Promise<void> {
    if (!this.ready) this.ready = this.store.init().catch(e => { this.ready = null; throw e; });
    return this.ready;
  }

  met(seats: MetSeat[], mode: unknown, ranked = false): void {
    const seen = new Map<string, MetSeat>();
    for (const s of seats.slice(0, RECENT_SEATS_MAX)) {
      if (!s || typeof s.pkey !== 'string' || !PKEY_RE.test(s.pkey) || seen.has(s.pkey)) continue;
      seen.set(s.pkey, { pkey: s.pkey, name: String(s.name ?? '').slice(0, 32) });
    }
    if (seen.size < 2) return;
    const at = this.now();
    const m = cleanMode(mode);
    const rows: MetRow[] = [];
    for (const a of seen.values()) for (const b of seen.values()) {
      if (a.pkey !== b.pkey) rows.push({ pkey: a.pkey, other: b.pkey, name: b.name, mode: m, ranked: ranked === true, at });
    }
    this.ensure().then(() => this.store.put(rows)).catch(e => this.deps.log?.('WARN', `recent players not saved: ${String(e).slice(0, 120)}`));
  }

  played(seats: ResultSeat[]): void {
    if (seats.length !== 2) return;
    const [a, b] = seats;
    if (!a || !b || a.bot || b.bot || !a.pkey || !b.pkey || a.pkey === b.pkey) return;
    if (!PKEY_RE.test(a.pkey) || !PKEY_RE.test(b.pkey)) return;
    const at = this.now();
    const one = (x: ResultSeat, y: ResultSeat): H2hRow => ({
      pkey: x.pkey as string, other: y.pkey as string, at,
      w: x.result === 'win' ? 1 : 0, l: x.result === 'lose' ? 1 : 0, d: x.result === 'draw' ? 1 : 0,
    });
    const rows = [one(a, b), one(b, a)].filter(r => r.w + r.l + r.d === 1);
    if (rows.length !== 2) return;
    this.ensure().then(() => this.store.bump(rows)).catch(e => this.deps.log?.('WARN', `head to head not saved: ${String(e).slice(0, 120)}`));
  }

  private async recordMap(me: string, others: string[]): Promise<Map<string, Record3>> {
    const out = new Map<string, Record3>();
    if (others.length === 0) return out;
    for (const r of await this.store.records(me, others)) if (r.w + r.l + r.d > 0) out.set(r.other, { w: r.w, l: r.l, d: r.d });
    return out;
  }

  async handle(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    if (msg.type === 'social_h2h') return this.h2hList(ws, me);
    if (msg.type !== 'social_recent') return;
    const t = this.now();
    if (t - (ws.data.recentAt ?? 0) < RECENT_GAP_MS) return;
    ws.data.recentAt = t;
    await this.ensure();
    const rows = await this.store.list(me);
    const info = await this.deps.describe(me, rows.map(r => r.other));
    const recs = await this.recordMap(me, rows.map(r => r.other));
    const items: object[] = [];
    for (const r of rows) {
      const l = info.get(r.other);
      if (!l) continue;
      items.push({
        code: l.code, name: l.name !== '' ? l.name : r.name, mode: r.mode, ranked: r.ranked || undefined, at: r.at, rank: l.rank, dev: l.dev,
        online: l.online, friend: l.friend || undefined, pending: (l.pending && !l.friend) || undefined, incoming: l.incoming || undefined,
        h2h: recs.get(r.other),
      });
    }
    this.deps.send(ws, { type: 'social_recent', items });
  }

  private async h2hList(ws: WS, me: string): Promise<void> {
    const t = this.now();
    if (t - (ws.data.h2hAt ?? 0) < RECENT_GAP_MS) return;
    ws.data.h2hAt = t;
    await this.ensure();
    const friends = this.deps.friends ? await this.deps.friends(me) : [];
    const recs = await this.recordMap(me, friends.map(f => f.pkey));
    const items: Record<string, Record3> = {};
    for (const f of friends) { const r = recs.get(f.pkey); if (r) items[f.code] = r; }
    this.deps.send(ws, { type: 'social_h2h', items });
  }
}
