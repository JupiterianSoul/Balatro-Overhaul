import { describe, it, expect, afterAll } from 'bun:test';
import { startServer } from './index';

const srv = startServer(0);
afterAll(() => srv.stop(true));

type Msg = Record<string, unknown>;
interface C { msgs: Msg[]; send: (m: Msg) => void; wait: (pred: (m: Msg) => boolean, ms?: number) => Promise<Msg>; close: () => void }

let uid = 0;
const nm = (p: string) => `${p}${++uid}h${Math.floor(Math.random() * 1e5)}`;

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
  await new Promise<void>((resolve, reject) => { ws.onopen = () => resolve(); ws.onerror = () => reject(new Error('ws error')); });
  return {
    msgs,
    send: (m) => ws.send(JSON.stringify(m)),
    wait: (pred, ms = 2000) => {
      const hit = msgs.find(pred);
      if (hit) return Promise.resolve(hit);
      return new Promise<Msg>((resolve, reject) => {
        const t = setTimeout(() => reject(new Error('timed out waiting for message')), ms);
        waiters.push({ pred, resolve: (m) => { clearTimeout(t); resolve(m); } });
      });
    },
    close: () => ws.close(),
  };
}

const is = (type: string, extra?: (m: Msg) => boolean) => (m: Msg) => m.type === type && (!extra || extra(m));

describe('in-run scoreboard data', () => {
  it('play_hand reaches the opponent with score, hands and discards left', async () => {
    const host = await connect();
    const guest = await connect();
    host.send({ type: 'create_room', name: nm('HudHost') });
    const created = await host.wait(is('room_created'));
    guest.send({ type: 'join_room', code: created.code, name: nm('HudGuest') });
    await guest.wait(is('room_ready'));
    await host.wait(is('room_ready'));
    host.send({ type: 'match_start', seed: 'HUD1', settings: { mode: 'nemesis', starting_lives: 2, pvp_start_round: 2, win_ante: 3 }, player_name: 'HudHostX' });
    await guest.wait(is('match_start'));
    host.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    guest.send({ type: 'blind_entered', ante: 2, blind: 'L' });
    host.send({ type: 'play_hand', score: '0', hands_left: 4, discards_left: 3 });
    const start = await guest.wait(is('enemy_info', (m) => m.score === '0'));
    expect(start).toMatchObject({ hands_left: 4, discards_left: 3 });
    host.send({ type: 'play_hand', score: '1234', hands_left: 3, discards_left: 1 });
    const after = await guest.wait(is('enemy_info', (m) => m.score === '1234'));
    expect(after).toMatchObject({ hands_left: 3, discards_left: 1 });
    guest.send({ type: 'play_hand', score: '50', hands_left: 2 });
    const old = await host.wait(is('enemy_info', (m) => m.score === '50'));
    expect(old.hands_left).toBe(2);
    expect('discards_left' in old).toBe(false);
    host.close();
    guest.close();
  });
});
