import { describe, it, expect, afterAll } from 'bun:test';
import path from 'node:path';
import fs from 'node:fs';
process.env.BOT_WORKER = `bun ${path.join(import.meta.dir, 'bot_fake_worker.ts')}`;
process.env.BOT_WORKERS = '2';
import { startServer, rooms } from './index';
import { parties } from './party';
import { botTiming, botPace, paceMs, actRange, shopLine, stopBots, botWorkerCall, timingOf, workerStats, maxWorkers, workerPoolStats, pickWorker, levelCost, listBots, BOT_NAMES, type BotLevel } from './bots';
import { botSocial } from './bot_social';

type Msg = Record<string, unknown>;
const srv = startServer(0);
botTiming.beatMs = 0;
botPace.scale = 0;
botSocial.level = 0;
afterAll(() => { stopBots(); srv.stop(true); });

interface C { msgs: Msg[]; send: (m: Msg) => void; wait: (t: string, f?: (m: Msg) => boolean, ms?: number) => Promise<Msg>; close: () => void; }

function decode(raw: string): Msg {
  const p = JSON.parse(raw) as Msg;
  if (p.z === 1 && typeof p.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(p.d, 'base64'))).toString('utf8')) as Msg;
  return p;
}

let uid = 0;
const nm = () => `BotTester${++uid}x${Math.floor(Math.random() * 1e6)}`;
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

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

async function roomWithBot(level = 'easy'): Promise<{ host: C; code: string }> {
  const host = await connect();
  host.send({ type: 'create_room', name: nm() });
  const created = await host.wait('room_created');
  host.send({ type: 'add_bot', level });
  await host.wait('room_ready');
  return { host, code: created.code as string };
}

describe('bots in 1v1 rooms', () => {
  it('the host adds a bot that joins and readies up', async () => {
    const { host, code } = await roomWithBot('hard');
    const ready = await host.wait('ready_state');
    expect(ready.ready).toBe(true);
    expect(rooms[code].sockets.length).toBe(2);
    const name = rooms[code].playerNames[1];
    expect(BOT_NAMES).toContain(name);
    host.close();
  });

  it('a guest cannot add or remove bots', async () => {
    const host = await connect();
    host.send({ type: 'create_room', name: nm() });
    const created = await host.wait('room_created');
    const guest = await connect();
    guest.send({ type: 'join_room', code: created.code, name: nm() });
    await guest.wait('room_ready');
    guest.send({ type: 'add_bot', level: 'easy' });
    expect((await guest.wait('bot_error')).reason).toBe('host_only');
    guest.send({ type: 'remove_bot' });
    expect((await guest.wait('bot_error')).reason).toBe('host_only');
    host.send({ type: 'add_bot', level: 'easy' });
    expect((await host.wait('bot_error')).reason).toBe('room_full');
    host.close(); guest.close();
  });

  it('removing the bot frees the seat for another one', async () => {
    const { host, code } = await roomWithBot('easy');
    host.send({ type: 'remove_bot' });
    await sleep(80);
    expect(rooms[code].sockets.filter(Boolean).length).toBe(1);
    host.send({ type: 'add_bot', level: 'medium' });
    await host.wait('room_ready');
    expect(BOT_NAMES).toContain(rooms[code].playerNames[1]);
    host.close();
  });

  it('the bot plays its blinds and finishes a PvP blind', async () => {
    const { host, code } = await roomWithBot('medium');
    host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'attrition', starting_lives: 3, pvp_start_round: 1 }, player_name: 'Host' });
    await host.wait('match_state_update', (m) => m.event === 'match_started');
    await host.wait('opponent_ready_blind', () => true, 5000);
    host.send({ type: 'ready_blind' });
    await host.wait('start_blind');
    host.send({ type: 'blind_entered', ante: 1, blind: 'L' });
    host.send({ type: 'play_hand', score: '100', hands_left: 0 });
    const res = await host.wait('pvp_resolved', () => true, 5000);
    expect(res.result).toBe('lose');
    expect(rooms[code].match?.pvpResults[0].p1Score).toBe(200);
    host.close();
  });

  it('the bot shares its jokers and deck when the match ends', async () => {
    const { host } = await roomWithBot('easy');
    host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'attrition', starting_lives: 3, pvp_start_round: 1 }, player_name: 'Host' });
    await host.wait('match_state_update', (m) => m.event === 'match_started');
    host.send({ type: 'match_finished', result: 'lose', reason: 'forfeit' });
    const j = await host.wait('end_game_jokers', (m) => m.available === true, 5000);
    expect(j.jokers).toEqual([{ k: 'j_joker', ed: 'foil' }]);
    const d = await host.wait('nemesis_deck_data', () => true, 5000);
    expect(d.back).toBe('b_red');
    expect((d.cards as unknown[]).length).toBe(2);
    host.close();
  });

  it('a human who readies before the bot reaches the PvP blind still gets start_blind', async () => {
    const { host } = await roomWithBot('easy');
    host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'attrition', starting_lives: 3, pvp_start_round: 1 }, player_name: 'Host' });
    host.send({ type: 'ready_blind' });
    await host.wait('match_state_update', (m) => m.event === 'match_started');
    await host.wait('start_blind', () => true, 5000);
    host.send({ type: 'blind_entered', ante: 1, blind: 'L' });
    host.send({ type: 'play_hand', score: '100', hands_left: 0 });
    expect((await host.wait('pvp_resolved', () => true, 5000)).result).toBe('lose');
    host.close();
  });

  it('the bot leaves when the last human goes', async () => {
    const { host, code } = await roomWithBot('easy');
    host.close();
    await sleep(100);
    botTiming.sweepMs = 50;
    expect(rooms[code]?.sockets.filter(Boolean).length ?? 0).toBeLessThan(2);
  });
});

describe('bots in parties', () => {
  it('the host fills a Battle Royale with bots and they ready up', async () => {
    const host = await connect();
    host.send({ type: 'party_create', name: nm(), kind: 'br' });
    const j = await host.wait('party_joined');
    const code = j.code as string;
    host.send({ type: 'add_bot', level: 'easy' });
    host.send({ type: 'add_bot', level: 'easy' });
    host.send({ type: 'add_bot', level: 'hard' });
    await sleep(150);
    const seats = parties[code].seats.filter(Boolean);
    expect(seats.length).toBe(4);
    const names = seats.slice(1).map(s => s!.name);
    expect(names.every(n => BOT_NAMES.includes(n))).toBe(true);
    expect(new Set(names.map(n => n.toLowerCase())).size).toBe(3);
    expect(seats.slice(1).every(s => s!.ready)).toBe(true);
    host.send({ type: 'remove_bot', name: names[1] });
    await sleep(80);
    expect(parties[code].seats.filter(Boolean).length).toBe(3);
    host.send({ type: 'party_start' });
    await host.wait('match_start');
    await sleep(200);
    const bots = parties[code].seats.filter(s => s && BOT_NAMES.includes(s.name));
    expect(bots.length).toBe(2);
    expect(bots.every(s => s!.ante >= 1 && s!.alive)).toBe(true);
    host.close();
  });

  it('a bot whose last hand closes the PvP blind still goes on to the next one', async () => {
    const host = await connect();
    host.send({ type: 'party_create', name: nm(), kind: 'br' });
    await host.wait('party_joined');
    host.send({ type: 'add_bot', level: 'easy' });
    await sleep(100);
    host.send({ type: 'party_start' });
    await host.wait('match_start');
    host.send({ type: 'blind_entered', ante: 1, blind: 'L' });
    host.send({ type: 'ready_blind', ante: 1, blind: 'L' });
    await host.wait('start_blind', () => true, 4000);
    host.send({ type: 'blind_finished', ante: 1, blind: 'L', score: 10 });
    await host.wait('pvp_resolved', () => true, 4000);
    host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    host.send({ type: 'ready_blind', ante: 2, blind: 'L' });
    const go = await host.wait('start_blind', () => true, 4000);
    expect(go.solo).toBeUndefined();
    host.close();
  });

  it('bots never wait on a human who is out of the PvP blind', async () => {
    const host = await connect();
    host.send({ type: 'party_create', name: nm(), kind: 'br' });
    await host.wait('party_joined');
    host.send({ type: 'add_bot', level: 'easy' });
    await sleep(100);
    host.send({ type: 'party_start' });
    await host.wait('match_start');
    host.send({ type: 'blind_entered', ante: 1, blind: 'L' });
    host.send({ type: 'ready_blind', ante: 1, blind: 'L' });
    await host.wait('start_blind', () => true, 4000);
    host.send({ type: 'play_hand', score: '10', hands_left: 3 });
    await sleep(50);
    const t0 = Date.now();
    host.send({ type: 'game_over', ante: 1, blind: 'L', score: 10 });
    await host.wait('pvp_resolved', () => true, 6000);
    expect(Date.now() - t0).toBeLessThan(1500);
    host.close();
  });

  it('a bot sends its locations and identity to the party', async () => {
    const host = await connect();
    host.send({ type: 'party_create', name: nm(), kind: 'br' });
    await host.wait('party_joined');
    host.send({ type: 'add_bot', level: 'medium' });
    const room = await host.wait('party_room', (m) => (m.players as Msg[]).length === 2, 3000);
    const bot = (room.players as Msg[])[1];
    expect(bot.is_bot).toBe(true);
    expect(bot.bot_level).toBe('medium');
    expect(bot.bot).toBe(true);
    host.send({ type: 'party_start' });
    const start = await host.wait('match_start');
    expect((start.players as Msg[]).map(p => p.is_bot)).toEqual([false, true]);
    const loc = await host.wait('party_location', (m) => m.location === 'loc_ready', 4000);
    expect(loc.pid).toBe(1);
    expect(loc.party).toBe(true);
    expect((await host.wait('party_location', (m) => m.location === 'loc_shop-bl_mp_royale', 4000)).pid).toBe(1);
    const st = await host.wait('party_state', (m) => (m.players as Msg[])[1]?.location != null, 4000);
    expect((st.players as Msg[])[1].bot_level).toBe('medium');
    host.close();
  });
});

describe('bots act like a human opponent', () => {
  it('the human sees the bot real score and hands left during a PvP blind', async () => {
    botTiming.beatMs = 5;
    try {
      const { host } = await roomWithBot('medium');
      host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'attrition', starting_lives: 3, pvp_start_round: 1 }, player_name: 'Host' });
      const started = await host.wait('match_state_update', (m) => m.event === 'match_started');
      const roster = started.players as Msg[];
      expect(roster.map(p => [p.pid, p.is_bot])).toEqual([[0, false], [1, true]]);
      expect(roster[1].bot_level).toBe('medium');
      await host.wait('set_location', (m) => m.location === 'loc_shop-bl_mp_nemesis' && m.pid === 1, 5000);
      await host.wait('set_location', (m) => m.location === 'loc_ready' && m.pid === 1, 5000);
      expect((await host.wait('opponent_ready_blind', () => true, 5000)).pid).toBe(1);
      host.send({ type: 'ready_blind' });
      await host.wait('start_blind');
      host.send({ type: 'blind_entered', ante: 1, blind: 'L' });
      const seen: Msg[] = [];
      for (let i = 0; i < 5; i++) seen.push(await host.wait('enemy_info', () => true, 5000));
      expect(seen.map(m => [m.score, m.hands_left])).toEqual([['0', 4], ['50', 3], ['100', 2], ['150', 1], ['200', 0]]);
      expect(seen.every(m => m.pid === 1)).toBe(true);
      await host.wait('set_location', (m) => m.location === 'loc_playing-bl_mp_nemesis', 5000);
      await host.wait('set_location', (m) => m.location === 'loc_wait', 5000);
      host.send({ type: 'play_hand', score: '100', hands_left: 0 });
      expect((await host.wait('pvp_resolved', () => true, 5000)).result).toBe('lose');
      host.close();
    } finally {
      botTiming.beatMs = 0;
    }
  });

  it('every location key the bot sends between blinds is one a human sends', async () => {
    const { host } = await roomWithBot('easy');
    host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'attrition', starting_lives: 3, pvp_start_round: 5 }, player_name: 'Host' });
    await host.wait('set_location', (m) => m.location === 'loc_pack', 5000);
    const locs = host.msgs.filter(m => m.type === 'set_location').map(m => String(m.location));
    const keys = new Set(['loc_selecting', 'loc_shop', 'loc_pack', 'loc_playing', 'loc_ready', 'loc_wait']);
    expect(locs.length).toBeGreaterThan(6);
    expect(locs.every(l => keys.has(l.split('-')[0]))).toBe(true);
    expect(locs[0]).toBe('loc_selecting');
    expect(locs).toContain('loc_playing-bl_small');
    expect(locs).toContain('loc_shop-bl_big');
    host.close();
  });

  it('the bot sends one gg when the match ends and no emote before', async () => {
    const { host } = await roomWithBot('easy');
    host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'attrition', starting_lives: 3, pvp_start_round: 1 }, player_name: 'Host' });
    await host.wait('match_state_update', (m) => m.event === 'match_started');
    await sleep(300);
    expect(host.msgs.some(m => m.type === 'social_emote')).toBe(false);
    host.send({ type: 'match_finished', result: 'lose', reason: 'forfeit' });
    await host.wait('match_ended', () => true, 5000);
    const gg = await host.wait('social_emote', () => true, 4000);
    expect(gg.id).toBe('gg');
    await sleep(2200);
    expect(host.msgs.filter(m => m.type === 'social_emote').length).toBe(0);
    host.close();
  });

  it('the bot answers a rematch vote and plays the new match', async () => {
    const { host } = await roomWithBot('easy');
    host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'attrition', starting_lives: 3, pvp_start_round: 1 }, player_name: 'Host' });
    await host.wait('match_state_update', (m) => m.event === 'match_started');
    host.send({ type: 'match_finished', result: 'lose', reason: 'forfeit' });
    const ended = await host.wait('match_ended', () => true, 5000);
    expect((ended.players as Msg[]).length).toBe(2);
    host.send({ type: 'rematch_vote' });
    await host.wait('rematch_accepted', () => true, 3000);
    host.msgs.length = 0;
    await host.wait('opponent_ready_blind', () => true, 5000);
    host.close();
  });

  it('room payloads carry identity for the host and the bot', async () => {
    const host = await connect();
    host.send({ type: 'create_room', name: nm() });
    const created = await host.wait('room_created');
    expect((created.players as Msg[]).map(p => [p.pid, p.is_bot])).toEqual([[0, false]]);
    host.send({ type: 'add_bot', level: 'hard' });
    const ready = await host.wait('room_ready');
    expect(ready.oppBot).toBe(true);
    const bot = (ready.players as Msg[])[1];
    expect(bot.is_bot).toBe(true);
    expect(bot.bot_level).toBe('hard');
    expect(bot.rank).toBeUndefined();
    host.send({ type: 'room_joined', player: { name: 'Host' }, mp_version: 1, version: 'test' });
    const joined = await host.wait('room_joined', () => true, 3000);
    expect(joined.pid).toBe(1);
    expect((joined.player as Msg).is_bot).toBe(true);
    host.close();
  });
});

describe('bot worker timing', () => {
  it('splits each call into worker time and queue wait', async () => {
    stopBots();
    const before = workerStats.calls;
    const rs = await Promise.all([botWorkerCall('spin', { ms: 60 }), botWorkerCall('spin', { ms: 60 }), botWorkerCall('spin', { ms: 60 })]);
    const t = rs.map((r) => timingOf(r)!);
    expect(workerStats.calls - before).toBeGreaterThanOrEqual(3);
    for (const x of t) { expect(x.ms).toBeGreaterThanOrEqual(50); expect(x.ms).toBeLessThan(200); }
    expect(t[0].wait).toBeLessThan(50);
    expect(t[2].wait).toBeGreaterThanOrEqual(100);
    expect(t[2].wait).toBeGreaterThan(t[1].wait);
  });

  it('runs bots pinned to different workers in parallel', async () => {
    const t0 = performance.now();
    const rs = await Promise.all([botWorkerCall('spin', { ms: 150, bot: 'poolA' }), botWorkerCall('spin', { ms: 150, bot: 'poolB' })]);
    const t = rs.map((r) => timingOf(r)!);
    expect(t[0].wait).toBeLessThan(50);
    expect(t[1].wait).toBeLessThan(50);
    expect(performance.now() - t0).toBeLessThan(280);
    const again = await botWorkerCall('spin', { ms: 1, bot: 'poolA' });
    expect(timingOf(again)).toBeDefined();
    const st = workerPoolStats();
    expect(st.length).toBe(2);
    expect(st[0].bots + st[1].bots).toBeGreaterThanOrEqual(2);
  });

  it('pins bots by level cost, so 7 Hard and 7 Easy bots balance on 2 workers', async () => {
    const place = (order: BotLevel[]) => {
      const loads = [0, 0];
      for (const l of order) loads[pickWorker(loads)] += levelCost(l);
      return loads;
    };
    const easy = Array<BotLevel>(7).fill('easy'), hard = Array<BotLevel>(7).fill('hard');
    const mixed: BotLevel[] = easy.flatMap((e, i) => [e, hard[i]]);
    for (const order of [[...easy, ...hard], [...hard, ...easy], mixed]) {
      const loads = place(order);
      expect(Math.abs(loads[0] - loads[1])).toBeLessThanOrEqual(levelCost('hard'));
    }
    expect(levelCost('nope')).toBe(levelCost('medium'));
    stopBots();
    await Promise.all([...hard, ...easy].map((level, i) => botWorkerCall('spin', { ms: 1, bot: `wl${i}`, level })));
    const st = workerPoolStats();
    expect(st[0].load + st[1].load).toBe(7 * levelCost('hard') + 7 * levelCost('easy'));
    expect(Math.abs(st[0].load - st[1].load)).toBeLessThanOrEqual(levelCost('hard'));
    expect(Math.abs(st[0].bots - st[1].bots)).toBeGreaterThan(0);
    stopBots();
  });

  it('caps the worker count from env, one worker per bot below the cap', () => {
    expect(maxWorkers('3')).toBe(3);
    expect(maxWorkers('')).toBe(12);
    expect(maxWorkers('x')).toBe(12);
    expect(maxWorkers('500')).toBe(64);
  });

  it('gives every bot its own worker and frees it when the bot goes', async () => {
    stopBots();
    const host = await connect();
    host.send({ type: 'party_create', name: nm(), kind: 'br' });
    await host.wait('party_joined');
    host.send({ type: 'add_bot', level: 'hard' });
    host.send({ type: 'add_bot', level: 'easy' });
    await sleep(150);
    expect(listBots().length).toBe(2);
    expect(workerPoolStats().map(w => w.bots)).toEqual([1, 1]);
    host.send({ type: 'remove_bot' });
    await sleep(80);
    expect(workerPoolStats().map(w => w.bots)).toEqual([1]);
    host.close();
    stopBots();
  });
});

describe('bot bans', () => {
  it('match the nemesis bans humans get in bom_gamemodes', () => {
    const assets = path.resolve(import.meta.dir, '../../assets');
    const worker = fs.readFileSync(path.join(assets, 'bot/mp/worker.lua'), 'utf8');
    const modes = fs.readFileSync(path.join(assets, 'multiplayer/bom_gamemodes.lua'), 'utf8');
    const line = worker.match(/local MP_BANS = \{([^}]*)\}/)![1];
    const bot = [...line.matchAll(/"([^"]+)"/g)].map((m) => m[1]).sort();
    const nemesis = modes.slice(modes.indexOf('key = "nemesis"'), modes.indexOf('key = "faceoff"'));
    const human: string[] = [];
    for (const m of nemesis.matchAll(/banned_\w+ = \{([^}]*)\}/g)) for (const k of m[1].matchAll(/"([^"]+)"/g)) human.push(k[1]);
    expect(human.length).toBeGreaterThan(5);
    expect(bot).toEqual(human.sort());
  });
});

async function shopLog(level: string, until: (line: string) => boolean): Promise<string[]> {
  const lines: string[] = [];
  const was = console.log;
  console.log = (...a: unknown[]) => { const l = a.map(String).join(' '); if (l.includes('between blinds')) lines.push(l); else was(...a); };
  try {
    const { host, code } = await roomWithBot(level);
    host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'attrition', starting_lives: 3, pvp_start_round: 5 }, player_name: 'Host' });
    for (let i = 0; i < 200 && !lines.some((l) => l.includes(` ${code} `) && until(l)); i++) await sleep(25);
    host.close();
    return lines.filter((l) => l.includes(` ${code} `));
  } finally {
    console.log = was;
  }
}

describe('bots shop like a person', () => {
  it('logs every action between two blinds with its time, the money and the jokers', async () => {
    const lines = await shopLog('easy', (l) => l.includes('buy j_joker'));
    const line = lines.find((l) => l.includes('buy j_joker'))!;
    expect(line).toContain('[INFO][BOT]');
    expect(line).toMatch(/cash_out \+\$8 @[\d.]+s, shop @[\d.]+s, buy j_joker -\$5 @[\d.]+s, open p_buffoon_normal_1 -\$4 @[\d.]+s, pick j_egg @[\d.]+s, leave @[\d.]+s, select @[\d.]+s/);
    expect(line).toContain('$10, 2 jokers: j_joker j_egg');
  });

  it('stays in the shop for a human time before it leaves', async () => {
    const saved = { ...botPace };
    Object.assign(botPace, { scale: 1, hand: [0, 0], discard: [0, 0], cash: [100, 100], act: [100, 100], pick: [100, 100], select: [100, 100], shop: [700, 700] });
    try {
      const lines = await shopLog('easy', (l) => l.includes('leave'));
      const m = lines.find((l) => l.includes('leave'))!.match(/shop @([\d.]+)s, leave @([\d.]+)s, select @([\d.]+)s/)!;
      expect(m).not.toBeNull();
      expect(Number(m[1])).toBeGreaterThanOrEqual(0.05);
      expect(Number(m[2]) - Number(m[1])).toBeGreaterThanOrEqual(0.55);
      expect(Number(m[3]) - Number(m[2])).toBeGreaterThanOrEqual(0.05);
    } finally {
      Object.assign(botPace, saved);
    }
  });

  it('does not leave the shop while the human still plays the blind it just finished', async () => {
    const saved = { ...botPace };
    Object.assign(botPace, { scale: 1, hand: [0, 0], discard: [0, 0], cash: [50, 50], act: [50, 50], pick: [50, 50], select: [50, 50], shop: [100, 100], linger: [100, 100], follow: 5000 });
    const lines: string[] = [];
    const was = console.log;
    console.log = (...a: unknown[]) => { const l = a.map(String).join(' '); if (l.includes('between blinds')) lines.push(l); else was(...a); };
    try {
      const { host, code } = await roomWithBot('easy');
      host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'attrition', starting_lives: 3, pvp_start_round: 5 }, player_name: 'Host' });
      await host.wait('set_location', (m) => m.location === 'loc_selecting' && m.pid === 1, 3000);
      await host.wait('set_location', (m) => m.location === 'loc_playing-bl_small' && m.pid === 1, 3000);
      host.send({ type: 'set_location', location: 'loc_playing-bl_small' });
      await host.wait('set_location', (m) => m.location === 'loc_shop-bl_big' && m.pid === 1, 3000);
      await sleep(700);
      expect(host.msgs.some((m) => m.type === 'set_location' && m.location === 'loc_selecting' && m.pid === 1)).toBe(false);
      host.send({ type: 'set_location', location: 'loc_shop-bl_big' });
      await host.wait('set_location', (m) => m.location === 'loc_selecting' && m.pid === 1, 3000);
      for (let i = 0; i < 40 && !lines.some((l) => l.includes(` ${code} `) && l.includes('leave')); i++) await sleep(25);
      const line = lines.find((l) => l.includes(` ${code} `) && l.includes('leave'))!;
      const m = line.match(/shop @([\d.]+)s, wait ([\d.]+)s @[\d.]+s, leave @([\d.]+)s/)!;
      expect(m).not.toBeNull();
      expect(Number(m[2])).toBeGreaterThanOrEqual(0.7);
      expect(Number(m[3]) - Number(m[1])).toBeGreaterThanOrEqual(0.8);
      host.close();
    } finally {
      console.log = was;
      Object.assign(botPace, saved);
    }
  });

  it('in a party it waits only for humans who are still in the match', async () => {
    const host = await connect();
    host.send({ type: 'party_create', name: nm(), kind: 'br' });
    await host.wait('party_joined');
    host.send({ type: 'add_bot', level: 'easy' });
    await host.wait('party_room', (m) => (m.players as Msg[]).length === 2, 3000);
    await sleep(50);
    const b = listBots().find((x) => x.party && x.readyState === 1)!;
    expect(b.botPids.has(1)).toBe(true);
    b.lastKey = 'bl_small';
    b.onServer({ type: 'party_location', pid: 0, location: 'loc_playing-bl_small' });
    b.onServer({ type: 'party_location', pid: 2, location: 'loc_playing-bl_small' });
    expect(b.humanBehind()).toBe(true);
    b.onServer({ type: 'party_location', pid: 0, location: 'loc_shop-bl_big' });
    b.botPids.add(2);
    expect(b.humanBehind()).toBe(false);
    b.onServer({ type: 'party_location', pid: 0, location: 'loc_playing-bl_small' });
    b.onServer({ type: 'party_state', players: [{ pid: 0, alive: false, connected: true }] });
    expect(b.humanBehind()).toBe(false);
    b.onServer({ type: 'party_state', players: [{ pid: 0, alive: true, connected: true }] });
    expect(b.humanBehind()).toBe(true);
    b.lastKey = 'bl_big';
    expect(b.humanBehind()).toBe(false);
    host.close();
    stopBots();
  });

  it('paces each kind of action from its own range', () => {
    expect(actRange('cash_out', 'round_eval')).toBe(botPace.cash);
    expect(actRange('open', 'shop')).toBe(botPace.pick);
    expect(actRange('skip', 'pack')).toBe(botPace.pick);
    expect(actRange('skip', 'blind_select')).toBe(botPace.select);
    expect(actRange('buy', 'shop')).toBe(botPace.act);
    expect(actRange('reroll', 'shop')).toBe(botPace.act);
    expect(botPace.shop[0]).toBeGreaterThanOrEqual(10000);
    expect(shopLine([{ type: 'sell', key: 'j_egg', cost: -3, t: 1500 }, { type: 'leave', cost: 0, t: 4000 }], 7, ['j_joker'])).toBe('sell j_egg +$3 @1.5s, leave @4.0s | $7, 1 jokers: j_joker');
    expect(shopLine([{ type: 'buy', key: 'j_joker', cost: 2, t: 2000, spend: true }, { type: 'leave', cost: 0, t: 4000 }], 26, ['j_joker'])).toBe('buy j_joker -$2 (spend) @2.0s, leave @4.0s | $26, 1 jokers: j_joker');
  });
});

describe('bot pacing', () => {
  it('thinks like a person per action and can be turned off', () => {
    const was = botPace.scale;
    botPace.scale = 1;
    for (let i = 0; i < 20; i++) {
      const t = paceMs([1000, 2000]);
      expect(t >= 1000 && t <= 2000).toBe(true);
      const three = paceMs([1000, 2000], 3);
      expect(three >= 3000 && three <= 6000).toBe(true);
    }
    expect(paceMs([1000, 2000], 0)).toBe(0);
    botPace.scale = 0;
    expect(paceMs([1000, 2000], 4)).toBe(0);
    botPace.scale = was;
  });
});
