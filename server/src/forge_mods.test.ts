import { describe, it, expect, afterAll } from 'bun:test';
import { ForgeBoard, MemoryForgeStore, D1ForgeStore, forgeStoreFor, validateForge, checkMod, forgeHandlers, setForgeBoard, FORGE_MAX_BYTES, FORGE_PER_PAGE, FORGE_MAX_PER_OWNER, FORGE_HIDE_AT } from './forge_mods';
import { startServer } from './index';

const PNG = 'iVBORw0KGgoAAAANSUhEUgAAAEcAAABfCAYAAAA=';
const K1 = 'A'.repeat(24);
const K2 = 'B'.repeat(24);
const K3 = 'C'.repeat(24);
const K4 = 'D'.repeat(24);

function mod(o: Record<string, unknown> = {}): string {
  return JSON.stringify({
    format: 'forgemod', v: 1, id: 'abc123', name: 'Heart Pack', author: 'Tester', about: ['Hearts get stronger.'], version: 1, made: 1,
    jokers: [{ id: 'hthief', name: 'Heart Thief' }], creations: [{ id: 'ccoin', kind: 'tarot', name: 'Coin Card' }], files: { hthief: PNG }, ...o,
  });
}

function board(start = 1_000_000): { b: ForgeBoard; clock: { t: number } } {
  const clock = { t: start };
  return { b: new ForgeBoard(new MemoryForgeStore(), { now: () => clock.t }), clock };
}

describe('checkMod', () => {
  it('reads a good mod', () => {
    const c = checkMod(mod());
    expect(c.ok).toBe(true);
    if (c.ok) {
      expect(c.id).toBe('abc123');
      expect(c.summary).toEqual({ joker: 1, tarot: 1 });
      expect(c.about).toEqual(['Hearts get stronger.']);
    }
  });
  it('accepts an empty jokers object from the Lua encoder', () => {
    expect(checkMod(mod({ jokers: {} })).ok).toBe(true);
  });
  it('accepts newer format versions written by newer games', () => {
    expect(checkMod(mod({ v: 2 })).ok).toBe(true);
    expect(checkMod(mod({ v: 7 })).ok).toBe(true);
    expect(checkMod(mod({ v: 1, need: 2 })).ok).toBe(true);
  });
  it('accepts a joker made in the Builder with newer rules', () => {
    const raw = JSON.stringify({
      format: 'forgemod', v: 2, id: '82abwe', name: 'WOW', author: 'Tester', about: [], version: 1, made: 1794043249, creations: [],
      files: { et9omq: PNG },
      jokers: [{
        id: 'et9omq', name: 'WOW', v: 1, mode: 'advanced', rarity: 1, cost: 4, created: 1794042036, enabled: true, vars: [],
        art: { file: 'forge/art/et9omq.png' }, compat: { blueprint: true, eternal: true, perishable: true }, text: { en: ['{C:mult}+104{} Mult'] },
        rules: [{ when: 'card_scored', only: [], give: [{ id: 'mult', n: 104 }, { id: 'retrigger', n: 5 }] }, { when: 'card_bought', only: [{ id: 'blind', v: 'Boss' }], give: [{ id: 'money', n: 3 }] }],
      }],
    });
    const c = checkMod(raw);
    expect(c.ok).toBe(true);
    if (c.ok) expect(c.summary).toEqual({ joker: 1 });
  });
  it('refuses bad files and says why', () => {
    expect(checkMod('not json')).toEqual({ ok: false, reason: 'not_forge', why: 'not_json' });
    expect(checkMod('[1,2]')).toEqual({ ok: false, reason: 'not_forge', why: 'not_json' });
    expect(checkMod(mod({ format: 'other' }))).toEqual({ ok: false, reason: 'not_forge', why: 'bad_format' });
    expect(checkMod(mod({ v: 0 }))).toEqual({ ok: false, reason: 'not_forge', why: 'bad_version' });
    expect(checkMod(mod({ v: 1.5 }))).toEqual({ ok: false, reason: 'not_forge', why: 'bad_version' });
    expect(checkMod(mod({ v: '2' }))).toEqual({ ok: false, reason: 'not_forge', why: 'bad_version' });
    expect(checkMod(mod({ v: 100 }))).toEqual({ ok: false, reason: 'not_forge', why: 'bad_version' });
    expect(checkMod(mod({ id: '../x' }))).toEqual({ ok: false, reason: 'not_forge', why: 'bad_id' });
    expect(checkMod(mod({ jokers: 'x' }))).toEqual({ ok: false, reason: 'not_forge', why: 'bad_jokers' });
    expect(checkMod(mod({ jokers: [5] }))).toEqual({ ok: false, reason: 'not_forge', why: 'bad_joker' });
    expect(checkMod(mod({ jokers: [], creations: [] }))).toEqual({ ok: false, reason: 'empty', why: 'empty' });
    expect(checkMod(mod({ jokers: Array.from({ length: 61 }, (_, i) => ({ id: `j${i}` })) }))).toEqual({ ok: false, reason: 'too_many', why: 'too_many' });
    expect(checkMod(mod({ creations: [{ id: 'x', kind: 'nonsense' }] }))).toEqual({ ok: false, reason: 'not_forge', why: 'bad_kind' });
    expect(checkMod(mod({ files: { hthief: 'notpng=' } }))).toEqual({ ok: false, reason: 'bad_art', why: 'bad_art' });
    expect(checkMod(mod({ files: { '../evil': PNG } }))).toEqual({ ok: false, reason: 'bad_art', why: 'bad_art_name' });
    expect(checkMod(mod({ files: { big: PNG + 'A'.repeat(90 * 1024) } }))).toEqual({ ok: false, reason: 'bad_art', why: 'art_too_big' });
    expect(checkMod(mod({ files: [PNG] }))).toEqual({ ok: false, reason: 'not_forge', why: 'bad_files' });
    expect(checkMod(' '.repeat(FORGE_MAX_BYTES + 1))).toEqual({ ok: false, reason: 'too_big', why: 'too_big' });
  });
  it('cleans text', () => {
    const c = checkMod(mod({ name: 'N'.repeat(40) + '\n', about: ['a\u0001b', '', 'x'.repeat(80), 'third'] }));
    expect(c.ok && c.name.length).toBe(24);
    expect(c.ok && c.about).toEqual(['a b', 'x'.repeat(48)]);
  });
});

describe('validateForge', () => {
  it('checks the fields', () => {
    expect(validateForge({ type: 'daily_board' })).toBeNull();
    expect(validateForge({ type: 'forge_publish' })).toBe('forge_publish: missing mod');
    expect(validateForge({ type: 'forge_publish', mod: 'x'.repeat(FORGE_MAX_BYTES + 1) })).toBe('forge_publish: too big');
    expect(validateForge({ type: 'forge_browse', page: 0 })).toBe('forge_browse: invalid page');
    expect(validateForge({ type: 'forge_browse', page: 2, q: 'heart' })).toBeNull();
    expect(validateForge({ type: 'forge_get', id: 'ABC' })).toBe('forge_get: invalid id');
    expect(validateForge({ type: 'forge_report', id: 'abc123', reason: 'spam!' })).toBe('forge_report: invalid reason');
    expect(validateForge({ type: 'forge_report', id: 'abc123', reason: 'rude' })).toBeNull();
  });
});

describe('ForgeBoard', () => {
  it('publishes, updates and keeps the owner', async () => {
    const { b, clock } = board();
    expect(await b.publish(undefined, mod())).toEqual({ ok: false, reason: 'no_key' });
    expect(await b.publish(K1, mod(), true)).toEqual({ ok: false, reason: 'bot' });
    expect(await b.publish(K1, mod())).toEqual({ ok: true, id: 'abc123', version: 1, updated: false });
    expect(await b.publish(K1, mod({ version: 2 }))).toEqual({ ok: false, reason: 'too_soon' });
    clock.t += 30_000;
    expect(await b.publish(K2, mod())).toEqual({ ok: false, reason: 'taken' });
    expect(await b.publish(K1, mod({ version: 2, name: 'Heart Pack 2' }))).toEqual({ ok: true, id: 'abc123', version: 2, updated: true });
    const l = await b.browse(K2);
    expect(l.total).toBe(1);
    expect(l.mods[0].name).toBe('Heart Pack 2');
    expect(l.mods[0].mine).toBeUndefined();
    expect((await b.browse(K1)).mods[0].mine).toBe(true);
  });
  it('caps mods per owner', async () => {
    const { b, clock } = board();
    for (let i = 0; i < FORGE_MAX_PER_OWNER; i++) {
      clock.t += 30_000;
      expect((await b.publish(K1, mod({ id: `m${String(i).padStart(4, '0')}` }))).ok).toBe(true);
    }
    clock.t += 30_000;
    expect(await b.publish(K1, mod({ id: 'mlast1' }))).toEqual({ ok: false, reason: 'too_many_mods' });
  });
  it('pages, searches and lists mine', async () => {
    const { b, clock } = board();
    const keys = [K1, K2, K3, K4];
    for (let i = 0; i < FORGE_PER_PAGE + 3; i++) {
      clock.t += 30_000;
      await b.publish(keys[i % 4], mod({ id: `p${String(i).padStart(4, '0')}`, name: i === 2 ? 'Spade Set' : `Mod ${i}` }));
    }
    const p1 = await b.browse(K1, 1);
    expect(p1.pages).toBe(2);
    expect(p1.mods.length).toBe(FORGE_PER_PAGE);
    expect(p1.mods[0].id).toBe(`p${String(FORGE_PER_PAGE + 2).padStart(4, '0')}`);
    expect((await b.browse(K1, 9)).page).toBe(2);
    expect((await b.browse(K1, 1, 'spade')).mods.map(m => m.id)).toEqual(['p0002']);
    expect((await b.browse(K1, 1, '', true)).mods.every(m => m.mine)).toBe(true);
    expect(JSON.stringify(p1)).not.toContain('iVBOR');
  });
  it('gets a mod and counts downloads from others', async () => {
    const { b } = board();
    await b.publish(K1, mod());
    const g = await b.get(K2, 'abc123');
    expect(g.ok && JSON.parse(g.mod).id).toBe('abc123');
    await b.get(K1, 'abc123');
    expect((await b.browse(K2)).mods[0].downloads).toBe(1);
    expect(await b.get(K2, 'zzzz99')).toEqual({ ok: false, reason: 'gone' });
  });
  it('hides a mod after enough reports', async () => {
    const { b } = board();
    await b.publish(K1, mod());
    expect(await b.report(K1, 'abc123', 'rude')).toEqual({ ok: false, reason: 'own' });
    expect(await b.report(K2, 'abc123', 'rude')).toEqual({ ok: true });
    expect(await b.report(K2, 'abc123', 'rude')).toEqual({ ok: true });
    expect((await b.browse(K4)).total).toBe(1);
    await b.report(K3, 'abc123', 'broken');
    expect(FORGE_HIDE_AT).toBe(3);
    await b.report(K4, 'abc123', 'other');
    expect((await b.browse(K2)).total).toBe(0);
    expect((await b.browse(K1)).total).toBe(1);
    expect(await b.get(K2, 'abc123')).toEqual({ ok: false, reason: 'gone' });
    expect((await b.get(K1, 'abc123')).ok).toBe(true);
  });
  it('lets only the owner unpublish', async () => {
    const { b } = board();
    await b.publish(K1, mod());
    expect(await b.unpublish(K2, 'abc123')).toEqual({ ok: false, reason: 'not_yours' });
    expect(await b.unpublish(K1, 'abc123')).toEqual({ ok: true });
    expect((await b.browse(K1)).total).toBe(0);
  });
});

describe('stores', () => {
  it('picks D1 when the ranked store is D1', () => {
    const d1 = { kind: 'd1', query: async () => [], write: () => undefined };
    expect(forgeStoreFor(d1)).toBeInstanceOf(D1ForgeStore);
    expect(forgeStoreFor(null)).toBeInstanceOf(MemoryForgeStore);
  });
  it('writes and reads rows through D1', async () => {
    const rows = new Map<string, Record<string, unknown>>();
    const d1 = {
      kind: 'd1',
      query: async (sql: string, p: unknown[] = []) => {
        if (sql.startsWith('INSERT')) {
          const k = ['id', 'owner', 'name', 'author', 'about', 'version', 'summary', 'size', 'raw', 'at', 'updated', 'downloads', 'reports', 'hidden'];
          const r: Record<string, unknown> = {};
          k.forEach((n, i) => { r[n] = p[i]; });
          rows.set(String(p[0]), r);
        }
        if (sql.startsWith('SELECT * FROM forge_mods WHERE id')) return rows.has(String(p[0])) ? [rows.get(String(p[0]))!] : [];
        if (sql.startsWith('SELECT id')) return [...rows.values()].map(r => ({ ...r, raw: '' }));
        if (sql.startsWith('DELETE')) rows.delete(String(p[0]));
        return [];
      },
      write: () => undefined,
    };
    const b = new ForgeBoard(new D1ForgeStore(d1));
    expect((await b.publish(K1, mod())).ok).toBe(true);
    expect((await b.browse(K2)).mods[0].summary).toEqual({ joker: 1, tarot: 1 });
    expect((await b.get(K2, 'abc123')).ok).toBe(true);
    expect((await b.unpublish(K1, 'abc123')).ok).toBe(true);
  });
});

describe('handlers', () => {
  it('answers every message type', async () => {
    const { b } = board();
    setForgeBoard(b);
    const out: Record<string, unknown>[] = [];
    const h = forgeHandlers<string>({ keyOf: (ws) => ws, isBot: () => false, send: (_ws, d) => { out.push(d as Record<string, unknown>); } });
    h.forge_publish(K1, { mod: mod() });
    await Bun.sleep(5);
    h.forge_browse(K2, { page: 1 });
    h.forge_get(K2, { id: 'abc123' });
    h.forge_report(K2, { id: 'abc123', reason: 'rude' });
    h.forge_unpublish(K2, { id: 'abc123' });
    await Bun.sleep(5);
    expect(out.map(o => String(o.type)).sort()).toEqual(['forge_list', 'forge_mod', 'forge_published', 'forge_reported', 'forge_unpublished']);
    expect(out[0].ok).toBe(true);
    expect(out.find(o => o.type === 'forge_unpublished')).toEqual({ type: 'forge_unpublished', id: 'abc123', ok: false, reason: 'not_yours' });
  });
});

describe('server', () => {
  const srv = startServer(0);
  afterAll(() => srv.stop(true));
  it('publishes, browses and downloads over the socket', async () => {
    setForgeBoard(new ForgeBoard(new MemoryForgeStore()));
    const ws = new WebSocket(`ws://127.0.0.1:${srv.port}/ws`);
    const msgs: Record<string, unknown>[] = [];
    ws.onmessage = (ev) => {
      const m = JSON.parse(String(ev.data)) as Record<string, unknown>;
      if (m.z === 1 && typeof m.d === 'string') msgs.push(JSON.parse(Buffer.from(Bun.inflateSync(Buffer.from(m.d, 'base64'))).toString('utf8')));
      else msgs.push(m);
    };
    await new Promise<void>((res, rej) => { ws.onopen = () => res(); ws.onerror = () => rej(new Error('ws')); });
    const wait = async (t: string) => {
      for (let i = 0; i < 200; i++) {
        const m = msgs.find(x => x.type === t);
        if (m) return m;
        await Bun.sleep(10);
      }
      throw new Error(`no ${t}`);
    };
    const big = mod({ files: { hthief: PNG, more: 'iVBORw0KGgoA' + 'A'.repeat(60 * 1024) } });
    expect(big.length).toBeGreaterThan(4096);
    ws.send(JSON.stringify({ type: 'forge_publish', pkey: K1, mod: big }));
    expect((await wait('forge_published')).ok).toBe(true);
    ws.send(JSON.stringify({ type: 'forge_browse', pkey: K2, page: 1 }));
    const l = await wait('forge_list');
    expect((l.mods as { id: string }[])[0].id).toBe('abc123');
    ws.send(JSON.stringify({ type: 'forge_get', pkey: K2, id: 'abc123' }));
    const g = await wait('forge_mod');
    expect(g.mod).toBe(big);
    ws.send(JSON.stringify({ type: 'forge_get', id: 'BAD' }));
    const e = await wait('error');
    expect(String(e.reason)).toContain('forge_get: invalid id');
    ws.close();
  });
});
