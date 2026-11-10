import { describe, it, expect } from 'bun:test';
import { readFileSync } from 'node:fs';
import { D1Store, MemoryStore } from './ranked_store';
import { SOCIAL2_SCHEMA, CHAT_REPORTS_STATUS_SQL, D1Extra, MemoryExtra, socialExtraFor } from './social_store';

async function drain(store: D1Store): Promise<void> {
  for (let i = 0; i < 100 && store.pending() > 0; i++) await new Promise(r => setTimeout(r, 0));
}

function d1() {
  const calls: { sql: string; params: unknown[] }[] = [];
  let rows: Record<string, unknown>[] = [];
  const store = new D1Store({
    accountId: 'x', databaseId: 'y', token: 'z',
    fetch: (async (_u: string, i: { body: string }) => {
      const body = JSON.parse(i.body);
      calls.push({ sql: body.sql, params: body.params });
      return { ok: true, status: 200, json: async () => ({ success: true, result: [{ results: rows }] }) };
    }) as never,
  });
  return { store, calls, extra: new D1Extra(store), setRows: (r: Record<string, unknown>[]) => { rows = r; } };
}

describe('social store schema', () => {
  it('the migration file matches what the server creates', () => {
    const norm = (s: string) => s.replace(/\s+/g, ' ').trim();
    const file = readFileSync(new URL('../migrations/0003_social_chat.sql', import.meta.url), 'utf8');
    expect(file.split(';').map(norm).filter(Boolean)).toEqual(SOCIAL2_SCHEMA.map(norm));
  });

  it('only uses create if not exists, so running it twice is safe', () => {
    for (const sql of SOCIAL2_SCHEMA) expect(sql).toMatch(/^CREATE (TABLE|INDEX) IF NOT EXISTS /);
  });

  it('stores the age answer as a yes or no and never a year', () => {
    const prefs = SOCIAL2_SCHEMA.find(s => s.includes('social_prefs ('));
    expect(prefs).toContain('chat_allowed INTEGER');
    expect(prefs?.toLowerCase()).not.toContain('birth');
    expect(prefs?.toLowerCase()).not.toContain('year');
  });

  it('picks the right store for each ranked store', () => {
    expect(socialExtraFor(new MemoryStore())).toBeInstanceOf(MemoryExtra);
    expect(socialExtraFor(d1().store)).toBeInstanceOf(D1Extra);
  });
});

describe('D1 social store', () => {
  it('creates every table through its query path', async () => {
    const { extra, calls } = d1();
    await extra.init();
    expect(calls.map(c => c.sql)).toEqual([...SOCIAL2_SCHEMA, CHAT_REPORTS_STATUS_SQL]);
  });

  it('searches names with an escaped like pattern', async () => {
    const { extra, calls, setRows } = d1();
    setRows([{ pkey: 'P', code: 'ABCD-EFGH', name: 'Zob', last_seen: 5, rp: null }]);
    const hits = await extra.searchNames('50%_a\\b', 7);
    expect(calls[0].params).toEqual(['%50\\%\\_a\\\\b%', 7]);
    expect(calls[0].sql).toContain("ESCAPE '\\'");
    expect(hits).toEqual([{ pkey: 'P', code: 'ABCD-EFGH', name: 'Zob', last_seen: 5, rp: null }]);
  });

  it('reads and writes chat settings as numbers', async () => {
    const { store, extra, calls, setRows } = d1();
    extra.prefsSetChat('P', true, true);
    extra.prefsSetChat('P', false, null);
    await drain(store);
    expect(calls.map(c => c.params)).toEqual([['P', 1, 1], ['P', 0, null]]);
    setRows([{ chat_enabled: 1, chat_allowed: 0, rp: 12 }]);
    expect(await extra.prefsGet('P')).toEqual({ chat_enabled: true, chat_allowed: false, rp: 12 });
    setRows([{ chat_enabled: 0, chat_allowed: null, rp: null }]);
    expect(await extra.prefsGet('P')).toEqual({ chat_enabled: false, chat_allowed: null, rp: null });
    setRows([]);
    expect(await extra.prefsGet('P')).toBeNull();
  });

  it('keeps the name key when a touch has no name', async () => {
    const { store, extra, calls } = d1();
    extra.prefsTouch('P', '', 100);
    await drain(store);
    expect(calls[0].sql).toContain("CASE WHEN excluded.name_key = ''");
    expect(calls[0].sql).toContain('COALESCE(excluded.rp, social_prefs.rp)');
    expect(calls[0].params).toEqual(['P', '', 100]);
  });

  it('prunes a conversation to the newest rows', async () => {
    const { store, extra, calls } = d1();
    extra.dmPrune('A:B', 100);
    await drain(store);
    expect(calls[0].sql).toContain('NOT IN (SELECT id FROM chat_dms WHERE conv = ? ORDER BY at DESC, id DESC LIMIT ?)');
    expect(calls[0].params).toEqual(['A:B', 'A:B', 100]);
  });

  it('pages a conversation by time', async () => {
    const { extra, calls, setRows } = d1();
    setRows([{ id: 'd1', conv: 'A:B', sender: 'A', at: 3, text: 'hi' }]);
    expect(await extra.dmHistory('A:B', 10, 100)).toEqual([{ id: 'd1', conv: 'A:B', sender: 'A', at: 3, text: 'hi' }]);
    expect(calls[0].params).toEqual(['A:B', 10, 100]);
    await extra.dmHistory('A:B', null, 50);
    expect(calls[1].params).toEqual(['A:B', Number.MAX_SAFE_INTEGER, 50]);
  });

  it('counts unread with an upsert', async () => {
    const { store, extra, calls, setRows } = d1();
    extra.unreadBump('A', 'B');
    extra.unreadClear('A', 'B');
    await drain(store);
    expect(calls[0].sql).toContain('ON CONFLICT (pkey, other) DO UPDATE SET n = n + 1');
    expect(calls[1].sql).toContain('DELETE FROM chat_unread');
    setRows([{ other: 'B', n: 4 }]);
    expect(await extra.unreadAll('A')).toEqual(new Map([['B', 4]]));
  });

  it('stores notifications as json and reads them back', async () => {
    const { store, extra, calls, setRows } = d1();
    extra.notifyAdd({ id: 'n1', pkey: 'P', kind: 'invite', at: 9, read: false, data: { room: 'AB12', party: true }, expires: 99 });
    await drain(store);
    expect(calls[0].params).toEqual(['n1#P', 'P', 'invite', 9, 0, '{"room":"AB12","party":true}', 99]);
    setRows([
      { id: 'n1#P', kind: 'invite', at: 9, read: 1, data: '{"room":"AB12"}', expires: 99 },
      { id: 'n2', kind: 'error', at: 8, read: 0, data: 'not json', expires: null },
    ]);
    expect(await extra.notifyList('P')).toEqual([
      { id: 'n1', pkey: 'P', kind: 'invite', at: 9, read: true, data: { room: 'AB12' }, expires: 99 },
      { id: 'n2', pkey: 'P', kind: 'error', at: 8, read: false, data: {}, expires: null },
    ]);
  });

  it('marks and deletes one or all notifications', async () => {
    const { store, extra, calls } = d1();
    extra.notifyRead('P', 'n1');
    extra.notifyRead('P', null);
    extra.notifyDelete('P', 'n1');
    extra.notifyDelete('P', null);
    await drain(store);
    expect(calls.map(c => [c.sql, c.params])).toEqual([
      ['UPDATE notify_items SET read = 1 WHERE pkey = ? AND id IN (?, ?)', ['P', 'n1', 'n1#P']],
      ['UPDATE notify_items SET read = 1 WHERE pkey = ?', ['P']],
      ['DELETE FROM notify_items WHERE pkey = ? AND id IN (?, ?)', ['P', 'n1', 'n1#P']],
      ['DELETE FROM notify_items WHERE pkey = ?', ['P']],
    ]);
  });

  it('stores a report with its context and match id', async () => {
    const { store, extra, calls } = d1();
    extra.reportAdd({ id: 'r', reporter: 'A', reported: 'B', kind: 'lobby', msg_id: 'l1', text: 'hi', context: '[]', reason: 'spam', match_id: null, at: 5 });
    await drain(store);
    expect(calls[0].sql).toContain('INSERT OR IGNORE INTO chat_reports');
    expect(calls[0].params).toEqual(['r', 'A', 'B', 'lobby', 'l1', 'hi', '[]', 'spam', null, 5]);
  });

  it('looks up many players or prefs in chunks', async () => {
    const { extra, calls, setRows } = d1();
    setRows([]);
    const keys = Array.from({ length: 120 }, (_, i) => `k${i}`);
    await extra.prefsMany(keys);
    await extra.players(keys);
    expect(calls.map(c => c.params.length)).toEqual([50, 50, 20, 50, 50, 20]);
  });
});

describe('memory social store', () => {
  it('prunes by conversation and keeps the newest', async () => {
    const x = new MemoryExtra();
    for (let i = 0; i < 10; i++) x.dmAdd({ id: `d${i}`, conv: 'A:B', sender: 'A', at: i, text: `${i}` });
    x.dmAdd({ id: 'other', conv: 'A:C', sender: 'A', at: 1, text: 'x' });
    x.dmPrune('A:B', 3);
    expect((await x.dmHistory('A:B', null, 100)).map(d => d.text)).toEqual(['9', '8', '7']);
    expect(await x.dmGet('other')).not.toBeNull();
  });

  it('adds a duplicate message only once', async () => {
    const x = new MemoryExtra();
    x.dmAdd({ id: 'd', conv: 'A:B', sender: 'A', at: 1, text: 'a' });
    x.dmAdd({ id: 'd', conv: 'A:B', sender: 'A', at: 1, text: 'a' });
    expect(x.dms).toHaveLength(1);
  });
});
