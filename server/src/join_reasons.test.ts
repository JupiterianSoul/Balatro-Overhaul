import { describe, it, expect, afterAll } from 'bun:test';
import { startServer } from './index';
import { forgeHash } from './forge_relay';

const srv = startServer(0);
afterAll(() => srv.stop(true));

type Msg = Record<string, unknown>;
interface C { msgs: Msg[]; send: (m: Msg) => void; next: (type: string, ms?: number) => Promise<Msg>; close: () => void }

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let uid = 0;
const nm = (p: string) => `${p}${++uid}j${Math.floor(Math.random() * 1e5)}`;
const key = (c: string) => c.repeat(20) + String(1000 + Math.floor(Math.random() * 9000));

function decode(raw: string): Msg {
  const parsed = JSON.parse(raw) as Msg;
  if (parsed.z === 1 && typeof parsed.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(parsed.d, 'base64'))).toString('utf8')) as Msg;
  return parsed;
}

async function connect(): Promise<C> {
  const ws = new WebSocket(`ws://127.0.0.1:${srv.port}/ws`);
  const msgs: Msg[] = [];
  const seen: Record<string, number> = {};
  const waiters: { type: string; resolve: (m: Msg) => void }[] = [];
  ws.onmessage = (ev) => {
    const m = decode(String(ev.data));
    msgs.push(m);
    const i = waiters.findIndex(w => w.type === m.type);
    if (i >= 0) { seen[String(m.type)] = msgs.length; waiters.splice(i, 1)[0].resolve(m); }
  };
  await new Promise<void>((resolve, reject) => { ws.onopen = () => resolve(); ws.onerror = () => reject(new Error('ws error')); });
  return {
    msgs,
    send: (m) => ws.send(JSON.stringify(m)),
    next: (type, ms = 2000) => {
      const from = seen[type] ?? 0;
      const at = msgs.findIndex((m, i) => i >= from && m.type === type);
      if (at >= 0) { seen[type] = at + 1; return Promise.resolve(msgs[at]); }
      return new Promise<Msg>((resolve, reject) => {
        const t = setTimeout(() => reject(new Error(`timed out waiting for ${type}`)), ms);
        waiters.push({ type, resolve: (m) => { clearTimeout(t); resolve(m); } });
      });
    },
    close: () => ws.close(),
  };
}

const RAW = JSON.stringify({ format: 'forgemod', v: 1, id: 'join1', name: 'Join Fox', author: 'Gab', version: 1, about: ['x'], jokers: [{ id: 'j1', name: 'Join Fox' }] });
const FORGE = [{ id: 'forge:join1', name: 'Join Fox', version: forgeHash(RAW), author: 'Gab', size: Buffer.byteLength(RAW) }];

async function host(extra: Msg = {}): Promise<[C, Msg]> {
  const h = await connect();
  h.send({ type: 'create_room', visibility: 'private', name: nm('Host'), pkey: key('H'), ...extra });
  return [h, await h.next('room_created')];
}

const rowOf = (list: Msg, id: unknown) => (list.rooms as Msg[]).find(r => r.id === id);

describe('mods a player turned off are forgotten on the same connection', () => {
  it('a joiner who turned Forge mods off joins a plain private room', async () => {
    const [h, created] = await host();
    const j = await connect();
    j.send({ type: 'list_rooms', mods: FORGE });
    expect(rowOf(await j.next('room_list'), created.id)?.sameMods).toBe(false);
    j.send({ type: 'join_room', code: created.code, name: nm('Join'), pkey: key('J'), mods: FORGE });
    const refused = await j.next('room_error');
    expect(refused.reason).toBe('mods_mismatch');
    expect(refused.yourMods).toHaveLength(1);
    j.send({ type: 'list_rooms' });
    expect(rowOf(await j.next('room_list'), created.id)?.sameMods).toBe(true);
    j.send({ type: 'join_room', code: created.code, id: created.id, name: nm('Join'), pkey: key('J') });
    expect((await j.next('room_ready')).code).toBe(created.code);
    h.close(); j.close();
  });

  it('an empty mods list means no mods too', async () => {
    const [h, created] = await host();
    const j = await connect();
    j.send({ type: 'list_rooms', mods: FORGE });
    await j.next('room_list');
    j.send({ type: 'join_room', code: created.code, name: nm('Join'), pkey: key('K'), mods: [] });
    expect((await j.next('room_ready')).code).toBe(created.code);
    h.close(); j.close();
  });

  it('a host who turned Forge mods off creates a room without them', async () => {
    const h = await connect();
    h.send({ type: 'list_rooms', mods: FORGE });
    await h.next('room_list');
    h.send({ type: 'create_room', visibility: 'private', name: nm('Host'), pkey: key('L') });
    const created = await h.next('room_created');
    expect(created.modded).toBe(false);
    expect(created.forge).toEqual([]);
    const j = await connect();
    j.send({ type: 'join_room', code: created.code, name: nm('Join'), pkey: key('M') });
    expect((await j.next('room_ready')).code).toBe(created.code);
    h.close(); j.close();
  });

  it('still refuses a joiner whose Forge mods are on', async () => {
    const [h, created] = await host();
    const j = await connect();
    j.send({ type: 'join_room', code: created.code, name: nm('Join'), pkey: key('N'), mods: FORGE });
    const refused = await j.next('room_error');
    expect(refused.reason).toBe('mods_mismatch');
    expect(refused.hostMods).toEqual([]);
    h.close(); j.close();
  });
});

describe('join errors say the true reason', () => {
  it('a room that just closed is gone, a code never used is a wrong code', async () => {
    const [h, created] = await host();
    h.close();
    await sleep(150);
    const j = await connect();
    j.send({ type: 'join_room', code: created.code, name: nm('Join'), pkey: key('O') });
    expect((await j.next('room_error')).reason).toBe('room_gone');
    j.send({ type: 'join_room', code: '0000', name: nm('Join'), pkey: key('O') });
    expect((await j.next('room_error')).reason).toBe('invalid_code');
    j.close();
  });

  it('the right code joins its room when the listed room is another one or is gone', async () => {
    const [a, roomA] = await host();
    const [b, roomB] = await host();
    const j = await connect();
    j.send({ type: 'join_room', id: roomA.id, code: roomB.code, name: nm('Join'), pkey: key('P') });
    expect((await j.next('room_ready')).code).toBe(roomB.code);
    const [c, roomC] = await host();
    const k = await connect();
    k.send({ type: 'join_room', id: 'abcdef012345', code: roomC.code, name: nm('Join'), pkey: key('Q') });
    expect((await k.next('room_ready')).code).toBe(roomC.code);
    a.close(); b.close(); c.close(); j.close(); k.close();
  });

  it('a wrong code for a listed private room is still a wrong code', async () => {
    const [h, created] = await host();
    const j = await connect();
    j.send({ type: 'join_room', id: created.id, code: '0000', name: nm('Join'), pkey: key('R') });
    expect((await j.next('room_error')).reason).toBe('invalid_code');
    j.send({ type: 'join_room', id: created.id, name: nm('Join'), pkey: key('R') });
    expect((await j.next('room_error')).reason).toBe('code_required');
    h.close(); j.close();
  });

  it('a full room says so, not a wrong code', async () => {
    const [h, created] = await host();
    const g = await connect();
    g.send({ type: 'join_room', code: created.code, name: nm('Guest'), pkey: key('S') });
    await g.next('room_ready');
    const j = await connect();
    j.send({ type: 'join_room', code: created.code, name: nm('Join'), pkey: key('T') });
    expect((await j.next('room_error')).reason).toBe('room_full');
    h.close(); g.close(); j.close();
  });
});
