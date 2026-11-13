export const FORGE_TYPES = ['forge_publish', 'forge_browse', 'forge_get', 'forge_report', 'forge_unpublish'];
export const FORGE_MAX_BYTES = 512 * 1024;
export const FORGE_MAX_ITEMS = 60;
export const FORGE_MAX_FILE_B64 = 88 * 1024;
export const FORGE_PER_PAGE = 4;
export const FORGE_MAX_PER_OWNER = 20;
export const FORGE_HIDE_AT = 3;
export const FORGE_PUBLISH_GAP_MS = 20_000;
export const FORGE_MAX_V = 99;

const ID_RE = /^[a-z0-9]{4,8}$/;
const PKEY_RE = /^[A-Za-z0-9]{24}$/;
const FILE_KEY_RE = /^[A-Za-z0-9_]{1,40}$/;
const B64_RE = /^[A-Za-z0-9+/]*={0,2}$/;
const KINDS = new Set(['joker', 'tarot', 'planet', 'spectral', 'voucher', 'enhancement', 'seal', 'edition', 'tag', 'blind', 'stake', 'deck', 'booster', 'collab']);
const REASONS = new Set(['broken', 'rude', 'stolen', 'other']);

export interface ForgeEntry {
  id: string;
  owner: string;
  name: string;
  author: string;
  about: string[];
  version: number;
  summary: Record<string, number>;
  size: number;
  raw: string;
  at: number;
  updated: number;
  downloads: number;
  reports: string[];
  hidden: boolean;
}

export interface ForgeRow {
  id: string; name: string; author: string; about: string[]; version: number;
  summary: Record<string, number>; size: number; downloads: number; updated: number; mine?: boolean;
}

export interface ForgeStore {
  readonly kind: string;
  init(): Promise<void>;
  get(id: string): Promise<ForgeEntry | null>;
  put(e: ForgeEntry): Promise<void>;
  remove(id: string): Promise<void>;
  list(): Promise<ForgeEntry[]>;
}

export class MemoryForgeStore implements ForgeStore {
  readonly kind = 'memory';
  rows = new Map<string, ForgeEntry>();
  async init(): Promise<void> {}
  async get(id: string): Promise<ForgeEntry | null> { const e = this.rows.get(id); return e ? { ...e, reports: [...e.reports] } : null; }
  async put(e: ForgeEntry): Promise<void> { this.rows.set(e.id, { ...e, reports: [...e.reports] }); }
  async remove(id: string): Promise<void> { this.rows.delete(id); }
  async list(): Promise<ForgeEntry[]> { return [...this.rows.values()].map(e => ({ ...e, raw: '', reports: [...e.reports] })); }
}

export interface D1Like {
  kind?: string;
  query(sql: string, params?: unknown[]): Promise<Record<string, unknown>[]>;
  write(sql: string, params: unknown[]): void;
}

export const FORGE_SCHEMA = [
  `CREATE TABLE IF NOT EXISTS forge_mods (id TEXT PRIMARY KEY, owner TEXT NOT NULL, name TEXT NOT NULL, author TEXT NOT NULL, about TEXT NOT NULL,
    version INTEGER NOT NULL, summary TEXT NOT NULL, size INTEGER NOT NULL, raw TEXT NOT NULL, at INTEGER NOT NULL, updated INTEGER NOT NULL,
    downloads INTEGER NOT NULL, reports TEXT NOT NULL, hidden INTEGER NOT NULL)`,
];

function parseJson<T>(s: unknown, def: T): T {
  try { return typeof s === 'string' ? JSON.parse(s) as T : def; } catch { return def; }
}

function toEntry(r: Record<string, unknown>): ForgeEntry {
  return {
    id: String(r.id), owner: String(r.owner), name: String(r.name ?? ''), author: String(r.author ?? ''), about: parseJson<string[]>(r.about, []),
    version: Number(r.version) || 1, summary: parseJson<Record<string, number>>(r.summary, {}), size: Number(r.size) || 0, raw: String(r.raw ?? ''),
    at: Number(r.at) || 0, updated: Number(r.updated) || 0, downloads: Number(r.downloads) || 0, reports: parseJson<string[]>(r.reports, []), hidden: Number(r.hidden) === 1,
  };
}

export class D1ForgeStore implements ForgeStore {
  readonly kind = 'd1';
  constructor(private d1: D1Like) {}
  async init(): Promise<void> { for (const sql of FORGE_SCHEMA) await this.d1.query(sql); }
  async get(id: string): Promise<ForgeEntry | null> {
    const rows = await this.d1.query('SELECT * FROM forge_mods WHERE id = ?', [id]);
    return rows[0] ? toEntry(rows[0]) : null;
  }
  async put(e: ForgeEntry): Promise<void> {
    await this.d1.query(`INSERT INTO forge_mods (id, owner, name, author, about, version, summary, size, raw, at, updated, downloads, reports, hidden)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT (id) DO UPDATE SET owner = excluded.owner, name = excluded.name, author = excluded.author,
      about = excluded.about, version = excluded.version, summary = excluded.summary, size = excluded.size, raw = excluded.raw, updated = excluded.updated,
      downloads = excluded.downloads, reports = excluded.reports, hidden = excluded.hidden`,
    [e.id, e.owner, e.name, e.author, JSON.stringify(e.about), e.version, JSON.stringify(e.summary), e.size, e.raw, e.at, e.updated, e.downloads, JSON.stringify(e.reports), e.hidden ? 1 : 0]);
  }
  async remove(id: string): Promise<void> { await this.d1.query('DELETE FROM forge_mods WHERE id = ?', [id]); }
  async list(): Promise<ForgeEntry[]> {
    const rows = await this.d1.query(`SELECT id, owner, name, author, about, version, summary, size, '' AS raw, at, updated, downloads, reports, hidden FROM forge_mods`);
    return rows.map(toEntry);
  }
}

export function forgeStoreFor(store: unknown): ForgeStore {
  const s = store as D1Like | null;
  if (s && s.kind === 'd1' && typeof s.query === 'function' && typeof s.write === 'function') return new D1ForgeStore(s);
  return new MemoryForgeStore();
}

function isInt(v: unknown, lo: number, hi: number): boolean {
  return typeof v === 'number' && Number.isInteger(v) && v >= lo && v <= hi;
}

export function validateForge(msg: Record<string, unknown>): string | null {
  const t = msg.type;
  if (typeof t !== 'string' || !FORGE_TYPES.includes(t)) return null;
  if (t === 'forge_publish') {
    if (typeof msg.mod !== 'string' || msg.mod.length === 0) return 'forge_publish: missing mod';
    if (msg.mod.length > FORGE_MAX_BYTES) return 'forge_publish: too big';
  }
  if (t === 'forge_browse') {
    if (msg.page !== undefined && !isInt(msg.page, 1, 10000)) return 'forge_browse: invalid page';
    if (msg.q !== undefined && (typeof msg.q !== 'string' || msg.q.length > 24)) return 'forge_browse: invalid q';
    if (msg.mine !== undefined && typeof msg.mine !== 'boolean') return 'forge_browse: invalid mine';
  }
  if (t === 'forge_get' || t === 'forge_report' || t === 'forge_unpublish') {
    if (typeof msg.id !== 'string' || !ID_RE.test(msg.id)) return `${t}: invalid id`;
  }
  if (t === 'forge_report' && (typeof msg.reason !== 'string' || !REASONS.has(msg.reason))) return 'forge_report: invalid reason';
  return null;
}

function clean(s: unknown, max: number): string {
  return String(typeof s === 'string' ? s : '').replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, max);
}

export type Checked = { ok: true; id: string; name: string; author: string; about: string[]; version: number; summary: Record<string, number> } | { ok: false; reason: string; why?: string };

function no(reason: string, why: string): Checked { return { ok: false, reason, why }; }

export function checkMod(raw: string): Checked {
  if (raw.length > FORGE_MAX_BYTES) return no('too_big', 'too_big');
  let t: Record<string, unknown>;
  try {
    const p = JSON.parse(raw) as unknown;
    if (!p || typeof p !== 'object' || Array.isArray(p)) return no('not_forge', 'not_json');
    t = p as Record<string, unknown>;
  } catch { return no('not_forge', 'not_json'); }
  if (t.format !== 'forgemod') return no('not_forge', 'bad_format');
  if (!isInt(t.v, 1, FORGE_MAX_V)) return no('not_forge', 'bad_version');
  if (typeof t.id !== 'string' || !ID_RE.test(t.id)) return no('not_forge', 'bad_id');
  const jokers = Array.isArray(t.jokers) ? t.jokers : [];
  const creations = Array.isArray(t.creations) ? t.creations : [];
  if (t.jokers !== undefined && !Array.isArray(t.jokers) && !(typeof t.jokers === 'object' && t.jokers && Object.keys(t.jokers).length === 0)) return no('not_forge', 'bad_jokers');
  if (t.creations !== undefined && !Array.isArray(t.creations) && !(typeof t.creations === 'object' && t.creations && Object.keys(t.creations).length === 0)) return no('not_forge', 'bad_creations');
  const n = jokers.length + creations.length;
  if (n === 0) return no('empty', 'empty');
  if (n > FORGE_MAX_ITEMS) return no('too_many', 'too_many');
  const summary: Record<string, number> = {};
  for (const j of jokers) {
    if (!j || typeof j !== 'object' || Array.isArray(j)) return no('not_forge', 'bad_joker');
    summary.joker = (summary.joker ?? 0) + 1;
  }
  for (const c of creations) {
    const kind = c && typeof c === 'object' ? (c as Record<string, unknown>).kind : undefined;
    if (typeof kind !== 'string' || !KINDS.has(kind) || kind === 'joker') return no('not_forge', 'bad_kind');
    summary[kind] = (summary[kind] ?? 0) + 1;
  }
  if (t.files !== undefined && t.files !== null) {
    if (typeof t.files !== 'object') return no('not_forge', 'bad_files');
    const entries = Array.isArray(t.files) ? [] : Object.entries(t.files as Record<string, unknown>);
    if (Array.isArray(t.files) && t.files.length > 0) return no('not_forge', 'bad_files');
    if (entries.length > 200) return no('too_many', 'too_many_files');
    for (const [k, v] of entries) {
      if (!FILE_KEY_RE.test(k)) return no('bad_art', 'bad_art_name');
      if (typeof v === 'string' && v.length > FORGE_MAX_FILE_B64) return no('bad_art', 'art_too_big');
      if (typeof v !== 'string' || v.length % 4 !== 0 || !B64_RE.test(v) || !v.startsWith('iVBORw0KGgo')) return no('bad_art', 'bad_art');
    }
  }
  const name = clean(t.name, 24) || 'Forge mod';
  const about = (Array.isArray(t.about) ? t.about : []).filter((l): l is string => typeof l === 'string').map(l => clean(l, 48)).filter(l => l !== '').slice(0, 2);
  const version = isInt(t.version, 1, 9999) ? Number(t.version) : 1;
  return { ok: true, id: t.id, name, author: clean(t.author, 24), about, version, summary };
}

export interface ForgeDeps {
  now?: () => number;
  log?: (level: string, msg: string) => void;
}

export type PublishOut = { ok: true; id: string; version: number; updated: boolean } | { ok: false; reason: string; why?: string };
export interface ListOut { mods: ForgeRow[]; page: number; pages: number; total: number }

export class ForgeBoard {
  private ready: Promise<void> | null = null;
  private lastPublish = new Map<string, number>();
  private busy = new Set<string>();
  constructor(readonly store: ForgeStore, private deps: ForgeDeps = {}) {}

  private now(): number { return this.deps.now ? this.deps.now() : Date.now(); }

  ensure(): Promise<void> {
    if (!this.ready) this.ready = this.store.init().catch(e => { this.ready = null; throw e; });
    return this.ready;
  }

  async publish(pkey: string | undefined, raw: string, bot = false): Promise<PublishOut> {
    if (bot) return { ok: false, reason: 'bot' };
    if (!pkey || !PKEY_RE.test(pkey)) return { ok: false, reason: 'no_key' };
    const c = checkMod(raw);
    if (!c.ok) return c;
    const last = this.lastPublish.get(pkey) ?? 0;
    if (this.now() - last < FORGE_PUBLISH_GAP_MS) return { ok: false, reason: 'too_soon' };
    await this.ensure();
    if (this.busy.has(c.id)) return { ok: false, reason: 'busy' };
    this.busy.add(c.id);
    try {
      const old = await this.store.get(c.id);
      if (old && old.owner !== pkey) return { ok: false, reason: 'taken' };
      if (!old) {
        const mine = (await this.store.list()).filter(e => e.owner === pkey).length;
        if (mine >= FORGE_MAX_PER_OWNER) return { ok: false, reason: 'too_many_mods' };
      }
      const t = this.now();
      const e: ForgeEntry = {
        id: c.id, owner: pkey, name: c.name, author: c.author, about: c.about, version: Math.max(c.version, old ? old.version : 1),
        summary: c.summary, size: raw.length, raw, at: old ? old.at : t, updated: t, downloads: old ? old.downloads : 0,
        reports: old ? old.reports : [], hidden: old ? old.hidden : false,
      };
      await this.store.put(e);
      this.lastPublish.set(pkey, t);
      this.deps.log?.('INFO', 'FORGE', `${old ? 'updated' : 'published'} ${e.id} "${e.name}" ${e.size} bytes`);
      return { ok: true, id: e.id, version: e.version, updated: old !== null };
    } finally {
      this.busy.delete(c.id);
    }
  }

  async browse(pkey: string | undefined, page = 1, q = '', mineOnly = false): Promise<ListOut> {
    await this.ensure();
    const query = q.trim().toLowerCase();
    let list = (await this.store.list()).filter(e => (!e.hidden || (pkey && e.owner === pkey)));
    if (mineOnly) list = list.filter(e => pkey && e.owner === pkey);
    if (query) list = list.filter(e => e.name.toLowerCase().includes(query) || e.author.toLowerCase().includes(query));
    list.sort((a, b) => b.updated - a.updated || (a.id < b.id ? -1 : 1));
    const pages = Math.max(1, Math.ceil(list.length / FORGE_PER_PAGE));
    const p = Math.min(Math.max(1, page), pages);
    const mods = list.slice((p - 1) * FORGE_PER_PAGE, p * FORGE_PER_PAGE).map(e => {
      const r: ForgeRow = { id: e.id, name: e.name, author: e.author, about: e.about, version: e.version, summary: e.summary, size: e.size, downloads: e.downloads, updated: e.updated };
      if (pkey && e.owner === pkey) r.mine = true;
      return r;
    });
    return { mods, page: p, pages, total: list.length };
  }

  async get(pkey: string | undefined, id: string): Promise<{ ok: true; id: string; mod: string } | { ok: false; reason: string }> {
    await this.ensure();
    const e = await this.store.get(id);
    if (!e || (e.hidden && e.owner !== pkey)) return { ok: false, reason: 'gone' };
    if (e.owner !== pkey) {
      e.downloads += 1;
      await this.store.put(e);
    }
    return { ok: true, id: e.id, mod: e.raw };
  }

  async report(pkey: string | undefined, id: string, reason: string): Promise<{ ok: boolean; reason?: string }> {
    if (!pkey || !PKEY_RE.test(pkey)) return { ok: false, reason: 'no_key' };
    await this.ensure();
    const e = await this.store.get(id);
    if (!e) return { ok: false, reason: 'gone' };
    if (e.owner === pkey) return { ok: false, reason: 'own' };
    if (e.reports.includes(pkey)) return { ok: true };
    e.reports.push(pkey);
    if (e.reports.length >= FORGE_HIDE_AT) e.hidden = true;
    await this.store.put(e);
    this.deps.log?.('WARN', 'FORGE', `report ${id} (${reason}) ${e.reports.length}${e.hidden ? ' hidden' : ''}`);
    return { ok: true };
  }

  async unpublish(pkey: string | undefined, id: string): Promise<{ ok: boolean; reason?: string }> {
    if (!pkey || !PKEY_RE.test(pkey)) return { ok: false, reason: 'no_key' };
    await this.ensure();
    const e = await this.store.get(id);
    if (!e) return { ok: false, reason: 'gone' };
    if (e.owner !== pkey) return { ok: false, reason: 'not_yours' };
    await this.store.remove(id);
    return { ok: true };
  }
}

export let forgeBoard = new ForgeBoard(new MemoryForgeStore());
export function setForgeBoard(b: ForgeBoard): void { forgeBoard = b; }

export interface ForgeHandlerDeps<W> {
  keyOf: (ws: W, msg: Record<string, unknown>) => string | undefined;
  isBot: (ws: W) => boolean;
  send: (ws: W, data: object) => void;
}

export function forgeHandlers<W>(d: ForgeHandlerDeps<W>): Record<string, (ws: W, msg: Record<string, unknown>) => void> {
  return {
    forge_publish: (ws, msg) => {
      forgeBoard.publish(d.keyOf(ws, msg), String(msg.mod), d.isBot(ws))
        .then(r => d.send(ws, { type: 'forge_published', ...r }))
        .catch(() => d.send(ws, { type: 'forge_published', ok: false, reason: 'unavailable' }));
    },
    forge_browse: (ws, msg) => {
      const page = typeof msg.page === 'number' ? msg.page : 1;
      forgeBoard.browse(d.keyOf(ws, msg), page, typeof msg.q === 'string' ? msg.q : '', msg.mine === true)
        .then(r => d.send(ws, { type: 'forge_list', ...r }))
        .catch(() => d.send(ws, { type: 'forge_list', mods: [], page: 1, pages: 1, total: 0, error: 'unavailable' }));
    },
    forge_get: (ws, msg) => {
      const id = String(msg.id);
      forgeBoard.get(d.keyOf(ws, msg), id)
        .then(r => d.send(ws, { type: 'forge_mod', ...r, id }))
        .catch(() => d.send(ws, { type: 'forge_mod', ok: false, id, reason: 'unavailable' }));
    },
    forge_report: (ws, msg) => {
      const id = String(msg.id);
      forgeBoard.report(d.keyOf(ws, msg), id, String(msg.reason))
        .then(r => d.send(ws, { type: 'forge_reported', id, ...r }))
        .catch(() => d.send(ws, { type: 'forge_reported', id, ok: false, reason: 'unavailable' }));
    },
    forge_unpublish: (ws, msg) => {
      const id = String(msg.id);
      forgeBoard.unpublish(d.keyOf(ws, msg), id)
        .then(r => d.send(ws, { type: 'forge_unpublished', id, ...r }))
        .catch(() => d.send(ws, { type: 'forge_unpublished', id, ok: false, reason: 'unavailable' }));
    },
  };
}
