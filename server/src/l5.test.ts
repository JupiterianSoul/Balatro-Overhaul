import { describe, it, expect, afterAll } from 'bun:test';
import { startServer, nameCheck, menuInfo, validateMessage } from './index';

const srv = startServer(0);
afterAll(() => srv.stop(true));

type Msg = Record<string, unknown>;
interface C { msgs: Msg[]; send: (m: Msg) => void; wait: (pred: (m: Msg) => boolean, ms?: number) => Promise<Msg>; close: () => void }

let uid = 0;
const nm = (p: string) => `${p}${++uid}x${Math.floor(Math.random() * 1e4)}`;
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

describe('L5 name check', () => {
  it('refuses names with a slur or an insult, and never masks them', () => {
    expect(nameCheck(null, 'FuckMe')).toEqual({ ok: false, name: 'FuckMe', reason: 'bad_name' });
    expect(nameCheck(null, 'n1gger')).toMatchObject({ ok: false, reason: 'bad_name' });
    expect(nameCheck(null, 'Scunthorpe')).toEqual({ ok: true, name: 'Scunthorpe' });
  });

  it('refuses a bad name at claim time', async () => {
    const c = await connect();
    c.send({ type: 'create_room', name: 'DickHead' });
    expect((await c.wait(is('name_refused'))).reason).toBe('bad_name');
    c.close();
  });

  it('accepts a normal name and trims spaces', () => {
    expect(nameCheck(null, '  Zoé  ')).toEqual({ ok: true, name: 'Zoé' });
  });

  it('refuses empty, default, too long and odd names', () => {
    expect(nameCheck(null, '   ').reason).toBe('empty');
    expect(nameCheck(null, 'Player 2').reason).toBe('default');
    expect(nameCheck(null, 'P1').reason).toBe('default');
    expect(nameCheck(null, 'A'.repeat(17)).reason).toBe('too_long');
    expect(nameCheck(null, 'a<b>').reason).toBe('bad_chars');
    expect(nameCheck(null, 'Jimbo_2.0').ok).toBe(true);
  });

  it('validates the message shape', () => {
    expect(validateMessage({ type: 'name_check', name: 'Bob' }, 40)).toBeNull();
    expect(validateMessage({ type: 'name_check', name: 5 }, 40)).not.toBeNull();
    expect(validateMessage({ type: 'menu_info' }, 20)).toBeNull();
  });

  it('says taken when another online player holds the name, free for the same player', async () => {
    const holder = await connect();
    const other = await connect();
    const name = nm('Held');
    const hk = key('h');
    holder.send({ type: 'find_match', name, pkey: hk, version: 'l5-test-a' });
    await holder.wait(is('searching'));
    other.send({ type: 'name_check', name: name.toUpperCase(), pkey: key('o') });
    const refused = await other.wait(is('name_check'));
    expect(refused.ok).toBe(false);
    expect(refused.reason).toBe('taken');
    holder.send({ type: 'name_check', name, pkey: hk });
    const mine = await holder.wait(is('name_check'));
    expect(mine.ok).toBe(true);
    holder.send({ type: 'cancel_search' });
    holder.close();
    other.close();
  });
});

describe('L5 menu info', () => {
  it('counts online players and the ranked queue and sends the ranked ruleset', async () => {
    const a = await connect();
    a.send({ type: 'find_match', ranked: true, name: nm('Rk'), pkey: key('r'), version: 'l5-test-b', mods: [] });
    await a.wait(is('searching'));
    const b = await connect();
    b.send({ type: 'menu_info' });
    const info = await b.wait(is('menu_info'));
    expect(info.online as number).toBeGreaterThanOrEqual(1);
    expect(info.ranked_queue as number).toBeGreaterThanOrEqual(1);
    expect(typeof info.queue).toBe('number');
    expect(typeof info.matches).toBe('number');
    const rs = info.ruleset as Record<string, unknown>;
    expect(rs.id).toBe('ranked');
    expect(rs.locked).toBe(true);
    expect((rs.settings as Record<string, unknown>).ruleset_id).toBe('ranked');
    a.send({ type: 'cancel_search' });
    a.close();
    b.close();
  });

  it('builds the payload without a socket', () => {
    const info = menuInfo();
    expect(info.type).toBe('menu_info');
    expect((info.ruleset as Record<string, unknown>).mode).toBe('nemesis');
  });
});
