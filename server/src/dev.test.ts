import { describe, it, expect, afterAll, beforeAll } from 'bun:test';
import path from 'node:path';
process.env.BOT_WORKER = `bun ${path.join(import.meta.dir, 'bot_fake_worker.ts')}`;
import { startServer } from './index';
import { stopBots } from './bots';
import { isDevKey, devKeyHash, devMark, setDevHashes } from './dev';
import { whoOf, whoFields } from './identity';
import { startPick, type PickRoom, type PickDeps } from './pick';
import { DailyBoard, MemoryDailyStore } from './daily_board';

type Msg = Record<string, unknown>;
const DEV = 'Dev0Key0Abc1Def2Ghi3Jkl4';
const OTHER = 'Not0Dev0Abc1Def2Ghi3Jkl4';

const srv = startServer(0);
beforeAll(() => setDevHashes([devKeyHash(DEV)]));
afterAll(() => { setDevHashes(null); stopBots(); srv.stop(true); });

function decode(raw: string): Msg {
  const p = JSON.parse(raw) as Msg;
  if (p.z === 1 && typeof p.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(p.d, 'base64'))).toString('utf8')) as Msg;
  return p;
}

async function connect() {
  const ws = new WebSocket(`ws://127.0.0.1:${srv.port}/ws`);
  const msgs: Msg[] = [];
  const waiters: { t: string; resolve: (m: Msg) => void }[] = [];
  ws.onmessage = (ev) => {
    const m = decode(String(ev.data));
    const i = waiters.findIndex(w => w.t === m.type);
    if (i >= 0) waiters.splice(i, 1)[0].resolve(m); else msgs.push(m);
  };
  await new Promise<void>((res, rej) => { ws.onopen = () => res(); ws.onerror = () => rej(new Error('ws')); });
  return {
    send: (m: Msg) => ws.send(JSON.stringify(m)),
    wait: (t: string, ms = 3000): Promise<Msg> => {
      const i = msgs.findIndex(m => m.type === t);
      if (i >= 0) return Promise.resolve(msgs.splice(i, 1)[0]);
      return new Promise((res, rej) => {
        const to = setTimeout(() => rej(new Error('timeout ' + t)), ms);
        waiters.push({ t, resolve: (m) => { clearTimeout(to); res(m); } });
      });
    },
    close: () => ws.close(),
  };
}

describe('dev badge', () => {
  it('knows only the listed account keys', () => {
    expect(isDevKey(DEV)).toBe(true);
    expect(isDevKey(OTHER)).toBe(false);
    expect(isDevKey(devKeyHash(DEV))).toBe(false);
    expect(isDevKey(undefined)).toBe(false);
    expect(isDevKey('short')).toBe(false);
    expect(devMark(DEV)).toEqual({ dev: true });
    expect(devMark(OTHER)).toEqual({});
  });

  it('reads extra hashes from the server env list', () => {
    const before = process.env.DEV_KEY_SHA256;
    process.env.DEV_KEY_SHA256 = ` ${devKeyHash(OTHER).toUpperCase()} , junk`;
    setDevHashes(null);
    expect(isDevKey(OTHER)).toBe(true);
    if (before === undefined) delete process.env.DEV_KEY_SHA256; else process.env.DEV_KEY_SHA256 = before;
    setDevHashes([devKeyHash(DEV)]);
    expect(isDevKey(OTHER)).toBe(false);
  });

  it('comes from the account key, never from what the client says', () => {
    const real = whoOf({ data: { name: 'Gabe', pkey: DEV } }, 0);
    expect(real.dev).toBe(true);
    expect(whoFields(real).dev).toBe(true);
    const faker = whoOf({ data: { name: 'Faker', pkey: OTHER, dev: true } }, 1);
    expect(faker.dev).toBeUndefined();
    expect(whoFields(faker).dev).toBeUndefined();
    expect(whoOf({ data: { name: 'Bot', pkey: DEV, bot: true } }, 1).dev).toBeUndefined();
  });

  it('shows in room rosters and name badges for the dev account only', async () => {
    const { ranked } = await import('./ranked');
    await ranked.load(DEV, 'DevGabe');
    await ranked.load(OTHER, 'DevFaker');
    const host = await connect();
    const guest = await connect();
    host.send({ type: 'create_room', name: 'DevGabe', pkey: DEV });
    const created = await host.wait('room_created');
    expect((created.players as Msg[])[0].dev).toBe(true);
    guest.send({ type: 'join_room', code: created.code, name: 'DevFaker', pkey: OTHER, dev: true, is_dev: true });
    const ready = await guest.wait('room_ready');
    const players = ready.players as Msg[];
    expect(players.map(p => [p.name, p.dev === true])).toEqual([['DevGabe', true], ['DevFaker', false]]);
    guest.send({ type: 'ranked_badges', names: ['DevGabe', 'DevFaker'], dev: true });
    const b = (await guest.wait('ranked_badges')).badges as Record<string, Msg>;
    expect(b.DevGabe.dev).toBe(true);
    expect(b.DevFaker.dev).toBeUndefined();
    expect(typeof b.DevGabe.r).toBe('number');
    host.close();
    guest.close();
  });

  it('marks the dev seat on the pick screen', () => {
    const sent: { pid: number; msg: Msg }[] = [];
    const room: PickRoom = { code: 'DEVP', settings: { deck: 'Red Deck', joker_picks: 1 } };
    const deps: PickDeps = { sendTo: (pid, msg) => sent.push({ pid, msg }), isBot: () => false, connected: () => true, isDev: (pid) => pid === 1, log: () => {} };
    const p = startPick(room, deps, [0, 1], ['b_red', 'b_blue']);
    expect(sent.length).toBe(2);
    for (const s of sent) expect(s.msg.devs).toEqual([1]);
    if (p.timer) clearTimeout(p.timer);
    const quiet: { msg: Msg }[] = [];
    const q = startPick({ code: 'DEVQ', settings: { deck: 'Red Deck', joker_picks: 1 } }, { ...deps, sendTo: (_, msg) => quiet.push({ msg }), isDev: () => false }, [0, 1], ['b_red']);
    for (const s of quiet) expect('devs' in s.msg).toBe(false);
    if (q.timer) clearTimeout(q.timer);
  });

  it('marks the dev row on the daily board', async () => {
    const board = new DailyBoard(new MemoryDailyStore(), { now: () => Date.UTC(2026, 10, 13, 12) });
    const day = '2026-11-13';
    const base = { day, sig: 'S1', won: true, round: 9, best: 1000 };
    await board.submit({ ...base, pkey: DEV, name: 'DevGabe', ante: 8 });
    await board.submit({ ...base, pkey: OTHER, name: 'DevFaker', ante: 5 });
    const out = await board.board(OTHER, day, 'S1');
    expect(out.top.map(r => [r.name, r.dev === true])).toEqual([['DevGabe', true], ['DevFaker', false]]);
    expect(out.me?.dev).toBeUndefined();
  });
});
