import { describe, it, expect, afterAll } from 'bun:test';
import { startServer, botModsRefusal } from './index';
import { forgeHash, ForgeRelay, FORGE_RELAY_PER_SOCKET } from './forge_relay';
import { FORGE_MAX_BYTES } from './forge_mods';

const srv = startServer(0);
afterAll(() => srv.stop(true));

type Msg = Record<string, unknown>;
interface C { msgs: Msg[]; send: (m: Msg) => void; wait: (pred: (m: Msg) => boolean, ms?: number) => Promise<Msg>; close: () => void }

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
let uid = 0;
const nm = (p: string) => `${p}${++uid}q${Math.floor(Math.random() * 1e5)}`;
const key = (c: string) => c.repeat(20) + String(1000 + Math.floor(Math.random() * 9000));

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



const rawMod = (id: string, name = 'Lucky Café', pad = 0) => JSON.stringify({ format: 'forgemod', v: 1, id, name, author: 'Gab', version: 1,
  about: ['x'.repeat(Math.min(pad, 10))], jokers: [{ id: 'j1', name: 'Forge Fox', pad: 'p'.repeat(pad) }] });
const entry = (raw: string, id: string) => ({ id: `forge:${id}`, name: 'Lucky Café', version: forgeHash(raw), author: 'Gab', size: Buffer.byteLength(raw) });
const PLAIN = [{ id: 'Steamodded', name: 'Steamodded', version: '1.0.0' }];

describe('forge mods in room mod sets', () => {
  it('hashes like the game does (djb2 and sdbm over the UTF-8 bytes)', () => {
    expect(forgeHash('abc')).toBe('0b885c8b3025f862');
    expect(forgeHash('{"format":"forgemod","name":"Café"}')).toBe('f2f8e5a0eab7c23b');
    expect(forgeHash('xyz'.repeat(5000))).toBe('8ab55a5dfa917b00');
  });

  it('puts the host Forge mods in a private room set and only lets the exact same content in', async () => {
    const raw = rawMod('fox1');
    const h = await connect();
    h.send({ type: 'create_room', visibility: 'private', name: nm('FHost'), pkey: key('F'), mods: [entry(raw, 'fox1')] });
    const created = await h.wait(is('room_created'));
    expect(created.modded).toBe(true);
    expect(created.forge).toEqual([entry(raw, 'fox1')]);
    const code = created.code as string;
    const j = await connect();
    j.send({ type: 'join_room', code, name: nm('FJoin'), pkey: key('G') });
    const miss = await j.wait(is('room_error'));
    expect(miss.reason).toBe('mods_mismatch');
    expect(miss.hostMods).toEqual([entry(raw, 'fox1')]);
    j.msgs.length = 0;
    j.send({ type: 'join_room', code, name: nm('FJoin'), pkey: key('G'), mods: [{ ...entry(raw, 'fox1'), version: forgeHash(raw + ' ') }] });
    expect((await j.wait(is('room_error'))).reason).toBe('mods_mismatch');
    j.msgs.length = 0;
    j.send({ type: 'join_room', code, name: nm('FJoin'), pkey: key('G'), mods: [entry(raw, 'fox1')] });
    const ready = await j.wait(is('room_ready'));
    expect(ready.forge).toEqual([entry(raw, 'fox1')]);
    h.close(); j.close();
  });

  it('refuses Forge mods in public rooms, quick match and public parties', async () => {
    const raw = rawMod('fox2');
    const a = await connect();
    a.send({ type: 'create_room', visibility: 'public', name: nm('FPub'), pkey: key('H'), mods: [entry(raw, 'fox2')] });
    const r = await a.wait(is('room_error'));
    expect(r.reason).toBe('mods_private_only');
    expect(r.mods).toEqual(['forge:fox2']);
    a.msgs.length = 0;
    a.send({ type: 'find_match', name: nm('FQuick'), pkey: key('H'), mods: [entry(raw, 'fox2')] });
    expect((await a.wait(is('room_error'))).reason).toBe('mods_private_only');
    a.send({ type: 'party_create', visibility: 'public', kind: 'br', name: nm('FParty'), pkey: key('H'), mods: [entry(raw, 'fox2')] });
    expect((await a.wait(is('party_error'))).reason).toBe('mods_private_only');
    a.close();
  });

  it('lets a player with Forge mods on join a plain public room, where they stay off', async () => {
    const raw = rawMod('fox3');
    const h = await connect();
    h.send({ type: 'create_room', visibility: 'public', name: nm('PHost'), pkey: key('I'), mods: PLAIN });
    const created = await h.wait(is('room_created'));
    expect(created.forge).toEqual([]);
    const j = await connect();
    j.send({ type: 'list_rooms', mods: [...PLAIN, entry(raw, 'fox3')] });
    const list = await j.wait(is('room_list'));
    const row = (list.rooms as Msg[]).find(x => x.id === created.id);
    expect(row?.sameMods).toBe(true);
    j.send({ type: 'join_room', id: created.id, code: created.code, name: nm('PJoin'), pkey: key('J'), mods: [...PLAIN, entry(raw, 'fox3')] });
    const ready = await j.wait(is('room_ready'));
    expect(ready.forge).toEqual([]);
    h.close(); j.close();
  });

  it('does not hold remembered Forge mods against quick match or a public room', async () => {
    const raw = rawMod('fox4');
    const a = await connect();
    a.send({ type: 'list_rooms', mods: [entry(raw, 'fox4')] });
    await a.wait(is('room_list'));
    a.send({ type: 'find_match', name: nm('QPlain'), pkey: key('P') });
    expect((await a.wait(m => m.type === 'searching' || m.type === 'room_error')).type).toBe('searching');
    a.close();
    const b = await connect();
    b.send({ type: 'list_rooms', mods: [entry(raw, 'fox4')] });
    await b.wait(is('room_list'));
    b.send({ type: 'create_room', visibility: 'public', name: nm('PubPlain'), pkey: key('Q') });
    const c = await b.wait(m => m.type === 'room_created' || m.type === 'room_error');
    expect(c.type).toBe('room_created');
    expect(c.forge).toEqual([]);
    b.close();
  });

  it('rejects bad Forge entries', async () => {
    const a = await connect();
    a.send({ type: 'create_room', visibility: 'private', name: nm('FBad'), pkey: key('K'), mods: [{ id: 'forge:fox4', name: 'x', version: 'nothex' }] });
    const e = await a.wait(m => m.type === 'error' || m.type === 'room_error' || m.type === 'room_created');
    expect(e.type).not.toBe('room_created');
    a.close();
  });

  it('relays a missing Forge mod from the host, checked against the room hash', async () => {
    const raw = rawMod('fox5');
    const h = await connect();
    h.send({ type: 'create_room', visibility: 'private', name: nm('RHost'), pkey: key('L'), mods: [entry(raw, 'fox5')] });
    const created = await h.wait(is('room_created'));
    const j = await connect();
    j.send({ type: 'forge_room_get', room: created.id, id: 'fox5', hash: forgeHash(raw) });
    const req = await h.wait(is('forge_room_req'));
    expect(req.id).toBe('fox5');
    h.send({ type: 'forge_room_put', rid: req.rid, mod: raw });
    const got = await j.wait(is('forge_room_mod'));
    expect(got.ok).toBe(true);
    expect(got.mod).toBe(raw);
    expect(got.author).toBe('Gab');
    expect(forgeHash(String(got.mod))).toBe(forgeHash(raw));

    j.msgs.length = 0; h.msgs.length = 0;
    j.send({ type: 'forge_room_get', code: created.code, id: 'fox5', hash: forgeHash(raw) });
    const req2 = await h.wait(is('forge_room_req'));
    h.send({ type: 'forge_room_put', rid: req2.rid, mod: rawMod('fox5', 'Other') });
    const bad = await j.wait(is('forge_room_mod'));
    expect(bad.ok).toBe(false);
    expect(bad.reason).toBe('hash_mismatch');

    j.msgs.length = 0;
    j.send({ type: 'forge_room_get', room: created.id, id: 'zzzz', hash: forgeHash(raw) });
    expect((await j.wait(is('forge_room_mod'))).reason).toBe('not_in_room');
    j.msgs.length = 0;
    j.send({ type: 'forge_room_get', room: created.id, id: 'fox5', hash: '0000000000000000' });
    expect((await j.wait(is('forge_room_mod'))).reason).toBe('hash_mismatch');

    j.msgs.length = 0; h.msgs.length = 0;
    j.send({ type: 'forge_room_get', room: created.id, id: 'fox5', hash: forgeHash(raw) });
    await h.wait(is('forge_room_req'));
    h.close();
    expect((await j.wait(is('forge_room_mod'))).reason).toBe('host_gone');
    j.close();
  });

  it('caps the relayed size and the requests per player', () => {
    const sent: { to: string; m: Msg }[] = [];
    const big = rawMod('fox6', 'Big', FORGE_MAX_BYTES);
    const room = { mods: [{ id: 'forge:fox6', version: forgeHash(big) }, { id: 'forge:fox7', version: forgeHash('x'), size: FORGE_MAX_BYTES + 1 }], host: 'host' };
    const relay = new ForgeRelay<string>({ findRoom: () => room, send: (to, m) => sent.push({ to, m: m as Msg }), timeoutMs: 50 });
    relay.get('j', { id: 'fox7', hash: forgeHash('x'), room: 'aaaaaaaaaaaa' });
    expect(sent.pop()?.m.reason).toBe('too_big');
    relay.get('j', { id: 'fox6', hash: forgeHash(big), room: 'aaaaaaaaaaaa' });
    const req = sent.pop()!;
    expect(req.to).toBe('host');
    relay.put('host', { rid: req.m.rid, mod: big });
    expect(sent.pop()?.m.reason).toBe('too_big');
    for (let i = 0; i < FORGE_RELAY_PER_SOCKET; i++) relay.get('k', { id: 'fox6', hash: forgeHash(big), room: 'aaaaaaaaaaaa' });
    expect(relay.pending.size).toBe(FORGE_RELAY_PER_SOCKET);
    relay.get('k', { id: 'fox6', hash: forgeHash(big), room: 'aaaaaaaaaaaa' });
    expect(sent.pop()?.m.reason).toBe('busy');
    relay.put('intruder', { rid: [...relay.pending.keys()][0], mod: big });
    expect(relay.pending.size).toBe(FORGE_RELAY_PER_SOCKET);
    relay.drop('k');
    expect(relay.pending.size).toBe(0);
  });

  it('times out when the host never answers', async () => {
    const sent: Msg[] = [];
    const relay = new ForgeRelay<string>({ findRoom: () => ({ mods: [{ id: 'forge:fox8', version: forgeHash('a') }], host: 'h' }), send: (_to, m) => sent.push(m as Msg), timeoutMs: 20 });
    relay.get('j', { id: 'fox8', hash: forgeHash('a'), code: 'ABCD' });
    await sleep(60);
    expect(sent.pop()?.reason).toBe('timeout');
    expect(relay.pending.size).toBe(0);
  });
});

describe('bots and mods', () => {
  it('keeps server bots out of rooms with mods or Forge content', async () => {
    expect(botModsRefusal(PLAIN, {})).toBeNull();
    expect(botModsRefusal([{ id: 'Cryptid', version: '1' }], {})).toBe('mods');
    expect(botModsRefusal([{ id: 'forge:abcd', version: '0000000000000000' }], {})).toBe('mods');
    expect(botModsRefusal(PLAIN, { forge_room_on: true })).toBe('forge');
    const raw = rawMod('fox9');
    const h = await connect();
    h.send({ type: 'create_room', visibility: 'private', name: nm('BHost'), pkey: key('M'), mods: [entry(raw, 'fox9')] });
    await h.wait(is('room_created'));
    h.send({ type: 'add_bot', level: 'easy' });
    expect((await h.wait(is('bot_error'))).reason).toBe('mods');
    h.close();
    const p = await connect();
    p.send({ type: 'party_create', visibility: 'private', kind: 'br', name: nm('BParty'), pkey: key('N'), mods: [{ id: 'Cryptid', name: 'Cryptid', version: '0.5.3' }] });
    await p.wait(is('party_joined'));
    p.send({ type: 'add_bot', level: 'easy' });
    expect((await p.wait(is('bot_error'))).reason).toBe('mods');
    p.close();
  });
});

describe('too many forge mods', () => {
  const many = (n: number) => Array.from({ length: n }, (_, i) => { const id = `fm${String(i).padStart(4, '0')}`; return entry(rawMod(id), id); });

  it('takes 50 forge mods in a private room and lists rooms with them', async () => {
    const c = await connect();
    c.send({ type: 'create_room', visibility: 'private', mods: [...PLAIN, ...many(50)], name: nm('Big') });
    const created = await c.wait(is('room_created'));
    expect((created.forge as unknown[]).length).toBe(50);
    c.send({ type: 'list_rooms', mods: [...PLAIN, ...many(50)] });
    await c.wait(is('room_list'));
    c.close();
  });

  it('says why when there are more than 50, on every path, and old games still read it as invalid mods', async () => {
    const c = await connect();
    for (const type of ['create_room', 'list_rooms', 'join_room', 'party_create', 'party_join']) {
      c.msgs.length = 0;
      const msg: Msg = { type, mods: [...PLAIN, ...many(51)] };
      if (type === 'create_room' || type === 'party_create') msg.visibility = 'private';
      if (type === 'join_room' || type === 'party_join') msg.code = 'ABCD';
      c.send(msg);
      const err = await c.wait(is('error'));
      expect(String(err.reason)).toBe(`${type}: invalid mods (too many forge mods, max 50)`);
      expect(String(err.reason).match(/^\w+: invalid (\w+)/)?.[1]).toBe('mods');
    }
    c.msgs.length = 0;
    c.send({ type: 'list_rooms', mods: Array.from({ length: 101 }, (_, i) => ({ id: `m${i}`, version: '1' })) });
    expect(String((await c.wait(is('error'))).reason)).toBe('list_rooms: invalid mods (too many mods, max 100)');
    c.close();
  });
});
