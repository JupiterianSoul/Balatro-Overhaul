import { describe, it, expect } from 'bun:test';
import { SocialService, friendCode, searchKey, SEARCH_PER_WINDOW, SEARCH_LIMIT, PRESENCE_GAP_MS, type SocialSocket, type PresenceDetail } from './social';
import { MemoryStore } from './ranked_store';
import { rankTag } from './identity';

interface FakeWS extends SocialSocket { sent: Record<string, any>[]; detail: PresenceDetail | null }

const A = 'a'.repeat(24), B = 'b'.repeat(24), C = 'c'.repeat(24);
const key = (n: number) => `p${String(n).padStart(23, '0')}`;
const flush = () => new Promise(r => setTimeout(r, 0));

function sock(): FakeWS {
  return { data: {}, sent: [], detail: null };
}

function setup() {
  const store = new MemoryStore();
  const clock = { t: Date.UTC(2026, 10, 2, 12) };
  const svc = new SocialService<FakeWS>(store, {
    send: (ws, d) => { ws.sent.push(d as Record<string, any>); },
    where: ws => ws.detail?.where ?? 'menu',
    detail: ws => ws.detail,
    inviteTarget: () => null,
    roomPeers: () => [],
  }, () => clock.t);
  return { store, clock, svc };
}

type Env = ReturnType<typeof setup>;

function last(ws: FakeWS, type: string): any {
  return [...ws.sent].reverse().find(m => m.type === type);
}

function all(ws: FakeWS, type: string) {
  return ws.sent.filter(m => m.type === type);
}

async function send(env: Env, ws: FakeWS, type: string, extra: Record<string, unknown> = {}) {
  env.svc.handle(ws, { type, ...extra });
  await flush();
}

async function hello(env: Env, ws: FakeWS, pkey: string, name: string) {
  await send(env, ws, 'social_hello', { pkey, name });
}

async function befriend(env: Env, a: FakeWS, aKey: string, b: FakeWS, bKey: string) {
  await send(env, a, 'social_add', { code: friendCode(bKey) });
  await send(env, b, 'social_accept', { code: friendCode(aKey) });
}

async function crowd(env: Env, names: string[]) {
  const out: FakeWS[] = [];
  for (let i = 0; i < names.length; i++) {
    const ws = sock();
    await hello(env, ws, key(i + 1), names[i]);
    out.push(ws);
  }
  return out;
}

function names(ws: FakeWS): string[] {
  return (last(ws, 'social_search_result')?.results ?? []).map((r: any) => r.name);
}

describe('friend search by name', () => {
  it('needs at least two letters', async () => {
    const env = setup();
    const [me] = await crowd(env, ['Me', 'ZOB']);
    for (const q of ['z', ' z ', '', undefined, 5]) {
      await send(env, me, 'social_search', { q });
      expect(last(me, 'social_result')).toMatchObject({ action: 'social_search', ok: false, reason: 'too_short' });
    }
    env.clock.t += 11_000;
    await send(env, me, 'social_search', { q: 'zo' });
    expect(names(me)).toEqual(['ZOB']);
  });

  it('ignores case and matches the start or any part of a name', async () => {
    const env = setup();
    const [me] = await crowd(env, ['Me', 'ZOB', 'zoe', 'Lizzo', 'Bob']);
    for (const q of ['zo', 'ZO', 'Zo']) {
      env.clock.t += 11_000;
      await send(env, me, 'social_search', { q });
      expect(names(me).sort()).toEqual(['Lizzo', 'ZOB', 'zoe'].sort());
    }
  });

  it('leaves out yourself', async () => {
    const env = setup();
    const [me] = await crowd(env, ['Zorro', 'Zane', 'Zed']);
    await send(env, me, 'social_search', { q: 'z' + 'o' });
    expect(names(me)).toEqual([]);
    env.clock.t += 11_000;
    await send(env, me, 'social_search', { q: 'za' });
    expect(names(me)).toEqual(['Zane']);
  });

  it('ranks exact, then prefix, then word start, then the rest', async () => {
    const env = setup();
    const [me] = await crowd(env, ['Me', 'lizzo', 'big zo', 'zoom', 'zo']);
    await send(env, me, 'social_search', { q: 'zo' });
    expect(names(me)).toEqual(['zo', 'zoom', 'big zo', 'lizzo']);
  });

  it('ranks online players above offline ones with the same match', async () => {
    const env = setup();
    const [me, , off] = await crowd(env, ['Me', 'zoa', 'zob']);
    env.svc.drop(off);
    await send(env, me, 'social_search', { q: 'zo' });
    const res = last(me, 'social_search_result').results;
    expect(res.map((r: any) => [r.name, r.online])).toEqual([['zoa', true], ['zob', false]]);
  });

  it('finds players who are offline', async () => {
    const env = setup();
    const [me, bob] = await crowd(env, ['Me', 'Robert']);
    env.svc.drop(bob);
    await send(env, me, 'social_search', { q: 'robe' });
    expect(last(me, 'social_search_result').results).toMatchObject([{ name: 'Robert', online: false, friend: false, pending: false }]);
  });

  it('ignores accents and capitals in both the name and the search', async () => {
    const env = setup();
    const [me] = await crowd(env, ['Me', 'Zoë', 'ÉMILE']);
    await send(env, me, 'social_search', { q: 'zoe' });
    expect(names(me)).toEqual(['Zoë']);
    env.clock.t += 11_000;
    await send(env, me, 'social_search', { q: 'ZOË' });
    expect(names(me)).toEqual(['Zoë']);
    env.clock.t += 11_000;
    await send(env, me, 'social_search', { q: 'emile' });
    expect(names(me)).toEqual(['ÉMILE']);
    expect(searchKey('  Zoë  ')).toBe('zoe');
  });

  it('marks friends and pending requests', async () => {
    const env = setup();
    const [me, a, b, c] = await crowd(env, ['Me', 'Zeta friend', 'Zeta sent', 'Zeta asked']);
    await befriend(env, me, key(1), a, key(2));
    await send(env, me, 'social_add', { code: friendCode(key(3)) });
    await send(env, c, 'social_add', { code: friendCode(key(1)) });
    await send(env, me, 'social_search', { q: 'zeta' });
    const by = Object.fromEntries(last(me, 'social_search_result').results.map((r: any) => [r.name, r]));
    expect(by['Zeta friend']).toMatchObject({ friend: true, pending: false });
    expect(by['Zeta sent']).toMatchObject({ friend: false, pending: true, incoming: false });
    expect(by['Zeta asked']).toMatchObject({ friend: false, pending: true, incoming: true });
    expect(b.sent.length).toBeGreaterThan(0);
  });

  it('answers with the query, the code and the rank but never the key', async () => {
    const env = setup();
    const [me, bob] = await crowd(env, ['Me', 'Bobby']);
    bob.data.rp = 0;
    await send(env, me, 'social_search', { q: '  Bob ' });
    const msg = last(me, 'social_search_result');
    expect(msg.q).toBe('Bob');
    expect(msg.results[0].code).toBe(friendCode(key(2)));
    expect(Object.keys(msg.results[0]).sort()).toEqual(['code', 'friend', 'incoming', 'name', 'online', 'pending', 'rank']);
    expect(JSON.stringify(msg)).not.toContain(key(2));
    expect(msg.results[0].rank).toEqual(rankTag(0));
  });

  it('is rate limited', async () => {
    const env = setup();
    const [me] = await crowd(env, ['Me', 'Bob']);
    for (let i = 0; i < SEARCH_PER_WINDOW; i++) await send(env, me, 'social_search', { q: 'bo' });
    await send(env, me, 'social_search', { q: 'bo' });
    expect(last(me, 'social_result')).toMatchObject({ action: 'social_search', ok: false, reason: 'slow_down' });
    env.clock.t += 10_001;
    await send(env, me, 'social_search', { q: 'bo' });
    expect(names(me)).toEqual(['Bob']);
  });

  it('returns at most 20 results', async () => {
    const env = setup();
    const list = ['Me'];
    for (let i = 0; i < 30; i++) list.push(`Zed${String(i).padStart(2, '0')}`);
    const [me] = await crowd(env, list);
    await send(env, me, 'social_search', { q: 'zed' });
    expect(names(me)).toHaveLength(SEARCH_LIMIT);
  });

  it('treats percent and underscore as plain characters', async () => {
    const env = setup();
    const [me] = await crowd(env, ['Me', 'a_b', 'axb', '100%']);
    await send(env, me, 'social_search', { q: 'a_' });
    expect(names(me)).toEqual(['a_b']);
    env.clock.t += 11_000;
    await send(env, me, 'social_search', { q: '0%' });
    expect(names(me)).toEqual(['100%']);
  });

  it('needs a hello first', async () => {
    const env = setup();
    const a = sock();
    await send(env, a, 'social_search', { q: 'bob' });
    expect(last(a, 'social_result')).toMatchObject({ ok: false, reason: 'no_key' });
  });
});

describe('presence', () => {
  async function friends() {
    const env = setup();
    const a = sock(), b = sock();
    await hello(env, a, A, 'Ann');
    await hello(env, b, B, 'Bob');
    await befriend(env, a, A, b, B);
    return { env, a, b };
  }

  it('lists online, status, last seen, rank and unread for each friend', async () => {
    const { env, a, b } = await friends();
    b.data.rp = 0;
    await send(env, a, 'social_list');
    const f = last(a, 'social_list').friends[0];
    expect(f).toMatchObject({ code: friendCode(B), name: 'Bob', where: 'menu', online: true, status: { where: 'menu' }, last_seen: env.clock.t, unread: 0 });
    expect(f.rank).toEqual(rankTag(0));
  });

  it('shows offline friends with the time they were last seen', async () => {
    const { env, a, b } = await friends();
    const left = env.clock.t + 5000;
    env.clock.t = left;
    env.svc.drop(b);
    env.clock.t += 60_000;
    await send(env, a, 'social_list');
    expect(last(a, 'social_list').friends[0]).toMatchObject({ online: false, status: { where: 'offline' }, where: 'offline', last_seen: left });
  });

  it('derives lobby and match status from the room', async () => {
    const { env, a, b } = await friends();
    b.detail = { where: 'lobby', mode: 'faceoff', room: 'AB12' };
    await send(env, a, 'social_list');
    expect(last(a, 'social_list').friends[0].status).toEqual({ where: 'lobby', mode: 'faceoff', room: 'AB12' });
    b.detail = { where: 'match', mode: 'nemesis', ante: 4, opponents: ['Zed'], room: 'AB12' };
    await send(env, a, 'social_list');
    expect(last(a, 'social_list').friends[0]).toMatchObject({ where: 'match', status: { where: 'match', mode: 'nemesis', ante: 4, opponents: ['Zed'], room: 'AB12' } });
  });

  it('caps the opponent names at eight', async () => {
    const { env, a, b } = await friends();
    b.detail = { where: 'match', mode: 'br', ante: 2, opponents: Array.from({ length: 12 }, (_, i) => `P${i}`) };
    await send(env, a, 'social_list');
    expect(last(a, 'social_list').friends[0].status.opponents).toHaveLength(8);
  });

  it('shows browsing and spectating as reported by the client', async () => {
    const { env, a, b } = await friends();
    await send(env, b, 'social_status', { where: 'browsing' });
    await send(env, a, 'social_list');
    expect(last(a, 'social_list').friends[0]).toMatchObject({ where: 'menu', status: { where: 'browsing' } });
    await send(env, b, 'social_status', { where: 'spectating' });
    await send(env, a, 'social_list');
    expect(last(a, 'social_list').friends[0].status).toEqual({ where: 'spectating' });
    await send(env, b, 'social_status', { where: 'menu' });
    await send(env, a, 'social_list');
    expect(last(a, 'social_list').friends[0].status).toEqual({ where: 'menu' });
  });

  it('a solo run shows as solo and counts as menu for old clients', async () => {
    const { env, a, b } = await friends();
    await send(env, b, 'social_status', { where: 'solo' });
    await send(env, a, 'social_list');
    expect(last(a, 'social_list').friends[0]).toMatchObject({ where: 'menu', status: { where: 'solo' } });
    await send(env, b, 'social_status', { where: 'menu' });
    await send(env, a, 'social_list');
    expect(last(a, 'social_list').friends[0].status).toEqual({ where: 'menu' });
  });

  it('ignores states the client may not report', async () => {
    const { env, a, b } = await friends();
    for (const where of ['match', 'lobby', 'offline', 'god', 5, undefined]) await send(env, b, 'social_status', { where });
    await send(env, a, 'social_list');
    expect(last(a, 'social_list').friends[0].status).toEqual({ where: 'menu' });
  });

  it('what the server sees in the room wins over what the client said', async () => {
    const { env, a, b } = await friends();
    await send(env, b, 'social_status', { where: 'browsing' });
    b.detail = { where: 'lobby', mode: 'attrition' };
    await send(env, a, 'social_list');
    expect(last(a, 'social_list').friends[0].status.where).toBe('lobby');
  });

  it('pushes a change to online friends on the next tick, once', async () => {
    const { env, a, b } = await friends();
    env.svc.tick();
    const before = all(a, 'social_presence').length;
    b.detail = { where: 'match', mode: 'faceoff', ante: 3, opponents: ['Zed'], room: 'XY99' };
    env.clock.t += PRESENCE_GAP_MS;
    env.svc.tick();
    env.svc.tick();
    const pushed = all(a, 'social_presence');
    expect(pushed).toHaveLength(before + 1);
    expect(pushed[pushed.length - 1]).toMatchObject({
      code: friendCode(B), online: true, last_seen: env.clock.t,
      status: { where: 'match', mode: 'faceoff', ante: 3, opponents: ['Zed'], room: 'XY99' },
    });
    expect(all(b, 'social_presence').filter(m => m.code === friendCode(B))).toHaveLength(0);
  });

  it('pushes the ante as it changes but not faster than the gap', async () => {
    const { env, a, b } = await friends();
    env.clock.t += PRESENCE_GAP_MS;
    b.detail = { where: 'match', mode: 'nemesis', ante: 1 };
    env.svc.tick();
    const base = all(a, 'social_presence').length;
    b.detail = { where: 'match', mode: 'nemesis', ante: 2 };
    env.clock.t += 500;
    env.svc.tick();
    expect(all(a, 'social_presence')).toHaveLength(base);
    env.clock.t += PRESENCE_GAP_MS;
    env.svc.tick();
    expect(all(a, 'social_presence')).toHaveLength(base + 1);
    expect(last(a, 'social_presence').status.ante).toBe(2);
  });

  it('pushes right after the client reports a state', async () => {
    const { env, a, b } = await friends();
    env.clock.t += PRESENCE_GAP_MS;
    await send(env, b, 'social_status', { where: 'browsing' });
    expect(last(a, 'social_presence')).toMatchObject({ code: friendCode(B), online: true, status: { where: 'browsing' } });
  });

  it('tells friends when someone comes online and when they leave', async () => {
    const env = setup();
    const a = sock(), b = sock();
    await hello(env, a, A, 'Ann');
    await hello(env, b, B, 'Bob');
    await befriend(env, a, A, b, B);
    env.svc.drop(b);
    expect(last(a, 'social_presence')).toMatchObject({ code: friendCode(B), online: false, status: { where: 'offline' }, last_seen: env.clock.t });
    env.clock.t += 5000;
    const b2 = sock();
    await hello(env, b2, B, 'Bob');
    env.svc.tick();
    expect(last(a, 'social_presence')).toMatchObject({ code: friendCode(B), online: true, status: { where: 'menu' } });
  });

  it('does not tell strangers or pending requests', async () => {
    const env = setup();
    const a = sock(), b = sock(), c = sock();
    await hello(env, a, A, 'Ann');
    await hello(env, b, B, 'Bob');
    await hello(env, c, C, 'Cy');
    await send(env, a, 'social_add', { code: friendCode(B) });
    env.clock.t += PRESENCE_GAP_MS;
    a.detail = { where: 'lobby', mode: 'attrition' };
    env.svc.tick();
    expect(all(b, 'social_presence')).toHaveLength(0);
    expect(all(c, 'social_presence')).toHaveLength(0);
  });

  it('shows the busiest state when a player has two connections', async () => {
    const { env, a, b } = await friends();
    const b2 = sock();
    await hello(env, b2, B, 'Bob');
    b2.detail = { where: 'lobby', mode: 'br' };
    await send(env, a, 'social_list');
    expect(last(a, 'social_list').friends[0].status).toEqual({ where: 'lobby', mode: 'br' });
    expect(b.sent.length).toBeGreaterThan(0);
  });

  it('remembers the rank of a friend who left', async () => {
    const { env, a, b } = await friends();
    b.data.rp = 1800;
    env.svc.drop(b);
    await send(env, a, 'social_list');
    expect(last(a, 'social_list').friends[0].rank).toEqual(rankTag(1800));
    expect(last(a, 'social_presence').rank).toEqual(rankTag(1800));
  });

  it('loads the stored rank of offline friends after a restart', async () => {
    const { env, b } = await friends();
    b.data.rp = 900;
    env.svc.drop(b);
    const fresh = new SocialService<FakeWS>(env.store, {
      send: (ws, d) => { ws.sent.push(d as Record<string, any>); }, where: () => 'menu', inviteTarget: () => null, roomPeers: () => [],
    }, () => env.clock.t, env.svc.extra);
    const a2 = sock();
    await hello({ ...env, svc: fresh }, a2, A, 'Ann');
    expect(last(a2, 'social_list').friends[0]).toMatchObject({ online: false });
    expect(last(a2, 'social_list').friends[0].rank).toEqual(rankTag(900));
  });
});

describe('current name', () => {
  it('gives the latest name of a player, online or after a restart', async () => {
    const env = setup();
    const a = sock();
    await hello(env, a, key(1), 'Old');
    await hello(env, a, key(1), 'BALATRITO');
    expect(await env.svc.currentName(key(1))).toBe('BALATRITO');
    expect(await env.svc.currentName(key(2))).toBe(null);
    const fresh = new SocialService<FakeWS>(env.store, {
      send: (ws, d) => { ws.sent.push(d as Record<string, any>); }, where: () => 'menu', inviteTarget: () => null, roomPeers: () => [],
    }, () => env.clock.t, env.svc.extra);
    expect(await fresh.currentName(key(1))).toBe('BALATRITO');
  });
});
