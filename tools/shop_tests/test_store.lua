package.path = "assets/?.lua;" .. package.path

local saves = 0
G = {
  SETTINGS = {profile = 1},
  PROFILES = {[1] = {progression = {
    balacoin = 1000,
    owned_color_sets = {"ocean", "toxic"},
    owned_icon_effects = {"foil"},
    owned_jimbo_skins = {"j_greedy_joker"},
    unlocked_titles = {"beginner", "the_collector"},
    unlocked_decks = {"collab_STP"},
    equipped_color_set = "toxic",
    equipped_icon_effect = "foil",
    equipped_jimbo_skin = "j_greedy_joker",
    equipped_title = "the_collector",
  }}},
  P_CENTER_POOLS = {Joker = {
    {key = "j_joker", rarity = 1, discovered = true},
    {key = "j_greedy_joker", rarity = 1, discovered = true, name = "Greedy Joker"},
    {key = "j_blueprint", rarity = 3, discovered = true, name = "Blueprint"},
    {key = "j_secret", rarity = 2, discovered = false, name = "Secret"},
  }},
  save_progress = function() saves = saves + 1 end,
}
SHOP_RARITY = {COMMON = {id = 1}, UNCOMMON = {id = 2}, RARE = {id = 3}, EPIC = {id = 4}, LEGENDARY = {id = 5}}
SHOP_COLOR_SETS = {{id = "ocean", name = "Ocean", rarity = SHOP_RARITY.COMMON}, {id = "toxic", name = "Toxic", rarity = SHOP_RARITY.UNCOMMON}, {id = "abyss", name = "Abyss", rarity = SHOP_RARITY.LEGENDARY}}
SHOP_POLYCHROMATIC = {id = "polychromatic"}
SHOP_ICON_EFFECTS = {{id = "foil", name = "Foil", rarity = SHOP_RARITY.UNCOMMON}, {id = "negative", name = "Negative", rarity = SHOP_RARITY.LEGENDARY}}
TITLES = {{id = "beginner", name = "Beginner", unlock_type = "level"}, {id = "the_collector", name = "The Collector", unlock_type = "shop"}, {id = "omega", name = "Omega", unlock_type = "shop"}}
local applied
apply_color_set = function(id) applied = id end
reset_colors_to_default = function() applied = "default" end

local S = require("functions/shop/tavern_store")
local C = S.catalog

local fails, total = 0, 0
local function check(name, ok)
  total = total + 1
  if not ok then fails = fails + 1; print("FAIL " .. name) end
end

check("old colour set owned", S.owns(S.get("palette:ocean")))
check("old colour set not owned", not S.owns(S.get("palette:abyss")))
check("old effect owned", S.owns(S.get("effect:foil")))
check("old jimbo owned", S.owns(S.get("jimbo:j_greedy_joker")))
check("undiscovered joker not in list", S.get("jimbo:j_secret") == nil)
check("default joker not in list", S.get("jimbo:j_joker") == nil)
check("old shop title owned", S.owns(S.get("title:the_collector")))
check("milestone title not in packs", S.get("title:beginner") == nil)
check("collab deck not in the shop", S.get("deck:collab_STP") == nil)
check("old equipped palette", S.equipped("palette") == "toxic")
check("old equipped effect", S.equipped("effect") == "foil")
check("old equipped jimbo", S.equipped("jimbo") == "j_greedy_joker")
check("old equipped title", S.equipped("title") == "the_collector")
check("is_equipped", S.is_equipped(S.get("palette:toxic")))

local pr = G.PROFILES[1].progression
local seq = {}
for i = 1, 5000 do seq[i] = ((i * 7919) % 1000) / 1000 end
local k = 0
local function rand() k = k % #seq + 1; return seq[k] end

local res = S.open("palette", rand)
check("open returns cards", res and #res.cards == 3)
check("balance spent", pr.balacoin == 1000 - 120 + (res and res.refund or 0))
for _, r in ipairs(res.cards) do
  check("granted " .. r.item.id, S.owns(r.item))
  check("type in pack " .. r.item.id, r.item.type == "palette" or r.item.type == "felt")
end
check("state opened", S.state().opened == 1 and S.state().cards == 3)
check("saved", saves > 0)
check("old list kept", pr.owned_color_sets[1] == "ocean" and pr.owned_color_sets[2] == "toxic")

pr.balacoin = 50
local none, why = S.open("crate", rand)
check("not enough money", none == nil and why == "money" and pr.balacoin == 50)

pr.balacoin = 100000
local before = pr.balacoin
local dupes, refund = 0, 0
for _ = 1, 40 do
  local r = S.open("title", rand)
  for _, c in ipairs(r.cards) do if c.dupe then dupes = dupes + 1; refund = refund + c.refund end end
end
check("titles spent and refunded", pr.balacoin == before - 40 * 100 + refund)
check("dupes happen and refund", dupes > 0 and refund > 0)
local unique = {}
for _, id in ipairs(pr.unlocked_titles) do
  if unique[id] then check("title not duplicated in save " .. id, false) end
  unique[id] = true
end

S.state().since_legendary = C.PITY - 1
local lg = S.open("legend", function() return 0 end)
check("pity legendary first card", lg.cards[1].item.rarity == "legendary")
check("legend last epic or better", C.RARITY_INDEX[lg.cards[5].item.rarity] >= C.RARITY_INDEX.epic)
check("pity reset stored", S.state().since_legendary < C.PITY)

local felt
for _, it in ipairs(S.items("felt")) do if S.owns(it) then felt = it break end end
if not felt then
  felt = S.items("felt")[1]
  S.grant(felt)
end
check("equip felt", S.equip(felt) and S.equipped("felt") == felt.key)
check("unequip felt", S.unequip("felt") and S.equipped("felt") == nil)
check("cannot equip locked", not S.equip(S.get("palette:abyss")) or S.owns(S.get("palette:abyss")))
local pal = S.get("palette:ocean")
check("equip palette applies", S.equip(pal) and applied == "ocean" and pr.equipped_color_set == "ocean")
check("unequip palette resets", S.unequip("palette") and applied == "default" and pr.equipped_color_set == nil)
check("collab deck not equippable", not S.equip(S.get("deck:collab_STP")))
check("jimbo unequip to default", S.unequip("jimbo") and pr.equipped_jimbo_skin == "j_joker")

local have, all = S.counts()
check("counts", have > 0 and all > have)
check("pool size", S.pool_size(C.PACK_BY_ID.jester) == 2 + #(S.art.portraits or {}))

local TP = require("functions/shop/tavern_palettes")
local old = {owned_color_sets = {"neon", "pastel", "toxic"}, equipped_color_set = "neon"}
check("palette migrate changes", TP.migrate(old))
check("removed equipped palette moves to its nearest kept one", old.equipped_color_set == TP.ALIAS.neon and TP.KEEP[old.equipped_color_set] ~= nil)
local owned = {}
for _, v in ipairs(old.owned_color_sets) do owned[v] = (owned[v] or 0) + 1 end
check("owned removed palettes grant their kept ones once", owned[TP.ALIAS.neon] == 1 and owned[TP.ALIAS.pastel] == 1 and owned.toxic == 1)
check("palette migrate is idempotent", not TP.migrate(old))
check("resolve keeps kept ids", TP.resolve("toxic") == "toxic" and TP.resolve("polychromatic") == "polychromatic" and TP.resolve(nil) == nil)
local nalias = 0
for k, v in pairs(TP.ALIAS) do
  nalias = nalias + 1
  check("alias target kept " .. k, TP.KEEP[v] ~= nil and TP.KEEP[k] == nil)
end
check("palette list is small", nalias > 100)
local cols = {}
local src = io.open("assets/functions/shop_catalog.lua"):read("*a")
for id, b, r, g, y in src:gmatch('{id="([^"]+)",[^{}]-blue={([^}]*)},%s*red={([^}]*)},%s*green={([^}]*)},%s*yellow={([^}]*)}') do
  local set = {}
  for _, s in ipairs({b, r, g, y}) do
    local c = {}
    for n in s:gmatch("%d+") do c[#c + 1] = tonumber(n) end
    set[#set + 1] = c
  end
  cols[id] = set
end
for _, s in ipairs(require("functions/shop/tavern_catalog").NEW_PALETTES) do cols[s.id] = {s.blue, s.red, s.green, s.yellow} end
local function lab(c)
  local function lin(v) v = v / 255 return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4 end
  local r, g, b = lin(c[1]), lin(c[2]), lin(c[3])
  local function f(t) return t > 0.008856 and t ^ (1 / 3) or 7.787 * t + 16 / 116 end
  local x, y, z = f((0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047), f(0.2126 * r + 0.7152 * g + 0.0722 * b), f((0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883)
  return 116 * y - 16, 500 * (x - y), 200 * (y - z)
end
local function pal_dist(a, b)
  local d = 0
  for i = 1, 4 do
    local l1, a1, b1 = lab(a[i])
    local l2, a2, b2 = lab(b[i])
    d = d + math.sqrt((l1 - l2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
  end
  return d / 4
end
local kept = {{{0, 157, 255}, {254, 95, 85}, {75, 194, 146}, {253, 162, 0}}}
local nkept, missing = 0, 0
for id in pairs(TP.KEEP) do
  nkept = nkept + 1
  if cols[id] then kept[#kept + 1] = cols[id] else missing = missing + 1 end
end
check("at least 48 palettes kept", nkept >= 48)
check("every kept palette has colours", missing == 0)
local closest = math.huge
for i = 1, #kept do for j = i + 1, #kept do closest = math.min(closest, pal_dist(kept[i], kept[j])) end end
check("every pair of palettes is far apart", closest >= 30)
local function shuffles(t, n, out)
  n = n or #t
  out = out or {}
  if n <= 1 then out[#out + 1] = {t[1], t[2], t[3], t[4]} return out end
  for i = 1, n do
    t[i], t[n] = t[n], t[i]
    shuffles(t, n - 1, out)
    t[i], t[n] = t[n], t[i]
  end
  return out
end
local function near(a, b)
  local l1, a1, b1 = lab(a)
  local l2, a2, b2 = lab(b)
  return math.sqrt((l1 - l2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2) < 20
end
local closest_any, most_shared = math.huge, 0
for i = 1, #kept do for j = i + 1, #kept do
  for _, p in ipairs(shuffles({kept[j][1], kept[j][2], kept[j][3], kept[j][4]})) do
    closest_any = math.min(closest_any, pal_dist(kept[i], p))
    local n = 0
    for k = 1, 4 do if near(kept[i][k], p[k]) then n = n + 1 end end
    most_shared = math.max(most_shared, n)
  end
end end
check("no palette is another one's colours in a new order", closest_any >= 28)
check("no two palettes share three colours", most_shared <= 2)
local SL = require("functions/shop/tavern_sleeves")
for _, s in ipairs(SL.LIST) do check("no blind chip on sleeve " .. s.id, not (s.emblem and s.emblem.chip)) end
check("sleeves in the list", S.get("back:iron_ox") ~= nil and S.get("back:iron_ox_holo") ~= nil and S.get("back:iron_ox").atlas == "tavern_sleeves")
check("retired back gone", S.get("back:crimson_crest") == nil and S.get("back:crimson_crest_foil") == nil)
check("kept dev back still there", S.get("back:rocket") ~= nil)
S.state().equipped.back = "crimson_crest_foil"
check("retired equipped back falls back to default", S.equipped("back") == nil)
S.state().equipped.back = "iron_ox"
check("sleeve equipped", S.equipped("back") == "iron_ox")
RELEASE_BUILD = true
S.invalidate()
local n = 0
for _, it in ipairs(S.items("back")) do
  if it.atlas ~= "tavern_sleeves" then n = n + 1 end
end
check("release has only sleeves", n == 0 and #S.items("back") == #SL.LIST * #C.FINISHES)
RELEASE_BUILD = nil
S.invalidate()
local names = {}
for _, s in ipairs(SL.LIST) do
  check("sleeve name unique " .. s.id, not names[s.name])
  names[s.name] = true
  check("sleeve id matches name " .. s.id, C.title_case(s.id) == s.name)
end

print(string.format("tavern store: %d checks, %d failed", total, fails))
os.exit(fails == 0 and 0 or 1)
