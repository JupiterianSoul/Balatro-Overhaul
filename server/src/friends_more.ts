import { D1Store, type RankedStore } from './ranked_store';

export const MORE_TYPES = ['social_hide', 'social_block', 'social_unblock', 'social_blocks', 'social_typing', 'social_ask', 'social_ask_reply', 'social_gift'];
export const BLOCK_SCHEMA = [
  `CREATE TABLE IF NOT EXISTS social_blocks (
  pkey TEXT NOT NULL,
  other TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  at INTEGER NOT NULL,
  PRIMARY KEY (pkey, other)
)`,
];
export const BLOCKS_MAX = 200;
export const BLOCK_PER_MIN = 10;
export const TYPING_GAP_MS = 1500;
export const ASK_GAP_MS = 10_000;
export const GIFTS_PER_DAY = 10;
export const GIFT_ITEM_RE = /^[a-z_]{1,16}:[A-Za-z0-9_.-]{1,48}$/;
export const GIFT_RARITIES = ['common', 'uncommon', 'rare', 'epic', 'legendary'];
const DAY_MS = 86_400_000;

export interface BlockRow { pkey: string; other: string; name: string; at: number }

export interface BlockStore {
  init(): Promise<void>;
  list(pkey: string): Promise<BlockRow[]>;
  add(r: BlockRow): void;
  remove(pkey: string, other: string): void;
}

export class MemoryBlocks implements BlockStore {
  rows = new Map<string, Map<string, BlockRow>>();
  async init(): Promise<void> { return; }
  async list(pkey: string): Promise<BlockRow[]> {
    return [...(this.rows.get(pkey)?.values() ?? [])].map(r => ({ ...r }));
  }
  add(r: BlockRow): void {
    let mine = this.rows.get(r.pkey);
    if (!mine) { mine = new Map(); this.rows.set(r.pkey, mine); }
    mine.set(r.other, { ...r });
  }
  remove(pkey: string, other: string): void {
    this.rows.get(pkey)?.delete(other);
  }
}

export class D1Blocks implements BlockStore {
  constructor(private d1: D1Store) {}
  async init(): Promise<void> {
    for (const sql of BLOCK_SCHEMA) await this.d1.query(sql);
  }
  async list(pkey: string): Promise<BlockRow[]> {
    const rows = await this.d1.query('SELECT pkey, other, name, at FROM social_blocks WHERE pkey = ? ORDER BY at DESC LIMIT ?', [pkey, BLOCKS_MAX]);
    return rows.map(r => ({ pkey: String(r.pkey), other: String(r.other), name: String(r.name ?? ''), at: Number(r.at) }));
  }
  add(r: BlockRow): void {
    this.d1.enqueue(`INSERT INTO social_blocks (pkey, other, name, at) VALUES (?, ?, ?, ?)
      ON CONFLICT (pkey, other) DO UPDATE SET name = excluded.name, at = excluded.at`, [r.pkey, r.other, r.name, r.at]);
  }
  remove(pkey: string, other: string): void {
    this.d1.enqueue('DELETE FROM social_blocks WHERE pkey = ? AND other = ?', [pkey, other]);
  }
}

export function blockStoreFor(store: RankedStore): BlockStore {
  if (store instanceof D1Store) return new D1Blocks(store);
  return new MemoryBlocks();
}

export interface MoreSocket { data: { socialKey?: string; typingAt?: number; askAt?: number; blockAt?: number[] } }

export interface MoreDeps<WS> {
  send(ws: WS, data: object): void;
  socketsOf(pkey: string): WS[];
  nameOf(pkey: string): string;
  codeOf(pkey: string): string;
  friendPkey(me: string, code: string): Promise<string | null>;
  playerOf(code: string): Promise<{ pkey: string; name: string } | null>;
  inLobby(pkey: string): boolean;
  inviteTarget(ws: WS): { code: string; party: boolean } | null;
  muted(pkey: string, other: string): boolean;
  unfriend(me: string, other: string): Promise<void>;
  setHidden(pkey: string, on: boolean): void;
  gift?(to: string, data: Record<string, unknown>, id: string): Promise<boolean>;
  log?(level: string, msg: string): void;
}

export class FriendsMore<WS extends MoreSocket> {
  private blocks = new Map<string, Map<string, BlockRow>>();
  private ready: Promise<void> | null = null;
  private gifts = new Map<string, { day: number; n: number }>();
  private giftSeq = 0;

  constructor(private store: BlockStore, private deps: MoreDeps<WS>, private now: () => number = Date.now) {}

  ensure(): Promise<void> {
    if (!this.ready) this.ready = this.store.init().catch(e => { this.ready = null; throw e; });
    return this.ready;
  }

  async load(pkey: string): Promise<void> {
    if (this.blocks.has(pkey)) return;
    await this.ensure();
    const map = new Map<string, BlockRow>();
    for (const r of await this.store.list(pkey)) map.set(r.other, r);
    if (!this.blocks.has(pkey)) this.blocks.set(pkey, map);
  }

  release(pkey: string): void {
    this.blocks.delete(pkey);
  }

  blockedNow(pkey: string, other: string): boolean {
    return this.blocks.get(pkey)?.has(other) ?? false;
  }

  async blocked(pkey: string, other: string): Promise<boolean> {
    const hit = this.blocks.get(pkey);
    if (hit) return hit.has(other);
    await this.ensure();
    return (await this.store.list(pkey)).some(r => r.other === other);
  }

  private fail(ws: WS, action: string, reason: string): void {
    this.deps.send(ws, { type: 'social_result', action, ok: false, reason });
  }

  private ok(ws: WS, action: string, more: Record<string, unknown> = {}): void {
    this.deps.send(ws, { type: 'social_result', action, ok: true, ...more });
  }

  async handle(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const t = msg.type;
    if (t === 'social_hide') { this.deps.setHidden(me, msg.on === true); this.ok(ws, 'social_hide', { on: msg.on === true }); return; }
    if (t === 'social_blocks') return this.list(ws, me);
    if (t === 'social_block') return this.block(ws, me, msg, true);
    if (t === 'social_unblock') return this.block(ws, me, msg, false);
    if (t === 'social_typing') return this.typing(ws, me, msg);
    if (t === 'social_ask') return this.ask(ws, me, msg);
    if (t === 'social_ask_reply') return this.askReply(ws, me, msg);
    if (t === 'social_gift') return this.gift(ws, me, msg);
  }

  private async gift(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const item = typeof msg.item === 'string' ? msg.item : '';
    if (!GIFT_ITEM_RE.test(item)) { this.fail(ws, 'social_gift', 'bad_item'); return; }
    const rarity = typeof msg.rarity === 'string' && GIFT_RARITIES.includes(msg.rarity) ? msg.rarity : 'common';
    const other = await this.deps.friendPkey(me, String(msg.code ?? ''));
    if (!other) { this.fail(ws, 'social_gift', 'not_friend'); return; }
    if (!this.deps.gift) { this.fail(ws, 'social_gift', 'offline'); return; }
    const t = this.now();
    const day = Math.floor(t / DAY_MS);
    const used = this.gifts.get(me);
    const n = used && used.day === day ? used.n : 0;
    if (n >= GIFTS_PER_DAY) { this.fail(ws, 'social_gift', 'gift_limit'); return; }
    this.gifts.set(me, { day, n: n + 1 });
    if (this.gifts.size > 5000) for (const [k, v] of this.gifts) if (v.day !== day) this.gifts.delete(k);
    this.giftSeq = (this.giftSeq + 1) % 100_000;
    const from = this.deps.codeOf(me);
    const data = {
      from, name: this.deps.nameOf(me), item, rarity,
      item_name: typeof msg.item_name === 'string' ? msg.item_name.slice(0, 40) : '',
    };
    const ok = await this.deps.gift(other, data, `gift:${from}:${t.toString(36)}${this.giftSeq.toString(36)}`);
    if (!ok) { this.gifts.set(me, { day, n }); this.fail(ws, 'social_gift', 'offline'); return; }
    this.ok(ws, 'social_gift', { code: this.deps.codeOf(other), item });
  }

  private async list(ws: WS, me: string): Promise<void> {
    await this.load(me);
    const items = [...(this.blocks.get(me)?.values() ?? [])]
      .sort((a, b) => b.at - a.at)
      .map(r => ({ code: this.deps.codeOf(r.other), name: this.deps.nameOf(r.other) || r.name, at: r.at }));
    this.deps.send(ws, { type: 'social_blocks', items });
  }

  private async block(ws: WS, me: string, msg: Record<string, unknown>, on: boolean): Promise<void> {
    const action = on ? 'social_block' : 'social_unblock';
    const t = this.now();
    const recent = (ws.data.blockAt ?? []).filter(a => t - a < 60_000);
    if (recent.length >= BLOCK_PER_MIN) { ws.data.blockAt = recent; this.fail(ws, action, 'slow_down'); return; }
    recent.push(t);
    ws.data.blockAt = recent;
    const other = await this.deps.playerOf(String(msg.code ?? ''));
    if (!other) { this.fail(ws, action, 'not_found'); return; }
    if (other.pkey === me) { this.fail(ws, action, 'self'); return; }
    await this.load(me);
    const mine = this.blocks.get(me) as Map<string, BlockRow>;
    const code = this.deps.codeOf(other.pkey);
    if (on) {
      if (!mine.has(other.pkey) && mine.size >= BLOCKS_MAX) { this.fail(ws, action, 'full'); return; }
      const fallback = typeof msg.name === 'string' ? msg.name.slice(0, 32) : '';
      const row: BlockRow = { pkey: me, other: other.pkey, name: (other.name || fallback).slice(0, 32), at: t };
      mine.set(other.pkey, row);
      this.store.add(row);
      await this.deps.unfriend(me, other.pkey);
    } else {
      mine.delete(other.pkey);
      this.store.remove(me, other.pkey);
    }
    this.ok(ws, action, { code });
    await this.list(ws, me);
  }

  private async typing(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const t = this.now();
    if (t - (ws.data.typingAt ?? 0) < TYPING_GAP_MS) return;
    ws.data.typingAt = t;
    const other = await this.deps.friendPkey(me, String(msg.to ?? ''));
    if (!other || this.deps.muted(other, me)) return;
    const payload = { type: 'social_typing', from: this.deps.codeOf(me) };
    for (const s of this.deps.socketsOf(other)) this.deps.send(s, payload);
  }

  private async ask(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const t = this.now();
    if (t - (ws.data.askAt ?? 0) < ASK_GAP_MS) { this.fail(ws, 'social_ask', 'slow_down'); return; }
    const other = await this.deps.friendPkey(me, String(msg.code ?? ''));
    if (!other) { this.fail(ws, 'social_ask', 'not_friend'); return; }
    if (!this.deps.inLobby(other)) { this.fail(ws, 'social_ask', 'not_in_lobby'); return; }
    ws.data.askAt = t;
    const payload = { type: 'social_ask', from: this.deps.codeOf(me), name: this.deps.nameOf(me) };
    for (const s of this.deps.socketsOf(other)) this.deps.send(s, payload);
    this.ok(ws, 'social_ask', { code: this.deps.codeOf(other) });
  }

  private async askReply(ws: WS, me: string, msg: Record<string, unknown>): Promise<void> {
    const other = await this.deps.friendPkey(me, String(msg.code ?? ''));
    if (!other) { this.fail(ws, 'social_ask_reply', 'not_friend'); return; }
    const from = this.deps.codeOf(me);
    const name = this.deps.nameOf(me);
    if (msg.ok !== true) {
      for (const s of this.deps.socketsOf(other)) this.deps.send(s, { type: 'social_ask_no', from, name });
      this.ok(ws, 'social_ask_reply', { code: this.deps.codeOf(other), accepted: false });
      return;
    }
    const target = this.deps.inviteTarget(ws);
    if (!target) { this.fail(ws, 'social_ask_reply', 'no_room'); return; }
    const payload = { type: 'social_invite', name, from, room: target.code, party: target.party, asked: true };
    for (const s of this.deps.socketsOf(other)) this.deps.send(s, payload);
    this.ok(ws, 'social_ask_reply', { code: this.deps.codeOf(other), accepted: true });
  }
}
