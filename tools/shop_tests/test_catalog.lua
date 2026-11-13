package.path = "assets/?.lua;" .. package.path
local C = require("functions/shop/tavern_catalog")

local fails, total = 0, 0
local function check(name, ok)
  total = total + 1
  if not ok then fails = fails + 1; print("FAIL " .. name) end
end

local function lcg(seed)
  local s = seed
  return function()
    s = (s * 1103515245 + 12345) % 2147483648
    return s / 2147483648
  end
end

local old_sets = {}
for i = 1, 91 do old_sets[i] = {id = "old" .. i, name = "Old " .. i, rarity = {id = (i % 5) + 1}} end
local old_effects = {
  {id = "foil", name = "Foil", rarity = {id = 2}}, {id = "holographic", name = "Holographic", rarity = {id = 3}},
  {id = "polychrome", name = "Polychrome", rarity = {id = 4}}, {id = "negative", name = "Negative", rarity = {id = 5}},
}
local jokers = {}
for i = 1, 150 do jokers[i] = {key = "j_" .. i, name = "Joker " .. i, rarity = (i % 4) + 1} end
local titles = {}
for k in pairs(C.SHOP_TITLE_RARITY) do titles[#titles + 1] = {id = k, name = k, unlock_type = "shop"} end
titles[#titles + 1] = {id = "beginner", name = "Beginner", unlock_type = "level"}
local portraits, backs = {}, {}
for i = 1, 80 do portraits[i] = {id = "p" .. i} end
for i, t in ipairs(C.BACK_THEMES) do backs[i] = {id = t} end

local list, by_id = C.build({color_sets = old_sets, polychromatic = true, effects = old_effects, jokers = jokers, titles = titles,
  portraits = portraits, backs = backs, decks = {collab_STP = "Slay the Princess", collab_R = "Rust"}})

local count = {}
for _, it in ipairs(list) do count[it.type] = (count[it.type] or 0) + 1 end
local kept_new = 0
for _, s in ipairs(C.NEW_PALETTES) do if TAVERN_PALETTES.kept(s.id) then kept_new = kept_new + 1 end end
check("palettes 91 + poly + kept tavern ones", count.palette == 92 + kept_new)
check("effects 4 + 12", count.effect == 16)
check("felts 40", count.felt == 40)
check("flames 30", count.flame == 30)
check("celebrations 12", count.celebration == 12)
check("titles 20 + 102", count.title == 122)
check("backs 40 x 5", count.back == 200)
check("portraits 80", count.portrait == 80)
check("no collab decks", (count.deck or 0) == 0)
check("jimbo 150", count.jimbo == 150)
check("milestone title not in packs", by_id["title:beginner"] == nil)
local designed = #list - count.jimbo
check("designed at least 5x of 97", designed >= 5 * 97)

local ids = {}
local dup = false
for _, it in ipairs(list) do
  if ids[it.id] then dup = true end
  ids[it.id] = true
  check("rarity known " .. it.id, C.RARITY_INDEX[it.rarity] ~= nil)
  check("name " .. it.id, type(it.name) == "string" and it.name ~= "")
end
check("unique ids", not dup)
check("back finish name", by_id["back:dragon_holo"] and by_id["back:dragon_holo"].name == "Dragon Holo" and by_id["back:dragon_holo"].finish == "holo")
check("back negative legendary", by_id["back:moon_negative"].rarity == "legendary")

for _, o in ipairs({C.ODDS, C.ODDS_RARE_PLUS, C.ODDS_EPIC_PLUS}) do
  local s = 0
  for _, w in ipairs(o) do s = s + w end
  check("odds sum 100", s == 100)
end

for _, p in ipairs(C.PACKS) do
  local pool = C.pool_for(p, list)
  local n = 0
  for _, b in pairs(pool) do n = n + #b end
  check("pack has a pool " .. p.id, n >= p.cards)
  check("pack price " .. p.id, p.price > 0 and p.cards >= 3)
  if p.types then
    for _, b in pairs(pool) do
      for _, it in ipairs(b) do
        local ok = false
        for _, t in ipairs(p.types) do if t == it.type then ok = true end end
        if not ok then check("pack type " .. p.id .. " " .. it.id, false) end
      end
    end
  end
end

local rand = lcg(7)
for _, p in ipairs(C.PACKS) do
  for _ = 1, 200 do
    local got = C.roll_pack(p, list, rand, nil, {})
    check("pack size " .. p.id, #got == p.cards)
    local seen = {}
    for _, it in ipairs(got) do
      if seen[it.id] then check("no repeat in one pack " .. p.id, false) end
      seen[it.id] = true
    end
    if p.last then
      local r = C.RARITY_INDEX[got[#got].rarity]
      check("last slot floor " .. p.id, r >= C.RARITY_INDEX[p.last])
    end
  end
end

local crate = C.PACK_BY_ID.crate
local tally = {}
local N = 20000
rand = lcg(42)
for _ = 1, N do
  local got = C.roll_pack(crate, list, rand, nil, {})
  for i = 1, crate.cards - 1 do tally[got[i].rarity] = (tally[got[i].rarity] or 0) + 1 end
end
local slots = N * (crate.cards - 1)
for i, r in ipairs(C.RARITIES) do
  local pct = 100 * (tally[r.key] or 0) / slots
  check(string.format("odds %s %.2f near %d", r.key, pct, C.ODDS[i]), math.abs(pct - C.ODDS[i]) < 1)
end

local legend = C.PACK_BY_ID.legend
local state = {since_legendary = C.PITY - 1}
local got = C.roll_pack(legend, list, function() return 0 end, nil, state)
check("pity gives legendary", got[1].rarity == "legendary")
check("pity resets", state.since_legendary < C.PITY)

local title_pack = C.PACK_BY_ID.title
local owned = {}
for _, it in ipairs(list) do if it.type == "title" and it.rarity == "common" then owned[it.id] = true end end
local unowned_hits, owned_hits = 0, 0
rand = lcg(9)
local function is_owned(it) return owned[it.id] end
local commons = C.pool_for(title_pack, list).common
for _ = 1, 4000 do
  local it = C.roll_item(rand, commons, is_owned, {})
  if owned[it.id] then owned_hits = owned_hits + 1 else unowned_hits = unowned_hits + 1 end
end
check("unowned bias with all owned still rolls", owned_hits > 0)

owned = {}
for i, it in ipairs(commons) do if i % 2 == 0 then owned[it.id] = true end end
local u, o = 0, 0
for _ = 1, 8000 do
  local it = C.roll_item(rand, commons, is_owned, {})
  if owned[it.id] then o = o + 1 else u = u + 1 end
end
check("unowned three times as likely", u / math.max(1, o) > 2.5 and u / math.max(1, o) < 3.5)

local NAMES = require("functions/shop/tavern_loc_names")
local ok_art, ART = pcall(require, "functions/shop/tavern_art")
local function has(name)
  return NAMES.fr[name] ~= nil and NAMES.es[name] ~= nil
end
for _, group in ipairs({C.NEW_PALETTES, C.NEW_EFFECTS, C.FELTS, C.FLAMES, C.CELEBRATIONS, C.NEW_TITLES}) do
  for _, it in ipairs(group) do check("fr es name " .. it.name, has(it.name)) end
end
if ok_art and type(ART) == "table" then
  for _, kind in ipairs({"backs", "portraits"}) do
    for _, it in ipairs(ART[kind] or {}) do check("fr es art name " .. it.name, has(it.name)) end
  end
end

check("refunds rise", C.refund("common") < C.refund("uncommon") and C.refund("epic") < C.refund("legendary"))
check("title case", C.title_case("ocean_waves") == "Ocean Waves")

print(string.format("tavern catalog: %d checks, %d failed", total, fails))
os.exit(fails == 0 and 0 or 1)
