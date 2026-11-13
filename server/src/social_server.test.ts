import { describe, it, expect, afterAll } from 'bun:test';
import { startServer } from './index';

type Msg = Record<string, any>;
const srv = startServer(0);
afterAll(() => srv.stop(true));

interface C { msgs: Msg[]; send: (m: Msg) => void; wait: (t: string, f?: (m: Msg) => boolean, ms?: number) => Promise<Msg>; last: (t: string) => Msg | undefined; close: () => void }

function decode(raw: string): Msg {
  const p = JSON.parse(raw) as Msg;
  if (p.z === 1 && typeof p.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(p.d, 'base64'))).toString('utf8')) as Msg;
  return p;
}

async function connect(): Promise<C> {
  const ws = new WebSocket(`ws://127.0.0.1:${srv.port}/ws`);
  const msgs: Msg[] = [];
  const waiters: { pred: (m: Msg) => boolean; resolve: (m: Msg) => void }[] = [];
  ws.onmessage = (ev) => {
    const m = decode(String(ev.data));
    msgs.push(m);
    for (let i = waiters.length - 1; i >= 0; i--) if (waiters[i].pred(m)) { waiters[i].resolve(m); waiters.splice(i, 1); }
  };
  await new Promise<void>((res, rej) => { ws.onopen = () => res(); ws.onerror = () => rej(new Error('ws')); });
  return {
    msgs,
    send: (m) => ws.send(JSON.stringify(m)),
    wait: (t, f = () => true, ms = 2000) => {
      const pred = (m: Msg) => m.type === t && f(m);
      const i = msgs.findIndex(pred);
      if (i >= 0) return Promise.resolve(msgs.splice(i, 1)[0]);
      return new Promise<Msg>((res, rej) => {
        const to = setTimeout(() => rej(new Error('timeout ' + t)), ms);
        waiters.push({ pred, resolve: (m) => { clearTimeout(to); msgs.splice(msgs.indexOf(m), 1); res(m); } });
      });
    },
    last: (t) => [...msgs].reverse().find(m => m.type === t),
    close: () => ws.close(),
  };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let uid = 0;
const nm = () => `Soc${++uid}x${Math.floor(Math.random() * 1e6)}`;
const pk = () => Array.from({ length: 24 }, () => 'abcdefghijklmnopqrstuvwxyz0123456789'[Math.floor(Math.random() * 36)]).join('');

interface User { c: C; name: string; pkey: string; code: string }

async function user(optIn = true): Promise<User> {
  const c = await connect();
  const name = nm();
  const pkey = pk();
  c.send({ type: 'social_hello', pkey, name });
  const me = await c.wait('social_me');
  await c.wait('notify_list');
  if (optIn) {
    c.send({ type: 'chat_optin', enabled: true, birth_year: 1990 });
    await c.wait('chat_state', (m) => m.enabled === true);
  }
  return { c, name, pkey, code: me.code as string };
}

async function befriend(a: User, b: User): Promise<void> {
  a.c.send({ type: 'social_add', code: b.code });
  await b.c.wait('social_list', (m) => m.requests.length > 0);
  b.c.send({ type: 'social_accept', code: a.code });
  await a.c.wait('social_list', (m) => m.friends.length > 0);
}

async function friendOf(viewer: User, friend: User): Promise<Msg> {
  for (let i = viewer.c.msgs.length - 1; i >= 0; i--) if (viewer.c.msgs[i].type === 'social_list') viewer.c.msgs.splice(i, 1);
  viewer.c.send({ type: 'social_list' });
  const list = await viewer.c.wait('social_list');
  return list.friends.find((f: Msg) => f.code === friend.code) as Msg;
}

describe('social over a real server', () => {
  it('friends see lobby and match status from the room', async () => {
    const a = await user(), b = await user(), c = await user();
    await befriend(a, b);
    expect((await friendOf(b, a)).status).toEqual({ where: 'menu' });
    a.c.send({ type: 'create_room', visibility: 'public', name: a.name });
    const created = await a.c.wait('room_created');
    await sleep(50);
    const lobby = await friendOf(b, a);
    expect(lobby).toMatchObject({ online: true, where: 'lobby', status: { where: 'lobby', mode: 'attrition', room: created.code } });
    c.c.send({ type: 'join_room', code: created.code, name: c.name });
    await c.c.wait('room_ready');
    await sleep(50);
    const full = await friendOf(b, a);
    expect(full.status.where).toBe('lobby');
    expect(full.status.room).toBeUndefined();
    a.c.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'attrition', starting_lives: 3, pvp_start_round: 1 }, player_name: a.name });
    await a.c.wait('match_state_update', (m) => m.event === 'match_started');
    await sleep(50);
    const playing = await friendOf(b, a);
    expect(playing).toMatchObject({ where: 'match', status: { where: 'match', mode: 'attrition', opponents: [c.name] } });
    expect(typeof playing.status.ante).toBe('number');
    expect(playing.status.room).toBe(created.code);
    for (const u of [a, b, c]) u.c.close();
  });

  it('a 1v1 match with spectators off gives friends no room to watch', async () => {
    const a = await user(), b = await user(), c = await user();
    await befriend(a, b);
    a.c.send({ type: 'create_room', visibility: 'public', name: a.name });
    const created = await a.c.wait('room_created');
    c.c.send({ type: 'join_room', code: created.code, name: c.name });
    await c.c.wait('room_ready');
    a.c.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'attrition', starting_lives: 3, pvp_start_round: 1, spectate: false }, player_name: a.name });
    await a.c.wait('match_state_update', (m) => m.event === 'match_started');
    await sleep(50);
    const playing = await friendOf(b, a);
    expect(playing.status.where).toBe('match');
    expect(playing.status.room).toBeUndefined();
    for (const u of [a, b, c]) u.c.close();
  });

  it('friends see a party lobby and a running party', async () => {
    const a = await user(), b = await user();
    await befriend(a, b);
    a.c.send({ type: 'party_create', name: a.name, kind: 'br' });
    const joined = await a.c.wait('party_joined');
    await sleep(50);
    const lobby = await friendOf(b, a);
    expect(lobby.status).toMatchObject({ where: 'lobby', mode: 'br', room: joined.code });
    a.c.close(); b.c.close();
  });

  it('search finds a player by part of the name', async () => {
    const a = await user(), b = await user();
    a.c.send({ type: 'social_search', q: b.name.slice(1, 7).toLowerCase() });
    const res = await a.c.wait('social_search_result');
    expect(res.results.map((r: Msg) => r.code)).toContain(b.code);
    expect(JSON.stringify(res)).not.toContain(b.pkey);
    a.c.close(); b.c.close();
  });

  it('direct messages go to a friend and show as unread', async () => {
    const a = await user(), b = await user();
    await befriend(a, b);
    a.c.send({ type: 'chat_dm_send', to: b.code, text: 'hello there' });
    const got = await b.c.wait('chat_dm');
    expect(got).toMatchObject({ from: a.code, to: b.code, text: 'hello there' });
    expect((await friendOf(b, a)).unread).toBe(1);
    b.c.send({ type: 'chat_dm_read', with: a.code });
    await b.c.wait('chat_result', (m) => m.action === 'read');
    expect((await friendOf(b, a)).unread).toBe(0);
    a.c.close(); b.c.close();
  });

  it('chat in a 1v1 room reaches both players', async () => {
    const a = await user(), b = await user();
    a.c.send({ type: 'create_room', visibility: 'public', name: a.name });
    const created = await a.c.wait('room_created');
    b.c.send({ type: 'join_room', code: created.code, name: b.name });
    await b.c.wait('room_ready');
    b.c.send({ type: 'chat_lobby_send', text: 'good luck' });
    for (const u of [a, b]) expect(await u.c.wait('chat_lobby')).toMatchObject({ pid: 1, name: b.name, text: 'good luck' });
    a.c.close(); b.c.close();
  });

  it('chat in a party reaches the players who turned it on', async () => {
    const a = await user(), b = await user(), c = await user(false);
    a.c.send({ type: 'party_create', name: a.name, kind: 'br' });
    const joined = await a.c.wait('party_joined');
    for (const u of [b, c]) {
      u.c.send({ type: 'party_join', code: joined.code, name: u.name });
      await u.c.wait('party_joined');
    }
    a.c.send({ type: 'chat_lobby_send', text: 'ready when you are' });
    expect(await a.c.wait('chat_lobby')).toMatchObject({ pid: 0, name: a.name });
    expect(await b.c.wait('chat_lobby')).toMatchObject({ pid: 0, text: 'ready when you are' });
    await sleep(80);
    expect(c.c.last('chat_lobby')).toBeUndefined();
    for (const u of [a, b, c]) u.c.close();
  });

  it('chat without a room is refused', async () => {
    const a = await user();
    a.c.send({ type: 'chat_lobby_send', text: 'anyone?' });
    const r = await a.c.wait('chat_result');
    expect(r).toMatchObject({ action: 'send', ok: false, reason: 'no_lobby' });
    a.c.close();
  });
});
