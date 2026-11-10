import { D1Store, MemoryStore, type RankedStore } from './ranked_store';

export const CHAT_REPORTS_STATUS_SQL = "ALTER TABLE chat_reports ADD COLUMN status TEXT NOT NULL DEFAULT 'open'";

export const SOCIAL2_SCHEMA = [
  `CREATE TABLE IF NOT EXISTS social_prefs (
  pkey TEXT PRIMARY KEY,
  name_key TEXT NOT NULL DEFAULT '',
  rp INTEGER,
  chat_enabled INTEGER NOT NULL DEFAULT 0,
  chat_allowed INTEGER
)`,
  'CREATE INDEX IF NOT EXISTS social_prefs_name ON social_prefs (name_key)',
  `CREATE TABLE IF NOT EXISTS chat_dms (
  id TEXT PRIMARY KEY,
  conv TEXT NOT NULL,
  sender TEXT NOT NULL,
  at INTEGER NOT NULL,
  text TEXT NOT NULL
)`,
  'CREATE INDEX IF NOT EXISTS chat_dms_conv ON chat_dms (conv, at)',
  `CREATE TABLE IF NOT EXISTS chat_unread (
  pkey TEXT NOT NULL,
  other TEXT NOT NULL,
  n INTEGER NOT NULL,
  PRIMARY KEY (pkey, other)
)`,
  `CREATE TABLE IF NOT EXISTS chat_mutes (
  pkey TEXT NOT NULL,
  other TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (pkey, other)
)`,
  `CREATE TABLE IF NOT EXISTS chat_reports (
  id TEXT PRIMARY KEY,
  reporter TEXT NOT NULL,
  reported TEXT NOT NULL,
  kind TEXT NOT NULL,
  msg_id TEXT NOT NULL,
  text TEXT NOT NULL,
  context TEXT NOT NULL,
  reason TEXT NOT NULL,
  match_id TEXT,
  at INTEGER NOT NULL
)`,
  'CREATE INDEX IF NOT EXISTS chat_reports_at ON chat_reports (at)',
  `CREATE TABLE IF NOT EXISTS notify_items (
  id TEXT PRIMARY KEY,
  pkey TEXT NOT NULL,
  kind TEXT NOT NULL,
  at INTEGER NOT NULL,
  read INTEGER NOT NULL DEFAULT 0,
  data TEXT NOT NULL,
  expires INTEGER
)`,
  'CREATE INDEX IF NOT EXISTS notify_items_pkey ON notify_items (pkey, at)',
];

export interface PrefsRow { chat_enabled: boolean; chat_allowed: boolean | null; rp: number | null }
export interface NameHit { pkey: string; code: string; name: string; last_seen: number; rp: number | null }
export interface DmRow { id: string; conv: string; sender: string; at: number; text: string }
export interface ReportRow {
  id: string; reporter: string; reported: string; kind: 'dm' | 'lobby'; msg_id: string; text: string;
  context: string; reason: string; match_id: string | null; at: number;
}
export interface NotifyRow { id: string; pkey: string; kind: string; at: number; read: boolean; data: Record<string, unknown>; expires: number | null }

export interface SocialExtra {
  init(): Promise<void>;
  prefsGet(pkey: string): Promise<PrefsRow | null>;
  prefsMany(pkeys: string[]): Promise<Map<string, PrefsRow>>;
  prefsTouch(pkey: string, nameKey: string, rp: number | null): void;
  prefsSetChat(pkey: string, enabled: boolean, allowed: boolean | null): void;
  searchNames(key: string, limit: number): Promise<NameHit[]>;
  players(pkeys: string[]): Promise<{ pkey: string; code: string; name: string }[]>;
  dmAdd(row: DmRow): void;
  dmGet(id: string): Promise<DmRow | null>;
  dmHistory(conv: string, before: number | null, limit: number): Promise<DmRow[]>;
  dmPrune(conv: string, keep: number): void;
  unreadAll(pkey: string): Promise<Map<string, number>>;
  unreadBump(pkey: string, other: string): void;
  unreadClear(pkey: string, other: string): void;
  mutesOf(pkey: string): Promise<string[]>;
  muteAdd(pkey: string, other: string, at: number): void;
  muteRemove(pkey: string, other: string): void;
  reportAdd(r: ReportRow): void;
  notifyList(pkey: string): Promise<NotifyRow[]>;
  notifyAdd(r: NotifyRow): void;
  notifyRead(pkey: string, id: string | null): void;
  notifyDelete(pkey: string, id: string | null): void;
}

interface MemPrefs { nameKey: string; rp: number | null; chat_enabled: boolean; chat_allowed: boolean | null }

export class MemoryExtra implements SocialExtra {
  prefs = new Map<string, MemPrefs>();
  dms: DmRow[] = [];
  unread = new Map<string, Map<string, number>>();
  mutes = new Map<string, Set<string>>();
  reports: ReportRow[] = [];
  notes = new Map<string, NotifyRow[]>();

  constructor(private base: MemoryStore | null = null) {}

  async init(): Promise<void> { return; }

  async prefsGet(pkey: string): Promise<PrefsRow | null> {
    const p = this.prefs.get(pkey);
    return p ? { chat_enabled: p.chat_enabled, chat_allowed: p.chat_allowed, rp: p.rp } : null;
  }

  async prefsMany(pkeys: string[]): Promise<Map<string, PrefsRow>> {
    const out = new Map<string, PrefsRow>();
    for (const k of pkeys) {
      const p = await this.prefsGet(k);
      if (p) out.set(k, p);
    }
    return out;
  }

  prefsTouch(pkey: string, nameKey: string, rp: number | null): void {
    const old = this.prefs.get(pkey) ?? { nameKey: '', rp: null, chat_enabled: false, chat_allowed: null };
    this.prefs.set(pkey, { ...old, nameKey: nameKey || old.nameKey, rp: rp ?? old.rp });
  }

  prefsSetChat(pkey: string, enabled: boolean, allowed: boolean | null): void {
    const old = this.prefs.get(pkey) ?? { nameKey: '', rp: null, chat_enabled: false, chat_allowed: null };
    this.prefs.set(pkey, { ...old, chat_enabled: enabled, chat_allowed: allowed });
  }

  async searchNames(key: string, limit: number): Promise<NameHit[]> {
    const out: NameHit[] = [];
    for (const [pkey, f] of this.prefs) {
      const row = this.base?.socialPlayers.get(pkey);
      if (!row || !f.nameKey.includes(key)) continue;
      out.push({ pkey, code: row.code, name: row.name, last_seen: row.last_seen, rp: f.rp });
    }
    return out.sort((a, b) => b.last_seen - a.last_seen).slice(0, limit);
  }

  async players(pkeys: string[]): Promise<{ pkey: string; code: string; name: string }[]> {
    const out: { pkey: string; code: string; name: string }[] = [];
    for (const k of pkeys) {
      const row = this.base?.socialPlayers.get(k);
      if (row) out.push({ pkey: k, code: row.code, name: row.name });
    }
    return out;
  }

  dmAdd(row: DmRow): void { if (!this.dms.some(d => d.id === row.id)) this.dms.push({ ...row }); }
  async dmGet(id: string): Promise<DmRow | null> { const d = this.dms.find(x => x.id === id); return d ? { ...d } : null; }
  async dmHistory(conv: string, before: number | null, limit: number): Promise<DmRow[]> {
    return this.dms.filter(d => d.conv === conv && (before === null || d.at < before))
      .sort((a, b) => b.at - a.at || (a.id < b.id ? 1 : -1)).slice(0, limit).map(d => ({ ...d }));
  }
  dmPrune(conv: string, keep: number): void {
    const mine = this.dms.filter(d => d.conv === conv).sort((a, b) => b.at - a.at || (a.id < b.id ? 1 : -1));
    const drop = new Set(mine.slice(keep).map(d => d.id));
    if (drop.size > 0) this.dms = this.dms.filter(d => !drop.has(d.id));
  }

  async unreadAll(pkey: string): Promise<Map<string, number>> { return new Map(this.unread.get(pkey) ?? []); }
  unreadBump(pkey: string, other: string): void {
    const m = this.unread.get(pkey) ?? new Map<string, number>();
    m.set(other, (m.get(other) ?? 0) + 1);
    this.unread.set(pkey, m);
  }
  unreadClear(pkey: string, other: string): void { this.unread.get(pkey)?.delete(other); }

  async mutesOf(pkey: string): Promise<string[]> { return [...(this.mutes.get(pkey) ?? [])]; }
  muteAdd(pkey: string, other: string, _at: number): void {
    const s = this.mutes.get(pkey) ?? new Set<string>();
    s.add(other);
    this.mutes.set(pkey, s);
  }
  muteRemove(pkey: string, other: string): void { this.mutes.get(pkey)?.delete(other); }

  reportAdd(r: ReportRow): void { if (!this.reports.some(x => x.id === r.id)) this.reports.push({ ...r }); }

  async notifyList(pkey: string): Promise<NotifyRow[]> {
    return (this.notes.get(pkey) ?? []).map(n => ({ ...n, data: { ...n.data } })).sort((a, b) => b.at - a.at);
  }
  notifyAdd(r: NotifyRow): void {
    const list = (this.notes.get(r.pkey) ?? []).filter(n => n.id !== r.id);
    list.push({ ...r, data: { ...r.data } });
    this.notes.set(r.pkey, list);
  }
  notifyRead(pkey: string, id: string | null): void {
    for (const n of this.notes.get(pkey) ?? []) if (id === null || n.id === id) n.read = true;
  }
  notifyDelete(pkey: string, id: string | null): void {
    if (id === null) { this.notes.delete(pkey); return; }
    this.notes.set(pkey, (this.notes.get(pkey) ?? []).filter(n => n.id !== id));
  }
}

function escapeLike(s: string): string {
  return s.replace(/[\\%_]/g, m => `\\${m}`);
}

function bool(v: unknown): boolean { return Number(v) === 1; }

export class D1Extra implements SocialExtra {
  constructor(private d1: D1Store) {}

  async init(): Promise<void> {
    for (const sql of SOCIAL2_SCHEMA) await this.d1.query(sql);
    await this.d1.query(CHAT_REPORTS_STATUS_SQL).catch(() => undefined);
  }

  private toPrefs(r: Record<string, unknown>): PrefsRow {
    return {
      chat_enabled: bool(r.chat_enabled),
      chat_allowed: r.chat_allowed === null || r.chat_allowed === undefined ? null : bool(r.chat_allowed),
      rp: r.rp === null || r.rp === undefined ? null : Number(r.rp),
    };
  }

  async prefsGet(pkey: string): Promise<PrefsRow | null> {
    const rows = await this.d1.query('SELECT chat_enabled, chat_allowed, rp FROM social_prefs WHERE pkey = ?', [pkey]);
    return rows[0] ? this.toPrefs(rows[0]) : null;
  }

  async prefsMany(pkeys: string[]): Promise<Map<string, PrefsRow>> {
    const out = new Map<string, PrefsRow>();
    for (let i = 0; i < pkeys.length; i += 50) {
      const chunk = pkeys.slice(i, i + 50);
      const rows = await this.d1.query(
        `SELECT pkey, chat_enabled, chat_allowed, rp FROM social_prefs WHERE pkey IN (${chunk.map(() => '?').join(', ')})`, chunk);
      for (const r of rows) out.set(String(r.pkey), this.toPrefs(r));
    }
    return out;
  }

  prefsTouch(pkey: string, nameKey: string, rp: number | null): void {
    this.d1.enqueue(`INSERT INTO social_prefs (pkey, name_key, rp) VALUES (?, ?, ?)
      ON CONFLICT (pkey) DO UPDATE SET name_key = CASE WHEN excluded.name_key = '' THEN social_prefs.name_key ELSE excluded.name_key END,
      rp = COALESCE(excluded.rp, social_prefs.rp)`, [pkey, nameKey, rp]);
  }

  prefsSetChat(pkey: string, enabled: boolean, allowed: boolean | null): void {
    this.d1.enqueue(`INSERT INTO social_prefs (pkey, chat_enabled, chat_allowed) VALUES (?, ?, ?)
      ON CONFLICT (pkey) DO UPDATE SET chat_enabled = excluded.chat_enabled, chat_allowed = excluded.chat_allowed`,
    [pkey, enabled ? 1 : 0, allowed === null ? null : allowed ? 1 : 0]);
  }

  async searchNames(key: string, limit: number): Promise<NameHit[]> {
    const rows = await this.d1.query(`SELECT p.pkey AS pkey, p.code AS code, p.name AS name, p.last_seen AS last_seen, f.rp AS rp
      FROM social_players p LEFT JOIN social_prefs f ON f.pkey = p.pkey
      WHERE COALESCE(NULLIF(f.name_key, ''), lower(p.name)) LIKE ? ESCAPE '\\' ORDER BY p.last_seen DESC LIMIT ?`,
    [`%${escapeLike(key)}%`, limit]);
    return rows.map(r => ({
      pkey: String(r.pkey), code: String(r.code), name: String(r.name), last_seen: Number(r.last_seen),
      rp: r.rp === null || r.rp === undefined ? null : Number(r.rp),
    }));
  }

  async players(pkeys: string[]): Promise<{ pkey: string; code: string; name: string }[]> {
    const out: { pkey: string; code: string; name: string }[] = [];
    for (let i = 0; i < pkeys.length; i += 50) {
      const chunk = pkeys.slice(i, i + 50);
      const rows = await this.d1.query(
        `SELECT pkey, code, name FROM social_players WHERE pkey IN (${chunk.map(() => '?').join(', ')})`, chunk);
      for (const r of rows) out.push({ pkey: String(r.pkey), code: String(r.code), name: String(r.name) });
    }
    return out;
  }

  dmAdd(row: DmRow): void {
    this.d1.enqueue('INSERT OR IGNORE INTO chat_dms (id, conv, sender, at, text) VALUES (?, ?, ?, ?, ?)', [row.id, row.conv, row.sender, row.at, row.text]);
  }

  private toDm(r: Record<string, unknown>): DmRow {
    return { id: String(r.id), conv: String(r.conv), sender: String(r.sender), at: Number(r.at), text: String(r.text) };
  }

  async dmGet(id: string): Promise<DmRow | null> {
    const rows = await this.d1.query('SELECT id, conv, sender, at, text FROM chat_dms WHERE id = ?', [id]);
    return rows[0] ? this.toDm(rows[0]) : null;
  }

  async dmHistory(conv: string, before: number | null, limit: number): Promise<DmRow[]> {
    const rows = await this.d1.query(
      'SELECT id, conv, sender, at, text FROM chat_dms WHERE conv = ? AND at < ? ORDER BY at DESC, id DESC LIMIT ?',
      [conv, before ?? Number.MAX_SAFE_INTEGER, limit]);
    return rows.map(r => this.toDm(r));
  }

  dmPrune(conv: string, keep: number): void {
    this.d1.enqueue('DELETE FROM chat_dms WHERE conv = ? AND id NOT IN (SELECT id FROM chat_dms WHERE conv = ? ORDER BY at DESC, id DESC LIMIT ?)', [conv, conv, keep]);
  }

  async unreadAll(pkey: string): Promise<Map<string, number>> {
    const rows = await this.d1.query('SELECT other, n FROM chat_unread WHERE pkey = ?', [pkey]);
    return new Map(rows.map(r => [String(r.other), Number(r.n)] as [string, number]));
  }

  unreadBump(pkey: string, other: string): void {
    this.d1.enqueue('INSERT INTO chat_unread (pkey, other, n) VALUES (?, ?, 1) ON CONFLICT (pkey, other) DO UPDATE SET n = n + 1', [pkey, other]);
  }

  unreadClear(pkey: string, other: string): void {
    this.d1.enqueue('DELETE FROM chat_unread WHERE pkey = ? AND other = ?', [pkey, other]);
  }

  async mutesOf(pkey: string): Promise<string[]> {
    const rows = await this.d1.query('SELECT other FROM chat_mutes WHERE pkey = ?', [pkey]);
    return rows.map(r => String(r.other));
  }

  muteAdd(pkey: string, other: string, at: number): void {
    this.d1.enqueue('INSERT OR IGNORE INTO chat_mutes (pkey, other, at) VALUES (?, ?, ?)', [pkey, other, at]);
  }

  muteRemove(pkey: string, other: string): void {
    this.d1.enqueue('DELETE FROM chat_mutes WHERE pkey = ? AND other = ?', [pkey, other]);
  }

  reportAdd(r: ReportRow): void {
    this.d1.enqueue('INSERT OR IGNORE INTO chat_reports (id, reporter, reported, kind, msg_id, text, context, reason, match_id, at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [r.id, r.reporter, r.reported, r.kind, r.msg_id, r.text, r.context, r.reason, r.match_id, r.at]);
  }

  async notifyList(pkey: string): Promise<NotifyRow[]> {
    const rows = await this.d1.query('SELECT id, kind, at, read, data, expires FROM notify_items WHERE pkey = ? ORDER BY at DESC LIMIT 200', [pkey]);
    return rows.map(r => {
      let data: Record<string, unknown> = {};
      try { data = JSON.parse(String(r.data)) as Record<string, unknown>; } catch { data = {}; }
      return {
        id: unscopeNotifyId(String(r.id)), pkey, kind: String(r.kind), at: Number(r.at), read: bool(r.read), data,
        expires: r.expires === null || r.expires === undefined ? null : Number(r.expires),
      };
    });
  }

  notifyAdd(r: NotifyRow): void {
    this.d1.enqueue('INSERT OR REPLACE INTO notify_items (id, pkey, kind, at, read, data, expires) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [scopeNotifyId(r.pkey, r.id), r.pkey, r.kind, r.at, r.read ? 1 : 0, JSON.stringify(r.data), r.expires]);
  }

  notifyRead(pkey: string, id: string | null): void {
    if (id === null) this.d1.enqueue('UPDATE notify_items SET read = 1 WHERE pkey = ?', [pkey]);
    else this.d1.enqueue('UPDATE notify_items SET read = 1 WHERE pkey = ? AND id IN (?, ?)', [pkey, id, scopeNotifyId(pkey, id)]);
  }

  notifyDelete(pkey: string, id: string | null): void {
    if (id === null) this.d1.enqueue('DELETE FROM notify_items WHERE pkey = ?', [pkey]);
    else this.d1.enqueue('DELETE FROM notify_items WHERE pkey = ? AND id IN (?, ?)', [pkey, id, scopeNotifyId(pkey, id)]);
  }
}

export function scopeNotifyId(pkey: string, id: string): string {
  return `${id}#${pkey.slice(0, 8)}`;
}

export function unscopeNotifyId(id: string): string {
  return id.replace(/#[A-Za-z0-9]{1,8}$/, '');
}

export function socialExtraFor(store: RankedStore): SocialExtra {
  if (store instanceof D1Store) return new D1Extra(store);
  return new MemoryExtra(store instanceof MemoryStore ? store : null);
}
