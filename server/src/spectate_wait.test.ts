import { describe, it, expect, afterAll } from 'bun:test';
import { startServer } from './index';
import { cleanPartySettings } from './party_rules';

type Msg = Record<string, unknown>;
const srv = startServer(0);
afterAll(() => srv.stop(true));

interface C { msgs: Msg[]; send: (m: Msg) => void; wait: (t: string, f?: (m: Msg) => boolean, ms?: number) => Promise<Msg>; none: (t: string, ms?: number) => Promise<boolean>; close: () => void; }

let uid = 0;
const nm = () => `Spec${++uid}x${Math.floor(Math.random() * 1e6)}`;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function decode(raw: string): Msg {
  const parsed = JSON.parse(raw) as Msg;
  if (parsed.z === 1 && typeof parsed.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(parsed.d, 'base64'))).toString('utf8')) as Msg;
  return parsed;
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
  const wait = (t: string, f: (m: Msg) => boolean = () => true, ms = 2000) => {
    const pred = (m: Msg) => m.type === t && f(m);
    const i = msgs.findIndex(pred);
    if (i >= 0) return Promise.resolve(msgs.splice(i, 1)[0]);
    return new Promise<Msg>((res, rej) => {
      const to = setTimeout(() => rej(new Error('timeout ' + t)), ms);
      waiters.push({ pred, resolve: (m) => { clearTimeout(to); msgs.splice(msgs.indexOf(m), 1); res(m); } });
    });
  };
  return {
    msgs,
    send: (m) => ws.send(JSON.stringify(m)),
    wait,
    none: async (t, ms = 150) => { await sleep(ms); return !msgs.some((m) => m.type === t); },
    close: () => ws.close(),
  };
}

async function duel(settings: Msg): Promise<[C, C]> {
  const host = await connect();
  const guest = await connect();
  host.send({ type: 'create_room', visibility: 'public', name: nm() });
  const created = await host.wait('room_created');
  guest.send({ type: 'join_room', code: created.code, name: nm() });
  await guest.wait('room_ready');
  await host.wait('room_ready');
  host.send({ type: 'match_start', seed: 'SPEC1', settings: { mode: 'nemesis', starting_lives: 2, pvp_start_round: 2, win_ante: 3, ...settings }, player_name: 'SpecHost' });
  await guest.wait('match_start');
  return [host, guest];
}

async function pvp(cs: C[]): Promise<void> {
  for (const c of cs) c.send({ type: 'blind_entered', ante: 2, blind: 'L' });
  await sleep(40);
  for (const c of cs) c.send({ type: 'ready_blind' });
  for (const c of cs) await c.wait('start_blind');
}

const BOARD = { where: 'blind', ante: 2, chips: 120, hand: [{ i: 1, k: 'S_A' }] };

describe('spectate while waiting, 1v1', () => {
  it('off by default: no spec_avail, spectate is denied, boards are not stored', async () => {
    const [a, b] = await duel({});
    await pvp([a, b]);
    b.send({ type: 'spec_board', board: BOARD });
    a.send({ type: 'play_hand', score: '500', hands_left: 0 });
    expect(await a.none('spec_avail')).toBe(true);
    a.send({ type: 'spectate', pid: 1 });
    expect((await a.wait('spec_board')).denied).toBe(true);
    a.close(); b.close();
  });

  it('on: a finished player gets spec_avail, sees the live board, and it stops at pvp_resolved', async () => {
    const [a, b] = await duel({ spectate_wait: true });
    await pvp([a, b]);
    b.send({ type: 'spec_board', board: BOARD });
    a.send({ type: 'spectate', pid: 1 });
    expect((await a.wait('spec_board')).denied).toBe(true);
    a.send({ type: 'play_hand', score: '500', hands_left: 0 });
    const av = await a.wait('spec_avail');
    expect(av.pid).toBe(1);
    expect(await b.none('spec_avail', 50)).toBe(true);
    a.send({ type: 'spectate', pid: 1 });
    const first = await a.wait('spec_board');
    expect(first.denied).toBeUndefined();
    expect(((first.board as Msg).hand as Msg[])[0].k).toBe('S_A');
    b.send({ type: 'spec_board', board: { ...BOARD, chips: 900 } });
    expect(((await a.wait('spec_board')).board as Msg).chips).toBe(900);
    b.send({ type: 'spectate', pid: 0 });
    expect((await b.wait('spec_board')).denied).toBe(true);
    b.send({ type: 'play_hand', score: '100', hands_left: 0 });
    await a.wait('pvp_resolved');
    await b.wait('pvp_resolved');
    b.send({ type: 'spec_board', board: { ...BOARD, chips: 5 } });
    expect(await a.none('spec_board')).toBe(true);
    a.send({ type: 'blind_entered', ante: 3, blind: 'L' });
    b.send({ type: 'blind_entered', ante: 3, blind: 'L' });
    await sleep(40);
    a.send({ type: 'ready_blind' });
    b.send({ type: 'ready_blind' });
    await a.wait('start_blind');
    a.send({ type: 'play_hand', score: '50', hands_left: 0 });
    await a.wait('spec_avail');
    a.send({ type: 'spectate', pid: 1 });
    expect((await a.wait('spec_board')).board).toBe(null);
    a.close(); b.close();
  });

  it('bad boards are dropped', async () => {
    const [a, b] = await duel({ spectate_wait: true });
    await pvp([a, b]);
    a.send({ type: 'play_hand', score: '500', hands_left: 0 });
    await a.wait('spec_avail');
    a.send({ type: 'spectate', pid: 1 });
    expect((await a.wait('spec_board')).board).toBe(null);
    b.send({ type: 'spec_board', board: [1, 2] });
    b.send({ type: 'spec_board', board: { pad: 'x'.repeat(13000) } });
    b.send({ type: 'spec_board', board: 'nope' });
    expect(await a.none('spec_board')).toBe(true);
    a.close(); b.close();
  });

  it('a non-boolean setting is cleaned away', async () => {
    const [a, b] = await duel({ spectate_wait: 'yes' });
    await pvp([a, b]);
    a.send({ type: 'play_hand', score: '500', hands_left: 0 });
    expect(await a.none('spec_avail')).toBe(true);
    a.close(); b.close();
  });
});

async function party(n: number, settings: Msg): Promise<C[]> {
  const host = await connect();
  host.send({ type: 'party_create', name: nm(), kind: settings.party_kind ?? 'br' });
  const j = await host.wait('party_joined');
  host.send({ type: 'match_settings', settings });
  const cs = [host];
  for (let i = 1; i < n; i++) {
    const c = await connect();
    c.send({ type: 'party_join', code: j.code, name: nm() });
    await c.wait('party_joined');
    cs.push(c);
  }
  for (const c of cs.slice(1)) c.send({ type: 'party_ready', ready: true });
  await sleep(60);
  cs[0].send({ type: 'party_start' });
  for (const c of cs) await c.wait('match_start');
  return cs;
}

describe('spectate while waiting, party', () => {
  it('with spectating off, only a player who finished the PvP blind may watch', async () => {
    const cs = await party(3, { party_kind: 'br', spectate: false, spectate_wait: true });
    await pvp(cs);
    cs[1].send({ type: 'spectate', pid: 0 });
    expect((await cs[1].wait('spec_board', (m) => m.pid === 0)).denied).toBe(true);
    cs[1].send({ type: 'play_hand', score: 300, hands_left: 0 });
    await sleep(60);
    cs[1].send({ type: 'spectate', pid: 0 });
    const ok = await cs[1].wait('spec_board', (m) => m.pid === 0);
    expect(ok.denied).toBeUndefined();
    cs[0].send({ type: 'spec_board', board: BOARD });
    expect(((await cs[1].wait('spec_board', (m) => m.pid === 0 && !!m.board)).board as Msg).chips).toBe(120);
    cs[2].send({ type: 'spectate', pid: 0 });
    expect((await cs[2].wait('spec_board', (m) => m.pid === 0)).denied).toBe(true);
    for (const c of cs) c.close();
  });

  it('with both off a living player is denied even after finishing', async () => {
    const cs = await party(2, { party_kind: 'br', spectate: false });
    await pvp(cs);
    cs[1].send({ type: 'play_hand', score: 300, hands_left: 0 });
    await sleep(60);
    cs[1].send({ type: 'spectate', pid: 0 });
    expect((await cs[1].wait('spec_board', (m) => m.pid === 0)).denied).toBe(true);
    for (const c of cs) c.close();
  });

  it('the setting is a cleaned boolean', () => {
    const s: Msg = { spectate_wait: 'on' };
    cleanPartySettings(s);
    expect(s.spectate_wait).toBeUndefined();
    const t: Msg = { spectate_wait: true };
    cleanPartySettings(t);
    expect(t.spectate_wait).toBe(true);
  });
});
