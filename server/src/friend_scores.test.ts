import { describe, it, expect, afterAll } from 'bun:test';
import { FriendScores, MemoryScores, cleanScore, BEST_PER_MIN, BOARD_TOP, BOARD_GAP_MS, type Ref } from './friend_scores';
import { startServer } from './index';

type Msg = Record<string, any>;
interface W { data: { mgBestAt?: number[]; mgBoardAt?: number }; sent: Msg[] }

function setup(friends: Record<string, string[]> = {}) {
  const clock = { t: 1_000_000 };
  const store = new MemoryScores();
  const ref = (k: string): Ref => ({ pkey: k, code: `C-${k}`, name: `N${k}` });
  const svc = new FriendScores<W>(store, {
    send: (ws, d) => { ws.sent.push(d as Msg); },
    friends: async k => (friends[k] ?? []).map(ref),
    me: ref,
  }, () => clock.t);
  const sock = (): W => ({ data: {}, sent: [] });
  return { clock, store, svc, sock };
}

describe('friend minigame scores', () => {
  it('cleans what the client sends', () => {
    expect(cleanScore({ game: 'blackjack', score: 40 })).toEqual({ game: 'blackjack', score: 40, low: false });
    expect(cleanScore({ game: 'find_ace', score: 3, low: true })).toEqual({ game: 'find_ace', score: 3, low: true });
    for (const bad of [{ game: 'Black', score: 1 }, { game: 'x'.repeat(30), score: 1 }, { game: 'a', score: -1 }, { game: 'a', score: 1.5 }, { game: 'a', score: 2e9 }, { game: 'a' }, { score: 3 }]) {
      expect(cleanScore(bad as Msg)).toBeNull();
    }
  });

  it('keeps only the best and builds a board of you and your friends', async () => {
    const env = setup({ me: ['f1', 'f2'] });
    const a = env.sock(), f1 = env.sock(), f2 = env.sock(), x = env.sock();
    await env.svc.handle(a, 'me', { type: 'mg_best', game: 'slots', score: 50 });
    await env.svc.handle(a, 'me', { type: 'mg_best', game: 'slots', score: 30 });
    await env.svc.handle(f1, 'f1', { type: 'mg_best', game: 'slots', score: 80 });
    await env.svc.handle(f2, 'f2', { type: 'mg_best', game: 'whack', score: 12 });
    await env.svc.handle(x, 'stranger', { type: 'mg_best', game: 'slots', score: 999 });
    await env.svc.handle(a, 'me', { type: 'mg_friends' });
    const b = a.sent.find(m => m.type === 'mg_friends')!;
    expect(b.friends).toBe(2);
    expect(b.games.slots).toEqual([{ rank: 1, code: 'C-f1', name: 'Nf1', score: 80 }, { rank: 2, code: 'C-me', name: 'Nme', score: 50, me: true }]);
    expect(b.games.whack).toEqual([{ rank: 1, code: 'C-f2', name: 'Nf2', score: 12 }]);
  });

  it('sorts lower-is-better games up and keeps you on the board past the top', async () => {
    const friends = Array.from({ length: BOARD_TOP + 3 }, (_, i) => `f${i}`);
    const env = setup({ me: friends });
    for (const [i, k] of friends.entries()) await env.svc.handle(env.sock(), k, { type: 'mg_best', game: 'find_ace', score: i + 1, low: true });
    const a = env.sock();
    await env.svc.handle(a, 'me', { type: 'mg_best', game: 'find_ace', score: 99, low: true });
    await env.svc.handle(a, 'me', { type: 'mg_friends' });
    const list = a.sent.find(m => m.type === 'mg_friends')!.games.find_ace;
    expect(list.length).toBe(BOARD_TOP + 1);
    expect(list[0]).toMatchObject({ rank: 1, score: 1 });
    expect(list[BOARD_TOP]).toMatchObject({ rank: BOARD_TOP + 4, me: true, score: 99 });
  });

  it('rate limits bests and boards', async () => {
    const env = setup({ me: [] });
    const a = env.sock();
    for (let i = 1; i <= BEST_PER_MIN + 5; i++) await env.svc.handle(a, 'me', { type: 'mg_best', game: 'slots', score: i });
    expect(env.store.rows.get('me|slots')!.score).toBe(BEST_PER_MIN);
    await env.svc.handle(a, 'me', { type: 'mg_friends' });
    await env.svc.handle(a, 'me', { type: 'mg_friends' });
    expect(a.sent.filter(m => m.type === 'mg_friends').length).toBe(1);
    env.clock.t += BOARD_GAP_MS;
    await env.svc.handle(a, 'me', { type: 'mg_friends' });
    expect(a.sent.filter(m => m.type === 'mg_friends').length).toBe(2);
  });
});

describe('friend minigame scores over a real server', () => {
  const srv = startServer(0);
  afterAll(() => srv.stop(true));

  function decode(raw: string): Msg {
    const p = JSON.parse(raw) as Msg;
    if (p.z === 1 && typeof p.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(p.d, 'base64'))).toString('utf8')) as Msg;
    return p;
  }

  async function user(name: string) {
    const ws = new WebSocket(`ws://127.0.0.1:${srv.port}/ws`);
    const msgs: Msg[] = [];
    ws.onmessage = ev => { msgs.push(decode(String(ev.data))); };
    await new Promise<void>((res, rej) => { ws.onopen = () => res(); ws.onerror = () => rej(new Error('ws')); });
    const wait = async (pred: (m: Msg) => boolean, ms = 2000) => {
      const end = Date.now() + ms;
      while (Date.now() < end) { const i = msgs.findIndex(pred); if (i >= 0) return msgs.splice(i, 1)[0]; await new Promise(r => setTimeout(r, 10)); }
      throw new Error('timed out');
    };
    const send = (m: Msg) => ws.send(JSON.stringify(m));
    const pkey = Array.from({ length: 24 }, () => 'abcdefghijklmnopqrstuvwxyz0123456789'[Math.floor(Math.random() * 36)]).join('');
    send({ type: 'social_hello', pkey, name });
    const me = await wait(m => m.type === 'social_me');
    return { send, wait, code: me.code as string, close: () => ws.close() };
  }

  it('a friend sees your best on the board', async () => {
    const a = await user(`Mga${Date.now() % 1e5}`), b = await user(`Mgb${Date.now() % 1e5}`);
    a.send({ type: 'social_add', code: b.code });
    await b.wait(m => m.type === 'social_list' && m.requests.length > 0);
    b.send({ type: 'social_accept', code: a.code });
    await a.wait(m => m.type === 'social_list' && m.friends.length > 0);
    b.send({ type: 'mg_best', game: 'blackjack', score: 140 });
    a.send({ type: 'mg_best', game: 'blackjack', score: 60 });
    await new Promise(r => setTimeout(r, 50));
    a.send({ type: 'mg_friends' });
    const board = await a.wait(m => m.type === 'mg_friends');
    expect(board.games.blackjack.map((r: Msg) => [r.code, r.score, r.me === true])).toEqual([[b.code, 140, false], [a.code, 60, true]]);
    a.close(); b.close();
  });
});
