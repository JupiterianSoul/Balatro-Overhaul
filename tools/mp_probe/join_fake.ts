import { readFileSync, writeFileSync } from 'node:fs';
import { forgeHash } from '../../server/src/forge_relay';

type Msg = Record<string, unknown>;
const [port, roomFile, version, lifeSec, visibility, kind, modPath] = process.argv.slice(2);
const raw = modPath ? readFileSync(modPath, 'utf8') : '';
const id = raw ? (JSON.parse(raw) as { id: string }).id : '';
const entry = { id: `forge:${id}`, name: 'Room Fox', version: forgeHash(raw), author: 'Tester', size: Buffer.byteLength(raw) };
const MODS: Record<string, Msg[] | undefined> = {
  none: undefined,
  forge: [entry],
  big: [{ ...entry, size: 600 * 1024 }],
  joinfix: [{ id: 'JoinFix', name: 'Join Fix', version: '1.0.0' }],
  workshop: [{ id: 'Steamodded', name: 'Steamodded', version: '1.0.0' }, { id: 'Cryptid', name: 'Cryptid', version: '0.5.17c' }],
};
const say = (...a: unknown[]) => console.log('[fake host]', ...a);

function decode(s: string): Msg {
  const p = JSON.parse(s) as Msg;
  if (p.z === 1 && typeof p.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(p.d, 'base64'))).toString('utf8')) as Msg;
  return p;
}

const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
let joins = 0;
ws.onmessage = (ev) => {
  const m = decode(String(ev.data));
  if (m.type !== 'pong' && m.type !== 'ping') say('got', m.type, m.reason ?? '');
  if (m.type === 'forge_room_req') {
    say('asked for', m.id, m.hash);
    ws.send(JSON.stringify({ type: 'forge_room_put', rid: m.rid, mod: m.hash === entry.version ? raw : undefined }));
  }
  if (m.type === 'room_created') {
    writeFileSync(roomFile, `${String(m.code)} ${String(m.id)}\n`);
    say('room', m.code, m.visibility, 'modded', m.modded, 'forge', JSON.stringify(m.forge));
  }
  if (m.type === 'room_ready') {
    joins++;
    say(`CHECK peer joined the room: OK (${joins})`);
  }
};
await new Promise<void>((r) => { ws.onopen = () => r(); });
const mods = MODS[kind ?? 'none'];
ws.send(JSON.stringify({ type: 'create_room', visibility, name: 'FakeHost', pkey: 'H'.repeat(20) + '1234', version, ...(mods ? { mods } : {}) }));
await Bun.sleep(Number(lifeSec || 120) * 1000);
if (joins === 0) say('CHECK peer joined the room: FAIL');
ws.close();
process.exit(0);
