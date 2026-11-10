export const DAILY_TYPES = ['daily_submit', 'daily_board'];
export const DAILY_TOP = 20;
export const DAILY_KEEP_DAYS = 40;

const DAY_RE = /^\d{4}-\d{2}-\d{2}$/;
const SIG_RE = /^[A-Za-z0-9_-]{1,64}$/;
const PKEY_RE = /^[A-Za-z0-9]{24}$/;
const DAY_MS = 86_400_000;

export interface DailyEntry {
  day: string;
  sig: string;
  pkey: string;
  name: string;
  won: boolean;
  ante: number;
  round: number;
  best: number;
  at: number;
}

export interface DailyRow { name: string; won: boolean; ante: number; round: number; best: number; me?: boolean; rank?: number }
export const DAILY_FRIENDS = 20;

export interface DailyStore {
  readonly kind: string;
  init(): Promise<void>;
  get(day: string, pkey: string): Promise<DailyEntry | null>;
  add(e: DailyEntry): Promise<void>;
  list(day: string, sig: string): Promise<DailyEntry[]>;
  sweep(beforeDay: string): Promise<void>;
}

export function dayOf(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

export function better(a: DailyEntry, b: DailyEntry): boolean {
  if (a.won !== b.won) return a.won;
  if (a.ante !== b.ante) return a.ante > b.ante;
  if (a.best !== b.best) return a.best > b.best;
  if (a.round !== b.round) return a.round < b.round;
  return a.at < b.at;
}

export function sortEntries(list: DailyEntry[]): DailyEntry[] {
  return list.slice().sort((a, b) => (better(a, b) ? -1 : better(b, a) ? 1 : 0));
}

export class MemoryDailyStore implements DailyStore {
  readonly kind = 'memory';
  rows = new Map<string, DailyEntry>();
  async init(): Promise<void> {}
  async get(day: string, pkey: string): Promise<DailyEntry | null> { return this.rows.get(`${day}|${pkey}`) ?? null; }
  async add(e: DailyEntry): Promise<void> {
    const k = `${e.day}|${e.pkey}`;
    if (!this.rows.has(k)) this.rows.set(k, { ...e });
  }
  async list(day: string, sig: string): Promise<DailyEntry[]> {
    return [...this.rows.values()].filter(e => e.day === day && e.sig === sig);
  }
  async sweep(beforeDay: string): Promise<void> {
    for (const [k, e] of this.rows) if (e.day < beforeDay) this.rows.delete(k);
  }
}

export interface D1Like {
  kind?: string;
  query(sql: string, params?: unknown[]): Promise<Record<string, unknown>[]>;
  write(sql: string, params: unknown[]): void;
}

export const DAILY_SCHEMA = [
  `CREATE TABLE IF NOT EXISTS daily_board (day TEXT NOT NULL, pkey TEXT NOT NULL, sig TEXT NOT NULL, name TEXT NOT NULL, won INTEGER NOT NULL, ante INTEGER NOT NULL,
    round INTEGER NOT NULL, best REAL NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (day, pkey))`,
  'CREATE INDEX IF NOT EXISTS daily_board_day_sig ON daily_board (day, sig)',
];

function toEntry(r: Record<string, unknown>): DailyEntry {
  return {
    day: String(r.day), sig: String(r.sig), pkey: String(r.pkey), name: String(r.name ?? ''), won: Number(r.won) === 1,
    ante: Number(r.ante) || 0, round: Number(r.round) || 0, best: Number(r.best) || 0, at: Number(r.at) || 0,
  };
}

export class D1DailyStore implements DailyStore {
  readonly kind = 'd1';
  constructor(private d1: D1Like) {}
  async init(): Promise<void> { for (const sql of DAILY_SCHEMA) await this.d1.query(sql); }
  async get(day: string, pkey: string): Promise<DailyEntry | null> {
    const rows = await this.d1.query('SELECT * FROM daily_board WHERE day = ? AND pkey = ?', [day, pkey]);
    return rows[0] ? toEntry(rows[0]) : null;
  }
  async add(e: DailyEntry): Promise<void> {
    await this.d1.query(`INSERT INTO daily_board (day, pkey, sig, name, won, ante, round, best, at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (day, pkey) DO NOTHING`,
      [e.day, e.pkey, e.sig, e.name, e.won ? 1 : 0, e.ante, e.round, e.best, e.at]);
  }
  async list(day: string, sig: string): Promise<DailyEntry[]> {
    const rows = await this.d1.query('SELECT * FROM daily_board WHERE day = ? AND sig = ?', [day, sig]);
    return rows.map(toEntry);
  }
  async sweep(beforeDay: string): Promise<void> { this.d1.write('DELETE FROM daily_board WHERE day < ?', [beforeDay]); }
}

export function dailyStoreFor(store: unknown): DailyStore {
  const s = store as D1Like | null;
  if (s && s.kind === 'd1' && typeof s.query === 'function' && typeof s.write === 'function') return new D1DailyStore(s);
  return new MemoryDailyStore();
}

function isInt(v: unknown, lo: number, hi: number): boolean {
  return typeof v === 'number' && Number.isInteger(v) && v >= lo && v <= hi;
}

export function validateDaily(msg: Record<string, unknown>): string | null {
  const t = msg.type;
  if (t !== 'daily_submit' && t !== 'daily_board') return null;
  if (typeof msg.day !== 'string' || !DAY_RE.test(msg.day)) return `${t}: invalid day`;
  if (typeof msg.sig !== 'string' || !SIG_RE.test(msg.sig)) return `${t}: invalid sig`;
  if (t === 'daily_submit') {
    if (typeof msg.won !== 'boolean') return 'daily_submit: invalid won';
    if (!isInt(msg.ante, 0, 1000)) return 'daily_submit: invalid ante';
    if (!isInt(msg.round, 0, 100000)) return 'daily_submit: invalid round';
    if (typeof msg.best !== 'number' || !(msg.best >= 0)) return 'daily_submit: invalid best';
  }
  return null;
}

export interface DailyDeps {
  now?: () => number;
  log?: (level: string, tag: string, msg: string) => void;
}

export interface SubmitIn { pkey: string | undefined; name: string; bot?: boolean; day: string; sig: string; won: boolean; ante: number; round: number; best: number }
export type SubmitOut = { ok: true; rank: number; total: number } | { ok: false; reason: string; rank?: number; total?: number };
export interface BoardOut { top: DailyRow[]; rank: number | null; total: number; me: DailyRow | null; played: boolean; friends?: DailyRow[] }

export class DailyBoard {
  private pending = new Set<string>();
  private ready: Promise<void> | null = null;
  private lastSweep = '';
  constructor(readonly store: DailyStore, private deps: DailyDeps = {}) {}

  private now(): number { return this.deps.now ? this.deps.now() : Date.now(); }

  ensure(): Promise<void> {
    if (!this.ready) this.ready = this.store.init().catch(e => { this.ready = null; throw e; });
    return this.ready;
  }

  dayOpen(day: string): boolean {
    const t = this.now();
    return day === dayOf(t) || day === dayOf(t - DAY_MS);
  }

  private async rankOf(e: DailyEntry): Promise<{ rank: number; total: number; list: DailyEntry[] }> {
    const list = sortEntries(await this.store.list(e.day, e.sig));
    const i = list.findIndex(x => x.pkey === e.pkey);
    return { rank: i >= 0 ? i + 1 : list.filter(x => better(x, e)).length + 1, total: list.length, list };
  }

  async submit(s: SubmitIn): Promise<SubmitOut> {
    if (s.bot) return { ok: false, reason: 'bot' };
    if (!s.pkey || !PKEY_RE.test(s.pkey)) return { ok: false, reason: 'no_key' };
    if (!this.dayOpen(s.day)) return { ok: false, reason: 'closed' };
    await this.ensure();
    const k = `${s.day}|${s.pkey}`;
    if (this.pending.has(k)) return { ok: false, reason: 'already' };
    this.pending.add(k);
    try {
      const old = await this.store.get(s.day, s.pkey);
      if (old) {
        const r = await this.rankOf(old);
        return { ok: false, reason: 'already', rank: r.rank, total: r.total };
      }
      const e: DailyEntry = {
        day: s.day, sig: s.sig, pkey: s.pkey, name: s.name.slice(0, 24) || 'Player', won: s.won,
        ante: s.ante, round: s.round, best: Math.min(s.best, Number.MAX_VALUE), at: this.now(),
      };
      await this.store.add(e);
      this.deps.log?.('INFO', 'DAILY', `${s.day} ${e.name}: ${e.won ? 'won' : 'lost'} ante ${e.ante}`);
      this.sweep();
      const r = await this.rankOf(e);
      return { ok: true, rank: r.rank, total: r.total };
    } finally {
      this.pending.delete(k);
    }
  }

  async board(pkey: string | undefined, day: string, sig: string, friends?: string[]): Promise<BoardOut> {
    await this.ensure();
    const list = sortEntries(await this.store.list(day, sig));
    const mine = pkey ? await this.store.get(day, pkey) : null;
    const row = (e: DailyEntry): DailyRow => {
      const r: DailyRow = { name: e.name, won: e.won, ante: e.ante, round: e.round, best: e.best };
      if (pkey && e.pkey === pkey) r.me = true;
      return r;
    };
    const top = list.slice(0, DAILY_TOP).map(row);
    let rank: number | null = null;
    let me: DailyRow | null = null;
    if (mine && mine.sig === sig) {
      const i = list.findIndex(x => x.pkey === mine.pkey);
      rank = i >= 0 ? i + 1 : null;
      me = row(mine);
    }
    const out: BoardOut = { top, rank, total: list.length, me, played: mine !== null };
    if (friends) {
      const set = new Set(friends);
      if (pkey) set.add(pkey);
      out.friends = [];
      for (let i = 0; i < list.length && out.friends.length < DAILY_FRIENDS; i++) {
        if (set.has(list[i].pkey)) out.friends.push({ ...row(list[i]), rank: i + 1 });
      }
    }
    return out;
  }

  sweep(): void {
    const today = dayOf(this.now());
    if (this.lastSweep === today) return;
    this.lastSweep = today;
    void this.store.sweep(dayOf(this.now() - DAILY_KEEP_DAYS * DAY_MS)).catch(() => undefined);
  }
}

export let daily = new DailyBoard(new MemoryDailyStore());
export function setDaily(d: DailyBoard): void { daily = d; }

export interface DailyHandlerDeps<W> {
  keyOf: (ws: W, msg: Record<string, unknown>) => string | undefined;
  isBot: (ws: W) => boolean;
  send: (ws: W, data: object) => void;
  nameFor: (ws: W, msg: Record<string, unknown>) => string;
  friendsOf?: (pkey: string) => Promise<string[]>;
  onSubmit?: (pkey: string, row: { won: boolean; ante: number; rank: number; total: number }) => void;
}

export function dailyHandlers<W>(d: DailyHandlerDeps<W>): Record<string, (ws: W, msg: Record<string, unknown>) => void> {
  return {
    daily_submit: (ws, msg) => {
      const day = String(msg.day), sig = String(msg.sig);
      daily.submit({
        pkey: d.keyOf(ws, msg), name: d.nameFor(ws, msg), bot: d.isBot(ws), day, sig,
        won: msg.won === true, ante: Number(msg.ante), round: Number(msg.round), best: Number(msg.best),
      }).then(r => {
        d.send(ws, { type: 'daily_submitted', day, sig, ...r });
        const k = d.keyOf(ws, msg);
        if (r.ok && k && d.onSubmit) d.onSubmit(k, { won: msg.won === true, ante: Number(msg.ante), rank: r.rank, total: r.total });
      })
        .catch(() => d.send(ws, { type: 'daily_submitted', day, sig, ok: false, reason: 'unavailable' }));
    },
    daily_board: (ws, msg) => {
      const day = String(msg.day), sig = String(msg.sig);
      const k = d.keyOf(ws, msg);
      const friends = k && d.friendsOf ? d.friendsOf(k).catch(() => undefined) : Promise.resolve(undefined);
      friends.then(f => daily.board(k, day, sig, f))
        .then(r => d.send(ws, { type: 'daily_board', day, sig, ...r }))
        .catch(() => d.send(ws, { type: 'daily_board', day, sig, top: [], rank: null, total: 0, me: null, played: false, error: 'unavailable' }));
    },
  };
}
