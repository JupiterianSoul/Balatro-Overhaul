import { describe, it, expect, afterAll } from 'bun:test';
import { startServer, sanitizeSettings } from './index';
import { rollDeck, cleanDeckPool, RANDOM_DECK } from './deck_roll';
import { rankedSettings } from './rulesets_server';

type Msg = Record<string, unknown>;
const srv = startServer(0);
afterAll(() => srv.stop(true));

interface C { send: (m: Msg) => void; wait: (t: string, ms?: number) => Promise<Msg>; close: () => void; }

let uid = 0;
const nm = () => `Deck${++uid}x${Math.floor(Math.random() * 1e6)}`;

function decode(raw: string): Msg {
  const parsed = JSON.parse(raw) as Msg;
  if (parsed.z === 1 && typeof parsed.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(parsed.d, 'base64'))).toString('utf8')) as Msg;
  return parsed;
}

async function connect(): Promise<C> {
  const ws = new WebSocket(`ws://127.0.0.1:${srv.port}/ws`);
  const msgs: Msg[] = [];
  const waiters: { t: string; resolve: (m: Msg) => void }[] = [];
  ws.onmessage = (ev) => {
    const m = decode(String(ev.data));
    const i = waiters.findIndex((w) => w.t === m.type);
    if (i >= 0) { waiters[i].resolve(m); waiters.splice(i, 1); } else msgs.push(m);
  };
  await new Promise<void>((res, rej) => { ws.onopen = () => res(); ws.onerror = () => rej(new Error('ws')); });
  return {
    send: (m) => ws.send(JSON.stringify(m)),
    wait: (t, ms = 2000) => {
      const i = msgs.findIndex((m) => m.type === t);
      if (i >= 0) return Promise.resolve(msgs.splice(i, 1)[0]);
      return new Promise<Msg>((res, rej) => {
        const to = setTimeout(() => rej(new Error('timeout ' + t)), ms);
        waiters.push({ t, resolve: (m) => { clearTimeout(to); res(m); } });
      });
    },
    close: () => ws.close(),
  };
}

const POOL = ['Red Deck', 'Blue Deck', 'Yellow Deck', 'Green Deck', 'Black Deck', 'Seer Deck'];

describe('random deck pick', () => {
  it('rolls one deck from the pool only when the deck is Random pick', () => {
    const s: Msg = { deck: RANDOM_DECK, deck_pool: POOL };
    expect(rollDeck(s, () => 0)).toBe('Red Deck');
    expect(rollDeck(s, () => 0.999)).toBe('Seer Deck');
    expect(s.rolled_deck).toBe('Seer Deck');
    const fixed: Msg = { deck: 'Blue Deck', deck_pool: POOL, rolled_deck: 'Red Deck' };
    expect(rollDeck(fixed)).toBeNull();
    expect(fixed.rolled_deck).toBeUndefined();
    expect(rollDeck({ deck: RANDOM_DECK, deck_pool: [] })).toBeNull();
  });

  it('over many rolls every deck in the pool comes up', () => {
    const seen = new Set<string>();
    for (let i = 0; i < 400; i++) seen.add(rollDeck({ deck: RANDOM_DECK, deck_pool: POOL }) as string);
    expect([...seen].sort()).toEqual([...POOL].sort());
  });

  it('the pool drops junk, duplicates and the Random pick value itself', () => {
    expect(cleanDeckPool(['Red Deck', 'Red Deck', 7, '', 'x'.repeat(41), RANDOM_DECK, 'Blue Deck'])).toEqual(['Red Deck', 'Blue Deck']);
    expect(cleanDeckPool('Red Deck')).toBeUndefined();
    const s = sanitizeSettings({ deck: RANDOM_DECK, deck_pool: ['Red Deck', 3], rolled_deck: 'y'.repeat(50) })!;
    expect(s.deck_pool).toEqual(['Red Deck']);
    expect(s.rolled_deck).toBeUndefined();
    expect(sanitizeSettings({ deck_pool: 'nope' })!.deck_pool).toBeUndefined();
  });

  it('a rematch rolls a fresh deck on the server and both players get the same one', async () => {
    const host = await connect();
    const guest = await connect();
    host.send({ type: 'create_room', visibility: 'public', name: nm() });
    const created = await host.wait('room_created');
    guest.send({ type: 'join_room', code: created.code, name: nm() });
    await guest.wait('room_ready');
    host.send({ type: 'match_start', seed: 'DECK1', settings: { mode: 'nemesis', starting_lives: 1, deck: RANDOM_DECK, deck_pool: POOL, rolled_deck: 'Blue Deck' }, player_name: 'H' });
    const ms = await guest.wait('match_start');
    expect((ms.settings as Msg).rolled_deck).toBe('Blue Deck');
    guest.send({ type: 'game_over', ante: 1, blind: 'S', score: 10 });
    await host.wait('match_ended');
    host.send({ type: 'rematch_vote' });
    guest.send({ type: 'rematch_vote' });
    const a = (await host.wait('rematch_accepted')).settings as Msg;
    const b = (await guest.wait('rematch_accepted')).settings as Msg;
    expect(POOL).toContain(a.rolled_deck as string);
    expect(b.rolled_deck).toBe(a.rolled_deck);
    host.close(); guest.close();
  });
});

describe('random deck pick in a party', () => {
  it('the server rolls one deck at party start and every player gets it', async () => {
    const host = await connect();
    host.send({ type: 'party_create', name: nm(), kind: 'br' });
    const j = await host.wait('party_joined');
    host.send({ type: 'match_settings', settings: { party_kind: 'br', deck: RANDOM_DECK, deck_pool: POOL } });
    const cs = [host];
    for (let i = 0; i < 2; i++) {
      const c = await connect();
      c.send({ type: 'party_join', code: j.code, name: nm() });
      await c.wait('party_joined');
      cs.push(c);
    }
    for (const c of cs.slice(1)) c.send({ type: 'party_ready', ready: true });
    await Bun.sleep(60);
    host.send({ type: 'party_start' });
    const decks: unknown[] = [];
    for (const c of cs) decks.push(((await c.wait('match_start')).settings as Msg).rolled_deck);
    expect(POOL).toContain(decks[0] as string);
    expect(decks.every((d) => d === decks[0])).toBe(true);
    for (const c of cs) c.close();
  });

  it('a Random pick deck and a Random stake both roll once at party start', async () => {
    const host = await connect();
    host.send({ type: 'party_create', name: nm(), kind: 'br' });
    const j = await host.wait('party_joined');
    host.send({ type: 'match_settings', settings: { party_kind: 'br', deck: RANDOM_DECK, deck_pool: POOL, stake: 'random' } });
    const cs = [host];
    for (let i = 0; i < 2; i++) {
      const c = await connect();
      c.send({ type: 'party_join', code: j.code, name: nm() });
      await c.wait('party_joined');
      cs.push(c);
    }
    for (const c of cs.slice(1)) c.send({ type: 'party_ready', ready: true });
    await Bun.sleep(60);
    host.send({ type: 'party_start' });
    const got: Msg[] = [];
    for (const c of cs) got.push((await c.wait('match_start')).settings as Msg);
    expect(POOL).toContain(got[0].rolled_deck as string);
    expect(got[0].stake).toBe('random');
    expect(got[0].rolled_stake).toBeGreaterThanOrEqual(1);
    for (const s of got) {
      expect(s.rolled_deck).toBe(got[0].rolled_deck);
      expect(s.rolled_stake).toBe(got[0].rolled_stake);
    }
    for (const c of cs) c.close();
  });
});

describe('joker picks', () => {
  it('joker_picks is a whole number from 0 to 5 and the old toggle is gone from ranked', () => {
    expect(sanitizeSettings({ joker_picks: 9 })!.joker_picks).toBe(5);
    expect(sanitizeSettings({ joker_picks: -2 })!.joker_picks).toBe(0);
    expect(sanitizeSettings({ joker_picks: 2.4 })!.joker_picks).toBe(2);
    expect(sanitizeSettings({ joker_picks: 'lots' })!.joker_picks).toBeUndefined();
    const r = rankedSettings() as Msg;
    expect(r.joker_picks).toBe(0);
    expect(r.per_player_jokers).toBeUndefined();
  });
});
