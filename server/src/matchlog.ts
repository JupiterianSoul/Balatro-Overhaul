import { deflateRawSync, inflateRawSync } from 'node:zlib';
import type { Who } from './identity';
import type { MatchIn } from './ranked';
import { checkMessage, newTrack, lifeGainAllowed, scoreText, type Flag, type Track } from './integrity';

export interface LogMod { id: string; version: string }
export interface LogPlayer extends Who { pid: number; version: string; mods: LogMod[]; rec?: string }

export interface LogHeader {
  id: string;
  v: 1;
  mode: string;
  ranked: boolean;
  private?: boolean;
  kind: '1v1' | 'party';
  settings: Record<string, unknown>;
  ruleset: unknown;
  seeds: string[];
  players: LogPlayer[];
  started_at: number;
}

export interface LogEvent { t: number; pid: number; e: string; [k: string]: unknown }
export interface LogResult { pid: number; placement: number; result: string; score: string }
export interface LogRating { pid: number; before: number; after: number; delta: number }

export interface LogEnd {
  reason: string;
  ended_at: number;
  results: LogResult[];
  rating: LogRating[];
  flags: Flag[];
  held: boolean;
  truncated?: boolean;
}

export type LogStatus = '' | 'held' | 'apply' | 'void' | 'applied' | 'voided';

export interface StoredLog {
  header: LogHeader;
  events: LogEvent[];
  end: LogEnd | null;
  streams: Record<string, unknown[]>;
  status?: LogStatus;
  contested?: boolean;
  keys?: Record<string, string>;
  rate?: MatchIn | null;
  applied?: Record<string, number>;
}

export interface HistoryItem {
  id: string;
  at: number;
  mode: string;
  ranked: boolean;
  players: Who[];
  result: string | null;
  placement: number | null;
  rp_delta: number | null;
  has_replay: boolean;
  status?: LogStatus;
}

export interface LogRow {
  id: string; at: number; ended: number; mode: string; kind: string; ranked: boolean; status: LogStatus;
  keep_until: number | null; has_replay: boolean; bytes: number; data: string;
}

export interface LogPlayerRow { id: string; pkey: string; pid: number; at: number; keep_until: number | null; item: HistoryItem }

export const CAPS = {
  events: 192_000,
  stream: 1_000_000,
  streams: 3_000_000,
  stored: 900_000,
  liveMs: 2000,
  pending: 32,
  batch: 500,
  recent: 200,
  recentMs: 3 * 3_600_000,
  liveMaxMs: 8 * 3_600_000,
  lateMs: 20_000,
};
export const CASUAL_KEEP_MS = 60 * 86_400_000;
export const CONTEST_WINDOW_MS = 30 * 60_000;
export const CONTEST_REASON_MAX = 200;

interface StreamState { seq: number; entries: unknown[]; bytes: number; pending: Map<number, unknown[]>; full: boolean }

const BLIND_LETTER: Record<string, string> = { S: 'S', B: 'B', L: 'L', Small: 'S', Big: 'B', Boss: 'L' };

export function blindLetter(v: unknown): string | null {
  return typeof v === 'string' ? BLIND_LETTER[v] ?? null : null;
}

function short(v: unknown, n = 64): string | null {
  if (typeof v === 'string') return v.slice(0, n);
  if (typeof v === 'number' && Number.isFinite(v)) return String(v);
  return null;
}

function count(v: unknown): number | null {
  const n = typeof v === 'string' && /^\d+$/.test(v) ? Number(v) : v;
  return typeof n === 'number' && Number.isInteger(n) && n >= 0 && n <= 1000 ? n : null;
}

function size(v: unknown): number { return JSON.stringify(v).length + 1; }

export function encodeLog(rec: StoredLog): string {
  return Buffer.from(deflateRawSync(Buffer.from(JSON.stringify(rec), 'utf8'))).toString('base64');
}

export function decodeLog(data: string): StoredLog {
  return JSON.parse(Buffer.from(inflateRawSync(Buffer.from(data, 'base64'), { maxOutputLength: 64 * 1024 * 1024 })).toString('utf8')) as StoredLog;
}

export class MatchLog {
  events: LogEvent[] = [];
  end: LogEnd | null = null;
  streams = new Map<number, StreamState>();
  keys: Record<string, string> = {};
  flags: Flag[] = [];
  contested = false;
  truncated = false;
  rate: MatchIn | null = null;
  applied: Record<string, number> = {};
  status: LogStatus = '';
  lives = new Map<number, number>();
  tracks = new Map<number, Track>();
  pvp = new Map<number, boolean>();
  at = new Map<number, { ante: number | null; blind: string | null }>();
  packed: string | null = null;
  slimmed = false;
  private replayFlag = false;
  private eventBytes = 0;
  private streamBytes = 0;
  private lastLive = new Map<number, number>();

  constructor(public header: LogHeader, private now: () => number = Date.now) {}

  get id(): string { return this.header.id; }

  isBot(pid: number): boolean { return this.header.players.find(p => p.pid === pid)?.is_bot === true; }

  pidOf(pkey: string): number | null {
    for (const [pid, k] of Object.entries(this.keys)) if (k === pkey) return Number(pid);
    return null;
  }

  add(pid: number, e: string, fields: Record<string, unknown> = {}): boolean {
    const t = Math.max(0, this.now() - this.header.started_at);
    if (e === 'live') {
      const last = this.lastLive.get(pid);
      if (last !== undefined && t - last < CAPS.liveMs) return false;
    }
    const ev: LogEvent = { t, pid, e, ...fields };
    const n = size(ev);
    if (this.eventBytes + n > CAPS.events) {
      this.truncated = true;
      if (e === 'live') return false;
      while (this.eventBytes + n > CAPS.events) {
        const i = this.events.findIndex(x => x.e === 'live');
        if (i < 0) return false;
        this.eventBytes -= size(this.events[i]);
        this.events.splice(i, 1);
      }
    }
    if (e === 'live') this.lastLive.set(pid, t);
    this.events.push(ev);
    this.eventBytes += n;
    return true;
  }

  flag(pid: number, f: Flag): void {
    if (!this.flags.some(x => x.code === f.code && x.detail === f.detail)) this.flags.push({ code: f.code, detail: f.detail });
    this.add(pid, 'flag', { code: f.code, detail: f.detail });
  }

  act(pid: number, seq: unknown, a: unknown): 'ok' | 'repeat' | 'full' | 'bad' {
    if (typeof seq !== 'number' || !Number.isInteger(seq) || seq < 1 || !Array.isArray(a) || a.length > CAPS.batch) return 'bad';
    let s = this.streams.get(pid);
    if (!s) { s = { seq: 0, entries: [], bytes: 0, pending: new Map(), full: false }; this.streams.set(pid, s); }
    if (seq <= s.seq || s.pending.has(seq)) return 'repeat';
    if (s.full) return 'full';
    s.pending.set(seq, a);
    if (s.pending.size > CAPS.pending) s.seq = Math.min(...s.pending.keys()) - 1;
    const cap = Math.min(CAPS.stream, Math.floor(CAPS.streams / Math.max(1, this.header.players.length)));
    for (let next = s.pending.get(s.seq + 1); next; next = s.pending.get(s.seq + 1)) {
      s.pending.delete(s.seq + 1);
      s.seq++;
      for (const entry of next) {
        const n = size(entry);
        if (s.bytes + n > cap || this.streamBytes + n > CAPS.streams) { s.full = true; this.truncated = true; s.pending.clear(); return 'full'; }
        s.entries.push(entry);
        s.bytes += n;
        this.streamBytes += n;
      }
    }
    return 'ok';
  }

  hasReplay(): boolean {
    if (this.slimmed) return this.replayFlag;
    for (const s of this.streams.values()) if (s.entries.length > 0) return true;
    return false;
  }

  slim(): void {
    if (this.slimmed || !this.packed) return;
    this.replayFlag = this.hasReplay();
    this.events = [];
    this.streams.clear();
    this.tracks.clear();
    this.slimmed = true;
  }

  streamsRecord(): Record<string, unknown[]> {
    const out: Record<string, unknown[]> = {};
    for (const [pid, s] of this.streams) out[String(pid)] = s.entries;
    return out;
  }

  publicEnd(): LogEnd | null {
    if (!this.end) return null;
    return { ...this.end, flags: [...this.flags], held: this.end.held, ...(this.truncated ? { truncated: true } : {}) };
  }

  record(): StoredLog {
    return {
      header: this.header, events: this.events, end: this.publicEnd(), streams: this.streamsRecord(),
      status: this.status, contested: this.contested, keys: this.keys, rate: this.rate, applied: this.applied,
    };
  }

  static fromStored(rec: StoredLog, now: () => number = Date.now): MatchLog {
    const log = new MatchLog(rec.header, now);
    log.events = rec.events ?? [];
    log.end = rec.end ?? null;
    log.flags = rec.end?.flags ?? [];
    log.truncated = rec.end?.truncated === true;
    log.status = rec.status ?? '';
    log.contested = rec.contested === true;
    log.keys = rec.keys ?? {};
    log.rate = rec.rate ?? null;
    log.applied = rec.applied ?? {};
    for (const [pid, entries] of Object.entries(rec.streams ?? {})) {
      log.streams.set(Number(pid), { seq: 0, entries, bytes: 0, pending: new Map(), full: true });
    }
    return log;
  }

  historyItem(pid: number): HistoryItem {
    const res = this.end?.results.find(r => r.pid === pid);
    const rating = this.end && !this.end.held ? this.end.rating.find(r => r.pid === pid) : undefined;
    return {
      id: this.id, at: this.header.started_at, mode: this.header.mode, ranked: this.header.ranked,
      players: this.header.players.map(p => {
        const w: Who = { pid: p.pid, name: p.name, is_bot: p.is_bot };
        if (p.bot_level) w.bot_level = p.bot_level;
        if (p.rank) w.rank = p.rank;
        return w;
      }),
      result: res?.result ?? null, placement: res?.placement ?? null, rp_delta: rating ? rating.delta : null,
      has_replay: this.hasReplay(), status: this.status,
    };
  }
}

export function finishedItem(it: HistoryItem): boolean {
  return it.result === 'win' || it.result === 'lose' || it.result === 'draw' || typeof it.placement === 'number';
}

function stripSnapshots(streams: Record<string, unknown[]>): boolean {
  let any = false;
  for (const [pid, list] of Object.entries(streams)) {
    streams[pid] = list.map(e => {
      const x = e as { k?: unknown; m?: Record<string, unknown> };
      if (x && x.k === 'rs' && x.m && typeof x.m === 'object' && x.m.snapshot !== undefined) {
        any = true;
        const m = { ...x.m, big: true };
        delete m.snapshot;
        return { ...x, m };
      }
      return e;
    });
  }
  return any;
}

export function packLog(log: MatchLog): { data: string; truncated: boolean } {
  const rec = log.record();
  let data = encodeLog(rec);
  if (data.length <= CAPS.stored) return { data, truncated: false };
  rec.streams = { ...rec.streams };
  if (stripSnapshots(rec.streams)) {
    data = encodeLog(rec);
    if (data.length <= CAPS.stored) return { data, truncated: true };
  }
  const pids = Object.keys(rec.streams).sort((a, b) => size(rec.streams[b]) - size(rec.streams[a]));
  for (const pid of pids) {
    rec.streams[pid] = [];
    if (rec.end) rec.end.truncated = true;
    data = encodeLog(rec);
    if (data.length <= CAPS.stored) return { data, truncated: true };
  }
  rec.events = rec.events.filter(e => e.e !== 'live');
  data = encodeLog(rec);
  if (data.length <= CAPS.stored) return { data, truncated: true };
  rec.events = [];
  return { data: encodeLog(rec), truncated: true };
}

export interface LogStore {
  readonly kind: string;
  init(): Promise<void>;
  save(row: LogRow, players: LogPlayerRow[]): void;
  get(id: string): Promise<LogRow | null>;
  history(pkey: string, limit: number, before: number): Promise<HistoryItem[]>;
  setStatus(id: string, status: LogStatus): void;
  hide(id: string, pkey: string): void;
  decisions(limit: number): Promise<{ id: string; status: LogStatus }[]>;
  sweep(now: number): void;
}

export class MemoryLogStore implements LogStore {
  readonly kind = 'memory';
  rows = new Map<string, LogRow>();
  players = new Map<string, LogPlayerRow[]>();

  async init(): Promise<void> { return; }
  save(row: LogRow, players: LogPlayerRow[]): void {
    this.rows.set(row.id, { ...row });
    this.players.set(row.id, players.map(p => ({ ...p, item: { ...p.item } })));
  }
  async get(id: string): Promise<LogRow | null> { const r = this.rows.get(id); return r ? { ...r } : null; }
  async history(pkey: string, limit: number, before: number): Promise<HistoryItem[]> {
    const out: HistoryItem[] = [];
    for (const [id, list] of this.players) {
      const row = this.rows.get(id);
      for (const p of list) if (p.pkey === pkey && p.at < before) out.push({ ...p.item, status: row?.status ?? '' });
    }
    return out.sort((a, b) => b.at - a.at).slice(0, limit);
  }
  setStatus(id: string, status: LogStatus): void { const r = this.rows.get(id); if (r) r.status = status; }
  hide(id: string, pkey: string): void {
    const list = this.players.get(id);
    if (list) this.players.set(id, list.filter(p => p.pkey !== pkey));
  }
  async decisions(limit: number): Promise<{ id: string; status: LogStatus }[]> {
    return [...this.rows.values()].filter(r => r.status === 'apply' || r.status === 'void').slice(0, limit).map(r => ({ id: r.id, status: r.status }));
  }
  sweep(now: number): void {
    for (const [id, r] of this.rows) if (r.keep_until !== null && r.keep_until < now) { this.rows.delete(id); this.players.delete(id); }
  }
}

export const LOG_SCHEMA = [
  `CREATE TABLE IF NOT EXISTS match_logs (
  id TEXT PRIMARY KEY,
  at INTEGER NOT NULL,
  ended INTEGER NOT NULL,
  mode TEXT NOT NULL,
  kind TEXT NOT NULL,
  ranked INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT '',
  keep_until INTEGER,
  has_replay INTEGER NOT NULL DEFAULT 0,
  bytes INTEGER NOT NULL,
  data TEXT NOT NULL
)`,
  'CREATE INDEX IF NOT EXISTS match_logs_keep ON match_logs (keep_until)',
  'CREATE INDEX IF NOT EXISTS match_logs_status ON match_logs (status)',
  `CREATE TABLE IF NOT EXISTS match_log_players (
  id TEXT NOT NULL,
  pkey TEXT NOT NULL,
  pid INTEGER NOT NULL,
  at INTEGER NOT NULL,
  keep_until INTEGER,
  item TEXT NOT NULL,
  PRIMARY KEY (id, pkey)
)`,
  'CREATE INDEX IF NOT EXISTS match_log_players_pkey ON match_log_players (pkey, at)',
  'CREATE INDEX IF NOT EXISTS match_log_players_keep ON match_log_players (keep_until)',
];

export interface D1Like {
  query(sql: string, params?: unknown[]): Promise<Record<string, unknown>[]>;
  write(sql: string, params: unknown[]): void;
}

export class D1LogStore implements LogStore {
  readonly kind = 'd1';
  constructor(private d1: D1Like) {}

  async init(): Promise<void> { for (const sql of LOG_SCHEMA) await this.d1.query(sql); }

  save(row: LogRow, players: LogPlayerRow[]): void {
    this.d1.write(`INSERT INTO match_logs (id, at, ended, mode, kind, ranked, status, keep_until, has_replay, bytes, data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT (id) DO UPDATE SET ended = excluded.ended, status = excluded.status, keep_until = excluded.keep_until, has_replay = excluded.has_replay, bytes = excluded.bytes, data = excluded.data`,
    [row.id, row.at, row.ended, row.mode, row.kind, row.ranked ? 1 : 0, row.status, row.keep_until, row.has_replay ? 1 : 0, row.bytes, row.data]);
    for (const p of players) {
      this.d1.write(`INSERT INTO match_log_players (id, pkey, pid, at, keep_until, item) VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT (id, pkey) DO UPDATE SET keep_until = excluded.keep_until, item = excluded.item`,
      [p.id, p.pkey, p.pid, p.at, p.keep_until, JSON.stringify(p.item)]);
    }
  }

  async get(id: string): Promise<LogRow | null> {
    const rows = await this.d1.query('SELECT * FROM match_logs WHERE id = ?', [id]);
    const r = rows[0];
    if (!r) return null;
    return {
      id: String(r.id), at: Number(r.at), ended: Number(r.ended), mode: String(r.mode), kind: String(r.kind), ranked: Number(r.ranked) === 1,
      status: String(r.status ?? '') as LogStatus, keep_until: r.keep_until === null || r.keep_until === undefined ? null : Number(r.keep_until),
      has_replay: Number(r.has_replay) === 1, bytes: Number(r.bytes), data: String(r.data),
    };
  }

  async history(pkey: string, limit: number, before: number): Promise<HistoryItem[]> {
    const rows = await this.d1.query(`SELECT p.item AS item, l.status AS status FROM match_log_players p JOIN match_logs l ON l.id = p.id
      WHERE p.pkey = ? AND p.at < ? ORDER BY p.at DESC LIMIT ?`, [pkey, before, limit]);
    const out: HistoryItem[] = [];
    for (const r of rows) {
      try { out.push({ ...(JSON.parse(String(r.item)) as HistoryItem), status: String(r.status ?? '') as LogStatus }); } catch { continue; }
    }
    return out;
  }

  setStatus(id: string, status: LogStatus): void { this.d1.write('UPDATE match_logs SET status = ? WHERE id = ?', [status, id]); }
  hide(id: string, pkey: string): void { this.d1.write('DELETE FROM match_log_players WHERE id = ? AND pkey = ?', [id, pkey]); }

  async decisions(limit: number): Promise<{ id: string; status: LogStatus }[]> {
    const rows = await this.d1.query("SELECT id, status FROM match_logs WHERE status IN ('apply', 'void') LIMIT ?", [limit]);
    return rows.map(r => ({ id: String(r.id), status: String(r.status) as LogStatus }));
  }

  sweep(now: number): void {
    this.d1.write('DELETE FROM match_logs WHERE keep_until IS NOT NULL AND keep_until < ?', [now]);
    this.d1.write('DELETE FROM match_log_players WHERE keep_until IS NOT NULL AND keep_until < ?', [now]);
  }
}

export function logStoreFor(store: unknown): LogStore {
  const s = store as Partial<D1Like> & { kind?: string } | null;
  if (s && s.kind === 'd1' && typeof s.query === 'function' && typeof s.write === 'function') return new D1LogStore(s as D1Like);
  return new MemoryLogStore();
}

type RecordFn = (m: MatchIn) => Promise<Map<string, Record<string, unknown>>>;

export interface LogDeps {
  now?: () => number;
  log?: (level: string, msg: string) => void;
  record?: RecordFn;
  adjust?: (pkey: string, delta: number) => Promise<void>;
  onAct?: (id: string, pid: number, seq: number, entries: unknown[]) => void;
  onDecision?: (id: string, status: LogStatus, pkeys: string[]) => void;
  nameOf?: (pkey: string) => Promise<string | null>;
}

export interface FinishIn { reason: string; results: LogResult[]; rate: MatchIn | null }

const LIFE_CAUSE: Record<string, string> = { pvp_resolved: 'pvp', ante_timer: 'timer', life_lost: 'boss', round_lost: 'boss' };

export class MatchLogService {
  live = new Map<object, MatchLog>();
  liveById = new Map<string, MatchLog>();
  recent = new Map<string, MatchLog>();
  hidden = new Map<string, Set<string>>();
  private now: () => number;
  private say: (level: string, msg: string) => void;

  constructor(public store: LogStore = new MemoryLogStore(), public deps: LogDeps = {}) {
    this.now = deps.now ?? Date.now;
    this.say = deps.log ?? (() => undefined);
  }

  ensure(): Promise<void> { return this.store.init(); }

  start(host: object, header: Omit<LogHeader, 'v' | 'started_at'> & { started_at?: number }, keys: Record<string, string> = {}): MatchLog {
    const old = this.live.get(host);
    if (old) void this.finish(host, { reason: 'restarted', results: [], rate: null });
    const log = new MatchLog({ ...header, v: 1, started_at: header.started_at ?? this.now() }, this.now);
    log.keys = { ...keys };
    this.live.set(host, log);
    this.liveById.set(log.id, log);
    return log;
  }

  of(host: object | null | undefined): MatchLog | null { return host ? this.live.get(host) ?? null : null; }

  observe(host: object, pid: number, msg: Record<string, unknown>, isPvp?: (ante: number, blind: string) => boolean): boolean {
    const log = this.live.get(host);
    if (!log || pid < 0) return false;
    const track = log.tracks.get(pid) ?? newTrack();
    log.tracks.set(pid, track);
    const v = checkMessage(track, msg);
    if (!log.isBot(pid)) {
      for (const f of v.flags) log.flag(pid, f);
      if (v.reject && log.header.ranked) return true;
    }
    const cur = log.at.get(pid) ?? { ante: null, blind: null };
    switch (msg.type) {
      case 'ready_blind': log.add(pid, 'ready'); break;
      case 'unready_blind': log.add(pid, 'unready'); break;
      case 'blind_entered': {
        const ante = typeof msg.ante === 'number' ? msg.ante : cur.ante;
        const blind = blindLetter(msg.blind) ?? cur.blind;
        const pvp = !!(isPvp && ante !== null && blind && isPvp(ante, blind));
        log.at.set(pid, { ante, blind });
        log.pvp.set(pid, pvp);
        log.add(pid, 'blind_in', { ante, blind, key: short(msg.key ?? msg.blind_key), pvp });
        break;
      }
      case 'blind_finished':
        log.add(pid, 'blind_out', {
          ante: typeof msg.ante === 'number' ? msg.ante : cur.ante, blind: blindLetter(msg.blind) ?? cur.blind,
          score: scoreText(msg.score), hands: count(msg.hands ?? msg.hands_left) ?? track.hands, discards: count(msg.discards ?? msg.discards_left) ?? track.discards,
        });
        break;
      case 'play_hand':
      case 'live_stat':
        log.add(pid, 'live', {
          ante: typeof msg.ante === 'number' ? msg.ante : cur.ante, blind: blindLetter(msg.blind) ?? cur.blind,
          hands: track.hands, discards: track.discards, score: scoreText(msg.score),
        });
        break;
      case 'sabotage': {
        const to = typeof msg.to === 'number' ? msg.to : typeof msg.target === 'number' ? msg.target : log.header.kind === '1v1' ? 1 - pid : null;
        log.add(pid, 'trap', { to, key: short(msg.key ?? msg.sabotage ?? msg.kind ?? msg.id) });
        break;
      }
      case 'leave_match': log.add(pid, 'forfeit', { reason: 'leave_match' }); break;
      case 'leave_lobby':
      case 'party_leave':
      case 'return_to_menu': log.add(pid, 'leave', { reason: msg.type }); break;
      default: break;
    }
    return false;
  }

  sync(host: object, lives: (number | null | undefined)[], hint?: string): void {
    const log = this.live.get(host);
    if (!log) return;
    lives.forEach((now, pid) => {
      if (typeof now !== 'number' || !Number.isFinite(now)) return;
      const before = log.lives.get(pid);
      log.lives.set(pid, now);
      if (before === undefined || before === now) return;
      const delta = now - before;
      const cause = delta > 0 ? 'rule' : LIFE_CAUSE[hint ?? ''] ?? (log.pvp.get(pid) ? 'pvp' : hint === 'game_over' ? 'boss' : 'rule');
      log.add(pid, 'life', { lives: now, delta, cause });
      if (delta > 0 && !log.isBot(pid) && !lifeGainAllowed(log.header.settings, log.header.kind)) log.flag(pid, { code: 'lives_up', detail: `${before} to ${now}` });
    });
  }

  note(host: object, pid: number, e: 'rejoin' | 'disconnect' | 'leave' | 'forfeit', reason?: string): void {
    const log = this.live.get(host);
    if (log && pid >= 0) log.add(pid, e, reason ? { reason } : {});
  }

  actSeq(host: object, pid: number): number {
    const s = this.live.get(host)?.streams.get(pid);
    if (!s) return 0;
    return Math.max(s.seq, ...s.pending.keys());
  }

  private late = new Map<string, { log: MatchLog; until: number; host: object }>();

  private sweepLate(): void {
    const now = this.now();
    for (const [id, l] of this.late) {
      if (l.until > now) continue;
      this.late.delete(id);
      l.log.slim();
    }
  }

  private lateAct(id: string, pid: number | null, seq: unknown, a: unknown, host?: object, pkey?: string): string {
    const l = this.late.get(id);
    if (!l) return 'no_match';
    if (l.log.slimmed) { this.late.delete(id); return 'no_match'; }
    const who = host !== undefined && host === l.host ? pid : (pkey ? l.log.pidOf(pkey) : null);
    if (who === null || who === undefined || who < 0) return 'no_match';
    const res = l.log.act(who, seq, a);
    if (res === 'ok') this.save(l.log);
    return res;
  }

  actByKey(id: unknown, pkey: string | undefined, seq: unknown, a: unknown): string {
    this.sweepLate();
    if (typeof id !== 'string' || !pkey) return 'no_match';
    return this.lateAct(id, null, seq, a, undefined, pkey);
  }

  act(host: object, pid: number, seq: unknown, a: unknown, id?: unknown): string {
    this.sweepLate();
    const live = this.live.get(host);
    const log = live && (typeof id !== 'string' || id === live.id) ? live : null;
    if (!log && typeof id === 'string') return this.lateAct(id, pid, seq, a, host);
    if (!log || pid < 0) return 'no_match';
    const res = log.act(pid, seq, a);
    if (res === 'ok') {
      try { this.deps.onAct?.(log.id, pid, seq as number, a as unknown[]); } catch (e) { this.say('WARN', `act forward failed: ${String(e).slice(0, 120)}`); }
    }
    return res;
  }

  async finish(host: object, o: FinishIn): Promise<Map<string, Record<string, unknown>>> {
    const log = this.live.get(host);
    const record = this.deps.record;
    if (!log) return o.rate && record ? record(o.rate) : new Map();
    this.live.delete(host);
    this.liveById.delete(log.id);
    const held = log.header.ranked && (log.flags.length > 0 || log.contested);
    let out = new Map<string, Record<string, unknown>>();
    if (o.rate && record) {
      log.rate = { ...o.rate, seats: o.rate.seats.map(s => ({ ...s })) };
      try { out = await record(held ? { ...o.rate, held: true } : o.rate); } catch (e) { this.say('WARN', `rating failed for ${log.id}: ${String(e).slice(0, 120)}`); }
    }
    const rating: LogRating[] = [];
    if (!held) {
      for (const s of o.rate?.seats ?? []) {
        const res = s.pkey ? out.get(s.pkey) as { counted?: boolean; delta?: number; before?: { rp?: number }; after?: { rp?: number } } | undefined : undefined;
        if (!res || !res.counted || s.pid === undefined) continue;
        rating.push({ pid: s.pid, before: Number(res.before?.rp) || 0, after: Number(res.after?.rp) || 0, delta: Number(res.delta) || 0 });
        log.applied[s.pkey as string] = Number(res.delta) || 0;
      }
    }
    log.end = { reason: o.reason, ended_at: this.now(), results: o.results, rating, flags: log.flags, held };
    log.status = held ? 'held' : '';
    this.remember(log);
    this.save(log);
    this.sweepLate();
    this.late.set(log.id, { log, until: this.now() + CAPS.lateMs, host });
    return out;
  }

  private remember(log: MatchLog): void {
    this.recent.delete(log.id);
    this.recent.set(log.id, log);
    const cut = this.now() - CAPS.recentMs;
    for (const [id, l] of this.recent) {
      if (this.recent.size <= CAPS.recent && (l.end?.ended_at ?? 0) >= cut) break;
      this.recent.delete(id);
      this.hidden.delete(id);
    }
  }

  save(log: MatchLog): void {
    if (!log.end) return;
    const { data, truncated } = packLog(log);
    if (truncated) log.truncated = true;
    log.packed = data;
    const keep = log.header.ranked ? null : log.end.ended_at + CASUAL_KEEP_MS;
    const row: LogRow = {
      id: log.id, at: log.header.started_at, ended: log.end.ended_at, mode: log.header.mode, kind: log.header.kind, ranked: log.header.ranked,
      status: log.status, keep_until: keep, has_replay: log.hasReplay(), bytes: data.length, data,
    };
    const players = Object.entries(log.keys).filter(([, pkey]) => !this.hidden.get(log.id)?.has(pkey)).map(([pid, pkey]) => ({ id: log.id, pkey, pid: Number(pid), at: log.header.started_at, keep_until: keep, item: log.historyItem(Number(pid)) }));
    try { this.store.save(row, players); } catch (e) { this.say('WARN', `log save failed for ${log.id}: ${String(e).slice(0, 120)}`); }
  }

  async load(id: string): Promise<MatchLog | null> {
    const hit = this.liveById.get(id) ?? this.recent.get(id);
    if (hit) return hit;
    const row = await this.store.get(id);
    if (!row) return null;
    const log = MatchLog.fromStored(decodeLog(row.data), this.now);
    log.status = row.status;
    log.packed = row.data;
    log.slim();
    if (log.end) this.remember(log);
    return log;
  }

  async full(id: string): Promise<MatchLog | null> {
    const log = await this.load(id);
    if (!log || !log.slimmed || !log.packed) return log;
    const f = MatchLog.fromStored(decodeLog(log.packed), this.now);
    f.status = log.status;
    f.packed = log.packed;
    if (f.end) this.remember(f);
    return f;
  }

  async history(pkey: string, limit = 20, before?: number): Promise<HistoryItem[]> {
    const lim = Math.max(1, Math.min(50, Math.floor(Number(limit) || 20)));
    const cut = typeof before === 'number' && Number.isFinite(before) ? before : Infinity;
    const mine = [...this.recent.values()].filter(l => l.end && l.header.started_at < cut && l.pidOf(pkey) !== null && !this.hidden.get(l.id)?.has(pkey)).map(l => l.historyItem(l.pidOf(pkey) as number));
    let stored: HistoryItem[] = [];
    try { stored = await this.store.history(pkey, lim, cut === Infinity ? Number.MAX_SAFE_INTEGER : cut); } catch (e) { this.say('WARN', `history read failed: ${String(e).slice(0, 120)}`); }
    const byId = new Map<string, HistoryItem>();
    for (const it of stored) byId.set(it.id, it);
    for (const it of mine) byId.set(it.id, it);
    return [...byId.values()].filter(finishedItem).sort((a, b) => b.at - a.at).slice(0, lim);
  }

  async hide(id: string, pkey: string | undefined): Promise<{ ok: boolean; reason?: string }> {
    if (!pkey) return { ok: false, reason: 'not_in_match' };
    if (this.liveById.has(id)) return { ok: false, reason: 'live' };
    const log = this.recent.get(id);
    if (log && log.pidOf(pkey) === null) return { ok: false, reason: 'not_in_match' };
    if (log) {
      const set = this.hidden.get(id) ?? new Set<string>();
      set.add(pkey);
      this.hidden.set(id, set);
    }
    try { this.store.hide(id, pkey); } catch (e) { this.say('WARN', `hide failed for ${id}: ${String(e).slice(0, 120)}`); return { ok: false, reason: 'unavailable' }; }
    return { ok: true };
  }

  async replay(id: string, pkey?: string): Promise<{ id: string; header: LogHeader; streams: Record<string, unknown[]>; you?: number } | { reason: string }> {
    if (this.liveById.has(id)) return { reason: 'live' };
    let log: MatchLog | null = null;
    try { log = await this.full(id); } catch { return { reason: 'unavailable' }; }
    if (!log || !log.end) return { reason: 'not_found' };
    const you = pkey ? log.pidOf(pkey) : null;
    if (log.header.settings.spectate === false && you === null) return { reason: 'private' };
    const header = { ...log.header, players: await this.currentNames(log) };
    return { id: log.id, header, streams: log.streamsRecord(), ...(you !== null ? { you } : {}) };
  }

  private async currentNames(log: MatchLog): Promise<LogHeader['players']> {
    const players = log.header.players.map(p => ({ ...p }));
    const nameOf = this.deps.nameOf;
    if (!nameOf) return players;
    for (const p of players) {
      const k = log.keys[String(p.pid)];
      if (!k || p.is_bot) continue;
      try {
        const n = await nameOf(k);
        if (typeof n === 'string' && n.trim() !== '' && n !== p.name) { p.rec = p.name; p.name = n; }
      } catch { continue; }
    }
    return players;
  }

  async contest(id: string, pkey: string | undefined, reason: unknown): Promise<{ ok: boolean; reason?: string }> {
    let log: MatchLog | null = null;
    try { log = await this.full(id); } catch { return { ok: false, reason: 'unavailable' }; }
    if (!log) return { ok: false, reason: 'not_found' };
    const pid = pkey ? log.pidOf(pkey) : null;
    if (pid === null) return { ok: false, reason: 'not_in_match' };
    if (!log.header.ranked) return { ok: false, reason: 'not_ranked' };
    if (log.status === 'apply' || log.status === 'void' || log.status === 'applied' || log.status === 'voided') return { ok: false, reason: 'already_reviewed' };
    if (log.end && this.now() - log.end.ended_at > CONTEST_WINDOW_MS) return { ok: false, reason: 'too_late' };
    if (log.contested) return { ok: true };
    log.contested = true;
    log.add(pid, 'contest', { reason: typeof reason === 'string' ? reason.replace(/[\x00-\x1f]/g, ' ').slice(0, CONTEST_REASON_MAX) : '' });
    if (log.end) {
      if (!log.end.held) {
        for (const [k, delta] of Object.entries(log.applied)) {
          try { await this.deps.adjust?.(k, -delta); } catch (e) { this.say('WARN', `contest revert failed: ${String(e).slice(0, 120)}`); }
        }
        log.end.held = true;
      }
      log.status = 'held';
      this.save(log);
      log.slim();
    }
    this.notify(log, 'held');
    return { ok: true };
  }

  async decide(id: string, decision: 'apply' | 'void'): Promise<{ ok: boolean; reason?: string }> {
    let log: MatchLog | null = null;
    try { log = await this.full(id); } catch { return { ok: false, reason: 'unavailable' }; }
    if (!log || !log.end) return { ok: false, reason: 'not_found' };
    if (log.status === 'applied' || log.status === 'voided') return { ok: false, reason: 'already_reviewed' };
    if (decision === 'apply' && log.end.held) {
      const applied = Object.entries(log.applied);
      if (applied.length > 0) {
        for (const [k, delta] of applied) await this.deps.adjust?.(k, delta);
      } else if (log.rate && this.deps.record) {
        const out = await this.deps.record({ ...log.rate, held: false });
        const rating: LogRating[] = [];
        for (const s of log.rate.seats) {
          const res = s.pkey ? out.get(s.pkey) as { counted?: boolean; delta?: number; before?: { rp?: number }; after?: { rp?: number } } | undefined : undefined;
          if (!res || !res.counted || s.pid === undefined) continue;
          rating.push({ pid: s.pid, before: Number(res.before?.rp) || 0, after: Number(res.after?.rp) || 0, delta: Number(res.delta) || 0 });
          log.applied[s.pkey as string] = Number(res.delta) || 0;
        }
        log.end.rating = rating;
      }
      log.end.held = false;
    }
    log.status = decision === 'apply' ? 'applied' : 'voided';
    this.save(log);
    log.slim();
    this.notify(log, log.status);
    return { ok: true };
  }

  private notify(log: MatchLog, status: LogStatus): void {
    try { this.deps.onDecision?.(log.id, status, Object.values(log.keys)); } catch (e) { this.say('WARN', `decision hook failed: ${String(e).slice(0, 120)}`); }
  }

  async pollDecisions(): Promise<number> {
    let list: { id: string; status: LogStatus }[] = [];
    try { list = await this.store.decisions(20); } catch (e) { this.say('WARN', `decision read failed: ${String(e).slice(0, 120)}`); return 0; }
    let n = 0;
    for (const d of list) {
      const res: { ok: boolean; reason?: string } = await this.decide(d.id, d.status === 'apply' ? 'apply' : 'void')
        .catch(e => { this.say('WARN', `decision ${d.id} failed: ${String(e).slice(0, 120)}`); return { ok: false, reason: 'unavailable' }; });
      if (res.ok) n++;
      else if (res.reason !== 'unavailable') this.store.setStatus(d.id, d.status === 'apply' ? 'applied' : 'voided');
    }
    return n;
  }

  sweep(): void {
    const now = this.now();
    for (const [host, log] of this.live) {
      if (now - log.header.started_at > CAPS.liveMaxMs) void this.finish(host, { reason: 'abandoned', results: [], rate: null });
    }
    try { this.store.sweep(now); } catch (e) { this.say('WARN', `log sweep failed: ${String(e).slice(0, 120)}`); }
  }
}

export let matchlogs = new MatchLogService();

export function setMatchlogs(s: MatchLogService): void { matchlogs = s; }
