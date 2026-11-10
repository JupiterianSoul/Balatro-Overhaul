import { describe, it, expect } from 'bun:test';
import { readFileSync } from 'node:fs';
import { SocialService, friendCode, cleanFriendCode, EMOTE_GAP_MS, EMOTE_IDS, ADD_PER_MIN, type SocialSocket, type InviteTarget } from './social';
import { MemoryStore, SOCIAL_SCHEMA, D1Store } from './ranked_store';

interface FakeWS extends SocialSocket { sent: Record<string, unknown>[]; where: 'menu' | 'lobby' | 'match'; target: InviteTarget | null; peers: FakeWS[] }

function sock(): FakeWS {
  return { data: {}, sent: [], where: 'menu', target: null, peers: [] };
}

const A = 'a'.repeat(24), B = 'b'.repeat(24), C = 'c'.repeat(24);
const tick = () => new Promise(r => setTimeout(r, 0));

function setup() {
  const store = new MemoryStore();
  const clock = { t: 1_000_000 };
  const svc = new SocialService<FakeWS>(store, {
    send: (ws, d) => { ws.sent.push(d as Record<string, unknown>); },
    where: ws => ws.where,
    inviteTarget: ws => ws.target,
    roomPeers: ws => ws.peers,
  }, () => clock.t);
  return { store, clock, svc };
}

function last(ws: FakeWS, type: string) {
  return [...ws.sent].reverse().find(m => m.type === type) as Record<string, any> | undefined;
}

async function hello(svc: SocialService<FakeWS>, ws: FakeWS, pkey: string, name: string) {
  svc.handle(ws, { type: 'social_hello', pkey, name });
  await tick();
}

async function send(svc: SocialService<FakeWS>, ws: FakeWS, type: string, extra: Record<string, unknown> = {}) {
  svc.handle(ws, { type, ...extra });
  await tick();
}

describe('friend codes', () => {
  it('are stable, formatted and do not contain the key', () => {
    const c = friendCode(A);
    expect(c).toBe(friendCode(A));
    expect(c).toMatch(/^[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    expect(friendCode(B)).not.toBe(c);
    expect(c.replace('-', '').toLowerCase()).not.toBe('a'.repeat(8));
  });

  it('are cleaned from what people type', () => {
    expect(cleanFriendCode(' abcd efgh ')).toBe('ABCD-EFGH');
    expect(cleanFriendCode('abcd-efgh')).toBe('ABCD-EFGH');
    expect(cleanFriendCode('abc')).toBeNull();
    expect(cleanFriendCode('ABCD-EFG1')).toBeNull();
    expect(cleanFriendCode(5)).toBeNull();
  });
});

describe('schema', () => {
  it('the migration file matches what the server creates', () => {
    const norm = (s: string) => s.replace(/\s+/g, ' ').trim();
    const file = readFileSync(new URL('../migrations/0002_social.sql', import.meta.url), 'utf8');
    expect(file.split(';').map(norm).filter(Boolean)).toEqual(SOCIAL_SCHEMA.map(norm));
  });

  it('the D1 store creates every table through its query path', async () => {
    const sqls: string[] = [];
    const store = new D1Store({
      accountId: 'x', databaseId: 'y', token: 'z',
      fetch: (async (_u: string, i: { body: string }) => {
        sqls.push(JSON.parse(i.body).sql);
        return { ok: true, status: 200, json: async () => ({ success: true, result: [{ results: [] }] }) };
      }) as never,
    });
    await store.socialInit();
    expect(sqls).toEqual(SOCIAL_SCHEMA);
  });
});

describe('friends', () => {
  it('hello tells you your code and an empty list', async () => {
    const { svc } = setup();
    const a = sock();
    await hello(svc, a, A, 'Ann');
    expect(last(a, 'social_me')?.code).toBe(friendCode(A));
    expect(last(a, 'social_list')).toMatchObject({ friends: [], requests: [], sent: [] });
  });

  it('refuses a bad key and anything before hello', async () => {
    const { svc } = setup();
    const a = sock();
    await send(svc, a, 'social_hello', { pkey: 'nope' });
    expect(last(a, 'social_result')?.reason).toBe('no_key');
    await send(svc, a, 'social_list');
    expect(last(a, 'social_result')?.reason).toBe('no_key');
  });

  it('request, accept, presence and remove', async () => {
    const { svc } = setup();
    const a = sock(), b = sock();
    await hello(svc, a, A, 'Ann');
    await hello(svc, b, B, 'Bob');
    await send(svc, a, 'social_add', { code: friendCode(B) });
    expect(last(a, 'social_list')?.sent[0]).toMatchObject({ name: 'Bob', code: friendCode(B) });
    expect(last(b, 'social_list')?.requests[0]).toMatchObject({ name: 'Ann', code: friendCode(A) });
    await send(svc, b, 'social_accept', { code: friendCode(A) });
    expect(last(a, 'social_list')?.friends[0]).toMatchObject({ name: 'Bob', where: 'menu' });
    b.where = 'match';
    await send(svc, a, 'social_list');
    expect(last(a, 'social_list')?.friends[0].where).toBe('match');
    await send(svc, a, 'social_remove', { code: friendCode(B) });
    expect(last(a, 'social_list')?.friends).toEqual([]);
    expect(last(b, 'social_list')?.friends).toEqual([]);
  });

  it('adding someone who already asked you makes you friends', async () => {
    const { svc } = setup();
    const a = sock(), b = sock();
    await hello(svc, a, A, 'Ann');
    await hello(svc, b, B, 'Bob');
    await send(svc, a, 'social_add', { code: friendCode(B) });
    await send(svc, b, 'social_add', { code: friendCode(A) });
    expect(last(a, 'social_list')?.friends.length).toBe(1);
    expect(last(b, 'social_list')?.friends.length).toBe(1);
  });

  it('refuses yourself, unknown codes and repeats, and rate limits guesses', async () => {
    const { svc } = setup();
    const a = sock(), b = sock();
    await hello(svc, a, A, 'Ann');
    await hello(svc, b, B, 'Bob');
    await send(svc, a, 'social_add', { code: friendCode(A) });
    expect(last(a, 'social_result')?.reason).toBe('self');
    await send(svc, a, 'social_add', { code: 'ZZZZ-ZZZZ' });
    expect(last(a, 'social_result')?.reason).toBe('not_found');
    await send(svc, a, 'social_add', { code: friendCode(B) });
    await send(svc, a, 'social_add', { code: friendCode(B) });
    expect(last(a, 'social_result')?.reason).toBe('already_sent');
    for (let i = 0; i < ADD_PER_MIN; i++) await send(svc, a, 'social_add', { code: 'ZZZZ-ZZZZ' });
    expect(last(a, 'social_result')?.reason).toBe('slow_down');
  });

  it('friends survive a restart through the store, and an offline player can be added by code', async () => {
    const { svc, store, clock } = setup();
    const a = sock(), b = sock();
    await hello(svc, a, A, 'Ann');
    await hello(svc, b, B, 'Bob');
    svc.drop(b);
    await send(svc, a, 'social_add', { code: friendCode(B) });
    expect(last(a, 'social_list')?.sent[0].name).toBe('Bob');
    const fresh = new SocialService<FakeWS>(store, {
      send: (ws, d) => { ws.sent.push(d as Record<string, unknown>); },
      where: ws => ws.where, inviteTarget: ws => ws.target, roomPeers: ws => ws.peers,
    }, () => clock.t);
    const b2 = sock();
    await hello(fresh, b2, B, 'Bob');
    expect(last(b2, 'social_list')?.requests[0].name).toBe('Ann');
  });

  it('offline friends show as offline with their last seen time', async () => {
    const { svc, clock } = setup();
    const a = sock(), b = sock();
    await hello(svc, a, A, 'Ann');
    await hello(svc, b, B, 'Bob');
    await send(svc, a, 'social_add', { code: friendCode(B) });
    await send(svc, b, 'social_accept', { code: friendCode(A) });
    clock.t += 5000;
    svc.drop(b);
    await send(svc, a, 'social_list');
    expect(last(a, 'social_list')?.friends[0].where).toBe('offline');
  });

  it('a second socket of the same player keeps them online', async () => {
    const { svc } = setup();
    const a = sock(), b1 = sock(), b2 = sock();
    await hello(svc, a, A, 'Ann');
    await hello(svc, b1, B, 'Bob');
    await hello(svc, b2, B, 'Bob');
    await send(svc, a, 'social_add', { code: friendCode(B) });
    await send(svc, b1, 'social_accept', { code: friendCode(A) });
    svc.drop(b1);
    await send(svc, a, 'social_list');
    expect(last(a, 'social_list')?.friends[0].where).toBe('menu');
  });
});

describe('invites', () => {
  async function friends() {
    const s = setup();
    const a = sock(), b = sock();
    await hello(s.svc, a, A, 'Ann');
    await hello(s.svc, b, B, 'Bob');
    await send(s.svc, a, 'social_add', { code: friendCode(B) });
    await send(s.svc, b, 'social_accept', { code: friendCode(A) });
    return { ...s, a, b };
  }

  it('reach a friend with the room code', async () => {
    const { svc, a, b } = await friends();
    a.target = { code: 'AB12', party: false };
    await send(svc, a, 'social_invite', { code: friendCode(B) });
    expect(last(b, 'social_invite')).toMatchObject({ name: 'Ann', room: 'AB12', party: false, from: friendCode(A) });
    expect(last(a, 'social_result')).toMatchObject({ action: 'social_invite', ok: true });
  });

  it('are refused without a room, for strangers, in a match, and when offline', async () => {
    const { svc, a, b, clock } = await friends();
    await send(svc, a, 'social_invite', { code: friendCode(B) });
    expect(last(a, 'social_result')?.reason).toBe('no_room');
    a.target = { code: 'AB12', party: false };
    await send(svc, a, 'social_invite', { code: friendCode(C) });
    expect(last(a, 'social_result')?.reason).toBe('not_friend');
    b.where = 'match';
    await send(svc, a, 'social_invite', { code: friendCode(B) });
    expect(last(a, 'social_result')?.reason).toBe('busy');
    svc.drop(b);
    clock.t += 10000;
    await send(svc, a, 'social_invite', { code: friendCode(B) });
    expect(last(a, 'social_result')?.reason).toBe('offline');
    expect(b.sent.some(m => m.type === 'social_invite')).toBe(false);
  });

  it('are rate limited', async () => {
    const { svc, a, b } = await friends();
    a.target = { code: 'AB12', party: false };
    await send(svc, a, 'social_invite', { code: friendCode(B) });
    await send(svc, a, 'social_invite', { code: friendCode(B) });
    expect(last(a, 'social_result')?.reason).toBe('slow_down');
    expect(b.sent.filter(m => m.type === 'social_invite').length).toBe(1);
  });
});

describe('emotes', () => {
  it('reach the others in the room, not the sender, and are rate limited', async () => {
    const { svc, clock } = setup();
    const a = sock(), b = sock();
    await hello(svc, a, A, 'Ann');
    await hello(svc, b, B, 'Bob');
    a.peers = [a, b];
    svc.handle(a, { type: 'social_emote', e: 2 });
    svc.handle(a, { type: 'social_emote', e: 3 });
    expect(b.sent.filter(m => m.type === 'social_emote')).toEqual([{ type: 'social_emote', id: 'gg', e: 2, name: 'Ann' }]);
    expect(a.sent.some(m => m.type === 'social_emote')).toBe(false);
    clock.t += EMOTE_GAP_MS;
    svc.handle(a, { type: 'social_emote', e: 3 });
    expect(b.sent.filter(m => m.type === 'social_emote').length).toBe(2);
  });

  it('ignores ids outside the preset set', async () => {
    const { svc } = setup();
    const a = sock(), b = sock();
    await hello(svc, a, A, 'Ann');
    a.peers = [a, b];
    for (const e of [0, 7, 1.5, 'x']) svc.handle(a, { type: 'social_emote', e });
    for (const id of ['', 'dance', 7, 'GG']) svc.handle(a, { type: 'social_emote', id });
    expect(b.sent.length).toBe(0);
  });

  it('relay new ids with the closest old number for old clients', async () => {
    const { svc, clock } = setup();
    const a = sock(), b = sock();
    await hello(svc, a, A, 'Ann');
    a.peers = [a, b];
    svc.handle(a, { type: 'social_emote', id: 'laugh' });
    clock.t += EMOTE_GAP_MS;
    svc.handle(a, { type: 'social_emote', id: 'nope' });
    clock.t += EMOTE_GAP_MS;
    svc.handle(a, { type: 'social_emote', id: 'chips', e: 5 });
    expect(b.sent.filter(m => m.type === 'social_emote')).toEqual([
      { type: 'social_emote', id: 'laugh', e: 3, name: 'Ann' },
      { type: 'social_emote', id: 'nope', name: 'Ann' },
      { type: 'social_emote', id: 'chips', e: 5, name: 'Ann' },
    ]);
    expect(EMOTE_IDS.length).toBeGreaterThanOrEqual(8);
    expect(EMOTE_IDS.length).toBeLessThanOrEqual(12);
  });

  it('carry the sender seat so clients find their row', async () => {
    const store = new MemoryStore();
    const clock = { t: 1_000_000 };
    const svc = new SocialService<FakeWS>(store, {
      send: (ws, d) => { ws.sent.push(d as Record<string, unknown>); },
      where: ws => ws.where,
      inviteTarget: ws => ws.target,
      roomPeers: ws => ws.peers,
      lobby: ws => ({ id: 'r1', me: ws.peers.indexOf(ws), seats: ws.peers.map((s, pid) => ({ pid, ws: s })), matchId: null }),
    }, () => clock.t);
    const a = sock(), b = sock();
    await hello(svc, a, A, 'Ann');
    await hello(svc, b, B, 'Bob');
    a.peers = [b, a];
    svc.handle(a, { type: 'social_emote', id: 'hi' });
    expect(last(b, 'social_emote')).toEqual({ type: 'social_emote', id: 'hi', e: 1, name: 'Ann', pid: 1 });
  });
});
