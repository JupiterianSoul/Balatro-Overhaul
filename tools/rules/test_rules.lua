local root = arg and arg[1] or "."
package.path = root .. "/assets/?.lua;" .. package.path

local REG = {fr = {}, es = {}}
function mod_loc(s) return s end
function mod_loc_register(t)
    for lang, entries in pairs(t or {}) do
        REG[lang] = REG[lang] or {}
        for k, v in pairs(entries) do REG[lang][k] = v end
    end
end

local DEFAULTS = {mode = "nemesis", starting_lives = 4, timer = false, timer_base_seconds = 120, timer_increment_seconds = 0,
    timer_forgiveness = 0, different_seeds = false, custom_seed = "random", deck = "Red Deck", stake = 1, rules = {}, party_kind = "br",
    the_order = false, multiplayer_jokers = true}
local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end
local match = {settings = copy(DEFAULTS), phase = "lobby", is_host = true}
package.loaded["multiplayer.bom_match"] = {
    DEFAULT_SETTINGS = DEFAULTS,
    PARTY_KEYS = {party_kind = true},
    PHASE = {LOBBY = "lobby"},
    defaults = function() return copy(DEFAULTS) end,
    get_state = function() return match end,
    get_settings = function() return match.settings end,
    get_phase = function() return match.phase end,
    is_host_player = function() return match.is_host end,
    sync_settings = function() end,
    different_seeds = function(s) return s.different_seeds == true end,
    random_seed = function() return "SEED1234" end,
    update_settings = function(n) for k, v in pairs(n) do if DEFAULTS[k] ~= nil then match.settings[k] = copy(v) end end end,
}

local ly = require("multiplayer.bom_layers")
_G.bom_layers = ly
local R = require("multiplayer.bom_rulesets")
_G.bom_rulesets = R
mod_loc_register({fr = ly.FR, es = ly.ES})
mod_loc_register({fr = R.FR, es = R.ES})

local fails, checks = 0, 0
local function ok(cond, msg)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        print("FAIL: " .. msg)
    end
end

ok(DEFAULTS.hide_opp_score == false and type(DEFAULTS.layers) == "table" and DEFAULTS.ruleset_id == "" and DEFAULTS.pool_seed == "", "new settings installed")

ok(#ly.LIST >= 15 and #ly.LIST <= 20, "15 to 20 layers, got " .. #ly.LIST)
for _, d in ipairs(ly.LIST) do
    for _, s in ipairs({d.name, d.desc}) do
        ok(REG.fr[s] ~= nil and REG.es[s] ~= nil, "layer string translated: " .. s)
    end
    ok(d.cat ~= nil, "layer has a category: " .. d.id)
end
for _, c in ipairs(ly.CAT_ORDER) do ok(REG.fr[c.label] and REG.es[c.label], "category translated: " .. c.label) end

for _, m in ipairs(R.MODES) do
    ok(REG.fr[m.name] and REG.es[m.name], "mode translated: " .. m.name)
    local list = R.for_mode(m.key)
    ok(#list >= 3, "mode has rulesets: " .. m.key)
    ok(list[1] and list[1].family == "classic", "classic first: " .. m.key)
    ok(R.find(m.key, "small_world") ~= nil, "small world in " .. m.key)
end
for _, d in ipairs(R.LIST) do
    ok(REG.fr[d.name] and REG.es[d.name], "ruleset name translated: " .. d.name)
    ok(REG.fr[d.desc] and REG.es[d.desc], "ruleset desc translated: " .. d.desc)
    for _, id in ipairs(d.layers) do ok(ly.get(id) ~= nil, d.id .. " layer exists: " .. id) end
    ok(#d.desc <= 60, "short desc: " .. d.id)
end

local t = ly.toggle({"clock_blitz", "econ_frugal"}, "clock_relaxed", true)
ok(#t == 2 and t[1] == "clock_relaxed" and t[2] == "econ_frugal", "timer group is exclusive")
t = ly.toggle(t, "econ_frugal", false)
ok(#t == 1 and t[1] == "clock_relaxed", "toggle off")
ok(#ly.valid({"nope", "glass_sturdy", "glass_fragile"}) == 1, "valid drops unknown and same-group ids")

local centers, tags = {}, {}
for r = 1, 3 do for i = 1, 40 do centers["j_" .. r .. "_" .. i] = {set = "Joker", rarity = r} end end
for i = 1, 22 do centers["c_t" .. i] = {set = "Tarot"} end
centers.c_soul = {set = "Spectral", name = "The Soul", hidden = true}
for i = 1, 16 do centers["v_" .. i] = {set = "Voucher"} end
for i = 1, 16 do centers["v_" .. i .. "_up"] = {set = "Voucher", requires = {"v_" .. i}} end
centers.j_gros_michel = {set = "Joker", rarity = 1}
centers.j_cavendish = {set = "Joker", rarity = 1}
for i = 1, 24 do tags["tag_" .. i] = {} end
local a = ly.small_world_bans("ABC", centers, tags, {})
local b = ly.small_world_bans("ABC", centers, tags, {})
local c = ly.small_world_bans("XYZ", centers, tags, {})
local same, diff, n = true, false, 0
for k in pairs(a) do n = n + 1; if not b[k] then same = false end; if not c[k] then diff = true end end
for k in pairs(b) do if not a[k] then same = false end end
ok(same, "small world is deterministic")
ok(diff, "small world depends on the seed")
local per = {}
for k in pairs(a) do
    local cc = centers[k]
    local g = cc and (cc.set == "Joker" and ("J" .. cc.rarity) or cc.set) or "Tag"
    if not (cc and cc.requires) and k ~= "j_cavendish" then per[g] = (per[g] or 0) + 1 end
end
ok(per.J2 == 30 and per.J3 == 30 and per.Tarot == 17 and per.Voucher == 12 and per.Tag == 18, "75% of each pool banned")
ok(not a.c_soul, "hidden cards are never banned")
for i = 1, 16 do
    if a["v_" .. i] then ok(a["v_" .. i .. "_up"], "upgrade follows its base voucher " .. i) end
end
ok((a.j_gros_michel and a.j_cavendish) or not a.j_gros_michel, "Cavendish goes with Gros Michel")

local s = R.settings_for("nemesis_small_world", match.settings)
ok(s and s.ruleset_id == "nemesis_small_world" and s.layers[1] == "small_world" and s.pool_seed == "SEED1234", "small world ruleset settings")
match.settings = s
local rs = R.effective()
ok(rs.id == "nemesis_small_world" and #rs.reworks == 7 and rs.bans.consumables[1] == "c_justice", "effective small world ruleset")
local got = R.get("nemesis_small_world")
ok(got and got.layers[1] == "small_world" and got.settings.ruleset_id == "nemesis_small_world" and type(got.bans.tags) == "table", "get shape")

local ch = R.layer_change(match.settings, ly.toggle(match.settings.layers, "clock_blitz", true))
ok(ch.timer == true and ch.timer_base_seconds == 60 and #ch.layers == 2, "timer layer writes the clock")
match.settings.timer, match.settings.timer_base_seconds, match.settings.layers = true, 60, ch.layers
ch = R.layer_change(match.settings, ly.toggle(match.settings.layers, "clock_blitz", false))
ok(ch.timer == false and ch.timer_base_seconds == 120 and #ch.layers == 1, "timer layer off restores the clock")

match.settings.mode = "faceoff"
ok(R.current_id(match.settings) == "faceoff_small_world", "ruleset follows the mode family")
match.settings.mode = "ascension"
match.settings.ruleset_id = "nemesis_vanilla"
ok(R.current_id(match.settings) == "ascension_classic", "unknown family falls back to classic")

local rules = ly.rules_for({"econ_inflation", "shop_tight"}, {dollars = 8})
ok(rules.inflation == true and rules.shop_slots == 1 and rules.reroll_cost == 3 and rules.dollars == 8, "layer rules merge")

match.phase = "lobby"
R.apply_server({id = "ranked", name = "Ranked", desc = "x", mode = "nemesis", settings = {starting_lives = 4, hide_opp_score = true, timer = true},
    bans = {consumables = {"c_justice"}, blinds = {"bl_mp_nemesis"}}, reworks = {"m_glass"}, layers = {}, locked = true}, "ranked")
ok(R.lock_kind() == "ranked" and match.settings.hide_opp_score == true and match.settings.ruleset_id == "ranked", "ranked applies and locks")
rs = R.effective()
ok(rs.id == "ranked" and #rs.bans.blinds == 0 and rs.reworks[1] == "m_glass", "ranked effective, nemesis blind never banned")
match.bom_lock, match.bom_server_rs, match.ranked, match.ruleset = nil, nil, nil, nil
R.apply_server({id = "daily-2026-11-02", base = "nemesis_balanced", name = "Balanced", mode = "nemesis",
    settings = {mode = "nemesis", layers = {"clock_pressure"}, custom_seed = "ABCDEFGH"}, bans = {consumables = {"c_justice"}}, reworks = {"m_glass"},
    layers = {"clock_pressure"}, locked = true}, "daily")
ok(R.lock_kind() == "daily" and match.settings.ruleset_id == "nemesis_balanced" and match.settings.timer_base_seconds == 90, "daily applies on its base ruleset")
ok(match.bom_server_rs == nil and R.effective().id == "nemesis_balanced", "daily guests and host share the base ruleset")

ok(ly.wobble_factor() == 1, "no game, factor 1")
_G.G = {GAME = {pseudorandom = {seed = "AAAA"}, round_resets = {ante = 2}, round = 3, current_round = {hands_played = 1}}}
local lo, hi = 9, 0
for i = 0, 200 do
    G.GAME.current_round.hands_played = i
    local f = ly.wobble_factor()
    lo, hi = math.min(lo, f), math.max(hi, f)
end
ok(lo >= 0.7 and hi <= 1.4 and hi > lo, "wobble stays in x0.7 to x1.4")

for _, f in ipairs({"bom_layers.lua", "bom_rulesets.lua", "bom_daily.lua", "bom_lobby_settings.lua", "bom_gamemodes.lua"}) do
    local h = io.open(root .. "/assets/multiplayer/" .. f, "rb")
    local src = h and h:read("*a") or ""
    if h then h:close() end
    ok(not src:find("\226\128\148", 1, true), "no em dash in " .. f)
    if f == "bom_lobby_settings.lua" then
        for _, key in ipairs({"Rulesets", "This match", "Hide enemy score", "Hidden until you play your first PvP hand", "Ranked rules", "Daily rules",
            "Weekly rules", "RANKED RULES", "DAILY RULES", "WEEKLY RULES", "These rules are fixed for this match."}) do
            local _, count = src:gsub('%["' .. key:gsub("%p", "%%%0") .. '"%]', "")
            ok(count == 2, "lobby string in FR and ES: " .. key)
        end
    end
end

print(string.format("%d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
