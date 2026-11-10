import { describe, expect, test } from 'bun:test';
import { handleSwapState, handleSwapApplied, handleSwapReady, handleBotSwapState, holdsSnapshot, swapStatus, validateSwap, type SwapMatch, type SwapIO } from './swap';

function setup(mode = 'swap') {
  const m: SwapMatch = { mode, phase: 'playing', players: [{}, {}] };
  const sent: { pid: number; p: Record<string, unknown> }[] = [];
  const snaps: (string | null)[] = [null, null];
  const io: SwapIO = {
    send: (pid, p) => { sent.push({ pid, p }); },
    setSnapshot: (pid, data) => { snaps[pid] = data; },
    names: () => ['Ann', 'Bob'],
    log: () => {},
  };
  return { m, sent, snaps, io };
}

const B64 = (s: string) => Buffer.from(s).toString('base64');

describe('swap mode exchange', () => {
  test('validates payloads', () => {
    expect(validateSwap({ type: 'swap_state', round: 1, data: B64('run-a') })).toBeNull();
    expect(validateSwap({ type: 'swap_state', round: 0, data: B64('x') })).toContain('round');
    expect(validateSwap({ type: 'swap_state', round: 1, data: 'not base64!' })).toContain('base64');
    expect(validateSwap({ type: 'swap_state', round: 1 })).toContain('missing');
    expect(validateSwap({ type: 'swap_state', round: 1, data: B64('x'), hash: 'h'.repeat(65) })).toContain('hash');
    expect(validateSwap({ type: 'swap_applied', round: 1.5 })).toContain('round');
  });

  test('waits for both players, then each gets the other run', () => {
    const { m, sent, snaps, io } = setup();
    handleSwapState(m, 0, { round: 1, data: B64('run-a'), hash: 'ha', ante: 2 }, io);
    expect(sent).toEqual([{ pid: 1, p: { type: 'swap_waiting', round: 1, from: 'Ann' } }]);
    expect(holdsSnapshot(m, 0)).toBe(true);
    expect(holdsSnapshot(m, 1)).toBe(false);
    handleSwapState(m, 1, { round: 1, data: B64('run-b'), hash: 'hb', ante: 2 }, io);
    const runs = sent.filter(x => x.p.type === 'swap_run');
    expect(runs.length).toBe(2);
    expect(runs.find(x => x.pid === 0)!.p).toMatchObject({ round: 1, data: B64('run-b'), hash: 'hb', from: 'Bob', mine: 'ha' });
    expect(runs.find(x => x.pid === 1)!.p).toMatchObject({ round: 1, data: B64('run-a'), hash: 'ha', from: 'Ann', mine: 'hb' });
    expect(snaps).toEqual([B64('run-b'), B64('run-a')]);
    expect(m.swapDone).toBe(1);
    expect(holdsSnapshot(m, 0)).toBe(true);
    handleSwapApplied(m, 0, { round: 1 }, io);
    handleSwapApplied(m, 1, { round: 1 }, io);
    expect(holdsSnapshot(m, 0)).toBe(false);
    expect(holdsSnapshot(m, 1)).toBe(false);
  });

  test('three swaps move each run back and forth', () => {
    const { m, sent, io } = setup();
    const own = ['A1', 'B1'];
    for (let r = 1; r <= 3; r++) {
      handleSwapState(m, 1, { round: r, data: B64(own[1]), hash: own[1] }, io);
      handleSwapState(m, 0, { round: r, data: B64(own[0]), hash: own[0] }, io);
      const got = [0, 1].map(p => sent.filter(x => x.pid === p && x.p.type === 'swap_run' && x.p.round === r)[0].p.hash as string);
      expect(got).toEqual([own[1], own[0]]);
      own[0] = `${got[0]}>${r}`;
      own[1] = `${got[1]}>${r}`;
      handleSwapApplied(m, 0, { round: r }, io);
      handleSwapApplied(m, 1, { round: r }, io);
    }
    expect(m.swapDone).toBe(3);
    expect(m.swapLog!.map(x => x.round)).toEqual([1, 2, 3]);
  });

  test('a repeated round is answered again, a skipped round is ignored', () => {
    const { m, sent, io } = setup();
    handleSwapState(m, 0, { round: 1, data: B64('a'), hash: 'ha' }, io);
    handleSwapState(m, 1, { round: 1, data: B64('b'), hash: 'hb' }, io);
    sent.length = 0;
    handleSwapState(m, 1, { round: 1, data: B64('b'), hash: 'hb' }, io);
    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({ pid: 1, p: { type: 'swap_run', round: 1, hash: 'ha' } });
    sent.length = 0;
    handleSwapState(m, 0, { round: 3, data: B64('a'), hash: 'ha' }, io);
    expect(sent).toHaveLength(0);
    expect(m.players[0].swapData).toBeFalsy();
  });

  test('other modes and finished matches never swap', () => {
    const a = setup('nemesis');
    handleSwapState(a.m, 0, { round: 1, data: B64('a') }, a.io);
    expect(a.sent[0].p.type).toBe('error');
    expect(holdsSnapshot(a.m, 0)).toBe(false);
    expect(swapStatus(a.m, 0)).toBeNull();
    const b = setup();
    b.m.phase = 'finished';
    handleSwapState(b.m, 0, { round: 1, data: B64('a') }, b.io);
    expect(b.sent).toHaveLength(0);
  });

  test('status reports what each side sent', () => {
    const { m, io } = setup();
    handleSwapState(m, 1, { round: 1, data: B64('b') }, io);
    expect(swapStatus(m, 0)).toEqual({ done: 0, applied: 0, sent: false, oppSent: true, ante: 0, ready: false, oppReady: true });
    expect(swapStatus(m, 1)).toEqual({ done: 0, applied: 0, sent: true, oppSent: false, ante: 0, ready: true, oppReady: false });
  });

  test('ready screen: the swap waits until both players press ready', () => {
    const { m, sent, io } = setup();
    const fa = { owner: 'Ann', dollars: 12, deck: 52 };
    const fb = { owner: 'Bob', dollars: 30, deck: 54 };
    handleSwapState(m, 0, { round: 1, data: B64('a'), hash: 'ha', v: 2, facts: fa }, io);
    expect(sent.map(x => [x.pid, x.p.type])).toEqual([[1, 'swap_waiting'], [0, 'swap_status']]);
    expect(sent[1].p).toMatchObject({ ready: false, oppSent: false, oppReady: false, oppFacts: null, from: 'Bob' });
    sent.length = 0;
    handleSwapState(m, 1, { round: 1, data: B64('b'), hash: 'hb', v: 2, facts: fb }, io);
    expect(sent.filter(x => x.p.type === 'swap_run')).toHaveLength(0);
    expect(sent.find(x => x.pid === 0)!.p).toMatchObject({ type: 'swap_status', oppSent: true, oppReady: false, oppFacts: fb });
    expect(sent.find(x => x.pid === 1)!.p).toMatchObject({ type: 'swap_status', oppSent: true, oppReady: false, oppFacts: fa });
    sent.length = 0;
    handleSwapReady(m, 0, { round: 1 }, io);
    expect(sent.filter(x => x.p.type === 'swap_run')).toHaveLength(0);
    expect(sent.find(x => x.pid === 1)!.p).toMatchObject({ type: 'swap_status', oppReady: true, ready: false });
    expect(swapStatus(m, 1)).toMatchObject({ ready: false, oppReady: true });
    handleSwapReady(m, 0, { round: 1 }, io);
    sent.length = 0;
    handleSwapReady(m, 1, { round: 1 }, io);
    const runs = sent.filter(x => x.p.type === 'swap_run');
    expect(runs.map(x => [x.pid, x.p.hash, x.p.countdown])).toEqual([[0, 'hb', 3], [1, 'ha', 3]]);
    expect(m.swapDone).toBe(1);
    expect(m.players[0].swapReady).toBe(false);
    expect(m.players[0].swapFacts).toBeNull();
  });

  test('ready screen: a ready before sending or for another round is ignored', () => {
    const { m, sent, io } = setup();
    handleSwapReady(m, 0, { round: 1 }, io);
    expect(m.players[0].swapReady).toBeFalsy();
    handleSwapState(m, 0, { round: 1, data: B64('a'), v: 2 }, io);
    handleSwapState(m, 1, { round: 1, data: B64('b'), v: 2 }, io);
    handleSwapReady(m, 0, { round: 2 }, io);
    handleSwapReady(m, 1, { round: 2 }, io);
    expect(sent.filter(x => x.p.type === 'swap_run')).toHaveLength(0);
  });

  test('ready screen: an older client counts as ready, the newer one still presses', () => {
    const { m, sent, io } = setup();
    handleSwapState(m, 1, { round: 1, data: B64('b'), hash: 'hb' }, io);
    handleSwapState(m, 0, { round: 1, data: B64('a'), hash: 'ha', v: 2 }, io);
    expect(sent.filter(x => x.p.type === 'swap_run')).toHaveLength(0);
    expect(sent.filter(x => x.pid === 1 && x.p.type === 'swap_status')).toHaveLength(0);
    expect(sent.find(x => x.pid === 0 && x.p.type === 'swap_status')!.p).toMatchObject({ oppSent: true, oppReady: true });
    handleSwapReady(m, 0, { round: 1 }, io);
    expect(sent.filter(x => x.p.type === 'swap_run')).toHaveLength(2);
  });

  test('ready screen: a resent state after a reconnect asks for ready again', () => {
    const { m, sent, io } = setup();
    handleSwapState(m, 0, { round: 1, data: B64('a'), v: 2 }, io);
    handleSwapReady(m, 0, { round: 1 }, io);
    handleSwapState(m, 0, { round: 1, data: B64('a'), v: 2 }, io);
    expect(m.players[0].swapReady).toBe(false);
    handleSwapReady(m, 0, { round: 1 }, io);
    handleSwapState(m, 1, { round: 1, data: B64('b'), v: 2 }, io);
    handleSwapReady(m, 1, { round: 1 }, io);
    expect(sent.filter(x => x.p.type === 'swap_run')).toHaveLength(2);
  });

  test('validates the ready screen fields', () => {
    expect(validateSwap({ type: 'swap_state', round: 1, data: B64('a'), v: 2, facts: { dollars: 4 } })).toBeNull();
    expect(validateSwap({ type: 'swap_state', round: 1, data: B64('a'), v: -1 })).toContain('v');
    expect(validateSwap({ type: 'swap_state', round: 1, data: B64('a'), facts: [1] })).toContain('facts');
    expect(validateSwap({ type: 'swap_state', round: 1, data: B64('a'), facts: { x: 'y'.repeat(2000) } })).toContain('facts');
    expect(validateSwap({ type: 'swap_ready', round: 0 })).toContain('round');
    expect(validateSwap({ type: 'swap_ready', round: 2 })).toBeNull();
  });

  test('a bot opponent gives its own run and takes the human run', () => {
    const { m, sent, io } = setup();
    const human = { owner: 'Ann', dollars: 9, jokers: [{ k: 'j_joker' }] };
    handleSwapState(m, 0, { round: 1, data: B64('run-a'), hash: 'ha', ante: 2, v: 2, run: human }, io);
    handleSwapReady(m, 0, { round: 1 }, io);
    expect(sent.filter(x => x.p.type === 'swap_run')).toHaveLength(0);
    const botRun = { owner: 'Bob', dollars: 4, jokers: [{ k: 'j_egg' }] };
    expect(handleBotSwapState(m, 1, { round: 1, data: B64('run-a'), hash: 'ha', ante: 2, run: botRun, facts: { owner: 'Bob', dollars: 4 } }, io)).toBe(true);
    const status = sent.filter(x => x.p.type === 'swap_status' && x.pid === 0).pop()!.p;
    expect(status).toMatchObject({ oppSent: true, oppReady: true, oppFacts: { owner: 'Bob', dollars: 4 } });
    const runs = sent.filter(x => x.p.type === 'swap_run');
    expect(runs.find(x => x.pid === 0)!.p).toMatchObject({ round: 1, from: 'Bob', bot_run: botRun });
    expect(runs.find(x => x.pid === 1)!.p.bot_run).toBeUndefined();
    expect(m.swapDone).toBe(1);
    expect(m.players[1].swapRun).toBeNull();
    expect(handleBotSwapState(m, 1, { round: 1, data: B64('run-a'), hash: 'ha', ante: 2, run: botRun, facts: {} }, io)).toBe(false);
  });

  test('validates the bot run field', () => {
    expect(validateSwap({ type: 'swap_state', round: 1, data: B64('a'), run: { dollars: 1 } })).toBeNull();
    expect(validateSwap({ type: 'swap_state', round: 1, data: B64('a'), run: [1] })).toContain('run');
    expect(validateSwap({ type: 'swap_state', round: 1, data: B64('a'), run: { x: 'y'.repeat(100 * 1024) } })).toContain('run');
  });
});
