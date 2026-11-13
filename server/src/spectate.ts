import type { MatchLog } from './matchlog';
import { friendCode } from './social';

export const SPECTATE_TYPES = ['spectate_list', 'spectate_watch', 'spectate_leave'];

export const SPEC_CAPS = {
  perMatch: 50,
  list: 30,
  listGapMs: 1500,
};

export interface SpectateDeps<WS> {
  logs(): Iterable<MatchLog>;
  isLive(id: string): boolean;
  send(ws: WS, data: object): void;
  keyOf(ws: WS): string | undefined;
  friendKeys(pkey: string): string[];
  byRoom?(code: string): MatchLog | null;
  log?(level: string, msg: string): void;
}

interface Watch { id: string; pid: number }

export interface SpectateItem {
  id: string;
  mode: string;
  ranked: boolean;
  kind: string;
  players: object[];
  ante: number;
  started_at: number;
  friend: boolean;
  friends: string[];
  watchers: number;
  see_jokers: boolean;
}

function players(log: MatchLog): object[] {
  return log.header.players.map(p => {
    const out: Record<string, unknown> = { pid: p.pid, name: p.name, is_bot: p.is_bot };
    if (p.is_bot && p.bot_level) out.bot_level = p.bot_level;
    if (!p.is_bot && p.rank) out.rank = p.rank;
    return out;
  });
}

function publicHeader(log: MatchLog): object {
  const h = log.header;
  return { id: h.id, v: h.v, mode: h.mode, ranked: h.ranked, kind: h.kind, settings: h.settings, ruleset: h.ruleset, seeds: h.seeds, players: players(log), started_at: h.started_at };
}

function anteOf(log: MatchLog): number {
  let a = 1;
  for (const v of log.at.values()) if (typeof v.ante === 'number' && v.ante > a) a = v.ante;
  return a;
}

export function spectatable(log: MatchLog): boolean {
  return log.header.settings?.spectate !== false && !log.end && !log.header.ranked && log.header.private !== true;
}

export function seeJokers(log: MatchLog): boolean {
  return log.header.settings?.spectate_jokers !== false;
}

export class SpectateService<WS> {
  watchers = new Map<string, Set<WS>>();
  watching = new Map<WS, Watch>();
  private lastList = new Map<WS, number>();

  constructor(private deps: SpectateDeps<WS>, private now: () => number = Date.now) {}

  private find(id: string): MatchLog | null {
    for (const l of this.deps.logs()) if (l.id === id) return l;
    return null;
  }

  private mine(log: MatchLog, key: string | undefined): boolean {
    return !!key && log.pidOf(key) !== null;
  }

  list(ws: WS): SpectateItem[] {
    const key = this.deps.keyOf(ws);
    const friends = new Set(key ? this.deps.friendKeys(key) : []);
    const out: SpectateItem[] = [];
    for (const log of this.deps.logs()) {
      if (!spectatable(log) || this.mine(log, key)) continue;
      const fr = Object.entries(log.keys).filter(([, k]) => friends.has(k)).map(([, k]) => friendCode(k));
      out.push({
        id: log.id, mode: log.header.mode, ranked: log.header.ranked, kind: log.header.kind,
        players: players(log), ante: anteOf(log), started_at: log.header.started_at,
        friend: fr.length > 0, friends: fr, watchers: this.watchers.get(log.id)?.size ?? 0, see_jokers: seeJokers(log),
      });
    }
    out.sort((a, b) => Number(b.friend) - Number(a.friend) || b.ante - a.ante || a.started_at - b.started_at);
    return out.slice(0, SPEC_CAPS.list);
  }

  private fail(ws: WS, reason: string, extra: Record<string, unknown> = {}): void {
    this.deps.send(ws, { type: 'spectate_error', reason, ...extra });
  }

  watch(ws: WS, msg: Record<string, unknown>): void {
    const key = this.deps.keyOf(ws);
    let log: MatchLog | null = null;
    let pid: number | null = typeof msg.pid === 'number' && Number.isInteger(msg.pid) ? msg.pid : null;
    if (typeof msg.code === 'string' && msg.code) {
      const code = msg.code.toUpperCase();
      const friends = key ? this.deps.friendKeys(key) : [];
      const fk = friends.find(k => friendCode(k) === code);
      if (!fk) { this.fail(ws, 'not_friend', { code }); return; }
      for (const l of this.deps.logs()) {
        const p = l.pidOf(fk);
        if (p !== null && !l.end) { log = l; pid = p; break; }
      }
      if (!log) { this.fail(ws, 'not_found', { code }); return; }
    } else if (typeof msg.room === 'string' && msg.room) {
      log = this.deps.byRoom?.(msg.room.toUpperCase()) ?? null;
      if (!log || log.end) { this.fail(ws, 'not_found', { room: msg.room }); return; }
      if (pid === null && key) {
        const friends = new Set(this.deps.friendKeys(key));
        for (const [p, k] of Object.entries(log.keys)) if (friends.has(k)) { pid = Number(p); break; }
      }
    } else if (typeof msg.id === 'string') {
      log = this.find(msg.id);
      if (!log || log.end) { this.fail(ws, 'not_found', { id: msg.id }); return; }
    } else { this.fail(ws, 'not_found'); return; }
    if (this.mine(log, key)) { this.fail(ws, 'in_match', { id: log.id }); return; }
    if (log.header.ranked) { this.fail(ws, 'ranked_live', { id: log.id }); return; }
    if (!spectatable(log)) { this.fail(ws, 'private', { id: log.id }); return; }
    const set = this.watchers.get(log.id);
    const already = this.watching.get(ws)?.id === log.id;
    if (!already && set && set.size >= SPEC_CAPS.perMatch) { this.fail(ws, 'full', { id: log.id }); return; }
    this.leave(ws, true);
    const pids = log.header.players.map(p => p.pid);
    if (pid === null || !pids.includes(pid)) pid = log.header.players.find(p => !p.is_bot)?.pid ?? pids[0] ?? 0;
    let s = this.watchers.get(log.id);
    if (!s) { s = new Set(); this.watchers.set(log.id, s); }
    s.add(ws);
    this.watching.set(ws, { id: log.id, pid });
    const seqs: Record<string, number> = {};
    for (const [p, st] of log.streams) seqs[String(p)] = st.seq;
    this.deps.send(ws, {
      type: 'spectate_start', id: log.id, pid, live: true, see_jokers: seeJokers(log),
      header: publicHeader(log), streams: log.streamsRecord(), seqs,
    });
  }

  leave(ws: WS, quiet = false): void {
    const w = this.watching.get(ws);
    if (!w) return;
    this.watching.delete(ws);
    const s = this.watchers.get(w.id);
    if (s) { s.delete(ws); if (s.size === 0) this.watchers.delete(w.id); }
    if (!quiet) this.deps.send(ws, { type: 'spectate_end', id: w.id, reason: 'left' });
  }

  drop(ws: WS): void {
    this.lastList.delete(ws);
    const w = this.watching.get(ws);
    if (!w) return;
    this.watching.delete(ws);
    const s = this.watchers.get(w.id);
    if (s) { s.delete(ws); if (s.size === 0) this.watchers.delete(w.id); }
  }

  onAct(id: string, pid: number, seq: number, entries: unknown[]): void {
    const s = this.watchers.get(id);
    if (!s || s.size === 0) return;
    const msg = { type: 'spectate_act', id, pid, seq, a: entries };
    for (const ws of s) this.deps.send(ws, msg);
  }

  end(id: string, reason = 'ended'): void {
    const s = this.watchers.get(id);
    if (!s) return;
    this.watchers.delete(id);
    for (const ws of s) {
      this.watching.delete(ws);
      this.deps.send(ws, { type: 'spectate_end', id, reason });
    }
  }

  sweep(): void {
    for (const id of [...this.watchers.keys()]) if (!this.deps.isLive(id)) this.end(id, 'ended');
  }

  watcherCount(id: string): number { return this.watchers.get(id)?.size ?? 0; }

  handle(ws: WS, msg: Record<string, unknown>): boolean {
    const t = msg.type;
    if (t === 'spectate_list') {
      const at = this.now();
      const last = this.lastList.get(ws) ?? 0;
      if (at - last < SPEC_CAPS.listGapMs) { this.deps.send(ws, { type: 'spectate_list', matches: [], slow_down: true }); return true; }
      this.lastList.set(ws, at);
      this.deps.send(ws, { type: 'spectate_list', matches: this.list(ws) });
      return true;
    }
    if (t === 'spectate_watch') { this.watch(ws, msg); return true; }
    if (t === 'spectate_leave') { this.leave(ws); return true; }
    return false;
  }
}

export function validateSpectate(msg: Record<string, unknown>): string | null {
  const t = msg.type;
  if (t !== 'spectate_watch') return null;
  if (msg.id !== undefined && (typeof msg.id !== 'string' || msg.id.length > 64)) return 'spectate_watch: invalid id';
  if (msg.code !== undefined && (typeof msg.code !== 'string' || msg.code.length > 32)) return 'spectate_watch: invalid code';
  if (msg.pid !== undefined && (typeof msg.pid !== 'number' || !Number.isInteger(msg.pid) || msg.pid < 0 || msg.pid > 16)) return 'spectate_watch: invalid pid';
  if (msg.room !== undefined && (typeof msg.room !== 'string' || msg.room.length > 16)) return 'spectate_watch: invalid room';
  if (msg.id === undefined && msg.code === undefined && msg.room === undefined) return 'spectate_watch: id, code or room needed';
  return null;
}
