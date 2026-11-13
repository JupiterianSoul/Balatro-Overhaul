import { describe, it, expect } from 'bun:test';
import { MatchLogService, MemoryLogStore, MatchLog, CAPS, CASUAL_KEEP_MS, CONTEST_WINDOW_MS, packLog, decodeLog, encodeLog, logStoreFor, D1LogStore, type LogHeader } from './matchlog';
import type { MatchIn } from './ranked';

const A = 'a'.repeat(24), B = 'b'.repeat(24);

function header(over: Partial<LogHeader> = {}): Omit<LogHeader, 'v' | 'started_at'> {
  return {
    id: over.id ?? 'log-1', mode: 'nemesis', ranked: over.ranked ?? false, kind: over.kind ?? '1v1', settings: over.settings ?? { starting_lives: 4 },
    ruleset: null, seeds: ['SEED1'],
    players: over.players ?? [
      { pid: 0, name: 'Ann', is_bot: false, version: '1.0', mods: [] },
      { pid: 1, name: 'Ben', is_bot: false, version: '1.0', mods: [{ id: 'Steamodded', version: '1' }] },
    ],
  };
}

function rig(opts: { ranked?: boolean; settings?: Record<string, unknown> } = {}) {
  let now = 1_000_000;
  const store = new MemoryLogStore();
  const records: MatchIn[] = [];
  const adjusts: [string, number][] = [];
  const svc = new MatchLogService(store, {
    now: () => now,
    record: async (m) => {
      records.push(m);
      const out = new Map<string, Record<string, unknown>>();
      for (const s of m.seats) {
        if (!s.pkey) continue;
        const delta = m.held ? 0 : s.result === 'win' ? 24 : -20;
        out.set(s.pkey, { counted: !m.held, delta, before: { rp: 100 }, after: { rp: 100 + delta } });
      }
      return out;
    },
    adjust: async (k, d) => { adjusts.push([k, d]); },
  });
  const host = {};
  const log = svc.start(host, header({ ranked: opts.ranked, settings: opts.settings }), { 0: A, 1: B });
  const rate: MatchIn = {
    id: log.id, mode: '1v1', at: now, seats: [
      { pid: 0, pkey: A, name: 'Ann', bot: false, placement: 1, result: 'win', ante: 3, score: 900 },
      { pid: 1, pkey: B, name: 'Ben', bot: false, placement: 2, result: 'lose', ante: 3, score: 100 },
    ],
  };
  const results = [{ pid: 0, placement: 1, result: 'win', score: '900' }, { pid: 1, placement: 2, result: 'lose', score: '100' }];
  return { svc, store, host, log, rate, results, records, adjusts, tick: (ms: number) => { now += ms; }, at: () => now };
}

describe('match log events', () => {
  it('records the contract events with times and throttles live stats', () => {
    const r = rig();
    const pvp = (ante: number, blind: string) => blind === 'L' && ante >= 2;
    r.svc.sync(r.host, [4, 4]);
    r.svc.observe(r.host, 0, { type: 'ready_blind' });
    r.tick(100);
    r.svc.observe(r.host, 0, { type: 'blind_entered', ante: 2, blind: 'L' }, pvp);
    r.svc.observe(r.host, 0, { type: 'play_hand', score: '120', hands_left: 3 });
    r.tick(500);
    r.svc.observe(r.host, 0, { type: 'play_hand', score: '240', hands_left: 2 });
    r.tick(2000);
    r.svc.observe(r.host, 0, { type: 'play_hand', score: '360', hands_left: 1 });
    r.svc.observe(r.host, 0, { type: 'blind_finished', ante: 2, blind: 'L', score: '360' });
    r.svc.sync(r.host, [4, 3], 'pvp_resolved');
    r.svc.observe(r.host, 1, { type: 'sabotage', key: 'sab_fog' });
    r.svc.note(r.host, 1, 'disconnect');
    r.svc.note(r.host, 1, 'rejoin');
    r.svc.observe(r.host, 1, { type: 'leave_match' });
    r.svc.observe(r.host, 0, { type: 'unready_blind' });
    const names = r.log.events.map(e => e.e);
    expect(names).toEqual(['ready', 'blind_in', 'live', 'live', 'blind_out', 'life', 'trap', 'disconnect', 'rejoin', 'forfeit', 'unready']);
    expect(r.log.events[1]).toMatchObject({ t: 100, pid: 0, ante: 2, blind: 'L', pvp: true });
    expect(r.log.events[4]).toMatchObject({ e: 'blind_out', ante: 2, blind: 'L', score: '360', hands: 1 });
    expect(r.log.events[5]).toMatchObject({ pid: 1, lives: 3, delta: -1, cause: 'pvp' });
    expect(r.log.events[6]).toMatchObject({ pid: 1, to: 0, key: 'sab_fog' });
  });

  it('flags lives going up without a rule, but not with life steal', () => {
    const r = rig();
    r.svc.sync(r.host, [4, 4]);
    r.svc.sync(r.host, [5, 4]);
    expect(r.log.flags).toEqual([{ code: 'lives_up', detail: '4 to 5' }]);
    const s = rig({ settings: { life_steal: true } });
    s.svc.sync(s.host, [4, 4]);
    s.svc.sync(s.host, [5, 4]);
    expect(s.log.flags).toEqual([]);
  });

  it('when the event cap is hit, live events go first and the log says it was cut', () => {
    const r = rig();
    const keep = CAPS.events;
    CAPS.events = 600;
    try {
      for (let i = 0; i < 6; i++) { r.tick(3000); r.svc.observe(r.host, 0, { type: 'play_hand', score: String(i), hands_left: 1 }); }
      for (let i = 0; i < 6; i++) r.svc.observe(r.host, 1, { type: 'ready_blind' });
      expect(r.log.truncated).toBe(true);
      expect(r.log.events.filter(e => e.e === 'ready').length).toBe(6);
      expect(r.log.events.filter(e => e.e === 'live').length).toBeLessThan(6);
    } finally { CAPS.events = keep; }
  });
});

describe('action streams', () => {
  it('appends in seq order, ignores repeats and waits for a missing batch', () => {
    const r = rig();
    expect(r.svc.act(r.host, 0, 1, [{ a: 'play' }])).toBe('ok');
    expect(r.svc.act(r.host, 0, 1, [{ a: 'play' }])).toBe('repeat');
    expect(r.svc.act(r.host, 0, 3, [{ a: 'buy' }])).toBe('ok');
    expect(r.log.streamsRecord()['0']).toEqual([{ a: 'play' }]);
    expect(r.svc.act(r.host, 0, 2, [{ a: 'sell' }, { a: 'reroll' }])).toBe('ok');
    expect(r.log.streamsRecord()['0']).toEqual([{ a: 'play' }, { a: 'sell' }, { a: 'reroll' }, { a: 'buy' }]);
    expect(r.svc.act(r.host, 0, 0, [])).toBe('bad');
    expect(r.svc.act(r.host, 0, 4, 'x')).toBe('bad');
    expect(r.svc.act({}, 0, 1, [])).toBe('no_match');
  });

  it('caps a stream and marks the log', () => {
    const r = rig();
    const keep = CAPS.stream;
    CAPS.stream = 200;
    try {
      let res = '';
      for (let i = 1; i < 20 && res !== 'full'; i++) res = r.svc.act(r.host, 1, i, [{ a: 'play', cards: [1, 2, 3, 4, 5] }]);
      expect(res).toBe('full');
      expect(r.log.truncated).toBe(true);
      expect(r.svc.act(r.host, 1, 50, [{ a: 'x' }])).toBe('full');
    } finally { CAPS.stream = keep; }
  });

  it('forwards accepted batches to the spectate hook', () => {
    const seen: number[] = [];
    const svc = new MatchLogService(new MemoryLogStore(), { onAct: (_id, pid, seq) => seen.push(pid * 100 + seq) });
    const host = {};
    svc.start(host, header());
    svc.act(host, 1, 1, [{}]);
    svc.act(host, 1, 1, [{}]);
    expect(seen).toEqual([101]);
  });

  it('keeps the last batches that arrive just after the match ends, then stops taking them', async () => {
    const r = rig();
    r.svc.act(r.host, 0, 1, [{ k: 'start' }, { k: 'pl' }]);
    await r.svc.finish(r.host, { reason: 'match_over', results: r.results, rate: null });
    expect(r.svc.act(r.host, 0, 2, [{ k: 'in', m: { type: 'pvp_resolved' } }, { k: 'end' }], 'log-1')).toBe('ok');
    expect(r.svc.act(r.host, 1, 1, [{ k: 'start' }], 'other-match')).toBe('no_match');
    expect(r.svc.actByKey('log-1', B, 1, [{ k: 'start' }, { k: 'end' }])).toBe('ok');
    expect(r.svc.actByKey('log-1', 'c'.repeat(24), 1, [{ k: 'start' }])).toBe('no_match');
    let rep = await r.svc.replay('log-1');
    expect('streams' in rep && rep.streams['0'].map(e => (e as { k: string }).k)).toEqual(['start', 'pl', 'in', 'end']);
    expect('streams' in rep && rep.streams['1'].length).toBe(2);
    r.tick(CAPS.lateMs + 1);
    expect(r.svc.act(r.host, 0, 3, [{ k: 'ck' }], 'log-1')).toBe('no_match');
    rep = await r.svc.replay('log-1');
    expect('streams' in rep && rep.streams['0'].length).toBe(4);
  });

  it('a batch for another match id never lands in the live match of the same room', () => {
    const svc = new MatchLogService(new MemoryLogStore());
    const host = {};
    svc.start(host, header({ id: 'new-match' }));
    expect(svc.act(host, 0, 1, [{ k: 'pl' }], 'old-match')).toBe('no_match');
    expect(svc.act(host, 0, 1, [{ k: 'pl' }], 'new-match')).toBe('ok');
    expect(svc.act(host, 0, 2, [{ k: 'di' }])).toBe('ok');
  });

  it('packing drops rejoin snapshots before whole streams', () => {
    const keep = CAPS.stored;
    try {
      const log = new MatchLog({ ...header(), v: 1, started_at: 0 });
      const big = Array.from({ length: 4000 }, (_, i) => ((i * 7919) % 65536).toString(36)).join('');
      log.act(0, 1, [{ k: 'start' }, { k: 'rs', m: { type: 'rejoin_ok', snapshot: { data: big, seq: 3 } } }, { k: 'pl' }]);
      log.act(1, 1, [{ k: 'start' }, { k: 'pl' }]);
      CAPS.stored = encodeLog({ ...log.record(), streams: { 0: [{ k: 'start' }, { k: 'rs', m: { type: 'rejoin_ok', big: true } }, { k: 'pl' }], 1: [{ k: 'start' }, { k: 'pl' }] } }).length + 50;
      const out = packLog(log);
      const rec = decodeLog(out.data);
      expect(out.truncated).toBe(true);
      expect(rec.streams['0'].length).toBe(3);
      expect((rec.streams['0'][1] as { m: Record<string, unknown> }).m).toEqual({ type: 'rejoin_ok', big: true });
      expect(rec.streams['1'].length).toBe(2);
    } finally { CAPS.stored = keep; }
  });

  it('tells a rejoining client the last batch it has, so a restarted game never reuses a seq', () => {
    const svc = new MatchLogService(new MemoryLogStore());
    const host = {};
    svc.start(host, header());
    expect(svc.actSeq(host, 0)).toBe(0);
    svc.act(host, 0, 1, [{ k: 'bs' }]);
    svc.act(host, 0, 2, [{ k: 'pl' }]);
    expect(svc.actSeq(host, 0)).toBe(2);
    svc.act(host, 0, 4, [{ k: 'di' }]);
    expect(svc.actSeq(host, 0)).toBe(4);
    expect(svc.actSeq(host, 1)).toBe(0);
    expect(svc.actSeq({}, 0)).toBe(0);
  });
});

describe('finishing, storage and history', () => {
  it('a casual match is rated, stored compressed for 60 days and shows in both histories', async () => {
    const r = rig();
    r.svc.act(r.host, 0, 1, [{ a: 'play' }]);
    const out = await r.svc.finish(r.host, { reason: 'opponent_eliminated', results: r.results, rate: r.rate });
    expect(out.get(A)?.delta).toBe(24);
    const row = r.store.rows.get('log-1')!;
    expect(row).toMatchObject({ ranked: false, status: '', has_replay: true, mode: 'nemesis' });
    expect(row.keep_until).toBe(row.ended + CASUAL_KEEP_MS);
    const rec = decodeLog(row.data);
    expect(rec.header.players.map(p => p.name)).toEqual(['Ann', 'Ben']);
    expect(rec.end?.rating).toEqual([{ pid: 0, before: 100, after: 124, delta: 24 }, { pid: 1, before: 100, after: 80, delta: -20 }]);
    expect(rec.end?.held).toBe(false);
    const h = await r.svc.history(B);
    expect(h[0]).toMatchObject({ id: 'log-1', result: 'lose', rp_delta: -20, has_replay: true, ranked: false });
    expect(h[0].players[1]).toEqual({ pid: 1, name: 'Ben', is_bot: false });
    r.svc.recent.clear();
    expect((await r.svc.history(A))[0]).toMatchObject({ id: 'log-1', result: 'win', rp_delta: 24 });
    expect(await r.svc.history('z'.repeat(24))).toEqual([]);
  });

  it('a ranked log is kept forever, casual ones are swept after 60 days', async () => {
    const r = rig({ ranked: true });
    await r.svc.finish(r.host, { reason: 'x', results: r.results, rate: r.rate });
    expect(r.store.rows.get('log-1')!.keep_until).toBeNull();
    const host2 = {};
    r.svc.start(host2, header({ id: 'log-2' }));
    await r.svc.finish(host2, { reason: 'x', results: [], rate: null });
    r.tick(CASUAL_KEEP_MS + 1000);
    r.svc.sweep();
    expect(r.store.rows.has('log-1')).toBe(true);
    expect(r.store.rows.has('log-2')).toBe(false);
  });

  it('a flagged ranked match is held unrated, a casual one is only flagged', async () => {
    const r = rig({ ranked: true });
    r.svc.observe(r.host, 0, { type: 'blind_entered', ante: 1 });
    expect(r.svc.observe(r.host, 0, { type: 'blind_entered', ante: 5 })).toBe(true);
    await r.svc.finish(r.host, { reason: 'x', results: r.results, rate: r.rate });
    expect(r.records[0].held).toBe(true);
    expect(r.store.rows.get('log-1')!.status).toBe('held');
    const rec = decodeLog(r.store.rows.get('log-1')!.data);
    expect(rec.end).toMatchObject({ held: true, rating: [], flags: [{ code: 'ante_jump', detail: '1 to 5' }] });
    expect(rec.keys).toEqual({ 0: A, 1: B });
    expect((await r.svc.history(A))[0].rp_delta).toBeNull();
    const c = rig();
    c.svc.observe(c.host, 0, { type: 'blind_entered', ante: 1 });
    expect(c.svc.observe(c.host, 0, { type: 'blind_entered', ante: 5 })).toBe(false);
    await c.svc.finish(c.host, { reason: 'x', results: c.results, rate: c.rate });
    expect(c.records[0].held).toBeUndefined();
    expect(c.store.rows.get('log-1')!.status).toBe('');
  });

  it('bots are never flagged', () => {
    const svc = new MatchLogService(new MemoryLogStore());
    const host = {};
    const log = svc.start(host, header({ ranked: true, players: [{ pid: 0, name: 'Ann', is_bot: false, version: '', mods: [] }, { pid: 1, name: 'Lou', is_bot: true, bot_level: 'hard', version: '', mods: [] }] }));
    svc.observe(host, 1, { type: 'blind_entered', ante: 1 });
    expect(svc.observe(host, 1, { type: 'blind_entered', ante: 6 })).toBe(false);
    expect(log.flags).toEqual([]);
  });

  it('packing drops streams first when a log is too big', () => {
    const log = new MatchLog({ ...header(), v: 1, started_at: 0 });
    const keep = CAPS.stored;
    for (let i = 1; i <= 40; i++) log.act(0, i, Array.from({ length: 50 }, (_, j) => ({ r: Math.random(), i, j })));
    CAPS.stored = 2000;
    try {
      log.end = { reason: 'x', ended_at: 1, results: [], rating: [], flags: [], held: false };
      const packed = packLog(log);
      expect(packed.truncated).toBe(true);
      expect(packed.data.length).toBeLessThanOrEqual(2000);
      expect(decodeLog(packed.data).streams['0']).toEqual([]);
    } finally { CAPS.stored = keep; }
    expect(decodeLog(encodeLog(log.record())).streams['0'].length).toBe(2000);
  });
});

describe('contest and review', () => {
  it('only a player of a ranked match can contest it, within the window', async () => {
    const c = rig();
    await c.svc.finish(c.host, { reason: 'x', results: c.results, rate: c.rate });
    expect(await c.svc.contest('log-1', A, 'cheat')).toEqual({ ok: false, reason: 'not_ranked' });
    const r = rig({ ranked: true });
    await r.svc.finish(r.host, { reason: 'x', results: r.results, rate: r.rate });
    expect(await r.svc.contest('nope', A, '')).toEqual({ ok: false, reason: 'not_found' });
    expect(await r.svc.contest('log-1', 'z'.repeat(24), '')).toEqual({ ok: false, reason: 'not_in_match' });
    expect(await r.svc.contest('log-1', undefined, '')).toEqual({ ok: false, reason: 'not_in_match' });
    expect(await r.svc.contest('log-1', B, 'they jumped\nto ante 8')).toEqual({ ok: true });
    expect(r.adjusts).toEqual([[A, -24], [B, 20]]);
    expect(r.store.rows.get('log-1')!.status).toBe('held');
    expect(decodeLog(r.store.rows.get('log-1')!.data).events.at(-1)).toMatchObject({ e: 'contest', pid: 1, reason: 'they jumped to ante 8' });
    expect(r.svc.recent.get('log-1')?.slimmed).toBe(true);
    expect(r.svc.recent.get('log-1')?.events).toEqual([]);
    expect(await r.svc.contest('log-1', A, '')).toEqual({ ok: true });
    expect(r.adjusts.length).toBe(2);
    const late = rig({ ranked: true });
    await late.svc.finish(late.host, { reason: 'x', results: late.results, rate: late.rate });
    late.tick(CONTEST_WINDOW_MS + 1);
    expect(await late.svc.contest('log-1', A, '')).toEqual({ ok: false, reason: 'too_late' });
  });

  it('a contest during the match holds it at the end', async () => {
    const r = rig({ ranked: true });
    expect(await r.svc.contest('log-1', A, 'lag')).toEqual({ ok: true });
    await r.svc.finish(r.host, { reason: 'x', results: r.results, rate: r.rate });
    expect(r.records[0].held).toBe(true);
    expect(r.store.rows.get('log-1')!.status).toBe('held');
  });

  it('review applies a reverted match again, or voids it for good', async () => {
    const r = rig({ ranked: true });
    await r.svc.finish(r.host, { reason: 'x', results: r.results, rate: r.rate });
    await r.svc.contest('log-1', A, '');
    expect(await r.svc.decide('log-1', 'apply')).toEqual({ ok: true });
    expect(r.adjusts.slice(2)).toEqual([[A, 24], [B, -20]]);
    expect(r.store.rows.get('log-1')!.status).toBe('applied');
    expect(await r.svc.decide('log-1', 'void')).toEqual({ ok: false, reason: 'already_reviewed' });
    const v = rig({ ranked: true });
    await v.svc.contest('log-1', A, '');
    await v.svc.finish(v.host, { reason: 'x', results: v.results, rate: v.rate });
    expect(await v.svc.decide('log-1', 'void')).toEqual({ ok: true });
    expect(v.records.length).toBe(1);
    expect(v.store.rows.get('log-1')!.status).toBe('voided');
  });

  it('applying a match that was never rated rates it now', async () => {
    const r = rig({ ranked: true });
    await r.svc.contest('log-1', A, '');
    await r.svc.finish(r.host, { reason: 'x', results: r.results, rate: r.rate });
    r.svc.recent.clear();
    r.store.setStatus('log-1', 'apply');
    expect(await r.svc.pollDecisions()).toBe(1);
    expect(r.records.at(-1)?.held).toBe(false);
    const rec = decodeLog(r.store.rows.get('log-1')!.data);
    expect(rec.end).toMatchObject({ held: false, rating: [{ pid: 0, delta: 24 }, { pid: 1, delta: -20 }] });
    expect(r.store.rows.get('log-1')!.status).toBe('applied');
    expect((await r.svc.history(A))[0].rp_delta).toBe(24);
  });
});

describe('replays', () => {
  it('returns the header and streams, never the keys, and respects private rooms', async () => {
    const r = rig();
    r.svc.act(r.host, 1, 1, [{ a: 'play' }]);
    expect(await r.svc.replay('log-1')).toEqual({ reason: 'live' });
    await r.svc.finish(r.host, { reason: 'x', results: r.results, rate: r.rate });
    expect(r.svc.recent.get('log-1')?.hasReplay()).toBe(true);
    const rep = await r.svc.replay('log-1') as Record<string, unknown>;
    expect(rep.id).toBe('log-1');
    expect(rep.streams).toEqual({ 1: [{ a: 'play' }] });
    expect(JSON.stringify(rep)).not.toContain(A);
    expect(await r.svc.replay('missing')).toEqual({ reason: 'not_found' });
    const p = rig({ settings: { spectate: false } });
    await p.svc.finish(p.host, { reason: 'x', results: p.results, rate: null });
    expect(await p.svc.replay('log-1', 'z'.repeat(24))).toEqual({ reason: 'private' });
    expect((await p.svc.replay('log-1', A) as Record<string, unknown>).id).toBe('log-1');
  });

  it('tells the viewer their seat and shows current names', async () => {
    const r = rig();
    await r.svc.finish(r.host, { reason: 'x', results: r.results, rate: null });
    expect((await r.svc.replay('log-1', B) as Record<string, unknown>).you).toBe(1);
    expect('you' in (await r.svc.replay('log-1') as Record<string, unknown>)).toBe(false);
    const named = new MatchLogService(r.store, { nameOf: async k => (k === B ? 'Benjamin' : null) });
    const rep = await named.replay('log-1', A) as { header: LogHeader; you: number };
    expect(rep.you).toBe(0);
    expect(rep.header.players.map(p => p.name)).toEqual(['Ann', 'Benjamin']);
    expect(rep.header.players.map(p => p.rec)).toEqual([undefined, 'Ben']);
  });

  it('hides a replay from one player only and lists finished matches only', async () => {
    const r = rig();
    await r.svc.finish(r.host, { reason: 'x', results: r.results, rate: null });
    expect(await r.svc.hide('log-1', 'z'.repeat(24))).toEqual({ ok: false, reason: 'not_in_match' });
    expect(await r.svc.hide('log-1', A)).toEqual({ ok: true });
    expect(await r.svc.history(A)).toEqual([]);
    expect((await r.svc.history(B))[0].id).toBe('log-1');
    r.svc.recent.clear();
    expect(await r.svc.history(A)).toEqual([]);
    expect((await r.svc.history(B))[0].id).toBe('log-1');
    const u = rig();
    await u.svc.finish(u.host, { reason: 'x', results: [], rate: null });
    expect(await u.svc.history(A)).toEqual([]);
  });
});

describe('stores', () => {
  it('picks the D1 log store only for a D1 ranked store', () => {
    expect(logStoreFor({ kind: 'memory' }).kind).toBe('memory');
    expect(logStoreFor({ kind: 'd1', query: async () => [], write: () => undefined })).toBeInstanceOf(D1LogStore);
  });

  it('the D1 store writes upserts and reads history with the review status', async () => {
    const writes: [string, unknown[]][] = [];
    const d1 = new D1LogStore({
      query: async (sql: string) => sql.startsWith('SELECT p.item') ? [{ item: JSON.stringify({ id: 'x', at: 5, mode: 'nemesis', ranked: true, players: [], result: 'win', placement: 1, rp_delta: 3, has_replay: false }), status: 'voided' }] : [],
      write: (sql: string, params: unknown[]) => { writes.push([sql, params]); },
    });
    const svc = new MatchLogService(d1);
    const host = {};
    svc.start(host, header({ ranked: true }), { 0: A });
    await svc.finish(host, { reason: 'x', results: [], rate: null });
    expect(writes[0][0]).toContain('INSERT INTO match_logs');
    expect(writes[0][1][7]).toBeNull();
    expect(writes[1][0]).toContain('INSERT INTO match_log_players');
    expect((await d1.history(A, 10, 1e15))[0]).toMatchObject({ id: 'x', status: 'voided' });
    d1.sweep(10);
    expect(writes.at(-1)?.[0]).toContain('DELETE FROM match_log_players');
  });
});
