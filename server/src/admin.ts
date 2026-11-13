import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { rankOf } from './ranked';

type Row = Record<string, unknown>;
export type AdminQuery = (sql: string, params?: unknown[]) => Promise<Row[]>;

export interface LiveSocket {
  name: string;
  pkey: string;
  version: string;
  mods: string[];
  room: string | null;
  party: string | null;
  where: string;
  queue: boolean;
  rtt: number | null;
  since: number;
}

export interface LiveRoom {
  code: string;
  visibility: string;
  ranked: boolean;
  quick: boolean;
  mode: string;
  phase: string;
  ante: number;
  blind: string;
  players: { name: string; lives: number; score: number | null; status: string; here: boolean }[];
  mods: number;
  version: string;
  created: number;
  activity: number;
}

export interface LiveState {
  sockets: LiveSocket[];
  rooms: LiveRoom[];
  bots: number;
  conns: number;
  peakConns: number;
  totalConns: number;
  matchesStarted: number;
  roomsMade: number;
}

export interface AdminDeps {
  query: () => AdminQuery | null;
  live: () => LiveState;
  build: string;
  started: number;
  memory: () => Record<string, number>;
  d1: () => Record<string, number>;
  env?: () => string | undefined;
  now?: () => number;
  log?: (level: string, msg: string) => void;
  assets?: string;
}

const HOUR = 3_600_000;
const DAY = 86_400_000;
const MAX_LABELS = 30;
const MAX_DEVICES = 200_000;
const FAIL_WINDOW = 10 * 60_000;
const FAIL_MAX = 10;
const ID_CAP = 20_000;

const SCHEMA = [
  `CREATE TABLE IF NOT EXISTS admin_hours (
    h INTEGER PRIMARY KEY, online_peak INTEGER NOT NULL DEFAULT 0, online_sum INTEGER NOT NULL DEFAULT 0, samples INTEGER NOT NULL DEFAULT 0,
    named_peak INTEGER NOT NULL DEFAULT 0, rooms_peak INTEGER NOT NULL DEFAULT 0, playing_peak INTEGER NOT NULL DEFAULT 0,
    conns INTEGER NOT NULL DEFAULT 0, checks INTEGER NOT NULL DEFAULT 0, patch_dl INTEGER NOT NULL DEFAULT 0,
    matches INTEGER NOT NULL DEFAULT 0, rooms_made INTEGER NOT NULL DEFAULT 0, mem_mb INTEGER NOT NULL DEFAULT 0)`,
  `CREATE TABLE IF NOT EXISTS admin_days (
    day TEXT PRIMARY KEY, devices INTEGER NOT NULL DEFAULT 0, players INTEGER NOT NULL DEFAULT 0, checks INTEGER NOT NULL DEFAULT 0,
    patch_dl INTEGER NOT NULL DEFAULT 0, online_peak INTEGER NOT NULL DEFAULT 0, detail TEXT NOT NULL DEFAULT '{}',
    salt TEXT NOT NULL DEFAULT '', seen TEXT NOT NULL DEFAULT '', seen_players TEXT NOT NULL DEFAULT '')`,
];

const NAME = `COALESCE(NULLIF(p.name, ''), s.name, '')`;
const SEEN = `MAX(COALESCE(p.last_seen, 0), COALESCE(s.last_seen, 0))`;
const KEYS = `(SELECT pkey FROM players UNION SELECT pkey FROM social_players)`;
const PLAYER_COLS = `k.pkey AS pkey, ${NAME} AS name, s.code AS code, p.rp AS rp, p.peak_rp AS peak_rp, p.level AS level, p.xp AS xp,
  p.matches AS matches, p.wins AS wins, p.streak AS streak, p.packs AS packs, p.season AS season, p.created AS created, ${SEEN} AS last_seen`;
const PLAYER_FROM = `${KEYS} k LEFT JOIN players p ON p.pkey = k.pkey LEFT JOIN social_players s ON s.pkey = k.pkey`;
const SORTS: Record<string, string> = {
  last_seen: 'last_seen', created: 'created', rp: 'rp', level: 'xp', matches: 'matches', wins: 'wins', name: 'name COLLATE NOCASE', streak: 'streak',
};

function sha(text: string): string {
  return createHash('sha256').update(text).digest('hex');
}

function num(v: unknown): number {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

function dayOf(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

function packSet(values: Iterable<number>, count: number): string {
  const a = new Uint32Array(count);
  let i = 0;
  for (const v of values) a[i++] = v;
  return Buffer.from(a.buffer, 0, i * 4).toString('base64');
}

function unpack(text: string): Uint32Array {
  const b = Buffer.from(text || '', 'base64');
  const n = Math.floor(b.length / 4);
  const out = new Uint32Array(n);
  for (let i = 0; i < n; i++) out[i] = b.readUInt32LE(i * 4);
  return out;
}

export function uaFamily(ua: string): string {
  const u = ua.toLowerCase();
  if (u === '') return 'none';
  if (u.includes('launcher')) return 'launcher';
  if (u.includes('overhaul') || u.includes('balatro')) return 'game';
  if (u.includes('love')) return 'love';
  if (u.includes('luasocket') || u.includes('lua')) return 'lua';
  if (u.includes('curl')) return 'curl';
  if (u.includes('winhttp')) return 'winhttp';
  if (u.includes('okhttp') || u.includes('dalvik') || u.includes('android')) return 'android';
  if (u.includes('mozilla')) return 'browser';
  return 'other';
}

class DayState {
  day = '';
  salt = '';
  labels: string[] = [];
  counts = new Map<string, number>();
  devices = new Map<number, number>();
  players = new Set<number>();
  checks = 0;
  patch = 0;
  onlinePeak = 0;
  dirty = false;

  reset(day: string): void {
    this.day = day;
    this.salt = randomBytes(12).toString('hex');
    this.labels = [];
    this.counts.clear();
    this.devices.clear();
    this.players.clear();
    this.checks = 0;
    this.patch = 0;
    this.onlinePeak = 0;
    this.dirty = true;
  }

  hash(text: string): number {
    return createHash('sha256').update(this.salt).update(text).digest().readUInt32LE(0);
  }

  bit(label: string): number {
    let i = this.labels.indexOf(label);
    if (i < 0) {
      if (this.labels.length >= MAX_LABELS) return this.bit('other');
      this.labels.push(label);
      i = this.labels.length - 1;
    }
    return i;
  }

  note(ip: string, label: string): void {
    const i = this.bit(label);
    const name = this.labels[i];
    this.counts.set(name, (this.counts.get(name) ?? 0) + 1);
    const h = this.hash(ip);
    const had = this.devices.get(h);
    if (had === undefined && this.devices.size >= MAX_DEVICES) return;
    this.devices.set(h, ((had ?? 0) | (1 << i)) >>> 0);
    this.dirty = true;
  }

  detail(): Record<string, { requests: number; devices: number }> {
    const per = this.labels.map(() => 0);
    for (const mask of this.devices.values()) {
      for (let i = 0; i < per.length; i++) if (mask & (1 << i)) per[i]++;
    }
    const out: Record<string, { requests: number; devices: number }> = {};
    this.labels.forEach((l, i) => { out[l] = { requests: this.counts.get(l) ?? 0, devices: per[i] }; });
    return out;
  }

  save(): { seen: string; seenPlayers: string; detail: string } {
    const flat: number[] = [];
    for (const [h, m] of this.devices) flat.push(h, m);
    return {
      seen: packSet(flat, flat.length),
      seenPlayers: packSet(this.players, this.players.size),
      detail: JSON.stringify({ labels: this.labels, rows: this.detail() }),
    };
  }

  load(row: Row): void {
    this.day = String(row.day);
    this.salt = String(row.salt || '') || randomBytes(12).toString('hex');
    this.checks = num(row.checks);
    this.patch = num(row.patch_dl);
    this.onlinePeak = num(row.online_peak);
    this.devices.clear();
    this.players.clear();
    this.counts.clear();
    this.labels = [];
    try {
      const d = JSON.parse(String(row.detail || '{}')) as { labels?: string[]; rows?: Record<string, { requests?: number }> };
      this.labels = Array.isArray(d.labels) ? d.labels.slice(0, MAX_LABELS + 1).map(String) : [];
      for (const l of this.labels) this.counts.set(l, num(d.rows?.[l]?.requests));
    } catch {
      this.labels = [];
    }
    const pairs = unpack(String(row.seen || ''));
    for (let i = 0; i + 1 < pairs.length; i += 2) this.devices.set(pairs[i], pairs[i + 1]);
    for (const h of unpack(String(row.seen_players || ''))) this.players.add(h);
  }
}

interface HourState {
  h: number;
  onlinePeak: number;
  onlineSum: number;
  samples: number;
  namedPeak: number;
  roomsPeak: number;
  playingPeak: number;
  checks: number;
  patch: number;
  conns0: number;
  matches0: number;
  rooms0: number;
}

export class AdminService {
  private readonly deps: AdminDeps;
  private readonly now: () => number;
  private readonly today = new DayState();
  private hour: HourState | null = null;
  private ready: Promise<void> | null = null;
  private timer: ReturnType<typeof setInterval> | null = null;
  private lastFlush = 0;
  private tokenHash: string | null = null;
  private tokenAt = 0;
  private readonly fails = new Map<string, number[]>();
  private readonly cache = new Map<string, { at: number; value: unknown }>();
  private readonly ids = new Map<string, string>();
  private readonly idSalt = randomBytes(16).toString('hex');
  private page: string | null = null;
  private readonly files = new Map<string, Uint8Array>();

  constructor(deps: AdminDeps) {
    this.deps = deps;
    this.now = deps.now ?? (() => Date.now());
  }

  private q(): AdminQuery | null {
    return this.deps.query();
  }

  private async rows(sql: string, params: unknown[] = []): Promise<Row[]> {
    const q = this.q();
    if (!q) return [];
    return q(sql, params);
  }

  private async one(sql: string, params: unknown[] = []): Promise<Row> {
    return (await this.rows(sql, params))[0] ?? {};
  }

  private async cached<T>(key: string, ttl: number, make: () => Promise<T>): Promise<T> {
    const hit = this.cache.get(key);
    const t = this.now();
    if (hit && t - hit.at < ttl) return hit.value as T;
    const value = await make();
    if (this.cache.size > 200) this.cache.clear();
    this.cache.set(key, { at: t, value });
    return value;
  }

  idOf(pkey: unknown): string | null {
    if (typeof pkey !== 'string' || pkey === '') return null;
    const id = sha(this.idSalt + pkey).slice(0, 20);
    if (!this.ids.has(id)) {
      if (this.ids.size >= ID_CAP) {
        const first = this.ids.keys().next().value;
        if (first !== undefined) this.ids.delete(first);
      }
      this.ids.set(id, pkey);
    }
    return id;
  }

  private shape(r: Row): Row {
    const { pkey, ...rest } = r;
    const out: Row = { id: this.idOf(pkey), ...rest };
    if (typeof r.rp === 'number' && num(r.matches) > 0) {
      const info = rankOf(r.rp);
      out.rank_name = info.name;
      out.rank_tier = info.tier;
    }
    return out;
  }

  async ensure(): Promise<void> {
    if (!this.q()) return;
    this.ready ??= (async () => {
      for (const sql of SCHEMA) await this.rows(sql);
      const day = dayOf(this.now());
      const row = (await this.rows('SELECT * FROM admin_days WHERE day = ?', [day]))[0];
      if (row && this.today.devices.size === 0 && this.today.players.size === 0) {
        const pending = this.today.day === day ? { counts: new Map(this.today.counts), checks: this.today.checks, patch: this.today.patch } : null;
        this.today.load(row);
        if (pending) {
          this.today.checks += pending.checks;
          this.today.patch += pending.patch;
        }
      }
      await this.rows("UPDATE admin_days SET seen = '', seen_players = '', salt = '' WHERE day < ? AND seen <> ''", [day]);
      await this.rows('DELETE FROM admin_hours WHERE h < ?', [Math.floor((this.now() - 90 * DAY) / HOUR)]);
      await this.rows('DELETE FROM admin_days WHERE day < ?', [dayOf(this.now() - 400 * DAY)]);
    })().catch(e => {
      this.ready = null;
      this.deps.log?.('WARN', `admin tables: ${String(e)}`);
    });
    await this.ready;
  }

  start(): void {
    if (this.timer) return;
    void this.ensure().then(() => this.sample());
    this.timer = setInterval(() => { void this.sample(); }, 60_000);
    (this.timer as unknown as { unref?: () => void }).unref?.();
  }

  async stop(): Promise<void> {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    await this.flush();
  }

  private roll(): void {
    const day = dayOf(this.now());
    if (this.today.day !== day) this.today.reset(day);
  }

  seen(ip: string, kind: 'check' | 'feed' | 'patch', label: string, ua = ''): void {
    try {
      this.note(ip, kind, label, ua);
    } catch (e) {
      this.deps.log?.('WARN', `admin seen: ${String(e)}`);
    }
  }

  private note(ip: string, kind: 'check' | 'feed' | 'patch', label: string, ua: string): void {
    this.roll();
    const clean = label.replace(/[^\w.\-+ ]/g, '').slice(0, 40) || 'any';
    this.today.note(ip, `${kind}:${clean}`);
    this.today.note(ip, `ua:${uaFamily(ua)}`);
    if (kind === 'patch') {
      this.today.patch++;
      if (this.hour) this.hour.patch++;
    } else {
      this.today.checks++;
      if (this.hour) this.hour.checks++;
    }
  }

  async sample(): Promise<void> {
    try {
      await this.tick();
    } catch (e) {
      this.deps.log?.('WARN', `admin sample: ${String(e)}`);
    }
  }

  private async tick(): Promise<void> {
    const t = this.now();
    this.roll();
    const live = this.deps.live();
    const h = Math.floor(t / HOUR);
    if (this.hour && this.hour.h !== h) {
      await this.flush();
      this.hour = null;
    }
    this.hour ??= { h, onlinePeak: 0, onlineSum: 0, samples: 0, namedPeak: 0, roomsPeak: 0, playingPeak: 0, checks: 0, patch: 0,
      conns0: live.totalConns, matches0: live.matchesStarted, rooms0: live.roomsMade };
    const named = live.sockets.filter(s => s.name !== '').length;
    const playing = live.rooms.filter(r => r.phase === 'playing' || r.phase === 'pvp_pending').reduce((n, r) => n + r.players.filter(p => p.here).length, 0);
    const hr = this.hour;
    hr.onlinePeak = Math.max(hr.onlinePeak, live.conns);
    hr.onlineSum += live.conns;
    hr.samples++;
    hr.namedPeak = Math.max(hr.namedPeak, named);
    hr.roomsPeak = Math.max(hr.roomsPeak, live.rooms.length);
    hr.playingPeak = Math.max(hr.playingPeak, playing);
    this.today.onlinePeak = Math.max(this.today.onlinePeak, live.conns);
    for (const s of live.sockets) {
      if (s.pkey && this.today.players.size < MAX_DEVICES) {
        const before = this.today.players.size;
        this.today.players.add(this.today.hash(s.pkey));
        if (this.today.players.size !== before) this.today.dirty = true;
      }
    }
    if (t - this.lastFlush >= 10 * 60_000) await this.flush();
  }

  async flush(): Promise<void> {
    if (!this.q()) return;
    await this.ensure();
    this.lastFlush = this.now();
    try {
      const hr = this.hour;
      if (hr && hr.samples > 0) {
        const live = this.deps.live();
        await this.rows(
          `INSERT INTO admin_hours (h, online_peak, online_sum, samples, named_peak, rooms_peak, playing_peak, conns, checks, patch_dl, matches, rooms_made, mem_mb)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(h) DO UPDATE SET online_peak = MAX(online_peak, excluded.online_peak), online_sum = online_sum + excluded.online_sum,
             samples = samples + excluded.samples, named_peak = MAX(named_peak, excluded.named_peak), rooms_peak = MAX(rooms_peak, excluded.rooms_peak),
             playing_peak = MAX(playing_peak, excluded.playing_peak), conns = conns + excluded.conns, checks = checks + excluded.checks,
             patch_dl = patch_dl + excluded.patch_dl, matches = matches + excluded.matches, rooms_made = rooms_made + excluded.rooms_made, mem_mb = excluded.mem_mb`,
          [hr.h, hr.onlinePeak, hr.onlineSum, hr.samples, hr.namedPeak, hr.roomsPeak, hr.playingPeak,
            Math.max(0, live.totalConns - hr.conns0), hr.checks, hr.patch, Math.max(0, live.matchesStarted - hr.matches0),
            Math.max(0, live.roomsMade - hr.rooms0), Math.round(this.deps.memory().totalMB ?? 0)],
        );
        hr.onlineSum = 0;
        hr.samples = 0;
        hr.checks = 0;
        hr.patch = 0;
        hr.conns0 = live.totalConns;
        hr.matches0 = live.matchesStarted;
        hr.rooms0 = live.roomsMade;
      }
      if (this.today.day && this.today.dirty) {
        const d = this.today;
        const s = d.save();
        await this.rows(
          `INSERT INTO admin_days (day, devices, players, checks, patch_dl, online_peak, detail, salt, seen, seen_players) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(day) DO UPDATE SET devices = excluded.devices, players = excluded.players, checks = excluded.checks, patch_dl = excluded.patch_dl,
             online_peak = MAX(online_peak, excluded.online_peak), detail = excluded.detail, salt = excluded.salt, seen = excluded.seen, seen_players = excluded.seen_players`,
          [d.day, d.devices.size, d.players.size, d.checks, d.patch, d.onlinePeak, s.detail, d.salt, s.seen, s.seenPlayers],
        );
        d.dirty = false;
      }
    } catch (e) {
      this.deps.log?.('WARN', `admin flush: ${String(e)}`);
    }
  }

  private async expected(): Promise<string | null> {
    const env = (this.deps.env ?? (() => process.env.ADMIN_TOKEN))();
    if (env) return sha(env);
    const t = this.now();
    if (t - this.tokenAt < 60_000) return this.tokenHash;
    this.tokenAt = t;
    try {
      const r = await this.rows("SELECT v FROM data_meta WHERE k = 'admin_token_sha256'");
      const v = typeof r[0]?.v === 'string' ? r[0].v.trim().toLowerCase() : '';
      this.tokenHash = /^[0-9a-f]{64}$/.test(v) ? v : null;
    } catch {
      this.tokenHash = null;
    }
    return this.tokenHash;
  }

  private blocked(ip: string): boolean {
    const t = this.now();
    const list = (this.fails.get(ip) ?? []).filter(x => t - x < FAIL_WINDOW);
    if (list.length) this.fails.set(ip, list);
    else this.fails.delete(ip);
    return list.length >= FAIL_MAX;
  }

  private failed(ip: string): void {
    if (this.fails.size > 5000) this.fails.clear();
    const list = this.fails.get(ip) ?? [];
    list.push(this.now());
    this.fails.set(ip, list);
  }

  private asset(name: string): Uint8Array | null {
    if (!this.files.has(name)) {
      try {
        this.files.set(name, new Uint8Array(readFileSync(join(this.deps.assets ?? join(import.meta.dir, 'admin'), name))));
      } catch {
        return null;
      }
    }
    return this.files.get(name) ?? null;
  }

  async handle(req: Request, url: URL, ip: string): Promise<Response> {
    const missing = () => new Response('Not Found', { status: 404 });
    const want = await this.expected();
    if (!want || req.method !== 'GET') return missing();
    const path = url.pathname.replace(/\/+$/, '') || '/admin';
    const common = { 'X-Robots-Tag': 'noindex, nofollow', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' };
    if (path === '/admin') {
      this.page ??= new TextDecoder().decode(this.asset('page.html') ?? new Uint8Array());
      if (!this.page) return missing();
      return new Response(this.page, { headers: { ...common, 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-cache',
        'Content-Security-Policy': "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src 'self' data:; frame-ancestors 'none'" } });
    }
    if (path === '/admin/manifest.webmanifest') {
      const body = this.asset('manifest.webmanifest');
      return body ? new Response(body, { headers: { ...common, 'Content-Type': 'application/manifest+json', 'Cache-Control': 'max-age=3600' } }) : missing();
    }
    const icon = /^\/admin\/(icon-(?:192|512)\.png)$/.exec(path);
    if (icon) {
      const body = this.asset(icon[1]);
      return body ? new Response(body, { headers: { ...common, 'Content-Type': 'image/png', 'Cache-Control': 'max-age=86400' } }) : missing();
    }
    if (!path.startsWith('/admin/api/')) return missing();
    const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...common, 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } });
    if (this.blocked(ip)) return json({ error: 'slow_down' }, 429);
    const given = (req.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
    const a = Buffer.from(sha(given), 'hex'), b = Buffer.from(want, 'hex');
    if (given === '' || a.length !== b.length || !timingSafeEqual(a, b)) {
      this.failed(ip);
      return json({ error: 'unauthorized' }, 401);
    }
    const p = url.searchParams;
    try {
      switch (path.slice('/admin/api/'.length)) {
        case 'overview': return json(await this.overview());
        case 'online': return json(await this.online());
        case 'players': return json(await this.players(p));
        case 'player': return json(await this.player(p.get('id') ?? ''));
        case 'stats': return json(await this.stats());
        case 'installs': return json(await this.installs());
        case 'matches': return json(await this.matches(p));
        case 'boards': return json(await this.boards());
        case 'forge': return json(await this.forge());
        case 'reports': return json(await this.reports());
        default: return json({ error: 'unknown' }, 404);
      }
    } catch (e) {
      this.deps.log?.('WARN', `admin ${path}: ${String(e)}`);
      return json({ error: 'failed', detail: String(e).slice(0, 200) }, 500);
    }
  }

  private liveCounts(live: LiveState): Row {
    const playing = live.rooms.filter(r => r.phase === 'playing' || r.phase === 'pvp_pending');
    const versions: Record<string, number> = {};
    for (const s of live.sockets) {
      const v = s.version || 'unknown';
      versions[v] = (versions[v] ?? 0) + 1;
    }
    return {
      connections: live.conns,
      named: live.sockets.filter(s => s.name !== '').length,
      rooms: live.rooms.length,
      matches_running: playing.length,
      in_match: playing.reduce((n, r) => n + r.players.filter(x => x.here).length, 0),
      in_queue: live.sockets.filter(s => s.queue).length,
      with_mods: live.sockets.filter(s => s.mods.length > 0).length,
      bots: live.bots,
      peak_since_start: live.peakConns,
      connections_since_start: live.totalConns,
      matches_since_start: live.matchesStarted,
      rooms_since_start: live.roomsMade,
      versions,
    };
  }

  async overview(): Promise<Row> {
    const t = this.now();
    const live = this.deps.live();
    this.roll();
    const db = await this.cached('overview', 600_000, async () => {
      if (!this.q()) return null;
      const totals = await this.one(
        `WITH seen AS (SELECT pkey, MAX(ls) ls FROM (SELECT pkey, last_seen ls FROM players UNION ALL SELECT pkey, last_seen ls FROM social_players) GROUP BY pkey)
         SELECT COUNT(*) total, COALESCE(SUM(ls >= ?), 0) active_1h, COALESCE(SUM(ls >= ?), 0) active_24h, COALESCE(SUM(ls >= ?), 0) active_7d, COALESCE(SUM(ls >= ?), 0) active_30d FROM seen`,
        [t - HOUR, t - DAY, t - 7 * DAY, t - 30 * DAY]);
      const profiles = await this.one(
        `SELECT COUNT(*) ranked_profiles, COALESCE(SUM(created >= ?), 0) new_24h, COALESCE(SUM(created >= ?), 0) new_7d, COALESCE(SUM(matches > 0), 0) played_ranked,
           COALESCE(SUM(matches), 0) ranked_seats, MIN(created) first_created FROM players`, [t - DAY, t - 7 * DAY]);
      const logs = await this.one(
        `SELECT COUNT(*) logged, COALESCE(SUM(at >= ?), 0) logged_24h, COALESCE(SUM(at >= ?), 0) logged_7d, MIN(at) oldest FROM match_logs`, [t - DAY, t - 7 * DAY]);
      const misc = await this.one(
        `SELECT (SELECT COUNT(*) FROM social_players) social_profiles, (SELECT COUNT(*) FROM matches) ranked_matches,
           (SELECT COUNT(*) FROM social_links WHERE status = 'accepted') / 2 friend_links, (SELECT COUNT(*) FROM speedruns) speedruns,
           (SELECT COUNT(*) FROM forge_mods) forge_mods, (SELECT COALESCE(SUM(downloads), 0) FROM forge_mods) forge_downloads,
           (SELECT COUNT(*) FROM chat_reports) reports, (SELECT COUNT(*) FROM chat_reports WHERE COALESCE(status, '') = '') reports_open,
           (SELECT COUNT(*) FROM daily_board WHERE day = ?) daily_today`, [dayOf(t)]);
      return { ...totals, ...profiles, ...logs, ...misc };
    });
    return {
      at: t,
      live: this.liveCounts(live),
      server: { build: this.deps.build, started: this.deps.started, memory: this.deps.memory(), d1: this.deps.d1(), database: this.q() ? 'd1' : 'none' },
      db,
      today: { day: this.today.day, devices: this.today.devices.size, players: this.today.players.size, checks: this.today.checks, patch_downloads: this.today.patch, online_peak: this.today.onlinePeak },
    };
  }

  async online(): Promise<Row> {
    const live = this.deps.live();
    const keys = [...new Set(live.sockets.map(s => s.pkey).filter(k => k !== ''))].slice(0, 400);
    const prof = new Map<string, Row>();
    if (keys.length && this.q()) {
      const rows = await this.cached(`online:${sha(keys.join(','))}`, 120_000, () => this.rows(
        `SELECT p.pkey, p.rp, p.level, p.matches, p.wins, p.created, s.code FROM players p LEFT JOIN social_players s ON s.pkey = p.pkey WHERE p.pkey IN (${keys.map(() => '?').join(',')})`, keys));
      for (const r of rows) prof.set(String(r.pkey), r);
    }
    const sockets = live.sockets.map(s => {
      const r = prof.get(s.pkey);
      const row: Row = { id: this.idOf(s.pkey), name: s.name, version: s.version, mods: s.mods, room: s.room, party: s.party, where: s.where, queue: s.queue, rtt: s.rtt, since: s.since };
      if (r) {
        Object.assign(row, { rp: r.rp, level: r.level, matches: r.matches, wins: r.wins, created: r.created, code: r.code });
        if (typeof r.rp === 'number' && num(r.matches) > 0) row.rank_name = rankOf(r.rp).name;
      }
      return row;
    });
    return { at: this.now(), counts: this.liveCounts(live), sockets, rooms: live.rooms };
  }

  async players(p: URLSearchParams): Promise<Row> {
    const size = Math.min(100, Math.max(10, Math.floor(num(p.get('size')) || 50)));
    const page = Math.max(0, Math.floor(num(p.get('page'))));
    const sort = SORTS[p.get('sort') ?? ''] ?? SORTS.last_seen;
    const dir = p.get('dir') === 'asc' ? 'ASC' : 'DESC';
    const term = (p.get('q') ?? '').trim().slice(0, 40);
    const like = `%${term.replace(/[\\%_]/g, m => `\\${m}`)}%`;
    const where = term === '' ? '' : `WHERE (${NAME} LIKE ? ESCAPE '\\' OR COALESCE(s.code, '') LIKE ? ESCAPE '\\')`;
    const args = term === '' ? [] : [like, like];
    const filter = p.get('filter') ?? '';
    const t = this.now();
    const extra: Record<string, string> = {
      ranked: 'COALESCE(p.matches, 0) > 0', new: `COALESCE(p.created, 0) >= ${t - 7 * DAY}`, active: `${SEEN} >= ${t - DAY}`,
      gone: `${SEEN} < ${t - 7 * DAY}`,
    };
    const cond = extra[filter] ? (where === '' ? `WHERE ${extra[filter]}` : `${where} AND ${extra[filter]}`) : where;
    const total = num((await this.one(`SELECT COUNT(*) n FROM ${PLAYER_FROM} ${cond}`, args)).n);
    const rows = await this.rows(
      `SELECT * FROM (SELECT ${PLAYER_COLS} FROM ${PLAYER_FROM} ${cond}) ORDER BY ${sort} IS NULL, ${sort} ${dir}, pkey LIMIT ? OFFSET ?`, [...args, size, page * size]);
    const online = new Set(this.deps.live().sockets.map(s => s.pkey).filter(k => k !== ''));
    return { at: t, total, page, size, rows: rows.map(r => ({ ...this.shape(r), online: online.has(String(r.pkey)) })) };
  }

  private async named(sql: string, params: unknown[], keyCols: string[]): Promise<Row[]> {
    const rows = await this.rows(sql, params);
    return rows.map(r => {
      const out: Row = { ...r };
      for (const c of keyCols) {
        out[`${c}_id`] = this.idOf(r[c]);
        delete out[c];
      }
      return out;
    });
  }

  async player(id: string): Promise<Row> {
    const pkey = this.ids.get(id);
    if (!pkey) return { error: 'expired' };
    const base = (await this.rows(`SELECT ${PLAYER_COLS}, p.best_rank AS best_rank FROM ${PLAYER_FROM} WHERE k.pkey = ?`, [pkey]))[0];
    if (!base) return { error: 'gone' };
    const live = this.deps.live().sockets.find(s => s.pkey === pkey);
    const on = `LEFT JOIN players p ON p.pkey = x.other LEFT JOIN social_players s ON s.pkey = x.other`;
    const [ranked, logs, h2h, links, recent, runs, mods, unlocks, equipped, daily, mini, reports] = await Promise.all([
      this.rows(`SELECT m.id, m.mode, m.at, m.season, mp.placement, mp.players, mp.result, mp.ante, mp.score, mp.rp_delta, mp.xp, mp.bot_factor
        FROM match_players mp JOIN matches m ON m.id = mp.match_id WHERE mp.pkey = ? ORDER BY m.at DESC LIMIT 50`, [pkey]),
      this.rows(`SELECT l.id, l.at, l.ended, l.mode, l.kind, l.ranked, l.status, l.has_replay, lp.pid, lp.item,
        (SELECT group_concat(COALESCE(NULLIF(p.name, ''), s.name, '?'), ', ') FROM match_log_players o LEFT JOIN players p ON p.pkey = o.pkey LEFT JOIN social_players s ON s.pkey = o.pkey
          WHERE o.id = l.id AND o.pkey <> lp.pkey) AS versus
        FROM match_log_players lp JOIN match_logs l ON l.id = lp.id WHERE lp.pkey = ? ORDER BY l.at DESC LIMIT 50`, [pkey]),
      this.named(`SELECT x.other AS other, ${NAME} AS name, x.wins, x.losses, x.draws, x.at FROM head_to_head x ${on} WHERE x.pkey = ? ORDER BY x.at DESC LIMIT 50`, [pkey], ['other']),
      this.named(`SELECT x.other AS other, ${NAME} AS name, x.status, x.at FROM social_links x ${on} WHERE x.pkey = ? ORDER BY x.at DESC LIMIT 200`, [pkey], ['other']),
      this.named(`SELECT x.other AS other, x.name AS name, x.mode, x.ranked, x.at FROM recent_players x WHERE x.pkey = ? ORDER BY x.at DESC LIMIT 30`, [pkey], ['other']),
      this.rows('SELECT id, cat, deck, stake, seed_type, seed, time, at, v FROM speedruns WHERE pkey = ? ORDER BY at DESC LIMIT 50', [pkey]),
      this.rows('SELECT id, name, author, version, size, at, updated, downloads, hidden FROM forge_mods WHERE owner = ? ORDER BY updated DESC LIMIT 50', [pkey]),
      this.rows('SELECT item, source, at FROM unlocks WHERE pkey = ? ORDER BY at DESC LIMIT 300', [pkey]),
      this.rows('SELECT slot, item FROM equipped WHERE pkey = ?', [pkey]),
      this.rows('SELECT day, won, ante, round, best, at FROM daily_board WHERE pkey = ? ORDER BY day DESC LIMIT 30', [pkey]),
      this.rows('SELECT game, score, low, at FROM minigame_best WHERE pkey = ?', [pkey]),
      this.named('SELECT id, reporter, reported, kind, text, reason, match_id, at, status FROM chat_reports WHERE reporter = ? OR reported = ? ORDER BY at DESC LIMIT 50', [pkey, pkey], ['reporter', 'reported']),
    ]);
    return {
      at: this.now(), profile: this.shape(base),
      online: live ? { version: live.version, mods: live.mods, room: live.room, party: live.party, where: live.where, queue: live.queue, since: live.since } : null,
      ranked, logs: logs.map(l => ({ ...l, item: tryJson(l.item) })), head_to_head: h2h, links, recent, speedruns: runs, forge_mods: mods, unlocks, equipped, daily, minigames: mini, reports,
    };
  }

  async stats(): Promise<Row> {
    return this.cached('stats', 1_800_000, async () => {
      const t = this.now();
      const top = (order: string, where = '') => this.named(
        `SELECT pkey, name, rp, level, xp, matches, wins, streak FROM players ${where} ORDER BY ${order} DESC LIMIT 10`, [], ['pkey']);
      const [created, lastSeen, logDays, logHours, modes, statuses, ranks, levels, hours, days, topRp, topLevel, topMatches, topWins, topStreak, friends, cosmetics] = await Promise.all([
        this.rows(`SELECT date(created / 1000, 'unixepoch') d, COUNT(*) n FROM players GROUP BY d ORDER BY d`),
        this.rows(`WITH seen AS (SELECT pkey, MAX(ls) ls FROM (SELECT pkey, last_seen ls FROM players UNION ALL SELECT pkey, last_seen ls FROM social_players) GROUP BY pkey)
          SELECT date(ls / 1000, 'unixepoch') d, COUNT(*) n FROM seen GROUP BY d ORDER BY d`),
        this.rows(`SELECT date(at / 1000, 'unixepoch') d, mode, kind, ranked, COUNT(*) n FROM match_logs GROUP BY d, mode, kind, ranked ORDER BY d`),
        this.rows(`SELECT CAST(strftime('%H', at / 1000, 'unixepoch') AS INTEGER) h, COUNT(*) n FROM match_logs GROUP BY h ORDER BY h`),
        this.rows(`SELECT mode, kind, ranked, COUNT(*) n, AVG(CASE WHEN ended > at THEN ended - at END) avg_ms FROM match_logs GROUP BY mode, kind, ranked ORDER BY n DESC`),
        this.rows(`SELECT COALESCE(status, '') status, COUNT(*) n FROM match_logs GROUP BY status ORDER BY n DESC`),
        this.rows(`SELECT rp / 100 * 100 AS floor, COUNT(*) n FROM players WHERE matches > 0 GROUP BY floor ORDER BY floor`),
        this.rows(`SELECT level, COUNT(*) n FROM players GROUP BY level ORDER BY level`),
        this.rows(`SELECT * FROM admin_hours WHERE h >= ? ORDER BY h`, [Math.floor((t - 30 * DAY) / HOUR)]),
        this.rows(`SELECT day, devices, players, checks, patch_dl, online_peak FROM admin_days ORDER BY day DESC LIMIT 120`),
        top('rp', 'WHERE matches > 0'), top('xp'), top('matches', 'WHERE matches > 0'), top('wins', 'WHERE wins > 0'), top('streak', 'WHERE streak > 0'),
        this.one(`SELECT COUNT(*) / 2 links, COUNT(DISTINCT pkey) players FROM social_links WHERE status = 'accepted'`),
        this.rows(`SELECT slot, item, COUNT(*) n FROM equipped GROUP BY slot, item ORDER BY n DESC LIMIT 30`),
      ]);
      const hr = this.hour;
      if (hr) {
        const live = this.deps.live();
        const cur = hours.find(x => num(x.h) === hr.h);
        const peak = Math.max(hr.onlinePeak, live.conns, num(cur?.online_peak));
        if (cur) cur.online_peak = peak;
        else hours.push({ h: hr.h, online_peak: peak, named_peak: hr.namedPeak, rooms_peak: hr.roomsPeak, playing_peak: hr.playingPeak });
      }
      const liveDay = { day: this.today.day, devices: this.today.devices.size, players: this.today.players.size, checks: this.today.checks, patch_dl: this.today.patch, online_peak: this.today.onlinePeak };
      const dayRow = days.find(x => x.day === this.today.day);
      if (dayRow) Object.assign(dayRow, liveDay);
      else if (this.today.day) days.unshift(liveDay);
      return {
        at: t, created, last_seen: lastSeen, log_days: logDays, log_hours: logHours, modes, statuses,
        ranks: ranks.map(r => ({ ...r, name: rankOf(num(r.floor)).name, tier: rankOf(num(r.floor)).tier })), levels, hours, days: days.reverse(),
        top: { rp: topRp.map(r => ({ ...r, rank_name: rankOf(num(r.rp)).name })), level: topLevel, matches: topMatches, wins: topWins, streak: topStreak }, friends, cosmetics,
      };
    });
  }

  async installs(): Promise<Row> {
    this.roll();
    const days = await this.cached('installs', 600_000, () => this.rows('SELECT day, devices, players, checks, patch_dl, online_peak, detail FROM admin_days ORDER BY day DESC LIMIT 120'));
    const list: Row[] = days.map(d => ({ ...d, detail: (tryJson(d.detail) as { rows?: unknown } | null)?.rows ?? {} })).reverse();
    const liveDay: Row = { day: this.today.day, devices: this.today.devices.size, players: this.today.players.size, checks: this.today.checks, patch_dl: this.today.patch, online_peak: this.today.onlinePeak, detail: this.today.detail() };
    const at = list.findIndex(d => d.day === this.today.day);
    if (at >= 0) list[at] = liveDay;
    else if (this.today.day) list.push(liveDay);
    return {
      at: this.now(),
      today: { day: this.today.day, devices: this.today.devices.size, players: this.today.players.size, checks: this.today.checks, patch_downloads: this.today.patch, rows: this.today.detail() },
      days: list,
    };
  }

  async matches(p: URLSearchParams): Promise<Row> {
    const size = 50;
    const page = Math.max(0, Math.floor(num(p.get('page'))));
    const total = num((await this.cached('matches:n', 600_000, () => this.one('SELECT COUNT(*) n FROM match_logs'))).n);
    const rows = await this.rows(
      `SELECT l.id, l.at, l.ended, l.mode, l.kind, l.ranked, l.status, l.has_replay, l.bytes, l.keep_until,
        (SELECT group_concat(COALESCE(NULLIF(p.name, ''), s.name, '?'), ', ') FROM match_log_players o LEFT JOIN players p ON p.pkey = o.pkey LEFT JOIN social_players s ON s.pkey = o.pkey WHERE o.id = l.id) AS names
       FROM match_logs l ORDER BY l.at DESC LIMIT ? OFFSET ?`, [size, page * size]);
    return { at: this.now(), total, page, size, rows };
  }

  async boards(): Promise<Row> {
    return this.cached('boards', 600_000, async () => ({
      at: this.now(),
      speedruns: await this.named('SELECT pkey, name, cat, deck, stake, seed_type, time, at FROM speedruns ORDER BY cat, time LIMIT 200', [], ['pkey']),
      daily: await this.named('SELECT day, pkey, name, won, ante, round, best, at FROM daily_board WHERE day >= ? ORDER BY day DESC, won DESC, ante DESC, round DESC, best DESC LIMIT 300', [dayOf(this.now() - 7 * DAY)], ['pkey']),
      minigames: await this.named(`SELECT x.pkey AS pkey, COALESCE(NULLIF(p.name, ''), s.name, '') AS name, x.game, x.score, x.low, x.at FROM minigame_best x
        LEFT JOIN players p ON p.pkey = x.pkey LEFT JOIN social_players s ON s.pkey = x.pkey ORDER BY x.game, x.score DESC LIMIT 300`, [], ['pkey']),
    }));
  }

  async forge(): Promise<Row> {
    return this.cached('forge', 600_000, async () => ({
      at: this.now(),
      mods: (await this.named(`SELECT x.id, x.owner AS owner, x.name, x.author, x.about, x.version, x.summary, x.size, x.at, x.updated, x.downloads, x.hidden,
        CASE WHEN COALESCE(x.reports, '') IN ('', '[]') THEN 0 ELSE 1 END AS reported FROM forge_mods x ORDER BY x.updated DESC LIMIT 300`, [], ['owner']))
        .map(m => ({ ...m, about: aboutText(m.about), summary: tryJson(m.summary) ?? {} })),
    }));
  }

  async reports(): Promise<Row> {
    const on = (c: string, a: string) => `LEFT JOIN players ${a}p ON ${a}p.pkey = x.${c} LEFT JOIN social_players ${a}s ON ${a}s.pkey = x.${c}`;
    return {
      at: this.now(),
      rows: await this.named(`SELECT x.id, x.reporter AS reporter, x.reported AS reported, COALESCE(NULLIF(r1p.name, ''), r1s.name, '') AS reporter_name,
        COALESCE(NULLIF(r2p.name, ''), r2s.name, '') AS reported_name, x.kind, x.text, x.reason, x.match_id, x.at, x.status
        FROM chat_reports x ${on('reporter', 'r1')} ${on('reported', 'r2')} ORDER BY x.at DESC LIMIT 200`, [], ['reporter', 'reported']),
    };
  }
}

function aboutText(v: unknown): string {
  const j = tryJson(v);
  if (Array.isArray(j)) return j.filter(x => typeof x === 'string').join(' ');
  return j === null && typeof v === 'string' ? v : '';
}

function tryJson(v: unknown): unknown {
  if (typeof v !== 'string' || v === '') return null;
  try {
    return JSON.parse(v);
  } catch {
    return null;
  }
}
