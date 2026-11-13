import { createHash } from 'node:crypto';
import type { RankedStore, SocialPlayerRow } from './ranked_store';
import { rankTag, type RankTag } from './identity';
import { devMark } from './dev';
import { ChatService, CHAT_TYPES, type LobbyInfo, type PlayerRef } from './chat';
import { NotifyService, NOTIFY_TYPES } from './notify';
import { socialExtraFor, type SocialExtra } from './social_store';
import { FriendScores, SCORE_TYPES, scoreStoreFor } from './friend_scores';
import { RecentPlayers, RECENT_TYPES, recentStoreFor, type MetSeat, type RecentLink, type ResultSeat } from './recent_players';
import { FriendsMore, MORE_TYPES, blockStoreFor } from './friends_more';

export const EMOTE_COUNT = 6;
export const EMOTE_GAP_MS = 2000;
export const EMOTE_IDS = ['hi', 'laugh', 'cry', 'nope', 'chips', 'fire', 'money', 'gg', 'think', 'lucky', 'oops', 'hurry'] as const;
export const EMOTE_FROM_LEGACY = ['lucky', 'gg', 'fire', 'oops', 'gg', 'hurry'] as const;
export const EMOTE_TO_LEGACY: Record<string, number> = { hi: 1, lucky: 1, gg: 2, laugh: 3, chips: 3, fire: 3, money: 3, cry: 4, oops: 4, hurry: 6 };
export const INVITE_GAP_MS = 3000;
export const INVITE_MANY_MAX = 7;
export const ADD_PER_MIN = 10;
export const MAX_FRIENDS = 100;
export const SEARCH_MIN = 2;
export const SEARCH_MAX = 32;
export const SEARCH_LIMIT = 20;
export const SEARCH_PER_WINDOW = 10;
export const SEARCH_WINDOW_MS = 10_000;
export const PRESENCE_GAP_MS = 2000;
export const PRESENCE_TICK_MS = 3000;
export const SOCIAL_TYPES = [
  'social_hello', 'social_list', 'social_add', 'social_accept', 'social_remove', 'social_invite', 'social_emote',
  'social_search', 'social_status', ...CHAT_TYPES, ...NOTIFY_TYPES, ...SCORE_TYPES, ...RECENT_TYPES, ...MORE_TYPES,
];

const CHAT_SET = new Set(CHAT_TYPES);
const NOTIFY_SET = new Set(NOTIFY_TYPES);
const SCORE_SET = new Set(SCORE_TYPES);
const RECENT_SET = new Set(RECENT_TYPES);
const MORE_SET = new Set(MORE_TYPES);
export const ACTIVITY_GAP_MS = 60_000;
const PKEY_RE = /^[A-Za-z0-9]{24}$/;
const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_RE = /^[A-Z2-9]{4}-[A-Z2-9]{4}$/;
const MINUTE_MS = 60_000;

export function friendCode(pkey: string): string {
  const hash = createHash('sha256').update(`balatro-overhaul-friend:${pkey}`).digest();
  let out = '';
  for (let i = 0; i < 8; i++) {
    if (i === 4) out += '-';
    out += CODE_ALPHABET[hash[i] % CODE_ALPHABET.length];
  }
  return out;
}

export function cleanFriendCode(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const s = v.toUpperCase().replace(/[^A-Z0-9]/g, '');
  if (s.length !== 8) return null;
  const code = `${s.slice(0, 4)}-${s.slice(4)}`;
  return CODE_RE.test(code) ? code : null;
}

export function searchKey(name: string): string {
  return name.normalize('NFKD').replace(/\p{M}/gu, '').replace(/[​-‏⁠﻿­]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();
}

export interface SocialSocket {
  data: {
    socialKey?: string; socialEmoteAt?: number; socialInviteAt?: number; socialAdds?: number[];
    socialWhere?: string; socialSearchAt?: number[]; rp?: unknown; bot?: boolean; name?: string;
    mgBestAt?: number[]; mgBoardAt?: number; recentAt?: number; typingAt?: number; askAt?: number; blockAt?: number[];
  };
}

export interface InviteTarget { code: string; party: boolean }

export type Where = 'offline' | 'menu' | 'browsing' | 'solo' | 'lobby' | 'match' | 'spectating';
export interface Status { where: Where; mode?: string; ante?: number; opponents?: string[]; room?: string }
export interface PresenceDetail { where: 'menu' | 'lobby' | 'match'; mode?: string; ante?: number; opponents?: string[]; room?: string }

export interface SocialDeps<WS extends SocialSocket> {
  send(ws: WS, data: object): void;
  where(ws: WS): 'menu' | 'lobby' | 'match';
  inviteTarget(ws: WS): InviteTarget | null;
  roomPeers(ws: WS): WS[];
  detail?(ws: WS): PresenceDetail | null;
  lobby?(ws: WS): LobbyInfo<WS> | null;
  lobbyAlive?(id: string): boolean;
  log?(level: string, msg: string): void;
}

interface Link { other: SocialPlayerRow; status: 'pending' | 'incoming' | 'accepted' }

const PRIORITY: Record<Where, number> = { offline: 0, menu: 1, browsing: 2, solo: 2, spectating: 3, lobby: 4, match: 5 };

function legacyWhere(s: Status): 'offline' | 'menu' | 'lobby' | 'match' {
  return s.where === 'browsing' || s.where === 'spectating' || s.where === 'solo' ? 'menu' : s.where;
}

function numericRp(v: unknown): number | null {
  return typeof v === 'number' && Number.isFinite(v) ? v : null;
}

function matchScore(nameKey: string, q: string): number {
  if (nameKey === q) return 100;
  if (nameKey.startsWith(q)) return 80;
  if (nameKey.split(/[^\p{L}\p{N}]+/u).some(w => w.startsWith(q))) return 60;
  return 40;
}

export class SocialService<WS extends SocialSocket> {
  private online = new Map<string, Set<WS>>();
  private names = new Map<string, string>();
  private links = new Map<string, Map<string, Link>>();
  private rps = new Map<string, number>();
  private sigs = new Map<string, string>();
  private pushedAt = new Map<string, number>();
  private dirty = new Set<string>();
  private ready: Promise<void> | null = null;
  private hidden = new Set<string>();
  private activityAt = new Map<string, number>();
  private timer: ReturnType<typeof setInterval> | null = null;
  readonly extra: SocialExtra;
  readonly chat: ChatService<WS>;
  readonly notify: NotifyService<WS>;
  readonly scores: FriendScores<WS>;
  readonly recent: RecentPlayers<WS>;
  readonly more: FriendsMore<WS>;

  constructor(private store: RankedStore, private deps: SocialDeps<WS>, private now: () => number = Date.now, extra?: SocialExtra) {
    this.extra = extra ?? socialExtraFor(store);
    this.notify = new NotifyService<WS>(this.extra, { socketsOf: k => this.socketsOf(k) }, { send: (ws, d) => deps.send(ws, d), log: deps.log }, now);
    this.chat = new ChatService<WS>(this.extra, {
      socketsOf: k => this.socketsOf(k),
      keyOf: ws => ws.data.socialKey,
      nameOf: k => this.names.get(k) ?? '',
      codeOf: k => friendCode(k),
      friendPkey: (me, code) => this.friendPkey(me, code),
      pkeyOfCode: code => this.pkeyOfCode(code),
      refs: keys => this.refs(keys),
      blocked: (k, other) => this.more.blockedNow(k, other),
    }, { send: (ws, d) => deps.send(ws, d), lobby: ws => deps.lobby?.(ws) ?? null, lobbyAlive: deps.lobbyAlive, log: deps.log }, now);
    this.scores = new FriendScores<WS>(scoreStoreFor(store), {
      send: (ws, d) => deps.send(ws, d),
      friends: async k => { await this.linksOf(k); return this.refs(this.friendKeys(k)); },
      me: k => ({ pkey: k, code: friendCode(k), name: this.names.get(k) ?? '' }),
      onBest: (k, game, score) => this.activity(k, 'mg_best', { game, score }, `mg_best:${game}`),
      log: deps.log,
    }, now);
    this.recent = new RecentPlayers<WS>(recentStoreFor(store), {
      send: (ws, d) => deps.send(ws, d),
      describe: (me, others) => this.describe(me, others),
      friends: async k => { await this.linksOf(k); return this.friendKeys(k).map(p => ({ pkey: p, code: friendCode(p) })); },
      log: deps.log,
    }, now);
    this.more = new FriendsMore<WS>(blockStoreFor(store), {
      send: (ws, d) => deps.send(ws, d),
      socketsOf: k => this.socketsOf(k),
      nameOf: k => this.names.get(k) ?? '',
      codeOf: k => friendCode(k),
      friendPkey: (me, code) => this.friendPkey(me, code),
      playerOf: async code => { const c = cleanFriendCode(code); const r = c ? await this.playerByCode(c) : null; return r ? { pkey: r.pkey, name: this.names.get(r.pkey) ?? r.name } : null; },
      inLobby: k => this.statusOf(k).where === 'lobby',
      inviteTarget: ws => deps.inviteTarget(ws),
      muted: (k, other) => this.chat.muted(k, other),
      unfriend: (me, other) => this.unfriend(me, other),
      setHidden: (k, on) => this.setHidden(k, on),
      gift: async (to, data, id) => (await this.notify.push(to, 'gift', data, id)) !== null,
      log: deps.log,
    }, now);
  }

  ensure(): Promise<void> {
    if (!this.ready) {
      this.ready = this.store.socialInit().then(() => this.extra.init()).catch(e => {
        this.ready = null;
        this.deps.log?.('WARN', `social tables not ready: ${String(e).slice(0, 160)}`);
        throw e;
      });
    }
    return this.ready;
  }

  start(): void {
    if (this.timer) return;
    this.timer = setInterval(() => this.tick(), PRESENCE_TICK_MS);
    (this.timer as { unref?: () => void }).unref?.();
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }

  tick(): void {
    const t = this.now();
    for (const pkey of this.online.keys()) this.pushPresence(pkey, false);
    for (const pkey of [...this.dirty]) if (!this.online.has(pkey)) this.dirty.delete(pkey);
    for (const [pkey, at] of this.pushedAt) {
      if (t - at > 60_000 && !this.online.has(pkey)) { this.pushedAt.delete(pkey); this.sigs.delete(pkey); }
    }
    this.chat.tick();
  }

  async currentName(pkey: string): Promise<string | null> {
    const live = this.names.get(pkey);
    if (live) return live;
    const rows = await this.extra.players([pkey]);
    const n = rows.find(r => r.pkey === pkey)?.name;
    return n ? n : null;
  }

  socketsOf(pkey: string): WS[] {
    return [...(this.online.get(pkey) ?? [])];
  }

  isOnline(pkey: string): boolean {
    return (this.online.get(pkey)?.size ?? 0) > 0;
  }

  private shown(pkey: string): boolean {
    return this.isOnline(pkey) && !this.hidden.has(pkey);
  }

  isHidden(pkey: string): boolean {
    return this.hidden.has(pkey);
  }

  private setHidden(pkey: string, on: boolean): void {
    if (on === this.hidden.has(pkey)) return;
    if (on) this.hidden.add(pkey); else this.hidden.delete(pkey);
    if (this.isOnline(pkey)) this.pushPresence(pkey, true);
  }

  async friendsOf(pkey: string): Promise<string[]> {
    await this.ensure();
    await this.linksOf(pkey);
    return this.friendKeys(pkey);
  }

  activity(pkey: string | undefined, what: string, data: Record<string, unknown>, tag = what): void {
    if (!pkey || !this.isOnline(pkey)) return;
    const t = this.now();
    const key = `${pkey}|${tag}`;
    if (t - (this.activityAt.get(key) ?? 0) < ACTIVITY_GAP_MS) return;
    this.activityAt.set(key, t);
    if (this.activityAt.size > 5000) for (const [k, at] of this.activityAt) if (t - at > ACTIVITY_GAP_MS) this.activityAt.delete(k);
    const code = friendCode(pkey);
    const name = this.names.get(pkey) ?? '';
    this.quiet(this.ensure().then(async () => {
      await this.linksOf(pkey);
      for (const f of this.friendKeys(pkey)) {
        await this.notify.push(f, 'friend_activity', { from: code, name, what, ...data }, `act:${code}:${tag}`);
      }
    }));
  }

  private async unfriend(me: string, other: string): Promise<void> {
    const mine = await this.linksOf(me);
    await this.linksOf(other);
    const otherCode = friendCode(other);
    const myCode = friendCode(me);
    if (mine.has(other)) {
      this.dropLink(me, other);
      this.dropLink(other, me);
    }
    this.quiet(this.notify.remove(me, [`fr:${otherCode}`, `fa:${otherCode}`, `inv:${otherCode}`]));
    this.quiet(this.notify.remove(other, [`fr:${myCode}`, `fa:${myCode}`, `inv:${myCode}`]));
    await this.pushList(me);
    await this.pushList(other);
  }

  friendKeys(pkey: string): string[] {
    const out: string[] = [];
    for (const l of this.links.get(pkey)?.values() ?? []) if (l.status === 'accepted') out.push(l.other.pkey);
    return out;
  }

  private async friendPkey(me: string, code: string): Promise<string | null> {
    const clean = cleanFriendCode(code);
    if (!clean) return null;
    for (const l of (await this.linksOf(me)).values()) if (l.status === 'accepted' && l.other.code === clean) return l.other.pkey;
    return null;
  }

  private async pkeyOfCode(code: string): Promise<string | null> {
    const clean = cleanFriendCode(code);
    if (!clean) return null;
    return (await this.playerByCode(clean))?.pkey ?? null;
  }

  private async refs(pkeys: string[]): Promise<PlayerRef[]> {
    const out: PlayerRef[] = [];
    const missing: string[] = [];
    for (const k of pkeys) {
      const name = this.names.get(k);
      if (name !== undefined && this.online.has(k)) out.push({ pkey: k, code: friendCode(k), name }); else missing.push(k);
    }
    if (missing.length > 0) for (const r of await this.extra.players(missing)) out.push(r);
    return out;
  }

  private async describe(me: string, others: string[]): Promise<Map<string, RecentLink>> {
    const mine = await this.linksOf(me);
    const out = new Map<string, RecentLink>();
    for (const r of await this.refs(others)) {
      const link = mine.get(r.pkey);
      out.set(r.pkey, {
        code: r.code, name: this.names.get(r.pkey) ?? r.name, online: this.shown(r.pkey), rank: this.rankOf(r.pkey), ...devMark(r.pkey),
        friend: link?.status === 'accepted', pending: !!link && link.status !== 'accepted', incoming: link?.status === 'incoming',
      });
    }
    return out;
  }

  onMatch(seats: MetSeat[], mode: unknown, ranked = false): void {
    this.recent.met(seats, mode, ranked);
  }

  onResult1v1(seats: ResultSeat[]): void {
    this.recent.played(seats);
  }

  private async linksOf(pkey: string): Promise<Map<string, Link>> {
    const hit = this.links.get(pkey);
    if (hit) return hit;
    const rows = await this.store.socialLinks(pkey);
    const map = new Map<string, Link>();
    for (const r of rows) map.set(r.player.pkey, { other: r.player, status: r.status });
    try {
      const prefs = await this.extra.prefsMany(rows.map(r => r.player.pkey));
      for (const [k, p] of prefs) if (p.rp !== null) this.rps.set(k, p.rp);
    } catch (e) {
      this.deps.log?.('WARN', `friend ranks not loaded: ${String(e).slice(0, 120)}`);
    }
    const again = this.links.get(pkey);
    if (again) return again;
    this.links.set(pkey, map);
    return map;
  }

  private row(pkey: string): SocialPlayerRow {
    return { pkey, code: friendCode(pkey), name: this.names.get(pkey) ?? '', last_seen: this.now() };
  }

  private statusOfSocket(ws: WS): Status {
    const d = this.deps.detail ? this.deps.detail(ws) : null;
    const base: PresenceDetail = d ?? { where: this.deps.where(ws) };
    if (base.where === 'lobby' || base.where === 'match') {
      const s: Status = { where: base.where };
      if (base.mode) s.mode = base.mode;
      if (typeof base.ante === 'number') s.ante = base.ante;
      if (base.opponents && base.opponents.length > 0) s.opponents = base.opponents.slice(0, 8);
      if (base.room) s.room = base.room;
      return s;
    }
    const reported = ws.data.socialWhere;
    if (reported === 'browsing' || reported === 'spectating' || reported === 'solo') return { where: reported };
    return { where: 'menu' };
  }

  private statusOf(pkey: string): Status {
    const set = this.online.get(pkey);
    if (!set || set.size === 0 || this.hidden.has(pkey)) return { where: 'offline' };
    let best: Status = { where: 'menu' };
    for (const ws of set) {
      const s = this.statusOfSocket(ws);
      if (PRIORITY[s.where] > PRIORITY[best.where]) best = s;
    }
    return best;
  }

  private rankOf(pkey: string): RankTag | undefined {
    for (const ws of this.online.get(pkey) ?? []) {
      const rp = numericRp(ws.data.rp);
      if (rp !== null) return rankTag(rp);
    }
    const cached = this.rps.get(pkey);
    return cached === undefined ? undefined : rankTag(cached);
  }

  private presencePayload(pkey: string): object {
    const status = this.statusOf(pkey);
    return { type: 'social_presence', code: friendCode(pkey), online: status.where !== 'offline', status, last_seen: this.now(), rank: this.rankOf(pkey), ...devMark(pkey) };
  }

  private pushPresence(pkey: string, force: boolean): void {
    const sig = JSON.stringify(this.statusOf(pkey));
    if (!force && this.sigs.get(pkey) === sig) { this.dirty.delete(pkey); return; }
    const t = this.now();
    if (!force && t - (this.pushedAt.get(pkey) ?? 0) < PRESENCE_GAP_MS) { this.dirty.add(pkey); return; }
    this.sigs.set(pkey, sig);
    this.pushedAt.set(pkey, t);
    this.dirty.delete(pkey);
    const links = this.links.get(pkey);
    if (!links) return;
    const payload = this.presencePayload(pkey);
    for (const l of links.values()) {
      if (l.status !== 'accepted') continue;
      for (const s of this.online.get(l.other.pkey) ?? []) this.deps.send(s, payload);
    }
  }

  private touchSeen(pkey: string, t: number): void {
    const links = this.links.get(pkey);
    if (!links) return;
    for (const l of links.values()) {
      const theirs = this.links.get(l.other.pkey)?.get(pkey);
      if (theirs) theirs.other = { ...theirs.other, last_seen: t };
    }
  }

  private async listPayload(pkey: string): Promise<object> {
    const friends: object[] = [], requests: object[] = [], sent: object[] = [];
    for (const l of (await this.linksOf(pkey)).values()) {
      const name = this.names.get(l.other.pkey) ?? l.other.name;
      const rank = this.rankOf(l.other.pkey);
      if (l.status === 'accepted') {
        const status = this.statusOf(l.other.pkey);
        const online = status.where !== 'offline';
        friends.push({
          code: l.other.code, name, where: legacyWhere(status), online, status,
          last_seen: online ? this.now() : l.other.last_seen, rank, ...devMark(l.other.pkey), unread: this.chat.unreadFrom(pkey, l.other.pkey),
        });
      } else if (l.status === 'incoming') requests.push({ code: l.other.code, name, rank, ...devMark(l.other.pkey) });
      else sent.push({ code: l.other.code, name, rank });
    }
    return { type: 'social_list', friends, requests, sent };
  }

  private async pushList(pkey: string): Promise<void> {
    const set = this.online.get(pkey);
    if (!set || set.size === 0) return;
    const payload = await this.listPayload(pkey);
    for (const ws of set) this.deps.send(ws, payload);
  }

  private setLink(a: string, b: SocialPlayerRow, status: Link['status'], at: number): void {
    this.links.get(a)?.set(b.pkey, { other: b, status });
    this.store.socialSetLink(a, b.pkey, status, at);
  }

  private dropLink(a: string, b: string): void {
    this.links.get(a)?.delete(b);
    this.store.socialDeleteLink(a, b);
  }

  private async playerByCode(code: string): Promise<SocialPlayerRow | null> {
    for (const pkey of this.online.keys()) if (friendCode(pkey) === code) return this.row(pkey);
    return this.store.socialByCode(code);
  }

  private fail(ws: WS, action: string, reason: string): void {
    this.deps.send(ws, { type: 'social_result', action, ok: false, reason });
  }

  private quiet(p: Promise<unknown>): void {
    p.catch(e => this.deps.log?.('WARN', `notification failed: ${String(e).slice(0, 120)}`));
  }

  handle(ws: WS, msg: Record<string, unknown>): void {
    const t = msg.type as string;
    if (t === 'social_hello') {
      const pkey = this.register(ws, msg);
      if (pkey) this.run(ws, t, () => this.hello(ws, pkey));
      return;
    }
    if (t === 'social_emote' && ws.data.bot) { this.emote(ws, msg); return; }
    const me = ws.data.socialKey;
    if (!me) { this.fail(ws, t, 'no_key'); return; }
    if (t === 'social_emote') { this.emote(ws, msg); return; }
    if (t === 'social_status') { this.status(ws, me, msg); return; }
    if (t === 'social_list') { this.run(ws, t, () => this.pushOne(ws, me)); return; }
    if (t === 'social_add') { this.run(ws, t, () => this.add(ws, me, msg)); return; }
    if (t === 'social_accept') { this.run(ws, t, () => this.accept(ws, me, msg)); return; }
    if (t === 'social_remove') { this.run(ws, t, () => this.remove(ws, me, msg)); return; }
    if (t === 'social_invite') { this.run(ws, t, () => this.invite(ws, me, msg)); return; }
    if (t === 'social_search') { this.run(ws, t, () => this.search(ws, me, msg)); return; }
    if (CHAT_SET.has(t)) { this.run(ws, t, async () => { this.chat.handle(ws, me, msg); }); return; }
    if (NOTIFY_SET.has(t)) { this.run(ws, t, async () => { this.notify.handle(ws, me, msg); }); return; }
    if (SCORE_SET.has(t)) { this.run(ws, t, () => this.scores.handle(ws, me, msg)); return; }
    if (RECENT_SET.has(t)) { this.run(ws, t, () => this.recent.handle(ws, me, msg)); return; }
    if (MORE_SET.has(t)) { this.run(ws, t, () => this.more.handle(ws, me, msg)); return; }
  }

  private run(ws: WS, action: string, fn: () => Promise<void>): void {
    this.ensure().then(fn).catch(e => {
      this.deps.log?.('WARN', `${action} failed: ${String(e).slice(0, 160)}`);
      this.fail(ws, action, 'offline');
    });
  }

  private async pushOne(ws: WS, me: string): Promise<void> {
    this.deps.send(ws, await this.listPayload(me));
  }

  private register(ws: WS, msg: Record<string, unknown>): string | null {
    const pkey = msg.pkey;
    if (typeof pkey !== 'string' || !PKEY_RE.test(pkey)) { this.fail(ws, 'social_hello', 'no_key'); return null; }
    if (ws.data.socialKey && ws.data.socialKey !== pkey) this.drop(ws);
    ws.data.socialKey = pkey;
    let set = this.online.get(pkey);
    if (!set) { set = new Set(); this.online.set(pkey, set); }
    set.add(ws);
    const name = typeof msg.name === 'string' ? msg.name : '';
    if (name) this.names.set(pkey, name);
    if (msg.hidden === true) this.hidden.add(pkey);
    else if (msg.hidden === false) this.hidden.delete(pkey);
    return pkey;
  }

  private async hello(ws: WS, pkey: string): Promise<void> {
    this.store.socialUpsert(this.row(pkey));
    this.extra.prefsTouch(pkey, searchKey(this.names.get(pkey) ?? ''), numericRp(ws.data.rp));
    this.deps.send(ws, { type: 'social_me', code: friendCode(pkey) });
    await Promise.all([this.chat.load(pkey), this.notify.items(pkey), this.linksOf(pkey), this.more.load(pkey).catch(e => this.deps.log?.('WARN', `blocks not loaded: ${String(e).slice(0, 120)}`))]);
    await this.pushOne(ws, pkey);
    this.deps.send(ws, this.chat.statePayload(pkey));
    this.deps.send(ws, await this.notify.payload(pkey));
    this.pushPresence(pkey, false);
  }

  private status(ws: WS, me: string, msg: Record<string, unknown>): void {
    const w = msg.where;
    if (w !== 'menu' && w !== 'browsing' && w !== 'spectating' && w !== 'solo') return;
    ws.data.socialWhere = w;
    this.pushPresence(me, false);
  }

  private async search(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const t = this.now();
    const recent = (ws.data.socialSearchAt ?? []).filter(a => t - a < SEARCH_WINDOW_MS);
    if (recent.length >= SEARCH_PER_WINDOW) { ws.data.socialSearchAt = recent; this.fail(ws, 'social_search', 'slow_down'); return; }
    recent.push(t);
    ws.data.socialSearchAt = recent;
    const raw = typeof msg.q === 'string' ? msg.q.trim().slice(0, SEARCH_MAX) : '';
    const key = searchKey(raw);
    if (Array.from(key).length < SEARCH_MIN) { this.fail(ws, 'social_search', 'too_short'); return; }
    const mine = await this.linksOf(me);
    const found = new Map<string, { pkey: string; code: string; name: string; rp: number | null }>();
    for (const h of await this.extra.searchNames(key, SEARCH_LIMIT * 3)) found.set(h.pkey, { pkey: h.pkey, code: h.code, name: h.name, rp: h.rp });
    for (const pkey of this.online.keys()) {
      const name = this.names.get(pkey) ?? '';
      if (name !== '' && searchKey(name).includes(key)) found.set(pkey, { pkey, code: friendCode(pkey), name, rp: null });
    }
    found.delete(me);
    const rows = [...found.values()].filter(h => h.name !== '').map(h => {
      const name = this.names.get(h.pkey) ?? h.name;
      const link = mine.get(h.pkey);
      const rank = this.rankOf(h.pkey) ?? (h.rp !== null ? rankTag(h.rp) : undefined);
      return {
        score: matchScore(searchKey(name), key), online: this.shown(h.pkey), friend: link?.status === 'accepted',
        out: { code: h.code, name, rank, ...devMark(h.pkey), online: this.shown(h.pkey), friend: link?.status === 'accepted', pending: !!link && link.status !== 'accepted', incoming: link?.status === 'incoming' },
      };
    });
    rows.sort((a, b) =>
      b.score - a.score || Number(b.online) - Number(a.online) || Number(a.friend) - Number(b.friend)
      || a.out.name.length - b.out.name.length || a.out.name.localeCompare(b.out.name));
    this.deps.send(ws, { type: 'social_search_result', q: raw, results: rows.slice(0, SEARCH_LIMIT).map(r => r.out) });
  }

  private async add(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const t = this.now();
    const adds = (ws.data.socialAdds ?? []).filter(a => t - a < MINUTE_MS);
    if (adds.length >= ADD_PER_MIN) { ws.data.socialAdds = adds; this.fail(ws, 'social_add', 'slow_down'); return; }
    adds.push(t);
    ws.data.socialAdds = adds;
    const code = cleanFriendCode(msg.code);
    if (!code) { this.fail(ws, 'social_add', 'bad_code'); return; }
    const other = await this.playerByCode(code);
    if (!other) { this.fail(ws, 'social_add', 'not_found'); return; }
    if (other.pkey === me) { this.fail(ws, 'social_add', 'self'); return; }
    if (await this.more.blocked(me, other.pkey)) { this.fail(ws, 'social_add', 'blocked'); return; }
    if (await this.more.blocked(other.pkey, me)) { this.fail(ws, 'social_add', 'not_found'); return; }
    const mine = await this.linksOf(me);
    const existing = mine.get(other.pkey);
    if (existing?.status === 'accepted') { this.fail(ws, 'social_add', 'already'); return; }
    if (existing?.status === 'pending') { this.fail(ws, 'social_add', 'already_sent'); return; }
    if (mine.size >= MAX_FRIENDS) { this.fail(ws, 'social_add', 'full'); return; }
    const theirs = await this.linksOf(other.pkey);
    if (theirs.size >= MAX_FRIENDS && !existing) { this.fail(ws, 'social_add', 'their_list_full'); return; }
    const myRow = this.row(me);
    const myCode = friendCode(me);
    const info = { from: myCode, name: myRow.name };
    if (existing?.status === 'incoming') {
      this.setLink(me, other, 'accepted', t);
      this.setLink(other.pkey, myRow, 'accepted', t);
      this.quiet(this.notify.remove(me, [`fr:${other.code}`]));
      this.quiet(this.notify.push(other.pkey, 'friend_accepted', info, `fa:${myCode}`));
    } else {
      this.setLink(me, other, 'pending', t);
      this.setLink(other.pkey, myRow, 'incoming', t);
      this.quiet(this.notify.push(other.pkey, 'friend_request', info, `fr:${myCode}`));
    }
    this.deps.send(ws, { type: 'social_result', action: 'social_add', ok: true, code, name: other.name });
    await this.pushList(me);
    await this.pushList(other.pkey);
  }

  private async accept(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const code = cleanFriendCode(msg.code);
    const mine = await this.linksOf(me);
    const link = code ? [...mine.values()].find(l => l.other.code === code) : undefined;
    if (!link || link.status !== 'incoming') { this.fail(ws, 'social_accept', 'not_found'); return; }
    const t = this.now();
    await this.linksOf(link.other.pkey);
    this.setLink(me, link.other, 'accepted', t);
    this.setLink(link.other.pkey, this.row(me), 'accepted', t);
    const myCode = friendCode(me);
    this.quiet(this.notify.remove(me, [`fr:${link.other.code}`]));
    this.quiet(this.notify.push(link.other.pkey, 'friend_accepted', { from: myCode, name: this.names.get(me) ?? '' }, `fa:${myCode}`));
    this.deps.send(ws, { type: 'social_result', action: 'social_accept', ok: true, code });
    await this.pushList(me);
    await this.pushList(link.other.pkey);
  }

  private async remove(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const code = cleanFriendCode(msg.code);
    const mine = await this.linksOf(me);
    const link = code ? [...mine.values()].find(l => l.other.code === code) : undefined;
    if (!link) { this.fail(ws, 'social_remove', 'not_found'); return; }
    await this.linksOf(link.other.pkey);
    this.dropLink(me, link.other.pkey);
    this.dropLink(link.other.pkey, me);
    const myCode = friendCode(me);
    this.quiet(this.notify.remove(me, [`fr:${link.other.code}`, `fa:${link.other.code}`]));
    this.quiet(this.notify.remove(link.other.pkey, [`fr:${myCode}`, `fa:${myCode}`]));
    this.deps.send(ws, { type: 'social_result', action: 'social_remove', ok: true, code });
    await this.pushList(me);
    await this.pushList(link.other.pkey);
  }

  private async invite(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const t = this.now();
    if (t - (ws.data.socialInviteAt ?? 0) < INVITE_GAP_MS) { this.fail(ws, 'social_invite', 'slow_down'); return; }
    if (Array.isArray(msg.codes)) { await this.inviteMany(ws, me, msg.codes, t); return; }
    const code = cleanFriendCode(msg.code);
    const link = code ? [...(await this.linksOf(me)).values()].find(l => l.other.code === code) : undefined;
    if (!link || link.status !== 'accepted') { this.fail(ws, 'social_invite', 'not_friend'); return; }
    const target = this.deps.inviteTarget(ws);
    if (!target) { this.fail(ws, 'social_invite', 'no_room'); return; }
    const where = legacyWhere(this.statusOf(link.other.pkey));
    if (where === 'offline') { this.fail(ws, 'social_invite', 'offline'); return; }
    if (where === 'match') { this.fail(ws, 'social_invite', 'busy'); return; }
    ws.data.socialInviteAt = t;
    const name = this.names.get(me) ?? '';
    const payload = { type: 'social_invite', name, from: friendCode(me), room: target.code, party: target.party };
    for (const s of this.online.get(link.other.pkey) ?? []) this.deps.send(s, payload);
    this.quiet(this.notify.push(link.other.pkey, 'invite', { from: friendCode(me), name, room: target.code, party: target.party }, `inv:${friendCode(me)}`));
    this.deps.send(ws, { type: 'social_result', action: 'social_invite', ok: true, code });
  }

  private async inviteMany(ws: WS, me: string, codes: unknown[], t: number): Promise<void> {
    const target = this.deps.inviteTarget(ws);
    if (!target) { this.fail(ws, 'social_invite', 'no_room'); return; }
    ws.data.socialInviteAt = t;
    const mine = await this.linksOf(me);
    const name = this.names.get(me) ?? '';
    const from = friendCode(me);
    const sent: string[] = [];
    const failed: { code: string; reason: string }[] = [];
    for (const raw of [...new Set(codes)].slice(0, INVITE_MANY_MAX)) {
      const code = cleanFriendCode(raw);
      const link = code ? [...mine.values()].find(l => l.other.code === code) : undefined;
      if (!code || !link || link.status !== 'accepted') { failed.push({ code: String(raw).slice(0, 12), reason: 'not_friend' }); continue; }
      const where = legacyWhere(this.statusOf(link.other.pkey));
      if (where === 'offline' || where === 'match') { failed.push({ code, reason: where === 'match' ? 'busy' : 'offline' }); continue; }
      const payload = { type: 'social_invite', name, from, room: target.code, party: target.party };
      for (const s of this.online.get(link.other.pkey) ?? []) this.deps.send(s, payload);
      this.quiet(this.notify.push(link.other.pkey, 'invite', { from, name, room: target.code, party: target.party }, `inv:${from}`));
      sent.push(code);
    }
    const out: Record<string, unknown> = { type: 'social_result', action: 'social_invite', ok: sent.length > 0, many: true, sent, failed };
    if (sent.length === 0) out.reason = failed[0]?.reason ?? 'not_friend';
    this.deps.send(ws, out);
  }

  private emote(ws: WS, msg: Record<string, unknown>): void {
    const e = msg.e;
    const legacy = typeof e === 'number' && Number.isInteger(e) && e >= 1 && e <= EMOTE_COUNT ? e : undefined;
    const id = typeof msg.id === 'string' && (EMOTE_IDS as readonly string[]).includes(msg.id) ? msg.id
      : legacy !== undefined ? EMOTE_FROM_LEGACY[legacy - 1] : undefined;
    if (!id) return;
    const t = this.now();
    if (t - (ws.data.socialEmoteAt ?? 0) < EMOTE_GAP_MS) return;
    ws.data.socialEmoteAt = t;
    const payload: Record<string, unknown> = { type: 'social_emote', id, name: ws.data.bot ? String(ws.data.name ?? '') : (this.names.get(ws.data.socialKey ?? '') ?? '') };
    const old = legacy ?? EMOTE_TO_LEGACY[id];
    if (old !== undefined) payload.e = old;
    const pid = this.deps.lobby?.(ws)?.me;
    if (typeof pid === 'number' && pid >= 0) payload.pid = pid;
    const from = ws.data.socialKey;
    for (const peer of this.deps.roomPeers(ws)) {
      if (peer === ws) continue;
      const to = peer.data.socialKey;
      if (from && to && this.more.blockedNow(to, from)) continue;
      this.deps.send(peer, payload);
    }
  }

  onRanked(pkey: string | undefined, result: Record<string, unknown>): void {
    if (!pkey || result.type !== 'ranked_result') return;
    if (result.promoted === true) {
      const after = (result.after ?? {}) as Record<string, unknown>;
      this.quiet(this.notify.push(pkey, 'game_info', { what: 'rank_up', rank: after.rank, tier: after.tier, rp: after.rp }));
      this.activity(pkey, 'rank_up', { rank: after.rank, tier: after.tier });
    }
    const unlocks = Array.isArray(result.unlocks) ? result.unlocks : [];
    for (const u of unlocks.slice(0, 5)) {
      const item = (u ?? {}) as Record<string, unknown>;
      if (typeof item.id !== 'string') continue;
      this.quiet(this.notify.push(pkey, 'game_info', { what: 'reward', item: item.id, name: item.name, type: item.type, rarity: item.rarity }));
    }
  }

  sizes(): Record<string, number> {
    return { socialOnline: this.online.size, socialNames: this.names.size, socialLinks: this.links.size, socialRps: this.rps.size, socialActivity: this.activityAt.size, ...this.chat.sizes() };
  }

  drop(ws: WS): void {
    const pkey = ws.data.socialKey;
    if (!pkey) return;
    const rp = numericRp(ws.data.rp);
    ws.data.socialKey = undefined;
    const set = this.online.get(pkey);
    if (!set) return;
    set.delete(ws);
    if (set.size > 0) return;
    this.online.delete(pkey);
    this.hidden.delete(pkey);
    const t = this.now();
    if (rp !== null) this.rps.set(pkey, rp);
    this.pushPresence(pkey, true);
    this.touchSeen(pkey, t);
    this.links.delete(pkey);
    this.store.socialUpsert(this.row(pkey));
    this.extra.prefsTouch(pkey, '', rp);
    this.chat.release(pkey);
    this.notify.release(pkey);
    this.more.release(pkey);
    this.names.delete(pkey);
  }
}
