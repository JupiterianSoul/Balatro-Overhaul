package.path = "assets/?.lua;" .. package.path

local fails, total = 0, 0
local function check(name, ok)
  total = total + 1
  if not ok then fails = fails + 1; print("FAIL " .. name) end
end

local files, dirs = {}, {}
local function reset_fs() files, dirs = {}, {} end
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

local json = require("bot.sim.json")
local Store = require("functions/forge/forge_store")
local M = require("functions/forge/forge_mods")

local function png(tag, w, h)
  local function u32(n) return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256) end
  return "\137PNG\r\n\26\n" .. u32(13) .. "IHDR" .. u32(w or 71) .. u32(h or 95) .. "\8\6\0\0\0" .. tag .. string.rep("\0\255\1", 30)
end

local function fresh_store()
  Store.list, Store.items_list, Store.settings = nil, nil, nil
  M.index, M.list, M.jokers, M.items = nil, {}, {}, {}
end

local function setup_author()
  reset_fs()
  fresh_store()
  files["forge/art/aaa111.png"] = png("A")
  files["forge/art/fJ.png"] = png("J")
  files["forge/art/fK.png"] = png("K")
  files["forge/art/bad.png"] = "not a png"
  Store.put({id = "aaa111", name = "Heart Thief", rarity = 2, cost = 6, art = {file = "forge/art/aaa111.png"}, rules = {}})
  Store.put({id = "bbb222", name = "Plain One", rarity = 1, cost = 4, art = {atlas = "Joker", x = 3, y = 2}})
  Store.put({id = "ccc333", name = "Bad Art", art = {file = "forge/art/bad.png"}})
  Store.put_item({id = "ddd444", kind = "tarot", name = "Coin Card", fields = {}, effects = {}})
  Store.put_item({id = "eee555", kind = "collab", name = "Court", faces = {J = "forge/art/fJ.png", K = "forge/art/fK.png"}})
end

for _, s in ipairs({"", "a", "ab", "abc", "\0\255\128", string.rep("xyz\1", 40)}) do
  check("b64 " .. #s, M.b64_decode(M.b64_encode(s)) == s)
end
check("b64 bad chars", M.b64_decode("ab$=") == nil)
check("png size", select(1, M.png_size(png("x"))) == 71 and select(2, M.png_size(png("x"))) == 95)
check("png not", M.png_size("hello") == nil)

setup_author()
local raw, out = M.pack({name = "Heart Pack", author = "Tester", about = {"Hearts everywhere", "", "third"}}, {"aaa111", "bbb222", "ccc333", "ddd444", "eee555", "nope"})
check("pack ok", type(raw) == "string")
check("pack counts", #out.jokers == 3 and #out.creations == 2)
check("pack files", out.files.aaa111 and out.files.fJ and out.files.fK and not out.files.bad)
check("pack bad art dropped", out.jokers[3].art == nil)
check("pack about", #out.about == 2 and out.about[2] == "third")
check("pack id", M.clean_id(out.id) == out.id and #out.id == 6)
check("pack empty", select(2, M.pack({name = "x"}, {"nope"})) == "empty")

local mod = M.parse(raw)
check("parse ok", mod and mod.name == "Heart Pack" and mod.author == "Tester")
check("parse ids", mod.jokers[1].id == out.id .. "aaa111" and mod.jokers[1].src == "aaa111")
check("parse art path", mod.jokers[1].art.file == "forge/art/fm_" .. out.id .. "_aaa111.png")
check("parse atlas kept", mod.jokers[2].art.atlas == "Joker" and mod.jokers[2].art.x == 3)
check("parse bad art default", mod.jokers[3].art.atlas == "Joker")
check("parse kinds", mod.creations[1].kind == "tarot" and mod.creations[2].kind == "collab")
check("parse faces", mod.creations[2].faces.J == "forge/art/fm_" .. out.id .. "_fJ.png" and mod.creations[2].faces.Q == nil)
check("parse file bytes", mod.files.aaa111 == files["forge/art/aaa111.png"])

local mine, share = M.export({name = "Heart Pack", author = "Tester"}, {"aaa111", "bbb222", "ddd444", "eee555"})
check("export ok", mine and mine.mine == true)
check("export share path", share == "forge/exports/Heart_Pack_" .. mine.id .. ".forgemod" and files[share])
check("export installed", files["forge/mods/" .. mine.id .. ".forgemod"] ~= nil)
check("export arts", files["forge/art/fm_" .. mine.id .. "_aaa111.png"] == files["forge/art/aaa111.png"])
check("mine hidden while own exist", #M.jokers == 0 and #M.items == 0 and #Store.live_jokers() == 3)
Store.delete("bbb222")
M.rebuild()
check("mine shows once own gone", #M.jokers == 1 and M.jokers[1].src == "bbb222")
check("store get falls back", Store.get(mine.id .. "bbb222") ~= nil and Store.get_item(mine.id .. "ddd444") == nil)
check("own list untouched", #Store.all() == 2)
check("forge badge", M.jokers[1].forge_mod and M.jokers[1].forge_mod.display_name == "Heart Pack")

local again = M.export({id = mine.id, name = "Heart Pack 2", author = "Tester", version = mine.version + 1}, {"aaa111"})
check("edit same id", again and again.id == mine.id and again.version == 2 and #M.list == 1)
check("edit removes old arts", files["forge/art/fm_" .. mine.id .. "_fJ.png"] == nil and files["forge/art/fm_" .. mine.id .. "_aaa111.png"] ~= nil)

local shared = files[share]
setup_author()
reset_fs()
fresh_store()
files["forge/import/Heart_Pack.forgemod"] = shared
files["forge/import/notes.txt"] = "hello"
files["forge/import/broken.forgemod"] = "{not json"
local done, bad = M.import_folder()
check("import one", #done == 1 and #bad == 1 and bad[1].err == "not_forge")
check("import removed", files["forge/import/Heart_Pack.forgemod"] == nil and files["forge/import/broken.forgemod"] ~= nil)
check("import not mine", done[1].mine == false and done[1].on == true)
check("import live", #M.jokers == 2 and #M.items == 2 and #Store.live_jokers() == 2 and #Store.live_items() == 2)
check("import own empty", #Store.all() == 0 and #Store.items() == 0)
check("import arts", files["forge/art/fm_" .. done[1].id .. "_aaa111.png"] ~= nil)
check("index saved", json.decode(files[M.INDEX]).mods[done[1].id].on == true)

M.set_on(done[1].id, false)
check("off hides", #M.jokers == 0 and #Store.live_items() == 0 and Store.get(done[1].id .. "aaa111") == nil)
fresh_store()
M.load()
check("off kept after load", #M.list == 1 and M.list[1].on == false and #M.jokers == 0)
M.set_on(done[1].id, true)
check("on again", #M.jokers == 2)
files["forge/art/fm_" .. done[1].id .. "_aaa111.png"] = nil
fresh_store()
M.load()
check("load restores missing art", files["forge/art/fm_" .. done[1].id .. "_aaa111.png"] ~= nil)

local same = M.install(shared)
check("reinstall keeps on and count", same and #M.list == 1 and M.list[1].on == true)

local t = json.decode(shared)
t.v = 99
check("newer", select(2, M.parse(json.encode(t))) == "newer")
t.v = 1
t.id = "../../x"
check("bad id", select(2, M.parse(json.encode(t))) == "not_forge")
t.id = "abcd12"
t.format = "other"
check("bad format", select(2, M.parse(json.encode(t))) == "not_forge")
t.format = "forgemod"
t.files = {aaa111 = M.b64_encode(png("x", 200, 200)), ["../evil"] = t.files.aaa111}
local m2 = M.parse(json.encode(t))
check("wrong size art dropped", m2 and next(m2.files) == nil and m2.jokers[1].art.atlas == "Joker")
t.jokers = {}
for i = 1, 80 do t.jokers[i] = {id = "j" .. i, name = "J" .. i} end
local m3 = M.parse(json.encode(t))
check("item cap", m3 and #m3.jokers + #m3.creations == M.MAX_ITEMS)
check("too big", select(2, M.parse(string.rep(" ", M.MAX_BYTES + 1))) == "too_big")
t.jokers = {{id = "x1", name = string.rep("N", 100) .. "\n", rarity = 99, cost = -5}}
t.creations = {{id = "y1", kind = "joker"}, {id = "y2", kind = "nonsense"}}
local m4 = M.parse(json.encode(t))
check("clean untrusted", m4 and #m4.jokers[1].name == Store.MAX_NAME and m4.jokers[1].rarity == 4 and m4.jokers[1].cost == 1 and #m4.creations == 0)

check("delete", M.delete(done[1].id) and #M.list == 0 and files["forge/mods/" .. done[1].id .. ".forgemod"] == nil and files["forge/art/fm_" .. done[1].id .. "_aaa111.png"] == nil)

do
  local Cat = require("functions/forge/forge_catalog")
  local money = Cat.effect("tarot", "money")
  check("catalog: money effect has no small cap", money and money.num.hi >= 1e9 and money.num.old_hi == 20)
  check("catalog: card price keeps its cap", Cat.kind("tarot").fields[1].id == "cost" and Cat.kind("tarot").fields[1].num.old_hi == nil)
  check("catalog: typed big value is kept", Cat.clamp(money.num, 12345) == 12345 and Cat.clamp(money.num, 7) == 7)
  check("catalog: old values still snap", Cat.clamp({lo = 5, hi = 100, def = 30, step = 5}, 37) == 35)
  check("catalog: big creation is v3", Cat.need_v({kind = "tarot", fields = {cost = 3}, effects = {{id = "money", n = 500}}}) == 3)
  check("catalog: normal creation is v1", Cat.need_v({kind = "tarot", fields = {cost = 3}, effects = {{id = "money", n = 5}}}) == 1)
  check("mods: creations count for the version", M.needs_v({}, {{kind = "tarot", effects = {{id = "money", n = 500}}}}) == 3 and M.needs_v({}, {}) == 1)
  local raw = json.encode({format = "forgemod", v = 1, need = M.V + 1, id = "abcd12", name = "Later", jokers = {{id = "x1", name = "X", rules = {}}}})
  local mod, err = M.parse(raw)
  check("mods: need above this game is refused as newer", mod == nil and err == "newer")
  local again = M.for_old_server(json.encode({format = "forgemod", v = 3, id = "abcd12", name = "Later", jokers = {{id = "x1"}}}))
  local t = again and json.decode(again)
  check("mods: old server copy is v1 with need", t and t.v == 1 and t.need == 3)
  check("mods: v1 files are sent as they are", M.for_old_server(json.encode({format = "forgemod", v = 1, id = "abcd12"})) == nil)
end

print(string.format("%d checks, %d failed", total, fails))
os.exit(fails == 0 and 0 or 1)
