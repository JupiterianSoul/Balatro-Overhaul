import { describe, expect, it } from 'bun:test';
import { readFileSync } from 'fs';
import { join } from 'path';
import { dailyRuleset, rankedRuleset, DAILY_POOL, BALANCED_REWORKS } from './rulesets_server';

const MP = join(import.meta.dir, '..', '..', 'assets', 'multiplayer');

function luaIds(file: string, pattern: RegExp): Set<string> {
  const src = readFileSync(join(MP, file), 'utf8');
  const out = new Set<string>();
  for (const m of src.matchAll(pattern)) out.add(m[1]);
  return out;
}

const clientLayers = luaIds('bom_layers.lua', /M\.register\{id = "([a-z_]+)"/g);
const clientRulesets = new Set<string>([
  ...luaIds('bom_rulesets.lua', /R\.register\{id = "([a-z_]+)"/g),
  ...[...readFileSync(join(MP, 'bom_rulesets.lua'), 'utf8').matchAll(/family\("([a-z]+)", "([a-z_]+)"/g)].map(m => `${m[1]}_${m[2]}`),
]);

describe('L9 rulesets and layers on the server', () => {
  it('every daily layer and preset exists on the client', () => {
    expect(clientLayers.size).toBeGreaterThanOrEqual(15);
    for (const l of DAILY_POOL.layers) expect(clientLayers.has(l.id)).toBe(true);
    for (const p of DAILY_POOL.presets) expect(clientRulesets.has(p.id)).toBe(true);
  });

  it('layers that share a group on the client share it on the server', () => {
    const src = readFileSync(join(MP, 'bom_layers.lua'), 'utf8');
    for (const m of src.matchAll(/M\.register\{id = "([a-z_]+)", cat = "[a-z]+", group = "([a-z_]+)"/g)) {
      const l = DAILY_POOL.layers.find(x => x.id === m[1]);
      expect(l?.group).toBe(m[2]);
    }
  });

  it('daily rulesets carry the preset id, its bans and its reworks', () => {
    for (let i = 0; i < 40; i++) {
      const d = dailyRuleset(i % 2 ? 'weekly' : 'daily', Date.UTC(2026, 10, 1 + i));
      const p = DAILY_POOL.presets.find(x => x.id === d.ruleset.base);
      expect(p).toBeDefined();
      expect(d.ruleset.reworks).toEqual(p?.reworks ?? []);
      expect(d.ruleset.bans.consumables).toEqual(p?.bans?.consumables ?? []);
      expect(Object.keys(d.ruleset.bans).sort()).toEqual(['blinds', 'consumables', 'jokers', 'tags', 'vouchers']);
      for (const id of d.ruleset.layers) expect(clientLayers.has(id)).toBe(true);
    }
  });

  it('ranked uses the Balanced reworks and bans Justice', () => {
    const r = rankedRuleset();
    expect(r.reworks).toEqual(BALANCED_REWORKS);
    expect(r.bans.consumables).toContain('c_justice');
    const src = readFileSync(join(MP, 'bom_rulesets.lua'), 'utf8');
    expect(src).toContain('timer_base_seconds = 150');
    expect(src).toContain('hide_opp_score = true, layers = {}, ruleset_id = "ranked"');
  });
});
