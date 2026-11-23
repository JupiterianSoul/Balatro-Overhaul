package.path = "assets/?.lua;" .. package.path

local fails, total = 0, 0
local function check(name, ok, extra)
  total = total + 1
  if not ok then fails = fails + 1; print("FAIL " .. name .. (extra ~= nil and (" (" .. tostring(extra) .. ")") or "")) end
end

local files, dirs = {}, {forge = true, ["forge/art"] = true}
love = {filesystem = {
  getInfo = function(p) if files[p] then return {type = "file"} end if dirs[p] then return {type = "directory"} end return nil end,
  read = function(p) if files[p] then return files[p], #files[p] end return nil, "missing" end,
  write = function(p, d) files[p] = d return true end,
  createDirectory = function(p) dirs[p] = true return true end,
  remove = function(p) files[p] = nil return true end,
  getSaveDirectory = function() return "/save" end,
  getDirectoryItems = function() return {} end,
}}
package.loaded["functions/fast_fs"] = {write = function(p, d) files[p] = tostring(d) return true end}
mod_loc = function(s) return s end
localize = function(x) return type(x) == "string" and x or "?" end

G = {
  P_CARDS = {}, P_CENTERS = {c_base = {key = "c_base"}}, P_CENTER_POOLS = {},
  C = {SUITS = {}, SO_1 = {}, SO_2 = {}}, SETTINGS = {language = "en-us"}, GAME = {probabilities = {normal = 1}},
  localization = {misc = {suits_plural = {}, suits_singular = {}, poker_hands = {}, poker_hand_descriptions = {}, dictionary = {}}, descriptions = {}},
}
G.C.SET, G.C.SECONDARY_SET, G.C.UI = {}, {}, {TEXT_LIGHT = {1, 1, 1, 1}}
number_format = function(v) return tostring(v) end

local Cat = require("functions/forge/forge_catalog")
local Store = require("functions/forge/forge_store")
local R = require("functions/forge/forge_rules")
local D = require("functions/forge/forge_doc")
local Ty = require("functions/forge/forge_types")
local X = require("functions/forge/forge_typerules")

local f = Cat.clean_fields("ctype", {sell = 3, neg = 25, max_held = 2})
check("fields: sell", f.sell == 3)
check("fields: negative chance", f.neg == 25)
check("fields: most held", f.max_held == 2)
local d = Cat.clean_fields("ctype", {})
check("fields: defaults change nothing", d.sell == 0 and d.neg == 0 and d.max_held == 0)
check("fields: negative chance capped at 100", Cat.clean_fields("ctype", {neg = 500}).neg == 100)

check("rules: card types host run rules", R.host_of("ctype") == "run")
local w = R.whens("ctype")
check("rules: used, bought, sold", #w == 3 and w[1] == "type_used" and w[2] == "type_bought" and w[3] == "type_sold")
local runes = Store.clean_item({id = "runes", kind = "ctype", name = "Runes", fields = {colour = "TEAL", shop = 3, sell = 2, neg = 50, max_held = 2},
  rules = {{when = "type_used", only = {}, give = {{id = "money", n = 1}}}}})
check("store: rules kept", runes.rules and runes.rules[1].when == "type_used" and runes.rules[1].give[1].id == "money")
check("share: format 16", Cat.need_v(runes) == 16)
Store.put_item(runes)
Ty.refresh_list()
local own = "type_forge_runes"
check("types: Runes live", Ty.by_id.runes ~= nil)
check("value: own type maps to its set", X.set_of_value(own) == Ty.set_key("runes"))

local j = R.clean_rules({{when = "consumable_used", only = {{id = "used_kind", v = own}}, give = {{id = "gain_mult", n = 1}}}})
check("joker: IF it is a Rune survives", j[1] and j[1].only[1] and j[1].only[1].v == own)
check("joker: IF it is a Rune needs 16", R.need_v(j) == 16)
local set = Ty.set_key("runes")
check("joker: used Rune matches", R.CHECKS.used_kind({v = own}, {consumeable = {ability = {set = set}}}))
check("joker: used Tarot does not", not R.CHECKS.used_kind({v = own}, {consumeable = {ability = {set = "Tarot"}}}))
check("joker: bought Rune matches", R.CHECKS.used_kind({v = own}, {buying_card = true, card = {ability = {set = set}}}))
check("joker: bought vanilla Tarot still works", R.CHECKS.used_kind({v = "Tarot"}, {buying_card = true, card = {ability = {set = "Tarot"}}}))
local jb = R.clean_rules({{when = "card_bought", only = {{id = "used_kind", v = own}}, give = {{id = "money", n = 1}}}})
check("joker: IF works on card bought", jb[1] and jb[1].only[1] and jb[1].only[1].id == "used_kind")
check("joker: text names the type", (R.TEXT_ONLY.used_kind({v = own}, {}, "en")):find("Runes", 1, true) ~= nil)

local per = R.clean_rules({{when = "hand_played", only = {}, give = {{id = "mult_per", n = 2, per = "type_held", m = own}}}})
check("count: for each Rune you have survives", per[1] and per[1].give[1].per == "type_held" and per[1].give[1].m == own)
local per2 = R.clean_rules({{when = "hand_played", only = {}, give = {{id = "mult_per", n = 2, per = "type_used", m = own}}}})
check("count: for each Rune used survives", per2[1] and per2[1].give[1].per == "type_used")
local list = R.count_matches("type_held")
check("count: picker offers Runes", list[1] == own)
check("count: label", R.count_label({per = "type_held", m = own}, "en"):find("Runes", 1, true) ~= nil, R.count_label({per = "type_held", m = own}, "en"))
G.consumeables = {cards = {{ability = {set = set}}, {ability = {set = set}}, {ability = {set = "Tarot"}}}}
check("count: 2 Runes held", R.COUNT.type_held({m = own}) == 2)
G.GAME.consumeable_usage = {c_a = {set = set, count = 3}, c_b = {set = "Tarot", count = 5}}
check("count: 3 Runes used", R.COUNT.type_used({m = own}) == 3)
check("most held: full at 2", X.full({ability = {set = set}}))
G.consumeables.cards[2] = nil
check("most held: room at 1", not X.full({ability = {set = set}}))

local vals = Cat.values("set")
local has = false
for _, v in ipairs(vals) do if v == own then has = true end end
check("make cards: offers Runes", has)
check("make cards: label", Cat.value_label("set", own) == "Runes")
local tarot = Store.clean_item({id = "rmaker", kind = "tarot", name = "Rune Maker", effects = {{id = "create", v = own, n = 1}}})
check("make cards: kept on a Tarot", tarot.effects[1] and tarot.effects[1].v == own)
check("make cards: needs 16", Cat.need_v(tarot) == 16)
local jc = R.clean_rules({{when = "blind_selected", only = {}, give = {{id = "create", v = own}}}})
check("joker create: own type kept", jc[1] and jc[1].give[1].v == own)

local text = table.concat(D.lines(runes, "en"), "|")
check("text: sell line", text:find("sell for", 1, true) ~= nil, text)
check("text: negative line", text:find("Negative", 1, true) ~= nil)
check("text: most held line", text:find("hold at most", 1, true) ~= nil)
check("text: rule line", text:find("used", 1, true) ~= nil)

local fs = X.fields({fields = {fixed_sell = 3}})
check("fixed sell: field kept", fs.fixed_sell == 3 and fs.sell == 0)
check("fixed sell: replaces the half price", X.sell_price(fs, 1) == 3 and X.sell_price(fs, 7) == 3)
check("fixed sell: earned extra value still adds", X.sell_price(fs, 9, 2) == 5)
local fb = X.fields({fields = {fixed_sell = 3, sell = 2}})
check("fixed sell: +$ sell value adds on top", X.sell_price(fb, 1) == 5)
local fo = X.fields({fields = {sell = 2}})
check("fixed sell: off keeps the normal price plus extra", X.sell_price(fo, 4) == 6)
check("fixed sell: defaults off", X.fields({fields = {}}).fixed_sell == -1)
check("fixed sell: older 0 still means off", X.fields({fields = {fixed_sell = 0}}).fixed_sell == -1)
local f0 = X.fields({fields = {sell_at = 0}})
check("fixed sell: $0 allowed", f0.fixed_sell == 0 and X.sell_price(f0, 7) == 0)
check("fixed sell: $0 plus earned extra", X.sell_price(f0, 7, 2) == 2)
check("fixed sell: clean keeps it", Cat.clean_fields("ctype", {sell_at = 3}).sell_at == 3)
check("fixed sell: clean keeps $0", Cat.clean_fields("ctype", {sell_at = 0}).sell_at == 0)
check("fixed sell: clean defaults Off", Cat.clean_fields("ctype", {}).sell_at == -1)
check("fixed sell: older field moves over", Cat.clean_fields("ctype", {fixed_sell = 3}).sell_at == 3)
check("fixed sell: clean caps", Cat.clean_fields("ctype", {sell_at = 5e9}).sell_at == 1e9)
local fspec
for _, fd in ipairs(Cat.kind("ctype").fields) do if fd.id == "sell_at" then fspec = fd.num end end
check("fixed sell: shows Off below 0", fspec and Cat.fmt(fspec, -1) == "Off", fspec and Cat.fmt(fspec, -1))
check("fixed sell: shows $0", fspec and Cat.fmt(fspec, 0) == "$0")
check("fixed sell: shows $3", fspec and Cat.fmt(fspec, 3) == "$3")
check("fixed sell: in Simple fields", fspec ~= nil)
local f0l = {}
X.doc_lines({sell_at = 0}, function(l) f0l[#f0l + 1] = l end)
check("fixed sell: $0 text line", f0l[1] and f0l[1]:find("$0", 1, true) ~= nil, f0l[1])
local fl = {}
X.doc_lines({fixed_sell = 3, sell = 2}, function(l) fl[#fl + 1] = l end)
check("fixed sell: text line", fl[1] and fl[1]:find("always sell for", 1, true) ~= nil and fl[2] and fl[2]:find("more", 1, true) ~= nil, fl[1])
local runes2 = Store.clean_item({id = "runes2", kind = "ctype", name = "Runes", fields = {colour = "TEAL", fixed_sell = 3}, art = {file = "forge/art/runes2.png"}})
check("pack art: type keeps its art", runes2 and runes2.art and runes2.art.file == "forge/art/runes2.png")
check("pack art: share format stays 16", Cat.need_v(runes2) == 16, Cat.need_v(runes2))
local old = Store.clean_item({id = "runes3", kind = "ctype", name = "Runes", fields = {colour = "TEAL"}})
check("pack art: older type without art loads", old and old.art == nil and Cat.need_v(old) == 16)

local Tx = require("functions/forge/forge_text")
local ctext = Tx.give_text({id = "create", v = own}, "en", {}, "hand_played")
check("text: create names the forged type", ctext:find("Runes", 1, true) ~= nil and ctext:find("Tarot", 1, true) == nil, ctext)
check("text: create Planet unchanged", Tx.give_text({id = "create", v = "Planet"}, "en", {}, "hand_played"):find("Planet", 1, true) ~= nil)
check("text: create fr names the type", Tx.give_text({id = "create", v = own}, "fr", {}, "hand_played"):find("Runes", 1, true) ~= nil)

print(string.format("forge types2: %d checks, %d failed", total, fails))
if fails > 0 then os.exit(1) end
