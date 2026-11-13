import { describe, it, expect, afterAll } from 'bun:test';
import { startServer, validateMessage, sanitizeSettings } from './index';
import { partyCfg, cleanPartySettings, raceCleared, raceOrder, raceWinner } from './party_rules';
import { draftPool, newDraft, draftAct, draftAuto, draftView, draftDecks, draftMyDeck, remaining, draftTiming, DRAFT_DECKS } from './draft';

type Msg = Record<string, unknown>;
const srv = startServer(0);
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
let uid = 0;
const nm = () => `Lten${++uid}x${Math.floor(Math.random() * 1e6)}`;

async function party(n: number, settings: Msg): Promise<C[]> {
  const host = await connect();
  host.send({ type: 'party_create', name: nm(), kind: settings.party_kind });
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
  return cs;
}

async function room(settings: Msg = {}): Promise<[C, C]> {
  const host = await connect();
  const guest = await connect();
  host.send({ type: 'create_room', name: nm() });
  const created = await host.wait('room_created');
  host.send({ type: 'match_settings', settings });
  guest.send({ type: 'join_room', code: created.code, name: nm() });
  await guest.wait('room_ready');
  await host.wait('room_ready');
  await sleep(30);
  return [host, guest];
}

describe('party kinds', () => {
  it('manhunt is gone: an old client asking for it gets Battle Royale', () => {
    const s: Msg = { party_kind: 'manhunt', race_target: 'x' };
    cleanPartySettings(s);
    expect(s).toEqual({});
    expect(partyCfg({ party_kind: 'manhunt' }).kind).toBe('br');
    expect(partyCfg({ party_kind: 'race', race_target: 6 }).raceTarget).toBe(6);
    expect(partyCfg({ party_kind: 'race' }).raceTarget).toBe(4);
  });
});

describe('race rules', () => {
  it('counts cleared blinds', () => {
    expect(raceCleared(1, 'S')).toBe(1);
    expect(raceCleared(1, 'L')).toBe(3);
    expect(raceCleared(4, 'B')).toBe(11);
  });
  it('the first to clear the target wins and time breaks ties', () => {
    expect(raceWinner(2, [{ pid: 0, cleared: 6, at: 900, alive: true }, { pid: 1, cleared: 6, at: 800, alive: true }])).toBe(1);
    expect(raceWinner(2, [{ pid: 0, cleared: 5, at: 1, alive: true }, { pid: 1, cleared: 4, at: 1, alive: true }])).toBeNull();
    expect(raceOrder([{ pid: 0, cleared: 3, at: 50, alive: true }, { pid: 1, cleared: 3, at: 40, alive: false }, { pid: 2, cleared: 4, at: 90, alive: true }])).toEqual([2, 1, 0]);
  });
  it('the last runner standing wins once past everyone who is out', () => {
    const out = { pid: 1, cleared: 5, at: 10, alive: false };
    expect(raceWinner(4, [{ pid: 0, cleared: 5, at: 20, alive: true }, out])).toBeNull();
    expect(raceWinner(4, [{ pid: 0, cleared: 6, at: 20, alive: true }, out])).toBe(0);
    expect(raceWinner(4, [{ pid: 0, cleared: 2, at: 20, alive: false }, out])).toBe(1);
  });
});

describe('deck draft', () => {
  it('the pool is the same for the same seed and comes from the deck list', () => {
    const a = draftPool('SEED1');
    expect(a).toEqual(draftPool('SEED1'));
    expect(a.length).toBe(7);
    expect(new Set(a).size).toBe(7);
    for (const d of a) expect(DRAFT_DECKS).toContain(d);
    expect(newDraft('SEED1').pool.length).toBe(5);
  });
  it('bans go in turn and the last deck left is the deck of both players', () => {
    const d = newDraft('S2');
    expect(d.phase).toBe('ban');
    const first = d.turn as number;
    const second = first === 0 ? 1 : 0;
    expect(draftAct(d, second, 'ban', d.pool[0])).toBe('not_your_turn');
    expect(draftAct(d, first, 'pick', d.pool[0])).toBe('wrong_phase');
    expect(draftAct(d, first, 'ban', 'Nope Deck')).toBe('not_in_pool');
    expect(draftAct(d, 5, 'ban', d.pool[0])).toBe('not_in_draft');
    expect(draftAct(d, first, 'ban', d.pool[0])).toBeNull();
    expect(draftAct(d, second, 'ban', d.pool[0])).toBe('not_in_pool');
    expect(draftAct(d, second, 'ban', d.pool[1])).toBeNull();
    expect(draftAct(d, first, 'ban', d.pool[2])).toBeNull();
    expect(d.phase).toBe('ban');
    expect(draftAct(d, second, 'ban', d.pool[3])).toBeNull();
    expect(d.phase).toBe('done');
    expect(d.deck).toBe(d.pool[4]);
    expect(remaining(d)).toEqual([d.pool[4]]);
    expect(draftAct(d, first, 'ban', d.pool[4])).toBe('done');
    for (const pid of [0, 1]) {
      const v = draftView(d, pid);
      expect(v.deck).toBe(d.pool[4]);
      expect(v.picks).toEqual({ '0': d.pool[4], '1': d.pool[4] });
      expect(draftMyDeck({ draft: d }, pid)).toBe(d.pool[4]);
    }
    expect(draftDecks({ draft: d })).toEqual({ deck: d.pool[4], different_decks: false });
  });
  it('either player can get the first ban, depending on the seed', () => {
    const firsts = new Set(Array.from({ length: 40 }, (_, i) => newDraft('ORDER' + i).turn));
    expect([...firsts].sort()).toEqual([0, 1]);
  });
  it('a timeout bans at random and the draft still ends on one deck', () => {
    const d = newDraft('S3');
    const first = d.turn as number;
    for (let i = 0; i < 4; i++) expect(draftAuto(d, () => 0.5)).toEqual([i % 2 === 0 ? first : 1 - first]);
    expect(d.phase).toBe('done');
    expect(remaining(d)).toEqual([d.deck as string]);
    expect(draftAuto(d, () => 0)).toEqual([]);
    expect(d.random[0]).toBe(2);
    expect(d.random[1]).toBe(2);
    expect(draftDecks({ draft: d }).different_decks).toBe(false);
  });
  it('only the player on turn can be auto banned for', () => {
    const d = newDraft('S4');
    const other = d.turn === 0 ? 1 : 0;
    expect(draftAuto(d, () => 0, other)).toEqual([]);
    expect(d.bans.length).toBe(0);
  });
  it('validates draft messages and the new settings', () => {
    expect(validateMessage({ type: 'draft_action', action: 'ban', deck: 'Red Deck' }, 60)).toBeNull();
    expect(validateMessage({ type: 'draft_action', action: 'ban', deck: 5 }, 60)).not.toBeNull();
    expect(validateMessage({ type: 'draft_start' }, 20)).toBeNull();
    const s = sanitizeSettings({ mode: 'race', race_target: 40, deck_draft: true, traps: 'yes' })!;
    expect(s.mode).toBe('race');
    expect(s.race_target).toBe(12);
    expect(s.deck_draft).toBe(true);
    expect(s.traps).toBeUndefined();
  });
  it('runs a full draft between two players and both get the same deck at match start', async () => {
    const [host, guest] = await room({ deck_draft: true });
    host.send({ type: 'draft_start' });
    const st = await guest.wait('draft_state');
    const pool = st.pool as string[];
    expect(pool.length).toBe(5);
    const by = (pid: number) => (pid === 0 ? host : guest);
    let turn = st.turn as number;
    for (let i = 0; i < 4; i++) {
      by(turn).send({ type: 'draft_action', action: 'ban', deck: pool[i] });
      if (i < 3) {
        const next = await by(1 - turn).wait('draft_state', (m) => (m.bans as unknown[]).length === i + 1);
        expect(next.turn).toBe(1 - turn);
        turn = next.turn as number;
      }
    }
    const dh = await host.wait('draft_done');
    const dg = await guest.wait('draft_done');
    for (const d of [dh, dg]) {
      expect(d.deck).toBe(pool[4]);
      expect(d.my_deck).toBe(pool[4]);
      expect(d.decks).toEqual({ '0': pool[4], '1': pool[4] });
      expect(d.different_decks).toBe(false);
    }
    host.send({ type: 'match_start', seed: 'DRAFT', settings: { deck: 'Red Deck', different_decks: true, deck_draft: true }, player_name: 'H' });
    const ms = await guest.wait('match_start');
    expect(ms.myDeck).toBe(pool[4]);
    host.close(); guest.close();
  });
  it('a player who leaves during the bans stops the draft for the other player', async () => {
    const old = draftTiming.turnMs;
    draftTiming.turnMs = 60;
    const [host, guest] = await room({ deck_draft: true });
    host.send({ type: 'draft_start' });
    await host.wait('draft_state');
    guest.close();
    expect((await host.wait('draft_cancelled')).reason).toBeDefined();
    await sleep(400);
    expect(host.msgs.some(m => m.type === 'draft_state')).toBe(false);
    expect(host.msgs.some(m => m.type === 'draft_done')).toBe(false);
    draftTiming.turnMs = old;
    host.close();
  });
  it('refuses a draft when the room does not ask for one, and times out with a random pick', async () => {
    const [host, guest] = await room({});
    host.send({ type: 'draft_start' });
    expect((await host.wait('draft_error')).reason).toBe('off');
    host.close(); guest.close();
    const old = draftTiming.turnMs;
    draftTiming.turnMs = 40;
    const [h2, g2] = await room({ deck_draft: true });
    h2.send({ type: 'draft_start' });
    const done = await g2.wait('draft_done', () => true, 3000);
    const hd = await h2.wait('draft_done', () => true, 3000);
    expect(typeof done.deck).toBe('string');
    expect(hd.deck).toBe(done.deck);
    expect(done.my_deck).toBe(done.deck);
    expect(done.random).toBe(2);
    draftTiming.turnMs = old;
    h2.close(); g2.close();
  });
});

describe('1v1 race', () => {
  it('the first player to clear the target ante wins', async () => {
    const [host, guest] = await room({ mode: 'race', race_target: 1 });
    host.send({ type: 'match_start', seed: 'RACE', settings: { mode: 'race', race_target: 1 }, player_name: 'H' });
    await guest.wait('match_start');
    for (const b of ['S', 'B']) {
      for (const c of [host, guest]) c.send({ type: 'blind_entered', ante: 1, blind: b });
      await sleep(20);
      for (const c of [host, guest]) c.send({ type: 'blind_finished', ante: 1, blind: b, score: 100 });
      await sleep(20);
    }
    const st = await host.wait('race_state', (m) => ((m.players as Msg[])[0].cleared as number) === 2);
    expect(st.goal).toBe(3);
    guest.send({ type: 'blind_entered', ante: 1, blind: 'L' });
    await sleep(20);
    guest.send({ type: 'blind_finished', ante: 1, blind: 'L', score: 300 });
    const r = await host.wait('race_resolved');
    expect(r.result).toBe('lose');
    expect(r.winner).toBe(1);
    host.close(); guest.close();
  });
});

describe('party race', () => {
  it('party race has no PvP blind and ends when someone clears the target', async () => {
    const cs = await party(3, { party_kind: 'race', race_target: 1 });
    cs[0].send({ type: 'party_start' });
    for (const c of cs) expect(((await c.wait('match_start')).settings as Msg).mode).toBe('race');
    for (const b of ['S', 'B', 'L']) {
      cs[2].send({ type: 'blind_entered', ante: 1, blind: b });
      cs[2].send({ type: 'blind_finished', ante: 1, blind: b, score: 50 });
    }
    cs[0].send({ type: 'blind_entered', ante: 1, blind: 'S' });
    cs[0].send({ type: 'blind_finished', ante: 1, blind: 'S', score: 50 });
    const end = await cs[2].wait('match_ended');
    expect(end.result).toBe('win');
    expect(end.reason).toBe('race_won');
    const lose = await cs[0].wait('match_ended');
    expect(lose.result).toBe('lose');
    expect(cs[0].msgs.some(m => m.type === 'start_blind')).toBe(false);
    for (const c of cs) c.close();
  });
  it('relays a trap in a party to the target and the leader by default', async () => {
    const cs = await party(3, { party_kind: 'br' });
    cs[0].send({ type: 'party_start' });
    for (const c of cs) await c.wait('match_start');
    cs[0].send({ type: 'sabotage', sabotage_id: 'trap_set', key: 'c_mp_trap_fire', to: 2 });
    const got = await cs[2].wait('sabotage');
    expect(got.from).toBe(0);
    expect(got.key).toBe('c_mp_trap_fire');
    cs[1].send({ type: 'sabotage', sabotage_id: 'trap_set', key: 'c_mp_trap_toll' });
    const any = await Promise.race([cs[0].wait('sabotage'), cs[2].wait('sabotage')]);
    expect(any.from).toBe(1);
    cs[0].send({ type: 'sabotage', sabotage_id: 'hand_reduction', to: 1 });
    await sleep(80);
    expect(cs[1].msgs.some(m => m.type === 'sabotage')).toBe(false);
    for (const c of cs) c.close();
  });
});
