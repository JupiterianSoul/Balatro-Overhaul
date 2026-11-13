import { describe, it, expect } from 'bun:test';
import { startPick, pickAction, wantsPick, cancelPick, pickTiming, pickMyDeck, pickJokers, botPick, deckKey, SIM_DECKS, RANDOM_PICK, type PickRoom, type PickDeps } from './pick';
import { newDraft, draftAct, remaining, DRAFT_BANS_EACH } from './draft';

type Msg = Record<string, unknown>;

function setup(settings: Record<string, unknown>, bots: number[] = [], gone: number[] = []) {
  const sent: { pid: number; msg: Msg }[] = [];
  const room: PickRoom = { code: 'TEST', settings: { deck: 'Red Deck', ...settings } };
  const deps: PickDeps = {
    sendTo: (pid, msg) => { sent.push({ pid, msg }); },
    isBot: (pid) => bots.includes(pid),
    connected: (pid) => !gone.includes(pid),
    log: () => {},
  };
  const last = (pid: number, type: string) => [...sent].reverse().find(x => x.pid === pid && x.msg.type === type)?.msg;
  return { room, deps, sent, last };
}

const POOL = ['Red Deck', 'Blue Deck', 'Plasma Deck', RANDOM_PICK];

describe('pick phase at match launch', () => {
  it('runs only when a player choice is on, never in ranked', () => {
    expect(wantsPick({ code: 'a', settings: {} })).toBe(false);
    expect(wantsPick({ code: 'a', settings: { different_decks: true } })).toBe(true);
    expect(wantsPick({ code: 'a', settings: { joker_picks: 2 } })).toBe(true);
    expect(wantsPick({ code: 'a', settings: { different_decks: true, deck_draft: true } })).toBe(true);
    expect(wantsPick({ code: 'a', settings: { different_decks: true, deck_draft: true, joker_picks: 1 } })).toBe(true);
    expect(wantsPick({ code: 'a', ranked: true, settings: { joker_picks: 3 } })).toBe(false);
  });

  it('every player picks a deck and jokers, the result goes to everyone', () => {
    const t = setup({ different_decks: true, joker_picks: 2 });
    const p = startPick(t.room, t.deps, [0, 1], POOL);
    expect(t.last(0, 'pick_state')?.deck).toBe(true);
    expect(t.last(1, 'pick_state')?.jokers).toBe(2);
    expect(p.decks[0]).toBe('Red Deck');
    expect(pickAction(t.room, 0, { deck: 'Plasma Deck', jokers: ['j_joker', 'j_egg'], ready: true }, t.deps)).toBeNull();
    expect(p.done).toBe(false);
    expect(pickAction(t.room, 1, { deck: RANDOM_PICK, jokers: ['j_greedy_joker'], ready: true }, t.deps)).toBeNull();
    expect(p.done).toBe(true);
    const r0 = t.last(0, 'pick_done')!;
    const r1 = t.last(1, 'pick_done')!;
    expect(r0).toEqual(r1);
    expect((r0.decks as Record<string, string>)['0']).toBe('Plasma Deck');
    expect(['Red Deck', 'Blue Deck', 'Plasma Deck']).toContain((r0.decks as Record<string, string>)['1']);
    expect(r0.rolled).toEqual({ '0': false, '1': true });
    expect(r0.jokers).toEqual({ '0': ['j_joker', 'j_egg'], '1': ['j_greedy_joker'] });
    expect(pickMyDeck(t.room, 1)).toBe((r0.decks as Record<string, string>)['1']);
    cancelPick(t.room);
  });

  it('refuses decks outside the pool, too many jokers, duplicates and junk keys', () => {
    const t = setup({ different_decks: true, joker_picks: 1 });
    const p = startPick(t.room, t.deps, [0, 1], POOL);
    expect(pickAction(t.room, 0, { deck: 'Cheat Deck' }, t.deps)).toBe('bad_deck');
    expect(pickAction(t.room, 0, { jokers: ['j_joker', 'j_egg'] }, t.deps)).toBe('too_many_jokers');
    expect(pickAction(t.room, 0, { jokers: ['j_x"; drop'] }, t.deps)).toBe('bad_jokers');
    expect(pickAction(t.room, 0, { ready: 'yes' }, t.deps)).toBe('bad_ready');
    expect(pickAction(t.room, 2, { ready: true }, t.deps)).toBe('not_in_pick');
    expect(t.last(0, 'pick_error')?.reason).toBe('bad_ready');
    expect(p.decks[0]).toBe('Red Deck');
    expect(p.picks[0]).toEqual([]);
    cancelPick(t.room);
  });

  it('jokers only: no deck section and a deck sent is refused', () => {
    const t = setup({ joker_picks: 3 });
    const p = startPick(t.room, t.deps, [0, 1], POOL);
    expect(p.deck).toBe(false);
    expect(t.last(0, 'pick_state')?.pool).toEqual([]);
    expect(pickAction(t.room, 0, { deck: 'Blue Deck' }, t.deps)).toBe('no_deck_pick');
    cancelPick(t.room);
  });

  it('a bot is ready at once, so the human alone decides when it ends', () => {
    const t = setup({ joker_picks: 2 }, [1]);
    const p = startPick(t.room, t.deps, [0, 1], POOL);
    expect(p.ready[1]).toBe(true);
    expect(p.done).toBe(false);
    pickAction(t.room, 0, { jokers: ['j_joker'], ready: true }, t.deps);
    expect(p.done).toBe(true);
  });

  it('a bot gets a random deck from the pool and random jokers from the allowed list, like a player', () => {
    const t = setup({ different_decks: true, joker_picks: 2 }, [1]);
    const allowed = ['j_joker', 'j_egg', 'j_greedy_joker', 'j_egg', 'bad key!'];
    const seen = new Set<string>();
    for (let i = 0; i < 40; i++) {
      const p = startPick(t.room, t.deps, [0, 1], POOL, { botJokers: allowed });
      expect(p.ready[1]).toBe(true);
      expect(POOL.filter(d => d !== RANDOM_PICK)).toContain(p.decks[1]);
      expect(p.picks[1].length).toBe(2);
      expect(new Set(p.picks[1]).size).toBe(2);
      for (const k of p.picks[1]) expect(['j_joker', 'j_egg', 'j_greedy_joker']).toContain(k);
      seen.add(p.decks[1]!);
      expect(p.decks[0]).toBe('Red Deck');
      expect(p.picks[0]).toEqual([]);
    }
    expect(seen.size).toBeGreaterThan(1);
    pickAction(t.room, 0, { ready: true }, t.deps);
    const done = t.last(0, 'pick_done') as Msg;
    expect((done.jokers as Record<string, string[]>)['1'].length).toBe(2);
  });

  it('a bot prefers decks its sim plays, keeps the free slot cap and gets no jokers without a list', () => {
    expect(deckKey('Plasma Deck')).toBe('b_plasma');
    expect(SIM_DECKS).toContain(deckKey('Checkered Deck'));
    const t = setup({ different_decks: true, joker_picks: 5, rules: { joker_slots: 5, starting_jokers: ['j_joker', 'j_egg', 'j_ice_cream'] } }, [1]);
    const p = startPick(t.room, t.deps, [0, 1], ['Nemesis Deck', 'Zodiac Deck', RANDOM_PICK], { botJokers: ['j_a', 'j_b', 'j_c', 'j_d'], rnd: () => 0.99 });
    expect(p.decks[1]).toBe('Zodiac Deck');
    expect(p.picks[1].length).toBe(2);
    const q = startPick(t.room, t.deps, [0, 1], ['Nemesis Deck'], {});
    expect(q.decks[1]).toBe('Nemesis Deck');
    expect(q.picks[1]).toEqual([]);
    const j = setup({ joker_picks: 3 }, [0]);
    const r = startPick(j.room, j.deps, [0, 1], [], { botJokers: ['j_a'] });
    expect(r.decks[0]).toBeNull();
    expect(r.picks[0]).toEqual(['j_a']);
    const lone = { ...r, picks: { ...r.picks }, decks: { ...r.decks } };
    botPick(lone, 0, [], () => 0);
    expect(lone.picks[0]).toEqual([]);
  });

  it('a player who disconnected does not block the others', () => {
    const t = setup({ joker_picks: 1 }, [], [1]);
    const p = startPick(t.room, t.deps, [0, 1], POOL);
    pickAction(t.room, 0, { ready: true }, t.deps);
    expect(p.done).toBe(true);
  });

  it('unready again before the end is allowed', () => {
    const t = setup({ joker_picks: 1 });
    const p = startPick(t.room, t.deps, [0, 1], POOL);
    pickAction(t.room, 0, { ready: true }, t.deps);
    pickAction(t.room, 0, { ready: false, jokers: ['j_egg'] }, t.deps);
    expect(p.ready[0]).toBe(false);
    pickAction(t.room, 1, { ready: true }, t.deps);
    expect(p.done).toBe(false);
    cancelPick(t.room);
  });

  it('the timer ends the phase and keeps what each player picked so far', async () => {
    const old = pickTiming.ms;
    pickTiming.ms = 40;
    try {
      const t = setup({ different_decks: true, joker_picks: 2 });
      const p = startPick(t.room, t.deps, [0, 1], POOL);
      pickAction(t.room, 1, { deck: 'Blue Deck', jokers: ['j_egg'] }, t.deps);
      await Bun.sleep(80);
      expect(p.done).toBe(true);
      expect(t.last(0, 'pick_done')?.decks).toEqual({ '0': 'Red Deck', '1': 'Blue Deck' });
      expect(t.last(1, 'pick_done')?.jokers).toEqual({ '0': [], '1': ['j_egg'] });
    } finally { pickTiming.ms = old; }
  });

  it('joker picks never go past the free joker slots', () => {
    expect(pickJokers({ joker_picks: 3 })).toBe(3);
    expect(pickJokers({ joker_picks: 3, rules: { starting_jokers: ['j_joker', 'j_egg', 'j_ice_cream'] } })).toBe(2);
    expect(pickJokers({ joker_picks: 3, rules: { joker_slots: 4, random_jokers: 3 } })).toBe(1);
    expect(pickJokers({ joker_picks: 2, rules: { joker_slots: 2, starting_jokers: ['j_joker', 'j_egg'] } })).toBe(0);
    expect(wantsPick({ code: 'a', settings: { joker_picks: 2, rules: { joker_slots: 2, starting_jokers: ['j_joker', 'j_egg'] } } })).toBe(false);
  });

  it('the clock is 120 seconds', () => {
    expect(pickTiming.ms).toBe(120_000);
    const t = setup({ joker_picks: 1 });
    startPick(t.room, t.deps, [0, 1], POOL);
    expect(t.last(0, 'pick_state')?.total_seconds).toBe(120);
    cancelPick(t.room);
  });

  it('after a deck draft, picks only offer the decks left and default to the draft deck', () => {
    const d = newDraft('seed-x', [0, 1], DRAFT_BANS_EACH, 2 * DRAFT_BANS_EACH + 3);
    while (d.phase !== 'done') draftAct(d, d.turn!, 'ban', remaining(d)[0]);
    const left = remaining(d);
    expect(left.length).toBe(3);
    const t = setup({ different_decks: true, deck_draft: true });
    const p = startPick(t.room, t.deps, [0, 1], [...left, RANDOM_PICK], { defaultDeck: d.deck });
    expect(p.decks[0]).toBe(d.deck);
    const banned = d.bans[0].deck;
    expect(pickAction(t.room, 0, { deck: banned }, t.deps)).toBe('bad_deck');
    pickAction(t.room, 0, { deck: RANDOM_PICK, ready: true }, t.deps);
    pickAction(t.room, 1, { deck: left[1], ready: true }, t.deps);
    expect(left).toContain(p.decks[0] as string);
    expect(p.decks[1]).toBe(left[1]);
  });

  it('a rematch pick keeps the previous picks and runs the done hook once', () => {
    const t = setup({ different_decks: true, joker_picks: 2 });
    let calls = 0;
    const p = startPick(t.room, t.deps, [0, 1], POOL, {
      rematch: true, prev: { decks: { 0: 'Blue Deck', 1: RANDOM_PICK }, picks: { 0: ['j_egg'], 1: ['j_joker', 'j_egg', 'j_ice_cream'] } },
      onDone: () => { calls++; },
    });
    expect(t.last(0, 'pick_state')?.rematch).toBe(true);
    expect(p.decks[0]).toBe('Blue Deck');
    expect(p.decks[1]).toBe(RANDOM_PICK);
    expect(p.picks[1]).toEqual(['j_joker', 'j_egg']);
    pickAction(t.room, 0, { ready: true }, t.deps);
    pickAction(t.room, 1, { ready: true }, t.deps);
    pickAction(t.room, 1, { ready: true }, t.deps);
    expect(calls).toBe(1);
    expect(t.last(1, 'pick_done')?.rematch).toBe(true);
  });

  it('cancel stops the timer and tells the caller a phase was running', async () => {
    const old = pickTiming.ms;
    pickTiming.ms = 30;
    try {
      const t = setup({ joker_picks: 1 });
      startPick(t.room, t.deps, [0, 1], POOL);
      expect(cancelPick(t.room)).toBe(true);
      await Bun.sleep(60);
      expect(t.sent.some(x => x.msg.type === 'pick_done')).toBe(false);
      expect(cancelPick(t.room)).toBe(false);
    } finally { pickTiming.ms = old; }
  });
});

describe('pick phase with older clients', () => {
  it('only rooms on build 64 or later get the pick screen and the 3 deck draft', async () => {
    const { pickCapable } = await import('./index');
    const { draftLeftForPicks } = await import('./draft');
    expect(pickCapable({ gameVersion: '64' })).toBe(true);
    expect(pickCapable({ gameVersion: '70' })).toBe(true);
    expect(pickCapable({ gameVersion: '63' })).toBe(false);
    expect(pickCapable({ gameVersion: '' })).toBe(false);
    expect(pickCapable({ gameVersion: '?' })).toBe(false);
    expect(draftLeftForPicks({ code: 'a', gameVersion: '63', settings: { different_decks: true } })).toBe(1);
    expect(draftLeftForPicks({ code: 'a', gameVersion: '64', settings: { different_decks: true } })).toBe(3);
    expect(draftLeftForPicks({ code: 'a', gameVersion: '64', settings: {} })).toBe(1);
  });
});
