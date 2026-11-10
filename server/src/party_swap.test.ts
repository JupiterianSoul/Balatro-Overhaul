import { describe, expect, test } from 'bun:test';
import { newPartySwap, partySwapOn, handlePartySwapState, handlePartySwapApplied, handlePartySwapReady, partyHoldsSnapshot, partySwapStatus, trySwap, type PartySwapIO } from './party_swap';

const B64 = (s: string) => Buffer.from(s).toString('base64');
const NAMES = ['Ann', 'Bob', 'Cid', 'Dee'];

function setup(members: number[]) {
  const st = newPartySwap();
  const sent: { pid: number; p: Record<string, unknown> }[] = [];
  const snaps: Record<number, string> = {};
  const alive = { list: [...members] };
  const io: PartySwapIO = {
    members: () => alive.list,
    name: pid => NAMES[pid],
    send: (pid, p) => { sent.push({ pid, p }); },
    setSnapshot: (pid, data) => { snaps[pid] = data; },
    log: () => {},
  };
  const runs = () => sent.filter(x => x.p.type === 'swap_run');
  return { st, sent, snaps, alive, io, runs };
}

describe('party switcheroo rotation', () => {
  test('only on for a Battle Royale party with the toggle', () => {
    expect(partySwapOn({ party_swap: true })).toBe(true);
    expect(partySwapOn({ party_swap: true, party_kind: 'br' })).toBe(true);
    expect(partySwapOn({ party_swap: true, party_kind: 'teams' })).toBe(false);
    expect(partySwapOn({ party_kind: 'br' })).toBe(false);
    expect(partySwapOn(undefined)).toBe(false);
  });

  test('three players: each run moves to the next seat', () => {
    const { st, sent, snaps, io, runs } = setup([0, 1, 2]);
    handlePartySwapState(st, 0, { round: 1, data: B64('run-a'), hash: 'ha', ante: 2 }, io);
    expect(sent).toEqual([{ pid: 0, p: { type: 'swap_waiting', party: true, round: 1, waiting: ['Bob', 'Cid'], ready: 1, total: 3, from: null, notReady: [], readyIds: [0], pressed: 1 } }]);
    expect(partyHoldsSnapshot(st, 0)).toBe(true);
    handlePartySwapState(st, 2, { round: 1, data: B64('run-c'), hash: 'hc', ante: 2 }, io);
    expect(runs().length).toBe(0);
    handlePartySwapState(st, 1, { round: 1, data: B64('run-b'), hash: 'hb', ante: 2 }, io);
    expect(runs().length).toBe(3);
    const got = (pid: number) => runs().find(x => x.pid === pid)!.p;
    expect(got(1)).toMatchObject({ round: 1, data: B64('run-a'), from: 'Ann', fromId: 0, mine: 'hb' });
    expect(got(2)).toMatchObject({ round: 1, data: B64('run-b'), from: 'Bob', fromId: 1, mine: 'hc' });
    expect(got(0)).toMatchObject({ round: 1, data: B64('run-c'), from: 'Cid', fromId: 2, mine: 'ha' });
    expect(snaps).toEqual({ 0: B64('run-c'), 1: B64('run-a'), 2: B64('run-b') });
    expect(st.done).toBe(1);
  });

  test('two rotations bring each run two seats along', () => {
    const { st, io, runs } = setup([0, 1, 2]);
    for (const [pid, d] of [[0, 'a'], [1, 'b'], [2, 'c']] as const) handlePartySwapState(st, pid, { round: 1, data: B64(d), hash: d }, io);
    for (const [pid, d] of [[0, 'c'], [1, 'a'], [2, 'b']] as const) handlePartySwapState(st, pid, { round: 2, data: B64(d), hash: d }, io);
    const second = runs().filter(x => x.p.round === 2);
    expect(second.find(x => x.pid === 0)!.p.data).toBe(B64('b'));
    expect(second.find(x => x.pid === 1)!.p.data).toBe(B64('c'));
    expect(second.find(x => x.pid === 2)!.p.data).toBe(B64('a'));
  });

  test('an eliminated player leaves the ring and the swap goes on without them', () => {
    const { st, io, alive, runs } = setup([0, 1, 2, 3]);
    handlePartySwapState(st, 0, { round: 1, data: B64('a'), hash: 'a' }, io);
    handlePartySwapState(st, 1, { round: 1, data: B64('b'), hash: 'b' }, io);
    handlePartySwapState(st, 3, { round: 1, data: B64('d'), hash: 'd' }, io);
    expect(runs().length).toBe(0);
    alive.list = [0, 1, 3];
    expect(trySwap(st, io)).toBe(true);
    const got = (pid: number) => runs().find(x => x.pid === pid)!.p;
    expect(got(0).data).toBe(B64('d'));
    expect(got(1).data).toBe(B64('a'));
    expect(got(3).data).toBe(B64('b'));
    expect(runs().some(x => x.pid === 2)).toBe(false);
  });

  test('a run sent by a player who is then knocked out is dropped', () => {
    const { st, io, alive, runs } = setup([0, 1, 2]);
    handlePartySwapState(st, 2, { round: 1, data: B64('c'), hash: 'c' }, io);
    alive.list = [0, 1];
    handlePartySwapState(st, 0, { round: 1, data: B64('a'), hash: 'a' }, io);
    handlePartySwapState(st, 1, { round: 1, data: B64('b'), hash: 'b' }, io);
    expect(runs().map(x => [x.pid, x.p.data])).toEqual([[0, B64('b')], [1, B64('a')]]);
    expect(st.seats[2].data).toBeNull();
  });

  test('ignores knocked out players, stale and future rounds', () => {
    const { st, io, alive, sent } = setup([0, 1, 2]);
    alive.list = [0, 1];
    handlePartySwapState(st, 2, { round: 1, data: B64('c') }, io);
    handlePartySwapState(st, 0, { round: 3, data: B64('a') }, io);
    expect(sent.length).toBe(0);
    expect(st.seats[2]).toBeUndefined();
  });

  test('a resend after the swap gets the same run back', () => {
    const { st, io, runs } = setup([0, 1, 2]);
    for (const [pid, d] of [[0, 'a'], [1, 'b'], [2, 'c']] as const) handlePartySwapState(st, pid, { round: 1, data: B64(d), hash: d }, io);
    handlePartySwapState(st, 1, { round: 1, data: B64('b'), hash: 'b' }, io);
    const again = runs().filter(x => x.pid === 1);
    expect(again.length).toBe(2);
    expect(again[1].p.data).toBe(B64('a'));
  });

  test('a lone human keeps their own run', () => {
    const { st, io, runs } = setup([1]);
    handlePartySwapState(st, 1, { round: 1, data: B64('b'), hash: 'b' }, io);
    expect(runs().map(x => [x.pid, x.p.data, x.p.from])).toEqual([[1, B64('b'), 'Bob']]);
  });

  test('snapshot uploads wait for the load, rejoin status follows', () => {
    const { st, io } = setup([0, 1, 2]);
    expect(partySwapStatus(undefined, 0)).toBeNull();
    for (const [pid, d] of [[0, 'a'], [1, 'b'], [2, 'c']] as const) handlePartySwapState(st, pid, { round: 1, data: B64(d), hash: d, ante: 3 }, io);
    expect(partyHoldsSnapshot(st, 0)).toBe(true);
    expect(partySwapStatus(st, 0)).toEqual({ done: 1, applied: 0, sent: false, ante: 3 });
    handlePartySwapApplied(st, 0, { round: 1 }, io);
    expect(partyHoldsSnapshot(st, 0)).toBe(false);
    expect(partySwapStatus(st, 0)).toMatchObject({ applied: 1 });
    handlePartySwapApplied(st, 0, { round: 5 }, io);
    expect(st.seats[0].applied).toBe(1);
  });

  test('ready screen: the rotation waits until every player pressed Ready', () => {
    const { st, sent, io, runs } = setup([0, 1, 2]);
    handlePartySwapState(st, 0, { round: 1, data: B64('a'), v: 2 }, io);
    handlePartySwapState(st, 1, { round: 1, data: B64('b'), v: 2 }, io);
    handlePartySwapState(st, 2, { round: 1, data: B64('c') }, io);
    expect(runs().length).toBe(0);
    const last = sent[sent.length - 1].p;
    expect(last).toMatchObject({ type: 'swap_waiting', waiting: [], notReady: ['Ann', 'Bob'], pressed: 1 });
    handlePartySwapReady(st, 0, { round: 1 }, io);
    handlePartySwapReady(st, 0, { round: 2 }, io);
    expect(runs().length).toBe(0);
    handlePartySwapReady(st, 1, { round: 1 }, io);
    expect(runs().length).toBe(3);
    expect(runs()[0].p.countdown).toBe(3);
    expect(st.seats[0].ready).toBe(false);
  });

  test('ready screen: a ready before sending is ignored', () => {
    const { st, io, runs } = setup([0, 1]);
    handlePartySwapReady(st, 0, { round: 1 }, io);
    handlePartySwapState(st, 0, { round: 1, data: B64('a'), v: 2 }, io);
    handlePartySwapState(st, 1, { round: 1, data: B64('b'), v: 2 }, io);
    handlePartySwapReady(st, 1, { round: 1 }, io);
    expect(runs().length).toBe(0);
    handlePartySwapReady(st, 0, { round: 1 }, io);
    expect(runs().length).toBe(2);
  });
});
