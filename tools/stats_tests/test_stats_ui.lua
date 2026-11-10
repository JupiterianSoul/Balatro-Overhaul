package.path = "assets/?.lua;" .. package.path
local fails, passes = 0, 0
local function ok(cond, msg)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL " .. msg) end
end

local white = {1, 1, 1, 1}
G = {
  SETTINGS = {language = "en-us", profile = 1}, FUNCS = {}, PROFILES = {[1] = {}},
  C = setmetatable({UI = setmetatable({}, {__index = function() return white end})}, {__index = function() return white end}),
  UIT = {T = 1, B = 2, C = 3, R = 4, O = 5, ROOT = 7},
}
love = {filesystem = {getInfo = function() return nil end, read = function() return nil end, write = function() return true end, remove = function() end}}
package.preload["functions/fast_fs"] = function() return {write = function() return true end, read = function() return nil end} end
dofile("assets/functions/mod_localization.lua")
dofile("assets/functions/overhaul_stats.lua")
dofile("assets/functions/ui_kit.lua")
function UIBox(t) return t end
function UIBox_button(o) return {n = G.UIT.C, config = {button = o.button, minw = o.minw, scale = o.scale}, nodes = {}} end
function create_UIBox_generic_options(a) return {config = {}, args = a} end
function localize(k) return k end
local opened
G.FUNCS.overlay_menu = function(o) opened = o.definition end
dofile("assets/functions/stats_ui.lua")
dofile("assets/functions/achievements_ui.lua")
local SU, AU = Overhaul.stats_ui, Overhaul.achievements_ui

local built_ok = true
local raw_print = print
print = function(...)
  local m = tostring((...))
  if m:find("[UIK] tab", 1, true) then built_ok = false; raw_print(m:sub(1, 300)) end
end

local function find(node, pred)
  if type(node) ~= "table" then return nil end
  if pred(node) then return node end
  for _, v in pairs(node) do
    if type(v) == "table" then
      local r = find(v, pred)
      if r then return r end
    end
  end
end

local function views(fn)
  for _, v in ipairs({{desk = true}, {desk = false}, {desk = false, port = true}}) do
    _G._IS_DESKTOP = v.desk
    PORTRAIT = v.port and {on = function() return true end} or nil
    UIK.sync()
    fn((v.port and "portrait") or (v.desk and "desktop") or "phone")
  end
  _G._IS_DESKTOP, PORTRAIT = nil, nil
  UIK.sync()
end

ok(type(G.FUNCS.open_mp_achievements) == "function", "MP achievements opener exists")
G.FUNCS.open_mp_achievements()
ok(AU.back == "mp_stats", "Back from MP achievements goes to MP Stats")
ok(UIK._last_tab.ach == "Multiplayer", "MP achievements open on the Multiplayer tab")
ok(opened and opened.args and opened.args.back_func == "mp_stats", "window Back button is mp_stats")
G.FUNCS.open_achievements()
ok(AU.back == "high_scores", "Back from Stats achievements goes to Stats")

views(function(v)
  local mp = create_UIBox_mp_stats()
  ok(find(mp, function(n) return n.config and n.config.button == "open_mp_achievements" end) ~= nil, v .. ": MP Stats footer links to achievements")
  local st = create_UIBox_high_scores()
  for _, b in ipairs({"usage", "mp_stats", "open_achievements"}) do
    ok(find(st, function(n) return n.config and n.config.button == b end) ~= nil, v .. ": Stats footer has " .. b)
  end
  local fw = SU.foot_w()
  local back = (UIK.touch() and not UIK.portrait()) and (3.0 * 1.5 + 0.2) or 0
  ok(3 * fw + back + 0.12 * 5 <= UIK.W + 1e-9, v .. ": Stats footer fits the window width")

  local list = {}
  for i = 1, 16 do list[i] = {"Label " .. i, tostring(i), nil, i % 2 == 0 and "sub" or nil} end
  local grid = SU.tiles(list)
  local tile = find(grid, function(n) return n.config and n.config.r == 0.12 and n.config.emboss == 0.05 end)
  local per = UIK.portrait() and 2 or 4
  local rows = math.ceil(16 / per)
  local h = tile and tile.config.minh or 99
  ok(UIK.TOP + 0.08 + rows * (h + 0.12 + 0.05 * per) <= UIK.H + 1e-9, v .. ": 16 tiles fit the tab height")
  local inner = 0.16
  for _, r in ipairs(tile and tile.nodes or {}) do inner = inner + (r.config.minh or 0) end
  ok(inner <= h + 1e-9, v .. ": tile rows fit inside the tile")

  local cw, ch = AU.card_size()
  local cols = AU.cols()
  local per_page = AU.per_page()
  local pager = (UIK.touch() and 0.82 or 0.66) + 0.12
  ok(UIK.TOP + 0.08 + (per_page / cols) * (ch + 0.08 + 0.05 * cols) + pager <= UIK.H + 1e-9, v .. ": a page of achievement cards fits the tab height")
  ok(per_page >= (UIK.portrait() and 8 or 8), v .. ": at least 8 achievements per page")
end)

local d = Overhaul.stats.data()
if d then
  d.mp.legacy.played, d.mp.legacy.wins, d.mp.best = 10, 8, 0
  UIK._last_tab.omps = "overview"
  local win = create_UIBox_mp_stats()
  local tile = find(win, function(n)
    return n.config and n.config.r == 0.12 and n.nodes and n.nodes[1] and find(n.nodes[1], function(x) return x.config and x.config.text == "Best win streak" end) ~= nil
  end)
  local val = tile and find(tile.nodes[2], function(x) return x.config and x.config.text end)
  ok(val and val.config.text == "1", "old save with 8 wins shows a best streak of at least 1, got " .. tostring(val and val.config.text))
else
  ok(false, "stats data available")
end

mod_loc_register{es = {["Played"] = "Jugada", ["Win rate"] = "Porcentaje de victorias"}, fr = {["Achievements"] = "Accomplissements"}}
G.SETTINGS.language = "es_ES"
ok(SU.L("Played") == "Jugadas", "Stats keep their own Spanish for Played")
ok(SU.L("Win rate") == "Tasa de victorias", "Stats keep their own Spanish for Win rate")
ok(SU.L("Completion") == "Avance", "new Progress title in Spanish")
G.SETTINGS.language = "fr"
ok(SU.L("Most wins") == "Plus de victoires", "new MP tile in French")
ok(SU.L("Page %d of %d") == "Page %d sur %d", "pager in French")
ok(AU.L("ACHIEVEMENTS") ~= "ACHIEVEMENTS", "achievements title in French")
ok(AU.L("Outscore your opponent in 25 blinds") == "Battre le score de votre adversaire sur 25 blindes", "blinds achievement in French")
G.SETTINGS.language = "en-us"

ok(built_ok, "every Overview tab built without an error")
print = raw_print
print(string.format("stats ui tests: %d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
