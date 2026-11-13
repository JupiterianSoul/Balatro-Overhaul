import { randomBytes } from 'node:crypto';
import type { NotifyRow, SocialExtra } from './social_store';

export const NOTIFY_TYPES = ['notify_list', 'notify_read', 'notify_clear'];
export const NOTIFY_KINDS = ['friend_request', 'friend_accepted', 'invite', 'game_info', 'match_voided', 'match_contested', 'error', 'friend_activity', 'gift'] as const;
export type NotifyKind = typeof NOTIFY_KINDS[number];
export const NOTIFY_MAX = 100;
export const INVITE_TTL_MS = 15 * 60_000;
export const DECISION_TARGETS_MAX = 16;
export const DECISION_ID_MAX = 60;

export interface NotifyItem { id: string; kind: NotifyKind; at: number; read: boolean; data: Record<string, unknown> }

export interface NotifyDirectory<WS> {
  socketsOf(pkey: string): WS[];
}

export interface NotifyDeps<WS> {
  send(ws: WS, data: object): void;
  log?(level: string, msg: string): void;
}

const KEY_RE = /^[a-z_]{1,24}$/;
const DATA_MAX = 1200;

const DECISIONS = new Map<string, 'contested' | 'voided' | 'applied'>([['held', 'contested'], ['voided', 'voided'], ['applied', 'applied']]);

function scalar(v: unknown): string | number | boolean | null | undefined {
  if (typeof v === 'string') return v.slice(0, 200);
  if (typeof v === 'number') return Number.isFinite(v) ? v : undefined;
  if (typeof v === 'boolean' || v === null) return v;
  return undefined;
}

export function cleanData(data: unknown): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  if (!data || typeof data !== 'object' || Array.isArray(data)) return out;
  let n = 0;
  for (const [k, v] of Object.entries(data as Record<string, unknown>)) {
    if (!KEY_RE.test(k) || n >= 16) continue;
    const s = scalar(v);
    if (s !== undefined) { out[k] = s; n++; continue; }
    if (Array.isArray(v)) {
      out[k] = v.slice(0, 12).map(scalar).filter(x => x !== undefined);
      n++;
    } else if (v && typeof v === 'object') {
      const inner: Record<string, unknown> = {};
      for (const [ik, iv] of Object.entries(v as Record<string, unknown>).slice(0, 12)) {
        const is = scalar(iv);
        if (KEY_RE.test(ik) && is !== undefined) inner[ik] = is;
      }
      out[k] = inner;
      n++;
    }
  }
  while (JSON.stringify(out).length > DATA_MAX) {
    const keys = Object.keys(out);
    if (keys.length === 0) break;
    delete out[keys[keys.length - 1]];
  }
  return out;
}

function toItem(r: NotifyRow): NotifyItem {
  return { id: r.id, kind: r.kind as NotifyKind, at: r.at, read: r.read, data: r.data };
}

interface DecisionSink { matchDecision(matchId: string, status: string, pkeys: string[]): Promise<void> }

let bound: DecisionSink | null = null;

export function notifyMatchDecision(matchId: string, status: string, pkeys: string[]): Promise<void> {
  if (!bound) return Promise.resolve();
  try {
    return bound.matchDecision(matchId, status, pkeys).catch(() => undefined);
  } catch {
    return Promise.resolve();
  }
}

export class NotifyService<WS> {
  private cache = new Map<string, NotifyRow[]>();
  private loading = new Map<string, Promise<NotifyRow[]>>();

  constructor(private extra: SocialExtra, private dir: NotifyDirectory<WS>, private deps: NotifyDeps<WS>, private now: () => number = Date.now) {
    bound = this;
  }

  private newId(at: number): string {
    return `n${at.toString(36)}${randomBytes(4).toString('hex')}`;
  }

  private live(r: NotifyRow, t: number): boolean {
    return r.expires === null || r.expires > t;
  }

  items(pkey: string): Promise<NotifyRow[]> {
    const hit = this.cache.get(pkey);
    if (hit) return Promise.resolve(hit);
    const pending = this.loading.get(pkey);
    if (pending) return pending;
    const p = this.extra.notifyList(pkey).then(rows => {
      const current = this.cache.get(pkey);
      if (current) return current;
      const t = this.now();
      const keep: NotifyRow[] = [];
      for (const r of rows) {
        if (this.live(r, t)) keep.push(r); else this.extra.notifyDelete(pkey, r.id);
      }
      keep.sort((a, b) => b.at - a.at);
      for (const r of keep.slice(NOTIFY_MAX)) this.extra.notifyDelete(pkey, r.id);
      const list = keep.slice(0, NOTIFY_MAX);
      this.cache.set(pkey, list);
      return list;
    }).finally(() => { this.loading.delete(pkey); });
    this.loading.set(pkey, p);
    return p;
  }

  release(pkey: string): void {
    this.cache.delete(pkey);
  }

  private unread(list: NotifyRow[]): number {
    const t = this.now();
    return list.filter(r => !r.read && this.live(r, t)).length;
  }

  private sweep(pkey: string, list: NotifyRow[]): void {
    const t = this.now();
    for (let i = list.length - 1; i >= 0; i--) {
      if (this.live(list[i], t)) continue;
      this.extra.notifyDelete(pkey, list[i].id);
      list.splice(i, 1);
    }
  }

  async payload(pkey: string): Promise<object> {
    const list = await this.items(pkey);
    this.sweep(pkey, list);
    return { type: 'notify_list', items: list.map(toItem), unread: this.unread(list) };
  }

  async sendList(pkey: string): Promise<void> {
    const p = await this.payload(pkey);
    for (const ws of this.dir.socketsOf(pkey)) this.deps.send(ws, p);
  }

  async push(pkey: string, kind: NotifyKind, data: Record<string, unknown> = {}, id?: string): Promise<NotifyItem | null> {
    if (!NOTIFY_KINDS.includes(kind)) return null;
    const at = this.now();
    const row: NotifyRow = {
      id: id ?? this.newId(at), pkey, kind, at, read: false, data: cleanData(data),
      expires: kind === 'invite' ? at + INVITE_TTL_MS : null,
    };
    this.extra.notifyAdd(row);
    const socks = this.dir.socketsOf(pkey);
    if (socks.length === 0 && !this.cache.has(pkey)) return toItem(row);
    const list = await this.items(pkey);
    const same = list.findIndex(r => r.id === row.id);
    if (same >= 0) list.splice(same, 1);
    list.unshift(row);
    while (list.length > NOTIFY_MAX) {
      let idx = -1;
      for (let i = list.length - 1; i >= 0; i--) if (list[i].read) { idx = i; break; }
      const drop = list.splice(idx >= 0 ? idx : list.length - 1, 1)[0];
      this.extra.notifyDelete(pkey, drop.id);
    }
    const payload = { type: 'notify_new', item: toItem(row), unread: this.unread(list) };
    for (const ws of socks) this.deps.send(ws, payload);
    return toItem(row);
  }

  async remove(pkey: string, ids: string[]): Promise<void> {
    for (const id of ids) this.extra.notifyDelete(pkey, id);
    const socks = this.dir.socketsOf(pkey);
    if (socks.length === 0 && !this.cache.has(pkey)) return;
    const list = await this.items(pkey);
    let changed = false;
    for (const id of ids) {
      const i = list.findIndex(r => r.id === id);
      if (i >= 0) { list.splice(i, 1); changed = true; }
    }
    if (changed) await this.sendList(pkey);
  }

  async matchDecision(matchId: string, status: string, pkeys: string[]): Promise<void> {
    const id = typeof matchId === 'string' ? matchId.trim() : '';
    const verdict = typeof status === 'string' ? DECISIONS.get(status) : undefined;
    if (id === '' || id.length > DECISION_ID_MAX || !verdict || !Array.isArray(pkeys)) return;
    const targets = [...new Set(pkeys.filter((p): p is string => typeof p === 'string' && p !== ''))].slice(0, DECISION_TARGETS_MAX);
    await Promise.all(targets.map(async pkey => {
      try {
        if (verdict === 'contested') {
          await this.push(pkey, 'match_contested', { match_id: id }, `mc:${id}`);
          return;
        }
        await this.remove(pkey, [`mc:${id}`]).catch(e => this.warn(`match notice cleanup failed: ${String(e).slice(0, 120)}`));
        if (verdict === 'applied') return;
        await this.push(pkey, 'match_voided', { match_id: id }, `mv:${id}`);
      } catch (e) {
        this.warn(`match notice failed: ${String(e).slice(0, 120)}`);
      }
    }));
  }

  private warn(msg: string): void {
    try { this.deps.log?.('WARN', msg); } catch { return; }
  }

  handle(ws: WS, pkey: string, msg: Record<string, unknown>): void {
    const t = String(msg.type);
    this.run(ws, t, pkey, msg).catch(e => {
      this.deps.log?.('WARN', `${t} failed: ${String(e).slice(0, 160)}`);
      this.deps.send(ws, { type: 'social_result', action: t, ok: false, reason: 'offline' });
    });
  }

  private async run(ws: WS, t: string, pkey: string, msg: Record<string, unknown>): Promise<void> {
    if (t === 'notify_list') { this.deps.send(ws, await this.payload(pkey)); return; }
    const all = msg.all === true;
    const id = typeof msg.id === 'string' && msg.id.length > 0 && msg.id.length <= 64 ? msg.id : null;
    if (!all && id === null) { this.deps.send(ws, { type: 'social_result', action: t, ok: false, reason: 'bad_request' }); return; }
    const list = await this.items(pkey);
    if (t === 'notify_read') {
      for (const r of list) if (all || r.id === id) r.read = true;
      this.extra.notifyRead(pkey, all ? null : id);
    } else {
      if (all) list.length = 0;
      else {
        const i = list.findIndex(r => r.id === id);
        if (i >= 0) list.splice(i, 1);
      }
      this.extra.notifyDelete(pkey, all ? null : id);
    }
    await this.sendList(pkey);
  }
}
