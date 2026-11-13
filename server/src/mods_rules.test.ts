import { describe, it, expect, afterAll } from 'bun:test';
import { startServer, cleanModVersion } from './index';

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


const CRYPTID = [{ id: 'Steamodded', name: 'Steamodded', version: '1.0.0' }, { id: 'Cryptid', name: 'Cryptid', version: '0.5.3' }];
const SMODS_ONLY = [{ id: 'Steamodded', name: 'Steamodded', version: '1.0.0' }];

describe('mods stay out of public play', () => {
  it('refuses a public room with mods and allows the same mods in a private room', async () => {
    const a = await connect();
    a.send({ type: 'create_room', visibility: 'public', name: nm('PubMod'), pkey: key('A'), mods: CRYPTID });
    const refused = await a.wait(is('room_error'));
    expect(refused.reason).toBe('mods_private_only');
    expect(refused.mods).toEqual(['Cryptid']);
    a.send({ type: 'create_room', visibility: 'private', name: nm('PrvMod'), pkey: key('A'), mods: CRYPTID });
    const created = await a.wait(is('room_created'));
    expect(created.visibility).toBe('private');
    expect(created.modded).toBe(true);
    a.close();
  });

  it('lets the modded game with no mods turned on create a public room', async () => {
    const a = await connect();
    a.send({ type: 'create_room', visibility: 'public', name: nm('PubPlain'), pkey: key('B'), mods: SMODS_ONLY });
    expect((await a.wait(is('room_created'))).visibility).toBe('public');
    a.close();
  });

  it('refuses quick match and a public party with mods', async () => {
    const a = await connect();
    a.send({ type: 'find_match', name: nm('QuickMod'), pkey: key('C'), mods: CRYPTID });
    expect((await a.wait(is('room_error'))).reason).toBe('mods_private_only');
    a.send({ type: 'party_create', visibility: 'public', kind: 'br', name: nm('PartyMod'), pkey: key('C'), mods: CRYPTID });
    expect((await a.wait(is('party_error'))).reason).toBe('mods_private_only');
    a.close();
  });

  it('blanks a mod version that could change a download address', () => {
    expect(cleanModVersion('x/../../../../evil/repo/archive/refs/heads/main')).toBe('');
    expect(cleanModVersion('1.0?x=1')).toBe('');
    expect(cleanModVersion('..')).toBe('');
    expect(cleanModVersion('1.0 && calc')).toBe('');
    expect(cleanModVersion('0.5.3')).toBe('0.5.3');
    expect(cleanModVersion('1.0.0~BETA-0301a')).toBe('1.0.0~BETA-0301a');
    expect(cleanModVersion('1.0.3.8(20250129)')).toBe('1.0.3.8(20250129)');
    expect(cleanModVersion('1.1 I guess')).toBe('1.1 I guess');
  });
});
