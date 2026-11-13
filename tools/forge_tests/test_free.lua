package.path = "assets/?.lua;" .. package.path
mod_loc = function(s) return s end
G = {}
local Cat = require("functions/forge/forge_catalog")

local fails, total = 0, 0
local function check(name, ok, got)
  total = total + 1
  if not ok then fails = fails + 1; print("FAIL " .. name .. (got ~= nil and (" got: " .. tostring(got)) or "")) end
end

local bounded = {}
for _, k in ipairs(Cat.KINDS) do
  for _, list in ipairs({k.fields or {}, k.adv_fields or {}}) do
    for _, f in ipairs(list) do
      if f.type == "num" and f.num.hi - f.num.lo < 9 and f.id ~= "shown" and f.id ~= "choose" then bounded[#bounded + 1] = k.id .. "." .. f.id end
    end
  end
end
check("every field has a wide range", #bounded == 0, table.concat(bounded, ","))

local narrow = {}
for kind, list in pairs(Cat.EFFECTS) do
  for _, e in ipairs(list) do
    if e.num and e.num.hi - e.num.lo < 9 and e.id ~= "pack_slots" and e.id ~= "voucher_slots" then narrow[#narrow + 1] = kind .. "." .. e.id end
  end
end
check("every effect number has a wide range", #narrow == 0, table.concat(narrow, ","))

check("hand size can go negative", Cat.effect("voucher", "hand_size").num.lo < 0)
check("rank can go down", Cat.effect("tarot", "rank_up").num.lo == -12)
check("discount stops at 100", Cat.effect("voucher", "discount").num.hi == 100)
check("decimals kept on multipliers", Cat.clamp(Cat.effect("seal", "scored_xmult").num, 1.37) == 1.37)
check("whole numbers stay whole", Cat.clamp(Cat.effect("voucher", "hand_size").num, 2.6) == 3)
check("big jumps exist", (Cat.effect("voucher", "money").num.big or 0) > 1)

local function has(list, v) for _, x in ipairs(list or {}) do if x == v then return true end end return false end
check("voucher has run effects", Cat.effect("voucher", "blind_size") and Cat.effect("voucher", "shop_rate") and Cat.effect("voucher", "xmult") and true)
check("deck has run effects", Cat.effect("deck", "probability") and Cat.effect("deck", "dollars").run and true)
check("stake has run effects", Cat.effect("stake", "interest_amount") and Cat.effect("stake", "hand_size") and true)
check("blind has scoring effects", Cat.effect("blind", "mult") and not Cat.effect("blind", "shop_rate"))
check("scoring only when scoring", has(Cat.whens_for("voucher", "chips"), "hand_played") and not has(Cat.whens_for("voucher", "chips"), "now"))
check("money can be per card", has(Cat.whens_for("voucher", "money"), "card_scored"))
check("hand size not per card", not has(Cat.whens_for("voucher", "hand_size"), "card_scored") and has(Cat.whens_for("voucher", "hand_size"), "ante_up"))
check("blind has no now", not has(Cat.whens_for("blind", "money"), "now") and Cat.default_when("blind", "money") == "blind_selected")
check("tarot has no whens", Cat.whens_for("tarot", "money") == nil)

local e = Cat.clean_effects("voucher", {
  {id = "xmult", n = 2.345, when = "card_scored", only = {{id = "suit", v = "Hearts"}, {id = "ante", op = "at_most", n = 4}, {id = "every", n = 3}, {id = "boss"}}},
  {id = "money", n = 5, when = "bogus", only = {{id = "suit", v = "Hearts"}}},
  {id = "hand_size", n = -3},
})
check("xmult keeps decimals", e[1].n == 2.35, e[1].n)
check("only capped at 3", #e[1].only == 3)
check("every kept", e[1].only[3].id == "every" and e[1].only[3].n == 3)
check("bad when falls back", e[2].when == "now" or e[2].when == nil, e[2].when)
check("card only dropped off card trigger", e[2].only == nil)
check("negative hand size kept", e[3].n == -3 and e[3].when == nil)
check("tarot effects lose when", Cat.clean_effects("tarot", {{id = "money", n = 3, when = "round_end"}})[1].when == nil)

local f = Cat.clean_fields("voucher", {cost = 0, requires = "v_forge_abc1", weight = 25, max_buys = 3, min_ante = 2})
check("voucher can be free", f.cost == 0)
check("requires forge voucher", f.requires == "v_forge_abc1")
check("requires bad text", Cat.clean_fields("voucher", {requires = "x; rm"}).requires == "none")
check("weight and buys", f.weight == 25 and f.max_buys == 3 and f.min_ante == 2)

check("plain voucher stays v1", Cat.need_v({kind = "voucher", fields = {cost = 10, requires = "none"}, effects = {{id = "hand_size", n = 1}}}) == 1)
check("weight needs v4", Cat.need_v({kind = "voucher", fields = {cost = 10, weight = 2}, effects = {}}) == 4)
check("trigger needs v4", Cat.need_v({kind = "voucher", fields = {}, effects = {{id = "money", n = 2, when = "round_end"}}}) == 4)
check("new effect needs v4", Cat.need_v({kind = "deck", fields = {}, effects = {{id = "blind_size", n = 0.5}}}) == 4)
check("off-grid value needs v4", Cat.need_v({kind = "enhancement", fields = {xmult = 1.3}}) == 4)
check("on-grid value stays v1", Cat.need_v({kind = "enhancement", fields = {xmult = 1.25}}) == 1)
check("lifted value stays v3", Cat.need_v({kind = "tag", fields = {}, effects = {{id = "money", n = 500}}}) == 3)

local line = Cat.effect_line("voucher", {id = "money", n = 5, when = "round_end", only = {{id = "boss"}}})
check("sentence has trigger and condition", line:find("end of the round") and line:find("Boss") and line:find("%$5"), line)
check("signed lines", Cat.effect_line("voucher", {id = "hands_round", n = -2, when = "blind_selected"}):find("%-2 {}") ~= nil or Cat.effect_line("voucher", {id = "hands_round", n = -2, when = "blind_selected"}):find("{C:blue}%-2{}") ~= nil)
check("multiplier line", Cat.effect_line("deck", {id = "blind_size", n = 0.75}) == "Blinds are {C:attention}X0.75{} as big")
check("value line", Cat.effect_line("voucher", {id = "shop_rate", v = "Spectral", n = 3}):find("+3") ~= nil)

local rt = Cat.clean_effects("tarot", {{id = "tag", n = 2, v = "random"}, {id = "tag", n = 1, v = "tag_bogus"}})
check("random tag is a choice of Give tags", Cat.values("tag")[1] == "random" and rt[1] and rt[1].v == "random")
check("unknown tag is still refused", rt[2] == nil or rt[2].v ~= "tag_bogus")
check("random tag has a label and a line", Cat.value_label("tag", "random") == "Random Tag" and Cat.effect_line("tarot", rt[1]):find("Random Tag") ~= nil)
check("random tag needs v5", Cat.need_v({kind = "tarot", fields = {cost = 3}, effects = {{id = "tag", n = 1, v = "random"}}}) == 5)
check("fixed tag stays v4", Cat.need_v({kind = "tarot", fields = {cost = 3}, effects = {{id = "tag", n = 1, v = "tag_double"}}}) == 4)

print(string.format("forge free: %d checks, %d failed", total, fails))
if fails > 0 then os.exit(1) end
