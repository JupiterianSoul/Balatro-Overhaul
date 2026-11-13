import { describe, it, expect } from 'bun:test';
import {
  rankOf, computeDelta, botFactor, placementPoints, addXp, xpNeed, seasonAt, softReset, RankedService, cleanRecoveryCode, newRecoveryCode,
  itemInfo, rankUnlocks, LEGEND_RP, type MatchIn, type SeatIn, CATALOG } from './ranked';
import { MemoryStore, D1Store } from './ranked_store';

function seat(o: Partial<SeatIn>): SeatIn {
  return { name: 'A', bot: false, placement: 1, result: 'win', ante: 4, score: 50_000, ...o };
}
function duel(a: Partial<SeatIn>, b: Partial<SeatIn>): MatchIn {
  return { id: 'm1', mode: '1v1', at: Date.UTC(2026, 9, 15), seats: [seat({ pkey: 'a'.repeat(24), ...a }), seat({ pkey: 'b'.repeat(24), name: 'B', placement: 2, result: 'lose', ...b })] };
}

describe('ranks', () => {
  it('maps RP to ranks and tiers', () => {
    expect(rankOf(0)).toMatchObject({ rank: 0, tier: 3, name: 'Stone' });
    expect(rankOf(199)).toMatchObject({ rank: 0, tier: 2 });
    expect(rankOf(299)).toMatchObject({ rank: 0, tier: 1, next: 300 });
    expect(rankOf(300)).toMatchObject({ rank: 1, tier: 3, name: 'Bronze' });
    expect(rankOf(2699)).toMatchObject({ rank: 8, tier: 1, name: 'Negative' });
    expect(rankOf(LEGEND_RP)).toMatchObject({ rank: 9, tier: 0, name: 'TRUE JIMBO', next: null });
    expect(rankOf(-5).rank).toBe(0);
  });
});

describe('RP math', () => {
  it('a 1v1 win against a human gives placement, ante, score and streak points', () => {
    const m = duel({}, {});
    const d = computeDelta(m, m.seats[0], 500, 2);
    expect(d.counted).toBe(true);
    expect(d.botFactor).toBe(1);
    expect(d.delta).toBe(24 + 3 + 1 + 4);
    expect(d.lines.map(l => l.k)).toEqual(['placement', 'ante', 'score', 'streak', 'bots']);
  });

  it('bot matches count half', () => {
    const m = duel({}, { bot: true, pkey: undefined });
    const d = computeDelta(m, m.seats[0], 500, 0);
    expect(d.botFactor).toBe(0.5);
    expect(d.delta).toBe(Math.round((24 + 3 + 1) * 0.5));
  });

  it('losses cost less at low ranks', () => {
    const m = duel({}, {});
    const low = computeDelta(m, m.seats[1], 50, 0).delta;
    const mid = computeDelta(m, m.seats[1], 1300, 0).delta;
    const high = computeDelta(m, m.seats[1], 2000, 0).delta;
    expect(low).toBeLessThanOrEqual(0);
    expect(low).toBeGreaterThan(mid);
    expect(mid).toBeGreaterThan(high);
    expect(high).toBe(-20 + 2);
  });

  it('a loss at the RP floor adds a floor line so the lines add up to the total', () => {
    const m = duel({}, {});
    const d = computeDelta(m, m.seats[1], 0, 0);
    expect(d.delta).toBe(0);
    const floor = d.lines.find(l => l.k === 'floor');
    expect(floor).toBeDefined();
    const f = (d.lines.find(l => l.k === 'bots')?.v ?? 100) / 100;
    const sum = d.lines.filter(l => l.k !== 'bots' && l.k !== 'floor').reduce((a, l) => a + l.v, 0);
    expect(Math.round(sum * f) + floor!.v).toBe(d.delta);
    expect(computeDelta(m, m.seats[1], 500, 0).lines.some(l => l.k === 'floor')).toBe(false);
  });

  it('never takes RP below zero and never gives points for a loss', () => {
    const m = duel({}, { ante: 9, score: 1e9 });
    const d = computeDelta(m, m.seats[1], 3, 0);
    expect(d.delta).toBeGreaterThanOrEqual(-3);
    expect(d.delta).toBeLessThanOrEqual(0);
  });

  it('a match that never left ante 1 does not count', () => {
    const m = duel({ ante: 1 }, { ante: 1 });
    const d = computeDelta(m, m.seats[0], 100, 0);
    expect(d).toMatchObject({ counted: false, delta: 0, reason: 'short' });
  });

  it('battle royale placement goes from +24 to -20', () => {
    const m: MatchIn = { id: 'x', mode: 'br', at: 0, seats: [1, 2, 3, 4, 5].map(p => seat({ placement: p, result: p === 1 ? 'win' : 'lose' })) };
    expect(m.seats.map(s => placementPoints(m, s))).toEqual([24, 13, 2, -9, -20]);
  });

  it('teams and raid use the result, bot factor counts enemies only in teams', () => {
    const t: MatchIn = { id: 'x', mode: 'teams', at: 0, seats: [seat({ team: 0 }), seat({ team: 0, bot: true }), seat({ team: 1, result: 'lose', placement: 2 }), seat({ team: 1, bot: true, result: 'lose', placement: 2 })] };
    expect(placementPoints(t, t.seats[0])).toBe(24);
    expect(botFactor(t, t.seats[0])).toBe(0.75);
    const r: MatchIn = { id: 'x', mode: 'raid', at: 0, seats: [seat({}), seat({ bot: true })] };
    expect(placementPoints(r, r.seats[0])).toBe(18);
    expect(botFactor(r, r.seats[0])).toBe(0.5);
  });

  it('XP levels up and carries the rest', () => {
    expect(xpNeed(1)).toBe(300);
    expect(addXp(1, 250, 100)).toEqual({ level: 2, xp: 50, ups: 1 });
    expect(addXp(1, 0, 300 + 350 + 10)).toEqual({ level: 3, xp: 10, ups: 2 });
  });
});

describe('seasons', () => {
  it('a season is one quarter in UTC, starting in January, April, July and October', () => {
    const s = seasonAt(Date.UTC(2026, 9, 28, 12));
    expect(s.id).toBe('2026-Q4');
    expect(s.name).toBe('Autumn 2026');
    expect(s.starts).toBe(Date.UTC(2026, 9, 1));
    expect(s.ends).toBe(Date.UTC(2027, 0, 1));
    expect(seasonAt(Date.UTC(2026, 11, 31, 23, 59)).ends).toBe(Date.UTC(2027, 0, 1));
    expect(seasonAt(Date.UTC(2027, 0, 1)).id).toBe('2027-Q1');
    expect(seasonAt(Date.UTC(2027, 2, 31, 23, 59)).id).toBe('2027-Q1');
    expect(seasonAt(Date.UTC(2027, 3, 1)).id).toBe('2027-Q2');
    expect(seasonAt(Date.UTC(2027, 6, 15)).name).toBe('Summer 2027');
    expect(seasonAt(Date.UTC(2027, 6, 15)).quarter).toBe(3);
  });

  it('soft reset drops about one rank', () => {
    expect(softReset(1450)).toBe(1150);
    expect(softReset(120)).toBe(0);
  });

  it('a new quarter soft resets the player and grants the peak reward', async () => {
    let now = Date.UTC(2026, 10, 10);
    const store = new MemoryStore();
    const svc = new RankedService(store, () => now, () => 0.5);
    const k = 'c'.repeat(24);
    const st = await svc.load(k, 'Cee');
    expect(st.row.season).toBe('2026-Q4');
    st.row.rp = 1000; st.row.peak_rp = 1250; st.row.matches = 5;
    now = Date.UTC(2026, 11, 20);
    expect(svc.rollSeason(st)).toBe(false);
    expect(st.row.rp).toBe(1000);
    const ends: unknown[] = [];
    svc.onSeasonEnd = (pkey, info) => { ends.push({ pkey, ...info }); };
    now = Date.UTC(2027, 0, 2);
    expect(svc.rollSeason(st)).toBe(true);
    expect(ends).toEqual([{ pkey: k, season: '2026-Q4', peak: 4, rp: 700, rank: rankOf(700).rank, rewards: ['s2026-Q4_b_4', 's2026-Q4_k_4'] }]);
    expect(st.row.rp).toBe(700);
    expect(st.row.peak_rp).toBe(700);
    expect(st.row.season).toBe('2027-Q1');
    expect(st.unlocks.has('s2026-Q4_b_4')).toBe(true);
    expect(st.unlocks.has('s2026-Q4_k_4')).toBe(true);
    expect(itemInfo('s2026-Q4_b_4')).toMatchObject({ type: 'badge', name: 'Autumn 2026 Platinum Badge', source: 'season' });
    expect(itemInfo('s2026-Q4_k_4')).toMatchObject({ type: 'back', name: 'Autumn 2026 Sleeve' });
    expect(store.seasons.has('2027-Q1')).toBe(true);
    expect(svc.rollSeason(st)).toBe(false);
  });

  it('the live monthly season moves into the quarter with its points and rewards', async () => {
    const now = Date.UTC(2026, 10, 20);
    const store = new MemoryStore();
    const k = 'm'.repeat(24);
    store.savePlayer({ pkey: k, name: 'Mo', rp: 1000, rank: 3, peak_rp: 1250, best_rank: 4, season: '2026-11', xp: 0, level: 1, packs: 0, streak: 0, recovery: 'R', created: 1, last_seen: 1, matches: 5, wins: 3 });
    store.addUnlock(k, 's2026-10_b_3', 'season', 1);
    const svc = new RankedService(store, () => now, () => 0.5);
    const st = await svc.load(k);
    expect(st.row.season).toBe('2026-Q4');
    expect(st.row.rp).toBe(1000);
    expect(st.row.peak_rp).toBe(1250);
    expect(st.unlocks.has('s2026-10_b_3')).toBe(true);
    expect(itemInfo('s2026-10_b_3')).toMatchObject({ name: 'October 2026 Gold Badge' });
    expect(store.players.get(k)?.season).toBe('2026-Q4');
    expect([...st.unlocks.keys()].some(id => id.startsWith('s2026-11') || id.startsWith('s2026-Q4'))).toBe(false);
  });

  it('a monthly season that ended before the switch still pays out and resets once', async () => {
    const store = new MemoryStore();
    const k = 'o'.repeat(24);
    store.savePlayer({ pkey: k, name: 'Oct', rp: 1000, rank: 3, peak_rp: 1250, best_rank: 4, season: '2026-10', xp: 0, level: 1, packs: 0, streak: 0, recovery: 'R2', created: 1, last_seen: 1, matches: 5, wins: 3 });
    const svc = new RankedService(store, () => Date.UTC(2026, 10, 20), () => 0.5);
    const st = await svc.load(k);
    expect(st.row.season).toBe('2026-Q4');
    expect(st.row.rp).toBe(700);
    expect(st.unlocks.has('s2026-10_b_4')).toBe(true);
    expect(st.unlocks.has('s2026-10_k_4')).toBe(true);
  });

  it('a legacy month from an ended quarter rolls with the quarter reward', async () => {
    const store = new MemoryStore();
    const k = 'q'.repeat(24);
    store.savePlayer({ pkey: k, name: 'Late', rp: 1000, rank: 3, peak_rp: 1250, best_rank: 4, season: '2026-12', xp: 0, level: 1, packs: 0, streak: 0, recovery: 'R3', created: 1, last_seen: 1, matches: 5, wins: 3 });
    const svc = new RankedService(store, () => Date.UTC(2027, 1, 3), () => 0.5);
    const st = await svc.load(k);
    expect(st.row.season).toBe('2027-Q1');
    expect(st.row.rp).toBe(700);
    expect(st.unlocks.has('s2026-Q4_b_4')).toBe(true);
    expect(st.unlocks.has('s2026-12_b_4')).toBe(false);
  });

  it('the profile shows the quarter with its year and number', async () => {
    const svc = new RankedService(new MemoryStore(), () => Date.UTC(2026, 10, 2), () => 0.5);
    const st = await svc.load('p'.repeat(24), 'Pea');
    const season = svc.profilePayload(st).season as Record<string, unknown>;
    expect(season).toMatchObject({ id: '2026-Q4', name: 'Autumn 2026', year: 2026, quarter: 4, endsAt: Date.UTC(2027, 0, 1) });
  });
});

describe('held and adjusted results', () => {
  it('a held match changes nothing and says so', async () => {
    const store = new MemoryStore();
    const svc = new RankedService(store, () => Date.UTC(2026, 9, 15), () => 0.1);
    const out = await svc.recordMatch({ ...duel({}, {}), held: true });
    const a = out.get('a'.repeat(24)) as Record<string, any>;
    expect(a).toMatchObject({ counted: false, reason: 'held', delta: 0, held: true, match_id: 'm1' });
    expect(a.lines).toEqual([]);
    expect(a.xp.gain).toBe(0);
    expect(store.players.get('a'.repeat(24))?.rp).toBe(0);
    expect(store.matchPlayers.length).toBe(0);
  });

  it('adjust moves RP both ways and never below zero', async () => {
    const store = new MemoryStore();
    const svc = new RankedService(store, () => Date.UTC(2026, 9, 15), () => 0.1);
    const k = 'a'.repeat(24);
    const st = await svc.load(k, 'A');
    st.row.rp = 290;
    await svc.adjust(k, 20);
    expect(st.row.rp).toBe(310);
    expect(st.row.rank).toBe(1);
    expect(st.unlocks.has('rt_1')).toBe(true);
    await svc.adjust(k, -500);
    expect(st.row.rp).toBe(0);
    expect(st.unlocks.has('rt_1')).toBe(true);
  });
});

describe('service', () => {
  it('records a match, writes RP and history, and returns the results payload', async () => {
    const store = new MemoryStore();
    const svc = new RankedService(store, () => Date.UTC(2026, 9, 15), () => 0.1);
    const m = duel({}, {});
    const out = await svc.recordMatch(m);
    const a = out.get('a'.repeat(24)) as Record<string, any>;
    const b = out.get('b'.repeat(24)) as Record<string, any>;
    expect(a.delta).toBe(28);
    expect(a.after.rp).toBe(28);
    expect(b.delta).toBe(0);
    expect(a.xp.gain).toBe(60 + 45 + 40);
    expect(store.players.get('a'.repeat(24))?.rp).toBe(28);
    expect(store.matchPlayers.length).toBe(2);
    expect((await store.history('a'.repeat(24), 20))[0]).toMatchObject({ mode: '1v1', rp_delta: 28 });
    const board = await svc.leaderboard();
    expect(board[0].pkey).toBe('a'.repeat(24));
    expect(svc.badge('a'.repeat(24))).toMatchObject({ r: 0, t: 3 });
  });

  it('bots and players without a key get no row', async () => {
    const store = new MemoryStore();
    const svc = new RankedService(store);
    await svc.recordMatch(duel({ ante: 3 }, { bot: true, pkey: undefined }));
    expect(store.players.size).toBe(1);
  });

  it('promotion grants rank cosmetics once, packs open into owned items', async () => {
    const store = new MemoryStore();
    let r = 0;
    const svc = new RankedService(store, () => Date.UTC(2026, 9, 15), () => { r = (r + 0.37) % 1; return r; });
    const k = 'a'.repeat(24);
    const st = await svc.load(k, 'A');
    expect(st.unlocks.has('rt_0')).toBe(true);
    st.row.rp = 295;
    const res = (await svc.recordMatch(duel({}, {}))).get(k) as Record<string, any>;
    expect(res.promoted).toBe(true);
    expect(res.unlocks.map((u: any) => u.id)).toEqual(rankUnlocks(0, 1));
    st.row.packs = 1;
    const pack = svc.openPack(st);
    expect(pack?.items.length).toBe(3);
    for (const x of pack!.items) expect(st.unlocks.has(x.item.id)).toBe(true);
    expect(svc.openPack(st)).toBeNull();
    expect(svc.equip(st, 'title', 'rt_1')).toBe(true);
    expect(svc.equip(st, 'title', 'rk_1')).toBe(false);
    expect(svc.equip(st, 'flame', 'f_rainbow')).toBe(st.unlocks.has('f_rainbow'));
    expect(store.equipped.get(k)?.title).toBe('rt_1');
  });

  it('the test hook sets RP and packs and grants the rank cosmetics on the way', async () => {
    const svc = new RankedService(new MemoryStore(), () => Date.UTC(2026, 9, 15), () => 0.5);
    const st = await svc.load('c'.repeat(24), 'C');
    const got = svc.testSet(st, { rp: 2800, packs: 3 }, Date.UTC(2026, 9, 15));
    expect(st.row.rp).toBe(2800);
    expect(st.row.rank).toBe(9);
    expect(st.row.packs).toBe(3);
    expect(got).toEqual(rankUnlocks(0, 9));
  });

  it('the test hook with all unlocks every catalog item', async () => {
    const svc = new RankedService(new MemoryStore(), () => Date.UTC(2026, 9, 15), () => 0.5);
    const st = await svc.load('e'.repeat(24), 'E');
    svc.testSet(st, { rp: 3000, all: true }, Date.UTC(2026, 9, 15));
    expect(st.row.rank).toBe(9);
    for (const it of CATALOG) expect(st.unlocks.has(it.id)).toBe(true);
  });

  it('rank items include card and joker frames and old players get missing rank items on load', async () => {
    expect(rankUnlocks(0, 1)).toContain('rc_1');
    expect(rankUnlocks(0, 1)).toContain('rj_1');
    const store = new MemoryStore();
    const k = 'd'.repeat(24);
    const svc = new RankedService(store, () => Date.UTC(2026, 9, 15), () => 0.5);
    const st = await svc.load(k, 'D');
    svc.testSet(st, { rp: 700 }, Date.UTC(2026, 9, 15));
    svc.equip(st, 'cframe', 'rc_2');
    expect(st.equipped.cframe).toBe('rc_2');
    store.unlocks.set(k, (store.unlocks.get(k) ?? []).filter(u => u.item !== 'rj_1'));
    const fresh = new RankedService(store, () => Date.UTC(2026, 9, 15), () => 0.5);
    const again = await fresh.load(k, 'D');
    expect(again.unlocks.has('rj_1')).toBe(true);
  });

  it('recovery codes are clean and findable', async () => {
    const code = newRecoveryCode();
    expect(code).toMatch(/^[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$/);
    expect(cleanRecoveryCode(code.toLowerCase().replace(/-/g, ' '))).toBe(code);
    expect(cleanRecoveryCode('nope')).toBeNull();
    const store = new MemoryStore();
    const svc = new RankedService(store);
    const st = await svc.load('d'.repeat(24), 'D');
    expect((await store.findRecovery(st.row.recovery))?.pkey).toBe('d'.repeat(24));
  });
});

type FakeRes = { ok: boolean; status: number; json(): Promise<unknown> };

describe('D1 failure queue', () => {
  function fake(fail: () => boolean, seen: { sql: string; params: unknown[] }[]) {
    return async (_u: string, init: { body: string }): Promise<FakeRes> => {
      if (fail()) return { ok: false, status: 503, json: async () => ({ success: false, errors: [{ message: 'down' }] }) };
      seen.push(JSON.parse(init.body));
      return { ok: true, status: 200, json: async () => ({ success: true, result: [{ results: [] }] }) };
    };
  }

  it('queues writes while D1 fails and retries them in order', async () => {
    let down = true;
    const seen: { sql: string; params: unknown[] }[] = [];
    const timers: (() => void)[] = [];
    const store = new D1Store({ accountId: 'acc', databaseId: 'db', token: 't', fetch: fake(() => down, seen) as never, setTimer: fn => { timers.push(fn); return 0; } });
    store.addUnlock('k', 'one', 'pack', 1);
    store.addUnlock('k', 'two', 'pack', 2);
    await Bun.sleep(5);
    expect(store.pending()).toBe(2);
    expect(timers.length).toBe(1);
    store.addUnlock('k', 'three', 'pack', 3);
    await Bun.sleep(5);
    expect(store.pending()).toBe(3);
    down = false;
    timers.shift()!();
    await Bun.sleep(5);
    expect(store.pending()).toBe(0);
    expect(seen.map(s => s.params[1])).toEqual(['one', 'two', 'three']);
  });

  it('drops the oldest write when the queue is full', async () => {
    const store = new D1Store({ accountId: 'a', databaseId: 'b', token: 'c', fetch: fake(() => true, []) as never, setTimer: () => 0, maxQueue: 3 });
    for (let i = 0; i < 5; i++) store.setEquipped('k', 'title', `t${i}`);
    await Bun.sleep(5);
    expect(store.pending()).toBe(3);
    expect(store.dropped).toBe(2);
  });

  it('caps the queued bytes too, so a long D1 outage cannot hold big match logs in memory', async () => {
    const store = new D1Store({ accountId: 'a', databaseId: 'b', token: 'c', fetch: fake(() => true, []) as never, setTimer: () => 0, maxQueueBytes: 100_000 });
    const big = 'x'.repeat(30_000);
    for (let i = 0; i < 20; i++) store.write('INSERT INTO match_logs (id, data) VALUES (?, ?)', [`m${i}`, big]);
    await Bun.sleep(5);
    expect(store.queueBytes).toBeLessThanOrEqual(100_000);
    expect(store.pending()).toBeLessThanOrEqual(4);
    expect(store.dropped).toBeGreaterThanOrEqual(16);
  });

  it('a failed profile read defers the match result until the profile loads', async () => {
    let down = true;
    const store = new MemoryStore();
    const real = store.getPlayer.bind(store);
    store.getPlayer = async (k: string) => { if (down) throw new Error('down'); return real(k); };
    const svc = new RankedService(store, () => Date.UTC(2026, 9, 15));
    const out = await svc.recordMatch(duel({}, {}));
    expect(out.size).toBe(0);
    down = false;
    const st = await svc.load('a'.repeat(24), 'A');
    expect(st.row.rp).toBe(28);
    expect(store.matchPlayers.some(r => r.pkey === 'a'.repeat(24))).toBe(true);
  });

  it('sends the query to the D1 HTTP API with the token', async () => {
    let call: { url: string; init: { headers: Record<string, string>; body: string } } | null = null;
    const store = new D1Store({ accountId: 'ACC', databaseId: 'DB', token: 'TOK', fetch: (async (url: string, init: never) => { call = { url, init }; return { ok: true, status: 200, json: async () => ({ success: true, result: [{ results: [{ pkey: 'x', rp: 5 }] }] }) }; }) as never });
    const p = await store.getPlayer('x');
    expect(p?.rp).toBe(5);
    expect(call!.url).toBe('https://api.cloudflare.com/client/v4/accounts/ACC/d1/database/DB/query');
    expect(call!.init.headers.Authorization).toBe('Bearer TOK');
    expect(JSON.parse(call!.init.body).params).toEqual(['x']);
  });
});

describe('D1 refused writes', () => {
  it('a write D1 keeps refusing with a 4xx is dropped so the queue moves on', async () => {
    const seen: string[] = [];
    const timers: (() => void)[] = [];
    const store = new D1Store({ accountId: 'a', databaseId: 'b', token: 'c', setTimer: fn => { timers.push(fn); return 0; }, fetch: (async (_u: string, init: { body: string }) => {
      const b = JSON.parse(init.body);
      if (b.params[1] === 'bad') return { ok: false, status: 400, json: async () => ({ success: false }) };
      seen.push(b.params[1]);
      return { ok: true, status: 200, json: async () => ({ success: true, result: [{ results: [] }] }) };
    }) as never });
    store.addUnlock('k', 'bad', 'pack', 1);
    store.addUnlock('k', 'good', 'pack', 2);
    for (let i = 0; i < 3; i++) { await Bun.sleep(2); timers.shift()?.(); }
    await Bun.sleep(5);
    expect(store.pending()).toBe(0);
    expect(seen).toEqual(['good']);
  });
});
