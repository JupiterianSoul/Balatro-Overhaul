local R = {}

local function L(s)
    if mod_loc then
        local ok, r = pcall(mod_loc, s)
        if ok and r then return r end
    end
    return s
end

local S = {data = nil, box = nil, sig = nil, result = nil}
R.S = S

local FR = {
    ["Race"] = "Course",
    ["First to clear the target ante wins"] = "Le premier à finir la mise initiale visée gagne",
    ["No PvP: first to clear the target ante wins"] = "Pas de JcJ : le premier à finir la mise initiale visée gagne",
    ["Race to ante %d"] = "Course jusqu'à la mise initiale %d",
    ["Target ante"] = "Mise initiale visée",
    ["Ties go to whoever got there first"] = "En cas d'égalité, le plus rapide gagne",
    ["You won the race!"] = "Vous avez gagné la course !",
    ["%s won the race"] = "%s a gagné la course",
    ["Sprint"] = "Sprint",
    ["Classic race to ante 4, failed blinds cost a life"] = "Course classique jusqu'à la mise initiale 4, une blinde ratée coûte une vie",
    ["Race to ante 2, one life"] = "Course jusqu'à la mise initiale 2, une vie",
    ["Marathon"] = "Marathon",
    ["Race to ante 8, three lives"] = "Course jusqu'à la mise initiale 8, trois vies",
    ["A%d %s"] = "A%d %s",
    ["Out"] = "Éliminé",
    ["Done"] = "Fini",
}
local ES = {
    ["Race"] = "Carrera",
    ["First to clear the target ante wins"] = "Gana el primero en superar la apuesta inicial objetivo",
    ["No PvP: first to clear the target ante wins"] = "Sin JcJ: gana el primero en superar la apuesta inicial objetivo",
    ["Race to ante %d"] = "Carrera hasta la apuesta inicial %d",
    ["Target ante"] = "Apuesta inicial objetivo",
    ["Ties go to whoever got there first"] = "En empate gana quien llegó antes",
    ["You won the race!"] = "¡Ganaste la carrera!",
    ["%s won the race"] = "%s ganó la carrera",
    ["Sprint"] = "Sprint",
    ["Classic race to ante 4, failed blinds cost a life"] = "Carrera clásica hasta la apuesta inicial 4, una ciega fallida cuesta una vida",
    ["Race to ante 2, one life"] = "Carrera hasta la apuesta inicial 2, una vida",
    ["Marathon"] = "Maratón",
    ["Race to ante 8, three lives"] = "Carrera hasta la apuesta inicial 8, tres vidas",
    ["A%d %s"] = "A%d %s",
    ["Out"] = "Fuera",
    ["Done"] = "Terminado",
}

local BLIND_SHORT = {S = "Small", B = "Big", L = "Boss"}

local function settings() return (bom_match and bom_match.get_settings and bom_match.get_settings()) or {} end

local function party_on()
    local ok, r = pcall(function() return bom_party and bom_party.active and bom_party.active() end)
    return ok and r or false
end

function R.active()
    if not (G and G.GAME and G.GAME.multiplayer) then return false end
    if party_on() then return (settings().party_kind or (bom_party.kind and bom_party.kind())) == "race" end
    return (bom_match and bom_match.get_mode and bom_match.get_mode()) == "race"
end

local function remove_box()
    if S.box then pcall(function() S.box:remove() end) end
    S.box, S.sig = nil, nil
end
R.remove = remove_box

local function bar_row(p, goal, w, me)
    local d = bom_kit and bom_kit.dims and bom_kit.dims() or {row_h = 0.42, scale = 0.32}
    local h = d.row_h * 0.8
    local name_w = 1.7
    local bar_w = w - name_w - 1.15
    local frac = math.max(0, math.min(1, (tonumber(p.cleared) or 0) / math.max(1, goal)))
    local fill_w = math.max(0.02, bar_w * frac)
    local col = p.alive == false and G.C.UI.BACKGROUND_INACTIVE or (me and G.C.GOLD or G.C.BLUE)
    local name = bom_kit and bom_kit.name_bar and bom_kit.name_bar(p.name or "?", {w = name_w, h = h}) or
        {n = G.UIT.C, config = {align = "cm", minw = name_w, maxw = name_w}, nodes = {{n = G.UIT.T, config = {text = p.name or "?", scale = 0.28, colour = G.C.WHITE}}}}
    local where
    if p.alive == false then where = L("Out")
    elseif (tonumber(p.cleared) or 0) >= goal then where = L("Done")
    else where = string.format(L("A%d %s"), tonumber(p.ante) or 1, L(BLIND_SHORT[p.blind or "S"] or "Small")) end
    return {n = G.UIT.R, config = {align = "cm", padding = 0.03, r = 0.08, colour = me and {1, 1, 1, 0.08} or nil}, nodes = {
        name,
        {n = G.UIT.C, config = {minw = 0.08}},
        {n = G.UIT.C, config = {align = "cl", minw = bar_w, maxw = bar_w, minh = h * 0.7, r = 0.1, colour = G.C.BLACK}, nodes = {
            {n = G.UIT.C, config = {minw = fill_w, maxw = fill_w, minh = h * 0.7, r = 0.1, colour = col}},
        }},
        {n = G.UIT.C, config = {align = "cm", minw = 1.05, maxw = 1.05}, nodes = {{n = G.UIT.T, config = {text = where, scale = 0.27, colour = G.C.UI.TEXT_LIGHT, shadow = true}}}},
    }}
end

function R.render()
    local d = S.data
    if not (d and G and G.ROOM_ATTACH and R.active()) then remove_box() return end
    local players = d.players or {}
    local goal = tonumber(d.goal) or ((tonumber(d.target) or 4) * 3)
    local parts = {}
    for _, p in ipairs(players) do parts[#parts + 1] = tostring(p.pid) .. ":" .. tostring(p.cleared) .. ":" .. tostring(p.alive) .. ":" .. tostring(p.ante) .. tostring(p.blind) end
    local sig = table.concat(parts, "|") .. "/" .. tostring(goal)
    if sig == S.sig and S.box then return end
    remove_box()
    local sorted = {}
    for _, p in ipairs(players) do sorted[#sorted + 1] = p end
    table.sort(sorted, function(a, b)
        local ca, cb = tonumber(a.cleared) or 0, tonumber(b.cleared) or 0
        if ca ~= cb then return ca > cb end
        return (tonumber(a.at) or 0) < (tonumber(b.at) or 0)
    end)
    local w = 4.6
    local rows = {{n = G.UIT.R, config = {align = "cm", minh = 0.35}, nodes = {
        {n = G.UIT.T, config = {text = string.format(L("Race to ante %d"), tonumber(d.target) or 4), scale = 0.32, colour = G.C.GOLD, shadow = true}},
    }}}
    local me = d.you
    if me == nil and bom_party and bom_party.S and bom_party.S.ps then me = bom_party.S.ps.myId end
    for i, p in ipairs(sorted) do
        if i > 8 then break end
        rows[#rows + 1] = bar_row(p, goal, w, p.pid == me)
    end
    S.sig = sig
    local ok, box = pcall(UIBox, {
        definition = {n = G.UIT.ROOT, config = {align = "cm", padding = 0.08, r = 0.12, colour = {0, 0, 0, 0.55}, minw = w + 0.2}, nodes = rows},
        config = {align = "tri", offset = {x = -0.25, y = 0.25}, major = G.ROOM_ATTACH, bond = "Weak"},
    })
    if ok then S.box = box end
end

local function on_race_state(d)
    if type(d) ~= "table" then return end
    S.data = d
    pcall(R.render)
end

local function on_party_state(d)
    if type(d) == "table" and type(d.race) == "table" then
        local r = d.race
        r.you = d.myId
        S.data = r
        pcall(R.render)
    end
end

local function on_resolved(d)
    if type(d) ~= "table" then return end
    S.result = d
    local text
    if d.result == "win" then text = L("You won the race!")
    else
        local name = "?"
        for _, p in ipairs((S.data and S.data.players) or {}) do if p.pid == d.winner then name = p.name or name end end
        text = string.format(L("%s won the race"), name)
    end
    pcall(function()
        attention_text({text = text, scale = 0.8, hold = 3, major = G.play, align = "cm", offset = {x = 0, y = -2.5}, colour = d.result == "win" and G.C.GREEN or G.C.RED})
    end)
end

function R.update()
    if S.box and not R.active() then remove_box() S.data = nil end
end

local function register_mode()
    if bom_gamemodes and bom_gamemodes.register and not (bom_gamemodes.registry and bom_gamemodes.registry.race) then
        bom_gamemodes.register({
            key = "race", display_name = "Race",
            description = "No PvP blinds. Everyone plays their own run: the first to clear the target ante wins. Ties go to whoever got there first.",
            rule = "No PvP: first to clear the target ante wins", order = 4, default_lives = 2,
            is_blind_pvp = function() return false end,
            get_blinds_by_ante = function() return nil, nil, nil end,
            banned_jokers = {}, banned_consumables = {}, banned_vouchers = {}, banned_enhancements = {}, banned_tags = {}, banned_blinds = {},
        })
    end
    local RS = bom_rulesets
    if RS and RS.add_mode and RS.register then
        RS.add_mode({key = "race", name = "Race"})
        RS.register{id = "race_classic", mode = "race", family = "classic", name = "Classic", desc = "Classic race to ante 4, failed blinds cost a life",
            settings = {race_target = 4, starting_lives = 2, death_on_round_loss = true}}
        RS.register{id = "race_balanced", mode = "race", family = "balanced", name = "Balanced", desc = "MP balance reworks, Justice banned",
            reworks = RS.BALANCED_REWORKS, bans = {consumables = {"c_justice"}}, settings = {race_target = 4, starting_lives = 2, the_order = true}}
        RS.register{id = "race_sprint", mode = "race", family = "speed", name = "Sprint", desc = "Race to ante 2, one life",
            settings = {race_target = 2, starting_lives = 1}}
        RS.register{id = "race_marathon", mode = "race", family = "marathon", name = "Marathon", desc = "Race to ante 8, three lives",
            settings = {race_target = 8, starting_lives = 3}}
    end
end

function R.init()
    if mod_loc_register then pcall(mod_loc_register, {fr = FR, es = ES}) end
    pcall(register_mode)
    if bom_events and bom_events.register then
        bom_events.register("race_state", on_race_state)
        bom_events.register("party_state", on_party_state)
        bom_events.register("race_resolved", on_resolved)
        bom_events.register("match_ended", function() remove_box() end)
        bom_events.register("lobby_returned", function() remove_box() S.data = nil end)
    end
end

return R
