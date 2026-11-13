import { describe, it, expect } from 'bun:test';
import path from 'node:path';

const assets = process.env.BOT_LUA_ROOT ?? path.resolve(import.meta.dir, '../../assets');
const luajit = process.env.BOT_LUAJIT ?? Bun.which('luajit');

const PROBE = `
local root = os.getenv("ROOT")
local H = loadfile(root .. "/bot/mp/worker.lua")("--lib", root)
local E = require("bot.sim.engine")
local ST = require("bot.sim.state")
local PL = require("bot.seer.play")
H.warm({})
H.new({bot = "x", seed = "HOOK1", deck = "b_red", stake = 1, level = "easy", win_ante = 99})
local s = H.bots.x.core.s
s.mp = 1
E.select_blind(s)
s.blind_chips = 1e15
local guard = 0
while s.phase == "play" and s.hands_left > 0 and guard < 20 do
  guard = guard + 1
  E.play(s, {1})
end
print("lost_phase=" .. tostring(s.phase))
print("mp_lost=" .. tostring(s.mp_lost))
print("last_chips=" .. tostring(s.last_chips))
local c = ST.clone(s)
print("clone=" .. tostring(c.mp) .. "," .. tostring(c.mp_lost))
H.new({bot = "y", seed = "HOOK2", deck = "b_red", stake = 1, level = "easy", win_ante = 99})
local p = H.bots.y.core.s
p.mp = 1
E.select_blind(p)
p.mp_pvp = 1
p.blind_chips = 1
local before = p.hands_left
E.play(p, {1})
print("pvp_phase=" .. tostring(p.phase))
print("pvp_hands=" .. tostring(before - p.hands_left))
print("deadline=" .. type(PL.out) .. "," .. type(PL.now))
local made = H.new({bot = "z", seed = "PICK1", deck = "b_plasma", stake = 1, level = "easy", win_ante = 99,
  jokers = {"j_joker", "j_mp_not_in_sim", "j_egg", "j_greedy_joker", "j_ice_cream", "j_banner", "j_mystic_summit"}})
local z = H.bots.z.core.s
local keys = {}
for k = 1, z.n_jok do keys[k] = require("bot.sim.data").JOKERS[z.j_id[k]].key end
print("picked=" .. table.concat(keys, "+"))
print("picked_added=" .. table.concat(made.jokers, "+"))
print("picked_deck=" .. tostring(z.deck_key))
local made2 = H.new({bot = "r", seed = "PICK2", deck = "b_red", stake = 1, level = "easy", win_ante = 99, jokers = {"j_joker"}, random_jokers = 2})
local rr = H.bots.r.core.s
print("random_n=" .. tostring(rr.n_jok))
print("random_added=" .. tostring(#made2.jokers))
print("random_first=" .. tostring(made2.jokers[1]))
H.new({bot = "f", seed = "PICK3", deck = "b_red", stake = 1, level = "easy", win_ante = 99, jokers = {"j_joker", "j_egg", "j_ice_cream", "j_banner"}, random_jokers = 3})
print("random_cap=" .. tostring(H.bots.f.core.s.n_jok))
local worst = 0
for i = 1, 8 do
  local id = "shop" .. i
  H.new({bot = id, seed = "SHOPLOOP" .. i, deck = "b_red", stake = 1, level = "easy", win_ante = 99, jokers = {"j_joker", "j_throwback", "j_todo_list", "j_ancient"}})
  local q = H.bots[id].core.s
  q.money = 30
  E.select_blind(q)
  q.blind_chips = 1
  E.play(q, {1})
  local g = 0
  while q.phase ~= "shop" and g < 5 do g = g + 1 E.step(q, {type = "cash_out"}) end
  local n = 0
  for _, note in ipairs(H.advance({bot = id}).log or {}) do if note.type == "reorder_jokers" then n = n + 1 end end
  worst = math.max(worst, n)
end
print("shop_moves=" .. tostring(worst))
`;

function probe(): Record<string, string> {
  const p = Bun.spawnSync([luajit!, '-e', PROBE], { cwd: assets, env: { ...process.env, ROOT: assets }, stdout: 'pipe', stderr: 'pipe' });
  const out: Record<string, string> = { stderr: p.stderr.toString() };
  for (const line of p.stdout.toString().split('\n')) {
    const i = line.indexOf('=');
    if (i > 0) out[line.slice(0, i)] = line.slice(i + 1);
  }
  return out;
}

const SYNC_HINT = 'a botlatro-sim sync dropped the multiplayer hooks; put back the bot/sim and bot/seer changes from "MP bots never leave a running match" and "MP bots keep their thinking time again"';

describe.skipIf(!luajit)('bot sim keeps the multiplayer hooks', () => {
  const r = probe();

  it('starts with the picked jokers it knows, within its joker slots, on the picked deck', () => {
    expect(r.picked).toBe('j_joker+j_egg+j_greedy_joker+j_ice_cream+j_banner');
    expect(r.picked_added).toBe(r.picked);
    expect(r.picked_deck).toBe('b_plasma');
  });

  it('moves its jokers at most twice per shop instead of looping', () => {
    expect(Number(r.shop_moves)).toBeLessThanOrEqual(2);
  });

  it('adds the room\'s random starting jokers after the listed ones, never past the slots', () => {
    expect(r.random_n).toBe('3');
    expect(r.random_added).toBe('3');
    expect(r.random_first).toBe('j_joker');
    expect(r.random_cap).toBe('5');
  });

  it('runs the probe', () => {
    expect(r.stderr).toBe('');
  });

  it('a lost blind in a match is not game over (engine.lua end_round, state.lua SCALARS)', () => {
    expect(r.lost_phase, SYNC_HINT).not.toBe('game_over');
    expect(r.lost_phase, SYNC_HINT).toBe('round_eval');
    expect(r.mp_lost, SYNC_HINT).toBe('1');
    expect(r.clone, SYNC_HINT).toBe('1,1');
  });

  it('a PvP blind keeps playing after the target is reached (engine.lua E.play)', () => {
    expect(r.pvp_phase, SYNC_HINT).toBe('play');
    expect(r.pvp_hands, SYNC_HINT).toBe('1');
  });

  it('the hand score is kept for the PvP report (engine.lua play_eval)', () => {
    expect(Number(r.last_chips), SYNC_HINT).toBeGreaterThan(0);
  });

  it('the search still has its deadline checks (seer/play.lua PL.out, PL.now)', () => {
    expect(r.deadline, SYNC_HINT).toBe('function,function');
  });
});
