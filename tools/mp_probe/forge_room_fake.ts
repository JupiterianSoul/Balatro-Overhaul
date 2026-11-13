import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { forgeHash } from '../../server/src/forge_relay';

type Msg = Record<string, unknown>;
const [mode, port, modPath, roomFile, version, lifeSec] = process.argv.slice(2);
const raw = readFileSync(modPath, 'utf8');
const id = (JSON.parse(raw) as { id: string }).id;
const entry = { id: `forge:${id}`, name: 'Room Fox', version: forgeHash(raw), author: 'Tester', size: Buffer.byteLength(raw) };
const say = (...a: unknown[]) => console.log(`[fake ${mode}]`, ...a);

function decode(s: string): Msg {
  const p = JSON.parse(s) as Msg;
  if (p.z === 1 && typeof p.d === 'string') return JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(p.d, 'base64'))).toString('utf8')) as Msg;
  return p;
}

const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
const waiters: { pred: (m: Msg) => boolean; res: (m: Msg) => void }[] = [];
ws.onmessage = (ev) => {
  const m = decode(String(ev.data));
  if (m.type !== 'pong' && m.type !== 'ping') say('got', m.type, m.reason ?? '', m.ok ?? '');
  if (m.type === 'forge_room_req') {
    say('host asked for', m.id, m.hash);
    ws.send(JSON.stringify({ type: 'forge_room_put', rid: m.rid, mod: m.hash === entry.version ? raw : undefined }));
  }
  for (let i = waiters.length - 1; i >= 0; i--) if (waiters[i].pred(m)) { waiters[i].res(m); waiters.splice(i, 1); }
};
const wait = (pred: (m: Msg) => boolean, ms = 60000) => new Promise<Msg>((res, rej) => {
  const t = setTimeout(() => rej(new Error('timeout')), ms);
  waiters.push({ pred, res: (m) => { clearTimeout(t); res(m); } });
});
await new Promise<void>((r) => { ws.onopen = () => r(); });
const send = (m: Msg) => ws.send(JSON.stringify(m));

if (mode === 'host') {
  send({ type: 'create_room', visibility: 'private', name: 'FakeHost', pkey: 'H'.repeat(20) + '1234', version, mods: [entry] });
  const c = await wait(m => m.type === 'room_created');
  writeFileSync(roomFile, `${String(c.code)} ${String(c.id)}\n`);
  say('room', c.code, 'forge', JSON.stringify(c.forge));
  const r = await wait(m => m.type === 'room_ready', Number(lifeSec || 120) * 1000).catch(() => null);
  say(r ? 'CHECK peer joined the room: OK' : 'CHECK peer joined the room: FAIL');
  if (r) writeFileSync(roomFile + '.joined', '1');
  await Bun.sleep(Number(lifeSec || 120) * 1000);
} else {
  const until = Date.now() + 90000;
  while (!existsSync(roomFile) && Date.now() < until) await Bun.sleep(300);
  const [code] = readFileSync(roomFile, 'utf8').trim().split(' ');
  send({ type: 'join_room', code, name: 'FakeJoin', pkey: 'J'.repeat(20) + '1234', version });
  const miss = await wait(m => m.type === 'room_error' || m.type === 'room_ready');
  const forgeRow = (miss.hostMods as Msg[] | undefined)?.find(x => String(x.id).startsWith('forge:'));
  say(miss.reason === 'mods_mismatch' && forgeRow ? 'CHECK joiner without the mod gets Mods Required: OK' : `CHECK joiner without the mod gets Mods Required: FAIL ${String(miss.type)} ${String(miss.reason)}`);
  const want = { room: miss.id, id: String(forgeRow?.id).slice(6), hash: String(forgeRow?.version) };
  send({ type: 'forge_room_get', ...want });
  const got = await wait(m => m.type === 'forge_room_mod');
  const sameHash = got.ok === true && forgeHash(String(got.mod)) === want.hash && want.hash === entry.version;
  say(sameHash ? 'CHECK relayed Forge mod matches the room hash: OK' : `CHECK relayed Forge mod matches the room hash: FAIL ${String(got.reason)}`);
  send({ type: 'join_room', code, name: 'FakeJoin', pkey: 'J'.repeat(20) + '1234', version, mods: [{ ...entry, version: want.hash }] });
  const ready = await wait(m => m.type === 'room_ready' || m.type === 'room_error');
  say(ready.type === 'room_ready' ? 'CHECK joiner with the same hash joins: OK' : `CHECK joiner with the same hash joins: FAIL ${String(ready.reason)}`);
  say('room forge', JSON.stringify(ready.forge));
  if (ready.type === 'room_ready') writeFileSync(roomFile + '.joined', '1');
  await Bun.sleep(Number(lifeSec || 20) * 1000);
}
ws.close();
process.exit(0);
