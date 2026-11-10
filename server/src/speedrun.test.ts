import { describe, expect, test } from 'bun:test';
import { deflateSync } from 'node:zlib';
import { SpeedrunService, validateSpeedrun, plausible, parseDigest, weekId, weekSeed, bestPerPlayer, speedrunStoreFor, readReplay, SR_SUBMITS_PER_HOUR, SR_REPLAY_MAX_B64, SR_REPLAY_MSG_BYTES, SR_REPLAY_GETS_PER_HOUR, SPEEDRUN_BIG_TYPES, type SpeedrunRow } from './speedrun';

const NOW = Date.UTC(2026, 10, 5, 4, 0, 0);
const KEY_A = 'A'.repeat(24);
const KEY_B = 'B'.repeat(24);

function splits(n: number, total: number): number[] {
  return Array.from({ length: n }, (_, i) => Math.round((total * (i + 1) / n) * 10) / 10);
}

function run(over: Record<string, unknown> = {}): Record<string, unknown> {
  return { id: 'run' + Math.random().toString(36).slice(2, 12).replace(/[^a-z0-9]/g, 'x'), cat: 'ante2', deck: 'b_red', stake: 1, seed_type: 'random', seed: 'K3J9QX2A', time: 120, splits: splits(2, 120), blinds: [3, 6], hands: [6, 12], v: 1, ...over };
}

interface Sock { name: string; pkey?: string; out: Record<string, unknown>[] }

function service(now = () => NOW) {
  return new SpeedrunService<Sock>({
    store: () => null,
    send: (ws, d) => { ws.out.push(d as Record<string, unknown>); },
    keyOf: (ws, msg) => (typeof msg.pkey === 'string' ? msg.pkey : ws.pkey),
    nameOf: ws => ws.name,
    now,
  });
}

describe('speedrun validation', () => {
  test('accepts a good submit and board request', () => {
    expect(validateSpeedrun({ type: 'speedrun_submit', run: run() })).toBeNull();
    expect(validateSpeedrun({ type: 'speedrun_board', cat: 'any', deck: 'all', stake: 0, seed_type: 'weekly', limit: 20 })).toBeNull();
  });
  test('refuses bad fields', () => {
    expect(validateSpeedrun({ type: 'speedrun_submit', run: run({ cat: 'any' }) })).toContain('splits');
    expect(validateSpeedrun({ type: 'speedrun_submit', run: run({ deck: 'b_forge' }) })).toContain('deck');
    expect(validateSpeedrun({ type: 'speedrun_submit', run: run({ stake: 13 }) })).toContain('stake');
    expect(validateSpeedrun({ type: 'speedrun_submit', run: run({ time: -1 }) })).toContain('time');
    expect(validateSpeedrun({ type: 'speedrun_submit', run: run({ seed: 'abc' }) })).toContain('seed');
    expect(validateSpeedrun({ type: 'speedrun_submit', run: run({ id: 'x' }) })).toContain('id');
    expect(validateSpeedrun({ type: 'speedrun_submit', run: 'nope' })).toContain('run');
    expect(validateSpeedrun({ type: 'speedrun_submit', run: run({ blinds: [3] }) })).toContain('blinds');
    expect(validateSpeedrun({ type: 'speedrun_submit', run: run({ hands: [1.5, 2] }) })).toContain('hands');
    expect(validateSpeedrun({ type: 'speedrun_board', cat: 'ante9' })).toContain('cat');
    expect(validateSpeedrun({ type: 'speedrun_board', cat: 'any', limit: 1000 })).toContain('limit');
  });
});

describe('speedrun plausibility', () => {
  test('same weekly seed as the game', () => {
    expect(weekSeed(2914)).toBe('LX27UCFJ');
    expect(weekId(NOW)).toBe(Math.floor((Math.floor(NOW / 86_400_000) + 3) / 7));
  });
  test('refuses impossible times', () => {
    const d = { blinds: [3, 6], hands: [6, 12] };
    expect(plausible({ cat: 'ante2', seed_type: 'random', seed: 'AAAA', time: 20, splits: [10, 20], ...d }, NOW)).toBe('too_fast');
    expect(plausible({ cat: 'ante2', seed_type: 'random', seed: 'AAAA', time: 200, splits: [60, 120], ...d }, NOW)).toBe('time_mismatch');
    expect(plausible({ cat: 'ante2', seed_type: 'random', seed: 'AAAA', time: 120, splits: [80, 60], ...d }, NOW)).toBe('too_fast');
    expect(plausible({ cat: 'ante2', seed_type: 'weekly', seed: 'AAAA', time: 120, splits: [60, 120], ...d }, NOW)).toBe('weekly_seed');
    expect(plausible({ cat: 'ante2', seed_type: 'weekly', seed: weekSeed(weekId(NOW)), time: 120, splits: [60, 120], ...d }, NOW)).toBeNull();
    expect(plausible({ cat: 'ante2', seed_type: 'weekly', seed: weekSeed(weekId(NOW) - 1), time: 120, splits: [60, 120], ...d }, NOW)).toBeNull();
  });
  test('refuses run data that cannot fit the time', () => {
    const base = { cat: 'ante2', seed_type: 'random', seed: 'AAAA', time: 120, splits: [60, 120] };
    expect(plausible({ ...base, blinds: [3, 6], hands: [6, 12] }, NOW)).toBeNull();
    expect(plausible({ ...base, blinds: [0, 3], hands: [0, 6] }, NOW)).toBe('run_data');
    expect(plausible({ ...base, blinds: [3, 6], hands: [6, 6] }, NOW)).toBe('run_data');
    expect(plausible({ ...base, blinds: [3, 12], hands: [6, 20] }, NOW)).toBe('run_data');
    expect(plausible({ ...base, blinds: [3, 6], hands: [80, 90] }, NOW)).toBe('too_fast');
  });
  test('replay digest has to match the splits and the run data', () => {
    const base = { cat: 'ante2', seed_type: 'random', seed: 'AAAA', time: 120, splits: [60, 120], blinds: [3, 6], hands: [6, 12] };
    const rp = { n: 20, pl: [6, 6], bs: [3, 3], fb: [1.2, 63.5], lp: [58.9, 119.4] };
    expect(plausible({ ...base, rp }, NOW)).toBeNull();
    expect(plausible({ ...base, rp: { ...rp, pl: [5, 6] } }, NOW)).toBe('replay');
    expect(plausible({ ...base, rp: { ...rp, bs: [3, 2] } }, NOW)).toBe('replay');
    expect(plausible({ ...base, rp: { ...rp, lp: [58.9, 140] } }, NOW)).toBe('replay');
    expect(plausible({ ...base, rp: { ...rp, fb: [1.2, 40] } }, NOW)).toBe('replay');
    expect(plausible({ ...base, rp: { ...rp, fb: [30, 63.5], lp: [20, 119.4] } }, NOW)).toBe('replay');
    expect(plausible({ ...base, rp: { ...rp, n: 10 } }, NOW)).toBe('replay');
    expect(parseDigest(rp, 2)).toEqual(rp);
    expect(parseDigest({ ...rp, pl: [6] }, 2)).toBeNull();
    expect(parseDigest({ ...rp, lp: [1, 'x'] }, 2)).toBeNull();
    expect(parseDigest([1, 2], 2)).toBeNull();
  });
  test('best per player keeps one row each, fastest first', () => {
    const base = { cat: 'ante2', deck: 'b_red', stake: 1, seed_type: 'random', seed: 'A', splits: [1, 2], v: 1 };
    const rows: SpeedrunRow[] = [
      { ...base, id: '1', pkey: KEY_A, name: 'a', time: 150, at: 1 },
      { ...base, id: '2', pkey: KEY_A, name: 'a', time: 130, at: 2 },
      { ...base, id: '3', pkey: KEY_B, name: 'b', time: 140, at: 3 },
    ];
    expect(bestPerPlayer(rows).map(r => r.id)).toEqual(['2', '3']);
  });
  test('memory store unless the ranked store is d1', () => {
    expect(speedrunStoreFor(null).kind).toBe('memory');
    expect(speedrunStoreFor({ kind: 'd1', query: async () => [], write: () => undefined }).kind).toBe('d1');
  });
});

describe('speedrun service', () => {
  test('two players on one board, sorted, one submit per run', async () => {
    const svc = service();
    const a: Sock = { name: 'Alice', pkey: KEY_A, out: [] };
    const b: Sock = { name: 'Bob', pkey: KEY_B, out: [] };
    const r1 = run({ time: 130, splits: [60, 130] });
    await svc.handle(a, { type: 'speedrun_submit', run: r1 });
    expect(a.out.at(-1)).toMatchObject({ type: 'speedrun_submitted', ok: true, rank: 1 });
    await svc.handle(a, { type: 'speedrun_submit', run: r1 });
    expect(a.out.at(-1)).toMatchObject({ ok: true, duplicate: true });
    await svc.handle(b, { type: 'speedrun_submit', run: run({ time: 110, splits: [50, 110] }) });
    expect(b.out.at(-1)).toMatchObject({ ok: true, rank: 1 });
    await svc.handle(a, { type: 'speedrun_submit', run: run({ time: 150, splits: [70, 150] }) });
    await svc.handle(a, { type: 'speedrun_board', cat: 'ante2' });
    const board = a.out.at(-1) as { rows: { name: string; time: number; mine: boolean }[]; total: number; my_rank: number };
    expect(board.rows.map(r => [r.name, r.time, r.mine])).toEqual([['Bob', 110, false], ['Alice', 130, true]]);
    expect(board.total).toBe(2);
    expect(board.my_rank).toBe(2);
    expect(JSON.stringify(board)).not.toContain(KEY_A);
  });
  test('filters by deck, stake and seed type', async () => {
    const svc = service();
    const a: Sock = { name: 'Alice', pkey: KEY_A, out: [] };
    await svc.handle(a, { type: 'speedrun_submit', run: run({ deck: 'b_blue', time: 125, splits: [60, 125] }) });
    await svc.handle(a, { type: 'speedrun_submit', run: run({ stake: 3, time: 126, splits: [60, 126] }) });
    await svc.handle(a, { type: 'speedrun_board', cat: 'ante2', deck: 'b_blue' });
    expect((a.out.at(-1) as { rows: { deck: string }[] }).rows.map(r => r.deck)).toEqual(['b_blue']);
    await svc.handle(a, { type: 'speedrun_board', cat: 'ante2', stake: 3 });
    expect((a.out.at(-1) as { rows: { stake: number }[] }).rows.map(r => r.stake)).toEqual([3]);
    await svc.handle(a, { type: 'speedrun_board', cat: 'ante2', seed_type: 'weekly' });
    expect((a.out.at(-1) as { rows: unknown[] }).rows).toEqual([]);
  });
  test('refuses players without identity, impossible runs and floods', async () => {
    const svc = service();
    const anon: Sock = { name: 'Anon', out: [] };
    await svc.handle(anon, { type: 'speedrun_submit', run: run() });
    expect(anon.out.at(-1)).toMatchObject({ ok: false, reason: 'no_identity' });
    const a: Sock = { name: 'Alice', pkey: KEY_A, out: [] };
    await svc.handle(a, { type: 'speedrun_submit', run: run({ time: 15, splits: [5, 15] }) });
    expect(a.out.at(-1)).toMatchObject({ ok: false, reason: 'too_fast' });
    await svc.handle(a, { type: 'speedrun_submit', run: run({ rp: { n: 3 } }) });
    expect(a.out.at(-1)).toMatchObject({ ok: false, reason: 'replay' });
    await svc.handle(a, { type: 'speedrun_submit', run: run({ rp: { n: 20, pl: [6, 6], bs: [3, 3], fb: [1, 61], lp: [59, 119] } }) });
    expect(a.out.at(-1)).toMatchObject({ ok: true });
    for (let i = 0; i < SR_SUBMITS_PER_HOUR; i++) await svc.handle(a, { type: 'speedrun_submit', run: run() });
    await svc.handle(a, { type: 'speedrun_submit', run: run() });
    expect(a.out.at(-1)).toMatchObject({ ok: false, reason: 'rate_limited' });
  });
});

function pack(time: number, entries: unknown[] = [{ k: 'start' }, { k: 'pl', t: 1000 }]): { z: string; n: number } {
  const raw = Buffer.from(JSON.stringify({ v: 1, id: 'x', entries, x: { sr: { cat: 'ante2', time } } }), 'utf8');
  return { z: Buffer.from(deflateSync(raw)).toString('base64'), n: raw.length };
}

describe('speedrun replays', () => {
  test('validation keeps the size cap and base64 only', () => {
    const p = pack(120);
    expect(validateSpeedrun({ type: 'speedrun_replay_put', id: 'abcdefgh12', z: p.z, n: p.n })).toBeNull();
    expect(validateSpeedrun({ type: 'speedrun_replay_put', id: 'abcdefgh12', z: 'A'.repeat(SR_REPLAY_MAX_B64 + 4), n: 10 })).toContain('z');
    expect(validateSpeedrun({ type: 'speedrun_replay_put', id: 'abcdefgh12', z: 'not base64!', n: 10 })).toContain('z');
    expect(validateSpeedrun({ type: 'speedrun_replay_put', id: 'abcdefgh12', z: p.z, n: 0 })).toContain('n');
    expect(validateSpeedrun({ type: 'speedrun_replay_get', id: 'x' })).toContain('id');
    expect(SPEEDRUN_BIG_TYPES).toContain('speedrun_replay_put');
    expect(SR_REPLAY_MSG_BYTES).toBeGreaterThan(SR_REPLAY_MAX_B64);
    expect(readReplay(p.z, p.n)?.time).toBe(120);
    expect(readReplay(p.z, p.n + 1)).toBeNull();
    expect(readReplay('AAAA', 3)).toBeNull();
  });
  test('upload after the submit, board flags it, anyone can fetch it', async () => {
    const svc = service();
    const a: Sock = { name: 'Alice', pkey: KEY_A, out: [] };
    const b: Sock = { name: 'Bob', pkey: KEY_B, out: [] };
    const r1 = run({ time: 130, splits: [60, 130] });
    const p = pack(130);
    await svc.handle(a, { type: 'speedrun_replay_put', id: r1.id, ...p });
    expect(a.out.at(-1)).toMatchObject({ type: 'speedrun_replay_saved', ok: false, reason: 'no_run' });
    await svc.handle(a, { type: 'speedrun_submit', run: r1 });
    await svc.handle(a, { type: 'speedrun_replay_put', id: r1.id, ...pack(99) });
    expect(a.out.at(-1)).toMatchObject({ ok: false, reason: 'replay_data' });
    await svc.handle(b, { type: 'speedrun_replay_put', id: r1.id, ...p });
    expect(b.out.at(-1)).toMatchObject({ ok: false, reason: 'no_run' });
    await svc.handle(a, { type: 'speedrun_replay_put', id: r1.id, ...p });
    expect(a.out.at(-1)).toMatchObject({ type: 'speedrun_replay_saved', id: r1.id, ok: true });
    await svc.handle(b, { type: 'speedrun_board', cat: 'ante2' });
    const board = b.out.at(-1) as { rows: { id: string; rp: boolean }[] };
    expect(board.rows[0]).toMatchObject({ id: r1.id, rp: true });
    await svc.handle(b, { type: 'speedrun_replay_get', id: r1.id });
    expect(b.out.at(-1)).toMatchObject({ type: 'speedrun_replay', id: r1.id, ok: true, z: p.z, n: p.n, name: 'Alice', time: 130 });
    await svc.handle(b, { type: 'speedrun_replay_get', id: 'nothere123' });
    expect(b.out.at(-1)).toMatchObject({ ok: false, reason: 'missing' });
  });
  test('keeps one replay per player and setup, refuses a slower run', async () => {
    const svc = service();
    const a: Sock = { name: 'Alice', pkey: KEY_A, out: [] };
    const slow = run({ time: 140, splits: [70, 140] });
    const fast = run({ time: 125, splits: [60, 125] });
    await svc.handle(a, { type: 'speedrun_submit', run: slow });
    await svc.handle(a, { type: 'speedrun_replay_put', id: slow.id, ...pack(140) });
    expect(a.out.at(-1)).toMatchObject({ ok: true });
    await svc.handle(a, { type: 'speedrun_submit', run: fast });
    await svc.handle(a, { type: 'speedrun_replay_put', id: fast.id, ...pack(125) });
    expect(a.out.at(-1)).toMatchObject({ ok: true });
    await svc.handle(a, { type: 'speedrun_replay_get', id: slow.id });
    expect(a.out.at(-1)).toMatchObject({ ok: false, reason: 'missing' });
    await svc.handle(a, { type: 'speedrun_replay_put', id: slow.id, ...pack(140) });
    expect(a.out.at(-1)).toMatchObject({ ok: false, reason: 'not_best' });
    const anon: Sock = { name: 'Anon', out: [] };
    await svc.handle(anon, { type: 'speedrun_replay_put', id: fast.id, ...pack(125) });
    expect(anon.out.at(-1)).toMatchObject({ ok: false, reason: 'no_identity' });
    for (let i = 0; i < SR_REPLAY_GETS_PER_HOUR; i++) await svc.handle(anon, { type: 'speedrun_replay_get', id: fast.id });
    await svc.handle(anon, { type: 'speedrun_replay_get', id: fast.id });
    expect(anon.out.at(-1)).toMatchObject({ ok: false, reason: 'rate_limited' });
  });
});
