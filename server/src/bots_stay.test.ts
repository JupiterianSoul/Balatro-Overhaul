import { describe, it, expect, afterAll } from 'bun:test';
import path from 'node:path';
process.env.BOT_WORKER = `bun ${path.join(import.meta.dir, 'bot_fake_worker.ts')}`;
process.env.BOT_WORKERS = '2';
import { startServer, rooms } from './index';
import { botTiming, botPace, stopBots, botWorkerCall, workerPids, listBots, botMemory, simpleTarget, type BotLevel } from './bots';
botMemory.totalMB = () => 0;
import { botSocial } from './bot_social';

type Msg = Record<string, unknown>;
const srv = startServer(0);
botTiming.beatMs = 0;
botPace.scale = 0;
botSocial.level = 0;
afterAll(() => { stopBots(); srv.stop(true); });

interface C { msgs: Msg[]; seen: Msg[]; send: (m: Msg) => void; wait: (t: string, f?: (m: Msg) => boolean, ms?: number) => Promise<Msg>; close: () => void; }

function decode(raw: string): Msg {
  const p = JSON.parse(raw) as Msg;
  if (p.z === 1 && typeof p.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(p.d, 'base64'))).toString('utf8')) as Msg;
  return p;
}

let uid = 0;
const nm = () => `StayTester${++uid}x${Math.floor(Math.random() * 1e6)}`;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function connect(): Promise<C> {
  const ws = new WebSocket(`ws://127.0.0.1:${srv.port}/ws`);
  const msgs: Msg[] = [];
  const seen: Msg[] = [];
  const waiters: { pred: (m: Msg) => boolean; resolve: (m: Msg) => void }[] = [];
  ws.onmessage = (ev) => {
    const m = decode(String(ev.data));
    msgs.push(m);
    seen.push(m);
    for (let i = waiters.length - 1; i >= 0; i--) if (waiters[i].pred(m)) { waiters[i].resolve(m); waiters.splice(i, 1); }
  };
  await new Promise<void>((res, rej) => { ws.onopen = () => res(); ws.onerror = () => rej(new Error('ws')); });
  return {
    msgs, seen,
    send: (m) => ws.send(JSON.stringify(m)),
    wait: (t, f = () => true, ms = 3000) => {
      const pred = (m: Msg) => m.type === t && f(m);
      const i = msgs.findIndex(pred);
      if (i >= 0) return Promise.resolve(msgs.splice(i, 1)[0]);
      return new Promise<Msg>((res, rej) => {
        const to = setTimeout(() => rej(new Error('timeout ' + t)), ms);
        waiters.push({ pred, resolve: (m) => { clearTimeout(to); msgs.splice(msgs.indexOf(m), 1); res(m); } });
      });
    },
    close: () => ws.close(),
  };
}

const START = { mode: 'nemesis', starting_lives: 4, pvp_start_round: 2 };
const botIn = (code: string) => listBots().find(b => b.data.roomCode === code)!;
const over = (c: C) => c.seen.some(m => m.type === 'match_ended' || m.type === 'opponent_left' || m.type === 'guest_left' || m.type === 'opponent_disconnected');

async function started(seed: string, level: BotLevel = 'easy') {
  const host = await connect();
  host.send({ type: 'create_room', name: nm() });
  const created = await host.wait('room_created');
  const code = created.code as string;
  host.send({ type: 'add_bot', level });
  await host.wait('room_ready');
  host.send({ type: 'match_start', seed, settings: START, player_name: 'Host' });
  await host.wait('match_state_update', (m) => m.event === 'match_started');
  return { host, code, bot: botIn(code) };
}

async function pvpBlind(c: C, ante: number, botIsReady = false): Promise<Msg> {
  if (!botIsReady) await c.wait('opponent_ready_blind', () => true, 6000);
  c.send({ type: 'ready_blind', ante, blind: 'L' });
  await c.wait('start_blind', () => true, 6000);
  c.send({ type: 'blind_entered', ante, blind: 'L' });
  c.send({ type: 'play_hand', score: '100', hands_left: 0 });
  return c.wait('pvp_resolved', () => true, 6000);
}

describe('a bot never leaves a running match', () => {
  it('a bot whose own run ends is put on a fresh run and keeps its seat', async () => {
    const { host, code, bot } = await started('DONE1');
    const res = await pvpBlind(host, 2);
    expect(res.result).toBe('lose');
    expect(bot.restarts).toBe(1);
    expect(bot.simple).toBe(false);
    expect(over(host)).toBe(false);
    expect(rooms[code].match?.phase).not.toBe('finished');
    expect(rooms[code].sockets[1]).toBe(bot as never);
    host.close();
  });

  it('a worker that dies mid match is replaced and the bot plays on from the next blind', async () => {
    const { host, code, bot } = await started('KILL1');
    await host.wait('opponent_ready_blind', () => true, 6000);
    const before = workerPids();
    const died = await botWorkerCall('die', { bot: bot.id, level: 'easy' });
    expect(died.err).toBe('worker gone');
    await pvpBlind(host, 2, true);
    const res = await pvpBlind(host, 3);
    expect(res.result).toBe('lose');
    expect(bot.restarts).toBe(1);
    expect(bot.mark?.ante).toBe(3);
    expect(workerPids().some(p => !before.includes(p))).toBe(true);
    expect(over(host)).toBe(false);
    expect(rooms[code].match?.phase).not.toBe('finished');
    host.close();
  });

  it('a bot with no usable worker plays on with the simple brain', async () => {
    const { host, code, bot } = await started('NONEW NORESUME');
    const res = await pvpBlind(host, 2);
    expect(['win', 'lose']).toContain(res.result as string);
    expect(bot.simple).toBe(true);
    expect(Number(rooms[code].match?.pvpResults[0].p1Score)).toBeGreaterThanOrEqual(Math.floor(simpleTarget(2, 3) * 1.2) - 4);
    const again = await pvpBlind(host, 3);
    expect(again.result).toBe('lose');
    expect(over(host)).toBe(false);
    expect(rooms[code].sockets[1]).toBe(bot as never);
    host.close();
  });

  it('a bot that waited past the wait limit for a slow human still plays the PvP blind', async () => {
    const keep = botTiming.waitMs;
    botTiming.waitMs = 40;
    try {
      const { host, code } = await started('SLOW1');
      await host.wait('opponent_ready_blind', () => true, 6000);
      await sleep(300);
      host.send({ type: 'ready_blind', ante: 2, blind: 'L' });
      await host.wait('start_blind', () => true, 6000);
      host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
      host.send({ type: 'play_hand', score: '100', hands_left: 0 });
      const res = await host.wait('pvp_resolved', () => true, 6000);
      expect(res.result).toBe('lose');
      expect(rooms[code].match?.pvpResults[0].p1Score).toBe(200);
      host.close();
    } finally {
      botTiming.waitMs = keep;
    }
  });

  it('a worker that stops answering is restarted and its bot keeps playing', async () => {
    const keep = botTiming.silentMs;
    try {
      const { host, code, bot } = await started('HANG1');
      await host.wait('opponent_ready_blind', () => true, 6000);
      botTiming.silentMs = 300;
      const spin = await botWorkerCall('spin', { ms: 5000, bot: bot.id, level: 'easy' });
      expect(spin.err).toBe('worker gone');
      botTiming.silentMs = keep;
      await pvpBlind(host, 2, true);
      const res = await pvpBlind(host, 3);
      expect(res.result).toBe('lose');
      expect(bot.restarts).toBe(1);
      expect(over(host)).toBe(false);
      expect(rooms[code].match?.phase).not.toBe('finished');
      host.close();
    } finally {
      botTiming.silentMs = keep;
    }
  });

  it('a silent worker killed with calls still queued on its pipe is replaced without a broken pipe error', async () => {
    const keep = botTiming.silentMs;
    const errors: string[] = [];
    const catcher = (e: Error) => { errors.push(e.message); };
    process.on('uncaughtException', catcher);
    try {
      const { host, code, bot } = await started('PIPE1');
      await host.wait('opponent_ready_blind', () => true, 6000);
      botTiming.silentMs = 300;
      const pad = 'x'.repeat(400000);
      const calls = [botWorkerCall('spin', { ms: 5000, bot: bot.id, level: 'easy' })];
      for (let i = 0; i < 6; i++) calls.push(botWorkerCall('pad', { pad, bot: bot.id, level: 'easy' }));
      const res = await Promise.all(calls);
      expect(res.every(r => r.err === 'worker gone')).toBe(true);
      await sleep(300);
      botTiming.silentMs = keep;
      expect(errors).toEqual([]);
      await pvpBlind(host, 2, true);
      const again = await pvpBlind(host, 3);
      expect(again.result).toBe('lose');
      expect(over(host)).toBe(false);
      expect(rooms[code].match?.phase).not.toBe('finished');
      host.close();
    } finally {
      process.off('uncaughtException', catcher);
      botTiming.silentMs = keep;
    }
  });
});

describe('a human who drops against a bot', () => {
  it('rejoins inside the hold: the bot stayed, the seat is back and nobody was handed a win', async () => {
    const { host, code, bot } = await started('DROP1');
    const token = rooms[code].tokens[0];
    await host.wait('opponent_ready_blind', () => true, 6000);
    host.close();
    await sleep(200);
    expect(rooms[code].holdDeadline[0]).not.toBeNull();
    expect(rooms[code].match?.phase).not.toBe('finished');
    expect(rooms[code].sockets[1]).toBe(bot as never);
    expect(bot.readyState).toBe(1);
    await sleep(botTiming.sweepMs > 300 ? 0 : botTiming.sweepMs * 2);
    const back = await connect();
    back.send({ type: 'rejoin_match', code, token });
    const ok = await back.wait('rejoin_ok', () => true, 3000);
    expect(ok.playerId).toBe(0);
    expect(rooms[code].holdDeadline[0]).toBeNull();
    back.send({ type: 'ready_blind', ante: 2, blind: 'L' });
    await back.wait('start_blind', () => true, 6000);
    back.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    back.send({ type: 'play_hand', score: '100', hands_left: 0 });
    expect((await back.wait('pvp_resolved', () => true, 6000)).result).toBe('lose');
    expect(back.seen.some(m => m.type === 'match_ended')).toBe(false);
    expect(rooms[code].sockets[1]).toBe(bot as never);
    back.close();
  });
});
