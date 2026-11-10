package.path = "assets/?.lua;" .. package.path

local fails, total = 0, 0
local function check(name, ok)
  total = total + 1
  if not ok then fails = fails + 1; print("FAIL " .. name) end
end

local files, dirs = {}, {}
love = {filesystem = {
  getInfo = function(p) if files[p] then return {type = "file"} end if dirs[p] then return {type = "directory"} end return nil end,
  read = function(p) if files[p] then return files[p], #files[p] end return nil, "missing" end,
  write = function(p, d) files[p] = d return true end,
  createDirectory = function(p) dirs[p] = true return true end,
  remove = function(p) files[p] = nil return true end,
  getSaveDirectory = function() return "/save" end,
  getDirectoryItems = function(dir)
    local out = {}
    for p in pairs(files) do
      local name = p:match("^" .. dir:gsub("%p", "%%%0") .. "/([^/]+)$")
      if name then out[#out + 1] = name end
    end
    return out
  end,
}}
package.loaded["functions/fast_fs"] = {write = function(p, d) files[p] = tostring(d) return true end}
mod_loc = function(s) return s end

local Store = require("functions/forge/forge_store")
local M = require("functions/forge/forge_mods")
local FJ = require("functions/forge/forge_joker")
local R = require("functions/forge/forge_room")

local function png(tag, pad)
  local function u32(n) return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256) end
  return "\137PNG\r\n\26\n" .. u32(13) .. "IHDR" .. u32(71) .. u32(95) .. "\8\6\0\0\0" .. tag .. string.rep("\0\255\1", pad or 30)
end

local saves = {}
local function profile(name)
  if saves.current then saves[saves.current] = files end
  files = saves[name] or {}
  dirs = {forge = true, ["forge/art"] = true}
  saves.current = name
  Store.list, Store.items_list, Store.settings, Store.room = nil, nil, nil, nil
  M.index, M.list, M.jokers, M.items = nil, {}, {}, {}
  R.raw, R.info, R.manual = nil, nil, false
  pcall(M.load)
end

local function ids(list)
  local t = {}
  for _, c in ipairs(list) do t[#t + 1] = c.id end
  return table.concat(t, ",")
end

check("global", rawget(_G, "ForgeRoom") == R)

profile("host")
files["forge/art/hhh111.png"] = png("H")
Store.put({id = "hhh111", name = "Heart Thief", rarity = 2, cost = 6, art = {file = "forge/art/hhh111.png"}, rules = {}})
Store.put({id = "hhh222", name = "Plain", rarity = 1, cost = 4, art = {atlas = "Joker", x = 3, y = 2}})
Store.put({id = "hhh333", name = "Off One", enabled = false})
Store.put_item({id = "hhh444", kind = "tarot", name = "Coin Card", fields = {}, effects = {}})
Store.put_item({id = "hhh555", kind = "collab", name = "Court", faces = {J = "forge/art/hhh111.png"}})
check("host lists", #Store.live_jokers() == 3 and #Store.live_items() == 2)

local raw, info = R.pack()
check("pack ok", type(raw) == "string" and info.count == 3)
check("pack skips off and collab", info.jokers == 2 and info.items == 1)
check("pack art", info.art == 1 and info.dropped == 0)
check("pack fits", info.bytes <= R.MAX_BYTES)
check("pack is a forgemod", M.parse(raw) ~= nil)
check("pack keeps own lists", #Store.live_jokers() == 3)

check("too small budget", select(2, R.pack(50)) == "too_big")
local raw_small, info_small = R.pack(info.bytes - 100)
check("art dropped first", raw_small and info_small.art == 0 and info_small.dropped == 1)
local plain = raw_small and M.parse(raw_small)
check("dropped art falls back", plain and plain.jokers[1].art and plain.jokers[1].art.atlas == "Joker")
check("atlas art kept", plain and plain.jokers[2].art.atlas == "Joker" and plain.jokers[2].art.x == 3)

check("enter", R.enter(raw) == true and R.active())
local host_j, host_i = ids(Store.live_jokers()), ids(Store.live_items())
check("host room ids", host_j == "mproom01,mproom02" and host_i:find("^mproom03") ~= nil)
check("own collab stays", host_i:find("hhh555", 1, true) ~= nil and #Store.live_items() == 2)
check("room art extracted", files["forge/art/fm_mproom_r01art.png"] == files["forge/art/hhh111.png"])
check("get room joker", Store.get("mproom01") and Store.get("mproom01").name == "Heart Thief")
check("get room item", Store.get_item("mproom03") and Store.get_item("mproom03").kind == "tarot")
check("own still in builder lists", #Store.all() == 3 and #Store.items() == 2)
check("summary", R.summary() == "3 Forge creations in this match")
check("enter same again", R.enter(raw) == true)

profile("guest")
Store.put({id = "ggg111", name = "Guest Only", rarity = 3})
Store.put_item({id = "ggg222", kind = "planet", name = "Guest Planet", fields = {}, effects = {}})
check("guest lists", ids(Store.live_jokers()) == "ggg111")
check("guest enter", R.enter(raw) == true)
check("guest same jokers", ids(Store.live_jokers()) == host_j)
check("guest same items", ids(Store.live_items()) == "mproom03")
check("guest own out", Store.get("ggg111") ~= nil and not ids(Store.live_jokers()):find("ggg111", 1, true))
check("guest art", files["forge/art/fm_mproom_r01art.png"] ~= nil)
R.leave()
check("leave", not R.active() and ids(Store.live_jokers()) == "ggg111" and ids(Store.live_items()) == "ggg222")
check("leave art", files["forge/art/fm_mproom_r01art.png"] == nil)

check("bad payload", select(2, R.enter("{}")) == "not_room" and not R.active())
local t = require("bot.sim.json").decode(raw)
t.room = 99
check("newer payload", select(2, R.enter(require("bot.sim.json").encode(t))) == "newer")
t.room, t.id = 1, "abcd12"
check("normal mod is not a room", select(2, R.enter(require("bot.sim.json").encode(t))) == "not_room")

local settings, phase, state, syncs, in_match = {}, "none", {}, 0, false
state.settings = settings
bom_match = {
  get_phase = function() return phase end,
  get_settings = function() return settings end,
  get_state = function() return state end,
  is_host_player = function() return true end,
  update_settings = function(s) for k, v in pairs(s) do if k ~= "forge_room" or settings.forge_room ~= nil then settings[k] = v end end end,
  sync_settings = function() syncs = syncs + 1 end,
  is_in_match = function() return in_match end,
}
G = {GAME = {}}
check("solo allowed", FJ.allowed_here() == true and not R.active())
phase = "lobby"
check("lobby without key", FJ.allowed_here() == true and not R.active())
check("host_set refused without lobby key", select(2, R.host_set(true)) == "lobby" and settings.forge_room == nil)
bom_match.DEFAULT_SETTINGS = {mode = "nemesis", the_order = false, forge_room = ""}
settings.forge_room = ""
bom_lobby_settings = {DEFS = {{key = "multiplayer_jokers", tab = "match"}, {key = "the_order", tab = "match"}, {key = "different_seeds", tab = "players"}}, BY_KEY = {}}
check("install", R.install() and type(settings.forge_room) == "table" and settings.forge_room_on == false
  and bom_match.DEFAULT_SETTINGS.forge_room_on == false and type(bom_match.DEFAULT_SETTINGS.forge_room) == "table")
local def = bom_lobby_settings.DEFS[4]
check("lobby row after the last Match row", bom_lobby_settings.DEFS[3].header == "The Forge" and def.key == "forge_room_on" and def.kind == "toggle"
  and def.tab == "match" and def.label == "Forge creations" and bom_lobby_settings.BY_KEY.forge_room_on == def and def.show({}) == true
  and bom_lobby_settings.DEFS[5].key == "different_seeds" and def.info_fn() == "Everyone plays with the host's creations")
R.install()
check("lobby row once", #bom_lobby_settings.DEFS == 5)
check("lobby ready", R.lobby_ready())
check("host_set off", R.host_set(false) == true and R.raw_of(settings.forge_room) == nil and settings.forge_room_on == false and not R.host_on())
local before = syncs
bom_match.sync_settings()
check("sync still sends", syncs == before + 1)
profile("empty")
R.refused = nil
settings.forge_room_on = true
bom_match.sync_settings()
check("toggle with nothing to share", settings.forge_room_on == false and R.raw_of(settings.forge_room) == nil and R.refused == "Make or turn on a creation first"
  and def.info_fn() == "Make or turn on a creation first")
R.refused_at = R.refused_at - 9
check("help line comes back", def.info_fn() == "Everyone plays with the host's creations")
profile("host")
local ok_on, on_info = R.host_set(true)
check("host_set on", ok_on == true and on_info.count == 3 and R.host_on() and settings.forge_room_on == true)
R.refused_key, R.refused_at = "Make or turn on a creation first", R.refused_at + 9
bom_match.sync_settings()
check("reason cleared once it works", def.info_fn() == "Everyone plays with the host's creations")
local sent = R.raw_of(settings.forge_room)
settings.forge_room, settings.forge_room_on = {}, false
bom_match.sync_settings()
check("off stays off at sync", R.raw_of(settings.forge_room) == nil)
settings.forge_room_on = true
bom_match.sync_settings()
check("toggle packs at sync", R.raw_of(settings.forge_room) ~= nil and R.hash(R.raw_of(settings.forge_room)) == R.hash(sent))
local non_default = {}
for k, d in pairs(bom_match.DEFAULT_SETTINGS) do
  if type(d) ~= "table" and settings[k] ~= nil and settings[k] ~= d then non_default[k] = true end
end
check("presets keep the toggle, not the room", non_default.forge_room_on == true and non_default.forge_room == nil)
in_match = true
settings.forge_room_on = false
bom_match.sync_settings()
check("match keeps its room", R.raw_of(settings.forge_room) ~= nil)
in_match = false
bom_match.sync_settings()
check("toggle off clears at sync", R.raw_of(settings.forge_room) == nil)
settings.forge_room, settings.forge_room_on = {raw = sent}, true
bom_match.is_host_player = function() return false end
settings.forge_room_on = false
bom_match.sync_settings()
check("guest sync leaves settings", R.raw_of(settings.forge_room) == sent)
bom_match.is_host_player = function() return true end
settings.forge_room_on = true
profile("guest")
R.raw = nil
phase = "lobby"
check("guest sync in lobby", FJ.allowed_here() == true and R.active() and ids(Store.live_jokers()) == host_j)
phase = "playing"
G.GAME.multiplayer = true
check("in match allowed with room", FJ.allowed_here() == true)
check("same payload", R.raw == sent)
state.ranked = true
check("ranked leaves", FJ.allowed_here() == false and not R.active())
check("ranked host_set", select(2, R.host_set(true)) == "ranked")
check("ranked row locked", R.lobby_row().locked == "Off in Ranked")
check("ranked row hidden", def.show({}) == false)
settings.forge_room_on = true
bom_match.sync_settings()
check("ranked sync clears", R.raw_of(settings.forge_room) == nil)
settings.forge_room = {raw = sent}
state.ranked = nil
check("back after ranked", FJ.allowed_here() == true and R.active())
settings.forge_room = ""
check("host turned it off", FJ.allowed_here() == false and not R.active())
settings.forge_room = sent
FJ.allowed_here()
phase = "none"
G.GAME.multiplayer = nil
check("match over leaves", FJ.allowed_here() == true and not R.active() and ids(Store.live_jokers()) == "ggg111")
check("manual room stays", R.enter(sent, {manual = true}) == true and FJ.allowed_here() == true and R.active())
R.leave()
FairLock = {context = function() return "speedrun" end, blocks = function() return "Off in Speedrun" end}
check("speedrun off", FJ.allowed_here() == false)
FairLock = {context = function() return nil end, blocks = function() return nil end}
check("fairlock clear", FJ.allowed_here() == true)
phase = "playing"
G.GAME.multiplayer = true
settings.forge_room = ""
check("mp without room off", FJ.allowed_here() == false)
local row = R.lobby_row()
check("row shape", row.id == "forge_room" and row.label == "Forge creations" and type(row.get) == "function" and type(row.set) == "function" and row.locked == nil)
bom_match.is_host_player = function() return false end
check("guest cannot set", select(2, row.set(true)) == "Only the host chooses")
FairLock = nil
settings.forge_room = sent
phase = "lobby"
FJ.allowed_here()
check("lobby room before menu", R.active())
phase = "none"
Game = {start_run = function() return "started" end, main_menu = function() return "menu" end}
R.install_hooks()
check("main menu leaves room", Game.main_menu() == "menu" and not R.active() and ids(Store.live_jokers()) == "ggg111")
phase = "playing"
check("start_run enters room", Game.start_run() == "started" and R.active() and ids(Store.live_jokers()) == host_j)
phase = "none"
check("solo start_run leaves room", Game.start_run() == "started" and not R.active())
Game = nil
bom_match = nil
bom_lobby_settings = nil
G = nil

print(string.format("%d checks, %d failed", total, fails))
os.exit(fails == 0 and 0 or 1)
