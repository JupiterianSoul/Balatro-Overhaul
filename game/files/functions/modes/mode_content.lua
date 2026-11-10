local MC = {}

local function L(s) return mod_loc and mod_loc(s) or s end
local function g(name) return rawget(_G, name) end
local function in_list(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

MC.ATLAS = "mp_mode_jokers"
MC.ATLAS_FILE = "MPModeJokers.png"

MC.MODE_LIST = {
    {key = "nemesis", name = "Rivals"},
    {key = "faceoff", name = "FaceOff"},
    {key = "ranked", name = "Ranked"},
    {key = "ascension", name = "Ascension"},
    {key = "race", name = "Race"},
    {key = "br", name = "Battle Royale"},
    {key = "teams", name = "Teams"},
    {key = "raid", name = "Co-op Raid"},
    {key = "swap", name = "Switcheroo"},
}

local DUEL = {"nemesis", "faceoff", "ranked", "swap"}
local function with(...)
    local out = {}
    for _, k in ipairs(DUEL) do out[#out + 1] = k end
    for _, k in ipairs({...}) do out[#out + 1] = k end
    return out
end

MC.JOKER_MODES = {
    j_mp_truce = with("br", "teams"),
    j_mp_bulwark = with(),
    j_mp_shortcut = with("race"),
    j_mp_tariff = with(),
    j_mp_mirror_match = with(),
    j_mp_envy = with("ascension", "race"),
    j_mp_leftovers = with("br", "teams"),
    j_mp_photo_finish = with(),
    j_mp_high_roller = with(),
    j_mp_grudge = with("ascension", "race", "br", "teams"),
    j_mp_summit = {"ascension"},
    j_mp_base_camp = {"ascension"},
    j_mp_slipstream = {"race"},
    j_mp_pace_car = {"race"},
    j_mp_underdog = {"br"},
    j_mp_vulture = {"br"},
    j_mp_wingman = {"teams"},
    j_mp_huddle = {"teams"},
    j_mp_war_banner = {"raid"},
    j_mp_supply_drop = {"raid"},
}

MC.TRAP_MODES = {"nemesis", "faceoff", "ascension", "race", "br", "teams"}
MC.CLOCK_BANS = {"v_hieroglyph", "v_petroglyph"}
MC.ALL_MODES = {}
for _, m in ipairs(MC.MODE_LIST) do MC.ALL_MODES[#MC.ALL_MODES + 1] = m.key end
MC.BLIND_MODES = {
    bl_mp_nemesis = {"nemesis", "faceoff", "ranked", "swap"},
    bl_mp_royale = {"br"},
    bl_mp_clash = {"teams"},
    bl_mp_raid = {"raid"},
    bl_mp_race = {"race"},
}

MC.DECK_MODES = {}
for _, k in ipairs(MC.ALL_MODES) do if k ~= "ranked" then MC.DECK_MODES[#MC.DECK_MODES + 1] = k end end

MC.filter = MC.filter or "all"

function MC.filter_keep(key)
    if MC.filter == "all" then return true end
    for _, k in ipairs(MC.modes_of(key)) do if k == MC.filter then return true end end
    return false
end

function MC.filter_label()
    if MC.filter == "all" then return L("All modes") end
    return MC.mode_name(MC.filter)
end

function MC.filter_step(d)
    local keys = {"all"}
    for _, m in ipairs(MC.MODE_LIST) do keys[#keys + 1] = m.key end
    local at = 1
    for i, k in ipairs(keys) do if k == MC.filter then at = i end end
    MC.filter = keys[(at - 1 + d) % #keys + 1]
end

function MC.add_mode(def, extra)
    if type(def) ~= "table" or type(def.key) ~= "string" then return end
    local found = false
    for _, m in ipairs(MC.MODE_LIST) do if m.key == def.key then found = true end end
    if not found then
        MC.MODE_LIST[#MC.MODE_LIST + 1] = {key = def.key, name = def.name or def.key}
        MC.ALL_MODES[#MC.ALL_MODES + 1] = def.key
    end
    for key, on in pairs(extra or {}) do
        local list = MC.JOKER_MODES[key]
        if list and on then
            local has = false
            for _, k in ipairs(list) do if k == def.key then has = true end end
            if not has then list[#list + 1] = def.key end
        end
    end
end

local function starts(s, p) return type(s) == "string" and s:sub(1, #p) == p end

function MC.modes_of(key)
    if MC.JOKER_MODES[key] then return MC.JOKER_MODES[key] end
    if MC.BLIND_MODES[key] then return MC.BLIND_MODES[key] end
    if starts(key, "c_mp_trap") or key == "p_mp_trap_normal" then return MC.TRAP_MODES end
    if starts(key, "b_mp_") then
        local bd = g("bom_decks")
        if bd and bd.DEFS and bd.DEFS[key] and bd.DEFS[key].ranked then return MC.ALL_MODES end
        return MC.DECK_MODES
    end
    if starts(key, "stake_mp_") then return MC.DECK_MODES end
    local R = g("bom_rulesets")
    if R and R.BALANCED_REWORKS and G and G.P_CENTERS and G.P_CENTERS[key] and not starts(key, "j_mp_") then
        for _, k in ipairs(R.BALANCED_REWORKS) do if k == key then return MC.ALL_MODES end end
        return MC.DECK_MODES
    end
    return MC.ALL_MODES
end

local function name_in(m, lang)
    if lang == "fr" then return MC.STR_FR[m.name] or m.name end
    if lang == "es" then return MC.STR_ES[m.name] or m.name end
    return m.name
end

local EVERY = {en = "Every mode", fr = "Tous les modes", es = "Todos los modos"}
local BUT_RANKED = {en = "Every mode but Ranked", fr = "Tous sauf Classé", es = "Todos menos Clasificatoria"}

function MC.mode_names(key, lang)
    local list = MC.modes_of(key)
    if #list >= #MC.ALL_MODES then return nil, EVERY[lang] or EVERY.en end
    if #list == #MC.DECK_MODES and not in_list(list, "ranked") then return nil, BUT_RANKED[lang] or BUT_RANKED.en end
    local names = {}
    for _, m in ipairs(MC.MODE_LIST) do
        if in_list(list, m.key) then names[#names + 1] = name_in(m, lang) end
    end
    return names
end

function MC.modes_text(key)
    local O = g("bom_custom_objects")
    local lang = O and O.lang and O.lang() or "en"
    local names, whole = MC.mode_names(key, lang)
    if whole then return whole end
    return L("Modes") .. ": " .. table.concat(names, ", ")
end

local function wrap(names, max)
    local lines, cur = {}, ""
    for i, n in ipairs(names) do
        local piece = n .. (i < #names and "," or "")
        if cur ~= "" and #cur + 1 + #piece > max then lines[#lines + 1] = cur cur = piece
        else cur = cur == "" and piece or (cur .. " " .. piece) end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

function MC.register_modes_loc(keys)
    local O = g("bom_custom_objects")
    if not (O and O.register_loc) then return end
    local title = {en = "Modes", fr = "Modes", es = "Modos"}
    for _, key in ipairs(keys) do
        local tr = {}
        for _, lang in ipairs({"en", "fr", "es"}) do
            local names, whole = MC.mode_names(key, lang)
            local lines = whole and {whole} or wrap(names, 22)
            for i, l in ipairs(lines) do lines[i] = "{C:attention}" .. l .. "{}" end
            tr[lang] = {name = title[lang], text = lines}
        end
        O.register_loc("Other", "mpm_modes_" .. key, tr)
    end
end

function MC.mode_name(key)
    for _, m in ipairs(MC.MODE_LIST) do if m.key == key then return L(m.name) end end
    return tostring(key)
end

local function party()
    local P = g("bom_party")
    if not (P and P.active) then return nil end
    local ok, on = pcall(P.active)
    if not (ok and on) then return nil end
    return P
end

function MC.in_party() return party() ~= nil end

function MC.mode()
    local P = party()
    if P then return (P.kind and P.kind()) or "br" end
    local R = g("bom_rulesets")
    if R and R.lock_kind and R.lock_kind() == "ranked" then return "ranked" end
    local M = g("bom_match")
    local m = M and M.get_mode and M.get_mode() or "nemesis"
    if m == nil or m == "attrition" or m == "vanilla" or m == "ruleset" or m == "showdown" then m = "nemesis" end
    return m
end

function MC.joker_ok(key, mode, in_party)
    local list = MC.JOKER_MODES[key]
    if not list then return true end
    mode = mode or MC.mode()
    if in_party == nil then in_party = MC.in_party() end
    local center = G and G.P_CENTERS and G.P_CENTERS[key]
    if center and center.mp_duel and in_party then return false end
    if not in_list(MC.ALL_MODES, mode) then return center == nil or center.mp_mode_card ~= true end
    return in_list(list, mode)
end

function MC.traps_ok(mode)
    if mode == nil then
        local W = g("bom_swap")
        if W and W.party_on and W.party_on() then return false end
    end
    mode = mode or MC.mode()
    if mode == "ranked" or mode == "raid" then return false end
    if not in_list(MC.ALL_MODES, mode) then return true end
    return in_list(MC.TRAP_MODES, mode)
end

local function ps()
    local P = g("bom_party")
    return P and P.S and P.S.ps or nil
end

local function me_pid()
    local s = ps()
    local P = g("bom_party")
    return (s and s.myId) or (P and P.S and P.S.me)
end

local function players() return (ps() or {}).players or {} end

function MC.rival(p)
    if type(p) ~= "table" then return false end
    local me = me_pid()
    if p.pid == me then return false end
    local k = MC.mode()
    if k == "raid" then return false end
    if k == "teams" then
        for _, x in ipairs(players()) do
            if x.pid == me then return x.team ~= p.team end
        end
        return true
    end
    return true
end

local function my_entry()
    local me = me_pid()
    for _, p in ipairs(players()) do if p.pid == me then return p end end
    return nil
end

local function living_teammates()
    local mine = my_entry()
    if not mine then return 0 end
    local n = 0
    for _, p in ipairs(players()) do
        if p.pid ~= mine.pid and p.team == mine.team and p.alive ~= false then n = n + 1 end
    end
    return n
end

local function lives_behind()
    local mine = my_entry()
    local my = tonumber(mine and mine.lives) or tonumber(G.GAME.mp_lives) or 0
    local best = my
    for _, p in ipairs(players()) do
        if p.alive ~= false then best = math.max(best, tonumber(p.lives) or 0) end
    end
    return math.max(0, best - my)
end

local function knocked_out()
    local me = me_pid()
    local n = 0
    for _, p in ipairs(players()) do
        if p.pid ~= me and p.alive == false then n = n + 1 end
    end
    return n
end

local function pvp_now()
    return G.GAME and G.GAME.blind and G.GAME.blind.pvp and not G.GAME.blind.mp_pvp_over and true or false
end

local function pvp_kind(kind) return pvp_now() and MC.mode() == kind end
local PVP_KEYS = {bl_mp_nemesis = true, bl_mp_royale = true, bl_mp_clash = true, bl_mp_raid = true}
local function pvp_ended(kind)
    local b = G.GAME and G.GAME.blind
    if not b or MC.mode() ~= kind then return false end
    local key = b.config and b.config.blind and b.config.blind.key
    return (b.pvp or b.mp_pvp_over or PVP_KEYS[key]) and true or false
end

local function beat_blind()
    local ok, won = pcall(function() return G.GAME.chips >= G.GAME.blind.chips end)
    return ok and won
end

local function msg_x(x) return localize{type = "variable", key = "a_xmult", vars = {x}} end
local function msg_mult(m) return localize{type = "variable", key = "a_mult", vars = {m}} end
local function msg_chips(c) return localize{type = "variable", key = "a_chips", vars = {c}} end
local function round2(x) return math.floor(x * 100 + 0.5) / 100 end

local function main(context) return context.cardarea == G.jokers and context.joker_main end
local function round_end(context)
    return context.end_of_round and not context.individual and not context.repetition and not context.blueprint
end

local NEW = {}
MC.NEW = NEW
MC.NEW_KEYS = {
    "j_mp_summit", "j_mp_base_camp", "j_mp_slipstream", "j_mp_pace_car", "j_mp_underdog", "j_mp_vulture",
    "j_mp_wingman", "j_mp_huddle", "j_mp_war_banner", "j_mp_supply_drop",
}

NEW.j_mp_summit = {
    order = 1111, rarity = 2, cost = 7, name = "Summit", col = 0, blueprint_compat = true, perishable_compat = false, eternal_compat = true,
    config = {extra = {gain = 0.15, x_mult = 1}},
    vars = function(c) local e = c.ability.extra return {e.gain, round2(e.x_mult)} end,
    calc = function(c, context)
        local e = c.ability.extra
        if round_end(context) and not context.game_over and G.GAME.blind and G.GAME.blind.boss and beat_blind() then
            e.x_mult = round2(e.x_mult + e.gain)
            return {message = localize("k_upgrade_ex"), colour = G.C.MULT}
        end
        if main(context) and e.x_mult > 1 then return {message = msg_x(e.x_mult), Xmult_mod = e.x_mult} end
    end,
    loc = {
        en = {name = "Summit", text = {"Gains {X:mult,C:white} X#1# {} Mult when", "a {C:attention}Boss Blind{} is defeated", "{C:inactive}(Currently {X:mult,C:white} X#2# {C:inactive} Mult)"}},
        fr = {name = "Sommet", text = {"Gagne {X:mult,C:white} X#1# {} Multi quand", "une {C:attention}Blinde Boss{} est vaincue", "{C:inactive}(Actuellement {X:mult,C:white} X#2# {C:inactive} Multi)"}},
        es = {name = "Cumbre", text = {"Gana {X:mult,C:white} X#1# {} multi al", "vencer una {C:attention}ciega jefe{}", "{C:inactive}(Actual: {X:mult,C:white} X#2# {C:inactive} multi)"}},
    },
}

NEW.j_mp_base_camp = {
    order = 1112, rarity = 1, cost = 5, name = "Base Camp", col = 1, blueprint_compat = true, perishable_compat = false, eternal_compat = true,
    config = {extra = {chips = 25, count = 0}},
    vars = function(c) local e = c.ability.extra return {e.chips, e.chips * e.count} end,
    calc = function(c, context)
        local e = c.ability.extra
        if round_end(context) and not context.game_over and G.GAME.blind and G.GAME.blind.boss and beat_blind() then
            e.count = e.count + 1
            return {message = localize("k_upgrade_ex"), colour = G.C.CHIPS}
        end
        if main(context) and e.count > 0 then return {message = msg_chips(e.chips * e.count), chip_mod = e.chips * e.count} end
    end,
    on_life_lost = function(c)
        local e = c.ability.extra
        if e.count > 0 then
            e.count = 0
            return localize("k_reset")
        end
    end,
    loc = {
        en = {name = "Base Camp", text = {"{C:chips}+#1#{} Chips for each {C:attention}Boss Blind{}", "defeated since you last", "lost a {C:red}life{}", "{C:inactive}(Currently {C:chips}+#2#{C:inactive} Chips)"}},
        fr = {name = "Camp de base", text = {"{C:chips}+#1#{} jetons par {C:attention}Blinde Boss{}", "vaincue depuis votre dernière", "{C:red}vie{} perdue", "{C:inactive}(Actuellement {C:chips}+#2#{C:inactive} jetons)"}},
        es = {name = "Campamento base", text = {"{C:chips}+#1#{} fichas por cada {C:attention}ciega jefe{}", "vencida desde la última", "{C:red}vida{} que perdiste", "{C:inactive}(Actual: {C:chips}+#2#{C:inactive} fichas)"}},
    },
}

NEW.j_mp_slipstream = {
    order = 1113, rarity = 1, cost = 5, name = "Slipstream", col = 2, blueprint_compat = true, perishable_compat = true, eternal_compat = true,
    config = {extra = {dollars = 4}},
    vars = function(c) return {c.ability.extra.dollars} end,
    calc = function(c, context)
        if context.skip_blind then
            local d = c.ability.extra.dollars
            ease_dollars(d)
            card_eval_status_text(c, "dollars", d)
        end
    end,
    loc = {
        en = {name = "Slipstream", text = {"Earn {C:money}$#1#{} when you", "skip a {C:attention}Blind{}"}},
        fr = {name = "Aspiration", text = {"Gagnez {C:money}$#1#{} quand vous", "passez une {C:attention}Blinde{}"}},
        es = {name = "Rebufo", text = {"Gana {C:money}$#1#{} al", "saltar una {C:attention}ciega{}"}},
    },
}

NEW.j_mp_pace_car = {
    order = 1114, rarity = 2, cost = 6, name = "Pace Car", col = 3, blueprint_compat = true, perishable_compat = true, eternal_compat = true,
    config = {extra = {x_mult = 2}},
    vars = function(c) return {c.ability.extra.x_mult} end,
    calc = function(c, context)
        if main(context) and G.GAME.current_round and (G.GAME.current_round.hands_played or 0) == 0 then
            return {message = msg_x(c.ability.extra.x_mult), Xmult_mod = c.ability.extra.x_mult}
        end
    end,
    loc = {
        en = {name = "Pace Car", text = {"{X:mult,C:white} X#1# {} Mult on the", "{C:attention}first hand{} of each round"}},
        fr = {name = "Voiture de tête", text = {"{X:mult,C:white} X#1# {} Multi à la", "{C:attention}première main{} de chaque manche"}},
        es = {name = "Coche guía", text = {"{X:mult,C:white} X#1# {} multi en la", "{C:attention}primera mano{} de cada ronda"}},
    },
}

NEW.j_mp_underdog = {
    order = 1115, rarity = 2, cost = 6, name = "Underdog", col = 4, blueprint_compat = true, perishable_compat = true, eternal_compat = true,
    config = {extra = {per = 0.5, cap = 3}},
    cur = function(c) local e = c.ability.extra return math.min(e.cap, 1 + e.per * lives_behind()) end,
    vars = function(c) local e = c.ability.extra return {e.per, e.cap, NEW.j_mp_underdog.cur(c)} end,
    calc = function(c, context)
        if main(context) and pvp_now() then
            local x = NEW.j_mp_underdog.cur(c)
            if x > 1 then return {message = msg_x(x), Xmult_mod = x} end
        end
    end,
    loc = {
        en = {name = "Underdog", text = {"In {C:attention}PvP Blinds{}, {X:mult,C:white} X#1# {} Mult for each", "{C:red}life{} you are behind the player", "with the most lives {C:inactive}(Max {X:mult,C:white} X#2# {C:inactive})", "{C:inactive}(Currently {X:mult,C:white} X#3# {C:inactive} Mult)"}},
        fr = {name = "Outsider", text = {"En {C:attention}Blinde JcJ{}, {X:mult,C:white} X#1# {} Multi par", "{C:red}vie{} de retard sur le joueur", "qui en a le plus {C:inactive}(Max {X:mult,C:white} X#2# {C:inactive})", "{C:inactive}(Actuellement {X:mult,C:white} X#3# {C:inactive} Multi)"}},
        es = {name = "Desvalido", text = {"En una {C:attention}ciega JcJ{}, {X:mult,C:white} X#1# {} multi por", "cada {C:red}vida{} que vas por detrás", "del que más tiene {C:inactive}(Máx. {X:mult,C:white} X#2# {C:inactive})", "{C:inactive}(Actual: {X:mult,C:white} X#3# {C:inactive} multi)"}},
    },
}

NEW.j_mp_vulture = {
    order = 1116, rarity = 1, cost = 4, name = "Vulture", col = 5, blueprint_compat = false, perishable_compat = true, eternal_compat = true,
    config = {extra = {dollars = 4, owed = 0}},
    vars = function(c) return {c.ability.extra.dollars} end,
    poll = function(c)
        local e = c.ability.extra
        local n = knocked_out()
        if e.seen == nil or n < e.seen then e.seen = n return end
        if n > e.seen then
            e.owed = (e.owed or 0) + (n - e.seen)
            e.seen = n
        end
    end,
    dollars = function(c)
        local e = c.ability.extra
        local owed = e.owed or 0
        if owed <= 0 then return nil end
        e.owed = 0
        return owed * e.dollars
    end,
    loc = {
        en = {name = "Vulture", text = {"Earn {C:money}$#1#{} at end of round", "for each player knocked out", "since the last round"}},
        fr = {name = "Vautour", text = {"Gagnez {C:money}$#1#{} en fin de manche", "par joueur éliminé", "depuis la dernière manche"}},
        es = {name = "Buitre", text = {"Gana {C:money}$#1#{} al final de la ronda", "por cada jugador eliminado", "desde la última ronda"}},
    },
}

NEW.j_mp_wingman = {
    order = 1117, rarity = 1, cost = 5, name = "Wingman", col = 6, blueprint_compat = true, perishable_compat = true, eternal_compat = true,
    config = {extra = {mult = 5}},
    vars = function(c) return {c.ability.extra.mult, c.ability.extra.mult * living_teammates()} end,
    calc = function(c, context)
        if main(context) then
            local m = c.ability.extra.mult * living_teammates()
            if m > 0 then return {message = msg_mult(m), mult_mod = m} end
        end
    end,
    loc = {
        en = {name = "Wingman", text = {"{C:mult}+#1#{} Mult for each", "living {C:attention}teammate{}", "{C:inactive}(Currently {C:mult}+#2#{C:inactive} Mult)"}},
        fr = {name = "Ailier", text = {"{C:mult}+#1#{} Multi par", "{C:attention}coéquipier{} en vie", "{C:inactive}(Actuellement {C:mult}+#2#{C:inactive} Multi)"}},
        es = {name = "Escudero", text = {"{C:mult}+#1#{} multi por cada", "{C:attention}compañero{} con vida", "{C:inactive}(Actual: {C:mult}+#2#{C:inactive} multi)"}},
    },
}

NEW.j_mp_huddle = {
    order = 1118, rarity = 2, cost = 6, name = "Huddle", col = 7, blueprint_compat = true, perishable_compat = true, eternal_compat = true,
    config = {extra = {per = 0.5}},
    cur = function(c) return 1 + c.ability.extra.per * living_teammates() end,
    vars = function(c) return {c.ability.extra.per, NEW.j_mp_huddle.cur(c)} end,
    calc = function(c, context)
        if main(context) and pvp_now() then
            local x = NEW.j_mp_huddle.cur(c)
            if x > 1 then return {message = msg_x(x), Xmult_mod = x} end
        end
    end,
    loc = {
        en = {name = "Huddle", text = {"In {C:attention}PvP Blinds{}, {X:mult,C:white} X#1# {} Mult", "for each living {C:attention}teammate{}", "{C:inactive}(Currently {X:mult,C:white} X#2# {C:inactive} Mult)"}},
        fr = {name = "Mêlée", text = {"En {C:attention}Blinde JcJ{}, {X:mult,C:white} X#1# {} Multi", "par {C:attention}coéquipier{} en vie", "{C:inactive}(Actuellement {X:mult,C:white} X#2# {C:inactive} Multi)"}},
        es = {name = "Corrillo", text = {"En una {C:attention}ciega JcJ{}, {X:mult,C:white} X#1# {} multi", "por cada {C:attention}compañero{} con vida", "{C:inactive}(Actual: {X:mult,C:white} X#2# {C:inactive} multi)"}},
    },
}

NEW.j_mp_war_banner = {
    order = 1119, rarity = 2, cost = 6, name = "War Banner", col = 8, blueprint_compat = true, perishable_compat = true, eternal_compat = true,
    config = {extra = {x_mult = 1.75}},
    vars = function(c) return {c.ability.extra.x_mult} end,
    calc = function(c, context)
        if main(context) and pvp_kind("raid") then
            return {message = msg_x(c.ability.extra.x_mult), Xmult_mod = c.ability.extra.x_mult}
        end
    end,
    loc = {
        en = {name = "War Banner", text = {"{X:mult,C:white} X#1# {} Mult in", "{C:attention}Raid Blinds{}"}},
        fr = {name = "Bannière de guerre", text = {"{X:mult,C:white} X#1# {} Multi en", "{C:attention}Blinde de raid{}"}},
        es = {name = "Estandarte", text = {"{X:mult,C:white} X#1# {} multi en las", "{C:attention}ciegas de asalto{}"}},
    },
}

NEW.j_mp_supply_drop = {
    order = 1120, rarity = 1, cost = 5, name = "Supply Drop", col = 9, blueprint_compat = false, perishable_compat = true, eternal_compat = true,
    config = {extra = {base = 3, per = 1}},
    amount = function(c)
        local e = c.ability.extra
        return e.base + e.per * math.max(0, #players() - 1)
    end,
    vars = function(c) local e = c.ability.extra return {e.base, e.per, NEW.j_mp_supply_drop.amount(c)} end,
    calc = function(c, context)
        if round_end(context) and pvp_ended("raid") then c.ability.extra.pay = true end
    end,
    dollars = function(c)
        local e = c.ability.extra
        if not e.pay then return nil end
        e.pay = nil
        return NEW.j_mp_supply_drop.amount(c)
    end,
    loc = {
        en = {name = "Supply Drop", text = {"When a {C:attention}Raid Blind{} ends, earn", "{C:money}$#1#{} plus {C:money}$#2#{} for each other", "player in the raid", "{C:inactive}(Currently {C:money}$#3#{C:inactive})"}},
        fr = {name = "Ravitaillement", text = {"À la fin d'une {C:attention}Blinde de raid{},", "gagnez {C:money}$#1#{} plus {C:money}$#2#{} par autre", "joueur du raid", "{C:inactive}(Actuellement {C:money}$#3#{C:inactive})"}},
        es = {name = "Suministros", text = {"Al terminar una {C:attention}ciega de asalto{},", "gana {C:money}$#1#{} más {C:money}$#2#{} por cada otro", "jugador del asalto", "{C:inactive}(Actual: {C:money}$#3#{C:inactive})"}},
    },
}

MC.STR_FR = {
    ["Rivals"] = "Rivaux", ["Ranked"] = "Classé", ["Ascension"] = "Ascension", ["Race"] = "Course",
    ["Battle Royale"] = "Battle Royale", ["Teams"] = "Équipes", ["Co-op Raid"] = "Raid coop"
}
MC.STR_ES = {
    ["Rivals"] = "Rivales", ["Ranked"] = "Clasificatoria", ["Ascension"] = "Ascensión", ["Race"] = "Carrera",
    ["Battle Royale"] = "Battle Royale", ["Teams"] = "Equipos", ["Co-op Raid"] = "Asalto coop"
}

local function O() return g("bom_custom_objects") end

function MC.load_atlas()
    if not (G and G.ASSET_ATLAS and love and love.graphics) then return false end
    if G.ASSET_ATLAS[MC.ATLAS] then return true end
    local scale = (G.SETTINGS and G.SETTINGS.GRAPHICS and G.SETTINGS.GRAPHICS.texture_scaling) or 2
    local path = "resources/textures/" .. scale .. "x/" .. MC.ATLAS_FILE
    if not (love.filesystem and love.filesystem.getInfo and (love.filesystem.getInfo(path) or (release_art and release_art.has(path)))) then return false end
    local ok, img = pcall(love.graphics.newImage, path, {mipmaps = true, dpiscale = scale})
    if not ok or not img then return false end
    G.ASSET_ATLAS[MC.ATLAS] = {name = MC.ATLAS, image = img, px = 71, py = 95}
    return true
end

local PLACEHOLDER = {
    j_mp_summit = 12, j_mp_base_camp = 4, j_mp_slipstream = 5, j_mp_pace_car = 8, j_mp_underdog = 4, j_mp_vulture = 6,
    j_mp_wingman = 3, j_mp_huddle = 7, j_mp_war_banner = 11, j_mp_supply_drop = 9,
}

local function register_centers()
    local o = O()
    if not (o and o.DEFS and o.JOKER_KEYS and G and G.P_CENTERS) then return false end
    local own = MC.load_atlas()
    local added = false
    for _, key in ipairs(MC.NEW_KEYS) do
        local d = NEW[key]
        local atlas, pos = own and MC.ATLAS or "mp_jokers", own and {x = d.col, y = 0} or {x = PLACEHOLDER[key] or 3, y = 0}
        local ja = g("bom_joker_art")
        local art = ja and ja.slot and ja.slot(key)
        if art then atlas, pos = art.atlas, art.pos end
        if not o.DEFS[key] then
            o.DEFS[key] = {order = d.order, rarity = d.rarity, cost = d.cost, name = d.name, config = d.config, loc = d.loc, vars = d.vars,
                blueprint_compat = d.blueprint_compat, perishable_compat = d.perishable_compat, eternal_compat = d.eternal_compat}
            o.JOKER_KEYS[#o.JOKER_KEYS + 1] = key
            added = true
        end
        o.DEFS[key].atlas, o.DEFS[key].pos = atlas, pos
        local c = G.P_CENTERS[key]
        if c and (c.atlas ~= atlas or not c.mp_mode_card) then
            c.atlas, c.pos, c.mp_mode_card = atlas, {x = pos.x, y = pos.y}, true
        end
        if c and art then c.ai_art = false end
        if not G.P_CENTERS[key] then
            local cfg = {}
            for k, v in pairs(d.config) do
                if type(v) == "table" then
                    local t = {}
                    for k2, v2 in pairs(v) do t[k2] = v2 end
                    cfg[k] = t
                else cfg[k] = v end
            end
            G.P_CENTERS[key] = {
                key = key, order = d.order, unlocked = true, discovered = true, omit = true,
                blueprint_compat = d.blueprint_compat, perishable_compat = d.perishable_compat, eternal_compat = d.eternal_compat,
                rarity = d.rarity, cost = d.cost, name = d.name, set = "Joker", effect = "", cost_mult = 1.0, config = cfg,
                pos = {x = pos.x, y = pos.y}, atlas = atlas, mp_joker = true, mp_mode_card = true,
                ai_art = art and false or nil,
            }
            added = true
        end
        if o.register_loc then o.register_loc("Joker", key, d.loc) end
    end
    local keys = {}
    for key in pairs(MC.JOKER_MODES) do keys[#keys + 1] = key end
    local T = g("bom_traps")
    for key in pairs(T and T.BY_KEY or {}) do keys[#keys + 1] = key end
    MC.register_modes_loc(keys)
    if added then o.pools_on = nil end
    if o.inject_loc then pcall(o.inject_loc) end
    return true
end

function MC.set_bans()
    if not (G and G.GAME) then return end
    G.GAME.banned_keys = G.GAME.banned_keys or {}
    local bans = G.GAME.banned_keys
    for _, k in ipairs(MC.CLOCK_BANS) do
        if not bans[k] then bans[k] = true end
    end
end

local function flag_of(key) return "mpm_" .. key end

function MC.set_flags()
    if not (G and G.GAME and G.P_CENTERS) then return end
    G.GAME.pool_flags = G.GAME.pool_flags or {}
    local flags = G.GAME.pool_flags
    local o = O()
    local on = o and o.enabled and o.enabled() or false
    local mode, inp = MC.mode(), MC.in_party()
    for key in pairs(MC.JOKER_MODES) do
        local c = G.P_CENTERS[key]
        if c then
            local f = flag_of(key)
            if c.yes_pool_flag ~= f then c.yes_pool_flag = f end
            local want = (on and MC.joker_ok(key, mode, inp)) or nil
            if flags[f] ~= want then flags[f] = want end
        end
    end
end

local function key_of(card)
    return card and card.config and card.config.center and card.config.center.key
end

local function patch()
    if MC.patched or not Card then return end
    MC.patched = true
    local orig_calc = Card.calculate_joker
    Card.calculate_joker = function(self, context)
        local ret = orig_calc(self, context)
        local d = NEW[key_of(self)]
        if d and d.calc and context and not self.debuff and self.ability and self.ability.extra then
            local ok, r = pcall(d.calc, self, context)
            if ok and r then ret = r end
        end
        return ret
    end
    local orig_dollar = Card.calculate_dollar_bonus
    Card.calculate_dollar_bonus = function(self)
        local d = NEW[key_of(self)]
        if d and d.dollars then
            if self.debuff or not self.ability or not self.ability.extra then return nil end
            local ok, r = pcall(d.dollars, self)
            if ok and r and r > 0 then return r end
            return nil
        end
        return orig_dollar(self)
    end
    local orig_ui = Card.generate_UIBox_ability_table
    Card.generate_UIBox_ability_table = function(self, vars_only, ...)
        local ui = orig_ui(self, vars_only, ...)
        if not vars_only and ui and self.area and self.area.config and self.area.config.mpm_modes then
            local k = "mpm_modes_" .. tostring(key_of(self))
            local d = G.localization and G.localization.descriptions and G.localization.descriptions.Other
            if d and d[k] then pcall(generate_card_ui, {key = k, set = "Other"}, ui) end
        end
        return ui
    end
    if Back and Back.apply_to_run and not MC.back_wrapped then
        MC.back_wrapped = true
        local orig_apply = Back.apply_to_run
        Back.apply_to_run = function(self, ...)
            local r = orig_apply(self, ...)
            local M = g("bom_match")
            if M and M._starting_mp_run then pcall(MC.set_bans) end
            return r
        end
    end
    local T = g("bom_traps")
    if T and T.enabled and not MC.traps_wrapped then
        MC.traps_wrapped = true
        local orig_enabled = T.enabled
        T.enabled = function() return orig_enabled() and MC.traps_ok() end
        local orig_leader = T.leader
        T.leader = function()
            if not MC.in_party() then return orig_leader and orig_leader() or nil end
            local best
            for _, p in ipairs(players()) do
                if p.alive ~= false and MC.rival(p) and not p.bot then
                    local lv, sc = tonumber(p.lives) or 0, tonumber(p.live and p.live.score) or 0
                    if not best or lv > best.lv or (lv == best.lv and sc > best.sc) then best = {pid = p.pid, lv = lv, sc = sc, name = p.name} end
                end
            end
            return best
        end
    end
end

local function hide_rows()
    local LS = g("bom_lobby_settings")
    if not (LS and LS.DEFS) or MC.rows_done then return end
    MC.rows_done = true
    local function kind(s)
        if MC.lobby_party() then return s.party_kind or "br" end
        return s.mode or "nemesis"
    end
    local NO_PVP_WIN = {ascension = true, race = true, raid = true}
    local NO_HIDE = {ascension = true, race = true, raid = true}
    local rules = {
        life_steal = function(s) return not NO_PVP_WIN[kind(s)] end,
        pvp_win_money = function(s) return not NO_PVP_WIN[kind(s)] end,
        hide_opp_score = function(s) return not NO_HIDE[kind(s)] end,
        traps = function(s)
            local W = g("bom_swap")
            if MC.lobby_party() and W and W.party_swap_settings and W.party_swap_settings(s) then return false end
            local M = g("bom_match")
            if not MC.lobby_party() and M and M.get_state and (M.get_state() or {}).opp_bot == true then return false end
            return MC.traps_ok(kind(s))
        end,
    }
    for _, d in ipairs(LS.DEFS) do
        local rule = d.key and rules[d.key]
        if rule then
            local old = d.show
            d.show = function(s)
                s = s or {}
                if old and not old(s) then return false end
                return rule(s)
            end
        end
    end
end

function MC.lobby_party()
    local P = g("bom_party")
    if not (P and P.active) then return false end
    local ok, on = pcall(P.active)
    return ok and on or false
end

local function poll()
    if not (G and G.GAME and G.GAME.multiplayer and G.jokers and G.jokers.cards) then return end
    local lives = tonumber(G.GAME.mp_lives)
    local last = tonumber(G.GAME.mpm_lives_seen)
    G.GAME.mpm_lives_seen = lives
    local lost = lives and last and lives < last
    for _, c in ipairs(G.jokers.cards) do
        local d = NEW[key_of(c)]
        if d and c.ability and c.ability.extra and not c.debuff then
            local text
            if d.poll then
                local ok, r = pcall(d.poll, c)
                if ok then text = r end
            end
            if lost and d.on_life_lost then
                local ok, r = pcall(d.on_life_lost, c)
                if ok and r then text = r end
            end
            if text then pcall(card_eval_status_text, c, "extra", nil, nil, nil, {message = text, colour = G.C.RED}) end
        end
    end
end

function MC.update()
    if not MC.ready then return end
    local c = G and G.P_CENTERS and G.P_CENTERS.j_mp_summit
    if not (c and c.mp_mode_card) then pcall(register_centers) end
    pcall(MC.set_flags)
    if G and G.GAME and G.GAME.multiplayer then pcall(MC.set_bans) end
    pcall(poll)
end

function MC.init()
    local fr, es = {}, {}
    for k, v in pairs(MC.STR_FR) do fr[k] = v end
    for k, v in pairs(MC.STR_ES) do es[k] = v end
    fr["All modes"], es["All modes"] = "Tous les modes", "Todos los modos"
    fr["Every mode"], es["Every mode"] = "Tous les modes", "Todos los modos"
    fr["Every mode but Ranked"], es["Every mode but Ranked"] = "Tous sauf Classé", "Todos menos Clasificatoria"
    fr["Modes"], es["Modes"] = "Modes", "Modos"
    if mod_loc_register then pcall(mod_loc_register, {fr = fr, es = es}) end
    pcall(register_centers)
    pcall(patch)
    pcall(hide_rows)
    MC.ready = true
end

return MC
