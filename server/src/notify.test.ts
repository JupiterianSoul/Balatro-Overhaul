import { describe, it, expect } from 'bun:test';
import { NotifyService, cleanData, notifyMatchDecision, NOTIFY_KINDS, NOTIFY_MAX, INVITE_TTL_MS, DECISION_TARGETS_MAX, DECISION_ID_MAX } from './notify';
import { SocialService, friendCode, type SocialSocket, type InviteTarget } from './social';
import { MemoryStore } from './ranked_store';
import { MemoryExtra } from './social_store';

interface FakeWS { sent: Record<string, any>[] }

const flush = () => new Promise(r => setTimeout(r, 0));

function lastOf(ws: { sent: Record<string, any>[] }, type: string): any {
  return [...ws.sent].reverse().find(m => m.type === type);
}

function unit() {
  const extra = new MemoryExtra();
  const clock = { t: 1_000_000 };
  const socks = new Map<string, FakeWS[]>();
  const make = () => new NotifyService<FakeWS>(extra, { socketsOf: k => socks.get(k) ?? [] }, { send: (ws, d) => { ws.sent.push(d as Record<string, any>); } }, () => clock.t);
  const svc = make();
  const online = (pkey: string): FakeWS => {
    const ws: FakeWS = { sent: [] };
    socks.set(pkey, [...(socks.get(pkey) ?? []), ws]);
    return ws;
  };
  return { extra, clock, svc, make, online };
}

describe('notification inbox', () => {
  it('pushes new items to online clients and stores them', async () => {
    const { svc, extra, online } = unit();
    const ws = online('P1');
    const item = await svc.push('P1', 'friend_request', { from: 'ABCD-EFGH', name: 'Ann' });
    expect(item).toMatchObject({ kind: 'friend_request', read: false, data: { from: 'ABCD-EFGH', name: 'Ann' } });
    expect(lastOf(ws, 'notify_new')).toMatchObject({ item: { id: item?.id, kind: 'friend_request', read: false }, unread: 1 });
    expect((await extra.notifyList('P1')).map(r => r.id)).toEqual([item?.id as string]);
  });

  it('keeps items for players who are offline and lists them later', async () => {
    const { svc, make, online } = unit();
    await svc.push('P1', 'game_info', { what: 'season_end', season: '2026-Q4' });
    await svc.push('P1', 'error', { text: 'oops' });
    const fresh = make();
    const ws = online('P1');
    fresh.handle(ws, 'P1', { type: 'notify_list' });
    await flush();
    const list = lastOf(ws, 'notify_list');
    expect(list.items.map((i: any) => i.kind).sort()).toEqual(['error', 'game_info']);
    expect(list.unread).toBe(2);
  });

  it('lists newest first and counts unread', async () => {
    const { svc, clock, online } = unit();
    const ws = online('P1');
    await svc.push('P1', 'error', { text: 'one' });
    clock.t += 1000;
    await svc.push('P1', 'error', { text: 'two' });
    clock.t += 1000;
    await svc.push('P1', 'error', { text: 'three' });
    svc.handle(ws, 'P1', { type: 'notify_list' });
    await flush();
    const list = lastOf(ws, 'notify_list');
    expect(list.items.map((i: any) => i.data.text)).toEqual(['three', 'two', 'one']);
    expect(list.unread).toBe(3);
    expect(Object.keys(list.items[0]).sort()).toEqual(['at', 'data', 'id', 'kind', 'read']);
  });

  it('reads one, then all, and answers with a fresh list', async () => {
    const { svc, extra, online } = unit();
    const ws = online('P1');
    const a = await svc.push('P1', 'error', { text: 'a' });
    await svc.push('P1', 'error', { text: 'b' });
    svc.handle(ws, 'P1', { type: 'notify_read', id: a?.id });
    await flush();
    let list = lastOf(ws, 'notify_list');
    expect(list.unread).toBe(1);
    expect(list.items.find((i: any) => i.id === a?.id).read).toBe(true);
    svc.handle(ws, 'P1', { type: 'notify_read', all: true });
    await flush();
    list = lastOf(ws, 'notify_list');
    expect(list.unread).toBe(0);
    expect((await extra.notifyList('P1')).every(r => r.read)).toBe(true);
  });

  it('clears one, then all', async () => {
    const { svc, extra, online } = unit();
    const ws = online('P1');
    const a = await svc.push('P1', 'error', { text: 'a' });
    await svc.push('P1', 'error', { text: 'b' });
    await svc.push('P1', 'error', { text: 'c' });
    svc.handle(ws, 'P1', { type: 'notify_clear', id: a?.id });
    await flush();
    expect(lastOf(ws, 'notify_list').items).toHaveLength(2);
    svc.handle(ws, 'P1', { type: 'notify_clear', all: true });
    await flush();
    expect(lastOf(ws, 'notify_list')).toMatchObject({ items: [], unread: 0 });
    expect(await extra.notifyList('P1')).toEqual([]);
  });

  it('refuses read and clear without an id or all', async () => {
    const { svc, online } = unit();
    const ws = online('P1');
    await svc.push('P1', 'error', { text: 'a' });
    for (const type of ['notify_read', 'notify_clear']) {
      svc.handle(ws, 'P1', { type });
      await flush();
      expect(lastOf(ws, 'social_result')).toMatchObject({ action: type, ok: false, reason: 'bad_request' });
    }
    svc.handle(ws, 'P1', { type: 'notify_read', id: 5 });
    await flush();
    expect(lastOf(ws, 'social_result')).toMatchObject({ reason: 'bad_request' });
  });

  it('only touches the own items', async () => {
    const { svc, online } = unit();
    const w1 = online('P1'), w2 = online('P2');
    const a = await svc.push('P1', 'error', { text: 'mine' });
    svc.handle(w2, 'P2', { type: 'notify_clear', id: a?.id });
    await flush();
    svc.handle(w1, 'P1', { type: 'notify_list' });
    await flush();
    expect(lastOf(w1, 'notify_list').items).toHaveLength(1);
  });

  it('accepts every kind of the contract and nothing else', async () => {
    const { svc } = unit();
    for (const k of NOTIFY_KINDS) expect(await svc.push('P1', k, {})).not.toBeNull();
    expect(NOTIFY_KINDS).toEqual(['friend_request', 'friend_accepted', 'invite', 'game_info', 'match_voided', 'match_contested', 'error', 'friend_activity', 'gift']);
    expect(await svc.push('P1', 'spam' as never, {})).toBeNull();
  });

  it('cleans the data it keeps', () => {
    const data = cleanData({
      text: 'x'.repeat(500), n: 5, bad: Number.NaN, ok: true, nothing: null, 'Bad Key': 1, fn: () => 1,
      list: Array.from({ length: 20 }, (_, i) => i), nested: { a: 1, b: { deep: 1 }, c: 'z' },
    });
    expect((data.text as string).length).toBe(200);
    expect(data).toMatchObject({ n: 5, ok: true, nothing: null });
    expect(data.bad).toBeUndefined();
    expect(data['Bad Key']).toBeUndefined();
    expect(data.fn).toBeUndefined();
    expect(data.list).toHaveLength(12);
    expect(data.nested).toEqual({ a: 1, c: 'z' });
    expect(cleanData('nope')).toEqual({});
    expect(cleanData([1, 2])).toEqual({});
  });

  it('keeps stored data small', () => {
    const big: Record<string, unknown> = {};
    for (let i = 0; i < 40; i++) big[`k${String.fromCharCode(97 + (i % 26))}${i < 26 ? '' : 'x'}`] = 'y'.repeat(190);
    expect(JSON.stringify(cleanData(big)).length).toBeLessThanOrEqual(1200);
  });

  it('drops invites after fifteen minutes', async () => {
    const { svc, clock, extra, online } = unit();
    const ws = online('P1');
    await svc.push('P1', 'invite', { from: 'A', name: 'Ann', room: 'AB12', party: false });
    await svc.push('P1', 'error', { text: 'stays' });
    clock.t += INVITE_TTL_MS - 1;
    svc.handle(ws, 'P1', { type: 'notify_list' });
    await flush();
    expect(lastOf(ws, 'notify_list').items).toHaveLength(2);
    clock.t += 2;
    svc.handle(ws, 'P1', { type: 'notify_list' });
    await flush();
    expect(lastOf(ws, 'notify_list').items.map((i: any) => i.kind)).toEqual(['error']);
    expect((await extra.notifyList('P1')).map(r => r.kind)).toEqual(['error']);
  });

  it('never keeps more than 100 items and drops read ones first', async () => {
    const { svc, clock, online } = unit();
    const ws = online('P1');
    const first = await svc.push('P1', 'error', { text: 'first' });
    for (let i = 0; i < NOTIFY_MAX - 1; i++) { clock.t += 10; await svc.push('P1', 'error', { text: `n${i}` }); }
    svc.handle(ws, 'P1', { type: 'notify_read', id: first?.id });
    await flush();
    clock.t += 10;
    await svc.push('P1', 'error', { text: 'overflow' });
    svc.handle(ws, 'P1', { type: 'notify_list' });
    await flush();
    const items = lastOf(ws, 'notify_list').items;
    expect(items).toHaveLength(NOTIFY_MAX);
    expect(items.some((i: any) => i.id === first?.id)).toBe(false);
    expect(items[0].data.text).toBe('overflow');
  });

  it('trims an oversized stored inbox when it is loaded', async () => {
    const { svc, extra, make, online } = unit();
    for (let i = 0; i < 130; i++) extra.notifyAdd({ id: `x${i}`, pkey: 'P1', kind: 'error', at: 1000 + i, read: false, data: { text: `${i}` }, expires: null });
    const fresh = make();
    const ws = online('P1');
    fresh.handle(ws, 'P1', { type: 'notify_list' });
    await flush();
    expect(lastOf(ws, 'notify_list').items).toHaveLength(NOTIFY_MAX);
    expect((await extra.notifyList('P1')).length).toBe(NOTIFY_MAX);
    expect(svc).toBeDefined();
  });

  it('replaces an item with the same id and makes it unread again', async () => {
    const { svc, clock, online } = unit();
    const ws = online('P1');
    const first = await svc.push('P1', 'friend_request', { from: 'A', name: 'Ann' }, 'fr:A');
    svc.handle(ws, 'P1', { type: 'notify_read', all: true });
    await flush();
    clock.t += 1000;
    await svc.push('P1', 'friend_request', { from: 'A', name: 'Ann2' }, 'fr:A');
    svc.handle(ws, 'P1', { type: 'notify_list' });
    await flush();
    const list = lastOf(ws, 'notify_list');
    expect(list.items).toHaveLength(1);
    expect(list.items[0]).toMatchObject({ id: first?.id, read: false, data: { name: 'Ann2' } });
  });

  it('removes items by id and refreshes the client', async () => {
    const { svc, online } = unit();
    const ws = online('P1');
    await svc.push('P1', 'friend_request', { from: 'A' }, 'fr:A');
    await svc.push('P1', 'error', { text: 'x' });
    await svc.remove('P1', ['fr:A']);
    expect(lastOf(ws, 'notify_list').items.map((i: any) => i.kind)).toEqual(['error']);
  });
});

interface SocialFake extends SocialSocket { sent: Record<string, any>[]; target: InviteTarget | null }

describe('notifications from social events', () => {
  const A = 'a'.repeat(24), B = 'b'.repeat(24);

  function env() {
    const store = new MemoryStore();
    const clock = { t: Date.UTC(2026, 10, 2, 12) };
    const svc = new SocialService<SocialFake>(store, {
      send: (ws, d) => { ws.sent.push(d as Record<string, any>); },
      where: () => 'menu', inviteTarget: ws => ws.target, roomPeers: () => [],
    }, () => clock.t);
    const mk = (): SocialFake => ({ data: {}, sent: [], target: null });
    return { svc, clock, mk, extra: svc.extra as MemoryExtra };
  }

  async function go(svc: SocialService<SocialFake>, ws: SocialFake, type: string, more: Record<string, unknown> = {}) {
    svc.handle(ws, { type, ...more });
    await flush();
  }

  async function users() {
    const e = env();
    const a = e.mk(), b = e.mk();
    await go(e.svc, a, 'social_hello', { pkey: A, name: 'Ann' });
    await go(e.svc, b, 'social_hello', { pkey: B, name: 'Bob' });
    return { ...e, a, b };
  }

  it('hello sends the chat state and the inbox', async () => {
    const { a } = await users();
    expect(lastOf(a, 'chat_state')).toMatchObject({ enabled: false, allowed: null });
    expect(lastOf(a, 'notify_list')).toMatchObject({ items: [], unread: 0 });
  });

  it('a friend request reaches the other player and is stored', async () => {
    const { svc, a, b, extra } = await users();
    await go(svc, a, 'social_add', { code: friendCode(B) });
    expect(lastOf(b, 'notify_new')).toMatchObject({ item: { kind: 'friend_request', read: false, data: { from: friendCode(A), name: 'Ann' } }, unread: 1 });
    expect((await extra.notifyList(B)).map(r => r.kind)).toEqual(['friend_request']);
    expect(lastOf(a, 'notify_new')).toBeUndefined();
  });

  it('a request sent while the player is offline waits in the inbox', async () => {
    const { svc, a, b, mk } = await users();
    svc.drop(b);
    await go(svc, a, 'social_add', { code: friendCode(B) });
    const b2 = mk();
    await go(svc, b2, 'social_hello', { pkey: B, name: 'Bob' });
    expect(lastOf(b2, 'notify_list').items.map((i: any) => i.kind)).toEqual(['friend_request']);
    expect(lastOf(b2, 'notify_list').unread).toBe(1);
  });

  it('accepting tells the requester and removes the request from the inbox', async () => {
    const { svc, a, b } = await users();
    await go(svc, a, 'social_add', { code: friendCode(B) });
    await go(svc, b, 'social_accept', { code: friendCode(A) });
    expect(lastOf(a, 'notify_new')).toMatchObject({ item: { kind: 'friend_accepted', data: { from: friendCode(B), name: 'Bob' } } });
    expect(lastOf(b, 'notify_list').items).toEqual([]);
  });

  it('adding someone who already asked you accepts for both', async () => {
    const { svc, a, b } = await users();
    await go(svc, a, 'social_add', { code: friendCode(B) });
    await go(svc, b, 'social_add', { code: friendCode(A) });
    expect(lastOf(a, 'notify_new')).toMatchObject({ item: { kind: 'friend_accepted' } });
    expect(lastOf(b, 'notify_list').items).toEqual([]);
  });

  it('declining or removing clears the request', async () => {
    const { svc, a, b } = await users();
    await go(svc, a, 'social_add', { code: friendCode(B) });
    await go(svc, b, 'social_remove', { code: friendCode(A) });
    expect(lastOf(b, 'notify_list').items).toEqual([]);
    await go(svc, a, 'notify_list');
    expect(lastOf(a, 'notify_list').items).toEqual([]);
  });

  it('an invite carries the room code and a party flag', async () => {
    const { svc, a, b } = await users();
    await go(svc, a, 'social_add', { code: friendCode(B) });
    await go(svc, b, 'social_accept', { code: friendCode(A) });
    a.target = { code: 'ROOM', party: true };
    await go(svc, a, 'social_invite', { code: friendCode(B) });
    expect(lastOf(b, 'notify_new')).toMatchObject({ item: { kind: 'invite', data: { from: friendCode(A), name: 'Ann', room: 'ROOM', party: true } } });
    expect(lastOf(b, 'social_invite')).toMatchObject({ room: 'ROOM', party: true });
  });

  it('a rank up and the rewards of a ranked result become game info', async () => {
    const { svc, b } = await users();
    svc.onRanked(B, {
      type: 'ranked_result', promoted: true, after: { rp: 400, rank: 2, tier: 3 },
      unlocks: [{ id: 't_chips', name: 'Chip Stacker', type: 'title', rarity: 'common' }, { nope: 1 }],
    });
    await flush();
    const news = b.sent.filter(m => m.type === 'notify_new').map(m => m.item);
    expect(news.map(n => n.kind)).toEqual(['game_info', 'game_info']);
    expect(news[0].data).toMatchObject({ what: 'rank_up', rank: 2, tier: 3, rp: 400 });
    expect(news[1].data).toMatchObject({ what: 'reward', item: 't_chips', name: 'Chip Stacker' });
  });

  it('a ranked result without a promotion or unlocks says nothing', async () => {
    const { svc, b } = await users();
    svc.onRanked(B, { type: 'ranked_result', promoted: false, unlocks: [] });
    svc.onRanked(undefined, { type: 'ranked_result', promoted: true });
    svc.onRanked(B, { type: 'other', promoted: true });
    await flush();
    expect(b.sent.filter(m => m.type === 'notify_new')).toHaveLength(0);
  });

  it('other lanes can push match and season notices', async () => {
    const { svc, b } = await users();
    await svc.notify.push(B, 'match_voided', { match_id: 'm-1' });
    await svc.notify.push(B, 'match_contested', { match_id: 'm-2' });
    await svc.notify.push(B, 'game_info', { what: 'season_end', season: '2026-Q4', rank: 3 });
    const kinds = b.sent.filter(m => m.type === 'notify_new').map(m => m.item.kind);
    expect(kinds).toEqual(['match_voided', 'match_contested', 'game_info']);
    expect(lastOf(b, 'notify_new').unread).toBe(3);
  });
});

describe('match decision notices', () => {
  const noticeKinds = (ws: FakeWS) => ws.sent.filter(m => m.type === 'notify_new').map(m => m.item.kind);

  it('held tells every player the match is contested', async () => {
    const { svc, online } = unit();
    const a = online('pa'), b = online('pb');
    await notifyMatchDecision('m-1', 'held', ['pa', 'pb']);
    for (const ws of [a, b]) {
      const n = lastOf(ws, 'notify_new');
      expect(n.item.kind).toBe('match_contested');
      expect(n.item.data).toEqual({ match_id: 'm-1' });
      expect(n.item.read).toBe(false);
      expect(n.unread).toBe(1);
    }
    expect(((await svc.payload('pa')) as any).items).toHaveLength(1);
  });

  it('voided tells every player the match was voided and drops the contested notice', async () => {
    const { svc, online } = unit();
    const a = online('pa'), b = online('pb');
    await notifyMatchDecision('m-1', 'held', ['pa', 'pb']);
    await notifyMatchDecision('m-1', 'voided', ['pa', 'pb']);
    for (const ws of [a, b]) {
      expect(noticeKinds(ws)).toEqual(['match_contested', 'match_voided']);
      expect(lastOf(ws, 'notify_list').items).toEqual([]);
      const n = lastOf(ws, 'notify_new');
      expect(n.item.kind).toBe('match_voided');
      expect(n.item.data).toEqual({ match_id: 'm-1' });
      expect(n.unread).toBe(1);
    }
    expect(((await svc.payload('pa')) as any).items.map((i: any) => i.kind)).toEqual(['match_voided']);
  });

  it('sends nothing for any other status', async () => {
    const { svc, extra, online } = unit();
    const a = online('pa');
    for (const status of ['', 'apply', 'void', 'applied', 'HELD', ' held', 'Voided', 'contested', 'constructor', '__proto__', 'unknown']) {
      await svc.matchDecision('m-1', status, ['pa']);
    }
    expect(a.sent).toHaveLength(0);
    expect(await extra.notifyList('pa')).toHaveLength(0);
  });

  it('removes the contested notice when the review upholds the result', async () => {
    const { svc, online } = unit();
    const a = online('pa');
    await svc.matchDecision('m-1', 'held', ['pa']);
    const before = a.sent.length;
    await svc.matchDecision('m-1', 'applied', ['pa']);
    expect(a.sent.length).toBeGreaterThan(before);
    expect(((await svc.payload('pa')) as any).items).toEqual([]);
  });

  it('stores the notice for players who are offline', async () => {
    const { svc, extra } = unit();
    await notifyMatchDecision('m-9', 'held', ['pa']);
    await notifyMatchDecision('m-9', 'voided', ['pa']);
    const rows = await extra.notifyList('pa');
    expect(rows.map(r => r.kind)).toEqual(['match_voided']);
    expect(rows[0].id).toBe('mv:m-9');
    expect(((await svc.payload('pa')) as any).items).toHaveLength(1);
  });

  it('lists the same player once when the key repeats', async () => {
    const { svc, online } = unit();
    const a = online('pa');
    await svc.matchDecision('m-1', 'held', ['pa', 'pa', 'pa']);
    expect(noticeKinds(a)).toEqual(['match_contested']);
    expect(((await svc.payload('pa')) as any).items).toHaveLength(1);
  });

  it('a repeated verdict replaces the notice instead of stacking it', async () => {
    const { svc, online } = unit();
    online('pa');
    await svc.matchDecision('m-1', 'held', ['pa']);
    await svc.matchDecision('m-1', 'held', ['pa']);
    await svc.matchDecision('m-1', 'voided', ['pa']);
    await svc.matchDecision('m-1', 'voided', ['pa']);
    const items = ((await svc.payload('pa')) as any).items;
    expect(items.map((i: any) => i.kind)).toEqual(['match_voided']);
  });

  it('keeps different matches apart', async () => {
    const { svc, online } = unit();
    online('pa');
    await svc.matchDecision('m-1', 'held', ['pa']);
    await svc.matchDecision('m-2', 'held', ['pa']);
    await svc.matchDecision('m-1', 'voided', ['pa']);
    const items = ((await svc.payload('pa')) as any).items;
    expect(items.map((i: any) => `${i.kind}:${i.data.match_id}`).sort()).toEqual(['match_contested:m-2', 'match_voided:m-1']);
  });

  it('only reaches the first players up to the cap', async () => {
    const { svc, extra } = unit();
    const keys = Array.from({ length: DECISION_TARGETS_MAX + 20 }, (_, i) => `p${i}`);
    await svc.matchDecision('m-1', 'held', keys);
    let stored = 0;
    for (const k of keys) stored += (await extra.notifyList(k)).length;
    expect(stored).toBe(DECISION_TARGETS_MAX);
    expect((await extra.notifyList(keys[DECISION_TARGETS_MAX - 1])).length).toBe(1);
    expect((await extra.notifyList(keys[DECISION_TARGETS_MAX])).length).toBe(0);
  });

  it('counts the cap after duplicates are removed', async () => {
    const { svc, extra } = unit();
    const keys: string[] = [];
    for (let i = 0; i < DECISION_TARGETS_MAX; i++) keys.push(`p${i}`, `p${i}`);
    await svc.matchDecision('m-1', 'held', keys);
    for (let i = 0; i < DECISION_TARGETS_MAX; i++) expect((await extra.notifyList(`p${i}`)).length).toBe(1);
  });

  it('ignores bad ids, bad keys and bad lists without throwing', async () => {
    const { svc, extra } = unit();
    const bad: unknown[][] = [
      ['', 'held', ['pa']],
      ['   ', 'held', ['pa']],
      [null, 'held', ['pa']],
      [42, 'held', ['pa']],
      ['x'.repeat(DECISION_ID_MAX + 1), 'held', ['pa']],
      ['m-1', null, ['pa']],
      ['m-1', 7, ['pa']],
      ['m-1', 'held', null],
      ['m-1', 'held', 'pa'],
      ['m-1', 'held', {}],
      ['m-1', 'held', []],
      ['m-1', 'held', ['', null, 5, {}]],
    ];
    for (const args of bad) await (svc.matchDecision as any)(...args);
    for (const args of bad) await (notifyMatchDecision as any)(...args);
    expect(await extra.notifyList('pa')).toHaveLength(0);
  });

  it('keeps the notice id readable and clearable by the client', async () => {
    const { svc, online } = unit();
    const a = online('pa');
    const id = 'x'.repeat(DECISION_ID_MAX);
    await svc.matchDecision(id, 'held', ['pa']);
    const noticeId = lastOf(a, 'notify_new').item.id;
    expect(noticeId.length).toBeLessThanOrEqual(64);
    svc.handle(a, 'pa', { type: 'notify_clear', id: noticeId });
    await flush();
    expect(lastOf(a, 'notify_list').items).toHaveLength(0);
  });

  it('trims the match id', async () => {
    const { svc, online } = unit();
    const a = online('pa');
    await svc.matchDecision('  m-5  ', 'held', ['pa']);
    expect(lastOf(a, 'notify_new').item.data).toEqual({ match_id: 'm-5' });
    expect(lastOf(a, 'notify_new').item.id).toBe('mc:m-5');
  });

  it('a failing store for one player does not stop the others and never throws', async () => {
    const extra = new MemoryExtra();
    const logs: string[] = [];
    const socks = new Map<string, FakeWS[]>();
    const svc = new NotifyService<FakeWS>(extra, { socketsOf: k => socks.get(k) ?? [] }, {
      send: (ws, d) => { ws.sent.push(d as Record<string, any>); },
      log: (_l, m) => { logs.push(m); },
    });
    const good: FakeWS = { sent: [] };
    socks.set('pb', [good]);
    const real = extra.notifyAdd.bind(extra);
    extra.notifyAdd = r => { if (r.pkey === 'pa') throw new Error('disk full'); real(r); };
    await expect(notifyMatchDecision('m-1', 'held', ['pa', 'pb'])).resolves.toBeUndefined();
    expect(noticeKinds(good)).toEqual(['match_contested']);
    expect(logs.some(m => m.includes('match notice failed'))).toBe(true);
    await expect(notifyMatchDecision('m-1', 'voided', ['pa', 'pb'])).resolves.toBeUndefined();
    expect(noticeKinds(good)).toEqual(['match_contested', 'match_voided']);
    expect(((await svc.payload('pb')) as any).items.map((i: any) => i.kind)).toEqual(['match_voided']);
  });

  it('survives a log function that throws', async () => {
    const extra = new MemoryExtra();
    const svc = new NotifyService<FakeWS>(extra, { socketsOf: () => [] }, {
      send: () => undefined,
      log: () => { throw new Error('log down'); },
    });
    extra.notifyAdd = () => { throw new Error('boom'); };
    await expect(notifyMatchDecision('m-1', 'held', ['pa'])).resolves.toBeUndefined();
    await expect(svc.matchDecision('m-1', 'voided', ['pa'])).resolves.toBeUndefined();
  });

  it('the exported hook follows the newest service', async () => {
    const first = unit();
    const wsFirst = first.online('pa');
    const second = unit();
    const wsSecond = second.online('pa');
    await notifyMatchDecision('m-1', 'held', ['pa']);
    expect(noticeKinds(wsSecond)).toEqual(['match_contested']);
    expect(noticeKinds(wsFirst)).toEqual([]);
  });

  it('fits the onDecision hook type of the match log', async () => {
    type Hook = (id: string, status: 'held' | 'voided' | 'applied' | '', pkeys: string[]) => void;
    const hook: Hook = notifyMatchDecision;
    const { online } = unit();
    const a = online('pa');
    hook('m-1', 'held', ['pa']);
    await flush();
    await flush();
    expect(noticeKinds(a)).toEqual(['match_contested']);
  });
});
