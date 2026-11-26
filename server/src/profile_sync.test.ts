import { describe, it, expect, afterAll } from 'bun:test';
import { startServer, social } from './index';
import type { MemoryExtra } from './social_store';

const srv = startServer(0);
afterAll(() => srv.stop(true));

async function connect(): Promise<WebSocket> {
  const ws = new WebSocket(`ws://127.0.0.1:${srv.port}/ws`);
  await new Promise<void>((resolve, reject) => { ws.onopen = () => resolve(); ws.onerror = () => reject(new Error('ws error')); });
  return ws;
}

const settle = () => new Promise(r => setTimeout(r, 150));
const key = (c: string) => c.repeat(20) + String(1000 + Math.floor(Math.random() * 9000));
const mem = () => social.extra as unknown as MemoryExtra;

describe('profile_sync', () => {
  it('stores one snapshot per session and keeps the first within the gap', async () => {
    const pkey = key('p');
    const ws = await connect();
    ws.send(JSON.stringify({ type: 'client_hello', name: `Prof${Math.floor(Math.random() * 1e5)}`, pkey, version: '87' }));
    await settle();
    ws.send(JSON.stringify({ type: 'profile_sync', session: 'modded', data: { sp: { level: 12 }, mods: [{ id: 'Cryptid', on: true }] } }));
    await settle();
    ws.send(JSON.stringify({ type: 'profile_sync', session: 'modded', data: { sp: { level: 99 } } }));
    await settle();
    const rows = await mem().profileGet(pkey);
    expect(rows.length).toBe(1);
    expect(rows[0].session).toBe('modded');
    expect(JSON.parse(rows[0].data).sp.level).toBe(12);
    ws.close();
  });

  it('refuses oversized, non-object and keyless snapshots', async () => {
    const pkey = key('q');
    const ws = await connect();
    ws.send(JSON.stringify({ type: 'profile_sync', pkey: 'bad', data: { sp: { level: 3 } } }));
    ws.send(JSON.stringify({ type: 'client_hello', name: `Big${Math.floor(Math.random() * 1e5)}`, pkey, version: '87' }));
    await settle();
    ws.send(JSON.stringify({ type: 'profile_sync', data: 'text' }));
    ws.send(JSON.stringify({ type: 'profile_sync', data: { blob: 'x'.repeat(20000) } }));
    await settle();
    expect((await mem().profileGet(pkey)).length).toBe(0);
    ws.close();
  });
});
