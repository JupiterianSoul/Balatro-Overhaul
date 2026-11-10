import { describe, it, expect, afterAll } from 'bun:test';
import { startServer, validateMessage, spectate } from './index';
import { MatchLogService, MemoryLogStore } from './matchlog';
import { SpectateService, SPEC_CAPS } from './spectate';
import { friendCode } from './social';

type Msg = Record<string, unknown>;

function svc(opts: { friends?: Record<string, string[]>; now?: () => number } = {}) {
  const logs = new MatchLogService(new MemoryLogStore());
  const sent: { ws: string; d: Msg }[] = [];
  const s = new SpectateService<string>({
    logs: () => logs.liveById.values(),
    isLive: id => logs.liveById.has(id),
    send: (ws, d) => sent.push({ ws, d: d as Msg }),
    keyOf: ws => `key-${ws}`,
    friendKeys: k => opts.friends?.[k] ?? [],
  }, opts.now ?? (() => 100_000));
  logs.deps.onAct = (id, pid, seq, a) => s.onAct(id, pid, seq, a);
  return { logs, s, sent };
}

function start(logs: MatchLogService, id: string, settings: Msg = {}, keys: Record<string, string> = { 0: 'key-a', 1: 'key-b' }, ranked = false) {
  const host = { id };
  logs.start(host, {
    id, mode: 'nemesis', ranked, kind: '1v1', settings, ruleset: null, seeds: ['SEED'],
    players: [
      { pid: 0, name: 'Ann', is_bot: false, version: '1', mods: [] },
      { pid: 1, name: 'Bob', is_bot: true, bot_level: 'easy', version: '1', mods: [] },
    ],
  }, keys);
  return host;
}

const last = (sent: { ws: string; d: Msg }[], ws: string, type: string) => [...sent].reverse().find(x => x.ws === ws && x.d.type === type)?.d;

describe('spectate service', () => {
  it('lists live public matches, friends first, never your own or private ones', () => {
    const { logs, s, sent } = svc({ friends: { 'key-me': ['key-c'] } });
    start(logs, 'm1');
    start(logs, 'm2', { spectate: false }, { 0: 'key-x', 1: 'key-y' });
    start(logs, 'm3', {}, { 0: 'key-c', 1: 'key-d' });
    start(logs, 'm4', {}, { 0: 'key-me', 1: 'key-z' });
    expect(s.handle('me', { type: 'spectate_list' })).toBe(true);
    const list = last(sent, 'me', 'spectate_list')!.matches as Msg[];
    expect(list.map(m => m.id)).toEqual(['m3', 'm1']);
    expect(list[0].friend).toBe(true);
    expect(list[0].friends).toEqual([friendCode('key-c')]);
    expect((list[1].players as Msg[])[1]).toEqual({ pid: 1, name: 'Bob', is_bot: true, bot_level: 'easy' });
  });

  it('rate-limits the list', () => {
    let t = 100_000;
    const { logs, s, sent } = svc({ now: () => t });
    start(logs, 'm1');
    s.handle('me', { type: 'spectate_list' });
    s.handle('me', { type: 'spectate_list' });
    expect(last(sent, 'me', 'spectate_list')!.slow_down).toBe(true);
    t += SPEC_CAPS.listGapMs + 1;
    s.handle('me', { type: 'spectate_list' });
    expect((last(sent, 'me', 'spectate_list')!.matches as Msg[]).length).toBe(1);
  });

  it('catches up from the match start, then forwards live actions', () => {
    const { logs, s, sent } = svc();
    const host = start(logs, 'm1', { spectate_jokers: false });
    logs.act(host, 0, 1, [{ k: 'start', seed: 'SEED' }, { k: 'bs', b: 'Small Blind' }]);
    logs.act(host, 1, 1, [{ k: 'start', seed: 'SEED' }]);
    s.handle('w', { type: 'spectate_watch', id: 'm1', pid: 0 });
    const st = last(sent, 'w', 'spectate_start')!;
    expect(st.pid).toBe(0);
    expect(st.see_jokers).toBe(false);
    expect((st.streams as Record<string, unknown[]>)['0'].length).toBe(2);
    expect(st.seqs).toEqual({ 0: 1, 1: 1 });
    expect(JSON.stringify(st.header)).not.toContain('key-a');
    logs.act(host, 0, 2, [{ k: 'pl', c: [1, 2] }]);
    logs.act(host, 0, 2, [{ k: 'pl', c: [1, 2] }]);
    const acts = sent.filter(x => x.ws === 'w' && x.d.type === 'spectate_act');
    expect(acts.length).toBe(1);
    expect(acts[0].d).toEqual({ type: 'spectate_act', id: 'm1', pid: 0, seq: 2, a: [{ k: 'pl', c: [1, 2] }] });
    expect(s.watcherCount('m1')).toBe(1);
  });

  it('refuses private matches, your own match, and unknown ids', () => {
    const { logs, s, sent } = svc();
    start(logs, 'm1', { spectate: false });
    s.handle('w', { type: 'spectate_watch', id: 'm1' });
    expect(last(sent, 'w', 'spectate_error')!.reason).toBe('private');
    start(logs, 'm2', {}, { 0: 'key-a2', 1: 'key-b2' });
    s.handle('a2', { type: 'spectate_watch', id: 'm2' });
    expect(last(sent, 'a2', 'spectate_error')!.reason).toBe('in_match');
    s.handle('w', { type: 'spectate_watch', id: 'zzz' });
    expect(last(sent, 'w', 'spectate_error')!.reason).toBe('not_found');
  });

  it('never shows a live ranked match, not even to a friend', () => {
    const { logs, s, sent } = svc({ friends: { 'key-me': ['key-r'] } });
    start(logs, 'r1', {}, { 0: 'key-r', 1: 'key-s' }, true);
    start(logs, 'm1');
    s.handle('me', { type: 'spectate_list' });
    expect((last(sent, 'me', 'spectate_list')!.matches as Msg[]).map(m => m.id)).toEqual(['m1']);
    s.handle('me', { type: 'spectate_watch', id: 'r1' });
    expect(last(sent, 'me', 'spectate_error')!.reason).toBe('ranked_live');
    s.handle('me', { type: 'spectate_watch', code: friendCode('key-r') });
    expect(last(sent, 'me', 'spectate_error')!.reason).toBe('ranked_live');
    expect(s.watcherCount('r1')).toBe(0);
  });

  it('watches a friend by code and follows that player', () => {
    const { logs, s, sent } = svc({ friends: { 'key-me': ['key-b'] } });
    start(logs, 'm1');
    s.handle('me', { type: 'spectate_watch', code: friendCode('key-b') });
    const st = last(sent, 'me', 'spectate_start')!;
    expect(st.id).toBe('m1');
    expect(st.pid).toBe(1);
    s.handle('me', { type: 'spectate_watch', code: friendCode('key-a') });
    expect(last(sent, 'me', 'spectate_error')!.reason).toBe('not_friend');
  });

  it('switching matches leaves the old one; leave and drop clean up', () => {
    const { logs, s, sent } = svc();
    start(logs, 'm1');
    start(logs, 'm2', {}, { 0: 'key-p', 1: 'key-q' });
    s.handle('w', { type: 'spectate_watch', id: 'm1' });
    s.handle('w', { type: 'spectate_watch', id: 'm2' });
    expect(s.watcherCount('m1')).toBe(0);
    expect(s.watcherCount('m2')).toBe(1);
    s.handle('w', { type: 'spectate_leave' });
    expect(last(sent, 'w', 'spectate_end')!.reason).toBe('left');
    expect(s.watcherCount('m2')).toBe(0);
    s.handle('v', { type: 'spectate_watch', id: 'm2' });
    s.drop('v');
    expect(s.watcherCount('m2')).toBe(0);
  });

  it('ends watchers when the match finishes', async () => {
    const { logs, s, sent } = svc();
    const host = start(logs, 'm1');
    s.handle('w', { type: 'spectate_watch', id: 'm1' });
    await logs.finish(host, { reason: 'match_over', results: [], rate: null });
    s.sweep();
    expect(last(sent, 'w', 'spectate_end')!.reason).toBe('ended');
    expect(s.watcherCount('m1')).toBe(0);
  });

  it('caps watchers per match', () => {
    const { logs, s, sent } = svc();
    start(logs, 'm1');
    for (let i = 0; i < SPEC_CAPS.perMatch; i++) s.handle(`w${i}`, { type: 'spectate_watch', id: 'm1' });
    s.handle('late', { type: 'spectate_watch', id: 'm1' });
    expect(last(sent, 'late', 'spectate_error')!.reason).toBe('full');
  });
});

describe('spectate over the socket', () => {
  const srv = startServer(0);
  afterAll(() => srv.stop(true));

  function decode(raw: string): Msg {
    const parsed = JSON.parse(raw) as Msg;
    if (parsed.z === 1 && typeof parsed.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(parsed.d, 'base64'))).toString('utf8')) as Msg;
    return parsed;
  }

  async function connect() {
    const ws = new WebSocket(`ws://127.0.0.1:${srv.port}/ws`);
    const msgs: Msg[] = [];
    ws.onmessage = ev => { msgs.push(decode(String(ev.data))); };
    await new Promise<void>((resolve, reject) => { ws.onopen = () => resolve(); ws.onerror = () => reject(new Error('ws error')); });
    const wait = async (pred: (m: Msg) => boolean, ms = 2000) => {
      const end = Date.now() + ms;
      while (Date.now() < end) { const hit = msgs.find(pred); if (hit) return hit; await new Promise(r => setTimeout(r, 10)); }
      throw new Error('timed out');
    };
    return { msgs, wait, send: (m: Msg) => ws.send(JSON.stringify(m)), close: () => ws.close() };
  }

  const is = (t: string) => (m: Msg) => m.type === t;
  const key = (c: string) => c.repeat(20) + String(1000 + Math.floor(Math.random() * 9000));

  it('validates the new messages', () => {
    expect(validateMessage({ type: 'spectate_list' }, 30)).toBeNull();
    expect(validateMessage({ type: 'spectate_watch', id: 'abc' }, 40)).toBeNull();
    expect(validateMessage({ type: 'spectate_watch' }, 40)).toContain('spectate_watch');
    expect(validateMessage({ type: 'spectate_watch', id: 'a', pid: -1 }, 40)).toContain('pid');
    expect(validateMessage({ type: 'spectate_leave' }, 30)).toBeNull();
    expect(validateMessage({ type: 'spectate_watch', room: 'ABCD' }, 40)).toBeNull();
    expect(validateMessage({ type: 'spectate_watch', room: 5 }, 40)).toContain('room');
  });

  it('a match in a private room cannot be listed or watched', async () => {
    const host = await connect(), guest = await connect(), fan = await connect();
    host.send({ type: 'create_room', visibility: 'private', name: `PrvH${Date.now() % 1e5}`, pkey: key('P') });
    const created = await host.wait(is('room_created'));
    guest.send({ type: 'join_room', code: created.code, name: `PrvG${Date.now() % 1e5}`, pkey: key('Q') });
    await guest.wait(is('room_ready'));
    host.send({ type: 'match_start', seed: 'PRIV', settings: { mode: 'nemesis' }, player_name: 'PrvHost' });
    const st = await guest.wait(is('match_start'));
    const id = st.match_id as string;
    host.send({ type: 'act', seq: 1, a: [{ k: 'start', seed: 'PRIV' }] });
    await new Promise(r => setTimeout(r, 50));
    fan.send({ type: 'spectate_list' });
    const list = await fan.wait(is('spectate_list'));
    expect((list.matches as Msg[]).some(m => m.id === id)).toBe(false);
    fan.send({ type: 'spectate_watch', room: String(created.code), pid: 0 });
    const err = await fan.wait(m => m.type === 'spectate_error' || m.type === 'spectate_start');
    expect(err.type).toBe('spectate_error');
    expect(spectate.watcherCount(id)).toBe(0);
    fan.close(); guest.close(); host.close();
  });

  it('a third player lists, watches with catch-up and gets live actions', async () => {
    const host = await connect(), guest = await connect(), fan = await connect();
    host.send({ type: 'create_room', visibility: 'public', name: `SpecH${Date.now() % 1e5}`, pkey: key('S') });
    const created = await host.wait(is('room_created'));
    guest.send({ type: 'join_room', code: created.code, name: `SpecG${Date.now() % 1e5}`, pkey: key('T') });
    await guest.wait(is('room_ready'));
    host.send({ type: 'match_start', seed: 'SPEC', settings: { mode: 'nemesis' }, player_name: 'SpecHost' });
    const st = await guest.wait(is('match_start'));
    const id = st.match_id as string;
    host.send({ type: 'act', seq: 1, a: [{ k: 'start', seed: 'SPEC' }, { k: 'bs', b: 'Small Blind' }] });
    await new Promise(r => setTimeout(r, 50));
    fan.send({ type: 'spectate_list' });
    const list = await fan.wait(is('spectate_list'));
    const ms = list.matches as Msg[];
    expect(ms.some(m => m.id === id) || ms.length === SPEC_CAPS.list).toBe(true);
    fan.send({ type: 'spectate_watch', room: String(created.code).toLowerCase(), pid: 0 });
    const ss = await fan.wait(is('spectate_start'));
    expect(ss.id).toBe(id);
    expect((ss.streams as Record<string, unknown[]>)['0'].length).toBe(2);
    host.send({ type: 'act', seq: 2, a: [{ k: 'pl', c: [1] }] });
    const live = await fan.wait(is('spectate_act'));
    expect(live.seq).toBe(2);
    expect(spectate.watcherCount(id)).toBe(1);
    fan.close();
    await new Promise(r => setTimeout(r, 80));
    expect(spectate.watcherCount(id)).toBe(0);
    host.close(); guest.close();
  });
});
