import { describe, it, expect } from 'bun:test';
import { wipeForEpoch } from './ranked_store';

function fakeD1(tables: string[], epoch?: string) {
  const sqls: string[] = [];
  let stored = epoch;
  return {
    sqls,
    store: {
      kind: 'd1',
      async query(sql: string, params: unknown[] = []) {
        sqls.push(sql);
        if (sql.startsWith('SELECT v FROM data_meta')) return stored ? [{ v: stored }] : [];
        if (sql.startsWith('SELECT name FROM sqlite_master')) return tables.map(name => ({ name }));
        if (sql.startsWith('INSERT OR REPLACE INTO data_meta')) stored = String(params[1]);
        return [];
      },
    },
  };
}

describe('data epoch wipe', () => {
  it('empties every account, replay and Forge mod table once, keeps seasons', async () => {
    const d = fakeD1(['players', 'match_logs', 'speedrun_replays', 'social_links', 'seasons', 'forge_mods', 'data_meta', '_cf_KV', 'sqlite_sequence']);
    const wiped = await wipeForEpoch(d.store, 'E1');
    expect(wiped).toEqual(['players', 'match_logs', 'speedrun_replays', 'social_links', 'forge_mods']);
    expect(d.sqls.filter(s => s.startsWith('DELETE')).length).toBe(5);
    expect(await wipeForEpoch(d.store, 'E1')).toEqual([]);
  });
  it('does nothing on the memory store', async () => {
    expect(await wipeForEpoch({ kind: 'memory' }, 'E1')).toEqual([]);
  });
});
