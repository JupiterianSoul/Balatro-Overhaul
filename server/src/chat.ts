import { randomBytes } from 'node:crypto';
import { filterText } from './filter';
import type { DmRow, PrefsRow, SocialExtra } from './social_store';

export const CHAT_TYPES = ['chat_optin', 'chat_dm_send', 'chat_dm_history', 'chat_dm_read', 'chat_lobby_send', 'chat_mute', 'chat_unmute', 'chat_mute_list', 'chat_report'];
export const CHAT_MAX_CHARS = 200;
export const CHAT_BURST = 5;
export const CHAT_WINDOW_MS = 10_000;
export const DM_KEEP = 100;
export const MIN_AGE_YEARS = 13;
export const REPORT_LIMIT = 5;
export const REPORT_WINDOW_MS = 10 * 60_000;
export const STRIKE_LIMIT = 3;
export const STRIKE_WINDOW_MS = 5 * 60_000;
export const STRIKE_MUTE_MS = 60_000;
export const LOBBY_LOG_MAX = 40;
export const LOBBY_GRACE_MS = 120_000;
export const LOBBY_IDLE_MS = 6 * 60 * 60_000;
export const LOBBY_LOGS_MAX = 500;
export const MUTES_MAX = 200;

export interface LobbySeat<WS> { pid: number; ws: WS }
export interface LobbyInfo<WS> { id: string; me: number; seats: LobbySeat<WS>[]; matchId: string | null }

export interface PlayerRef { pkey: string; code: string; name: string }

export interface ChatDirectory<WS> {
  socketsOf(pkey: string): WS[];
  keyOf(ws: WS): string | undefined;
  nameOf(pkey: string): string;
  codeOf(pkey: string): string;
  friendPkey(me: string, code: string): Promise<string | null>;
  pkeyOfCode(code: string): Promise<string | null>;
  refs(pkeys: string[]): Promise<PlayerRef[]>;
  blocked?(pkey: string, other: string): boolean;
}

export interface ChatDeps<WS> {
  send(ws: WS, data: object): void;
  lobby?(ws: WS): LobbyInfo<WS> | null;
  lobbyAlive?(id: string): boolean;
  log?(level: string, msg: string): void;
}

interface LobbyLine {
  id: string; from: string; name: string; pid: number; at: number; text: string; to: string[]; matchId: string | null;
}
interface LobbyLog { lines: LobbyLine[]; last: number; gone: number | null }

function cleanText(v: unknown): string {
  if (typeof v !== 'string') return '';
  return v.replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ').replace(/\s+/g, ' ').trim();
}

export function convKey(a: string, b: string): string {
  return a < b ? `${a}:${b}` : `${b}:${a}`;
}

export class ChatService<WS> {
  private prefs = new Map<string, PrefsRow>();
  private mutes = new Map<string, Set<string>>();
  private unread = new Map<string, Map<string, number>>();
  private rate = new Map<string, number[]>();
  private strikes = new Map<string, { times: number[]; until: number }>();
  private reports = new Map<string, number[]>();
  private convs = new Map<string, DmRow[]>();
  private convLoads = new Map<string, Promise<DmRow[]>>();
  private pruneCount = new Map<string, number>();
  private lobbyLogs = new Map<string, LobbyLog>();
  private seq = 0;

  constructor(private extra: SocialExtra, private dir: ChatDirectory<WS>, private deps: ChatDeps<WS>, private now: () => number = Date.now) {}

  private newId(prefix: string, at: number): string {
    this.seq = (this.seq + 1) % 1296;
    return `${prefix}${at.toString(36)}${this.seq.toString(36).padStart(2, '0')}${randomBytes(3).toString('hex')}`;
  }

  async load(pkey: string): Promise<void> {
    const [prefs, mutes, unread] = await Promise.all([this.extra.prefsGet(pkey), this.extra.mutesOf(pkey), this.extra.unreadAll(pkey)]);
    this.prefs.set(pkey, prefs ?? { chat_enabled: false, chat_allowed: null, rp: null });
    this.mutes.set(pkey, new Set(mutes));
    this.unread.set(pkey, unread);
  }

  release(pkey: string): void {
    this.prefs.delete(pkey);
    this.mutes.delete(pkey);
    this.unread.delete(pkey);
    this.rate.delete(pkey);
    for (const key of [...this.convs.keys()]) {
      if (!key.split(':').includes(pkey)) continue;
      const other = key.split(':').find(k => k !== pkey) ?? '';
      if (this.dir.socketsOf(other).length === 0) this.convs.delete(key);
    }
  }

  statePayload(pkey: string): object {
    const p = this.prefs.get(pkey);
    return { type: 'chat_state', enabled: !!p && p.chat_enabled && p.chat_allowed === true, allowed: p ? p.chat_allowed : null };
  }

  muted(pkey: string, other: string): boolean {
    return this.mutes.get(pkey)?.has(other) ?? false;
  }

  unreadFrom(me: string, other: string): number {
    return this.unread.get(me)?.get(other) ?? 0;
  }

  private async prefsOf(pkey: string): Promise<PrefsRow> {
    const hit = this.prefs.get(pkey);
    if (hit) return hit;
    const row = (await this.extra.prefsGet(pkey)) ?? { chat_enabled: false, chat_allowed: null, rp: null };
    return row;
  }

  private res(ws: WS, action: string, ok: boolean, reason?: string, more: Record<string, unknown> = {}): void {
    this.deps.send(ws, { type: 'chat_result', action, ok, ...(reason ? { reason } : {}), ...more });
  }

  handle(ws: WS, me: string, msg: Record<string, unknown>): void {
    const t = String(msg.type);
    this.run(ws, me, t, msg).catch(e => {
      this.deps.log?.('WARN', `${t} failed: ${String(e).slice(0, 160)}`);
      this.deps.send(ws, { type: 'social_result', action: t, ok: false, reason: 'offline' });
    });
  }

  private async run(ws: WS, me: string, t: string, msg: Record<string, unknown>): Promise<void> {
    if (!this.prefs.has(me)) await this.load(me);
    if (t === 'chat_optin') return this.optin(ws, me, msg);
    if (t === 'chat_dm_send') return this.dmSend(ws, me, msg);
    if (t === 'chat_dm_history') return this.dmHistory(ws, me, msg);
    if (t === 'chat_dm_read') return this.dmRead(ws, me, msg);
    if (t === 'chat_lobby_send') return this.lobbySend(ws, me, msg);
    if (t === 'chat_mute' || t === 'chat_unmute') return this.mute(ws, me, t === 'chat_mute', msg);
    if (t === 'chat_mute_list') return this.muteList(ws, me);
    if (t === 'chat_report') return this.report(ws, me, msg);
  }

  private optin(ws: WS, me: string, msg: Record<string, unknown>): void {
    const prefs = this.prefs.get(me) as PrefsRow;
    const state = () => this.deps.send(ws, this.statePayload(me));
    if (msg.enabled !== true) {
      prefs.chat_enabled = false;
      this.extra.prefsSetChat(me, false, prefs.chat_allowed);
      state();
      return;
    }
    if (prefs.chat_allowed === false) {
      this.res(ws, 'optin', false, 'not_allowed');
      state();
      return;
    }
    if (prefs.chat_allowed === null) {
      const year = Number(msg.birth_year);
      const thisYear = new Date(this.now()).getUTCFullYear();
      if (msg.birth_year === undefined || msg.birth_year === null) {
        this.res(ws, 'optin', false, 'age_needed');
        state();
        return;
      }
      if (!Number.isInteger(year) || year < 1900 || year > thisYear) {
        this.res(ws, 'optin', false, 'bad_year');
        state();
        return;
      }
      prefs.chat_allowed = thisYear - year >= MIN_AGE_YEARS;
    }
    prefs.chat_enabled = prefs.chat_allowed === true;
    this.extra.prefsSetChat(me, prefs.chat_enabled, prefs.chat_allowed);
    if (!prefs.chat_enabled) this.res(ws, 'optin', false, 'not_allowed');
    state();
  }

  private gate(me: string): string | null {
    const prefs = this.prefs.get(me);
    if (!prefs || prefs.chat_allowed === false) return prefs ? 'not_allowed' : 'not_opted_in';
    if (!prefs.chat_enabled || prefs.chat_allowed !== true) return 'not_opted_in';
    return null;
  }

  private spend(me: string): string | null {
    const t = this.now();
    const strike = this.strikes.get(me);
    if (strike && strike.until > t) return 'muted';
    const times = (this.rate.get(me) ?? []).filter(x => t - x < CHAT_WINDOW_MS);
    if (times.length >= CHAT_BURST) { this.rate.set(me, times); return 'rate_limited'; }
    times.push(t);
    this.rate.set(me, times);
    return null;
  }

  private strike(me: string): void {
    const t = this.now();
    const s = this.strikes.get(me) ?? { times: [], until: 0 };
    s.times = s.times.filter(x => t - x < STRIKE_WINDOW_MS);
    s.times.push(t);
    if (s.times.length >= STRIKE_LIMIT) { s.until = t + STRIKE_MUTE_MS; s.times = []; }
    this.strikes.set(me, s);
  }

  private prepare(me: string, raw: unknown): { text: string } | { reason: string } {
    const gate = this.gate(me);
    if (gate) return { reason: gate };
    const text = cleanText(raw);
    if (text === '') return { reason: 'empty' };
    if (Array.from(text).length > CHAT_MAX_CHARS) return { reason: 'too_long' };
    const spent = this.spend(me);
    if (spent) return { reason: spent };
    const f = filterText(text);
    if (f.action === 'blocked') {
      this.strike(me);
      this.deps.log?.('INFO', `chat message blocked (${f.reasons.join(',')}) from ${me.slice(0, 6)}`);
      return { reason: 'blocked' };
    }
    return { text: f.text };
  }

  private async conv(key: string): Promise<DmRow[]> {
    const hit = this.convs.get(key);
    if (hit) return hit;
    const pending = this.convLoads.get(key);
    if (pending) return pending;
    const p = this.extra.dmHistory(key, null, DM_KEEP).then(rows => {
      const existing = this.convs.get(key);
      if (existing) return existing;
      const list = rows.slice().reverse();
      this.convs.set(key, list);
      return list;
    }).finally(() => { this.convLoads.delete(key); });
    this.convLoads.set(key, p);
    return p;
  }

  private async dmSend(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const code = typeof msg.to === 'string' ? msg.to.toUpperCase() : '';
    const more = { scope: 'dm', to: code };
    const prepared = this.prepare(me, msg.text);
    if ('reason' in prepared) { this.res(ws, 'send', false, prepared.reason, more); return; }
    const other = await this.dir.friendPkey(me, code);
    if (!other) { this.res(ws, 'send', false, 'not_friend', more); return; }
    if (this.mutes.get(me)?.has(other)) { this.res(ws, 'send', false, 'muted', more); return; }
    const theirs = await this.prefsOf(other);
    if (!theirs.chat_enabled || theirs.chat_allowed !== true) { this.res(ws, 'send', false, 'recipient_off', more); return; }
    const at = this.now();
    const row: DmRow = { id: this.newId('d', at), conv: convKey(me, other), sender: me, at, text: prepared.text };
    const list = await this.conv(row.conv);
    list.push(row);
    while (list.length > DM_KEEP) list.shift();
    this.extra.dmAdd(row);
    const sent = (this.pruneCount.get(row.conv) ?? 0) + 1;
    if (sent >= 20) { this.extra.dmPrune(row.conv, DM_KEEP); this.pruneCount.set(row.conv, 0); } else this.pruneCount.set(row.conv, sent);
    const payload = { type: 'chat_dm', id: row.id, from: this.dir.codeOf(me), to: this.dir.codeOf(other), at, text: row.text };
    for (const s of this.dir.socketsOf(me)) this.deps.send(s, payload);
    let deliver = true;
    const theirMutes = this.mutes.get(other);
    if (theirMutes?.has(me)) deliver = false;
    if (!deliver) return;
    const counts = this.unread.get(other);
    if (counts) counts.set(me, (counts.get(me) ?? 0) + 1);
    this.extra.unreadBump(other, me);
    for (const s of this.dir.socketsOf(other)) this.deps.send(s, payload);
  }

  private async dmHistory(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const code = typeof msg.with === 'string' ? msg.with.toUpperCase() : '';
    const other = await this.dir.pkeyOfCode(code);
    if (!other || other === me) { this.res(ws, 'history', false, 'unknown_player', { with: code }); return; }
    const before = typeof msg.before === 'number' && Number.isFinite(msg.before) ? msg.before : null;
    const list = await this.conv(convKey(me, other));
    const mine = this.mutes.get(me);
    const items = list
      .filter(d => (before === null || d.at < before) && !(d.sender !== me && mine?.has(d.sender)))
      .slice(-DM_KEEP)
      .map(d => ({ id: d.id, from: this.dir.codeOf(d.sender), at: d.at, text: d.text }));
    this.deps.send(ws, { type: 'chat_dm_history', with: code, items });
  }

  private async dmRead(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const code = typeof msg.with === 'string' ? msg.with.toUpperCase() : '';
    const other = await this.dir.pkeyOfCode(code);
    if (!other) { this.res(ws, 'read', false, 'unknown_player', { with: code }); return; }
    const counts = this.unread.get(me);
    const had = counts?.get(other) ?? 0;
    counts?.delete(other);
    this.extra.unreadClear(me, other);
    this.res(ws, 'read', true, undefined, { with: code, cleared: had });
  }

  private lobbyLog(id: string): LobbyLog {
    let log = this.lobbyLogs.get(id);
    if (!log) {
      log = { lines: [], last: this.now(), gone: null };
      this.lobbyLogs.set(id, log);
      if (this.lobbyLogs.size > LOBBY_LOGS_MAX) {
        const oldest = [...this.lobbyLogs.entries()].sort((a, b) => a[1].last - b[1].last)[0];
        if (oldest) this.lobbyLogs.delete(oldest[0]);
      }
    }
    return log;
  }

  botLine(ws: WS, name: string, text: string): number {
    const lobby = this.deps.lobby?.(ws) ?? null;
    if (!lobby || !name || !text) return 0;
    const at = this.now();
    const payload = { type: 'chat_lobby', id: this.newId('b', at), pid: lobby.me, name, at, text, bot: true };
    let sent = 0;
    for (const seat of lobby.seats) {
      if (seat.ws === ws) continue;
      const pk = this.dir.keyOf(seat.ws);
      if (!pk) continue;
      const p = this.prefs.get(pk);
      if (!p || !p.chat_enabled || p.chat_allowed !== true) continue;
      this.deps.send(seat.ws, payload);
      sent++;
    }
    return sent;
  }

  private async lobbySend(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const lobby = this.deps.lobby?.(ws) ?? null;
    const more = { scope: 'lobby' };
    if (!lobby) {
      const gate = this.gate(me);
      this.res(ws, 'send', false, gate ?? 'no_lobby', more);
      return;
    }
    const prepared = this.prepare(me, msg.text);
    if ('reason' in prepared) { this.res(ws, 'send', false, prepared.reason, more); return; }
    const at = this.now();
    const line: LobbyLine = {
      id: this.newId('l', at), from: me, name: this.dir.nameOf(me), pid: lobby.me, at, text: prepared.text, to: [], matchId: lobby.matchId,
    };
    const payload = { type: 'chat_lobby', id: line.id, pid: line.pid, name: line.name, at, text: line.text };
    for (const seat of lobby.seats) {
      const pk = this.dir.keyOf(seat.ws);
      if (!pk) continue;
      if (pk !== me) {
        const p = this.prefs.get(pk);
        if (!p || !p.chat_enabled || p.chat_allowed !== true) continue;
        if (this.mutes.get(pk)?.has(me) || this.dir.blocked?.(pk, me)) continue;
      }
      this.deps.send(seat.ws, payload);
      if (!line.to.includes(pk)) line.to.push(pk);
    }
    const log = this.lobbyLog(lobby.id);
    log.lines.push(line);
    while (log.lines.length > LOBBY_LOG_MAX) log.lines.shift();
    log.last = at;
    log.gone = null;
  }

  private async targetOf(ws: WS, me: string, msg: Record<string, unknown>): Promise<string | null> {
    if (typeof msg.code === 'string') return this.dir.pkeyOfCode(msg.code.toUpperCase());
    if (typeof msg.pid === 'number' && Number.isInteger(msg.pid)) {
      const lobby = this.deps.lobby?.(ws);
      const seat = lobby?.seats.find(s => s.pid === msg.pid);
      return seat ? this.dir.keyOf(seat.ws) ?? null : null;
    }
    return null;
  }

  private async mute(ws: WS, me: string, on: boolean, msg: Record<string, unknown>): Promise<void> {
    const action = on ? 'mute' : 'unmute';
    const target = await this.targetOf(ws, me, msg);
    if (!target) { this.res(ws, action, false, 'unknown_player'); return; }
    if (target === me) { this.res(ws, action, false, 'self'); return; }
    const set = this.mutes.get(me) as Set<string>;
    if (on) {
      if (!set.has(target) && set.size >= MUTES_MAX) { this.res(ws, action, false, 'full'); return; }
      set.add(target);
      this.extra.muteAdd(me, target, this.now());
    } else {
      set.delete(target);
      this.extra.muteRemove(me, target);
    }
    this.res(ws, action, true, undefined, { code: this.dir.codeOf(target) });
  }

  private async muteList(ws: WS, me: string): Promise<void> {
    const refs = await this.dir.refs([...(this.mutes.get(me) ?? [])]);
    this.deps.send(ws, { type: 'chat_mute_list', items: refs.map(r => ({ code: r.code, name: r.name })) });
  }

  private async report(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const msgId = typeof msg.msg_id === 'string' && msg.msg_id.length > 0 && msg.msg_id.length <= 64 ? msg.msg_id : null;
    const reason = cleanText(msg.reason).slice(0, 100);
    if (!msgId || !reason) { this.res(ws, 'report', false, 'bad_request'); return; }
    const t = this.now();
    const times = (this.reports.get(me) ?? []).filter(x => t - x < REPORT_WINDOW_MS);
    if (times.length >= REPORT_LIMIT) { this.reports.set(me, times); this.res(ws, 'report', false, 'rate_limited'); return; }
    times.push(t);
    this.reports.set(me, times);
    const current = this.deps.lobby?.(ws) ?? null;
    let found: { reported: string; kind: 'dm' | 'lobby'; text: string; context: object[]; matchId: string | null } | null = null;
    for (const log of this.lobbyLogs.values()) {
      const idx = log.lines.findIndex(l => l.id === msgId);
      if (idx < 0) continue;
      const line = log.lines[idx];
      if (line.from === me || !line.to.includes(me)) continue;
      found = {
        reported: line.from, kind: 'lobby', text: line.text, matchId: line.matchId ?? current?.matchId ?? null,
        context: log.lines.slice(Math.max(0, idx - 6), idx).map(l => ({ who: l.name, at: l.at, text: l.text })),
      };
      break;
    }
    if (!found) {
      const row = await this.extra.dmGet(msgId) ?? [...this.convs.values()].flat().find(d => d.id === msgId) ?? null;
      if (row && row.sender !== me && row.conv.split(':').includes(me)) {
        const list = await this.conv(row.conv);
        const idx = list.findIndex(d => d.id === row.id);
        found = {
          reported: row.sender, kind: 'dm', text: row.text, matchId: null,
          context: list.slice(Math.max(0, idx - 5), Math.max(0, idx)).map(d => ({ who: this.dir.codeOf(d.sender), at: d.at, text: d.text })),
        };
      }
    }
    if (!found) { this.res(ws, 'report', false, 'unknown_message'); return; }
    this.extra.reportAdd({
      id: `${me}:${msgId}`, reporter: me, reported: found.reported, kind: found.kind, msg_id: msgId, text: found.text,
      context: JSON.stringify(found.context), reason, match_id: found.matchId, at: t,
    });
    this.res(ws, 'report', true);
  }

  tick(): void {
    const t = this.now();
    for (const [id, log] of this.lobbyLogs) {
      const alive = this.deps.lobbyAlive ? this.deps.lobbyAlive(id) : t - log.last < LOBBY_IDLE_MS;
      if (alive) { log.gone = null; if (t - log.last > LOBBY_IDLE_MS) this.lobbyLogs.delete(id); continue; }
      if (log.gone === null) log.gone = t;
      else if (t - log.gone > LOBBY_GRACE_MS) this.lobbyLogs.delete(id);
    }
    for (const [k, v] of this.rate) if (!v.some(x => t - x < CHAT_WINDOW_MS)) this.rate.delete(k);
    for (const [k, v] of this.strikes) if (v.until < t && !v.times.some(x => t - x < STRIKE_WINDOW_MS)) this.strikes.delete(k);
    for (const [k, v] of this.reports) if (!v.some(x => t - x < REPORT_WINDOW_MS)) this.reports.delete(k);
  }

  lobbyLogCount(): number {
    return this.lobbyLogs.size;
  }
}
