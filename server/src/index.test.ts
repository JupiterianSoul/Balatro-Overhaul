
import { describe, it, expect, afterAll } from 'bun:test';
import {
  createMatchState,
  isBlindPvp,
  createRoom,
  generateCode,
  validateMessage,
  isRateLimited,
  isActRateLimited,
  rooms,
  startServer,
  setTimings,
  sweepRooms,
  SNAPSHOT_MAX_BYTES,
  lifeOnRoundLoss,
  finalAnteFor,
  cleanName,
  isDefaultName,
  sanitizeSettings,
  cleanRules,
} from './index';

const srv = startServer(0);
afterAll(() => srv.stop(true));

describe('createMatchState', () => {
  it('returns default state with no settings', () => {
    const m = createMatchState();
    expect(m.phase).toBe('lobby');
    expect(m.mode).toBe('nemesis');
    expect(m.startingLives).toBe(4);
    expect(m.players[0].lives).toBe(4);
    expect(m.players[1].lives).toBe(4);
    expect(m.currentAnte).toBe(1);
    expect(m.currentBlind).toBe('S');
    expect(m.winner).toBeNull();
    expect(m.anteTimer).toBe(false);
  });

  it('respects custom settings', () => {
    const m = createMatchState({ starting_lives: 2, mode: 'vanilla', ante_timer: true, ante_timer_base: 60 });
    expect(m.startingLives).toBe(2);
    expect(m.mode).toBe('vanilla');
    expect(m.players[0].lives).toBe(2);
    expect(m.anteTimer).toBe(true);
    expect(m.anteTimerBase).toBe(60);
  });

  it('defaults ante_timer_base to 120', () => {
    const m = createMatchState({});
    expect(m.anteTimerBase).toBe(120);
  });
});

describe('isBlindPvp', () => {
  it('returns false in vanilla mode always', () => {
    const m = createMatchState({ mode: 'vanilla' });
    expect(isBlindPvp(m, 5,  'L')).toBe(false);
    expect(isBlindPvp(m, 10, 'L')).toBe(false);
  });

  it('returns true for attrition L blind after pvpStartAnte', () => {
    const m = createMatchState({ mode: 'attrition' });
    m.pvpStartAnte = 1;
    expect(isBlindPvp(m, 2, 'L')).toBe(true);
    expect(isBlindPvp(m, 1, 'L')).toBe(false);
  });

  it('returns false for non-L blinds in attrition', () => {
    const m = createMatchState({ mode: 'attrition' });
    expect(isBlindPvp(m, 5, 'S')).toBe(false);
    expect(isBlindPvp(m, 5, 'B')).toBe(false);
  });

  it('handles showdown mode', () => {
    const m = createMatchState({ mode: 'showdown' });
    expect(isBlindPvp(m, 2, 'S')).toBe(true);
    expect(isBlindPvp(m, 1, 'L')).toBe(false);
  });
});

describe('createRoom', () => {
  it('creates room with expected structure', () => {
    const r = createRoom('ABCD');
    expect(r.code).toBe('ABCD');
    expect(Array.isArray(r.sockets)).toBe(true);
    expect(r.sockets.length).toBe(0);
    expect(r.match).toBeNull();
    expect(r.settings).toEqual({ mode: 'attrition', starting_lives: 4 });
    expect(Array.isArray(r.gameHistory)).toBe(true);
  });
});

describe('generateCode', () => {
  it('returns a 4-character string', () => {
    const code = generateCode();
    expect(typeof code).toBe('string');
    expect(code.length).toBe(4);
  });

  it('uses only allowed characters', () => {
    const allowed = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]+$/;
    for (let i = 0; i < 50; i++) {
      expect(generateCode()).toMatch(allowed);
    }
  });

  it('generates different codes (probabilistic)', () => {
    const codes = new Set(Array.from({ length: 20 }, () => generateCode()));
    expect(codes.size).toBeGreaterThan(1);
  });
});

describe('validateMessage', () => {
  it('accepts a valid create_room message', () => {
    expect(validateMessage({ type: 'create_room' }, 20)).toBeNull();
  });

  it('rejects oversized messages', () => {
    const err = validateMessage({ type: 'ping' }, 5000);
    expect(err).toBeTruthy();
    expect(err).toContain('oversized');
  });

  it('allows long settings lists in match_settings and match_start, up to 64 KB', () => {
    expect(validateMessage({ type: 'match_settings', settings: {} }, 20000)).toBeNull();
    expect(validateMessage({ type: 'match_start', settings: {} }, 20000)).toBeNull();
    expect(validateMessage({ type: 'match_settings', settings: {} }, 70000)).toContain('oversized');
    expect(validateMessage({ type: 'player_name', name: 'a' }, 20000)).toContain('oversized');
  });

  it('rejects unknown type', () => {
    const err = validateMessage({ type: 'hack_room' }, 20);
    expect(err).toBeTruthy();
    expect(err).toContain('unknown type');
  });

  it('rejects missing type', () => {
    const err = validateMessage({ action: 'create_room' } as Record<string, unknown>, 30);
    expect(err).toBeTruthy();
    expect(err).toContain('missing type');
  });

  it('rejects invalid join_room code', () => {
    const err = validateMessage({ type: 'join_room', code: '!@#$' }, 30);
    expect(err).toBeTruthy();
    expect(err).toContain('join_room');
  });

  it('accepts valid join_room', () => {
    expect(validateMessage({ type: 'join_room', code: 'AB3Z' }, 30)).toBeNull();
  });

  it('rejects blind_finished with negative score', () => {
    const err = validateMessage({ type: 'blind_finished', score: -1 }, 40);
    expect(err).toBeTruthy();
    expect(err).toContain('blind_finished');
  });

  it('rejects blind_finished with absurdly large score', () => {
    const err = validateMessage({ type: 'blind_finished', score: 2e15 }, 40);
    expect(err).toBeTruthy();
    expect(err).toContain('score too large');
  });

  it('accepts valid blind_finished', () => {
    expect(validateMessage({ type: 'blind_finished', score: 1_000_000 }, 50)).toBeNull();
  });

  it('rejects match_settings with invalid mode', () => {
    const err = validateMessage({ type: 'match_settings', settings: { mode: 'godmode' } }, 60);
    expect(err).toBeTruthy();
    expect(err).toContain('mode');
  });

  it('accepts valid sabotage', () => {
    expect(validateMessage({ type: 'sabotage', sabotage_id: 'sleep' }, 40)).toBeNull();
  });

  it('rejects sabotage with oversized sabotage_id', () => {
    const err = validateMessage({ type: 'sabotage', sabotage_id: 'x'.repeat(65) }, 80);
    expect(err).toBeTruthy();
    expect(err).toContain('sabotage');
  });

  it('accepts valid taunt', () => {
    expect(validateMessage({ type: 'taunt', title: 'GG' }, 30)).toBeNull();
  });

  it('rejects taunt with oversized title', () => {
    const err = validateMessage({ type: 'taunt', title: 'x'.repeat(65) }, 80);
    expect(err).toBeTruthy();
    expect(err).toContain('taunt');
  });
});

describe('isRateLimited', () => {
  it('allows messages under the per-second limit', () => {
    const rl = { msgCount: 0, msgWindowStart: Date.now(), createCount: 0, createWindowStart: Date.now() };
    for (let i = 0; i < 10; i++) expect(isRateLimited(rl, false)).toBe(false);
  });

  it('blocks messages exceeding 30/s', () => {
    const rl = { msgCount: 30, msgWindowStart: Date.now() - 100, createCount: 0, createWindowStart: Date.now() };
    expect(isRateLimited(rl, false)).toBe(true);
  });

  it('resets msg counter after 1 second window', () => {
    const rl = { msgCount: 30, msgWindowStart: Date.now() - 1500, createCount: 0, createWindowStart: Date.now() };
    expect(isRateLimited(rl, false)).toBe(false);
  });

  it('blocks create_room exceeding 5/min', () => {
    const rl = { msgCount: 0, msgWindowStart: Date.now(), createCount: 5, createWindowStart: Date.now() - 100 };
    expect(isRateLimited(rl, true)).toBe(true);
  });
});

describe('isActRateLimited', () => {
  it('gives replay batches their own budget, apart from the 30/s one', () => {
    const rl = { msgCount: 30, msgWindowStart: Date.now() - 100, createCount: 0, createWindowStart: Date.now() };
    for (let i = 0; i < 60; i++) expect(isActRateLimited(rl)).toBe(false);
    expect(isActRateLimited(rl)).toBe(true);
    expect(rl.msgCount).toBe(30);
  });

  it('resets the act counter after 1 second window', () => {
    const rl = { msgCount: 0, msgWindowStart: Date.now(), createCount: 0, createWindowStart: Date.now(), actCount: 60, actWindowStart: Date.now() - 1500 };
    expect(isActRateLimited(rl)).toBe(false);
  });
});

type Msg = Record<string, unknown>;

interface TestClient {
  msgs: Msg[];
  send: (m: Msg) => void;
  waitFor: (pred: (m: Msg) => boolean, timeoutMs?: number) => Promise<Msg>;
  close: () => void;
}

function decode(raw: string): Msg {
  const parsed = JSON.parse(raw) as Msg;
  if (parsed.z === 1 && typeof parsed.d === 'string') {
    const inflated = Bun.inflateSync(Buffer.from(parsed.d, 'base64'));
    return JSON.parse(Buffer.from(inflated).toString('utf8')) as Msg;
  }
  return parsed;
}

async function connect(): Promise<TestClient> {
  const ws = new WebSocket(`ws://127.0.0.1:${srv.port}/ws`);
  const msgs: Msg[] = [];
  const waiters: { pred: (m: Msg) => boolean; resolve: (m: Msg) => void }[] = [];
  ws.onmessage = (ev) => {
    const m = decode(String(ev.data));
    msgs.push(m);
    for (let i = waiters.length - 1; i >= 0; i--) {
      if (waiters[i].pred(m)) { waiters[i].resolve(m); waiters.splice(i, 1); }
    }
  };
  await new Promise<void>((resolve, reject) => {
    ws.onopen = () => resolve();
    ws.onerror = () => reject(new Error('ws error'));
  });
  return {
    msgs,
    send: (m) => ws.send(JSON.stringify(m)),
    waitFor: (pred, timeoutMs = 2000) => {
      const hit = msgs.find(pred);
      if (hit) return Promise.resolve(hit);
      return new Promise<Msg>((resolve, reject) => {
        const t = setTimeout(() => reject(new Error('timed out waiting for message')), timeoutMs);
        waiters.push({ pred, resolve: (m) => { clearTimeout(t); resolve(m); } });
      });
    },
    close: () => ws.close(),
  };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function startMatch(settings: Msg): Promise<[TestClient, TestClient]> {
  const host = await connect();
  const guest = await connect();
  host.send({ type: 'create_room' });
  const created = await host.waitFor((m) => m.type === 'room_created');
  guest.send({ type: 'join_room', code: created.code });
  await guest.waitFor((m) => m.type === 'room_ready');
  await host.waitFor((m) => m.type === 'room_ready');
  host.send({ type: 'match_start', seed: 'TEST', settings, player_name: 'Host' });
  await host.waitFor((m) => m.type === 'match_state_update' && m.event === 'match_started');
  await guest.waitFor((m) => m.type === 'match_state_update' && m.event === 'match_started');
  return [host, guest];
}

async function enterPvpBlind(host: TestClient, guest: TestClient): Promise<void> {
  host.send({ type: 'ready_blind' });
  guest.send({ type: 'ready_blind' });
  await host.waitFor((m) => m.type === 'start_blind');
  await guest.waitFor((m) => m.type === 'start_blind');
}

describe('live match flow', () => {
  it('a blind_entered from one side does not reset a PvP blind that already started', async () => {
    const [host, guest] = await startMatch({ mode: 'faceoff', starting_lives: 2 });
    await enterPvpBlind(host, guest);
    host.send({ type: 'blind_entered', ante: 1, blind: 'S' });
    host.send({ type: 'blind_finished', ante: 1, blind: 'S', score: 500 });
    await guest.waitFor((m) => m.type === 'opponent_blind_finished');
    guest.send({ type: 'blind_entered', ante: 1, blind: 'B' });
    guest.send({ type: 'blind_finished', ante: 1, blind: 'B', score: 100 });
    const res = await guest.waitFor((m) => m.type === 'pvp_resolved');
    expect(res.result).toBe('lose');
    host.close(); guest.close();
  });

  it('gameplay messages are never dropped by the rate limit', async () => {
    const [host, guest] = await startMatch({ mode: 'faceoff', starting_lives: 2 });
    await enterPvpBlind(host, guest);
    host.send({ type: 'blind_entered', ante: 1, blind: 'S' });
    guest.send({ type: 'blind_entered', ante: 1, blind: 'S' });
    for (let i = 0; i < 40; i++) host.send({ type: 'taunt', title: 'x', timestamp: 1 });
    host.send({ type: 'play_hand', score: '500', hands_left: 0 });
    guest.send({ type: 'play_hand', score: '100', hands_left: 0 });
    const res = await host.waitFor((m) => m.type === 'pvp_resolved');
    expect(res.result).toBe('win');
    host.close(); guest.close();
  });

  it('match_start settings decide starting lives even without match_settings', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 2 });
    const st = await guest.waitFor((m) => m.type === 'match_state_update' && m.event === 'match_started');
    expect(st.myLives).toBe(2);
    expect(st.oppLives).toBe(2);
    host.close(); guest.close();
  });

  it('losing the last life on a non-PvP blind ends the match on the server', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 1 });
    guest.send({ type: 'game_over', ante: 1, blind: 'S', score: 10 });
    const st = await host.waitFor((m) => m.type === 'match_state_update' && m.event === 'life_lost');
    expect(st.phase).toBe('finished');
    expect(st.winner).toBe(0);
    expect(st.oppLives).toBe(0);
    host.close(); guest.close();
  });

  it('second player entering the PvP blind does not wipe the first player result', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, pvp_start_round: 2 });
    await enterPvpBlind(host, guest);
    host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    host.send({ type: 'play_hand', score: '500', hands_left: 0 });
    await sleep(50);
    guest.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    guest.send({ type: 'play_hand', score: '100', hands_left: 0 });
    const res = await host.waitFor((m) => m.type === 'pvp_resolved');
    expect(res.result).toBe('win');
    expect(res.oppLives).toBe(2);
    host.close(); guest.close();
  });

  it('an infinite PvP score beats a finite one', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, pvp_start_round: 2 });
    await enterPvpBlind(host, guest);
    host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    guest.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    host.send({ type: 'play_hand', score: 'inf', hands_left: 0 });
    guest.send({ type: 'play_hand', score: '1e30', hands_left: 0 });
    const res = await guest.waitFor((m) => m.type === 'pvp_resolved');
    expect(res.result).toBe('lose');
    host.close(); guest.close();
  });

  it('a late blind_finished after PvP resolution is ignored', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, pvp_start_round: 2 });
    await enterPvpBlind(host, guest);
    host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    guest.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    host.send({ type: 'play_hand', score: '50', hands_left: 0 });
    guest.send({ type: 'play_hand', score: '60', hands_left: 0 });
    await host.waitFor((m) => m.type === 'pvp_resolved');
    host.send({ type: 'blind_finished', ante: 2, blind: 'L', score: 50 });
    await sleep(100);
    expect(guest.msgs.some((m) => m.type === 'opponent_blind_finished')).toBe(false);
    host.close(); guest.close();
  });

  it('relays version_mismatch and silently drops legacy client messages', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    host.send({ type: 'round_end', ante: 1, lives: 4 });
    host.send({ type: 'life_lost', lives: 3 });
    host.send({ type: 'get_end_game_jokers' });
    host.send({ type: 'version_mismatch', version: 'X', mp_version: 1 });
    const vm = await guest.waitFor((m) => m.type === 'version_mismatch');
    expect(vm.version).toBe('X');
    await sleep(50);
    expect(host.msgs.some((m) => m.type === 'error')).toBe(false);
    host.close(); guest.close();
  });

  it('any message from a player in a room keeps the room alive', async () => {
    const host = await connect();
    host.send({ type: 'create_room' });
    const created = await host.waitFor((m) => m.type === 'room_created');
    const code = created.code as string;
    rooms[code].lastActivity = 0;
    host.send({ type: 'ping' });
    await host.waitFor((m) => m.type === 'pong');
    expect(rooms[code].lastActivity).toBeGreaterThan(0);
    host.close();
  });
});

type Session = { code: string; token: string; playerId: number };

async function sessionOf(c: TestClient): Promise<Session> {
  const s = await c.waitFor((m) => m.type === 'match_session');
  return { code: s.code as string, token: s.token as string, playerId: s.playerId as number };
}

async function finishedMatch(): Promise<[TestClient, TestClient]> {
  const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 1 });
  guest.send({ type: 'game_over', ante: 1, blind: 'S', score: 10 });
  await host.waitFor((m) => m.type === 'match_ended');
  await guest.waitFor((m) => m.type === 'match_ended');
  return [host, guest];
}

function fakeSave(bytes: number): string {
  return Buffer.alloc(bytes, 7).toString('base64');
}

describe('non-PvP life loss', () => {
  it('a game_over sent again for the same blind costs one life, not two', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 4 });
    const code = (await host.waitFor((m) => m.type === 'room_created')).code as string;
    guest.send({ type: 'game_over', ante: 1, blind: 'B', score: 10 });
    guest.send({ type: 'game_over', ante: 1, blind: 'B', score: 10 });
    guest.send({ type: 'game_over', ante: 1, blind: 'B', score: 10 });
    await Bun.sleep(150);
    expect(rooms[code].match!.players[1].lives).toBe(3);
    guest.send({ type: 'game_over', ante: 2, blind: 'S', score: 10 });
    await Bun.sleep(100);
    expect(rooms[code].match!.players[1].lives).toBe(2);
    host.close(); guest.close();
  });
});

describe('session tokens', () => {
  it('room and match messages carry a per-seat token', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    const created = await host.waitFor((m) => m.type === 'room_created');
    const ready = await guest.waitFor((m) => m.type === 'room_ready');
    const hs = await sessionOf(host);
    const gs = await sessionOf(guest);
    expect(created.token).toBe(hs.token);
    expect(ready.token).toBe(gs.token);
    expect(hs.token).not.toBe(gs.token);
    expect(hs.token).toMatch(/^[a-f0-9]{32}$/);
    expect(hs.playerId).toBe(0);
    expect(gs.playerId).toBe(1);
    host.close(); guest.close();
  });
});

describe('drop and rejoin', () => {
  it('Ascension records an away player at the ante they reached', async () => {
    setTimings({ rejoinHoldMs: 15 * 60 * 1000 });
    const [host, guest] = await startMatch({ mode: 'ascension', starting_lives: 1 });
    guest.send({ type: 'blind_entered', ante: 1, blind: 'S' });
    host.send({ type: 'blind_entered', ante: 1, blind: 'S' });
    guest.send({ type: 'save_snapshot', data: fakeSave(100), seq: 1, ante: 2, blind: 'Big' });
    await guest.waitFor((m) => m.type === 'snapshot_ack');
    guest.close();
    await host.waitFor((m) => m.type === 'opponent_disconnected');
    host.send({ type: 'blind_entered', ante: 1, blind: 'L' });
    host.send({ type: 'game_over', ante: 1, blind: 'L', score: 300 });
    const res = await host.waitFor((m) => m.type === 'ascension_resolved');
    expect(res.oppAnte).toBe(2);
    expect(res.oppBlind).toBe('B');
    expect(res.result).toBe('lose');
    host.close();
  });

  it('Ascension uses the away player own blind_entered, not the opponent ante', async () => {
    setTimings({ rejoinHoldMs: 15 * 60 * 1000 });
    const [host, guest] = await startMatch({ mode: 'ascension', starting_lives: 1 });
    guest.send({ type: 'blind_entered', ante: 2, blind: 'S' });
    await sleep(30);
    guest.close();
    await host.waitFor((m) => m.type === 'opponent_disconnected');
    host.send({ type: 'blind_entered', ante: 3, blind: 'B' });
    host.send({ type: 'game_over', ante: 3, blind: 'B', score: 10 });
    const res = await host.waitFor((m) => m.type === 'ascension_resolved');
    expect(res.oppAnte).toBe(2);
    expect(res.oppBlind).toBe('S');
    expect(res.result).toBe('win');
    host.close();
  });

  it('Ascension costs a life per failed blind and only ends at zero lives', async () => {
    const [host, guest] = await startMatch({ mode: 'ascension', starting_lives: 3 });
    guest.send({ type: 'blind_entered', ante: 3, blind: 'S' });
    host.send({ type: 'blind_entered', ante: 1, blind: 'B' });
    host.send({ type: 'game_over', ante: 1, blind: 'B', score: 50 });
    const st = await host.waitFor((m) => m.type === 'match_state_update' && m.event === 'life_lost');
    expect(st.myLives).toBe(2);
    host.send({ type: 'game_over', ante: 1, blind: 'B', score: 50 });
    await sleep(40);
    expect(host.msgs.some((m) => m.type === 'ascension_resolved')).toBe(false);
    host.close(); guest.close();
  });

  it('Ascension lets a player behind an eliminated opponent keep playing until they pass them', async () => {
    const [host, guest] = await startMatch({ mode: 'ascension', starting_lives: 1 });
    guest.send({ type: 'blind_entered', ante: 3, blind: 'B' });
    host.send({ type: 'blind_entered', ante: 1, blind: 'B' });
    await sleep(20);
    guest.send({ type: 'game_over', ante: 3, blind: 'B', score: 900 });
    await sleep(40);
    expect(host.msgs.some((m) => m.type === 'ascension_resolved')).toBe(false);
    host.send({ type: 'blind_entered', ante: 3, blind: 'B' });
    await sleep(40);
    expect(host.msgs.some((m) => m.type === 'ascension_resolved')).toBe(false);
    host.send({ type: 'blind_entered', ante: 3, blind: 'L' });
    const res = await host.waitFor((m) => m.type === 'ascension_resolved');
    expect(res.result).toBe('win');
    const gres = await guest.waitFor((m) => m.type === 'ascension_resolved');
    expect(gres.result).toBe('lose');
    host.close(); guest.close();
  });

  it('Ascension ends at once when the survivor is already ahead', async () => {
    const [host, guest] = await startMatch({ mode: 'ascension', starting_lives: 1 });
    guest.send({ type: 'blind_entered', ante: 4, blind: 'S' });
    host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    await sleep(20);
    host.send({ type: 'game_over', ante: 2, blind: 'L', score: 10 });
    const res = await host.waitFor((m) => m.type === 'ascension_resolved');
    expect(res.result).toBe('lose');
    host.close(); guest.close();
  });

  it('a socket drop holds the match and a rejoin restores the full state', async () => {
    setTimings({ rejoinHoldMs: 15 * 60 * 1000 });
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3 });
    const gs = await sessionOf(guest);
    guest.send({ type: 'blind_entered', ante: 1, blind: 'B' });
    guest.send({ type: 'set_location', location: 'shop' });
    guest.send({ type: 'save_snapshot', data: fakeSave(1000), seq: 1, ante: 1, blind: 'B' });
    const ack = await guest.waitFor((m) => m.type === 'snapshot_ack');
    expect(ack.bytes).toBe(1000);
    guest.close();
    const dc = await host.waitFor((m) => m.type === 'opponent_disconnected');
    expect(dc.held).toBe(true);
    expect(dc.reason).toBe('connection_lost');
    expect(dc.secondsLeft).toBe(900);
    expect(rooms[gs.code].match?.phase).toBe('playing');

    const back = await connect();
    back.send({ type: 'check_rejoin', code: gs.code, token: gs.token });
    const st = await back.waitFor((m) => m.type === 'rejoin_status');
    expect(st.rejoinable).toBe(true);
    expect(st.opponentWaiting).toBe(true);
    expect(st.opponentName).toBe('Host');

    back.send({ type: 'rejoin_match', code: gs.code, token: gs.token });
    const ok = await back.waitFor((m) => m.type === 'rejoin_ok');
    expect(ok.playerId).toBe(1);
    expect(ok.host).toBe(false);
    expect(ok.phase).toBe('playing');
    expect(ok.currentAnte).toBe(1);
    expect(ok.currentBlind).toBe('B');
    expect((ok.settings as Msg).starting_lives).toBe(3);
    expect((ok.me as Msg).lives).toBe(3);
    expect((ok.me as Msg).location).toBe('shop');
    expect((ok.opp as Msg).name).toBe('Host');
    expect((ok.opp as Msg).connected).toBe(true);
    expect((ok.snapshot as Msg).data).toBe(fakeSave(1000));
    expect((ok.snapshot as Msg).seq).toBe(1);
    const rc = await host.waitFor((m) => m.type === 'opponent_reconnected');
    expect(rc.playerId).toBe(1);

    host.send({ type: 'taunt', title: 'hi' });
    const t = await back.waitFor((m) => m.type === 'taunt');
    expect(t.title).toBe('hi');
    host.close(); back.close();
  });

  it('going to the main menu mid-match is a drop, not a kick', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    const hs = await sessionOf(host);
    host.send({ type: 'return_to_menu' });
    const dc = await guest.waitFor((m) => m.type === 'opponent_disconnected');
    expect(dc.held).toBe(true);
    expect(dc.reason).toBe('left_to_menu');
    expect(guest.msgs.some((m) => m.type === 'room_closed')).toBe(false);
    host.send({ type: 'rejoin_match', code: hs.code, token: hs.token });
    const ok = await host.waitFor((m) => m.type === 'rejoin_ok');
    expect(ok.playerId).toBe(0);
    expect(ok.host).toBe(true);
    await guest.waitFor((m) => m.type === 'opponent_reconnected');
    host.close(); guest.close();
  });

  it('the room list marks a running match with a held seat, and the session carries the room id', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    const raw = await guest.waitFor((m) => m.type === 'match_session');
    const v = await connect();
    const before = (await listFor(v)).find((r) => r.id === raw.id)!;
    expect(before).toMatchObject({ inMatch: true, seatHeld: false });
    guest.send({ type: 'return_to_menu' });
    await host.waitFor((m) => m.type === 'opponent_disconnected');
    expect((await listFor(v)).find((r) => r.id === raw.id)).toMatchObject({ inMatch: true, seatHeld: true });
    guest.send({ type: 'rejoin_match', code: raw.code, token: raw.token });
    const ok = await guest.waitFor((m) => m.type === 'rejoin_ok');
    expect(ok.id).toBe(raw.id);
    await host.waitFor((m) => m.type === 'opponent_reconnected');
    expect((await listFor(v)).find((r) => r.id === raw.id)?.seatHeld).toBe(false);
    host.close(); guest.close(); v.close();
  });

  it('a wrong token or unknown room cannot rejoin', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    const gs = await sessionOf(guest);
    guest.close();
    await host.waitFor((m) => m.type === 'opponent_disconnected');
    const intruder = await connect();
    intruder.send({ type: 'rejoin_match', code: gs.code, token: 'f'.repeat(32) });
    const bad = await intruder.waitFor((m) => m.type === 'rejoin_failed');
    expect(bad.reason).toBe('bad_token');
    intruder.send({ type: 'check_rejoin', code: 'ZZZZ', token: gs.token });
    const nf = await intruder.waitFor((m) => m.type === 'rejoin_status');
    expect(nf.rejoinable).toBe(false);
    expect(nf.reason).toBe('not_found');
    intruder.send({ type: 'rejoin_match', code: gs.code, token: 'nope' });
    const err = await intruder.waitFor((m) => m.type === 'error');
    expect(err.reason).toContain('invalid token');
    expect(rooms[gs.code].sockets[1]).toBeNull();
    host.close(); intruder.close();
  });

  it('a player cannot take the other seat with its token', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    const gs = await sessionOf(guest);
    host.send({ type: 'rejoin_match', code: gs.code, token: gs.token });
    const failed = await host.waitFor((m) => m.type === 'rejoin_failed');
    expect(failed.reason).toBe('already_in_room');
    expect(guest.msgs.some((m) => m.type === 'session_replaced')).toBe(false);
    host.close(); guest.close();
  });

  it('a rejoin while the old socket is still open replaces it', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    const gs = await sessionOf(guest);
    const fresh = await connect();
    fresh.send({ type: 'rejoin_match', code: gs.code, token: gs.token });
    await fresh.waitFor((m) => m.type === 'rejoin_ok');
    await guest.waitFor((m) => m.type === 'session_replaced');
    await host.waitFor((m) => m.type === 'opponent_reconnected');
    await sleep(50);
    expect(host.msgs.some((m) => m.type === 'opponent_disconnected')).toBe(false);
    host.close(); fresh.close(); guest.close();
  });

  it('when the waiter leaves, the match is over and the dropped player cannot rejoin', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    const gs = await sessionOf(guest);
    guest.close();
    await host.waitFor((m) => m.type === 'opponent_disconnected');
    host.send({ type: 'leave_match' });
    const end = await host.waitFor((m) => m.type === 'match_ended');
    expect(end.result).toBe('win');
    expect(end.reason).toBe('stopped_waiting_opponent_dropped');
    expect(rooms[gs.code]).toBeUndefined();

    const back = await connect();
    back.send({ type: 'check_rejoin', code: gs.code, token: gs.token });
    const st = await back.waitFor((m) => m.type === 'rejoin_status');
    expect(st.rejoinable).toBe(false);
    expect(st.matchOver).toBe(true);
    expect(st.reason).toBe('dropped_opponent_stopped_waiting');
    expect(st.result).toBe('lose');
    back.send({ type: 'rejoin_match', code: gs.code, token: gs.token });
    const failed = await back.waitFor((m) => m.type === 'rejoin_failed');
    expect(failed.reason).toBe('dropped_opponent_stopped_waiting');
    host.close(); back.close();
  });

  it('the match ends when the hold runs out', async () => {
    setTimings({ rejoinHoldMs: 150 });
    try {
      const [host, guest] = await startMatch({ mode: 'nemesis' });
      const gs = await sessionOf(guest);
      guest.close();
      const dc = await host.waitFor((m) => m.type === 'opponent_disconnected');
      expect(dc.holdSeconds).toBe(0);
      const end = await host.waitFor((m) => m.type === 'match_ended', 2000);
      expect(end.result).toBe('win');
      expect(end.reason).toBe('opponent_timed_out');
      const closed = await host.waitFor((m) => m.type === 'room_closed');
      expect(closed.reason).toBe('opponent_timed_out');
      const back = await connect();
      back.send({ type: 'check_rejoin', code: gs.code, token: gs.token });
      const st = await back.waitFor((m) => m.type === 'rejoin_status');
      expect(st.matchOver).toBe(true);
      expect(st.reason).toBe('rejoin_expired');
      expect(st.result).toBe('lose');
      host.close(); back.close();
    } finally {
      setTimings({ rejoinHoldMs: 15 * 60 * 1000 });
    }
  });

  it('the dropped player can abandon from the menu', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    const gs = await sessionOf(guest);
    guest.close();
    await host.waitFor((m) => m.type === 'opponent_disconnected');
    const back = await connect();
    back.send({ type: 'leave_match', code: gs.code, token: gs.token });
    const st = await back.waitFor((m) => m.type === 'rejoin_status');
    expect(st.matchOver).toBe(true);
    expect(st.reason).toBe('abandoned');
    const end = await host.waitFor((m) => m.type === 'match_ended');
    expect(end.reason).toBe('opponent_abandoned');
    expect(end.result).toBe('win');
    const closed = await host.waitFor((m) => m.type === 'room_closed');
    expect(closed.reason).toBe('opponent_abandoned');
    host.close(); back.close();
  });

  it('leave_match with the opponent present is a forfeit', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    host.send({ type: 'leave_match' });
    const mine = await host.waitFor((m) => m.type === 'match_ended');
    expect(mine.result).toBe('lose');
    expect(mine.reason).toBe('forfeited');
    const theirs = await guest.waitFor((m) => m.type === 'match_ended');
    expect(theirs.result).toBe('win');
    expect(theirs.reason).toBe('opponent_forfeited');
    const closed = await guest.waitFor((m) => m.type === 'room_closed');
    expect(closed.reason).toBe('opponent_left');
    expect(closed.post_match).toBe(true);
    host.close(); guest.close();
  });

  it('PvP timer holds while a player is away and resumes on rejoin', async () => {
    setTimings({ pvpTimeoutMs: 250 });
    try {
      const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, pvp_start_round: 2 });
      const gs = await sessionOf(guest);
      host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
      guest.send({ type: 'blind_entered', ante: 2, blind: 'L' });
      await enterPvpBlind(host, guest);
      host.send({ type: 'play_hand', score: '500', hands_left: 0 });
      await sleep(30);
      guest.close();
      await host.waitFor((m) => m.type === 'pvp_timer_paused');
      await sleep(500);
      expect(host.msgs.some((m) => m.type === 'pvp_resolved')).toBe(false);

      const back = await connect();
      back.send({ type: 'rejoin_match', code: gs.code, token: gs.token });
      const ok = await back.waitFor((m) => m.type === 'rejoin_ok');
      const pvp = ok.pvp as Msg;
      expect(pvp.pending).toBe(true);
      expect(pvp.started).toBe(true);
      expect(pvp.oppFinished).toBe(true);
      expect(pvp.myFinished).toBe(false);
      await back.waitFor((m) => m.type === 'pvp_timer_resumed');
      await host.waitFor((m) => m.type === 'pvp_timer_resumed');
      const res = await back.waitFor((m) => m.type === 'pvp_resolved', 2000);
      expect(res.result).toBe('lose');
      host.close(); back.close();
    } finally {
      setTimings({ pvpTimeoutMs: 180 * 1000 });
    }
  });

  it('PvP timer: a player still discarding keeps the blind open after the other is done; an idle one is still closed', async () => {
    setTimings({ pvpTimeoutMs: 300 });
    try {
      const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, pvp_start_round: 2 });
      host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
      guest.send({ type: 'blind_entered', ante: 2, blind: 'L' });
      await enterPvpBlind(host, guest);
      guest.send({ type: 'boss_sync', score: 0, hands_left: 4, discards_left: 4 });
      host.send({ type: 'play_hand', score: '500', hands_left: 0 });
      for (let d = 3; d >= 0; d--) {
        await sleep(200);
        guest.send({ type: 'boss_sync', score: 0, hands_left: 4, discards_left: d });
      }
      await sleep(150);
      expect(host.msgs.some((m) => m.type === 'pvp_resolved')).toBe(false);
      const res = await guest.waitFor((m) => m.type === 'pvp_resolved', 2000);
      expect(res.result).toBe('lose');
      host.close(); guest.close();
    } finally {
      setTimings({ pvpTimeoutMs: 180 * 1000 });
    }
  });

  it('a dropped player\'s ready flag is cleared so the blind cannot start without them', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, pvp_start_round: 2 });
    guest.send({ type: 'ready_blind' });
    await host.waitFor((m) => m.type === 'opponent_ready_blind');
    await sleep(20);
    guest.close();
    await host.waitFor((m) => m.type === 'opponent_unready_blind');
    host.send({ type: 'ready_blind' });
    await sleep(100);
    expect(host.msgs.some((m) => m.type === 'start_blind')).toBe(false);
    host.close();
  });

  it('start_blind tells both players who was Ready first', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, pvp_start_round: 2 });
    guest.send({ type: 'ready_blind' });
    await host.waitFor((m) => m.type === 'opponent_ready_blind');
    host.send({ type: 'ready_blind' });
    const a = await host.waitFor((m) => m.type === 'start_blind');
    const b = await guest.waitFor((m) => m.type === 'start_blind');
    expect(a.first).toBe(1);
    expect(b.first).toBe(1);
    host.close(); guest.close();
  });

  it('a Ready after the PvP blind started lets that player in and starts no ante timer', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, pvp_start_round: 2, timer: true, timer_base_seconds: 5 });
    const gs = await sessionOf(guest);
    await enterPvpBlind(host, guest);
    guest.close();
    await host.waitFor((m) => m.type === 'opponent_disconnected');
    const back = await connect();
    back.send({ type: 'rejoin_match', code: gs.code, token: gs.token });
    const ok = await back.waitFor((m) => m.type === 'rejoin_ok');
    expect((ok.pvp as Msg).started).toBe(true);
    expect((ok.pvp as Msg).myReady).toBe(false);
    const timersBefore = host.msgs.filter((m) => m.type === 'ante_timer' && m.state === 'running').length;
    back.send({ type: 'ready_blind' });
    await back.waitFor((m) => m.type === 'start_blind');
    await sleep(100);
    expect(host.msgs.filter((m) => m.type === 'ante_timer' && m.state === 'running').length).toBe(timersBefore);
    expect(host.msgs.filter((m) => m.type === 'opponent_ready_blind').length).toBe(1);
    host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    back.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    host.send({ type: 'play_hand', score: '500', hands_left: 0 });
    back.send({ type: 'play_hand', score: '100', hands_left: 0 });
    const res = await back.waitFor((m) => m.type === 'pvp_resolved');
    expect(res.result).toBe('lose');
    host.close(); back.close();
  });

  it('a Ready from a player who already finished the started PvP blind is ignored', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, pvp_start_round: 2 });
    await enterPvpBlind(host, guest);
    host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    guest.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    host.send({ type: 'play_hand', score: '500', hands_left: 0 });
    await sleep(50);
    host.send({ type: 'ready_blind' });
    await sleep(100);
    expect(host.msgs.filter((m) => m.type === 'start_blind').length).toBe(1);
    expect(guest.msgs.filter((m) => m.type === 'opponent_ready_blind').length).toBe(1);
    host.close(); guest.close();
  });

  it('a too fast Unready is answered with ready_blind_kept and the blind still starts', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3 });
    guest.send({ type: 'ready_blind' });
    guest.send({ type: 'unready_blind' });
    await guest.waitFor((m) => m.type === 'ready_blind_kept');
    expect(host.msgs.some((m) => m.type === 'opponent_unready_blind')).toBe(false);
    host.send({ type: 'ready_blind' });
    await guest.waitFor((m) => m.type === 'start_blind');
    host.close(); guest.close();
  });
});

describe('save snapshots', () => {
  it('accepts a large snapshot and rejects bad ones', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    host.send({ type: 'save_snapshot', data: fakeSave(300 * 1024), seq: 5 });
    const ack = await host.waitFor((m) => m.type === 'snapshot_ack');
    expect(ack.bytes).toBe(300 * 1024);
    host.send({ type: 'save_snapshot', data: fakeSave(10), seq: 4 });
    const stale = await host.waitFor((m) => m.type === 'snapshot_ack' && m.stale === true);
    expect(stale.seq).toBe(4);
    host.send({ type: 'save_snapshot', data: 'not base64!!' });
    const bad = await host.waitFor((m) => m.type === 'error');
    expect(bad.reason).toContain('base64');
    host.close(); guest.close();
  });

  it('accepts a snapshot sent inside the compressed wrapper', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    const json = JSON.stringify({ type: 'save_snapshot', data: fakeSave(200 * 1024), seq: 1 });
    const wrapped = `{"z":1,"d":"${Buffer.from(Bun.deflateSync(Buffer.from(json))).toString('base64')}"}`;
    host.send(JSON.parse(wrapped) as Msg);
    const ack = await host.waitFor((m) => m.type === 'snapshot_ack');
    expect(ack.bytes).toBe(200 * 1024);
    host.close(); guest.close();
  });

  it('validates snapshot size and format', () => {
    expect(validateMessage({ type: 'save_snapshot', data: fakeSave(SNAPSHOT_MAX_BYTES) }, 800000)).toBeNull();
    expect(validateMessage({ type: 'save_snapshot', data: fakeSave(SNAPSHOT_MAX_BYTES + 3) }, 800000)).toContain('too large');
    expect(validateMessage({ type: 'save_snapshot', data: '' }, 50)).toContain('missing data');
    expect(validateMessage({ type: 'save_snapshot', data: 'abc' }, 50)).toContain('base64');
    expect(validateMessage({ type: 'save_snapshot', data: 'AAAA' }, 2_000_000)).toContain('oversized');
    expect(validateMessage({ type: 'ping' }, 5000)).toContain('oversized');
  });

  it('refuses a snapshot outside a match', async () => {
    const c = await connect();
    c.send({ type: 'save_snapshot', data: fakeSave(30) });
    const err = await c.waitFor((m) => m.type === 'error');
    expect(err.reason).toContain('no match');
    c.close();
  });
});

describe('match end reasons', () => {
  it('winner and loser each get their own reason', async () => {
    const [host, guest] = await finishedMatch();
    const hEnd = host.msgs.find((m) => m.type === 'match_ended')!;
    const gEnd = guest.msgs.find((m) => m.type === 'match_ended')!;
    expect(hEnd.result).toBe('win');
    expect(hEnd.reason).toBe('opponent_eliminated');
    expect(gEnd.result).toBe('lose');
    expect(gEnd.reason).toBe('eliminated');
    const gState = await guest.waitFor((m) => m.type === 'match_state_update' && m.phase === 'finished');
    expect(gState.winReason).toBe('eliminated');
    host.close(); guest.close();
  });

  it('PvP elimination gives the loser its own reason too', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 1, pvp_start_round: 2 });
    host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    guest.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    host.send({ type: 'play_hand', score: '900', hands_left: 0 });
    guest.send({ type: 'play_hand', score: '100', hands_left: 0 });
    const g = await guest.waitFor((m) => m.type === 'pvp_resolved');
    const h = await host.waitFor((m) => m.type === 'pvp_resolved');
    expect(g.matchEnded).toBe(true);
    expect(g.winReason).toBe('eliminated');
    expect(h.winReason).toBe('opponent_eliminated');
    host.close(); guest.close();
  });

  it('room_expired reaches clients before the room closes', async () => {
    const host = await connect();
    host.send({ type: 'create_room' });
    const created = await host.waitFor((m) => m.type === 'room_created');
    rooms[created.code as string].lastActivity = 0;
    sweepRooms();
    const exp = await host.waitFor((m) => m.type === 'room_expired');
    expect(exp.reason).toBe('ttl_expired');
    const closed = await host.waitFor((m) => m.type === 'room_closed');
    expect(closed.reason).toBe('room_expired');
    expect(rooms[created.code as string]).toBeUndefined();
    host.close();
  });

  it('a host disconnect in the lobby closes the room with a reason', async () => {
    const host = await connect();
    const guest = await connect();
    host.send({ type: 'create_room' });
    const created = await host.waitFor((m) => m.type === 'room_created');
    guest.send({ type: 'join_room', code: created.code });
    await guest.waitFor((m) => m.type === 'room_ready');
    host.close();
    const closed = await guest.waitFor((m) => m.type === 'room_closed');
    expect(closed.reason).toBe('opponent_disconnected');
    expect(closed.post_match).toBe(false);
    guest.close();
  });

  it('a guest disconnect in the lobby keeps the room full and holds the seat', async () => {
    const host = await connect();
    const guest = await connect();
    host.send({ type: 'create_room' });
    const created = await host.waitFor((m) => m.type === 'room_created');
    guest.send({ type: 'join_room', code: created.code });
    await host.waitFor((m) => m.type === 'room_ready');
    guest.close();
    const left = await host.waitFor((m) => m.type === 'guest_left');
    expect(left.reason).toBe('opponent_disconnected');
    expect(left.held).toBe(true);
    expect(host.msgs.some((m) => m.type === 'room_closed')).toBe(false);
    const room = rooms[created.code as string];
    expect(room.sockets.length).toBe(2);
    expect(room.sockets[1]).toBeNull();
    expect(room.holdDeadline[1]).not.toBeNull();
    host.close();
  });
});

describe('results screen', () => {
  it('both rematch votes start a new match with fresh sessions', async () => {
    const [host, guest] = await finishedMatch();
    host.send({ type: 'rematch_vote' });
    const s1 = await guest.waitFor((m) => m.type === 'rematch_status');
    expect(s1.votes).toEqual([true, false]);
    expect(s1.by).toBe(0);
    guest.send({ type: 'rematch_vote' });
    await host.waitFor((m) => m.type === 'rematch_status' && (m.votes as boolean[])[1] === true);
    await host.waitFor((m) => m.type === 'rematch_accepted');
    await guest.waitFor((m) => m.type === 'rematch_accepted');
    await sleep(30);
    expect(host.msgs.filter((m) => m.type === 'match_session').length).toBe(2);
    host.close(); guest.close();
  });

  it('a vote then quit sends the other player out with a reason', async () => {
    const [host, guest] = await finishedMatch();
    guest.send({ type: 'rematch_vote' });
    await host.waitFor((m) => m.type === 'rematch_status');
    guest.send({ type: 'return_to_menu' });
    const legacy = await host.waitFor((m) => m.type === 'opponent_returned_to_menu');
    expect(legacy.post_match).toBe(true);
    const closed = await host.waitFor((m) => m.type === 'room_closed');
    expect(closed.reason).toBe('opponent_left');
    expect(closed.post_match).toBe(true);
    host.close(); guest.close();
  });

  it('only the host returns to lobby, it brings both and clears rematch votes', async () => {
    const [host, guest] = await finishedMatch();
    guest.send({ type: 'return_to_lobby' });
    const err = await guest.waitFor((m) => m.type === 'error');
    expect(err.reason).toBe('host_only');
    guest.send({ type: 'rematch_vote' });
    await host.waitFor((m) => m.type === 'rematch_status');
    host.send({ type: 'return_to_lobby' });
    const g = await guest.waitFor((m) => m.type === 'lobby_returned');
    const h = await host.waitFor((m) => m.type === 'lobby_returned');
    expect(g.rematchCleared).toBe(true);
    expect(h.by).toBe(0);
    await guest.waitFor((m) => m.type === 'opponent_returned_to_lobby');
    const code = (await host.waitFor((m) => m.type === 'room_created')).code as string;
    expect(rooms[code].match?.phase).toBe('lobby');
    expect(rooms[code].rematchVotes).toEqual([false, false]);
    host.send({ type: 'rematch_vote' });
    const no = await host.waitFor((m) => m.type === 'error');
    expect(no.reason).toBe('rematch_unavailable');
    host.close(); guest.close();
  });

  it('after a quick match the loser hosts the next lobby', async () => {
    const a = await connect();
    const b = await connect();
    a.send({ type: 'find_match' });
    await a.waitFor((m) => m.type === 'searching');
    b.send({ type: 'find_match' });
    const ra = await a.waitFor((m) => m.type === 'room_ready');
    const rb = await b.waitFor((m) => m.type === 'room_ready');
    expect(ra.host).toBe(true);
    const code = ra.code as string;
    a.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'nemesis', starting_lives: 1 }, player_name: 'A' });
    await b.waitFor((m) => m.type === 'match_state_update' && m.event === 'match_started');
    b.send({ type: 'game_over', ante: 1, blind: 'S', score: 10 });
    await a.waitFor((m) => m.type === 'match_ended');
    a.send({ type: 'return_to_lobby' });
    const la = await a.waitFor((m) => m.type === 'lobby_returned');
    const lb = await b.waitFor((m) => m.type === 'lobby_returned');
    expect(la.host).toBe(false);
    expect(la.playerId).toBe(1);
    expect(la.token).toBe(ra.token);
    expect(lb.host).toBe(true);
    expect(lb.playerId).toBe(0);
    expect(lb.token).toBe(rb.token);
    const hist = (lb.gameHistory as Msg[])[0];
    expect(hist.winner).toBe(1);
    expect(rooms[code].tokens).toEqual([rb.token, ra.token]);
    const seen = (c: TestClient, t: string) => c.msgs.filter((m) => m.type === t).length;
    const nth = (c: TestClient, t: string, n: number) => c.waitFor(() => seen(c, t) >= n).then(() => c.msgs.filter((m) => m.type === t)[n - 1]);
    const started = a.msgs.filter((m) => m.type === 'match_state_update' && m.event === 'match_started').length;
    b.send({ type: 'match_start', seed: 'TEST2', settings: { mode: 'nemesis', starting_lives: 1 }, player_name: 'B' });
    await a.waitFor(() => a.msgs.filter((m) => m.type === 'match_state_update' && m.event === 'match_started').length > started);
    a.send({ type: 'game_over', ante: 1, blind: 'S', score: 10 });
    await nth(b, 'match_ended', 2);
    b.send({ type: 'return_to_lobby' });
    const lb2 = await nth(b, 'lobby_returned', 2);
    expect(lb2.host).toBe(false);
    a.close(); b.close();
  });

  it('a disconnect on the results screen is treated as a quit', async () => {
    const [host, guest] = await finishedMatch();
    host.close();
    const legacy = await guest.waitFor((m) => m.type === 'opponent_left');
    expect(legacy.post_match).toBe(true);
    const closed = await guest.waitFor((m) => m.type === 'room_closed');
    expect(closed.reason).toBe('opponent_disconnected');
    expect(closed.post_match).toBe(true);
    guest.close();
  });
});

describe('match rules', () => {
  it('same seed: both players get the host seed', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    const ms = await guest.waitFor((m) => m.type === 'match_start');
    expect(ms.seed).toBe('TEST');
    await sleep(30);
    expect(host.msgs.some((m) => m.type === 'match_seed')).toBe(false);
    host.close(); guest.close();
  });

  it('custom seed is cleaned and forced on both players', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', custom_seed: 'ab-c12' });
    const ms = await guest.waitFor((m) => m.type === 'match_start');
    expect(ms.seed).toBe('ABC12');
    const hs = await host.waitFor((m) => m.type === 'match_seed');
    expect(hs.seed).toBe('ABC12');
    host.close(); guest.close();
  });

  it('different seeds give the guest its own seed and ignore the custom seed', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', different_seeds: true, same_seed: false, custom_seed: 'ZZZ' });
    const ms = await guest.waitFor((m) => m.type === 'match_start');
    expect(typeof ms.seed).toBe('string');
    expect(ms.seed).not.toBe('TEST');
    expect((ms.seed as string).length).toBe(8);
    await sleep(30);
    expect(host.msgs.some((m) => m.type === 'match_seed')).toBe(false);
    host.close(); guest.close();
  });

  it('rematch keeps the seed rule', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 1, custom_seed: 'REMATCH1' });
    guest.send({ type: 'game_over', ante: 1, blind: 'S', score: 10 });
    await host.waitFor((m) => m.type === 'match_ended');
    host.send({ type: 'rematch_vote' });
    guest.send({ type: 'rematch_vote' });
    const a = await host.waitFor((m) => m.type === 'rematch_accepted');
    const b = await guest.waitFor((m) => m.type === 'rematch_accepted');
    expect(a.seed).toBe('REMATCH1');
    expect(b.seed).toBe('REMATCH1');
    host.close(); guest.close();
  });

  it('timer: forgiveness first, then a life, then readying stops it', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, timer: true, timer_base_seconds: 0.3, timer_forgiveness: 1 });
    host.send({ type: 'ready_blind' });
    const run = await guest.waitFor((m) => m.type === 'ante_timer' && m.state === 'running');
    expect(run.target).toBe('me');
    expect(run.forgivenessLeft).toBe(1);
    const hostView = await host.waitFor((m) => m.type === 'ante_timer' && m.state === 'running');
    expect(hostView.target).toBe('opp');
    const f = await guest.waitFor((m) => m.type === 'ante_timer' && m.state === 'expired' && m.forgiven === true, 3000);
    expect(f.lives).toBe(3);
    const l = await guest.waitFor((m) => m.type === 'ante_timer' && m.state === 'expired' && m.forgiven === false, 3000);
    expect(l.lives).toBe(2);
    const st = await host.waitFor((m) => m.type === 'match_state_update' && m.event === 'ante_timer');
    expect(st.oppLives).toBe(2);
    guest.send({ type: 'ready_blind' });
    await guest.waitFor((m) => m.type === 'ante_timer' && m.state === 'stopped');
    await guest.waitFor((m) => m.type === 'start_blind');
    host.close(); guest.close();
  });

  it('timer: the last life lost to the timer ends the match', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 1, ante_timer: true, ante_timer_base: 0.3 });
    guest.send({ type: 'ready_blind' });
    const end = await host.waitFor((m) => m.type === 'match_state_update' && m.phase === 'finished', 3000);
    expect(end.winner).toBe(1);
    expect(end.myLives).toBe(0);
    host.close(); guest.close();
  });

  it('timer: unready cancels it and the increment grows per ante', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', timer: true, timer_base_seconds: 10, timer_increment_seconds: 5 });
    guest.send({ type: 'blind_entered', ante: 3, blind: 'L' });
    await host.waitFor((m) => m.type === 'match_state_update' && m.event === 'blind_entered');
    guest.send({ type: 'ready_blind' });
    const run = await host.waitFor((m) => m.type === 'ante_timer' && m.state === 'running');
    expect(run.msLeft as number).toBeGreaterThan(19000);
    expect(run.msLeft as number).toBeLessThanOrEqual(20000);
    await sleep(1000);
    guest.send({ type: 'unready_blind' });
    await host.waitFor((m) => m.type === 'ante_timer' && m.state === 'stopped');
    host.close(); guest.close();
  });

  it('timer pauses while the timed player is away and resumes on rejoin', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', timer: true, timer_base_seconds: 5 });
    const gs = await sessionOf(guest);
    host.send({ type: 'ready_blind' });
    await guest.waitFor((m) => m.type === 'ante_timer' && m.state === 'running');
    guest.close();
    const p = await host.waitFor((m) => m.type === 'ante_timer' && m.state === 'paused');
    expect(p.msLeft as number).toBeGreaterThan(3000);
    const g2 = await connect();
    g2.send({ type: 'rejoin_match', code: gs.code, token: gs.token });
    const ok = await g2.waitFor((m) => m.type === 'rejoin_ok');
    expect((ok.anteClock as Msg).target).toBe('me');
    const r = await g2.waitFor((m) => m.type === 'ante_timer' && m.state === 'running');
    expect(r.target).toBe('me');
    host.close(); g2.close();
  });

  it('player_deck is stored for rejoin and relayed', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', different_decks: true });
    const gs = await sessionOf(guest);
    guest.send({ type: 'player_deck', deck: 'Yellow Deck' });
    const od = await host.waitFor((m) => m.type === 'opponent_deck');
    expect(od.deck).toBe('Yellow Deck');
    guest.close();
    await sleep(50);
    const g2 = await connect();
    g2.send({ type: 'rejoin_match', code: gs.code, token: gs.token });
    const ok = await g2.waitFor((m) => m.type === 'rejoin_ok');
    expect(ok.myDeck).toBe('Yellow Deck');
    host.close(); g2.close();
  });
});

describe('life rules', () => {
  it('lifeOnRoundLoss follows death_on_round_loss, then non_pvp_life_loss, then defaults on', () => {
    expect(lifeOnRoundLoss(undefined)).toBe(true);
    expect(lifeOnRoundLoss({})).toBe(true);
    expect(lifeOnRoundLoss({ death_on_round_loss: false })).toBe(false);
    expect(lifeOnRoundLoss({ non_pvp_life_loss: false })).toBe(false);
    expect(lifeOnRoundLoss({ death_on_round_loss: true, non_pvp_life_loss: false })).toBe(true);
    expect(lifeOnRoundLoss({ death_on_round_loss: 'no' })).toBe(true);
  });

  it('a lost non-PvP round costs a life by default', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3 });
    guest.send({ type: 'game_over', ante: 1, blind: 'S', score: 10 });
    const st = await guest.waitFor((m) => m.type === 'match_state_update' && m.event === 'life_lost');
    expect(st.myLives).toBe(2);
    expect(st.oppLives).toBe(3);
    host.close(); guest.close();
  });

  it('death_on_round_loss off keeps lives on a lost non-PvP round', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, death_on_round_loss: false, non_pvp_life_loss: false });
    guest.send({ type: 'game_over', ante: 1, blind: 'S', score: 10 });
    const st = await guest.waitFor((m) => m.type === 'match_state_update' && m.event === 'round_lost');
    expect(st.myLives).toBe(3);
    expect(st.phase).toBe('playing');
    const hs = await host.waitFor((m) => m.type === 'match_state_update' && m.event === 'round_lost');
    expect(hs.oppLives).toBe(3);
    host.close(); guest.close();
  });

  it('death_on_round_loss off still costs a life on a lost PvP blind', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, pvp_start_round: 2, death_on_round_loss: false });
    await enterPvpBlind(host, guest);
    host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    guest.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    host.send({ type: 'play_hand', score: '500', hands_left: 0 });
    guest.send({ type: 'play_hand', score: '100', hands_left: 0 });
    const res = await guest.waitFor((m) => m.type === 'pvp_resolved');
    expect(res.result).toBe('lose');
    expect(res.myLives).toBe(2);
    host.close(); guest.close();
  });

  it('match_settings from the lobby decide the rule and drop non-boolean values', async () => {
    const host = await connect();
    const guest = await connect();
    host.send({ type: 'create_room' });
    const created = await host.waitFor((m) => m.type === 'room_created');
    guest.send({ type: 'join_room', code: created.code });
    await host.waitFor((m) => m.type === 'room_ready');
    host.send({ type: 'match_settings', settings: { death_on_round_loss: false, no_gold_on_round_loss: 'yes' } });
    await guest.waitFor((m) => m.type === 'match_settings');
    const room = rooms[created.code as string];
    expect(room.settings.death_on_round_loss).toBe(false);
    expect(room.settings.no_gold_on_round_loss).toBeUndefined();
    host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'nemesis', starting_lives: 2 }, player_name: 'Host' });
    await guest.waitFor((m) => m.type === 'match_state_update' && m.event === 'match_started');
    host.send({ type: 'game_over', ante: 1, blind: 'B', score: 1 });
    const st = await host.waitFor((m) => m.type === 'match_state_update' && m.event === 'round_lost');
    expect(st.myLives).toBe(2);
    host.close(); guest.close();
  });

  it('only the host changes 1v1 settings or starts, and never during a match', async () => {
    const host = await connect();
    const guest = await connect();
    host.send({ type: 'create_room' });
    const created = await host.waitFor((m) => m.type === 'room_created');
    guest.send({ type: 'join_room', code: created.code });
    await host.waitFor((m) => m.type === 'room_ready');
    const room = rooms[created.code as string];
    guest.send({ type: 'match_settings', settings: { starting_lives: 9, allow_score_preview: true } });
    guest.send({ type: 'match_start', seed: 'GUEST', settings: { starting_lives: 9 }, player_name: 'Guest' });
    await sleep(150);
    expect(room.settings.starting_lives).not.toBe(9);
    expect(room.settings.allow_score_preview).toBeUndefined();
    expect(room.match).toBeFalsy();
    expect(host.msgs.some((m) => m.type === 'match_settings')).toBe(false);
    host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'nemesis', starting_lives: 2 }, player_name: 'Host' });
    await guest.waitFor((m) => m.type === 'match_state_update' && m.event === 'match_started');
    host.send({ type: 'match_settings', settings: { starting_lives: 7, allow_score_preview: true } });
    await sleep(150);
    expect(room.settings.starting_lives).toBe(2);
    expect(room.settings.allow_score_preview).toBeUndefined();
    expect(guest.msgs.some((m) => m.type === 'match_settings')).toBe(false);
    host.close(); guest.close();
  });
});

async function waitCount(c: TestClient, type: string, n: number): Promise<Msg> {
  for (let i = 0; i < 100; i++) {
    const all = c.msgs.filter((m) => m.type === type);
    if (all.length >= n) return all[n - 1];
    await sleep(20);
  }
  throw new Error(`timed out waiting for ${n} x ${type}`);
}

async function pvpRound(host: TestClient, guest: TestClient, ante: number, hs: number, gs: number, n: number): Promise<[Msg, Msg]> {
  host.send({ type: 'blind_entered', ante, blind: 'L' });
  guest.send({ type: 'blind_entered', ante, blind: 'L' });
  host.send({ type: 'play_hand', score: String(hs), hands_left: 0 });
  guest.send({ type: 'play_hand', score: String(gs), hands_left: 0 });
  return [await waitCount(host, 'pvp_resolved', n), await waitCount(guest, 'pvp_resolved', n)];
}

describe('final ante', () => {
  it('the final ante comes from win_ante, then the stake, then 8', () => {
    expect(finalAnteFor({})).toBe(8);
    expect(finalAnteFor(undefined)).toBe(8);
    expect(finalAnteFor({ stake: 8 })).toBe(8);
    expect(finalAnteFor({ stake: 9 })).toBe(10);
    expect(finalAnteFor({ stake: 12 })).toBe(13);
    expect(finalAnteFor({ stake: 13 })).toBe(8);
    expect(finalAnteFor({ win_ante: 5, stake: 10 })).toBe(5);
    expect(finalAnteFor({ win_ante: 0 })).toBe(8);
    expect(finalAnteFor({ win_ante: 'x' })).toBe(8);
    expect(createMatchState({ win_ante: 3 } as never).finalAnte).toBe(3);
  });

  it('a draw on the last PvP blind with different lives goes on to sudden death', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, pvp_start_round: 2, win_ante: 3 });
    const [h1] = await pvpRound(host, guest, 2, 500, 100, 1);
    expect(h1.matchEnded).toBe(false);
    expect(h1.oppLives).toBe(2);
    const [h2, g2] = await pvpRound(host, guest, 3, 300, 300, 2);
    expect(h2.result).toBe('draw');
    expect(h2.matchEnded).toBe(false);
    expect(h2.finalPvp).toBe(true);
    expect(h2.suddenDeath).toBe(1);
    expect(h2.myLives).toBe(3);
    expect(g2.myLives).toBe(2);
    await sleep(50);
    expect(host.msgs.some((m) => m.type === 'match_ended')).toBe(false);
    host.close(); guest.close();
  });

  it('a draw with equal lives starts sudden death and the next Nemesis win takes the match', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 1, pvp_start_round: 2, win_ante: 2 });
    const [h1, g1] = await pvpRound(host, guest, 2, 250, 250, 1);
    expect(h1.matchEnded).toBe(false);
    expect(h1.suddenDeath).toBe(1);
    expect(g1.suddenDeath).toBe(1);
    expect(h1.myLives).toBe(1);
    expect(g1.myLives).toBe(1);
    const st = await guest.waitFor((m) => m.type === 'match_state_update' && m.event === 'pvp_resolved');
    expect(st.phase).toBe('playing');
    expect(st.suddenDeath).toBe(1);
    expect(st.finalAnte).toBe(2);
    expect(host.msgs.some((m) => m.type === 'match_ended')).toBe(false);
    const [h2] = await pvpRound(host, guest, 3, 900, 100, 2);
    expect(h2.matchEnded).toBe(true);
    expect(h2.winner).toBe(0);
    const hEnd = await host.waitFor((m) => m.type === 'match_ended');
    const gEnd = await guest.waitFor((m) => m.type === 'match_ended');
    expect(hEnd.reason).toBe('sudden_death_won');
    expect(gEnd.reason).toBe('sudden_death_lost');
    expect(gEnd.result).toBe('lose');
    host.close(); guest.close();
  });

  it('a sudden death draw plays another round until someone wins', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 1, pvp_start_round: 2, win_ante: 2 });
    await pvpRound(host, guest, 2, 100, 100, 1);
    const [h2] = await pvpRound(host, guest, 3, 100, 100, 2);
    expect(h2.matchEnded).toBe(false);
    expect(h2.suddenDeath).toBe(2);
    const [h3, g3] = await pvpRound(host, guest, 4, 100, 700, 3);
    expect(h3.matchEnded).toBe(true);
    expect(h3.winner).toBe(1);
    expect(g3.winReason).toBe('sudden_death_won');
    expect(h3.winReason).toBe('sudden_death_lost');
    host.close(); guest.close();
  });

  it('a draw before the final ante is only a draw, and a custom final ante is respected', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 2, pvp_start_round: 2, win_ante: 4 });
    const [h1] = await pvpRound(host, guest, 2, 100, 100, 1);
    expect(h1.matchEnded).toBe(false);
    expect(h1.finalPvp).toBe(false);
    expect(h1.suddenDeath).toBe(0);
    const [h2] = await pvpRound(host, guest, 3, 100, 100, 2);
    expect(h2.suddenDeath).toBe(0);
    const [h3] = await pvpRound(host, guest, 4, 100, 100, 3);
    expect(h3.suddenDeath).toBe(1);
    host.close(); guest.close();
  });

  it('losing the last PvP blind with lives left does not end the match, only lives do', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, pvp_start_round: 2, win_ante: 2 });
    const [h1, g1] = await pvpRound(host, guest, 2, 100, 400, 1);
    expect(h1.matchEnded).toBe(false);
    expect(h1.finalPvp).toBe(true);
    expect(h1.myLives).toBe(2);
    expect(h1.suddenDeath).toBe(1);
    expect(g1.result).toBe('win');
    const [h2] = await pvpRound(host, guest, 3, 900, 100, 2);
    expect(h2.matchEnded).toBe(false);
    expect(h2.oppLives).toBe(2);
    expect(h2.suddenDeath).toBe(2);
    await pvpRound(host, guest, 4, 100, 400, 3);
    const [h4, g4] = await pvpRound(host, guest, 5, 100, 400, 4);
    expect(h4.matchEnded).toBe(true);
    expect(h4.myLives).toBe(0);
    expect(h4.winner).toBe(1);
    expect(g4.winReason).toBe('sudden_death_won');
    expect(h4.winReason).toBe('sudden_death_lost');
    host.close(); guest.close();
  });

  it('losing a non-final PvP blind in faceoff with lives left keeps the match going', async () => {
    const [host, guest] = await startMatch({ mode: 'faceoff', starting_lives: 2, showdown_starting_antes: 1, win_ante: 8 });
    const [h1] = await pvpRound(host, guest, 2, 100, 400, 1);
    expect(h1.matchEnded).toBe(false);
    expect(h1.myLives).toBe(1);
    host.close(); guest.close();
  });

  it('a run_completed claim is ignored in PvP modes but still ends a vanilla match', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 2, pvp_start_round: 2, win_ante: 2 });
    await pvpRound(host, guest, 2, 100, 100, 1);
    host.send({ type: 'match_finished', result: 'win', reason: 'run_completed' });
    await sleep(80);
    expect(host.msgs.some((m) => m.type === 'match_ended')).toBe(false);
    expect(guest.msgs.some((m) => m.type === 'match_ended')).toBe(false);
    host.close(); guest.close();
    const [h2, g2] = await startMatch({ mode: 'vanilla', starting_lives: 2 });
    g2.send({ type: 'match_finished', result: 'win', reason: 'run_completed' });
    const hEnd = await h2.waitFor((m) => m.type === 'match_ended');
    expect(hEnd.result).toBe('lose');
    expect(hEnd.reason).toBe('opponent_completed');
    h2.close(); g2.close();
  });

  it('a player who rejoins during sudden death gets the sudden death round', async () => {
    const [host, guest] = await startMatch({ mode: 'faceoff', starting_lives: 1, showdown_starting_antes: 1, win_ante: 2 });
    const sess = await guest.waitFor((m) => m.type === 'match_session');
    await pvpRound(host, guest, 2, 100, 100, 1);
    guest.close();
    await host.waitFor((m) => m.type === 'opponent_disconnected');
    const back = await connect();
    back.send({ type: 'rejoin_match', code: sess.code, token: sess.token });
    const ok = await back.waitFor((m) => m.type === 'rejoin_ok');
    expect(ok.suddenDeath).toBe(1);
    expect(ok.finalAnte).toBe(2);
    expect(ok.phase).toBe('playing');
    host.send({ type: 'blind_entered', ante: 3, blind: 'L' });
    back.send({ type: 'blind_entered', ante: 3, blind: 'L' });
    host.send({ type: 'play_hand', score: '100', hands_left: 0 });
    back.send({ type: 'play_hand', score: '500', hands_left: 0 });
    const h2 = await waitCount(host, 'pvp_resolved', 2);
    const g2 = await waitCount(back, 'pvp_resolved', 1);
    expect(g2.matchEnded).toBe(true);
    expect(g2.result).toBe('win');
    expect(h2.winReason).toBe('sudden_death_lost');
    host.close(); back.close();
  });
});

const sampleEnd = {
  jokers: [{ k: 'j_joker', ed: 'foil', st: ['eternal'] }, { k: 'j_blueprint' }],
  deck: { back: 'b_red', cards: [{ f: 'H_A', e: 'm_glass', ed: 'holo', s: 'Red' }, { f: 'S_2' }] },
};

describe('end game viewer', () => {
  it('stores each player\'s jokers and deck and answers requests', async () => {
    const [host, guest] = await finishedMatch();
    host.send({ type: 'get_end_game_jokers' });
    const none = await host.waitFor((m) => m.type === 'end_game_jokers');
    expect(none.available).toBe(false);
    host.send({ type: 'end_game_data', ...sampleEnd });
    const pushed = await guest.waitFor((m) => m.type === 'end_game_jokers');
    expect(pushed.available).toBe(true);
    expect(pushed.playerId).toBe(0);
    expect(pushed.jokers).toEqual(sampleEnd.jokers);
    const deck = await guest.waitFor((m) => m.type === 'nemesis_deck_data');
    expect(deck.back).toBe('b_red');
    expect(deck.cards).toEqual(sampleEnd.deck.cards);
    guest.msgs.length = 0;
    guest.send({ type: 'get_end_game_jokers' });
    const again = await guest.waitFor((m) => m.type === 'end_game_jokers');
    expect(again.jokers).toEqual(sampleEnd.jokers);
    await guest.waitFor((m) => m.type === 'nemesis_deck_data');
    host.close(); guest.close();
  });

  it('a big deck goes through the compressed wrapper', async () => {
    const [host, guest] = await finishedMatch();
    const cards = Array.from({ length: 600 }, (_, i) => ({ f: ['H', 'S', 'C', 'D'][i % 4] + '_' + String(2 + (i % 9)), e: 'm_bonus', ed: 'foil', s: 'Gold' }));
    const json = JSON.stringify({ type: 'end_game_data', jokers: [], deck: { back: 'b_blue', cards } });
    expect(json.length).toBeGreaterThan(4096);
    const z = Buffer.from(Bun.deflateSync(Buffer.from(json))).toString('base64');
    guest.send({ z: 1, d: z } as Msg);
    const deck = await host.waitFor((m) => m.type === 'nemesis_deck_data');
    expect((deck.cards as unknown[]).length).toBe(600);
    host.close(); guest.close();
  });

  it('rejects bad or oversized data and data outside a finished match', async () => {
    expect(validateMessage({ type: 'end_game_data', ...sampleEnd }, 200)).toBeNull();
    expect(validateMessage({ type: 'end_game_data', jokers: [] }, 20)).toBeNull();
    expect(validateMessage({ type: 'end_game_data', jokers: 'x' }, 20)).toContain('jokers');
    expect(validateMessage({ type: 'end_game_data', jokers: Array.from({ length: 101 }, () => ({ k: 'j_joker' })) }, 2000)).toContain('too many jokers');
    expect(validateMessage({ type: 'end_game_data', jokers: [{ k: 'bad key!' }] }, 50)).toContain('invalid joker');
    expect(validateMessage({ type: 'end_game_data', jokers: [], deck: { cards: Array.from({ length: 1001 }, () => ({ f: 'H_A' })) } }, 20000)).toContain('too many cards');
    expect(validateMessage({ type: 'end_game_data', jokers: [], deck: { cards: [{ f: 'H_A', s: { x: 1 } }] } }, 60)).toContain('invalid card');
    expect(validateMessage({ type: 'end_game_data', jokers: [] }, 70 * 1024)).toContain('oversized');
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 2 });
    host.send({ type: 'end_game_data', ...sampleEnd });
    const err = await host.waitFor((m) => m.type === 'error');
    expect(err.reason).toBe('end_game_data: no finished match');
    expect(guest.msgs.some((m) => m.type === 'end_game_jokers')).toBe(false);
    host.close(); guest.close();
  });

  it('a rematch clears the stored data', async () => {
    const [host, guest] = await finishedMatch();
    host.send({ type: 'end_game_data', ...sampleEnd });
    await guest.waitFor((m) => m.type === 'end_game_jokers');
    host.send({ type: 'rematch_vote' });
    guest.send({ type: 'rematch_vote' });
    await guest.waitFor((m) => m.type === 'rematch_accepted');
    guest.send({ type: 'game_over', ante: 1, blind: 'S', score: 1 });
    await waitCount(guest, 'match_ended', 2);
    guest.msgs.length = 0;
    guest.send({ type: 'get_end_game_jokers' });
    const res = await guest.waitFor((m) => m.type === 'end_game_jokers');
    expect(res.available).toBe(false);
    host.close(); guest.close();
  });
});

const MODS_A = [{ id: 'Cryptid', name: 'Cryptid', version: '0.5.17c' }, { id: 'Amulet', name: 'Amulet', version: '3.6.1' }];
const MODS_B = [{ id: 'Cryptid', name: 'Cryptid', version: '0.5.18' }, { id: 'Amulet', name: 'Amulet', version: '3.6.1' }];

async function hostRoom(extra: Msg): Promise<[TestClient, Msg]> {
  const host = await connect();
  host.send({ type: 'create_room', ...extra });
  const created = await host.waitFor((m) => m.type === 'room_created');
  return [host, created];
}

async function listFor(c: TestClient, mods?: unknown): Promise<Msg[]> {
  const before = c.msgs.filter((m) => m.type === 'room_list').length;
  c.send(mods === undefined ? { type: 'list_rooms' } : { type: 'list_rooms', mods });
  await c.waitFor(() => c.msgs.filter((m) => m.type === 'room_list').length > before);
  return c.msgs.filter((m) => m.type === 'room_list')[before].rooms as Msg[];
}

const modKey = (m: Msg) => String(m.id) + '@' + String(m.version);

describe('rooms and browsing', () => {
  it('validates the new room messages', () => {
    expect(validateMessage({ type: 'create_room', visibility: 'public', mods: MODS_A, name: 'Gab' }, 200)).toBeNull();
    expect(validateMessage({ type: 'create_room', visibility: 'secret' }, 50)).toContain('visibility');
    expect(validateMessage({ type: 'join_room', id: 'abcdef012345' }, 50)).toBeNull();
    expect(validateMessage({ type: 'join_room', id: 'nope' }, 50)).toContain('invalid id');
    expect(validateMessage({ type: 'join_room' }, 50)).toContain('invalid code');
    expect(validateMessage({ type: 'list_rooms', mods: [{ id: '' }] }, 50)).toContain('invalid mods');
    expect(validateMessage({ type: 'list_rooms', mods: 'x' }, 50)).toContain('invalid mods');
    expect(validateMessage({ type: 'join_room', code: 'ABCD', mods: MODS_A }, 9000)).toBeNull();
    expect(validateMessage({ type: 'ping', rtt: 42 }, 30)).toBeNull();
    expect(validateMessage({ type: 'ping', rtt: -1 }, 30)).toContain('rtt');
  });

  it('room_created says the visibility and the room id', async () => {
    const [host, created] = await hostRoom({ visibility: 'public', name: 'Gab' });
    expect(created.visibility).toBe('public');
    expect(typeof created.id).toBe('string');
    expect(created.modded).toBe(false);
    const [h2, c2] = await hostRoom({});
    expect(c2.visibility).toBe('private');
    host.close(); h2.close();
  });

  it('the room list shows public and private rooms without private codes', async () => {
    const [pub, pc] = await hostRoom({ visibility: 'public', name: 'PubHost' });
    const [priv, vc] = await hostRoom({ visibility: 'private', name: 'PrivHost', mods: MODS_A });
    pub.send({ type: 'ping', rtt: 87 });
    await pub.waitFor((m) => m.type === 'pong');
    const viewer = await connect();
    const list = await listFor(viewer);
    const p = list.find((r) => r.id === pc.id)!;
    const v = list.find((r) => r.id === vc.id)!;
    expect(p.name).toBe('PubHost');
    expect(p.players).toBe(1);
    expect(p.maxPlayers).toBe(2);
    expect(p.private).toBe(false);
    expect(p.joinable).toBe(true);
    expect(p.modded).toBe(false);
    expect(p.sameMods).toBe(true);
    expect(p.mode).toBe('attrition');
    expect(p.ping).toBe(87);
    expect(v.private).toBe(true);
    expect(v.modded).toBe(true);
    expect(v.sameMods).toBe(false);
    expect((v.mods as Msg[]).map((m) => m.id)).toEqual(['Amulet', 'Cryptid']);
    expect(JSON.stringify(list)).not.toContain('"' + String(vc.code) + '"');
    pub.close(); priv.close(); viewer.close();
  });

  it('a public room is joined by id, a private one needs its code', async () => {
    const [pub, pc] = await hostRoom({ visibility: 'public' });
    const g1 = await connect();
    g1.send({ type: 'join_room', id: pc.id });
    const ready = await g1.waitFor((m) => m.type === 'room_ready');
    expect(ready.code).toBe(pc.code);
    expect(ready.host).toBe(false);

    const [priv, vc] = await hostRoom({ visibility: 'private' });
    const g2 = await connect();
    g2.send({ type: 'join_room', id: vc.id });
    expect((await g2.waitFor((m) => m.type === 'room_error')).reason).toBe('code_required');
    g2.send({ type: 'join_room', id: vc.id, code: 'ZZZZ' });
    await g2.waitFor(() => g2.msgs.filter((m) => m.type === 'room_error').length >= 2);
    expect(g2.msgs.filter((m) => m.type === 'room_error')[1].reason).toBe('invalid_code');
    g2.send({ type: 'join_room', id: vc.id, code: String(vc.code).toLowerCase() });
    expect((await g2.waitFor((m) => m.type === 'room_ready')).code).toBe(vc.code);
    pub.close(); g1.close(); priv.close(); g2.close();
  });

  it('full and in-match rooms are listed but not joinable', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    const hs = await sessionOf(host);
    const id = rooms[hs.code].id;
    const viewer = await connect();
    const e = (await listFor(viewer)).find((r) => r.id === id)!;
    expect(e.players).toBe(2);
    expect(e.inMatch).toBe(true);
    expect(e.joinable).toBe(false);
    viewer.send({ type: 'join_room', id });
    expect((await viewer.waitFor((m) => m.type === 'room_error')).reason).toBe('in_match');

    const [h2, c2] = await hostRoom({ visibility: 'public' });
    const g2 = await connect();
    g2.send({ type: 'join_room', id: c2.id });
    await g2.waitFor((m) => m.type === 'room_ready');
    const f = (await listFor(viewer)).find((r) => r.id === c2.id)!;
    expect(f.full).toBe(true);
    expect(f.joinable).toBe(false);
    const g3 = await connect();
    g3.send({ type: 'join_room', code: c2.code });
    expect((await g3.waitFor((m) => m.type === 'room_error')).reason).toBe('room_full');
    host.close(); guest.close(); viewer.close(); h2.close(); g2.close(); g3.close();
  });

  it('the guest gets the host settings and name when joining', async () => {
    const [host, created] = await hostRoom({ visibility: 'public', name: 'Gab' });
    host.send({ type: 'match_settings', settings: { mode: 'attrition', starting_lives: 2 } });
    await sleep(30);
    const g = await connect();
    g.send({ type: 'join_room', id: created.id });
    const ready = await g.waitFor((m) => m.type === 'room_ready');
    expect((ready.settings as Msg).starting_lives).toBe(2);
    expect(ready.hostName).toBe('Gab');
    host.close(); g.close();
  });

  it('a guest leaving the lobby keeps the room full, holds the seat and lets only them back', async () => {
    const [host, created] = await hostRoom({ visibility: 'public' });
    const g1 = await connect();
    g1.send({ type: 'join_room', id: created.id });
    const r1 = await g1.waitFor((m) => m.type === 'room_ready');
    expect(r1.id).toBe(created.id);
    g1.send({ type: 'leave_lobby' });
    const left = await host.waitFor((m) => m.type === 'guest_left');
    expect(left.held).toBe(true);
    const g2 = await connect();
    const list = await listFor(g2);
    const entry = list.find((r) => r.id === created.id)!;
    expect(entry.full).toBe(true);
    expect(entry.joinable).toBe(false);
    expect(entry.players).toBe(2);
    expect(entry.seatHeld).toBe(true);
    g2.send({ type: 'join_room', id: created.id });
    const err = await g2.waitFor((m) => m.type === 'room_error');
    expect(err.reason).toBe('room_full');
    g2.send({ type: 'join_room', id: created.id, token: '0'.repeat(32) });
    await waitCount(g2, 'room_error', 2);
    const back = await connect();
    back.send({ type: 'join_room', id: created.id, token: r1.token });
    const r2 = await back.waitFor((m) => m.type === 'room_ready');
    expect(r2.playerId).toBe(1);
    expect(r2.token).toBe(r1.token);
    expect(r2.rejoined).toBe(true);
    const hostReady = await waitCount(host, 'room_ready', 2);
    expect(hostReady.host).toBe(true);
    expect(rooms[created.code as string].holdDeadline[1]).toBeNull();
    const after = (await listFor(g2)).find((r) => r.id === created.id)!;
    expect(after.full).toBe(true);
    expect(after.seatHeld).toBe(false);
    host.close(); g1.close(); g2.close(); back.close();
  });

  it('a held lobby seat closes the room when the guest does not come back in time', async () => {
    setTimings({ rejoinHoldMs: 60 });
    try {
      const [host, created] = await hostRoom({ visibility: 'private' });
      const g = await connect();
      g.send({ type: 'join_room', code: created.code });
      await g.waitFor((m) => m.type === 'room_ready');
      g.close();
      await host.waitFor((m) => m.type === 'guest_left');
      const closed = await host.waitFor((m) => m.type === 'room_closed');
      expect(closed.reason).toBe('opponent_timed_out');
      expect(rooms[created.code as string]).toBeUndefined();
      host.close();
    } finally {
      setTimings({ rejoinHoldMs: 15 * 60 * 1000 });
    }
  });

  it('the room owner stays host after a public room match, whoever won', async () => {
    const [host, created] = await hostRoom({ visibility: 'public', name: 'OwnerOne' });
    const g = await connect();
    g.send({ type: 'join_room', id: created.id, name: 'GuestOne' });
    await g.waitFor((m) => m.type === 'room_ready');
    host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'nemesis', starting_lives: 1, pvp_start_round: 2 } });
    await g.waitFor((m) => m.type === 'match_state_update' && m.event === 'match_started');
    await pvpRound(host, g, 2, 100, 900, 1);
    await host.waitFor((m) => m.type === 'match_ended');
    host.send({ type: 'return_to_lobby' });
    const hb = await host.waitFor((m) => m.type === 'lobby_returned');
    const gb = await g.waitFor((m) => m.type === 'lobby_returned');
    expect(hb.host).toBe(true);
    expect(gb.host).toBe(false);
    const viewer = await connect();
    const list = await listFor(viewer);
    expect(list.find((r) => r.id === created.id)!.name).toBe('OwnerOne');
    host.close(); g.close(); viewer.close();
  });
});

describe('mod sets', () => {
  it('a vanilla player cannot join a modded room and sees the host mods', async () => {
    const [host, created] = await hostRoom({ visibility: 'private', mods: MODS_A });
    expect(created.modded).toBe(true);
    const g = await connect();
    g.send({ type: 'join_room', code: created.code });
    const err = await g.waitFor((m) => m.type === 'room_error');
    expect(err.reason).toBe('mods_mismatch');
    expect(err.hostModded).toBe(true);
    expect((err.hostMods as Msg[]).map(modKey)).toEqual(['Amulet@3.6.1', 'Cryptid@0.5.17c']);
    expect(rooms[created.code as string].sockets.length).toBe(1);
    host.close(); g.close();
  });

  it('a modded player cannot join a vanilla room', async () => {
    const [host, created] = await hostRoom({ visibility: 'public' });
    const g = await connect();
    g.send({ type: 'join_room', id: created.id, mods: MODS_A });
    const err = await g.waitFor((m) => m.type === 'room_error');
    expect(err.reason).toBe('mods_mismatch');
    expect(err.hostModded).toBe(false);
    host.close(); g.close();
  });

  it('different mod versions are refused, the exact same set joins', async () => {
    const [host, created] = await hostRoom({ visibility: 'public', mods: MODS_A });
    const g = await connect();
    g.send({ type: 'join_room', id: created.id, mods: MODS_B });
    expect((await g.waitFor((m) => m.type === 'room_error')).reason).toBe('mods_mismatch');
    g.send({ type: 'join_room', id: created.id, mods: [...MODS_A].reverse() });
    expect((await g.waitFor((m) => m.type === 'room_ready')).host).toBe(false);
    host.close(); g.close();
  });

  it('quick match only pairs players with the same mods', async () => {
    const a = await connect();
    const b = await connect();
    const c = await connect();
    a.send({ type: 'find_match', mods: MODS_A });
    await a.waitFor((m) => m.type === 'searching');
    b.send({ type: 'find_match' });
    await b.waitFor((m) => m.type === 'searching');
    c.send({ type: 'find_match', mods: MODS_A });
    const rc = await c.waitFor((m) => m.type === 'room_ready');
    const ra = await a.waitFor((m) => m.type === 'room_ready');
    expect(ra.code).toBe(rc.code);
    expect(b.msgs.some((m) => m.type === 'room_ready')).toBe(false);
    a.close(); b.close(); c.close();
  });
});

describe('leave chain reasons', () => {
  it('left to menu, then the other stopped waiting: each gets the true story', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis' });
    const gs = await sessionOf(guest);
    guest.send({ type: 'return_to_menu' });
    await host.waitFor((m) => m.type === 'opponent_disconnected');
    host.send({ type: 'leave_match' });
    const end = await host.waitFor((m) => m.type === 'match_ended');
    expect(end.result).toBe('win');
    expect(end.reason).toBe('stopped_waiting_opponent_left');
    guest.send({ type: 'check_rejoin', code: gs.code, token: gs.token });
    const st = await guest.waitFor((m) => m.type === 'rejoin_status');
    expect(st.reason).toBe('left_opponent_stopped_waiting');
    expect(st.result).toBe('lose');
    host.close(); guest.close();
  });
});

describe('game version', () => {
  it('validates the version field', () => {
    expect(validateMessage({ type: 'create_room', version: '2.0' }, 50)).toBeNull();
    expect(validateMessage({ type: 'join_room', code: 'ABCD', version: '' }, 50)).toContain('invalid version');
    expect(validateMessage({ type: 'list_rooms', version: 'x'.repeat(33) }, 80)).toContain('invalid version');
  });

  it('joining a room with another version is refused with both versions', async () => {
    const [host, created] = await hostRoom({ visibility: 'private', version: '2.1' });
    expect(created.version).toBe('2.1');
    const g = await connect();
    g.send({ type: 'join_room', code: created.code, version: '2.0' });
    const err = await g.waitFor((m) => m.type === 'room_error');
    expect(err.reason).toBe('version_mismatch');
    expect(err.hostVersion).toBe('2.1');
    expect(err.yourVersion).toBe('2.0');
    expect(rooms[created.code as string].sockets.length).toBe(1);
    g.send({ type: 'join_room', code: created.code, version: '2.1' });
    const ok = await g.waitFor((m) => m.type === 'room_ready');
    expect(ok.version).toBe('2.1');
    host.close(); g.close();
  });

  it('browse rows carry the version and are not joinable when it differs', async () => {
    const [host, created] = await hostRoom({ visibility: 'public', version: '2.1' });
    const viewer = await connect();
    viewer.send({ type: 'list_rooms', version: '2.0' });
    await viewer.waitFor((m) => m.type === 'room_list');
    const row = (viewer.msgs.find((m) => m.type === 'room_list')!.rooms as Msg[]).find((r) => r.id === created.id)!;
    expect(row.version).toBe('2.1');
    expect(row.sameVersion).toBe(false);
    expect(row.joinable).toBe(false);
    const same = await connect();
    same.send({ type: 'list_rooms', version: '2.1' });
    await same.waitFor((m) => m.type === 'room_list');
    const row2 = (same.msgs.find((m) => m.type === 'room_list')!.rooms as Msg[]).find((r) => r.id === created.id)!;
    expect(row2.sameVersion).toBe(true);
    expect(row2.joinable).toBe(true);
    host.close(); viewer.close(); same.close();
  });

  it('quick match only pairs the same version', async () => {
    const a = await connect();
    const b = await connect();
    a.send({ type: 'find_match', version: '9.1' });
    await a.waitFor((m) => m.type === 'searching');
    b.send({ type: 'find_match', version: '9.2' });
    await b.waitFor((m) => m.type === 'searching');
    const c = await connect();
    c.send({ type: 'find_match', version: '9.1' });
    const ready = await c.waitFor((m) => m.type === 'room_ready');
    expect(ready.host).toBe(false);
    a.send({ type: 'leave_lobby' }); b.send({ type: 'cancel_search' });
    a.close(); b.close(); c.close();
  });
});

describe('player names', () => {
  it('cleans names and spots default ones', () => {
    expect(cleanName('  Gab   Q ')).toBe('Gab Q');
    for (const n of ['', 'P1', 'p2', 'Player', 'Player 1', 'player2', 'M1', 'M3', 'Opponent', 'You']) expect(isDefaultName(n)).toBe(true);
    for (const n of ['Gabriel', 'Mods', 'Pablo', 'M1ke', 'Player One']) expect(isDefaultName(n)).toBe(false);
  });

  it('default names are refused when creating or joining', async () => {
    const a = await connect();
    a.send({ type: 'create_room', name: 'P1' });
    const r1 = await a.waitFor((m) => m.type === 'name_refused');
    expect(r1.reason).toBe('default');
    expect(r1.for).toBe('create_room');
    a.send({ type: 'create_room', name: '' });
    await waitCount(a, 'name_refused', 2);
    expect(a.msgs.some((m) => m.type === 'room_created')).toBe(false);
    const [host, created] = await hostRoom({ name: 'RealHost' });
    a.send({ type: 'join_room', code: created.code, name: 'M2' });
    const r3 = await waitCount(a, 'name_refused', 3);
    expect(r3.for).toBe('join_room');
    expect(rooms[created.code as string].sockets.length).toBe(1);
    a.close(); host.close();
  });

  it('a match_start name that is too long, not a string or has control characters never replaces the lobby name', async () => {
    const bads: unknown[] = ['W'.repeat(60), 'Bad\u0001\u0007', 12345, { name: 'x' }];
    for (let i = 0; i < bads.length; i++) {
      const [host, created] = await hostRoom({ name: `LobbyHost${i}` });
      const guest = await connect();
      guest.send({ type: 'join_room', code: created.code, name: `LobbyGuest${i}` });
      await guest.waitFor((m) => m.type === 'room_ready');
      await host.waitFor((m) => m.type === 'room_ready');
      host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'nemesis' }, player_name: bads[i] });
      await guest.waitFor((m) => m.type === 'match_state_update' && m.event === 'match_started');
      const name = String(rooms[created.code as string].match!.players[0].name);
      expect([`LobbyHost${i}`, 'Bad']).toContain(name);
      expect(name).not.toMatch(/[\x00-\x1f]/);
      host.close(); guest.close();
    }
  });

  it('a name used by another online player is refused until they leave', async () => {
    const [host, created] = await hostRoom({ name: 'Twin' });
    const other = await connect();
    other.send({ type: 'create_room', name: 'twin' });
    const r = await other.waitFor((m) => m.type === 'name_refused');
    expect(r.reason).toBe('taken');
    other.send({ type: 'join_room', code: created.code, name: 'Twin' });
    await waitCount(other, 'name_refused', 2);
    other.send({ type: 'join_room', code: created.code, name: 'Other Twin' });
    await other.waitFor((m) => m.type === 'room_ready');
    other.send({ type: 'player_name', name: 'Twin' });
    await waitCount(other, 'name_refused', 3);
    expect(rooms[created.code as string].playerNames[1]).toBe('Other Twin');
    host.close();
    await sleep(50);
    const later = await connect();
    later.send({ type: 'create_room', name: 'Twin' });
    await later.waitFor((m) => m.type === 'room_created');
    other.close(); later.close();
  });

  it('a seat held mid-match keeps its name; a seat held in the lobby does not', async () => {
    const [host, created] = await hostRoom({ name: 'HoldHost' });
    const g = await connect();
    g.send({ type: 'join_room', code: created.code, name: 'HeldGuest' });
    const r1 = await g.waitFor((m) => m.type === 'room_ready');
    g.close();
    await host.waitFor((m) => m.type === 'guest_left');
    const other = await connect();
    other.send({ type: 'create_room', name: 'HeldGuest' });
    await other.waitFor((m) => m.type === 'room_created');
    other.close();
    await sleep(30);
    const back = await connect();
    back.send({ type: 'join_room', code: created.code, token: r1.token, name: 'HeldGuest' });
    await back.waitFor((m) => m.type === 'room_ready');
    host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'nemesis', starting_lives: 2 } });
    await back.waitFor((m) => m.type === 'match_state_update' && m.event === 'match_started');
    back.close();
    await host.waitFor((m) => m.type === 'opponent_disconnected');
    const thief = await connect();
    thief.send({ type: 'create_room', name: 'heldguest' });
    const r = await thief.waitFor((m) => m.type === 'name_refused');
    expect(r.reason).toBe('taken');
    host.close(); thief.close();
  });

  it('the same player key gets its own held name back for the next match', async () => {
    const key = 'AbCdEfGhIjKlMnOpQrStUvWx';
    const [host, created] = await hostRoom({ name: 'KeyHost' });
    const g = await connect();
    g.send({ type: 'join_room', code: created.code, name: 'KeyGuest', pkey: key });
    await g.waitFor((m) => m.type === 'room_ready');
    host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'nemesis', starting_lives: 2 } });
    await g.waitFor((m) => m.type === 'match_state_update' && m.event === 'match_started');
    g.close();
    await host.waitFor((m) => m.type === 'opponent_disconnected');
    const stranger = await connect();
    stranger.send({ type: 'create_room', name: 'KeyGuest', pkey: 'ZZZZZZZZZZZZZZZZZZZZZZZZ' });
    expect((await stranger.waitFor((m) => m.type === 'name_refused')).reason).toBe('taken');
    const me = await connect();
    me.send({ type: 'create_room', name: 'KeyGuest', pkey: key });
    await me.waitFor((m) => m.type === 'room_created');
    host.close(); stranger.close(); me.close();
  });
});

describe('lobby settings validation', () => {
  it('clamps numbers, drops wrong types and keeps valid values', () => {
    const s = sanitizeSettings({
      mode: 'faceoff', starting_lives: 3, pvp_win_money: 99, life_steal: 'yes', timer: true,
      timer_base_seconds: -5, timer_forgiveness: 2.6, pvp_start_round: 0, stake: 'x', win_ante: 0,
      custom_seed: 'ABCDEFGH', deck: 'D'.repeat(41), the_order: true,
    })!;
    expect(s.mode).toBe('faceoff');
    expect(s.starting_lives).toBe(3);
    expect(s.pvp_win_money).toBe(10);
    expect(s.life_steal).toBeUndefined();
    expect(s.timer).toBe(true);
    expect(s.timer_base_seconds).toBe(0.2);
    expect(s.timer_forgiveness).toBe(3);
    expect(s.pvp_start_round).toBe(1);
    expect(s.stake).toBeUndefined();
    expect(s.win_ante).toBeUndefined();
    expect(s.custom_seed).toBe('ABCDEFGH');
    expect(s.deck).toBeUndefined();
    expect(s.the_order).toBe(true);
    expect(sanitizeSettings({ win_ante: false })!.win_ante).toBe(false);
    expect(sanitizeSettings([])).toBeNull();
  });

  it('keeps the fair play switches only as booleans', () => {
    const s = sanitizeSettings({ allow_fast_speed: true, allow_score_speed: 'yes', allow_skip_score: 1, show_seed: false })!;
    expect(s.allow_fast_speed).toBe(true);
    expect(s.allow_score_speed).toBeUndefined();
    expect(s.allow_skip_score).toBeUndefined();
    expect(s.show_seed).toBe(false);
  });

  it('keeps plain run rules and drops bad keys and values', () => {
    const r = cleanRules({
      hands: 6, inflation: true, enhancement: 'random', starting_jokers: ['j_joker', 'j_greedy_joker'],
      'Bad Key': 1, nested: { a: 1 }, ban_jokers: [1, 2], huge: 1e9, long: 'x'.repeat(65),
    });
    expect(r).toEqual({ hands: 6, inflation: true, enhancement: 'random', starting_jokers: ['j_joker', 'j_greedy_joker'] });
    expect(cleanRules('nope')).toEqual({});
    const many: Record<string, number> = {};
    for (let i = 0; i < 200; i++) many['k' + i] = i;
    expect(Object.keys(cleanRules(many)).length).toBe(120);
  });

  it('keeps a short mp_stake and drops a long or non-string one', async () => {
    const host = await connect();
    const guest = await connect();
    host.send({ type: 'create_room' });
    const created = await host.waitFor((m) => m.type === 'room_created');
    guest.send({ type: 'join_room', code: created.code });
    await host.waitFor((m) => m.type === 'room_ready');
    host.send({ type: 'match_settings', settings: { mp_stake: 'planet' } });
    const a = await guest.waitFor((m) => m.type === 'match_settings');
    expect((a.settings as Record<string, unknown>).mp_stake).toBe('planet');
    host.send({ type: 'match_settings', settings: { mp_stake: 'x'.repeat(33) } });
    const b = await guest.waitFor((m) => m.type === 'match_settings' && (m.settings as Record<string, unknown>).mp_stake === undefined);
    expect((b.settings as Record<string, unknown>).mp_stake).toBeUndefined();
    host.send({ type: 'match_settings', settings: { mp_stake: 7 } });
    const c = await guest.waitFor((m) => m.type === 'match_settings' && (m.settings as Record<string, unknown>).mp_stake === undefined);
    expect((c.settings as Record<string, unknown>).mp_stake).toBeUndefined();
    host.close(); guest.close();
  });

  it('forwards the sanitized settings to the guest and stores them', async () => {
    const host = await connect();
    const guest = await connect();
    host.send({ type: 'create_room' });
    const created = await host.waitFor((m) => m.type === 'room_created');
    guest.send({ type: 'join_room', code: created.code });
    await host.waitFor((m) => m.type === 'room_ready');
    host.send({ type: 'match_settings', settings: { pvp_win_money: 40, life_steal: true, rules: { hands: 6, bad: { x: 1 } } } });
    const got = await guest.waitFor((m) => m.type === 'match_settings');
    const gs = got.settings as Record<string, unknown>;
    expect(gs.pvp_win_money).toBe(10);
    expect(gs.life_steal).toBe(true);
    expect(gs.rules).toEqual({ hands: 6 });
    const room = rooms[created.code as string];
    expect(room.settings.rules).toEqual({ hands: 6 });
    host.close(); guest.close();
  });

  it('life steal gives the PvP winner a lost life back, up to the starting lives', async () => {
    const [host, guest] = await startMatch({ mode: 'nemesis', starting_lives: 3, pvp_start_round: 2, life_steal: true });
    guest.send({ type: 'game_over', ante: 1, blind: 'S', score: 10 });
    const lost = await guest.waitFor((m) => m.type === 'match_state_update' && m.event === 'life_lost');
    expect(lost.myLives).toBe(2);
    await enterPvpBlind(host, guest);
    host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    guest.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    host.send({ type: 'play_hand', score: '100', hands_left: 0 });
    guest.send({ type: 'play_hand', score: '500', hands_left: 0 });
    const res = await guest.waitFor((m) => m.type === 'pvp_resolved');
    expect(res.result).toBe('win');
    expect(res.myLives).toBe(3);
    expect(res.oppLives).toBe(2);
    host.close(); guest.close();
  });

  it('without life steal the winner keeps the same lives', async () => {
    const m = createMatchState({ starting_lives: 3 });
    expect(m.lifeSteal).toBe(false);
    expect(createMatchState({ life_steal: true }).lifeSteal).toBe(true);
  });
});

describe('one join and one list for rooms and parties', () => {
  it('join_room with a party code or id joins the party, list has lives and ante', async () => {
    const host = await connect();
    host.send({ type: 'party_create', kind: 'teams', visibility: 'public', name: 'PartyHostX' });
    const made = await host.waitFor((m) => m.type === 'party_joined');
    const g1 = await connect();
    g1.send({ type: 'join_room', code: String(made.code).toLowerCase(), name: 'PartyGuestA' });
    expect((await g1.waitFor((m) => m.type === 'party_joined' || m.type === 'room_error')).type).toBe('party_joined');
    const g2 = await connect();
    g2.send({ type: 'join_room', id: made.id, name: 'PartyGuestB' });
    expect((await g2.waitFor((m) => m.type === 'party_joined' || m.type === 'room_error')).playerId).toBe(2);
    const viewer = await connect();
    const e = (await listFor(viewer)).find((r) => r.id === made.id);
    expect(e).toMatchObject({ party: true, players: 3, mode: 'party_teams', lives: 4, ante: null });
    const bad = await connect();
    bad.send({ type: 'join_room', code: 'ZZZZ', name: 'PartyGuestC' });
    expect((await bad.waitFor((m) => m.type === 'room_error')).reason).toBe('invalid_code');
    const [rh, created] = await hostRoom({ visibility: 'public', name: 'RoomHostY' });
    const r = (await listFor(viewer)).find((x) => x.id === created.id);
    expect(r).toMatchObject({ lives: 4, ante: null });
    for (const c of [host, g1, g2, viewer, bad, rh]) c.close();
  });
});

describe('ranked over the socket', () => {
  it('ranked messages from a party seat are answered, not swallowed by the party handler', async () => {
    const pk = 'P'.repeat(23) + 'q';
    const host = await connect();
    host.send({ type: 'party_create', kind: 'br', visibility: 'private', name: 'RankPartyHost', pkey: pk });
    await host.waitFor((m) => m.type === 'party_joined');
    host.send({ type: 'ranked_profile', pkey: pk, name: 'RankPartyHost' });
    const prof = await host.waitFor((m) => m.type === 'ranked_profile');
    expect((prof.profile as Msg).rp).toBe(0);
    host.send({ type: 'ranked_badges', names: ['RankPartyHost'] });
    const b = await host.waitFor((m) => m.type === 'ranked_badges');
    expect(Object.keys(b.badges as Msg)).toEqual(['RankPartyHost']);
    host.close();
  });

  it('a finished casual 1v1 leaves RP alone and sends no ranked_result', async () => {
    const { ranked } = await import('./ranked');
    const hk = 'H'.repeat(23) + 'r', gk = 'G'.repeat(23) + 'r';
    const host = await connect();
    const guest = await connect();
    host.send({ type: 'create_room', name: 'RankHost', pkey: hk });
    const created = await host.waitFor((m) => m.type === 'room_created');
    guest.send({ type: 'join_room', code: created.code, name: 'RankGuest', pkey: gk });
    await guest.waitFor((m) => m.type === 'room_ready');
    await host.waitFor((m) => m.type === 'room_ready');
    host.send({ type: 'match_start', seed: 'TEST', settings: { mode: 'nemesis', starting_lives: 1, pvp_start_round: 2, win_ante: 2 }, player_name: 'RankHost' });
    await host.waitFor((m) => m.type === 'match_state_update' && m.event === 'match_started');
    await guest.waitFor((m) => m.type === 'match_state_update' && m.event === 'match_started');
    await pvpRound(host, guest, 2, 900, 100, 1);
    await host.waitFor((m) => m.type === 'match_ended');
    await guest.waitFor((m) => m.type === 'match_ended');
    expect(host.msgs.some((m) => m.type === 'ranked_result')).toBe(false);
    expect(guest.msgs.some((m) => m.type === 'ranked_result')).toBe(false);
    expect(ranked.cached(hk)?.row.rp ?? 0).toBe(0);
    guest.send({ type: 'ranked_profile', pkey: gk });
    const prof = await guest.waitFor((m) => m.type === 'ranked_profile');
    expect((prof.profile as Msg).matches).toBe(0);
    host.send({ type: 'ranked_recovery', pkey: hk });
    const rec = await host.waitFor((m) => m.type === 'ranked_recovery');
    guest.send({ type: 'ranked_restore', code: rec.code });
    const res = await guest.waitFor((m) => m.type === 'ranked_restored');
    expect(res.pkey).toBe(hk);
    host.close(); guest.close();
  });
});
