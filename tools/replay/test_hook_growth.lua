local root = arg and arg[1] or "."
package.path = root .. "/assets/?.lua;" .. package.path
function mod_loc(s) return s end
function mod_loc_register() end

local calls = 0
G = { FUNCS = {}, STATES = {} }
G.FUNCS.discard_cards_from_highlighted = function() calls = calls + 1 return "ok" end
G.FUNCS.evaluate_play = function() return "ok" end
love = love or {}
love.update = function() end

local Hooks = require("overhaul.hooks")
Hooks.wrap("G.FUNCS", "discard_cards_from_highlighted", function(orig) return function(e, hook, ...)
  return orig(e, hook, ...)
end end, {id = "test.discard"})

local RP = dofile(root .. "/assets/multiplayer/bom_replay.lua")

local function depth(f)
  local n, seen = 0, {}
  while f and n < 100000 do
    if seen[f] then break end
    seen[f] = true
    n = n + 1
    local i = 1
    local nxt
    while true do
      local name, v = debug.getupvalue(f, i)
      if not name then break end
      if (name == "cur" or name == "current" or name == "orig") and type(v) == "function" then nxt = v end
      i = i + 1
    end
    f = nxt
  end
  return n
end

local fails = 0
for _ = 1, 3 do RP.install_hooks() Hooks.reapply() end
local d0 = depth(G.FUNCS.discard_cards_from_highlighted)
for _ = 1, 2000 do RP.install_hooks() Hooks.reapply() end
local d1 = depth(G.FUNCS.discard_cards_from_highlighted)
if d1 ~= d0 then fails = fails + 1 print("FAIL discard chain grew " .. d0 .. " -> " .. d1) end
local ok, r = pcall(G.FUNCS.discard_cards_from_highlighted, {}, false)
if not ok or r ~= "ok" or calls ~= 1 then fails = fails + 1 print("FAIL discard call", ok, r, calls) end
local e0 = depth(G.FUNCS.evaluate_play)
for _ = 1, 500 do RP.install_hooks() Hooks.reapply() end
if depth(G.FUNCS.evaluate_play) ~= e0 then fails = fails + 1 print("FAIL eval chain grew") end
print(("hook growth: discard depth %d, %s"):format(d1, fails == 0 and "OK" or (fails .. " FAIL")))
os.exit(fails == 0 and 0 or 1)
