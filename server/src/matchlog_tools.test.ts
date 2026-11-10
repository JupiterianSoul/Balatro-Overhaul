import { describe, it, expect } from 'bun:test';
import { MatchLogService, MemoryLogStore, decodeLog } from './matchlog';
import { formatLog, eventLine, maskKey, reviewSql, HELD_SQL } from '../../tools/matchlog/format';

describe('matchlog tools', () => {
  it('prints a readable log with masked keys', async () => {
    let now = Date.UTC(2026, 10, 2, 12);
    const store = new MemoryLogStore();
    const svc = new MatchLogService(store, { now: () => now });
    const host = {};
    svc.start(host, {
      id: 'abc-1', mode: 'nemesis', ranked: true, kind: '1v1', settings: { starting_lives: 4 }, ruleset: { id: 'ranked' }, seeds: ['SEEDX'],
      players: [
        { pid: 0, name: 'Ann', is_bot: false, rank: { rank: 3, tier: 2, name: 'Gold' }, version: '2.1', mods: [{ id: 'Steamodded', version: '1.0' }] },
        { pid: 1, name: 'Lou', is_bot: true, bot_level: 'hard', version: '', mods: [] },
      ],
    }, { 0: 'K'.repeat(24) });
    svc.sync(host, [4, 4]);
    now += 61_500;
    svc.observe(host, 0, { type: 'blind_entered', ante: 2, blind: 'L' }, () => true);
    svc.sync(host, [3, 4], 'pvp_resolved');
    svc.observe(host, 0, { type: 'blind_entered', ante: 6, blind: 'S' });
    svc.act(host, 0, 1, [{ k: 'play' }]);
    await svc.finish(host, { reason: 'opponent_eliminated', results: [{ pid: 0, placement: 1, result: 'win', score: '1200' }], rate: null });
    const text = formatLog(decodeLog(store.rows.get('abc-1')!.data), 'held');
    expect(text).toContain('Match abc-1');
    expect(text).toContain('nemesis, 1v1, ranked, started 2026-11-02 12:00:00 UTC');
    expect(text).toContain('P0 Ann (Gold 2) version 2.1 key KKKK...');
    expect(text).toContain('P1 Lou (bot hard)');
    expect(text).toContain('mods: Steamodded@1.0');
    expect(text).toContain('1:01.5  P0 Ann');
    expect(text).toContain('lives 3 (-1, pvp)');
    expect(text).toContain('flag        ante_jump: 2 to 6');
    expect(text).toContain('HELD unrated');
    expect(text).toContain('Replay streams: P0 1 actions');
    expect(text).not.toContain('K'.repeat(8));
    expect(eventLine({ t: 500, pid: 1, e: 'trap', to: 0, key: 'fog' }, { 1: 'Lou' })).toBe('    0:00.5  P1 Lou              trap        to=0 key=fog');
    expect(maskKey('abc')).toBe('...');
  });

  it('review only marks held matches', () => {
    expect(reviewSql('void', 'x1')).toEqual({ sql: "UPDATE match_logs SET status = ? WHERE id = ? AND status = 'held'", params: ['void', 'x1'] });
    expect(HELD_SQL).toContain("status = 'held'");
  });
});
