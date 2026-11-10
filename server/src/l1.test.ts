import { describe, it, expect, afterAll } from 'bun:test';
import { startServer, rooms, validateMessage } from './index';
import { ranked } from './ranked';
import { matchlogs, decodeLog } from './matchlog';

const srv = startServer(0);
afterAll(() => srv.stop(true));

type Msg = Record<string, unknown>;
interface C { msgs: Msg[]; send: (m: Msg) => void; wait: (pred: (m: Msg) => boolean, ms?: number) => Promise<Msg>; close: () => void }

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let uid = 0;
const nm = (p: string) => `${p}${++uid}q${Math.floor(Math.random() * 1e5)}`;
const key = (c: string) => c.repeat(20) + String(1000 + Math.floor(Math.random() * 9000));

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
  await new Promise<void>((resolve, reject) => { ws.onopen = () => resolve(); ws.onerror = () => reject(new Error('ws error')); });
  return {
    msgs,
    send: (m) => ws.send(JSON.stringify(m)),
    wait: (pred, ms = 2000) => {
      const hit = msgs.find(pred);
      if (hit) return Promise.resolve(hit);
      return new Promise<Msg>((resolve, reject) => {
        const t = setTimeout(() => reject(new Error('timed out waiting for message')), ms);
        waiters.push({ pred, resolve: (m) => { clearTimeout(t); resolve(m); } });
      });
    },
    close: () => ws.close(),
  };
}

const is = (type: string, extra?: (m: Msg) => boolean) => (m: Msg) => m.type === type && (!extra || extra(m));

async function room1v1(hk: string, gk: string): Promise<[C, C, Msg]> {
  const host = await connect();
  const guest = await connect();
  host.send({ type: 'create_room', name: nm('LogHost'), pkey: hk });
  const created = await host.wait(is('room_created'));
  guest.send({ type: 'join_room', code: created.code, name: nm('LogGuest'), pkey: gk });
  await guest.wait(is('room_ready'));
  await host.wait(is('room_ready'));
  return [host, guest, created];
}

async function rankedPair(): Promise<[C, C, string, string]> {
  const ka = key('A'), kb = key('B');
  const a = await connect();
  const b = await connect();
  a.send({ type: 'find_match', ranked: true, name: nm('RankA'), pkey: ka, mods: [{ id: 'Steamodded', name: 'Steamodded', version: '1.0' }] });
  await a.wait(is('searching'));
  b.send({ type: 'find_match', ranked: true, name: nm('RankB'), pkey: kb });
  await a.wait(is('room_ready'));
  await b.wait(is('room_ready'));
  return [a, b, ka, kb];
}

describe('L1 messages are validated', () => {
  it('checks the new client messages', () => {
    expect(validateMessage({ type: 'match_history', limit: 10 }, 40)).toBeNull();
    expect(validateMessage({ type: 'match_history', limit: 500 }, 40)).toContain('limit');
    expect(validateMessage({ type: 'contest', match_id: 'abc', reason: 'x' }, 40)).toBeNull();
    expect(validateMessage({ type: 'contest' }, 40)).toContain('match_id');
    expect(validateMessage({ type: 'act', seq: 1, a: [] }, 40)).toBeNull();
    expect(validateMessage({ type: 'act', seq: 0, a: [] }, 40)).toContain('seq');
    expect(validateMessage({ type: 'act', seq: 1, a: [] }, 30_000)).toBeNull();
    expect(validateMessage({ type: 'replay_get', id: 'x' }, 40)).toBeNull();
    expect(validateMessage({ type: 'daily_get', kind: 'monthly' }, 40)).toContain('kind');
    expect(validateMessage({ type: 'find_match', ranked: 'yes' }, 40)).toContain('ranked');
  });
});

describe('ranked seeds', () => {
  it('the server seed is in the ranked ruleset before the start, so host and guest play the same seed', async () => {
    const a = await connect();
    const b = await connect();
    a.send({ type: 'find_match', ranked: true, name: nm('SeedA'), pkey: key('S'), mods: [{ id: 'Steamodded', name: 'Steamodded', version: '1.0' }] });
    await a.wait(is('searching'));
    b.send({ type: 'find_match', ranked: true, name: nm('SeedB'), pkey: key('T') });
    const ra = await a.wait(is('room_ready'));
    const rb = await b.wait(is('room_ready'));
    const seed = (ra.ruleset as { settings: Record<string, unknown> }).settings.custom_seed as string;
    expect(typeof seed).toBe('string');
    expect(seed.length).toBeGreaterThan(0);
    expect((rb.ruleset as { settings: Record<string, unknown> }).settings.custom_seed).toBe(seed);
    const [host, guest] = ra.host ? [a, b] : [b, a];
    host.send({ type: 'match_start', seed: 'ZZZZZZZZ', settings: { mode: 'nemesis' }, player_name: 'SeedHost' });
    expect((await guest.wait(is('match_start'))).seed).toBe(seed);
    expect((await host.wait(is('match_seed'))).seed).toBe(seed);
    expect(((await host.wait(is('match_session'))).ruleset as { settings: Record<string, unknown> }).settings.custom_seed).toBe(seed);
  });
});

describe('a casual 1v1 is logged from start to end', () => {
  it('match_id travels in the start, the end and the results, and history and replay find it', async () => {
    const hk = key('H'), gk = key('G');
    const [host, guest] = await room1v1(hk, gk);
    host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'nemesis', starting_lives: 1, pvp_start_round: 2, win_ante: 2 }, player_name: 'LogHostX' });
    const start = await guest.wait(is('match_start'));
    const id = start.match_id as string;
    expect(typeof id).toBe('string');
    expect((await host.wait(is('match_session'))).match_id).toBe(id);
    expect((await guest.wait(is('match_session'))).match_id).toBe(id);
    host.send({ type: 'act', seq: 1, a: [{ k: 'select', b: 'S' }] });
    guest.send({ type: 'act', seq: 1, a: [{ k: 'select', b: 'S' }] });
    guest.send({ type: 'act', seq: 2, a: [{ k: 'play', c: [1, 2] }] });
    host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    guest.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    host.send({ type: 'play_hand', score: '900', hands_left: 0 });
    guest.send({ type: 'play_hand', score: '100', hands_left: 0 });
    const endH = await host.wait(is('match_ended'));
    const endG = await guest.wait(is('match_ended'));
    expect(endH.match_id).toBe(id);
    expect(endG.match_id).toBe(id);
    const log = decodeLog(matchlogs.recent.get(id)!.packed!);
    expect(log?.header).toMatchObject({ kind: '1v1', ranked: false, mode: 'nemesis', seeds: ['TEST'] });
    expect(log?.header.players.map(p => p.is_bot)).toEqual([false, false]);
    const kinds = log?.events.map(e => e.e) ?? [];
    expect(kinds).toContain('blind_in');
    expect(kinds).toContain('live');
    expect(kinds).toContain('life');
    expect(log?.end).toMatchObject({ held: false, results: [{ pid: 0, result: 'win', score: '900' }, { pid: 1, result: 'lose' }] });
    guest.send({ type: 'match_history', pkey: gk });
    const hist = await guest.wait(is('match_history'));
    const item = (hist.items as Msg[])[0];
    expect(item).toMatchObject({ id, result: 'lose', ranked: false, has_replay: true });
    expect((item.players as Msg[]).length).toBe(2);
    expect(JSON.stringify(hist)).not.toContain(hk);
    guest.send({ type: 'replay_get', id });
    const rep = await guest.wait(is('replay_data'));
    expect(rep.streams).toEqual({ 0: [{ k: 'select', b: 'S' }], 1: [{ k: 'select', b: 'S' }, { k: 'play', c: [1, 2] }] });
    expect((rep.header as Msg).id).toBe(id);
    expect(JSON.stringify(rep)).not.toContain(gk);
    guest.send({ type: 'replay_get', id: 'nope' });
    expect((await guest.wait(is('replay_error'))).reason).toBe('not_found');
    guest.send({ type: 'contest', match_id: id, reason: 'x' });
    expect(await guest.wait(is('contest_result'))).toMatchObject({ ok: false, reason: 'not_ranked' });
    host.close(); guest.close();
  });
});

describe('the ranked queue', () => {
  it('needs a profile and refuses mods outside the allowlist with their ids', async () => {
    const a = await connect();
    a.send({ type: 'find_match', ranked: true, name: nm('NoKey') });
    expect(await a.wait(is('ranked_error'))).toMatchObject({ code: 'no_key', for: 'find_match' });
    const b = await connect();
    b.send({ type: 'find_match', ranked: true, name: nm('Modded'), pkey: key('M'), mods: [{ id: 'Steamodded', name: 'Steamodded', version: '1' }, { id: 'Cryptid', name: 'Cryptid', version: '0.5' }] });
    const err = await b.wait(is('ranked_error'));
    expect(err).toMatchObject({ code: 'mods_not_allowed', reason: 'mods_not_allowed', mods: ['Cryptid'] });
    expect(b.msgs.some(m => m.type === 'searching')).toBe(false);
    a.close(); b.close();
  });

  it('pairs only ranked players, sends the fixed ruleset and ignores the host settings', async () => {
    const quick = await connect();
    quick.send({ type: 'find_match', name: nm('Quick') });
    await quick.wait(is('searching'));
    const [a, b] = await rankedPair();
    expect(quick.msgs.some(m => m.type === 'room_ready')).toBe(false);
    const ready = await a.wait(is('room_ready'));
    expect(ready).toMatchObject({ ranked: true, host: true });
    expect((ready.ruleset as Msg).id).toBe('ranked');
    const code = ready.code as string;
    a.send({ type: 'match_settings', settings: { starting_lives: 9 } });
    a.send({ type: 'add_bot', level: 'easy' });
    await a.wait(is('bot_error'));
    expect(rooms[code].settings.starting_lives).toBe(4);
    a.send({ type: 'match_start', seed: 'RANKSEED', settings: { mode: 'faceoff', starting_lives: 9 }, player_name: 'RankAX' });
    const start = await b.wait(is('match_start'));
    expect(start).toMatchObject({ ranked: true });
    expect(start.settings).toMatchObject({ mode: 'nemesis', starting_lives: 4, hide_opp_score: true, ruleset_id: 'ranked' });
    expect((start.ruleset as Msg).locked).toBe(true);
    expect(start.seed).not.toBe('RANKSEED');
    expect((await a.wait(is('match_seed'))).seed).toBe(start.seed);
    const sess = await a.wait(is('match_session'));
    expect(sess).toMatchObject({ ranked: true, match_id: start.match_id });
    expect(b.msgs.some(m => m.type === 'match_settings')).toBe(false);
    b.send({ type: 'blind_entered', ante: 1, blind: 'S' });
    await a.wait(is('blind_entered', m => m.ante === 1));
    b.send({ type: 'blind_entered', ante: 5, blind: 'S' });
    b.send({ type: 'ping' });
    await b.wait(is('pong'));
    await sleep(50);
    expect(a.msgs.some(m => m.type === 'blind_entered' && m.ante === 5)).toBe(false);
    expect(matchlogs.of(rooms[code])?.flags).toEqual([{ code: 'ante_jump', detail: '1 to 5' }]);
    b.send({ type: 'match_finished', result: 'lose', reason: 'forfeited' });
    const res = await a.wait(is('ranked_result'));
    expect(res).toMatchObject({ counted: false, reason: 'held', match_id: start.match_id });
    a.send({ type: 'contest', match_id: start.match_id, reason: 'they skipped antes' });
    expect(await a.wait(is('contest_result'))).toMatchObject({ ok: true, match_id: start.match_id });
    quick.send({ type: 'cancel_search' });
    a.close(); b.close(); quick.close();
  });

  it('a contested ranked result is taken back until review', async () => {
    const [a, b, ka] = await rankedPair();
    a.send({ type: 'match_start', seed: 'RANKSEED2', settings: {}, player_name: 'RankAY' });
    const start = await b.wait(is('match_start'));
    for (const c of [a, b]) { c.send({ type: 'blind_entered', ante: 1, blind: 'S' }); c.send({ type: 'blind_entered', ante: 2, blind: 'S' }); }
    await sleep(40);
    b.send({ type: 'match_finished', result: 'lose', reason: 'forfeited' });
    const res = await a.wait(is('ranked_result'));
    expect(res.counted).toBe(true);
    expect(res.delta as number).toBeGreaterThan(0);
    expect(ranked.cached(ka)?.row.rp).toBe(res.delta as number);
    b.send({ type: 'contest', match_id: start.match_id, reason: 'disconnect' });
    expect(await b.wait(is('contest_result'))).toMatchObject({ ok: true });
    expect(ranked.cached(ka)?.row.rp).toBe(0);
    expect(await matchlogs.decide(start.match_id as string, 'apply')).toEqual({ ok: true });
    expect(ranked.cached(ka)?.row.rp).toBe(res.delta as number);
    a.send({ type: 'match_history', pkey: ka });
    const hist = await a.wait(is('match_history'));
    expect((hist.items as Msg[])[0]).toMatchObject({ id: start.match_id, ranked: true, status: 'applied', rp_delta: res.delta });
    a.close(); b.close();
  });
});

describe('daily and weekly rulesets', () => {
  it('come from the server and match the UTC date', async () => {
    const c = await connect();
    c.send({ type: 'daily_get' });
    const d = await c.wait(is('daily_ruleset', m => m.kind === 'daily'));
    const today = new Date().toISOString().slice(0, 10);
    expect(d.key).toBe(today);
    expect((d.ruleset as Msg).locked).toBe(true);
    c.send({ type: 'daily_get', kind: 'weekly' });
    const w = await c.wait(is('daily_ruleset', m => m.kind === 'weekly'));
    expect(String(w.key)).toMatch(/^\d{4}-W\d{2}$/);
    expect(w.ends_at as number).toBeGreaterThan(Date.now());
    c.close();
  });
});

describe('party matches are logged too', () => {
  it('party match_start and match_ended carry the log id', async () => {
    const host = await connect();
    host.send({ type: 'party_create', name: nm('PHost'), kind: 'br', pkey: key('P') });
    const j = await host.wait(is('party_joined'));
    const guest = await connect();
    guest.send({ type: 'party_join', code: j.code, name: nm('PGuest') });
    await guest.wait(is('party_joined'));
    guest.send({ type: 'party_ready', ready: true });
    await sleep(60);
    host.send({ type: 'party_start' });
    const s1 = await host.wait(is('match_start'));
    const s2 = await guest.wait(is('match_start'));
    expect(typeof s1.match_id).toBe('string');
    expect(s2.match_id).toBe(s1.match_id);
    const log = matchlogs.liveById.get(s1.match_id as string);
    expect(log?.header).toMatchObject({ kind: 'party', mode: 'br' });
    expect(log?.header.players.length).toBe(2);
    guest.send({ type: 'leave_match' });
    const end = await host.wait(is('match_ended'));
    expect(end.match_id).toBe(s1.match_id);
    await sleep(30);
    const done = decodeLog(matchlogs.recent.get(s1.match_id as string)!.packed!);
    expect(done?.events.some(e => e.e === 'forfeit' && e.pid === 1)).toBe(true);
    expect(done?.end?.reason).toBe('match_over');
    host.close(); guest.close();
  });
});

describe('ranked results for both players', () => {
  async function playOut(a: C, b: C, ante: number): Promise<Msg> {
    a.send({ type: 'match_start', seed: 'RPSEED', settings: {}, player_name: 'RpHost' });
    const start = await b.wait(is('match_start'));
    for (let x = 1; x <= ante; x++) for (const c of [a, b]) c.send({ type: 'blind_entered', ante: x, blind: 'S' });
    await sleep(40);
    b.send({ type: 'match_finished', result: 'lose', reason: 'forfeited' });
    return start;
  }

  function lineSum(r: Msg): number {
    return (r.lines as { k: string; v: number }[]).filter(l => l.k !== 'bots').reduce((s, l) => s + l.v, 0);
  }

  it('the winner and the loser each get what the server applied, and their profile and history match it', async () => {
    const [a, b, ka, kb] = await rankedPair();
    await ranked.load(kb);
    ranked.testSet(ranked.cached(kb)!, { rp: 150 }, Date.now());
    const start = await playOut(a, b, 3);
    const win = await a.wait(is('ranked_result'));
    const lose = await b.wait(is('ranked_result'));
    expect(win).toMatchObject({ result: 'win', counted: true, match_id: start.match_id });
    expect(lose).toMatchObject({ result: 'lose', counted: true, match_id: start.match_id });
    expect(win.delta as number).toBeGreaterThan(0);
    expect(lose.delta as number).toBeLessThan(0);
    for (const [r, k] of [[win, ka], [lose, kb]] as [Msg, string][]) {
      const before = (r.before as Msg).rp as number, after = (r.after as Msg).rp as number;
      expect(after).toBe(before + (r.delta as number));
      expect(lineSum(r)).toBe(r.delta as number);
      expect(ranked.cached(k)?.row.rp).toBe(after);
    }
    expect((lose.before as Msg).rp).toBe(150);
    for (const [c, r] of [[a, win], [b, lose]] as [C, Msg][]) {
      c.send({ type: 'ranked_profile' });
      const prof = await c.wait(is('ranked_profile'));
      expect((prof.profile as Msg).rp).toBe((r.after as Msg).rp);
      expect((prof.profile as Msg).matches).toBe(1);
      expect((prof.last as Msg).match_id).toBe(start.match_id);
      c.send({ type: 'ranked_history' });
      const hist = await c.wait(is('ranked_history'));
      expect((hist.matches as Msg[])[0]).toMatchObject({ id: start.match_id, delta: r.delta, result: r.result });
    }
    a.close(); b.close();
  });

  it('a player who leaves a held ranked match from the menu still gets the result on the new connection', async () => {
    const [a, b, ka] = await rankedPair();
    const ready = await a.wait(is('room_ready'));
    a.send({ type: 'match_start', seed: 'RPLEAVE', settings: {}, player_name: 'RpLeaver' });
    await b.wait(is('match_start'));
    for (let x = 1; x <= 2; x++) for (const c of [a, b]) c.send({ type: 'blind_entered', ante: x, blind: 'S' });
    await sleep(40);
    a.close();
    await b.wait(is('opponent_disconnected'));
    const a2 = await connect();
    a2.send({ type: 'leave_match', code: ready.code, token: ready.token });
    const mine = await a2.wait(is('ranked_result'));
    const theirs = await b.wait(is('ranked_result'));
    expect(mine).toMatchObject({ result: 'lose', counted: true });
    expect(theirs).toMatchObject({ result: 'win', counted: true });
    expect(ranked.cached(ka)?.row.rp).toBe((mine.after as Msg).rp as number);
    a2.close(); b.close();
  });

  it('a loss at 0 RP costs nothing, says so in its lines, and the profile stays at 0', async () => {
    const [a, b, , kb] = await rankedPair();
    const start = await playOut(a, b, 4);
    const lose = await b.wait(is('ranked_result'));
    expect(lose).toMatchObject({ result: 'lose', counted: true, delta: 0, before: { rp: 0 }, after: { rp: 0 } });
    expect(lineSum(lose)).toBe(0);
    expect((lose.lines as { k: string; v: number }[]).some(l => l.k === 'floor')).toBe(true);
    expect(ranked.cached(kb)?.row.rp).toBe(0);
    b.send({ type: 'ranked_history' });
    const hist = await b.wait(is('ranked_history'));
    expect((hist.matches as Msg[])[0]).toMatchObject({ id: start.match_id, delta: 0, result: 'lose' });
    a.close(); b.close();
  });
});
