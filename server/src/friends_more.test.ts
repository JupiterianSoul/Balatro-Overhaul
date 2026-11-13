import { describe, it, expect } from 'bun:test';
import { SocialService, friendCode, ACTIVITY_GAP_MS, type SocialSocket, type PresenceDetail } from './social';
import { MemoryStore } from './ranked_store';
import { TYPING_GAP_MS, ASK_GAP_MS, GIFTS_PER_DAY } from './friends_more';
import { DailyBoard, MemoryDailyStore, dayOf } from './daily_board';
import { scopeNotifyId, unscopeNotifyId } from './social_store';

interface FakeWS extends SocialSocket { sent: Record<string, any>[]; detail: PresenceDetail | null; room?: string; peers?: FakeWS[] }

const A = 'a'.repeat(24), B = 'b'.repeat(24), C = 'c'.repeat(24);
const flush = () => new Promise(r => setTimeout(r, 0));

function sock(): FakeWS {
  return { data: {}, sent: [], detail: null };
}

function setup() {
  const store = new MemoryStore();
  const clock = { t: Date.UTC(2026, 10, 5, 12) };
  const svc = new SocialService<FakeWS>(store, {
    send: (ws, d) => { ws.sent.push(d as Record<string, any>); },
    where: ws => ws.detail?.where ?? 'menu',
    detail: ws => ws.detail,
    inviteTarget: ws => ws.room ? { code: ws.room, party: false } : null,
    roomPeers: ws => ws.peers ?? [],
  }, () => clock.t);
  return { store, clock, svc };
}

type Env = ReturnType<typeof setup>;

function last(ws: FakeWS, type: string): any {
  return [...ws.sent].reverse().find(m => m.type === type);
}

async function send(env: Env, ws: FakeWS, type: string, extra: Record<string, unknown> = {}) {
  env.svc.handle(ws, { type, ...extra });
  for (let i = 0; i < 5; i++) await flush();
}

async function hello(env: Env, ws: FakeWS, pkey: string, name: string, extra: Record<string, unknown> = {}) {
  await send(env, ws, 'social_hello', { pkey, name, ...extra });
}

async function friends(env: Env, a: FakeWS, aKey: string, b: FakeWS, bKey: string) {
  await send(env, a, 'social_add', { code: friendCode(bKey) });
  await send(env, b, 'social_accept', { code: friendCode(aKey) });
}

async function pair() {
  const env = setup();
  const a = sock(), b = sock();
  await hello(env, a, A, 'Ann');
  await hello(env, b, B, 'Ben');
  await friends(env, a, A, b, B);
  return { env, a, b };
}

function friendRow(ws: FakeWS, code: string): any {
  return (last(ws, 'social_list')?.friends ?? []).find((f: any) => f.code === code);
}

describe('appear offline', () => {
  it('shows a hidden player as offline to friends and back again', async () => {
    const { env, a, b } = await pair();
    expect(friendRow(b, friendCode(A)).online).toBe(true);
    await send(env, a, 'social_hide', { on: true });
    expect(last(a, 'social_result')).toMatchObject({ action: 'social_hide', ok: true, on: true });
    expect(last(b, 'social_presence')).toMatchObject({ code: friendCode(A), online: false });
    await send(env, b, 'social_list');
    expect(friendRow(b, friendCode(A)).online).toBe(false);
    await send(env, b, 'social_invite', { code: friendCode(A) });
    b.room = 'ROOM1';
    env.clock.t += 5000;
    await send(env, b, 'social_invite', { code: friendCode(A) });
    expect(last(b, 'social_result')).toMatchObject({ action: 'social_invite', ok: false, reason: 'offline' });
    await send(env, a, 'social_hide', { on: false });
    expect(last(b, 'social_presence')).toMatchObject({ code: friendCode(A), online: true });
  });

  it('keeps the hidden flag from hello and drops it when the player leaves', async () => {
    const env = setup();
    const a = sock(), b = sock();
    await hello(env, a, A, 'Ann', { hidden: true });
    await hello(env, b, B, 'Ben');
    await friends(env, a, A, b, B);
    expect(friendRow(b, friendCode(A)).online).toBe(false);
    expect(env.svc.isHidden(A)).toBe(true);
    env.svc.drop(a);
    expect(env.svc.isHidden(A)).toBe(false);
  });
});

describe('block a player', () => {
  it('removes the friend, lists the block and stops requests both ways', async () => {
    const { env, a, b } = await pair();
    await send(env, a, 'social_block', { code: friendCode(B) });
    expect(last(a, 'social_result')).toMatchObject({ action: 'social_block', ok: true, code: friendCode(B) });
    expect(last(a, 'social_blocks').items).toEqual([expect.objectContaining({ code: friendCode(B), name: 'Ben' })]);
    expect(last(a, 'social_list').friends).toEqual([]);
    expect(last(b, 'social_list').friends).toEqual([]);
    await send(env, b, 'social_add', { code: friendCode(A) });
    expect(last(b, 'social_result')).toMatchObject({ action: 'social_add', ok: false, reason: 'not_found' });
    await send(env, a, 'social_add', { code: friendCode(B) });
    expect(last(a, 'social_result')).toMatchObject({ action: 'social_add', ok: false, reason: 'blocked' });
    await send(env, a, 'social_unblock', { code: friendCode(B) });
    expect(last(a, 'social_blocks').items).toEqual([]);
    await send(env, b, 'social_add', { code: friendCode(A) });
    expect(last(b, 'social_result')).toMatchObject({ action: 'social_add', ok: true });
  });

  it('drops room emotes from a blocked player only for the one who blocked', async () => {
    const env = setup();
    const a = sock(), b = sock(), c = sock();
    await hello(env, a, A, 'Ann');
    await hello(env, b, B, 'Ben');
    await hello(env, c, C, 'Cat');
    await send(env, a, 'social_block', { code: friendCode(B) });
    b.peers = [a, b, c];
    await send(env, b, 'social_emote', { id: 'gg' });
    expect(last(a, 'social_emote')).toBeUndefined();
    expect(last(c, 'social_emote')).toMatchObject({ id: 'gg', name: 'Ben' });
  });

  it('refuses itself, unknown codes and keeps the list across a reconnect', async () => {
    const env = setup();
    const a = sock(), b = sock();
    await hello(env, a, A, 'Ann');
    await hello(env, b, B, 'Ben');
    await send(env, a, 'social_block', { code: friendCode(A) });
    expect(last(a, 'social_result')).toMatchObject({ ok: false, reason: 'self' });
    await send(env, a, 'social_block', { code: 'ZZZZ-ZZZZ' });
    expect(last(a, 'social_result')).toMatchObject({ ok: false, reason: 'not_found' });
    await send(env, a, 'social_block', { code: friendCode(B) });
    env.svc.drop(a);
    const a2 = sock();
    await hello(env, a2, A, 'Ann');
    await send(env, a2, 'social_blocks');
    expect(last(a2, 'social_blocks').items.map((i: any) => i.code)).toEqual([friendCode(B)]);
  });
});

describe('typing in DMs', () => {
  it('tells the friend, at most once per gap, and never a stranger', async () => {
    const { env, a, b } = await pair();
    await send(env, a, 'social_typing', { to: friendCode(B) });
    await send(env, a, 'social_typing', { to: friendCode(B) });
    expect(b.sent.filter(m => m.type === 'social_typing')).toEqual([{ type: 'social_typing', from: friendCode(A) }]);
    env.clock.t += TYPING_GAP_MS;
    await send(env, a, 'social_typing', { to: friendCode(B) });
    expect(b.sent.filter(m => m.type === 'social_typing').length).toBe(2);
    const c = sock();
    await hello(env, c, C, 'Cat');
    await send(env, c, 'social_typing', { to: friendCode(B) });
    expect(b.sent.filter(m => m.type === 'social_typing').length).toBe(2);
  });
});

describe('ask to join', () => {
  it('asks a friend in a lobby, and an accept sends the room as an invite', async () => {
    const { env, a, b } = await pair();
    await send(env, a, 'social_ask', { code: friendCode(B) });
    expect(last(a, 'social_result')).toMatchObject({ action: 'social_ask', ok: false, reason: 'not_in_lobby' });
    b.detail = { where: 'lobby', mode: 'attrition' };
    b.room = 'ROOM9';
    env.clock.t += ASK_GAP_MS;
    await send(env, a, 'social_ask', { code: friendCode(B) });
    expect(last(a, 'social_result')).toMatchObject({ action: 'social_ask', ok: true });
    expect(last(b, 'social_ask')).toEqual({ type: 'social_ask', from: friendCode(A), name: 'Ann' });
    await send(env, a, 'social_ask', { code: friendCode(B) });
    expect(last(a, 'social_result')).toMatchObject({ action: 'social_ask', ok: false, reason: 'slow_down' });
    await send(env, b, 'social_ask_reply', { code: friendCode(A), ok: true });
    expect(last(a, 'social_invite')).toMatchObject({ room: 'ROOM9', from: friendCode(B), name: 'Ben', asked: true });
  });

  it('a decline tells the asker', async () => {
    const { env, a, b } = await pair();
    b.detail = { where: 'lobby' };
    await send(env, a, 'social_ask', { code: friendCode(B) });
    await send(env, b, 'social_ask_reply', { code: friendCode(A), ok: false });
    expect(last(a, 'social_ask_no')).toEqual({ type: 'social_ask_no', from: friendCode(B), name: 'Ben' });
    expect(last(a, 'social_invite')).toBeUndefined();
  });
});

describe('friend activity', () => {
  it('puts a minigame best in each friend inbox, once per gap', async () => {
    const { env, a, b } = await pair();
    await send(env, a, 'mg_best', { game: 'blackjack', score: 42 });
    for (let i = 0; i < 10; i++) await flush();
    const item = last(b, 'notify_new')?.item;
    expect(item).toMatchObject({ kind: 'friend_activity', id: `act:${friendCode(A)}:mg_best:blackjack` });
    expect(item.data).toMatchObject({ from: friendCode(A), name: 'Ann', what: 'mg_best', game: 'blackjack', score: 42 });
    const count = b.sent.filter(m => m.type === 'notify_new').length;
    env.clock.t += 1000;
    await send(env, a, 'mg_best', { game: 'blackjack', score: 50 });
    for (let i = 0; i < 10; i++) await flush();
    expect(b.sent.filter(m => m.type === 'notify_new').length).toBe(count);
    env.clock.t += ACTIVITY_GAP_MS;
    env.svc.activity(A, 'daily', { won: true, ante: 8, rank: 1, total: 3 });
    for (let i = 0; i < 10; i++) await flush();
    expect(last(b, 'notify_new').item.data).toMatchObject({ what: 'daily', won: true, ante: 8 });
    expect(last(a, 'notify_new')?.item?.kind).not.toBe('friend_activity');
  });
});

describe('daily board friends', () => {
  it('lists the friends who played with their rank', async () => {
    const t = Date.UTC(2026, 10, 5, 12);
    const board = new DailyBoard(new MemoryDailyStore(), { now: () => t });
    const day = dayOf(t);
    const keys = [A, B, C];
    for (let i = 0; i < 3; i++) {
      await board.submit({ pkey: keys[i], name: ['Ann', 'Ben', 'Cat'][i], day, sig: 's', won: i === 1, ante: 3 + i, round: 9, best: 100 });
    }
    const out = await board.board(A, day, 's', [C]);
    expect(out.friends?.map(r => [r.name, r.rank, !!r.me])).toEqual([['Cat', 2, false], ['Ann', 3, true]]);
    const none = await board.board(A, day, 's');
    expect(none.friends).toBeUndefined();
  });
});

describe('notify ids per player', () => {
  it('scopes the stored id and reads it back unchanged', () => {
    expect(scopeNotifyId(A, 'fr:ABCD-EFGH')).toBe('fr:ABCD-EFGH#aaaaaaaa');
    expect(unscopeNotifyId(scopeNotifyId(A, 'fr:ABCD-EFGH'))).toBe('fr:ABCD-EFGH');
    expect(unscopeNotifyId('nabc123')).toBe('nabc123');
  });
});

describe('party invite to several friends', () => {
  it('invites every online friend in one go and lists the rest', async () => {
    const env = setup();
    const a = sock(), b = sock(), c = sock();
    await hello(env, a, A, 'Ann');
    await hello(env, b, B, 'Ben');
    await hello(env, c, C, 'Cat');
    await friends(env, a, A, b, B);
    await friends(env, a, A, c, C);
    c.detail = { where: 'match' };
    await send(env, a, 'social_invite', { codes: [friendCode(B), friendCode(C), 'NOPE'] });
    expect(last(a, 'social_result')).toMatchObject({ action: 'social_invite', ok: false, reason: 'no_room' });
    a.room = 'PARTY1';
    await send(env, a, 'social_invite', { codes: [friendCode(B), friendCode(C), 'NOPE'] });
    const r = last(a, 'social_result');
    expect(r).toMatchObject({ action: 'social_invite', ok: true, many: true, sent: [friendCode(B)] });
    expect(r.failed.map((f: any) => f.reason)).toEqual(['busy', 'not_friend']);
    expect(last(b, 'social_invite')).toMatchObject({ room: 'PARTY1', name: 'Ann' });
    expect(last(c, 'social_invite')).toBeUndefined();
    await send(env, a, 'social_invite', { codes: [friendCode(B)] });
    expect(last(a, 'social_result')).toMatchObject({ ok: false, reason: 'slow_down' });
  });
});

describe('gifts', () => {
  it('puts a gift in the friend inbox and checks the item and the daily limit', async () => {
    const { env, a, b } = await pair();
    await send(env, a, 'social_gift', { code: friendCode(B), item: 'palette:neon', item_name: 'Neon', rarity: 'epic' });
    expect(last(a, 'social_result')).toMatchObject({ action: 'social_gift', ok: true, item: 'palette:neon' });
    const item = last(b, 'notify_new').item;
    expect(item.kind).toBe('gift');
    expect(item.id.startsWith(`gift:${friendCode(A)}:`)).toBe(true);
    expect(item.data).toMatchObject({ from: friendCode(A), name: 'Ann', item: 'palette:neon', item_name: 'Neon', rarity: 'epic' });
    await send(env, a, 'social_gift', { code: friendCode(B), item: 'no spaces allowed', rarity: 'epic' });
    expect(last(a, 'social_result')).toMatchObject({ ok: false, reason: 'bad_item' });
    const c = sock();
    await hello(env, c, C, 'Cat');
    await send(env, c, 'social_gift', { code: friendCode(B), item: 'palette:neon' });
    expect(last(c, 'social_result')).toMatchObject({ ok: false, reason: 'not_friend' });
    for (let i = 1; i < GIFTS_PER_DAY; i++) await send(env, a, 'social_gift', { code: friendCode(B), item: 'felt:green', rarity: 'common' });
    await send(env, a, 'social_gift', { code: friendCode(B), item: 'felt:green', rarity: 'common' });
    expect(last(a, 'social_result')).toMatchObject({ ok: false, reason: 'gift_limit' });
    env.clock.t += 86_400_000;
    await send(env, a, 'social_gift', { code: friendCode(B), item: 'felt:green', rarity: 'bogus' });
    expect(last(a, 'social_result')).toMatchObject({ ok: true });
    expect(last(b, 'notify_new').item.data.rarity).toBe('common');
  });
});
