import { describe, it, expect, afterAll } from 'bun:test';
import { startServer, sanitizeSettings, finalAnteFor, rollMatchExtras, RANDOM_STAKE_MAX } from './index';

type Msg = Record<string, unknown>;
const srv = startServer(0);
afterAll(() => srv.stop(true));

interface C { send: (m: Msg) => void; wait: (t: string, f?: (m: Msg) => boolean, ms?: number) => Promise<Msg>; close: () => void; }

let uid = 0;
const nm = () => `Mt${++uid}x${Math.floor(Math.random() * 1e6)}`;

function decode(raw: string): Msg {
  const parsed = JSON.parse(raw) as Msg;
  if (parsed.z === 1 && typeof parsed.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(parsed.d, 'base64'))).toString('utf8')) as Msg;
  return parsed;
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
  const wait = (t: string, f: (m: Msg) => boolean = () => true, ms = 3000) => {
    const pred = (m: Msg) => m.type === t && f(m);
    const i = msgs.findIndex(pred);
    if (i >= 0) return Promise.resolve(msgs.splice(i, 1)[0]);
    return new Promise<Msg>((res, rej) => {
      const to = setTimeout(() => rej(new Error('timeout ' + t)), ms);
      waiters.push({ pred, resolve: (m) => { clearTimeout(to); msgs.splice(msgs.indexOf(m), 1); res(m); } });
    });
  };
  return { send: (m) => ws.send(JSON.stringify(m)), wait, close: () => ws.close() };
}

async function room(): Promise<[C, C]> {
  const host = await connect();
  const guest = await connect();
  host.send({ type: 'create_room', visibility: 'public', name: nm() });
  const created = await host.wait('room_created');
  guest.send({ type: 'join_room', code: created.code, name: nm() });
  await guest.wait('room_ready');
  await host.wait('room_ready');
  return [host, guest];
}

describe('random stake setting', () => {
  it('keeps "random" as a stake value and clamps the rolled stake', () => {
    const s = sanitizeSettings({ stake: 'random', rolled_stake: 40, match_roll: 'ABC', pvp_boss_effect: true, hide_opp_score: 'x' })!;
    expect(s.stake).toBe('random');
    expect(s.rolled_stake).toBe(RANDOM_STAKE_MAX);
    expect(s.match_roll).toBe('ABC');
    expect(s.pvp_boss_effect).toBe(true);
    expect(s.hide_opp_score).toBeUndefined();
    expect(sanitizeSettings({ stake: 'gold' })!.stake).toBeUndefined();
    expect(sanitizeSettings({ stake: 3 })!.stake).toBe(3);
  });

  it('rolls a real stake from 1 to 8, keeps a valid host roll, drops it for a fixed stake', () => {
    const seen = new Set<number>();
    for (let i = 0; i < 400; i++) {
      const s: Msg = { stake: 'random' };
      rollMatchExtras(s, 'SEED1');
      const r = s.rolled_stake as number;
      expect(Number.isInteger(r) && r >= 1 && r <= 8).toBe(true);
      seen.add(r);
      expect(s.match_roll).toBe('SEED1');
    }
    expect(seen.size).toBe(8);
    const kept: Msg = { stake: 'random' };
    rollMatchExtras(kept, 'S', { rolled_stake: 5, match_roll: 'HOSTROLL' });
    expect(kept.rolled_stake).toBe(5);
    expect(kept.match_roll).toBe('HOSTROLL');
    const fixed: Msg = { stake: 4, rolled_stake: 6 };
    rollMatchExtras(fixed, 'S');
    expect(fixed.rolled_stake).toBeUndefined();
  });

  it('uses the rolled stake for the automatic final ante', () => {
    expect(finalAnteFor({ stake: 'random', rolled_stake: 3 })).toBe(8);
    expect(finalAnteFor({ stake: 'random', rolled_stake: 10 })).toBe(11);
    expect(finalAnteFor({ stake: 'random', rolled_stake: 3, win_ante: 5 })).toBe(5);
  });

  it('sends the host roll to the guest at match start, and a fresh shared roll on rematch', async () => {
    const [host, guest] = await room();
    host.send({ type: 'match_start', seed: 'RSTK1', settings: { mode: 'nemesis', starting_lives: 2, stake: 'random', rolled_stake: 6, match_roll: 'RSTK1', pvp_boss_effect: true }, player_name: 'H' });
    const start = await guest.wait('match_start');
    const gs = start.settings as Msg;
    expect(gs.stake).toBe('random');
    expect(gs.rolled_stake).toBe(6);
    expect(gs.match_roll).toBe('RSTK1');
    expect(gs.pvp_boss_effect).toBe(true);
    host.send({ type: 'match_finished', result: 'lose', reason: 'forfeit' });
    await host.wait('match_ended', () => true, 5000);
    host.send({ type: 'rematch_vote' });
    guest.send({ type: 'rematch_vote' });
    const a = await host.wait('rematch_accepted', () => true, 5000);
    const b = await guest.wait('rematch_accepted', () => true, 5000);
    const sa = a.settings as Msg, sb = b.settings as Msg;
    expect(sa.stake).toBe('random');
    expect(Number.isInteger(sa.rolled_stake) && (sa.rolled_stake as number) >= 1 && (sa.rolled_stake as number) <= 8).toBe(true);
    expect(sb.rolled_stake).toBe(sa.rolled_stake);
    expect(sb.match_roll).toBe(sa.match_roll);
    expect(sa.match_roll).not.toBe('RSTK1');
    host.close(); guest.close();
  });

  it('rolls on the server when the host sent no roll', async () => {
    const [host, guest] = await room();
    host.send({ type: 'match_start', seed: 'RSTK2', settings: { mode: 'nemesis', stake: 'random' }, player_name: 'H' });
    const gs = (await guest.wait('match_start')).settings as Msg;
    expect(Number.isInteger(gs.rolled_stake)).toBe(true);
    expect(gs.match_roll).toBe('RSTK2');
    host.close(); guest.close();
  });

  it('never sends a rolled stake when the stake is fixed', async () => {
    const [host, guest] = await room();
    host.send({ type: 'match_start', seed: 'RSTK3', settings: { mode: 'nemesis', stake: 2, rolled_stake: 7 }, player_name: 'H' });
    const gs = (await guest.wait('match_start')).settings as Msg;
    expect(gs.stake).toBe(2);
    expect(gs.rolled_stake).toBeUndefined();
    host.close(); guest.close();
  });
});
