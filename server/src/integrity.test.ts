import { describe, it, expect } from 'bun:test';
import { allowedMods, blockedMods, scoreOk, scoreLog10, scoreText, checkMessage, newTrack, lifeGainAllowed, plausibleLog10, HANDS_MAX } from './integrity';
import { dailyRuleset, dailyKey, isoWeek, rankedRuleset, rankedSettings, setDailyPool, DAILY_POOL, NEMESIS_BLIND, RANKED_RULESET } from './rulesets_server';

describe('ranked mod allowlist', () => {
  it('allows the platform mods and the ids from the env list', () => {
    const allow = allowedMods('Talisman, JokerDisplay');
    expect(allow.has('Steamodded')).toBe(true);
    expect(allow.has('Lovely')).toBe(true);
    expect(allow.has('Talisman')).toBe(true);
    expect(allow.has('JokerDisplay')).toBe(true);
    expect(allowedMods('').size).toBe(3);
    expect(allowedMods(undefined).has('Balatro')).toBe(true);
  });

  it('lists every blocked id once, in order', () => {
    const allow = allowedMods('Talisman');
    expect(blockedMods([{ id: 'Steamodded' }, { id: 'Cryptid' }, { id: 'Talisman' }, { id: 'Cryptid' }, { id: 'Pokermon' }], allow)).toEqual(['Cryptid', 'Pokermon']);
    expect(blockedMods([], allow)).toEqual([]);
    expect(blockedMods(undefined, allow)).toEqual([]);
  });
});

describe('score sanity', () => {
  it('accepts numbers and number strings, big ones included', () => {
    for (const v of [0, 12, 1e300, '0', '123456', '1.5e400', '1e+20', 'inf', 'Infinity', 'naneinf', 'e10', 'ee10#3', ' 42 ']) expect(scoreOk(v)).toBe(true);
  });

  it('refuses negative, non-numeric and odd values', () => {
    for (const v of [-1, NaN, Infinity, '-5', 'abc', '12abc', '', {}, [], null, undefined, true, '1'.repeat(70)]) expect(scoreOk(v)).toBe(false);
  });

  it('reads the size of a score', () => {
    expect(scoreLog10(1000)).toBeCloseTo(3);
    expect(scoreLog10('1.5e400')).toBeCloseTo(400.176, 2);
    expect(scoreLog10('250000')).toBeCloseTo(5.398, 2);
    expect(scoreLog10('naneinf')).toBe(Infinity);
    expect(scoreLog10('0')).toBe(0);
    expect(scoreText(-3)).toBe('-3');
    expect(scoreText('abc')).toBe('0');
    expect(scoreText(' 77 ')).toBe('77');
  });
});

describe('message checks', () => {
  it('an ante can go up by one or down, a jump is impossible', () => {
    const t = newTrack();
    expect(checkMessage(t, { type: 'blind_entered', ante: 1 })).toEqual({ reject: false, flags: [] });
    expect(checkMessage(t, { type: 'blind_entered', ante: 2 }).reject).toBe(false);
    expect(checkMessage(t, { type: 'blind_entered', ante: 1 }).reject).toBe(false);
    const jump = checkMessage(t, { type: 'blind_entered', ante: 4 });
    expect(jump.reject).toBe(true);
    expect(jump.flags[0]).toEqual({ code: 'ante_jump', detail: '1 to 4' });
    expect(t.ante).toBe(1);
  });

  it('refuses bad scores and hands or discards above the maximum', () => {
    const t = newTrack();
    expect(checkMessage(t, { type: 'play_hand', score: '-10', hands_left: 2 }).flags[0].code).toBe('bad_score');
    expect(checkMessage(t, { type: 'play_hand', score: '10', hands_left: HANDS_MAX + 1 }).flags[0].code).toBe('hands_max');
    expect(checkMessage(t, { type: 'live_stat', score: 5, hands: 2, discards: 99 }).flags[0].code).toBe('discards_max');
    expect(checkMessage(t, { type: 'live_stat', score: 5, hands: 2.5 }).reject).toBe(true);
    const ok = checkMessage(t, { type: 'play_hand', score: '300', hands_left: '3' });
    expect(ok).toEqual({ reject: false, flags: [] });
    expect(t.hands).toBe(3);
  });

  it('flags an implausible score once per ante without refusing it', () => {
    const t = newTrack();
    checkMessage(t, { type: 'blind_entered', ante: 1 });
    expect(plausibleLog10(1)).toBe(5.5);
    const big = checkMessage(t, { type: 'play_hand', score: '9000000', hands_left: 2 });
    expect(big.reject).toBe(false);
    expect(big.flags).toEqual([{ code: 'implausible_score', detail: '9000000 at ante 1' }]);
    expect(checkMessage(t, { type: 'play_hand', score: '9900000', hands_left: 1 }).flags).toEqual([]);
    expect(checkMessage(t, { type: 'blind_finished', ante: 8, score: '1e20' }).flags).toEqual([]);
  });

  it('life gain needs a rule', () => {
    expect(lifeGainAllowed({}, '1v1')).toBe(false);
    expect(lifeGainAllowed({ life_steal: true }, '1v1')).toBe(true);
    expect(lifeGainAllowed({ party_kind: 'raid' }, 'party')).toBe(true);
    expect(lifeGainAllowed({ party_kind: 'br' }, 'party')).toBe(false);
    expect(lifeGainAllowed({ rules: { extra_lives: 2 } }, '1v1')).toBe(true);
  });
});

describe('server rulesets', () => {
  it('the ranked ruleset is fixed, locked, hides the score and never bans our Nemesis blind', () => {
    const r = rankedRuleset();
    expect(r).toMatchObject({ id: 'ranked', mode: 'nemesis', locked: true });
    expect(r.settings).toMatchObject({ mode: 'nemesis', hide_opp_score: true, ruleset_id: 'ranked', layers: [] });
    expect(r.settings).toMatchObject({ allow_fast_speed: false, allow_score_speed: false, allow_skip_score: false, show_seed: false });
    expect(r.bans.blinds).not.toContain(NEMESIS_BLIND);
    expect(Object.keys(r.bans).sort()).toEqual(['blinds', 'consumables', 'jokers', 'tags', 'vouchers']);
    r.settings.starting_lives = 99;
    expect(rankedSettings().starting_lives).toBe(RANKED_RULESET.settings.starting_lives);
  });

  it('ISO weeks follow the Thursday rule', () => {
    expect(isoWeek(Date.UTC(2026, 10, 2))).toMatchObject({ year: 2026, week: 45, start: Date.UTC(2026, 10, 2) });
    expect(isoWeek(Date.UTC(2026, 10, 8, 23))).toMatchObject({ year: 2026, week: 45 });
    expect(isoWeek(Date.UTC(2027, 0, 1))).toMatchObject({ year: 2026, week: 53 });
    expect(isoWeek(Date.UTC(2025, 11, 29))).toMatchObject({ year: 2026, week: 1 });
    expect(isoWeek(Date.UTC(2026, 0, 1))).toMatchObject({ year: 2026, week: 1 });
  });

  it('daily and weekly keys and end times are UTC', () => {
    expect(dailyKey('daily', Date.UTC(2026, 10, 2, 23, 59))).toEqual({ key: '2026-11-02', ends_at: Date.UTC(2026, 10, 3) });
    expect(dailyKey('weekly', Date.UTC(2026, 10, 4))).toEqual({ key: '2026-W45', ends_at: Date.UTC(2026, 10, 9) });
  });

  it('the same date gives everyone the same ruleset', () => {
    const a = dailyRuleset('daily', Date.UTC(2026, 10, 2, 1));
    const b = dailyRuleset('daily', Date.UTC(2026, 10, 2, 22));
    expect(a).toEqual(b);
    expect(a.ruleset).toMatchObject({ id: 'daily-2026-11-02', locked: true });
    expect(a.seed).toMatch(/^[1-9A-Z]{8}$/);
    expect(a.ruleset.settings.custom_seed).toBe(a.seed);
    expect(a.ruleset.layers.length).toBe(1);
    expect(a.ruleset.settings.layers).toEqual(a.ruleset.layers);
    const w = dailyRuleset('weekly', Date.UTC(2026, 10, 2));
    expect(w.key).toBe('2026-W45');
    expect(w.ruleset.layers.length).toBe(2);
    const groups = w.ruleset.layers.map(id => DAILY_POOL.layers.find(l => l.id === id)?.group);
    expect(new Set(groups).size).toBe(2);
    const seeds = new Set(Array.from({ length: 10 }, (_, i) => dailyRuleset('daily', Date.UTC(2026, 10, 1 + i)).seed));
    expect(seeds.size).toBeGreaterThan(8);
  });

  it('the pool can be replaced with L9 data', () => {
    setDailyPool({ presets: [{ id: 'only', name: 'Only', desc: 'd', mode: 'faceoff', settings: { starting_lives: 2 } }], layers: [], decks: [], layerCount: { daily: 3, weekly: 3 } });
    const d = dailyRuleset('weekly', Date.UTC(2026, 10, 2));
    expect(d.ruleset).toMatchObject({ name: 'Only', mode: 'faceoff', layers: [] });
    expect(d.ruleset.settings).toMatchObject({ starting_lives: 2, mode: 'faceoff' });
    setDailyPool(DAILY_POOL);
  });
});
