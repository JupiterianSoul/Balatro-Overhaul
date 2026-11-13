import { describe, it, expect } from 'bun:test';
import path from 'node:path';

const assets = process.env.BOT_LUA_ROOT ?? path.resolve(import.meta.dir, '../../assets');
const luajit = process.env.BOT_LUAJIT ?? Bun.which('luajit');

function lua(code: string, env: Record<string, string> = {}): Record<string, string> {
  const p = Bun.spawnSync([luajit!, '-e', code], { cwd: assets, env: { ...process.env, ROOT: assets, ...env }, stdout: 'pipe', stderr: 'pipe' });
  const out: Record<string, string> = {};
  for (const line of p.stdout.toString().split('\n')) {
    const i = line.indexOf('=');
    if (i > 0) out[line.slice(0, i)] = line.slice(i + 1);
  }
  out.stderr = p.stderr.toString();
  return out;
}

const HEAVY_HAND = `
local root = os.getenv("ROOT")
local H = loadfile(root .. "/bot/mp/worker.lua")("--lib", root)
H.warm({})
H.new({bot = "x", seed = "HEAVY1", deck = "b_painted", stake = 1, level = os.getenv("LEVEL"), win_ante = 99})
local s = H.bots.x.core.s
s.hand_size = 12
for _ = 1, 50 do
  local r = H.advance({bot = "x", stops = false, one = false})
  if r.ok and r.hands then break end
end
H.pvp({bot = "x", on = true})
local t = H.now()
local h = H.hand({bot = "x"})
print("ok=" .. tostring(h.ok))
print("n_hand=" .. tostring(s.n_hand))
print("ms=" .. math.floor((H.now() - t) * 1000))
`;

const SHOP = `
local root = os.getenv("ROOT")
local H = loadfile(root .. "/bot/mp/worker.lua")("--lib", root)
local PL = require("bot.seer.play")
H.warm({})
H.new({bot = "x", seed = "SHOP1", deck = "b_red", stake = 1, level = "medium", win_ante = 99})
local b = H.bots.x
local s = b.core.s
for _ = 1, 20 do
  local r = H.advance({bot = "x", stops = false, one = false})
  if r.ok and r.hands then
    for _ = 1, 10 do local h = H.hand({bot = "x"}) if not h.ok or h.over then break end end
  end
  if s.phase == "round_eval" then b.core:step({type = "cash_out"}) end
  if s.phase == "shop" then break end
end
print("phase=" .. tostring(s.phase))
PL.deadline, PL.hard = H.now() + 0.3, H.now() + 0.6
local _, why = b.core:decide()
print("why=" .. tostring(why))
`;

describe.skipIf(!luajit)('bot worker time budget', () => {
  for (const level of ['hard', 'medium']) {
    it(`a ${level} PvP hand with 12 cards stays inside its time budget`, () => {
      const r = lua(HEAVY_HAND, { LEVEL: level, BOT_TIME_SCALE: '0.2' });
      expect(r.stderr).toBe('');
      expect(r.ok).toBe('true');
      expect(Number(r.n_hand)).toBe(12);
      expect(Number(r.ms)).toBeLessThan(2500);
    }, 60000);
  }

  it('medium shop rollouts run without falling back on an error', () => {
    const r = lua(SHOP, { BOT_TIME_SCALE: '0.2' });
    expect(r.stderr).toBe('');
    expect(r.phase).toBe('shop');
    expect(r.why).not.toContain('fallback');
  }, 60000);
});
