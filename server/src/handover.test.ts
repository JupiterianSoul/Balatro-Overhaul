import { describe, it, expect, afterAll } from 'bun:test';
import path from 'path';
import { readFileSync } from 'fs';
import { startServer, rooms, parties, setTimings, handoverApi, ROOM_JSON, ROOM_SPECIAL } from './index';
import { MemoryHandoverStore, encodeEntry, decodeEntry, pack, unpack, handoverTiming, BOOT_ID, type HandoverEntry } from './handover';
import { PARTY_SKIP, SEAT_SKIP, type Party } from './party';
import { BOT_KEEP, BOT_SKIP, BotSocket, isBot } from './bots';
import { matchlogs } from './matchlog';

process.env.BOT_WORKER = `bun ${path.join(import.meta.dir, 'bot_fake_worker.ts')}`;
process.env.BOT_WORKERS = '1';

type Msg = Record<string, unknown>;
const srv = startServer(0);
const store = new MemoryHandoverStore();
handoverApi.setStore(store);
afterAll(() => srv.stop(true));

interface C { msgs: Msg[]; send: (m: Msg) => void; wait: (t: string, f?: (m: Msg) => boolean, ms?: number) => Promise<Msg>; close: () => void; }

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

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let uid = 0;
const nm = () => `Mover${++uid}`;

function fieldsOf(file: string, kind: 'interface' | 'class', name: string): string[] {
  const src = readFileSync(path.join(import.meta.dir, file), 'utf8');
  const start = src.indexOf(`${kind === 'interface' ? 'interface' : 'class'} ${name} {`);
  expect(start).toBeGreaterThanOrEqual(0);
  const out: string[] = [];
  let depth = 0;
  for (const line of src.slice(src.indexOf('{', start)).split('\n')) {
    const at = depth;
    for (const ch of line) { if (ch === '{') depth++; else if (ch === '}') depth--; }
    if (at === 1) {
      const m = /^\s{2}(?:readonly\s+|private\s+)?([A-Za-z_$][\w$]*)\??\s*[:=]/.exec(line);
      if (m) out.push(m[1]);
    }
    if (depth === 0 && out.length + at > 0 && line.includes('}')) break;
  }
  return out;
}

function killRoom(code: string): void {
  const r = rooms[code];
  if (!r) return;
  if (r.pvpTimer) clearTimeout(r.pvpTimer);
  if (r.holdTimer) clearTimeout(r.holdTimer);
  if (r.anteClock?.handle) clearTimeout(r.anteClock.handle);
  if (r.draft?.timer) clearTimeout(r.draft.timer);
  if (r.pick?.timer) clearTimeout(r.pick.timer);
  matchlogs.live.delete(r);
  delete rooms[code];
  for (const s of r.sockets) if (isBot(s)) { s.halt(); s.close(); }
}

function killParty(code: string): void {
  const p = parties[code];
  if (!p) return;
  if (p.pvpTimer) clearTimeout(p.pvpTimer);
  if (p.holdTimer) clearTimeout(p.holdTimer);
  matchlogs.live.delete(p);
  delete parties[code];
  for (const s of p.seats) if (s && isBot(s.ws)) { (s.ws as unknown as BotSocket).halt(); (s.ws as unknown as BotSocket).close(); }
}

async function moveOut(code: string, edit?: (e: HandoverEntry) => void): Promise<HandoverEntry> {
  const e = handoverApi.entries().find(x => x.code === code);
  expect(e).toBeDefined();
  const moved = decodeEntry(encodeEntry({ ...e!, boot: 'oldboot' }))!;
  if (edit) edit(moved);
  await store.put([moved]);
  if (moved.kind === 'room') killRoom(code); else killParty(code);
  return moved;
}

async function startMatch(settings: Msg): Promise<{ host: C; guest: C; code: string; tokens: string[] }> {
  const host = await connect();
  const guest = await connect();
  host.send({ type: 'create_room', name: nm() });
  const created = await host.wait('room_created');
  guest.send({ type: 'join_room', code: created.code, name: nm() });
  await guest.wait('room_ready');
  await host.wait('room_ready');
  host.send({ type: 'match_start', seed: 'MOVE', settings, player_name: 'Host' });
  const hs = await host.wait('match_session');
  const gs = await guest.wait('match_session');
  return { host, guest, code: created.code as string, tokens: [hs.token as string, gs.token as string] };
}

describe('every field is carried', () => {
  it('Room: each field is either copied or handled on its own', () => {
    const known = new Set<string>([...ROOM_JSON, ...ROOM_SPECIAL]);
    const missing = fieldsOf('index.ts', 'interface', 'Room').filter(f => !known.has(f));
    expect(missing).toEqual([]);
  });

  it('BotSocket: each field is kept or rebuilt', () => {
    const known = new Set<string>([...BOT_KEEP, ...BOT_SKIP]);
    const missing = fieldsOf('bots.ts', 'class', 'BotSocket').filter(f => !known.has(f));
    expect(missing).toEqual([]);
  });

  it('Party and Seat: every field survives the round trip', async () => {
    const pf = fieldsOf('party.ts', 'interface', 'Party');
    const sf = fieldsOf('party.ts', 'interface', 'Seat');
    const seat: Msg = {};
    for (const f of sf) seat[f] = f === 'ws' ? null : f === 'holdDeadline' ? Date.now() + 60_000 : f === 'snapshot' ? { data: 'QQ==', ante: 2 } : `${f}_v`;
    const p: Msg = {};
    for (const f of pf) p[f] = `${f}_v`;
    Object.assign(p, { code: 'PTST', phase: 'playing', seats: [seat, null], pvpTimer: null, holdTimer: null, pvpAnte: null, teamLives: { 0: 3 }, swap: { done: 1, last: null, seats: { 0: { data: null, hash: null, ante: 2, applied: 1 } }, log: [] } });
    const { partySnapshot, partyRestore } = await import('./party');
    const body = unpack(JSON.parse(JSON.stringify(pack(partySnapshot(p as unknown as Party, () => null))))) as Msg;
    const back = partyRestore(body, () => null) as unknown as Msg;
    for (const f of pf) if (!(PARTY_SKIP as readonly string[]).includes(f) && f !== 'seats' && f !== 'moved' && f !== 'pvpEndsAt' && f !== 'lastActivity') expect([f, back[f]]).toEqual([f, p[f]]);
    const s2 = (back.seats as Msg[])[0];
    for (const f of sf) if (!(SEAT_SKIP as readonly string[]).includes(f)) expect([f, s2[f]]).toEqual([f, seat[f]]);
    expect((back.moved as boolean[])[0]).toBe(true);
    if ((back as unknown as Party).holdTimer) clearTimeout((back as unknown as Party).holdTimer!);
    delete parties.PTST;
  });

  it('pack keeps Maps, Sets and nested values', () => {
    const v = { a: new Map<number, unknown>([[1, { x: new Set(['s']) }]]), b: [1, null, 'z'], c: undefined, f: () => 1 };
    const back = unpack(JSON.parse(JSON.stringify(pack(v)))) as Msg;
    expect((back.a as Map<number, Msg>).get(1)!.x).toEqual(new Set(['s']));
    expect(back.b).toEqual([1, null, 'z']);
    expect('c' in back).toBe(false);
    expect('f' in back).toBe(false);
  });
});

describe('the store', () => {
  it('expired rows are ignored', async () => {
    const s = new MemoryHandoverStore();
    const e: HandoverEntry = { code: 'XPRD', kind: 'room', tokens: ['a'], at: 0, boot: 'b', body: { code: 'XPRD' } };
    await s.put([e], Date.now() - handoverTiming.ttlMs - 1);
    expect(await s.find('XPRD')).toBeNull();
    await s.put([e]);
    expect((await s.find('XPRD'))?.code).toBe('XPRD');
  });

  it('a new connection gets the boot id', async () => {
    const c = await connect();
    const info = await c.wait('server_info');
    expect(info.boot).toBe(BOOT_ID);
    expect(typeof info.started).toBe('number');
    c.close();
  });
});

describe('a 1v1 match moves to the new server', () => {
  it('both players come back, the PvP timer keeps its remaining time, the match plays to the end', async () => {
    const { host, guest, code, tokens } = await startMatch({ mode: 'faceoff', starting_lives: 1 });
    host.send({ type: 'save_snapshot', data: Buffer.from('host run').toString('base64'), ante: 1, blind: 'S', seq: 3 });
    await sleep(50);
    host.send({ type: 'ready_blind' });
    guest.send({ type: 'ready_blind' });
    await host.wait('start_blind');
    host.send({ type: 'blind_entered', ante: 1, blind: 'S' });
    guest.send({ type: 'blind_entered', ante: 1, blind: 'S' });
    host.send({ type: 'play_hand', score: '300', hands_left: 2 });
    await sleep(80);
    const before = handoverApi.roomSnapshot(rooms[code]);
    await moveOut(code, e => { e.body.$pvpLeft = 5000; });
    host.close(); guest.close();
    expect(rooms[code]).toBeUndefined();

    const thief = await connect();
    thief.send({ type: 'rejoin_match', code, token: 'f'.repeat(32) });
    expect((await thief.wait('rejoin_failed')).reason).toBe('not_found');
    expect(rooms[code]).toBeUndefined();
    thief.close();

    const h2 = await connect();
    h2.send({ type: 'rejoin_match', code, token: tokens[0] });
    const ok = await h2.wait('rejoin_ok');
    expect(ok.moved).toBe(true);
    expect(ok.boot).toBe(BOOT_ID);
    expect((ok.snapshot as Msg).data).toBe(Buffer.from('host run').toString('base64'));
    expect((ok.pvp as Msg).myScore).toBe(300);
    const after = handoverApi.roomSnapshot(rooms[code]);
    for (const k of ROOM_JSON) {
      if (['lastActivity', 'holdDeadline', 'dropReason', 'moved', 'pvpPaused', 'pvpMsLeft'].includes(k)) continue;
      expect([k, after[k]]).toEqual([k, before[k]]);
    }
    expect(store.rows.has(code)).toBe(false);

    const g2 = await connect();
    g2.send({ type: 'rejoin_match', code, token: tokens[1] });
    expect((await g2.wait('rejoin_ok')).moved).toBe(true);
    const resumed = await h2.wait('pvp_timer_resumed');
    expect(resumed.ms).toBe(5000);
    expect(rooms[code].pvpEndsAt! - Date.now()).toBeLessThanOrEqual(5000);

    h2.send({ type: 'rejoin_match', code, token: tokens[0] });
    const again = await h2.wait('rejoin_failed', undefined, 1000).catch(() => null);
    void again;
    h2.send({ type: 'play_hand', score: '900', hands_left: 0 });
    g2.send({ type: 'play_hand', score: '100', hands_left: 0 });
    const res = await h2.wait('pvp_resolved');
    expect(res.result).toBe('win');
    const end = await g2.wait('match_ended');
    expect(end.result).toBe('lose');
    h2.close(); g2.close();
  });

  it('the ante clock comes back paused with its remaining time and runs again once both are back', async () => {
    const { host, guest, code, tokens } = await startMatch({ mode: 'attrition', starting_lives: 2, ante_timer: true, ante_timer_base: 120 });
    host.send({ type: 'ready_blind' });
    await guest.wait('ante_timer', m => m.state === 'running');
    await moveOut(code, e => { (e.body.$anteClock as Msg).msLeft = 7000; });
    host.close(); guest.close();
    const h2 = await connect();
    h2.send({ type: 'rejoin_match', code, token: tokens[0] });
    const ok = await h2.wait('rejoin_ok');
    expect((ok.anteClock as Msg).paused).toBe(true);
    expect((ok.anteClock as Msg).msLeft).toBe(7000);
    const g2 = await connect();
    g2.send({ type: 'rejoin_match', code, token: tokens[1] });
    await g2.wait('rejoin_ok');
    const run = await g2.wait('ante_timer', m => m.state === 'running');
    expect(run.msLeft as number).toBeLessThanOrEqual(7000);
    expect(run.msLeft as number).toBeGreaterThan(6000);
    h2.close(); g2.close();
  });

  it('a 2.0.5 style rejoin that arrives before the old server wrote its rows still lands', async () => {
    const { host, guest, code, tokens } = await startMatch({ mode: 'nemesis', starting_lives: 1 });
    const e = handoverApi.entries().find(x => x.code === code)!;
    killRoom(code);
    host.close(); guest.close();
    const h2 = await connect();
    h2.send({ type: 'rejoin_match', code, token: tokens[0] });
    await sleep(600);
    await store.put([{ ...decodeEntry(encodeEntry(e))!, boot: 'oldboot' }]);
    const ok = await h2.wait('rejoin_ok');
    expect(ok.moved).toBe(true);
    expect(ok.moved).toBe(true);
    h2.send({ type: 'game_over', ante: 1, blind: 'S', score: 1 });
    expect((await h2.wait('match_ended')).result).toBe('lose');
    h2.close();
  });
});

describe('the pick screen moves', () => {
  it('a lobby on the pick screen comes back with the same picks and the clock left', async () => {
    const host = await connect();
    const guest = await connect();
    host.send({ type: 'create_room', name: nm(), version: '64' });
    const created = await host.wait('room_created');
    const code = created.code as string;
    expect(rooms[code].gameVersion).toBe('64');
    guest.send({ type: 'join_room', code, name: nm(), version: '64' });
    await guest.wait('room_ready');
    rooms[code].settings = { ...rooms[code].settings, different_decks: true, joker_picks: 2 };
    host.send({ type: 'pick_start', pool: ['Red Deck', 'Blue Deck'] });
    await host.wait('pick_state');
    host.send({ type: 'pick_set', deck: 'Blue Deck' });
    await sleep(60);
    const tokens = [...rooms[code].tokens];
    const pickBefore = { ...rooms[code].pick!, timer: null };
    await moveOut(code, e => { (e.body.$pick as Msg).$left = 30_000; });
    host.close(); guest.close();
    const h2 = await connect();
    h2.send({ type: 'rejoin_match', code, token: tokens[0] });
    const back = await h2.wait('lobby_rejoined');
    expect(back.moved).toBe(true);
    expect(back.playerId).toBe(0);
    const ps = await h2.wait('pick_state');
    expect(ps.pick_id ?? ps.id).toBeDefined();
    const p = rooms[code].pick!;
    expect(p.decks).toEqual(pickBefore.decks);
    expect(p.deadline - Date.now()).toBeLessThanOrEqual(30_000);
    expect(p.deadline - Date.now()).toBeGreaterThan(25_000);
    const g2 = await connect();
    g2.send({ type: 'rejoin_match', code, token: tokens[1] });
    expect((await g2.wait('lobby_rejoined')).playerId).toBe(1);
    g2.send({ type: 'pick_set', deck: 'Red Deck', ready: true });
    h2.send({ type: 'pick_set', deck: 'Blue Deck', ready: true });
    const done = await h2.wait('pick_done', undefined, 4000);
    expect((done.decks as Msg)['0']).toBe('Blue Deck');
    h2.close(); g2.close();
  });
});

describe('a match against a bot moves', () => {
  it('the bot continues its own run on the new server and the match plays to the end', async () => {
    setTimings({});
    const host = await connect();
    host.send({ type: 'create_room', name: nm() });
    const created = await host.wait('room_created');
    const code = created.code as string;
    host.send({ type: 'add_bot', level: 'easy' });
    await host.wait('room_ready');
    host.send({ type: 'match_start', seed: 'BOTMOVE', settings: { mode: 'attrition', starting_lives: 1 }, player_name: 'Host' });
    const hs = await host.wait('match_session');
    const bot0 = rooms[code].sockets[1] as unknown as BotSocket;
    for (let i = 0; i < 100 && !(bot0.mark && bot0.mark.run); i++) await sleep(50);
    expect(bot0.mark?.run).toBeDefined();
    const mark = { ...bot0.mark! };
    await moveOut(code);
    host.close();
    const h2 = await connect();
    h2.send({ type: 'rejoin_match', code, token: hs.token });
    const ok = await h2.wait('rejoin_ok');
    expect(ok.moved).toBe(true);
    const bot = rooms[code].sockets[1] as unknown as BotSocket;
    expect(isBot(bot)).toBe(true);
    expect(bot).not.toBe(bot0);
    expect(bot.data.name).toBe(bot0.data.name);
    expect(bot.mark?.ante).toBe(mark.ante);
    for (let i = 0; i < 100 && bot.restarts === 0; i++) await sleep(50);
    expect(bot.restarts).toBe(1);
    expect(bot.simple).toBe(false);
    h2.send({ type: 'game_over', ante: 1, blind: 'S', score: 1 });
    const end = await h2.wait('match_ended');
    expect(end.result).toBe('lose');
    h2.close();
  });
});

describe('a party match moves', () => {
  it('three players come back to the same party and the blind resolves', async () => {
    const host = await connect();
    host.send({ type: 'party_create', name: nm(), kind: 'br' });
    const j = await host.wait('party_joined');
    const code = j.code as string;
    const cs = [host];
    const tokens = [j.token as string];
    for (let i = 1; i < 3; i++) {
      const c = await connect();
      c.send({ type: 'party_join', code, name: nm() });
      const r = await c.wait('party_joined');
      tokens.push(r.token as string);
      cs.push(c);
    }
    for (const c of cs.slice(1)) c.send({ type: 'party_ready', ready: true });
    await sleep(60);
    host.send({ type: 'party_start' });
    for (const c of cs) await c.wait('match_start');
    const livesBefore = parties[code].seats.map(s => s?.lives);
    await moveOut(code);
    for (const c of cs) c.close();
    const back: C[] = [];
    for (let i = 0; i < 3; i++) {
      const c = await connect();
      c.send({ type: 'rejoin_match', code, token: tokens[i] });
      const ok = await c.wait('rejoin_ok');
      expect(ok.moved).toBe(true);
      expect(ok.party).toBe(true);
      back.push(c);
    }
    expect(parties[code].seats.map(s => s?.lives)).toEqual(livesBefore);
    for (const c of back) c.send({ type: 'blind_entered', ante: 1, blind: 'L' });
    await sleep(40);
    for (const c of back) c.send({ type: 'ready_blind' });
    for (const c of back) await c.wait('start_blind');
    back.forEach((c, i) => c.send({ type: 'play_hand', score: (i + 1) * 100, hands_left: 0 }));
    for (const c of back) await c.wait('pvp_resolved');
    for (const c of back) c.close();
  });
});

describe('shutting down', () => {
  it('moveOut tells every in-match socket where its match goes and writes the rows', async () => {
    const { host, guest, code } = await startMatch({ mode: 'nemesis', starting_lives: 2 });
    const idle = await connect();
    const s2 = new MemoryHandoverStore();
    handoverApi.setStore(s2);
    const n = await handoverApi.moveOut();
    expect(n).toBeGreaterThanOrEqual(1);
    expect((await host.wait('server_moving')).code).toBe(code);
    expect((await guest.wait('server_moving')).party).toBe(false);
    expect((await idle.wait('server_moving')).code).toBeUndefined();
    const row = await s2.find(code);
    expect(row?.tokens.length).toBe(2);
    handoverApi.reset();
    handoverApi.setStore(store);
  });
});
