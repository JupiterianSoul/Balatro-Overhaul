import { describe, it, expect, afterAll } from 'bun:test';
import { RecentPlayers, MemoryRecent, cleanMode, RECENT_KEEP, RECENT_GAP_MS, type RecentLink } from './recent_players';
import { startServer } from './index';

type Msg = Record<string, any>;
interface W { data: { recentAt?: number }; sent: Msg[] }

const key = (n: number | string) => `k${String(n).padStart(23, '0')}`;

function setup(links: Record<string, Partial<RecentLink>> = {}) {
  const clock = { t: 1_000_000 };
  const store = new MemoryRecent();
  const svc = new RecentPlayers<W>(store, {
    send: (ws, d) => { ws.sent.push(d as Msg); },
    describe: async (_me, others) => new Map(others.map(o => [o, { code: `C-${o.slice(-3)}`, name: '', online: false, friend: false, pending: false, incoming: false, ...links[o] }])),
  }, () => clock.t);
  const sock = (): W => ({ data: {}, sent: [] });
  const flush = () => new Promise(r => setTimeout(r, 5));
  return { clock, store, svc, sock, flush };
}

describe('recent players', () => {
  it('keeps each human pair, newest first, with the mode', async () => {
    const { clock, svc, sock, flush } = setup();
    svc.met([{ pkey: key(1), name: 'Ann' }, { pkey: key(2), name: 'Ben' }], 'attrition');
    clock.t += 1000;
    svc.met([{ pkey: key(1), name: 'Ann' }, { pkey: key(3), name: 'Cal' }, { pkey: key(4), name: 'Dee' }], 'br', false);
    await flush();
    clock.t += RECENT_GAP_MS;
    const ws = sock();
    await svc.handle(ws, key(1), { type: 'social_recent' });
    const items = ws.sent[0].items as Msg[];
    expect(items.map(i => [i.name, i.mode])).toEqual([['Cal', 'br'], ['Dee', 'br'], ['Ben', 'attrition']]);
    const ws2 = sock();
    await svc.handle(ws2, key(3), { type: 'social_recent' });
    expect((ws2.sent[0].items as Msg[]).map(i => i.name)).toEqual(['Ann', 'Dee']);
  });

  it('skips bots, bad keys, duplicates and a lone human', async () => {
    const { svc, store, flush } = setup();
    svc.met([{ pkey: key(1), name: 'Ann' }, { pkey: 'bot', name: 'Bot' }], 'attrition');
    svc.met([{ pkey: key(1), name: 'Ann' }, { pkey: key(1), name: 'Ann' }], 'attrition');
    await flush();
    expect(store.rows.size).toBe(0);
  });

  it('keeps only the last 20 per player and updates a repeat', async () => {
    const { clock, svc, store, flush } = setup();
    for (let i = 0; i < RECENT_KEEP + 5; i++) {
      clock.t += 10;
      svc.met([{ pkey: key('me'), name: 'Me' }, { pkey: key(100 + i), name: `P${i}` }], 'attrition');
    }
    clock.t += 10;
    svc.met([{ pkey: key('me'), name: 'Me' }, { pkey: key(110), name: 'P10 again' }], 'nemesis', true);
    await flush();
    const list = await store.list(key('me'));
    expect(list.length).toBe(RECENT_KEEP);
    expect(list[0]).toMatchObject({ name: 'P10 again', mode: 'nemesis', ranked: true });
    expect(list.some(r => r.other === key(100))).toBe(false);
  });

  it('marks friends and requests, rate limits and cleans the mode', async () => {
    const { clock, svc, sock, flush } = setup({ [key(2)]: { friend: true, online: true, name: 'Ben now' }, [key(3)]: { pending: true, incoming: true } });
    svc.met([{ pkey: key(1), name: 'Ann' }, { pkey: key(2), name: 'Ben' }, { pkey: key(3), name: 'Cal' }], 'Bad Mode!');
    await flush();
    const ws = sock();
    await svc.handle(ws, key(1), { type: 'social_recent' });
    await svc.handle(ws, key(1), { type: 'social_recent' });
    expect(ws.sent.length).toBe(1);
    const items = ws.sent[0].items as Msg[];
    const ben = items.find(i => i.code === `C-${key(2).slice(-3)}`) as Msg;
    expect(ben).toMatchObject({ name: 'Ben now', friend: true, online: true, mode: 'match' });
    expect(ben.pending).toBeUndefined();
    expect(items.find(i => i.name === 'Cal')).toMatchObject({ pending: true, incoming: true });
    clock.t += RECENT_GAP_MS;
    await svc.handle(ws, key(1), { type: 'social_recent' });
    expect(ws.sent.length).toBe(2);
    expect(cleanMode('nemesis')).toBe('nemesis');
    expect(cleanMode(5)).toBe('match');
  });
});

describe('head to head', () => {
  it('counts 1v1 wins, losses and draws for both players, and skips bots', async () => {
    const { clock, svc, store, sock, flush } = setup();
    svc.played([{ pkey: key(1), result: 'win' }, { pkey: key(2), result: 'lose' }]);
    svc.played([{ pkey: key(1), result: 'win' }, { pkey: key(2), result: 'lose' }]);
    svc.played([{ pkey: key(1), result: 'lose' }, { pkey: key(2), result: 'win' }]);
    svc.played([{ pkey: key(1), result: 'draw' }, { pkey: key(2), result: 'draw' }]);
    svc.played([{ pkey: key(1), result: 'win' }, { pkey: key(3), bot: true, result: 'lose' }]);
    svc.played([{ pkey: key(1), result: 'win' }, { pkey: key(1), result: 'lose' }]);
    svc.played([{ pkey: key(1), result: 'win' }]);
    await flush();
    expect(await store.records(key(1), [key(2), key(3)])).toMatchObject([{ other: key(2), w: 2, l: 1, d: 1 }]);
    expect(await store.records(key(2), [key(1)])).toMatchObject([{ other: key(1), w: 1, l: 2, d: 1 }]);
    svc.met([{ pkey: key(1), name: 'Ann' }, { pkey: key(2), name: 'Ben' }], 'nemesis');
    await flush();
    clock.t += RECENT_GAP_MS;
    const ws = sock();
    await svc.handle(ws, key(1), { type: 'social_recent' });
    expect((ws.sent[0].items as Msg[])[0].h2h).toEqual({ w: 2, l: 1, d: 1 });
  });

  it('sends the record against each friend', async () => {
    const clock = { t: 1_000_000 };
    const store = new MemoryRecent();
    const svc = new RecentPlayers<W>(store, {
      send: (ws, d) => { ws.sent.push(d as Msg); },
      describe: async () => new Map(),
      friends: async () => [{ pkey: key(2), code: 'BBBB-2222' }, { pkey: key(3), code: 'CCCC-3333' }],
    }, () => clock.t);
    svc.played([{ pkey: key(1), result: 'lose' }, { pkey: key(2), result: 'win' }]);
    await new Promise(r => setTimeout(r, 5));
    const ws: W = { data: {}, sent: [] };
    await svc.handle(ws, key(1), { type: 'social_h2h' });
    await svc.handle(ws, key(1), { type: 'social_h2h' });
    expect(ws.sent).toEqual([{ type: 'social_h2h', items: { 'BBBB-2222': { w: 0, l: 1, d: 0 } } }]);
  });
});

describe('recent players over a real server', () => {
  const srv = startServer(0);
  afterAll(() => srv.stop(true));

  function decode(raw: string): Msg {
    const p = JSON.parse(raw) as Msg;
    if (p.z === 1 && typeof p.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(p.d, 'base64'))).toString('utf8')) as Msg;
    return p;
  }

  async function user(name: string) {
    const ws = new WebSocket(`ws://127.0.0.1:${srv.port}/ws`);
    const msgs: Msg[] = [];
    ws.onmessage = ev => { msgs.push(decode(String(ev.data))); };
    await new Promise<void>((res, rej) => { ws.onopen = () => res(); ws.onerror = () => rej(new Error('ws')); });
    const wait = async (pred: (m: Msg) => boolean, ms = 2000) => {
      const end = Date.now() + ms;
      while (Date.now() < end) { const i = msgs.findIndex(pred); if (i >= 0) return msgs.splice(i, 1)[0]; await new Promise(r => setTimeout(r, 10)); }
      throw new Error('timed out');
    };
    const send = (m: Msg) => ws.send(JSON.stringify(m));
    const pkey = Array.from({ length: 24 }, () => 'abcdefghijklmnopqrstuvwxyz0123456789'[Math.floor(Math.random() * 36)]).join('');
    send({ type: 'social_hello', pkey, name });
    const me = await wait(m => m.type === 'social_me');
    return { send, wait, name, code: me.code as string, close: () => ws.close() };
  }

  it('players of a 1v1 match see each other in recent players', async () => {
    const a = await user(`Rpa${Date.now() % 1e5}`), b = await user(`Rpb${Date.now() % 1e5}`);
    a.send({ type: 'create_room', name: a.name });
    const created = await a.wait(m => m.type === 'room_created');
    b.send({ type: 'join_room', code: created.code, name: b.name });
    await b.wait(m => m.type === 'room_ready');
    a.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'attrition', starting_lives: 3, pvp_start_round: 1 }, player_name: a.name });
    await a.wait(m => m.type === 'match_state_update' && m.event === 'match_started');
    await new Promise(r => setTimeout(r, 50));
    a.send({ type: 'social_recent' });
    const ra = await a.wait(m => m.type === 'social_recent');
    expect(ra.items.map((i: Msg) => [i.code, i.name, i.mode, i.online])).toEqual([[b.code, b.name, 'attrition', true]]);
    b.send({ type: 'social_recent' });
    const rb = await b.wait(m => m.type === 'social_recent');
    expect(rb.items.map((i: Msg) => i.code)).toEqual([a.code]);
    a.close(); b.close();
  });

  it('a finished 1v1 match counts in the head to head record', async () => {
    const a = await user(`Hha${Date.now() % 1e5}`), b = await user(`Hhb${Date.now() % 1e5}`);
    a.send({ type: 'create_room', name: a.name });
    const created = await a.wait(m => m.type === 'room_created');
    b.send({ type: 'join_room', code: created.code, name: b.name });
    await b.wait(m => m.type === 'room_ready');
    a.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'nemesis', starting_lives: 1, pvp_start_round: 2, win_ante: 2 }, player_name: a.name });
    await b.wait(m => m.type === 'match_start');
    a.send({ type: 'act', seq: 1, a: [{ k: 'select', b: 'S' }] });
    b.send({ type: 'act', seq: 1, a: [{ k: 'select', b: 'S' }] });
    b.send({ type: 'act', seq: 2, a: [{ k: 'play', c: [1, 2] }] });
    a.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    b.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    a.send({ type: 'play_hand', score: '900', hands_left: 0 });
    b.send({ type: 'play_hand', score: '100', hands_left: 0 });
    await a.wait(m => m.type === 'match_ended', 4000);
    await new Promise(r => setTimeout(r, 50));
    a.send({ type: 'social_recent' });
    const ra = await a.wait(m => m.type === 'social_recent');
    expect(ra.items[0]).toMatchObject({ code: b.code, h2h: { w: 1, l: 0, d: 0 } });
    b.send({ type: 'social_recent' });
    const rb = await b.wait(m => m.type === 'social_recent');
    expect(rb.items[0]).toMatchObject({ code: a.code, h2h: { w: 0, l: 1, d: 0 } });
    a.close(); b.close();
  });
});
