import { describe, it, expect, afterAll } from 'bun:test';
import path from 'node:path';
process.env.BOT_WORKER = `bun ${path.join(import.meta.dir, 'bot_fake_worker.ts')}`;
import { startServer } from './index';
import { ranked, rankOf } from './ranked';
import { stopBots } from './bots';
import { whoOf, whoAt, whoFields, noteRank, noteRankResult, roomRoster, seatRoster, rankTag } from './identity';

type Msg = Record<string, unknown>;
const srv = startServer(0);
afterAll(() => { stopBots(); srv.stop(true); });

function decode(raw: string): Msg {
  const p = JSON.parse(raw) as Msg;
  if (p.z === 1 && typeof p.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(p.d, 'base64'))).toString('utf8')) as Msg;
  return p;
}

async function connect(): Promise<{ send: (m: Msg) => void; wait: (t: string, ms?: number) => Promise<Msg>; close: () => void }> {
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
    send: (m) => ws.send(JSON.stringify(m)),
    wait: (t, ms = 3000) => {
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

describe('identity fields', () => {
  it('describes a bot with its level and no rank', () => {
    const w = whoOf({ data: { bot: true, name: 'Bob', rp: 5000 }, level: 'hard' }, 2);
    expect(w).toEqual({ pid: 2, name: 'Bob', is_bot: true, bot_level: 'hard' });
    expect(whoOf({ data: { bot: true, name: 'Lou' }, level: 'odd' }).bot_level).toBeUndefined();
  });

  it('gives a human the rank of the cached RP', () => {
    const w = whoOf({ data: { name: 'Ann', rp: 1234 } }, 0);
    const r = rankOf(1234);
    expect(w.rank).toEqual({ rank: r.rank, tier: r.tier, name: r.name });
    expect(w.is_bot).toBe(false);
    expect(whoOf({ data: { name: 'New' } }).rank).toBeUndefined();
    expect(rankTag(Number.NaN)).toBeUndefined();
  });

  it('caches RP from a loaded profile only once the player has played ranked', () => {
    const ws = { data: {} as Msg };
    noteRank(ws, 0, false);
    expect(ws.data.rp).toBeUndefined();
    noteRank(ws, 300, true);
    expect(ws.data.rp).toBe(300);
    noteRankResult(ws, { type: 'ranked_result', after: { rp: 650 } });
    expect(ws.data.rp).toBe(650);
    noteRankResult(ws, { type: 'ranked_profile', after: { rp: 1 } });
    expect(ws.data.rp).toBe(650);
    const bot = { data: { bot: true } as Msg };
    noteRank(bot, 900);
    expect(bot.data.rp).toBeUndefined();
  });

  it('keeps the identity of a seat whose player is reconnecting', () => {
    const owner = {};
    whoAt(owner, 1, { data: { name: 'Zed', rp: 2000 } }, 'Zed');
    const held = whoAt(owner, 1, null, 'Zed');
    expect(held.rank?.rank).toBe(rankOf(2000).rank);
    expect(whoFields(held)).toEqual({ is_bot: false, rank: held.rank });
    expect(whoAt(owner, 3, null, 'Gone')).toEqual({ pid: 3, name: 'Gone', is_bot: false });
  });

  it('lists room seats that are present or held, and every named seat for results', () => {
    const room = { sockets: [{ data: { name: 'A' } }, null], playerNames: ['A', 'B'], holdDeadline: [null, null] as (number | null)[] };
    expect(roomRoster(room).map(w => w.name)).toEqual(['A']);
    expect(roomRoster(room, true).map(w => w.name)).toEqual(['A', 'B']);
    room.holdDeadline[1] = Date.now() + 1000;
    expect(roomRoster(room).map(w => w.pid)).toEqual([0, 1]);
    const party = { seats: [{ ws: { data: { bot: true, name: 'Mina' }, level: 'easy' }, name: 'Mina' }, null, { ws: null, name: 'Kim' }] };
    expect(seatRoster(party, party.seats).map(w => [w.pid, w.is_bot, w.bot_level ?? null])).toEqual([[0, true, 'easy'], [2, false, null]]);
  });

  it('puts a ranked player rank in the room payloads', async () => {
    const pkey = 'IdentityTestKey000000001';
    const st = await ranked.load(pkey, 'Ranky');
    st.row.matches = 4;
    st.row.rp = 1900;
    const host = await connect();
    host.send({ type: 'create_room', name: 'Ranky', pkey });
    const created = await host.wait('room_created');
    const me = (created.players as Msg[])[0];
    expect(me.name).toBe('Ranky');
    expect(me.rank).toEqual(rankTag(1900) as unknown as Msg);
    host.send({ type: 'add_bot', level: 'easy' });
    const ready = await host.wait('room_ready');
    expect((ready.players as Msg[]).map(p => [p.pid, p.is_bot])).toEqual([[0, false], [1, true]]);
    host.close();
  });
});
