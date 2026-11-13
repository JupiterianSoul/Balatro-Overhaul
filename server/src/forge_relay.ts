import { checkMod, FORGE_MAX_BYTES } from './forge_mods';

export const FORGE_ROOM_TYPES = ['forge_room_get', 'forge_room_put'];
export const FORGE_ROOM_PREFIX = 'forge:';
export const FORGE_ROOM_MAX = 50;
export const FORGE_RELAY_MS = 20_000;
export const FORGE_RELAY_PER_SOCKET = 4;
export const FORGE_HASH_RE = /^[0-9a-f]{16}$/;
export const FORGE_ENTRY_RE = /^forge:[a-z0-9]{4,8}$/;

const MOD_ID_RE = /^[a-z0-9]{4,8}$/;
const RID_RE = /^[0-9a-f]{12}$/;
const ROOM_ID_RE = /^[a-z0-9]{8,16}$/;
const CODE_RE = /^[A-Za-z0-9]{4}$/;

export function forgeHash(raw: string): string {
  const bytes = Buffer.from(raw, 'utf8');
  let a = 5381;
  let b = 0;
  for (const c of bytes) {
    a = (Math.imul(a, 33) + c) >>> 0;
    b = (Math.imul(b, 65599) + c) >>> 0;
  }
  return a.toString(16).padStart(8, '0') + b.toString(16).padStart(8, '0');
}

export interface ForgeModRef { id: string; version?: string; name?: string; author?: string; size?: number }

export function isForgeEntry(m: { id?: unknown } | null | undefined): boolean {
  return !!m && typeof m.id === 'string' && m.id.startsWith(FORGE_ROOM_PREFIX);
}

export function plainMods<T extends { id?: unknown }>(list: T[] | undefined): T[] {
  return (list ?? []).filter(m => !isForgeEntry(m));
}

export function forgeMods<T extends { id?: unknown }>(list: T[] | undefined): T[] {
  return (list ?? []).filter(m => isForgeEntry(m));
}

export function validateForgeEntry(e: Record<string, unknown>): boolean {
  if (typeof e.id !== 'string' || !FORGE_ENTRY_RE.test(e.id)) return false;
  if (typeof e.version !== 'string' || !FORGE_HASH_RE.test(e.version)) return false;
  if (e.author !== undefined && (typeof e.author !== 'string' || e.author.length > 24 || /[\x00-\x1f]/.test(e.author))) return false;
  if (e.size !== undefined && (typeof e.size !== 'number' || !Number.isInteger(e.size) || e.size < 0 || e.size > 4 * 1024 * 1024)) return false;
  return true;
}

export function validateForgeRoom(msg: Record<string, unknown>): string | null {
  const t = msg.type;
  if (t === 'forge_room_get') {
    if (typeof msg.id !== 'string' || !MOD_ID_RE.test(msg.id)) return 'forge_room_get: invalid id';
    if (typeof msg.hash !== 'string' || !FORGE_HASH_RE.test(msg.hash)) return 'forge_room_get: invalid hash';
    const room = typeof msg.room === 'string' && ROOM_ID_RE.test(msg.room);
    const code = typeof msg.code === 'string' && CODE_RE.test(msg.code);
    if (!room && !code) return 'forge_room_get: room or code required';
  }
  if (t === 'forge_room_put') {
    if (typeof msg.rid !== 'string' || !RID_RE.test(msg.rid)) return 'forge_room_put: invalid rid';
    if (msg.mod !== undefined && typeof msg.mod !== 'string') return 'forge_room_put: invalid mod';
  }
  return null;
}

export interface RelayRoom<W> { mods: ForgeModRef[]; host: W | null }

export interface RelayDeps<W> {
  findRoom: (id: string | undefined, code: string | undefined) => RelayRoom<W> | null;
  send: (ws: W, data: object) => void;
  log?: (level: string, tag: string, msg: string) => void;
  timeoutMs?: number;
}

interface Pending<W> { from: W; host: W; id: string; hash: string; timer: ReturnType<typeof setTimeout> }

export class ForgeRelay<W> {
  pending = new Map<string, Pending<W>>();
  constructor(private d: RelayDeps<W>) {}

  private fail(ws: W, id: string, reason: string): void {
    this.d.send(ws, { type: 'forge_room_mod', ok: false, id, reason });
  }

  private rid(): string {
    let r = '';
    do { r = crypto.randomUUID().replace(/-/g, '').slice(0, 12); } while (this.pending.has(r));
    return r;
  }

  get(ws: W, msg: Record<string, unknown>): void {
    const id = String(msg.id);
    const hash = String(msg.hash);
    const room = this.d.findRoom(typeof msg.room === 'string' ? msg.room : undefined, typeof msg.code === 'string' ? msg.code.toUpperCase() : undefined);
    if (!room) { this.fail(ws, id, 'room_gone'); return; }
    const entry = room.mods.find(m => m.id === FORGE_ROOM_PREFIX + id);
    if (!entry) { this.fail(ws, id, 'not_in_room'); return; }
    if (entry.version !== hash) { this.fail(ws, id, 'hash_mismatch'); return; }
    if (typeof entry.size === 'number' && entry.size > FORGE_MAX_BYTES) { this.fail(ws, id, 'too_big'); return; }
    const host = room.host;
    if (!host) { this.fail(ws, id, 'host_gone'); return; }
    if (host === ws) { this.fail(ws, id, 'own'); return; }
    let mine = 0;
    for (const p of this.pending.values()) if (p.from === ws) mine++;
    if (mine >= FORGE_RELAY_PER_SOCKET) { this.fail(ws, id, 'busy'); return; }
    const rid = this.rid();
    const timer = setTimeout(() => {
      if (!this.pending.delete(rid)) return;
      this.fail(ws, id, 'timeout');
    }, this.d.timeoutMs ?? FORGE_RELAY_MS);
    this.pending.set(rid, { from: ws, host, id, hash, timer });
    this.d.send(host, { type: 'forge_room_req', rid, id, hash });
  }

  put(ws: W, msg: Record<string, unknown>): void {
    const rid = String(msg.rid);
    const p = this.pending.get(rid);
    if (!p || p.host !== ws) return;
    this.pending.delete(rid);
    clearTimeout(p.timer);
    const raw = msg.mod;
    if (typeof raw !== 'string' || raw === '') { this.fail(p.from, p.id, 'host_refused'); return; }
    if (Buffer.byteLength(raw, 'utf8') > FORGE_MAX_BYTES) { this.fail(p.from, p.id, 'too_big'); return; }
    const c = checkMod(raw);
    if (!c.ok || c.id !== p.id) { this.fail(p.from, p.id, 'bad_mod'); return; }
    if (forgeHash(raw) !== p.hash) { this.fail(p.from, p.id, 'hash_mismatch'); return; }
    this.d.log?.('INFO', 'FORGE', `relayed room mod ${p.id} ${raw.length} bytes`);
    this.d.send(p.from, { type: 'forge_room_mod', ok: true, id: p.id, hash: p.hash, name: c.name, author: c.author, mod: raw });
  }

  drop(ws: W): void {
    for (const [rid, p] of [...this.pending]) {
      if (p.from === ws) { clearTimeout(p.timer); this.pending.delete(rid); }
      else if (p.host === ws) { clearTimeout(p.timer); this.pending.delete(rid); this.fail(p.from, p.id, 'host_gone'); }
    }
  }
}
