import { describe, it, expect, afterAll } from 'bun:test';
import { startServer, setTimings, validateMessage } from './index';
import { partyCfg, resolveParty, raidTarget, bossChips, teamScore, teamTotals, balanceTeams, teamCount, cleanPartySettings, RPlayer } from './party_rules';
import { parties, partyTiming } from './party';

type Msg = Record<string, unknown>;
const srv = startServer(0);
afterAll(() => srv.stop(true));

interface C { msgs: Msg[]; send: (m: Msg) => void; wait: (t: string, f?: (m: Msg) => boolean, ms?: number) => Promise<Msg>; close: () => void; }

function decode(raw: string): Msg {
  const p = JSON.parse(raw) as Msg;
  if (p.z === 1 && typeof p.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(p.d, 'base64'))).toString('utf8')) as Msg;
  return p;
}

let uid = 0;
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
    close: () => ws.close(),
  };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const nm = () => `Tester${++uid}x${Math.floor(Math.random() * 1e6)}`;

let hostToken = '';
async function party(n: number, settings: Msg): Promise<{ cs: C[]; code: string }> {
  const host = await connect();
  host.send({ type: 'party_create', name: nm(), kind: settings.party_kind ?? 'br' });
  const j = await host.wait('party_joined');
  const code = j.code as string;
  hostToken = j.token as string;
  host.send({ type: 'match_settings', settings });
  const cs = [host];
  for (let i = 1; i < n; i++) {
    const c = await connect();
    c.send({ type: 'party_join', code, name: nm() });
    const r = await c.wait('party_joined');
    expect(r.playerId).toBe(i);
    cs.push(c);
  }
  return { cs, code };
}

async function start(cs: C[]): Promise<void> {
  for (const c of cs.slice(1)) c.send({ type: 'party_ready', ready: true });
  await sleep(60);
  cs[0].send({ type: 'party_start' });
  for (const c of cs) await c.wait('match_start');
}

async function blind(cs: C[], ante: number, scores: (number | null)[]): Promise<Msg[]> {
  for (let i = 0; i < cs.length; i++) if (scores[i] !== null) cs[i].send({ type: 'blind_entered', ante, blind: 'L' });
  await sleep(40);
  for (let i = 0; i < cs.length; i++) if (scores[i] !== null) cs[i].send({ type: 'ready_blind' });
  for (let i = 0; i < cs.length; i++) if (scores[i] !== null) await cs[i].wait('start_blind');
  for (let i = 0; i < cs.length; i++) if (scores[i] !== null) cs[i].send({ type: 'play_hand', score: scores[i], hands_left: 0 });
  const out: Msg[] = [];
  for (let i = 0; i < cs.length; i++) if (scores[i] !== null) out[i] = await cs[i].wait('pvp_resolved');
  return out;
}

const P = (pid: number, score: number, team = 0, alive = true): RPlayer => ({ pid, score, team, alive, lives: 3 });

describe('party ready flow like the game', () => {
  it('ready on the blind select starts the raid boss at ante 1 before anyone entered it', async () => {
    const { cs } = await party(2, { party_kind: 'raid' });
    await start(cs);
    for (const c of cs) c.send({ type: 'ready_blind', ante: 1, blind: 'L' });
    for (const c of cs) await c.wait('start_blind');
    for (const c of cs) c.send({ type: 'blind_entered', ante: 1, blind: 'L' });
    for (const c of cs) c.send({ type: 'play_hand', score: 99999, hands_left: 0 });
    for (const c of cs) expect((await c.wait('pvp_resolved')).result).toBe('win');
    for (const c of cs) c.close();
  });
  it('raid every blind makes the small blind a raid with a smaller target', async () => {
    const { cs } = await party(2, { party_kind: 'raid', raid_every_blind: true });
    await start(cs);
    for (const c of cs) c.send({ type: 'ready_blind', ante: 1, blind: 'S' });
    for (const c of cs) await c.wait('start_blind');
    expect(raidTarget(partyCfg({ party_kind: 'raid' }), 2, 1, 'S')).toBe(Math.round(raidTarget(partyCfg({ party_kind: 'raid' }), 2, 1) / 2));
    for (const c of cs) c.close();
  });
});

describe('party leaving', () => {
  const listed = async (code: string): Promise<boolean> => {
    const v = await connect();
    v.send({ type: 'list_rooms' });
    const list = await v.wait('room_list');
    v.close();
    const id = parties[code]?.id;
    return !!id && (list.rooms as Msg[]).some((r) => r.id === id);
  };
  it('leaving in the run tells everyone else and does not hold the seat', async () => {
    const { cs, code } = await party(3, { party_kind: 'raid' });
    await start(cs);
    const name = parties[code].seats[2]!.name;
    cs[2].send({ type: 'leave_match' });
    for (const c of [cs[0], cs[1]]) expect(await c.wait('party_notice')).toMatchObject({ event: 'left', pid: 2, name });
    expect(parties[code].seats[2]!.holdDeadline).toBeNull();
    const st = await cs[0].wait('party_state', (m) => (m.players as Msg[]).some((x) => x.pid === 2 && x.alive === false));
    expect(st).toBeTruthy();
    cs[1].send({ type: 'party_leave' });
    expect(await cs[0].wait('party_notice')).toMatchObject({ event: 'left', pid: 1 });
    expect(parties[code].seats[1]!.alive).toBe(false);
    for (const c of cs) c.close();
  });
  it('leaving the lobby tells the others; a dropped socket is held and announced', async () => {
    const { cs } = await party(3, { party_kind: 'br' });
    cs[1].send({ type: 'party_leave' });
    for (const c of [cs[0], cs[2]]) expect(await c.wait('party_notice')).toMatchObject({ event: 'left', pid: 1 });
    cs[2].close();
    expect(await cs[0].wait('party_notice')).toMatchObject({ event: 'dropped', pid: 2 });
    cs[0].close();
  });
  it('a party nobody is connected to leaves the room list at once', async () => {
    const { cs, code } = await party(2, { party_kind: 'br' });
    expect(await listed(code)).toBe(true);
    cs[1].close();
    await sleep(50);
    cs[0].send({ type: 'party_leave' });
    await sleep(50);
    expect(await listed(code)).toBe(false);
    cs[0].close();
  });
  it('a party whose players all quit mid run is closed and unlisted', async () => {
    const { cs, code } = await party(2, { party_kind: 'raid' });
    await start(cs);
    cs[0].send({ type: 'leave_match' });
    await cs[1].wait('party_notice');
    cs[1].send({ type: 'leave_match' });
    await sleep(50);
    expect(parties[code]).toBeUndefined();
    for (const c of cs) c.close();
  });
});

describe('party seat held on a trip to the menu', () => {
  const entryOf = async (code: string): Promise<Msg | undefined> => {
    const v = await connect();
    v.send({ type: 'list_rooms' });
    const list = await v.wait('room_list');
    v.close();
    return (list.rooms as Msg[]).find((r) => r.id === parties[code]?.id);
  };
  it('the seat is held, the others see the player away and the match goes on', async () => {
    setTimings({ rejoinHoldMs: 60000 });
    const { cs, code } = await party(3, { party_kind: 'br' });
    await start(cs);
    const sess = await cs[1].wait('match_session');
    expect(sess.id).toBe(parties[code].id);
    const name = parties[code].seats[1]!.name;
    cs[1].send({ type: 'return_to_menu' });
    for (const c of [cs[0], cs[2]]) expect(await c.wait('party_notice')).toMatchObject({ event: 'menu', pid: 1, name });
    const st = await cs[0].wait('party_state', (m) => (m.players as Msg[]).some((p) => p.pid === 1 && p.connected === false));
    expect((st.players as Msg[]).find((p) => p.pid === 1)).toMatchObject({ alive: true });
    const seat = parties[code].seats[1]!;
    expect(seat.alive).toBe(true);
    expect(seat.holdDeadline! - Date.now()).toBeGreaterThan(50000);
    expect(parties[code].phase).toBe('playing');
    expect(cs[0].msgs.some((m) => m.type === 'match_ended')).toBe(false);
    const entry = await entryOf(code);
    expect(entry).toMatchObject({ inMatch: true, seatHeld: true, party: true });
    cs[1].send({ type: 'check_rejoin', code, token: sess.token });
    const status = await cs[1].wait('rejoin_status');
    expect(status).toMatchObject({ rejoinable: true, party: true, kind: 'br' });
    expect(status.secondsLeft as number).toBeGreaterThan(50);
    cs[1].close();
    for (const c of [cs[0], cs[2]]) c.close();
  });

  it('a player back from the menu rejoins their run with their state and plays on', async () => {
    setTimings({ rejoinHoldMs: 60000 });
    const { cs, code } = await party(3, { party_kind: 'br' });
    await start(cs);
    const sess = await cs[1].wait('match_session');
    cs[1].send({ type: 'blind_entered', ante: 1, blind: 'B' });
    cs[1].send({ type: 'save_snapshot', data: 'x'.repeat(64), seq: 3, ante: 1, blind: 'Big' });
    await cs[1].wait('snapshot_ack');
    cs[1].send({ type: 'return_to_menu' });
    await cs[0].wait('party_notice', (m) => m.event === 'menu');
    cs[1].close();
    const back = await connect();
    back.send({ type: 'rejoin_match', code, token: sess.token });
    const ok = await back.wait('rejoin_ok');
    expect(ok).toMatchObject({ party: true, playerId: 1, code, id: parties[code].id, currentAnte: 1, currentBlind: 'B' });
    expect((ok.snapshot as Msg).seq).toBe(3);
    for (const c of [cs[0], cs[2]]) expect(await c.wait('party_notice', (m) => m.event === 'rejoined')).toMatchObject({ pid: 1 });
    expect(parties[code].seats[1]!.holdDeadline).toBeNull();
    expect((await entryOf(code))?.seatHeld).toBe(false);
    const r = await blind([cs[0], back, cs[2]], 2, [10, 30, 20]);
    expect(r[1]).toMatchObject({ result: 'win' });
    expect(r[0]).toMatchObject({ result: 'lose', myLives: 3 });
    for (const c of [cs[0], back, cs[2]]) c.close();
  });

  it('blinds missed while away count like for a dropped player: one free sit out, then 0', async () => {
    setTimings({ rejoinHoldMs: 60000 });
    const { cs, code } = await party(3, { party_kind: 'br' });
    await start(cs);
    await cs[2].wait('match_session');
    cs[2].send({ type: 'return_to_menu' });
    await cs[0].wait('party_state', (m) => (m.players as Msg[]).some((p) => p.pid === 2 && p.connected === false));
    const r1 = await blind([cs[0], cs[1]], 2, [10, 20]);
    expect(r1[0]).toMatchObject({ result: 'lose', myLives: 3 });
    expect(parties[code].seats[2]!.lives).toBe(4);
    const r2 = await blind([cs[0], cs[1]], 3, [10, 20]);
    expect(r2[0]).toMatchObject({ result: 'win', myLives: 3 });
    expect(parties[code].seats[2]!.lives).toBe(3);
    for (const c of cs) c.close();
  });

  it('when the hold runs out the player is out and told why', async () => {
    setTimings({ rejoinHoldMs: 150 });
    const { cs, code } = await party(3, { party_kind: 'br' });
    await start(cs);
    const sess = await cs[1].wait('match_session');
    cs[1].send({ type: 'return_to_menu' });
    await cs[0].wait('party_notice', (m) => m.event === 'menu');
    const st = await cs[0].wait('party_state', (m) => (m.players as Msg[]).some((p) => p.pid === 1 && p.alive === false));
    expect(st).toBeTruthy();
    expect(parties[code].seats[1]!.endReason).toBe('rejoin_expired');
    expect(parties[code].phase).toBe('playing');
    cs[1].send({ type: 'check_rejoin', code, token: sess.token });
    expect(await cs[1].wait('rejoin_status')).toMatchObject({ rejoinable: false, matchOver: true, reason: 'rejoin_expired', result: 'lose' });
    cs[1].send({ type: 'rejoin_match', code, token: sess.token });
    expect(await cs[1].wait('rejoin_failed')).toMatchObject({ rejoinable: false, reason: 'rejoin_expired' });
    setTimings({ rejoinHoldMs: 60000 });
    for (const c of cs) c.close();
  });

  it('Leave match from the menu prompt gives the held seat up and the party goes on', async () => {
    setTimings({ rejoinHoldMs: 60000 });
    const { cs, code } = await party(3, { party_kind: 'br' });
    await start(cs);
    const sess = await cs[1].wait('match_session');
    cs[1].send({ type: 'return_to_menu' });
    await cs[0].wait('party_notice', (m) => m.event === 'menu');
    cs[1].close();
    const back = await connect();
    back.send({ type: 'leave_match', code, token: sess.token });
    expect(await back.wait('rejoin_status')).toMatchObject({ party: true, rejoinable: false, matchOver: true, reason: 'abandoned', result: 'lose' });
    for (const c of [cs[0], cs[2]]) expect(await c.wait('party_notice', (m) => m.event === 'left')).toMatchObject({ pid: 1 });
    expect(parties[code].seats[1]!).toMatchObject({ alive: false, holdDeadline: null, endReason: 'abandoned' });
    expect(parties[code].phase).toBe('playing');
    back.send({ type: 'check_rejoin', code, token: sess.token });
    expect(await back.wait('rejoin_status')).toMatchObject({ rejoinable: false, reason: 'abandoned' });
    for (const c of [cs[0], back, cs[2]]) c.close();
  });

  it('a menu trip in the lobby still leaves the seat', async () => {
    const { cs, code } = await party(3, { party_kind: 'br' });
    cs[1].send({ type: 'return_to_menu' });
    for (const c of [cs[0], cs[2]]) expect(await c.wait('party_notice')).toMatchObject({ event: 'left', pid: 1 });
    expect(parties[code].seats[1]).toBeNull();
    for (const c of cs) c.close();
  });
});

describe('party PvP schedule after a player comes back', () => {
  const away = async (cs: C[], code: string, pid: number): Promise<C> => {
    const sess = await cs[pid].wait('match_session');
    cs[pid].send({ type: 'return_to_menu' });
    await cs[0 === pid ? 1 : 0].wait('party_notice', (m) => m.event === 'menu');
    cs[pid].close();
    await blind(cs.filter((_, i) => i !== pid), 2, [10, 20]);
    const back = await connect();
    back.send({ type: 'rejoin_match', code, token: sess.token });
    const ok = await back.wait('rejoin_ok');
    expect((ok.settings as Msg).mode).toBe('nemesis');
    return back;
  };

  it('ready on a PvP blind played while away is a solo pass at once, and the next PvP blind waits for the player', async () => {
    setTimings({ rejoinHoldMs: 60000 });
    const { cs, code } = await party(3, { party_kind: 'br' });
    await start(cs);
    const back = await away(cs, code, 2);
    for (const c of cs.slice(0, 2)) c.send({ type: 'ready_blind', ante: 3, blind: 'L' });
    await sleep(40);
    back.send({ type: 'ready_blind', ante: 2, blind: 'L' });
    expect(await back.wait('start_blind', (m) => m.solo === true, 500)).toMatchObject({ party: true });
    back.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    back.send({ type: 'play_hand', score: 40, hands_left: 0 });
    expect(await back.wait('pvp_resolved', (m) => m.solo === true)).toMatchObject({ result: 'draw', myLives: 4 });
    expect(parties[code].pvpStarted).toBe(false);
    expect(cs[0].msgs.some((m) => m.type === 'start_blind')).toBe(false);
    back.send({ type: 'ready_blind', ante: 3, blind: 'L' });
    for (const c of [cs[0], cs[1], back]) await c.wait('start_blind', (m) => m.solo !== true, 500);
    cs[0].send({ type: 'play_hand', score: 10, hands_left: 0 });
    cs[1].send({ type: 'play_hand', score: 20, hands_left: 0 });
    back.send({ type: 'play_hand', score: 30, hands_left: 0 });
    expect(await back.wait('pvp_resolved', (m) => m.ante === 3)).toMatchObject({ result: 'win', myLives: 4 });
    expect(parties[code].seats[0]!.lives).toBe(2);
    for (const c of [cs[0], cs[1], back]) c.close();
  });

  it('an old client that enters the missed PvP blind and fails it loses no life', async () => {
    setTimings({ rejoinHoldMs: 60000 });
    const { cs, code } = await party(3, { party_kind: 'br' });
    await start(cs);
    const back = await away(cs, code, 2);
    back.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    await back.wait('start_blind', (m) => m.solo === true);
    back.send({ type: 'game_over', ante: 2, blind: 'L', score: 526 });
    expect(await back.wait('pvp_resolved', (m) => m.solo === true)).toMatchObject({ result: 'draw', myLives: 4 });
    await sleep(40);
    expect(back.msgs.some((m) => m.type === 'match_state_update' && m.event === 'life_lost')).toBe(false);
    expect(parties[code].seats[2]!.lives).toBe(4);
    for (const c of [cs[0], cs[1], back]) c.close();
  });

  it('a ready on a PvP blind that started without the player lets them in', async () => {
    partyTiming.blindMs = 600;
    const { cs } = await party(3, { party_kind: 'br' });
    await start(cs);
    for (const c of cs.slice(0, 2)) c.send({ type: 'ready_blind', ante: 2, blind: 'L' });
    for (const c of cs.slice(0, 2)) await c.wait('start_blind', () => true, 2000);
    cs[2].send({ type: 'ready_blind', ante: 2, blind: 'L' });
    expect(await cs[2].wait('start_blind', () => true, 300)).toMatchObject({ party: true });
    cs[0].send({ type: 'play_hand', score: 10, hands_left: 0 });
    cs[1].send({ type: 'play_hand', score: 20, hands_left: 0 });
    await sleep(100);
    expect(cs[0].msgs.some((m) => m.type === 'pvp_resolved')).toBe(false);
    cs[2].send({ type: 'play_hand', score: 30, hands_left: 0 });
    expect(await cs[2].wait('pvp_resolved', () => true, 1000)).toMatchObject({ result: 'win', myScore: 30 });
    partyTiming.blindMs = 0;
    for (const c of cs) c.close();
  });

  it('a player who ran past the PvP blinds does not hold them or move the next one to their ante', async () => {
    const { cs, code } = await party(3, { party_kind: 'br' });
    await start(cs);
    for (const c of cs.slice(0, 2)) c.send({ type: 'ready_blind', ante: 2, blind: 'L' });
    await sleep(40);
    cs[2].send({ type: 'blind_entered', ante: 2, blind: 'L' });
    cs[2].send({ type: 'blind_finished', ante: 2, blind: 'L', score: 720 });
    cs[2].send({ type: 'blind_entered', ante: 3, blind: 'S' });
    for (const c of cs.slice(0, 2)) await c.wait('start_blind', () => true, 500);
    cs[2].send({ type: 'blind_entered', ante: 5, blind: 'L' });
    cs[0].send({ type: 'play_hand', score: 10, hands_left: 0 });
    cs[1].send({ type: 'play_hand', score: 20, hands_left: 0 });
    expect(await cs[0].wait('pvp_resolved', (m) => m.ante === 2, 500)).toMatchObject({ lowest: 2 });
    expect(parties[code].seats[2]!.lives).toBe(3);
    expect(parties[code].pvpAnte).toBeNull();
    for (const c of cs.slice(0, 2)) c.send({ type: 'ready_blind', ante: 3, blind: 'L' });
    for (const c of cs.slice(0, 2)) await c.wait('start_blind', () => true, 500);
    expect(parties[code].pvpAnte).toBe(3);
    for (const c of cs) c.close();
  });
});

describe('party modes as the client sees them', () => {
  const view = (m: Msg) => m.view as Msg;
  it('raid: every client gets the same team target and live team total, from ready_blind on', async () => {
    const { cs } = await party(3, { party_kind: 'raid' });
    await start(cs);
    for (const c of cs) c.send({ type: 'ready_blind', ante: 1, blind: 'L' });
    for (const c of cs) await c.wait('start_blind');
    for (const c of cs) c.send({ type: 'blind_entered', ante: 1, blind: 'L' });
    const target = raidTarget(partyCfg({ party_kind: 'raid' }), 3, 1, 'L');
    cs[0].send({ type: 'play_hand', score: 400, hands_left: 3 });
    for (const c of cs) {
      const e = await c.wait('enemy_info');
      expect(e.score).toBe(String(target));
      expect(view(e)).toMatchObject({ kind: 'raid', target, total: 400, n: 3 });
    }
    const st = await cs[1].wait('party_state', (m) => view(m)?.total === 400);
    expect(view(st)).toMatchObject({ mine: 0, waiting: 2, target });
    cs[0].send({ type: 'play_hand', score: 500, hands_left: 0 });
    const w = await cs[0].wait('party_state', (m) => view(m)?.total === 500);
    expect(view(w)).toMatchObject({ mine: 500, waiting: 2, finished: true });
    cs[1].send({ type: 'play_hand', score: target, hands_left: 0 });
    cs[2].send({ type: 'play_hand', score: 1, hands_left: 0 });
    for (const c of cs) {
      const r = await c.wait('pvp_resolved');
      expect(r).toMatchObject({ kind: 'raid', result: 'win', lifeLost: false, raidTotal: target + 501, raidTarget: target, raidLives: 3, mvpBonus: 3, mvpScore: target });
      expect(r.mvp).toBe(c === cs[1]);
    }
    for (const c of cs) c.close();
  });
  it('raid every blind: small and big blinds carry their own smaller targets', async () => {
    const { cs } = await party(2, { party_kind: 'raid', raid_every_blind: true, raid_lives: 2 });
    await start(cs);
    const cfg = partyCfg({ party_kind: 'raid' });
    for (const [b, part] of [['S', 'S'], ['B', 'B']] as const) {
      for (const c of cs) c.send({ type: 'ready_blind', ante: 1, blind: b });
      for (const c of cs) await c.wait('start_blind');
      for (const c of cs) c.send({ type: 'blind_entered', ante: 1, blind: b });
      const st = await cs[0].wait('party_state', (m) => m.pvpBlind === b && m.started === true);
      expect(view(st).target).toBe(raidTarget(cfg, 2, 1, part));
      for (const c of cs) c.send({ type: 'play_hand', score: 1, hands_left: 0 });
      for (const c of cs) expect(await c.wait('pvp_resolved')).toMatchObject({ kind: 'raid', blind: b, result: 'lose', lifeLost: true });
    }
    for (const c of cs) c.close();
  });
  it('battle royale: score to beat, rank, alive count and who was lowest', async () => {
    const { cs } = await party(4, { party_kind: 'br', starting_lives: 3 });
    await start(cs);
    for (const c of cs) c.send({ type: 'ready_blind', ante: 1, blind: 'L' });
    for (const c of cs) await c.wait('start_blind');
    for (const c of cs) c.send({ type: 'blind_entered', ante: 1, blind: 'L' });
    const sc = [300, 100, 200, 400];
    for (let i = 0; i < 4; i++) cs[i].send({ type: 'play_hand', score: sc[i], hands_left: 1 });
    const st = await cs[0].wait('party_state', (m) => view(m)?.ranked === 4 && (view(m).highest as Msg)?.score === 400 && (view(m).lowest as Msg)?.score === 100);
    expect(view(st)).toMatchObject({ kind: 'br', toBeat: 100, rank: 2, alive: 4, mine: 300 });
    for (let i = 0; i < 4; i++) cs[i].send({ type: 'play_hand', score: sc[i], hands_left: 0 });
    const r = [];
    for (const c of cs) r.push(await c.wait('pvp_resolved'));
    expect(r[1]).toMatchObject({ kind: 'br', result: 'lose', lifeLost: true, myLives: 2, rank: 4, ranked: 4 });
    expect(r[3]).toMatchObject({ result: 'win', lifeLost: false, rank: 1, lowestScore: 100 });
    expect(r[0].lowestName).toBe(r[1].lowestName);
    expect(r[0].losers).toEqual([r[1].lowestName]);
    for (const c of cs) c.close();
  });
  it('teams 2v2: my team total against the best enemy team, same numbers on both sides', async () => {
    const { cs } = await party(4, { party_kind: 'teams', team_size: 2, team_auto: true });
    await start(cs);
    for (const c of cs) c.send({ type: 'ready_blind', ante: 1, blind: 'L' });
    for (const c of cs) await c.wait('start_blind');
    for (const c of cs) c.send({ type: 'blind_entered', ante: 1, blind: 'L' });
    const sc = [100, 50, 30, 40];
    for (let i = 0; i < 4; i++) cs[i].send({ type: 'play_hand', score: sc[i], hands_left: 0 });
    const r = [];
    for (const c of cs) r.push(await c.wait('pvp_resolved'));
    const t0 = r[0].myTeam as number;
    const mates = r.filter(x => x.myTeam === t0).length;
    expect(mates).toBe(2);
    for (const x of r) {
      expect(x.kind).toBe('teams');
      const mine = (x.teamScores as Record<string, number>)[String(x.myTeam)];
      const other = Object.entries(x.teamScores as Record<string, number>).find(([t]) => Number(t) !== x.myTeam)![1];
      expect(x.result).toBe(mine > other ? 'win' : mine < other ? 'lose' : 'draw');
      expect(x.lifeLost).toBe(x.result === 'lose');
    }
    for (const c of cs) c.close();
  });
  it('teams: live view during the blind', async () => {
    const { cs } = await party(4, { party_kind: 'teams', team_size: 2 });
    await start(cs);
    for (const c of cs) c.send({ type: 'ready_blind', ante: 1, blind: 'L' });
    for (const c of cs) await c.wait('start_blind');
    for (const c of cs) c.send({ type: 'blind_entered', ante: 1, blind: 'L' });
    cs[0].send({ type: 'play_hand', score: 70, hands_left: 2 });
    const mine = await cs[0].wait('enemy_info');
    const v = view(mine);
    expect(v.teamTotal).toBe(70);
    expect(v.enemyTotal).toBe(0);
    expect(mine.score).toBe('0');
    const foes = [];
    for (let i = 1; i < 4; i++) { const e = await cs[i].wait('enemy_info'); if (view(e).team !== v.team) foes.push(view(e)); }
    expect(foes.length).toBe(2);
    for (const f of foes) expect(f).toMatchObject({ teamTotal: 0, enemyTotal: 70, enemyTeam: v.team });
    for (const c of cs) c.close();
  });
});

describe('party rules', () => {
  it('raid target only counts players who are connected or scored', () => {
    const cfg = partyCfg({ party_kind: 'raid' });
    const players: RPlayer[] = [
      { pid: 0, alive: true, score: 0, team: 0, lives: 2, present: true },
      { pid: 1, alive: true, score: 0, team: 0, lives: 2, present: true },
      { pid: 2, alive: true, score: 0, team: 0, lives: 2, present: false },
    ];
    expect(resolveParty(cfg, players, {}, 2).raidTarget).toBe(raidTarget(cfg, 2, 2));
  });
  it('br: lowest loses, ties all/spare, all equal is a draw', () => {
    const cfg = partyCfg({ party_kind: 'br' });
    expect(resolveParty(cfg, [P(0, 10), P(1, 20), P(2, 30)], {}, 2).lifeLoss).toEqual([0]);
    expect(resolveParty(cfg, [P(0, 10), P(1, 10), P(2, 30)], {}, 2).lifeLoss.sort()).toEqual([0, 1]);
    const spare = partyCfg({ party_kind: 'br', br_ties: 'spare' });
    expect(resolveParty(spare, [P(0, 10), P(1, 10), P(2, 30)], {}, 2).lifeLoss).toEqual([]);
    const r = resolveParty(cfg, [P(0, 5), P(1, 5)], {}, 2);
    expect(r.lifeLoss).toEqual([]);
    expect(r.outcome[0]).toBe('draw');
  });
  it('br: several losers per blind, never everyone', () => {
    const cfg = partyCfg({ party_kind: 'br', br_losers: 3 });
    expect(resolveParty(cfg, [P(0, 1), P(1, 2), P(2, 3), P(3, 4)], {}, 2).lifeLoss.sort()).toEqual([0, 1, 2]);
    expect(resolveParty(cfg, [P(0, 1), P(1, 2)], {}, 2).lifeLoss).toEqual([0]);
    expect(resolveParty(cfg, [P(0, 1), P(1, 2), P(2, 0, 0, false)], {}, 2).outcome[2]).toBeUndefined();
  });
  it('teams: summed scores and share', () => {
    expect(teamScore([100, 50, 50], 100)).toBe(200);
    expect(teamScore([100, 50, 50], 50)).toBe(150);
    const cfg = partyCfg({ party_kind: 'teams' });
    const r = resolveParty(cfg, [P(0, 100, 0), P(1, 10, 0), P(2, 60, 1), P(3, 60, 1)], { 0: 2, 1: 2 }, 2);
    expect(r.teamLoss).toEqual([0]);
    expect(r.outcome[0]).toBe('lose');
    expect(r.outcome[2]).toBe('win');
    expect(r.teamScores).toEqual({ 0: 110, 1: 120 });
  });
  it('raid curve 2: per-player target eases against the vanilla boss, old lobbies keep the old curve', () => {
    const v2 = partyCfg({ party_kind: 'raid', raid_curve: 2 });
    expect(v2.raidPerPlayer).toBe(100);
    expect(v2.raidScaling).toBe(0);
    expect(raidTarget(v2, 2, 1)).toBe(3600);
    expect(raidTarget(v2, 1, 8)).toBe(100000);
    expect(raidTarget(v2, 3, 4, 'S')).toBe(24750);
    expect(raidTarget(partyCfg({ party_kind: 'raid', raid_curve: 2, raid_per_player: 160, raid_scaling: 10 }), 2, 3)).toBe(Math.round(4000 * 2 * 1.6 * 1.2 * 2.3));
    for (let a = 2; a <= 8; a++) {
      expect(raidTarget(v2, 1, a) / bossChips(a)).toBeLessThanOrEqual(raidTarget(v2, 1, a - 1) / bossChips(a - 1));
      expect(raidTarget(v2, 1, a)).toBeGreaterThanOrEqual(bossChips(a));
    }
    const old = partyCfg({ party_kind: 'raid' });
    expect(old.raidCurve).toBe(1);
    expect(raidTarget(old, 2, 1)).toBe(3000);
    const s: Record<string, unknown> = { raid_curve: 7 };
    cleanPartySettings(s);
    expect(s.raid_curve).toBe(2);
  });
  it('raid: target scales with players, ante and settings', () => {
    const cfg = partyCfg({ party_kind: 'raid' });
    expect(bossChips(1)).toBe(600);
    expect(bossChips(8)).toBe(100000);
    expect(bossChips(9)).toBe(160000);
    expect(raidTarget(cfg, 2, 1)).toBe(3000);
    expect(raidTarget(cfg, 4, 2)).toBe(20000);
    expect(raidTarget(partyCfg({ party_kind: 'raid', raid_per_player: 50 }), 4, 2)).toBe(4000);
    expect(raidTarget(partyCfg({ party_kind: 'raid', raid_scaling: 50 }), 1, 3)).toBe(20000);
    expect(raidTarget(partyCfg({ party_kind: 'raid', raid_per_player: 100, raid_scaling: 0 }), 4, 2)).toBe(6400);
    const r = resolveParty(cfg, [P(0, 1000), P(1, 1000)], {}, 2);
    expect(r.raidTarget).toBe(10000);
    expect(r.raidFail).toBe(true);
    expect(resolveParty(cfg, [P(0, 9000), P(1, 1000)], {}, 2).raidFail).toBe(false);
  });
  it('balance and settings cleaning', () => {
    expect(teamCount(8, 4)).toBe(2);
    expect(teamCount(8, 2)).toBe(4);
    expect(teamCount(5, 2)).toBe(3);
    expect(balanceTeams([0, 1, 2, 3], 2)).toEqual({ 0: 0, 1: 1, 2: 0, 3: 1 });
    const s: Msg = { party_kind: 'zz', br_losers: 9, team_share: 'x', raid_lives: 2.6, br_ties: 'no' };
    cleanPartySettings(s);
    expect(s).toEqual({ br_losers: 3, raid_lives: 3 });
    expect(validateMessage({ type: 'party_team', pid: 9, team: 0 }, 20)).toContain('party_team');
    expect(validateMessage({ type: 'party_join' }, 20)).toContain('missing code');
  });
});

describe('party rooms', () => {
  it('8 players join, 9th is refused, leaving frees the seat, browse lists it', async () => {
    const { cs, code } = await party(8, { party_kind: 'br' });
    const room = await cs[0].wait('party_room', (m) => (m.players as Msg[]).length === 8);
    expect(room.maxPlayers).toBe(8);
    const extra = await connect();
    extra.send({ type: 'party_join', code, name: nm() });
    expect((await extra.wait('party_error')).reason).toBe('room_full');
    cs[7].send({ type: 'party_leave' });
    await cs[0].wait('party_room', (m) => (m.players as Msg[]).length === 7);
    extra.send({ type: 'party_join', code, name: nm() });
    expect((await extra.wait('party_joined')).playerId).toBe(7);
    const viewer = await connect();
    viewer.send({ type: 'list_rooms' });
    const list = await viewer.wait('room_list');
    const e = (list.rooms as Msg[]).find((r) => r.party === true && r.players === 8);
    expect(e?.mode).toBe('party_br');
    cs[0].send({ type: 'party_leave' });
    const passed = await extra.wait('party_room', (m) => m.hostId === 1);
    expect((passed.players as Msg[]).length).toBe(7);
    for (const c of [...cs, extra, viewer]) c.close();
  });

  it('start needs everyone ready; guests get settings', async () => {
    const { cs } = await party(3, { party_kind: 'raid', raid_lives: 2 });
    cs[0].send({ type: 'match_settings', settings: { raid_lives: 2, party_kind: 'nope' } });
    expect((await cs[1].wait('match_settings')).settings).toMatchObject({ party_kind: 'raid', raid_lives: 2, mode: 'attrition' });
    cs[0].send({ type: 'party_start' });
    expect((await cs[0].wait('party_error')).reason).toBe('not_ready');
    await start(cs);
    const st = await cs[2].wait('party_state');
    expect(st.kind).toBe('raid');
    for (const c of cs) c.close();
  });

  it('battle royale: lowest loses, last one standing wins', async () => {
    const { cs } = await party(3, { party_kind: 'br', starting_lives: 1, pvp_start_round: 2 });
    await start(cs);
    cs[1].send({ type: 'blind_entered', ante: 2, blind: 'L' });
    const live = await cs[0].wait('party_state', (m) => m.pvpAnte === 2);
    expect(live.pvpAnte).toBe(2);
    const r = await blind(cs, 2, [300, 100, 200]);
    expect(r[1]).toMatchObject({ result: 'lose', matchEnded: true, winReason: 'eliminated' });
    expect(r[0]).toMatchObject({ result: 'win', matchEnded: false, oppLives: 1 });
    expect((await cs[1].wait('match_ended')).placement).toBe(3);
    const r2 = await blind(cs, 3, [100, null, 500]);
    expect(r2[0]).toMatchObject({ result: 'lose', matchEnded: true });
    expect(r2[2]).toMatchObject({ result: 'win', matchEnded: true, winner: 2, winReason: 'last_standing' });
    const end = await cs[2].wait('match_ended');
    expect(end).toMatchObject({ result: 'win', placement: 1 });
    cs[0].send({ type: 'return_to_lobby' });
    expect((await cs[1].wait('lobby_returned')).party).toBe(true);
    for (const c of cs) c.close();
  });

  it('spectate: boards relay only to the watcher', async () => {
    const { cs } = await party(3, { party_kind: 'br' });
    await start(cs);
    cs[1].send({ type: 'spectate', pid: 0 });
    const first = await cs[1].wait('spec_board', (m) => m.pid === 0);
    expect(first.board).toBe(null);
    cs[0].send({ type: 'spec_board', board: { where: 'blind', ante: 1, hand: [{ k: 'S_A' }] } });
    const got = await cs[1].wait('spec_board', (m) => m.pid === 0 && !!m.board);
    expect(((got.board as Msg).hand as Msg[])[0].k).toBe('S_A');
    cs[2].send({ type: 'spectate', pid: 2 });
    cs[0].send({ type: 'live_stat', ante: 1, blind: 'S', hands: 3, discards: 2, score: 40, where: 'blind' });
    const st = await cs[2].wait('party_state', (m) => ((m.players as Msg[]).find(p => p.pid === 0)?.live as Msg | null)?.hands === 3);
    expect(((st.players as Msg[])[0].live as Msg).score).toBe(40);
    for (const c of cs) c.close();
  });

  it('spectate settings: off blocks living players, jokers can be hidden', async () => {
    const { cs } = await party(3, { party_kind: 'br', spectate: false });
    await start(cs);
    cs[1].send({ type: 'spectate', pid: 0 });
    const d = await cs[1].wait('spec_board', (m) => m.pid === 0);
    expect(d.denied).toBe(true);
    for (const c of cs) c.close();
    const r = await party(2, { party_kind: 'br', spectate_jokers: false });
    await start(r.cs);
    r.cs[1].send({ type: 'spectate', pid: 0 });
    await r.cs[1].wait('spec_board', (m) => m.pid === 0);
    r.cs[0].send({ type: 'spec_board', board: { where: 'blind', jokers: [{ c: 'j_joker' }], hand: [] } });
    const g = await r.cs[1].wait('spec_board', (m) => m.pid === 0 && !!m.board);
    expect((g.board as Msg).jokers_hidden).toBe(true);
    expect(((g.board as Msg).jokers as Msg[]).length).toBe(0);
    for (const c of r.cs) c.close();
  });

  it('live scores: lowest and highest in party_state, enemy_info aggregate', async () => {
    const { cs } = await party(3, { party_kind: 'br' });
    await start(cs);
    for (const c of cs) c.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    await sleep(40);
    for (const c of cs) c.send({ type: 'ready_blind' });
    for (const c of cs) await c.wait('start_blind');
    cs[0].send({ type: 'play_hand', score: 50, hands_left: 2 });
    cs[1].send({ type: 'play_hand', score: 90, hands_left: 2 });
    const info = await cs[2].wait('enemy_info', (m) => m.score === '90');
    expect(info.lives).toBe(2);
    expect((info.view as Msg).rank).toBe(3);
    const own = await cs[1].wait('enemy_info', (m) => (m.view as Msg).mine === 90);
    expect((own.view as Msg).rank).toBe(1);
    expect((own.view as Msg).leader).toBe(true);
    expect((own.view as Msg).value).toBe(50);
    const st = await cs[2].wait('party_state', (m) => !!m.highest && !!m.lowest && (m.highest as Msg).score === 90);
    expect((st.lowest as Msg).pid).toBe(0);
    for (const c of cs) c.close();
  });

  it('teams 2v2: summed team score, shared team lives', async () => {
    const { cs } = await party(4, { party_kind: 'teams', team_size: 2, starting_lives: 1 });
    await start(cs);
    const r = await blind(cs, 2, [100, 100, 10, 10]);
    expect(r[0].result).toBe('draw');
    const r2 = await blind(cs, 3, [100, 10, 10, 10]);
    expect(r2[1]).toMatchObject({ result: 'lose', matchEnded: true, winReason: 'team_eliminated' });
    expect(r2[3]).toMatchObject({ result: 'lose', matchEnded: true });
    expect(r2[0]).toMatchObject({ result: 'win', matchEnded: true, winReason: 'team_won' });
    for (const c of cs) c.close();
  });

  it('raid: shared lives, failing ends it for everyone', async () => {
    const { cs } = await party(2, { party_kind: 'raid', raid_lives: 2 });
    await start(cs);
    const r = await blind(cs, 2, [1000, 1000]);
    expect(r[0]).toMatchObject({ result: 'lose', myLives: 1, oppScore: 10000, raidTarget: 10000, matchEnded: false });
    const r2 = await blind(cs, 3, [30000, 1]);
    expect(r2[1]).toMatchObject({ result: 'win', myLives: 1 });
    const r3 = await blind(cs, 4, [1, 1]);
    expect(r3[0]).toMatchObject({ result: 'lose', matchEnded: true, winReason: 'raid_failed' });
    for (const c of cs) c.close();
  });

  it('raid: clearing the final ante wins', async () => {
    const { cs } = await party(2, { party_kind: 'raid', win_ante: 3 });
    await start(cs);
    await blind(cs, 2, [1e7, 1e7]);
    const r = await blind(cs, 3, [1e7, 1e7]);
    expect(r[0]).toMatchObject({ result: 'win', matchEnded: true, winReason: 'raid_cleared', winner: 0 });
    for (const c of cs) c.close();
  });

  it('a dropped player rejoins with the token; a forfeit keeps the party going', async () => {
    setTimings({ rejoinHoldMs: 60000 });
    const { cs, code } = await party(3, { party_kind: 'br' });
    await start(cs);
    const sess = await cs[1].wait('match_session');
    cs[1].close();
    await cs[0].wait('party_state', (m) => (m.players as Msg[]).some((p) => p.connected === false));
    const back = await connect();
    back.send({ type: 'check_rejoin', code, token: sess.token });
    expect((await back.wait('rejoin_status')).rejoinable).toBe(true);
    back.send({ type: 'rejoin_match', code, token: sess.token });
    expect((await back.wait('rejoin_ok')).playerId).toBe(1);
    cs[2].send({ type: 'leave_match' });
    expect((await cs[2].wait('match_ended')).reason).toBe('forfeited');
    const r = await blind([cs[0], back], 2, [10, 20]);
    expect(r[1]).toMatchObject({ result: 'win', oppLives: 1 });
    cs[0].close(); back.close();
  });

  it('blind timeout closes the blind with the scores so far', async () => {
    partyTiming.blindMs = 150;
    const { cs } = await party(2, { party_kind: 'br' });
    await start(cs);
    for (const c of cs) c.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    await sleep(40);
    for (const c of cs) c.send({ type: 'ready_blind' });
    for (const c of cs) await c.wait('start_blind');
    cs[0].send({ type: 'play_hand', score: 5, hands_left: 1 });
    const r = await cs[1].wait('pvp_resolved', () => true, 2000);
    expect(r.result).toBe('lose');
    partyTiming.blindMs = 0;
    expect(Object.keys(parties).length).toBeGreaterThan(0);
    for (const c of cs) c.close();
  });
});

describe('party edge cases: rules', () => {
  const A = (pid: number, score: number, present = true, team = 0, alive = true): RPlayer => ({ pid, score, team, alive, lives: 3, present });

  it('br: an absent player is never picked as a loser and does not push others down', () => {
    const r = resolveParty(partyCfg({ party_kind: 'br' }), [A(0, 0, false), A(1, 10), A(2, 20)], {}, 2);
    expect(r.lifeLoss).toEqual([1]);
    expect(r.outcome[0]).toBeUndefined();
    const solo = resolveParty(partyCfg({ party_kind: 'br' }), [A(0, 0, false), A(1, 10)], {}, 2);
    expect(solo.lifeLoss).toEqual([]);
  });

  it('br: a tie at the cut that would hit everyone only takes the strictly lower scores', () => {
    const cfg = partyCfg({ party_kind: 'br', br_losers: 2 });
    expect(resolveParty(cfg, [A(0, 1), A(1, 2), A(2, 2)], {}, 2).lifeLoss).toEqual([0]);
    expect(resolveParty(cfg, [A(0, 2), A(1, 2), A(2, 2)], {}, 2).lifeLoss).toEqual([]);
    expect(resolveParty(cfg, [A(0, 0), A(1, 0), A(2, 0), A(3, 0)], {}, 2).lifeLoss).toEqual([]);
    expect(resolveParty(cfg, [A(0, 1), A(1, 2), A(2, 2), A(3, 9)], {}, 2).lifeLoss.sort()).toEqual([0, 1, 2]);
  });

  it('teams: a short-handed team is filled up with its own average', () => {
    const cfg = partyCfg({ party_kind: 'teams' });
    const players = [A(0, 100, true, 0), A(1, 100, true, 0), A(2, 150, true, 1), A(3, 0, true, 1, false)];
    const t = teamTotals(cfg, players, { 0: 3, 1: 3 });
    expect(t).toEqual({ 0: 200, 1: 300 });
    expect(resolveParty(cfg, players, { 0: 3, 1: 3 }, 2).teamLoss).toEqual([0]);
    const absent = [A(0, 100, true, 0), A(1, 100, true, 0), A(2, 150, true, 1), A(3, 0, false, 1)];
    expect(resolveParty(cfg, absent, { 0: 3, 1: 3 }, 2).teamLoss).toEqual([0]);
  });

  it('teams: a team with nobody present sits the blind out; tied lowest teams both lose', () => {
    const cfg = partyCfg({ party_kind: 'teams' });
    const away = [A(0, 0, false, 0), A(1, 0, false, 0), A(2, 5, true, 1), A(3, 5, true, 1)];
    const r = resolveParty(cfg, away, { 0: 3, 1: 3 }, 2);
    expect(r.teamLoss).toEqual([]);
    const three = [A(0, 1, true, 0), A(1, 1, true, 1), A(2, 9, true, 2)];
    expect(resolveParty(cfg, three, { 0: 3, 1: 3, 2: 3 }, 2).teamLoss.sort()).toEqual([0, 1]);
    expect(resolveParty(cfg, [A(0, 4, true, 0), A(1, 4, true, 1)], { 0: 3, 1: 3 }, 2).teamLoss).toEqual([]);
  });

  it('raid: an absent player adds a partial score but no share of the target', () => {
    const cfg = partyCfg({ party_kind: 'raid' });
    const r = resolveParty(cfg, [A(0, 100, false), A(1, 3000), A(2, 3000)], {}, 2);
    expect(r.raidTarget).toBe(raidTarget(cfg, 2, 2));
    expect(r.raidTotal).toBe(6100);
  });
});

describe('party edge cases: rooms', () => {
  it('host dropping in the lobby passes host; the held seat comes back as a guest', async () => {
    setTimings({ rejoinHoldMs: 60000 });
    const { cs, code } = await party(3, { party_kind: 'br' });
    const tok = hostToken;
    cs[0].close();
    const room = await cs[1].wait('party_room', (m) => m.hostId === 1);
    expect((room.players as Msg[]).find((p) => p.pid === 0)?.held).toBe(true);
    const back = await connect();
    back.send({ type: 'party_join', code, token: tok, name: nm() });
    const r = await back.wait('party_joined');
    expect(r).toMatchObject({ host: false, playerId: 0, rejoined: true });
    back.close();
    for (const c of cs.slice(1)) c.close();
  });

  it('joining a running match is refused; rejoin after elimination fails with the reason', async () => {
    setTimings({ rejoinHoldMs: 60000 });
    const { cs, code } = await party(3, { party_kind: 'br', starting_lives: 1 });
    await start(cs);
    const late = await connect();
    late.send({ type: 'party_join', code, name: nm() });
    expect((await late.wait('party_error')).reason).toBe('in_match');
    const sess = await cs[0].wait('match_session');
    await blind(cs, 2, [1, 10, 20]);
    cs[0].close();
    const back = await connect();
    back.send({ type: 'rejoin_match', code, token: sess.token });
    const f = await back.wait('rejoin_failed');
    expect(f).toMatchObject({ reason: 'eliminated', matchOver: true });
    for (const c of [...cs.slice(1), late, back]) c.close();
  });

  it('br: a player who drops before playing sits out once, the second drop counts as 0', async () => {
    setTimings({ rejoinHoldMs: 60000 });
    const { cs, code } = await party(3, { party_kind: 'br' });
    await start(cs);
    const sess = await cs[2].wait('match_session');
    cs[2].close();
    await cs[0].wait('party_state', (m) => (m.players as Msg[]).some((p) => p.connected === false));
    const r1 = await blind([cs[0], cs[1]], 2, [10, 20]);
    expect(r1[0]).toMatchObject({ result: 'lose', myLives: 3 });
    const back = await connect();
    back.send({ type: 'rejoin_match', code, token: sess.token });
    expect((await back.wait('rejoin_ok')).me).toMatchObject({ lives: 4 });
    back.close();
    await cs[0].wait('party_state', (m) => (m.players as Msg[]).some((p) => p.pid === 2 && p.connected === false));
    const r2 = await blind([cs[0], cs[1]], 3, [10, 20]);
    expect(r2[0]).toMatchObject({ result: 'win', myLives: 3 });
    const st = await cs[0].wait('party_state', (m) => (m.players as Msg[]).some((p) => p.pid === 2 && p.lives === 3));
    expect(st).toBeTruthy();
    for (const c of cs.slice(0, 2)) c.close();
  });

  it('AFK limit: the PvP timer runs for party_blind_seconds and every hand restarts it', async () => {
    const seen: number[] = [];
    const real = globalThis.setTimeout;
    const spy = ((fn: (...a: unknown[]) => void, ms?: number, ...a: unknown[]) => { if ((ms ?? 0) >= 30000) seen.push(ms as number); return real(fn, ms, ...a); }) as typeof setTimeout;
    const { cs } = await party(2, { party_kind: 'br', party_blind_seconds: 90 });
    await start(cs);
    globalThis.setTimeout = spy;
    try {
      for (const c of cs) c.send({ type: 'blind_entered', ante: 2, blind: 'L' });
      await sleep(40);
      for (const c of cs) c.send({ type: 'ready_blind' });
      for (const c of cs) await c.wait('start_blind');
      const before = seen.filter((m) => m === 90000).length;
      cs[0].send({ type: 'play_hand', score: 10, hands_left: 2 });
      await sleep(60);
      expect(before).toBeGreaterThanOrEqual(2);
      expect(seen.filter((m) => m === 90000).length).toBe(before + 1);
      expect(seen.every((m) => m === 90000)).toBe(true);
    } finally { globalThis.setTimeout = real; }
    for (const c of cs) c.close();
  });

  it('br sudden death: when a knockout leaves two players, both drop to 1 life', async () => {
    const { cs } = await party(3, { party_kind: 'br', starting_lives: 3, br_sudden_death: true });
    await start(cs);
    const a = await blind(cs, 2, [1, 20, 30]);
    expect(a[1]).toMatchObject({ result: 'win', myLives: 3 });
    await blind(cs, 3, [1, 20, 30]);
    const c = await blind(cs, 4, [1, 20, 30]);
    expect(c[0].matchEnded).toBe(true);
    expect(c[1]).toMatchObject({ myLives: 1, oppLives: 1 });
    expect(c[2]).toMatchObject({ myLives: 1 });
    const d = await blind([cs[1], cs[2]], 5, [5, 50]);
    expect(d[0]).toMatchObject({ result: 'lose', matchEnded: true });
    expect(d[1]).toMatchObject({ result: 'win', matchEnded: true });
    for (const x of cs) x.close();
  });

  it('br sudden death off: the last two keep their lives', async () => {
    const { cs } = await party(3, { party_kind: 'br', starting_lives: 2 });
    await start(cs);
    await blind(cs, 2, [1, 20, 30]);
    const c = await blind(cs, 3, [1, 20, 30]);
    expect(c[1]).toMatchObject({ myLives: 2 });
    for (const x of cs) x.close();
  });

  it('br sudden death also starts when a forfeit leaves two players', async () => {
    const { cs } = await party(3, { party_kind: 'br', starting_lives: 3, br_sudden_death: true });
    await start(cs);
    cs[0].send({ type: 'leave_match' });
    expect((await cs[0].wait('match_ended')).reason).toBe('forfeited');
    expect((await cs[1].wait('match_state_update', (m) => m.myLives === 1)).myLives).toBe(1);
    const d = await blind([cs[1], cs[2]], 2, [5, 50]);
    expect(d[0]).toMatchObject({ result: 'lose', matchEnded: true });
    for (const x of cs) x.close();
  });

  it('br sudden death does not cut lives in a party that starts with two players', async () => {
    const { cs } = await party(2, { party_kind: 'br', starting_lives: 3, br_sudden_death: true });
    await start(cs);
    const a = await blind(cs, 2, [1, 20]);
    expect(a[0]).toMatchObject({ result: 'lose', myLives: 2 });
    expect(a[1]).toMatchObject({ result: 'win', myLives: 3 });
    for (const x of cs) x.close();
  });

  it('br: two players knocked out by the same blind share the placement', async () => {
    const { cs } = await party(3, { party_kind: 'br', starting_lives: 1, br_losers: 2 });
    await start(cs);
    await blind(cs, 2, [1, 2, 30]);
    expect((await cs[0].wait('match_ended')).placement).toBe(2);
    expect((await cs[1].wait('match_ended')).placement).toBe(2);
    expect((await cs[2].wait('match_ended')).placement).toBe(1);
    for (const c of cs) c.close();
  });

  it('raid: failing the final ante with lives left does not count as cleared', async () => {
    const { cs } = await party(2, { party_kind: 'raid', win_ante: 2, raid_lives: 2 });
    await start(cs);
    const r = await blind(cs, 2, [1, 1]);
    expect(r[0]).toMatchObject({ result: 'lose', matchEnded: false, myLives: 1 });
    const r2 = await blind(cs, 3, [1e8, 1e8]);
    expect(r2[0]).toMatchObject({ result: 'win', matchEnded: true, winReason: 'raid_cleared' });
    for (const c of cs) c.close();
  });

  it('a straggler cannot hold the PvP blind forever; ready timeout starts it, blind timeout scores them 0', async () => {
    partyTiming.blindMs = 150;
    const { cs } = await party(3, { party_kind: 'br' });
    await start(cs);
    for (const c of cs.slice(0, 2)) c.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    await sleep(40);
    for (const c of cs.slice(0, 2)) c.send({ type: 'ready_blind' });
    for (const c of cs.slice(0, 2)) await c.wait('start_blind');
    cs[0].send({ type: 'play_hand', score: 10, hands_left: 0 });
    cs[1].send({ type: 'play_hand', score: 20, hands_left: 0 });
    const r = await cs[2].wait('pvp_resolved', () => true, 2000);
    expect(r).toMatchObject({ result: 'lose', myScore: 0 });
    partyTiming.blindMs = 0;
    for (const c of cs) c.close();
  });

  it('raid: a raider left out by the ready timeout does not raise the target the others fought', async () => {
    partyTiming.blindMs = 150;
    const { cs } = await party(2, { party_kind: 'raid' });
    await start(cs);
    cs[0].send({ type: 'blind_entered', ante: 2, blind: 'L' });
    await sleep(40);
    cs[0].send({ type: 'ready_blind' });
    await cs[0].wait('start_blind', () => true, 2000);
    cs[0].send({ type: 'play_hand', score: 1, hands_left: 0 });
    const r = await cs[0].wait('pvp_resolved', () => true, 2000);
    expect(r.raidTarget).toBe(raidTarget(partyCfg({ party_kind: 'raid' }), 1, 2, 'L'));
    expect((await cs[1].wait('pvp_resolved', () => true, 2000)).raidTarget).toBe(r.raidTarget);
    partyTiming.blindMs = 0;
    for (const c of cs) c.close();
  });

  it('raid: a raider still discarding keeps the blind open after the other one is done; the timer still closes an idle one', async () => {
    partyTiming.blindMs = 300;
    const { cs } = await party(2, { party_kind: 'raid' });
    await start(cs);
    for (const c of cs) c.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    await sleep(40);
    for (const c of cs) c.send({ type: 'ready_blind' });
    for (const c of cs) await c.wait('start_blind', () => true, 2000);
    cs[1].send({ type: 'live_stat', where: 'blind', ante: 2, blind: 'L', hands: 4, discards: 4, score: 0 });
    cs[0].send({ type: 'play_hand', score: 100, hands_left: 0 });
    for (let d = 3; d >= 0; d--) {
      await sleep(200);
      cs[1].send({ type: 'live_stat', where: 'blind', ante: 2, blind: 'L', hands: 4, discards: d, score: 0 });
    }
    await sleep(150);
    expect(cs[0].msgs.some((m) => m.type === 'pvp_resolved')).toBe(false);
    expect(await cs[1].wait('pvp_resolved', () => true, 1000)).toMatchObject({ raidTotal: 100 });
    partyTiming.blindMs = 0;
    for (const c of cs) c.close();
  });

  it('a live player left out by the ready timeout does not hold the blind; one who comes in late still plays', async () => {
    partyTiming.blindMs = 600;
    const { cs } = await party(3, { party_kind: 'br' });
    await start(cs);
    for (const c of cs.slice(0, 2)) c.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    await sleep(40);
    for (const c of cs.slice(0, 2)) c.send({ type: 'ready_blind' });
    for (const c of cs.slice(0, 2)) await c.wait('start_blind', () => true, 2000);
    cs[0].send({ type: 'play_hand', score: 10, hands_left: 0 });
    const t0 = Date.now();
    cs[1].send({ type: 'play_hand', score: 20, hands_left: 0 });
    const r = await cs[2].wait('pvp_resolved', () => true, 2000);
    expect(Date.now() - t0).toBeLessThan(300);
    expect(r).toMatchObject({ result: 'lose', myScore: 0 });
    for (const c of cs.slice(0, 2)) c.send({ type: 'blind_entered', ante: 3, blind: 'L' });
    await sleep(40);
    for (const c of cs.slice(0, 2)) c.send({ type: 'ready_blind' });
    for (const c of cs.slice(0, 2)) await c.wait('start_blind', () => true, 2000);
    cs[2].send({ type: 'blind_entered', ante: 3, blind: 'L' });
    await cs[2].wait('start_blind', () => true, 1000);
    cs[0].send({ type: 'play_hand', score: 10, hands_left: 0 });
    cs[1].send({ type: 'play_hand', score: 20, hands_left: 0 });
    await sleep(150);
    expect(cs[0].msgs.some((m) => m.type === 'pvp_resolved' && m.ante === 3)).toBe(false);
    cs[2].send({ type: 'play_hand', score: 30, hands_left: 0 });
    expect(await cs[2].wait('pvp_resolved', () => true, 1000)).toMatchObject({ result: 'win', myScore: 30 });
    partyTiming.blindMs = 0;
    for (const c of cs) c.close();
  });

  it('a player ahead does not wipe the open PvP blind; it reopens at their ante; an old PvP blind is a solo pass', async () => {
    const { cs } = await party(2, { party_kind: 'br' });
    await start(cs);
    for (const c of cs) c.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    await sleep(40);
    for (const c of cs) c.send({ type: 'ready_blind' });
    for (const c of cs) await c.wait('start_blind');
    cs[0].send({ type: 'play_hand', score: 50, hands_left: 0 });
    await sleep(30);
    cs[0].send({ type: 'blind_entered', ante: 3, blind: 'L' });
    cs[0].send({ type: 'ready_blind' });
    await sleep(30);
    cs[1].send({ type: 'play_hand', score: 10, hands_left: 0 });
    expect((await cs[1].wait('pvp_resolved')).result).toBe('lose');
    await cs[1].wait('party_state', (m) => m.pvpAnte === 3);
    cs[1].send({ type: 'blind_entered', ante: 2, blind: 'L' });
    expect((await cs[1].wait('start_blind', (m) => m.solo === true)).party).toBe(true);
    cs[1].send({ type: 'blind_finished', score: 5, ante: 2, blind: 'L' });
    expect(await cs[1].wait('pvp_resolved', (m) => m.solo === true)).toMatchObject({ result: 'draw', myLives: 3 });
    cs[1].send({ type: 'blind_entered', ante: 3, blind: 'L' });
    cs[1].send({ type: 'ready_blind' });
    for (const c of cs) await c.wait('start_blind', (m) => m.solo !== true);
    for (const c of cs) c.close();
  });

  it('a game_over sent twice for the same normal blind costs one life', async () => {
    const { cs } = await party(2, { party_kind: 'br', party_lives: 4 });
    await start(cs);
    cs[0].send({ type: 'blind_entered', ante: 1, blind: 'S' });
    cs[0].send({ type: 'game_over', ante: 1, blind: 'S', score: 10 });
    const first = await cs[0].wait('match_state_update', (x) => x.event === 'life_lost');
    expect(first.myLives).toBe(3);
    cs[0].send({ type: 'game_over', ante: 1, blind: 'S', score: 10 });
    const again = await cs[0].wait('match_state_update', (x) => x.event === 'round_lost');
    expect(again.myLives).toBe(3);
    cs[0].send({ type: 'blind_entered', ante: 1, blind: 'B' });
    cs[0].send({ type: 'game_over', ante: 1, blind: 'B', score: 10 });
    const next = await cs[0].wait('match_state_update', (x) => x.event === 'life_lost');
    expect(next.myLives).toBe(2);
    for (const c of cs) c.close();
  });

  it('failing a normal blind with the life rule off sends round_lost and keeps lives', async () => {
    const { cs } = await party(2, { party_kind: 'br', death_on_round_loss: false });
    await start(cs);
    cs[0].send({ type: 'blind_entered', ante: 1, blind: 'S' });
    cs[0].send({ type: 'game_over' });
    const m = await cs[0].wait('match_state_update', (x) => x.event === 'round_lost');
    expect(m.myLives).toBe(4);
    for (const c of cs) c.close();
  });

  it('teams: out of range manual teams after a settings change are rebalanced at start', async () => {
    const { cs } = await party(4, { party_kind: 'teams', team_auto: false, team_size: 2 });
    cs[0].send({ type: 'party_team', pid: 1, team: 1 });
    cs[0].send({ type: 'party_team', pid: 3, team: 1 });
    await sleep(30);
    cs[0].send({ type: 'match_settings', settings: { party_kind: 'teams', team_auto: false, team_size: 4 } });
    await sleep(30);
    cs[0].send({ type: 'match_settings', settings: { party_kind: 'teams', team_auto: false, team_size: 2 } });
    await start(cs);
    const st = await cs[0].wait('party_state');
    const teams = new Set((st.players as Msg[]).map((p) => p.team));
    expect(teams.size).toBe(2);
    for (const c of cs) c.close();
  });
  it('teams: players pick their own team when auto is off, uneven teams block start', async () => {
    const { cs } = await party(4, { party_kind: 'teams', team_auto: false, team_size: 2 });
    cs[2].send({ type: 'party_team', pid: 2, team: 1 });
    await cs[0].wait('party_room', (m) => (m.players as Msg[]).find((p) => p.pid === 2)?.team === 1);
    cs[2].send({ type: 'party_team', pid: 1, team: 0 });
    for (const c of cs.slice(1)) c.send({ type: 'party_ready', ready: true });
    await sleep(60);
    cs[0].send({ type: 'party_start' });
    expect((await cs[0].wait('party_error')).reason).toBe('team_too_big');
    cs[0].send({ type: 'party_team', pid: 1, team: 0 });
    await sleep(30);
    cs[0].send({ type: 'party_start' });
    for (const c of cs) await c.wait('match_start');
    for (const c of cs) c.close();
  });
  it('teams: with auto-balance on a guest cannot move', async () => {
    const { cs } = await party(2, { party_kind: 'teams', team_size: 2 });
    cs[1].send({ type: 'party_team', pid: 1, team: 0 });
    await sleep(60);
    expect(cs[1].msgs.some((m) => m.type === 'party_room' && (m.players as Msg[]).find((p) => p.pid === 1)?.team === 0)).toBe(false);
    for (const c of cs) c.close();
  });
  it('join_room with a party code lands in the party, a bad code is refused', async () => {
    const { cs, code } = await party(1, { party_kind: 'br' });
    const c = await connect();
    c.send({ type: 'join_room', code: code.toLowerCase(), name: nm() });
    expect((await c.wait('party_joined')).code).toBe(code);
    const d = await connect();
    d.send({ type: 'join_room', code: 'ZZZZ', name: nm() });
    expect((await d.wait('room_error')).reason).toBe('invalid_code');
    for (const x of [...cs, c, d]) x.close();
  });
  it('everyone disconnected mid-blind: nothing resolves until someone is back', async () => {
    setTimings({ rejoinHoldMs: 60000 });
    const { cs, code } = await party(2, { party_kind: 'br' });
    await start(cs);
    for (const c of cs) c.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    await sleep(40);
    for (const c of cs) c.send({ type: 'ready_blind' });
    for (const c of cs) await c.wait('start_blind');
    for (const c of cs) c.close();
    await sleep(80);
    expect(parties[code].lastResult).toBeNull();
    expect(parties[code].seats.every((s) => !s || s.lives === 4)).toBe(true);
  });
});

describe('G3 party kick', () => {
  it('the host kicks a player from the lobby and the others see the new state', async () => {
    const { cs } = await party(3, { party_kind: 'br' });
    cs[0].send({ type: 'party_kick', pid: 2 });
    expect((await cs[2].wait('party_kicked')).reason).toBe('host');
    const room = await cs[1].wait('party_room', (m) => (m.players as Msg[]).length === 2);
    expect((room.players as Msg[]).length).toBe(2);
    cs.forEach((c) => c.close());
  });

  it('only the host can kick, and never themselves', async () => {
    const { cs } = await party(3, { party_kind: 'br' });
    cs[1].send({ type: 'party_kick', pid: 2 });
    expect((await cs[1].wait('party_error')).reason).toBe('host_only');
    cs[0].send({ type: 'party_kick', pid: 0 });
    expect((await cs[0].wait('party_error')).reason).toBe('bad_kick');
    expect(cs[2].msgs.some((m) => m.type === 'party_kicked')).toBe(false);
    cs.forEach((c) => c.close());
  });

  it('a kick during a run counts the player as out', async () => {
    const { cs } = await party(3, { party_kind: 'br', starting_lives: 4 });
    await start(cs);
    cs[0].send({ type: 'party_kick', pid: 1 });
    expect((await cs[1].wait('party_kicked')).reason).toBe('host');
    await cs[0].wait('party_state', (m) => JSON.stringify(m).includes('"alive":false'));
    cs.forEach((c) => c.close());
  });

  it('validates the pid', () => {
    expect(validateMessage({ type: 'party_kick', pid: 1 }, 40)).toBeNull();
    expect(validateMessage({ type: 'party_kick', pid: 'x' }, 40)).toContain('party_kick');
    expect(validateMessage({ type: 'party_kick' }, 40)).toContain('party_kick');
  });
});
