import { describe, it, expect } from 'bun:test';
import { DailyBoard, MemoryDailyStore, D1DailyStore, dailyStoreFor, validateDaily, dailyHandlers, dayOf, sortEntries, setDaily, DAILY_TOP, type DailyEntry } from './daily_board';

const A = 'a'.repeat(24), B = 'b'.repeat(24), C = 'c'.repeat(24);
const T0 = Date.UTC(2026, 10, 5, 12);
const DAY = '2026-11-05';

function rig(start = T0) {
  let now = start;
  const board = new DailyBoard(new MemoryDailyStore(), { now: () => now });
  return { board, at: (t: number) => { now = t; } };
}

const sub = (o: Partial<{ pkey: string; name: string; won: boolean; ante: number; round: number; best: number; day: string; sig: string; bot: boolean }> = {}) => ({
  pkey: o.pkey ?? A, name: o.name ?? 'Ann', bot: o.bot, day: o.day ?? DAY, sig: o.sig ?? 'S1',
  won: o.won ?? false, ante: o.ante ?? 3, round: o.round ?? 9, best: o.best ?? 1000,
});

describe('daily board', () => {
  it('derives the UTC day', () => {
    expect(dayOf(T0)).toBe(DAY);
    expect(dayOf(Date.UTC(2026, 10, 5, 23, 59))).toBe(DAY);
  });

  it('keeps one scored result per player and day', async () => {
    const { board } = rig();
    const first = await board.submit(sub({ ante: 4 }));
    expect(first).toEqual({ ok: true, rank: 1, total: 1 });
    const again = await board.submit(sub({ ante: 9, won: true }));
    expect(again.ok).toBe(false);
    if (!again.ok) expect(again.reason).toBe('already');
    const b = await board.board(A, DAY, 'S1');
    expect(b.top).toHaveLength(1);
    expect(b.top[0].ante).toBe(4);
    expect(b.top[0].won).toBe(false);
  });

  it('refuses a second result even with another rules signature', async () => {
    const { board } = rig();
    await board.submit(sub({ sig: 'S1' }));
    const r = await board.submit(sub({ sig: 'S2' }));
    expect(r.ok).toBe(false);
  });

  it('refuses parallel submits for the same day', async () => {
    const { board } = rig();
    const [x, y] = await Promise.all([board.submit(sub()), board.submit(sub())]);
    expect([x.ok, y.ok].sort()).toEqual([false, true]);
  });

  it('ranks wins first, then ante, then best hand', async () => {
    const { board } = rig();
    await board.submit(sub({ pkey: A, name: 'Ann', ante: 6, best: 5000 }));
    await board.submit(sub({ pkey: B, name: 'Ben', ante: 9, won: true, best: 100 }));
    const c = await board.submit(sub({ pkey: C, name: 'Cid', ante: 6, best: 9000 }));
    expect(c).toEqual({ ok: true, rank: 2, total: 3 });
    const b = await board.board(A, DAY, 'S1');
    expect(b.top.map(r => r.name)).toEqual(['Ben', 'Cid', 'Ann']);
    expect(b.rank).toBe(3);
    expect(b.me?.name).toBe('Ann');
    expect(b.top[2].me).toBe(true);
    expect(b.top[0].me).toBeUndefined();
  });

  it('shows the top 20 and the player rank below it', async () => {
    const { board } = rig();
    for (let i = 0; i < 25; i++) await board.submit(sub({ pkey: String(i).padStart(24, 'k'), name: `P${i}`, ante: 30 - i }));
    await board.submit(sub({ pkey: A, name: 'Ann', ante: 1 }));
    const b = await board.board(A, DAY, 'S1');
    expect(b.top).toHaveLength(DAILY_TOP);
    expect(b.rank).toBe(26);
    expect(b.total).toBe(26);
    expect(b.me?.ante).toBe(1);
    expect(b.top.some(r => r.me)).toBe(false);
  });

  it('keeps boards apart by rules signature', async () => {
    const { board } = rig();
    await board.submit(sub({ pkey: A, sig: 'S1' }));
    await board.submit(sub({ pkey: B, sig: 'S2' }));
    expect((await board.board(A, DAY, 'S1')).total).toBe(1);
    const other = await board.board(A, DAY, 'S2');
    expect(other.total).toBe(1);
    expect(other.rank).toBeNull();
    expect(other.played).toBe(true);
  });

  it('accepts today and yesterday only', async () => {
    const { board, at } = rig();
    expect((await board.submit(sub({ day: '2026-11-04', pkey: A }))).ok).toBe(true);
    const old = await board.submit(sub({ day: '2026-11-03', pkey: B }));
    expect(old.ok).toBe(false);
    if (!old.ok) expect(old.reason).toBe('closed');
    const future = await board.submit(sub({ day: '2026-11-06', pkey: B }));
    expect(future.ok).toBe(false);
    at(Date.UTC(2026, 10, 6, 0, 30));
    expect((await board.submit(sub({ day: '2026-11-06', pkey: B }))).ok).toBe(true);
  });

  it('needs a player key and refuses bots', async () => {
    const { board } = rig();
    expect(await board.submit(sub({ pkey: '' }))).toEqual({ ok: false, reason: 'no_key' });
    expect(await board.submit(sub({ pkey: 'short' }))).toEqual({ ok: false, reason: 'no_key' });
    expect(await board.submit(sub({ bot: true }))).toEqual({ ok: false, reason: 'bot' });
  });

  it('sweeps old days', async () => {
    const store = new MemoryDailyStore();
    let now = T0;
    const board = new DailyBoard(store, { now: () => now });
    await board.submit(sub());
    now = T0 + 50 * 86_400_000;
    await board.submit(sub({ pkey: B, day: dayOf(now) }));
    await new Promise(r => setTimeout(r, 0));
    expect(store.rows.size).toBe(1);
  });

  it('sorts ties by fewer rounds then earlier time', () => {
    const e = (o: Partial<DailyEntry>): DailyEntry => ({ day: DAY, sig: 'S', pkey: A, name: 'x', won: false, ante: 5, round: 10, best: 100, at: 1, ...o });
    const list = sortEntries([e({ name: 'late', at: 9 }), e({ name: 'slow', round: 12 }), e({ name: 'early', at: 2 })]);
    expect(list.map(x => x.name)).toEqual(['early', 'late', 'slow']);
  });
});

describe('daily validation', () => {
  const ok = { type: 'daily_submit', day: DAY, sig: 'S1', won: false, ante: 3, round: 9, best: 100 };
  it('accepts a good submit and board request', () => {
    expect(validateDaily(ok)).toBeNull();
    expect(validateDaily({ type: 'daily_board', day: DAY, sig: 'S1' })).toBeNull();
    expect(validateDaily({ type: 'ping' })).toBeNull();
  });
  it('refuses bad fields', () => {
    expect(validateDaily({ ...ok, day: '5/11/2026' })).toContain('invalid day');
    expect(validateDaily({ ...ok, sig: 'a b' })).toContain('invalid sig');
    expect(validateDaily({ ...ok, sig: 'x'.repeat(65) })).toContain('invalid sig');
    expect(validateDaily({ ...ok, won: 'yes' })).toContain('invalid won');
    expect(validateDaily({ ...ok, ante: 2.5 })).toContain('invalid ante');
    expect(validateDaily({ ...ok, ante: -1 })).toContain('invalid ante');
    expect(validateDaily({ ...ok, round: 1e9 })).toContain('invalid round');
    expect(validateDaily({ ...ok, best: Number.NaN })).toContain('invalid best');
    expect(validateDaily({ ...ok, best: -5 })).toContain('invalid best');
    expect(validateDaily({ type: 'daily_board', day: DAY })).toContain('invalid sig');
  });
});

describe('daily handlers', () => {
  it('submits and reads the board through the socket handlers', async () => {
    let now = T0;
    setDaily(new DailyBoard(new MemoryDailyStore(), { now: () => now }));
    const sent: Record<string, unknown>[] = [];
    const h = dailyHandlers<{ k: string }>({
      keyOf: (ws, msg) => (typeof msg.pkey === 'string' ? msg.pkey : ws.k),
      isBot: () => false,
      send: (_ws, d) => { sent.push(d as Record<string, unknown>); },
      nameFor: (_ws, msg) => String(msg.name ?? 'Player'),
    });
    const ann = { k: A }, ben = { k: B };
    h.daily_submit(ann, { type: 'daily_submit', day: DAY, sig: 'S1', won: true, ante: 9, round: 24, best: 50000, name: 'Ann' });
    h.daily_submit(ben, { type: 'daily_submit', day: DAY, sig: 'S1', won: false, ante: 4, round: 11, best: 2000, name: 'Ben' });
    await new Promise(r => setTimeout(r, 5));
    h.daily_submit(ben, { type: 'daily_submit', day: DAY, sig: 'S1', won: true, ante: 9, round: 20, best: 90000, name: 'Ben' });
    await new Promise(r => setTimeout(r, 5));
    h.daily_board(ben, { type: 'daily_board', day: DAY, sig: 'S1' });
    await new Promise(r => setTimeout(r, 5));
    expect(sent[0]).toMatchObject({ type: 'daily_submitted', ok: true, rank: 1 });
    expect(sent[1]).toMatchObject({ type: 'daily_submitted', ok: true, rank: 2, total: 2 });
    expect(sent[2]).toMatchObject({ type: 'daily_submitted', ok: false, reason: 'already', rank: 2 });
    expect(sent[3]).toMatchObject({ type: 'daily_board', rank: 2, total: 2, played: true });
    expect((sent[3].top as { name: string }[]).map(r => r.name)).toEqual(['Ann', 'Ben']);
    now = T0;
  });
});

describe('daily D1 store', () => {
  it('uses D1 when the ranked store is D1', async () => {
    const calls: [string, unknown[]][] = [];
    const fake = {
      kind: 'd1',
      query: async (sql: string, params: unknown[] = []) => {
        calls.push([sql, params]);
        if (sql.startsWith('SELECT * FROM daily_board WHERE day = ? AND pkey = ?')) return [];
        if (sql.startsWith('SELECT * FROM daily_board WHERE day = ? AND sig = ?')) return [{ day: DAY, sig: 'S1', pkey: A, name: 'Ann', won: 1, ante: 9, round: 20, best: 123, at: 5 }];
        return [];
      },
      write: (sql: string, params: unknown[]) => { calls.push([sql, params]); },
    };
    const store = dailyStoreFor(fake);
    expect(store).toBeInstanceOf(D1DailyStore);
    expect(dailyStoreFor({ kind: 'memory' })).toBeInstanceOf(MemoryDailyStore);
    const board = new DailyBoard(store, { now: () => T0 });
    const r = await board.submit(sub());
    expect(r.ok).toBe(true);
    expect(calls.some(([sql]) => sql.startsWith('CREATE TABLE IF NOT EXISTS daily_board'))).toBe(true);
    expect(calls.some(([sql, p]) => sql.startsWith('INSERT INTO daily_board') && p[0] === DAY && p[1] === A && p[4] === 0)).toBe(true);
    const b = await board.board(A, DAY, 'S1');
    expect(b.top[0]).toEqual({ name: 'Ann', won: true, ante: 9, round: 20, best: 123, me: true });
  });
});
