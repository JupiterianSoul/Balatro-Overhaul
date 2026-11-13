local F = {}

F.KEYS = {speed = "allow_fast_speed", score = "allow_score_speed", skip = "allow_skip_score", seed = "show_seed"}
F.SEED_BUTTONS = {copy_seed = true, seed_lib_save_current = true}

local function L(s) return mod_loc and mod_loc(s) or s end

local function mp_run()
    return G and G.STAGES and G.STAGE == G.STAGES.RUN and G.GAME and G.GAME.multiplayer and true or false
end

local function ranked()
    local R = rawget(_G, "bom_rulesets")
    local ok, kind = pcall(function() return R and R.lock_kind and R.lock_kind() end)
    return ok and kind == "ranked"
end

local function settings()
    local s = G and G.GAME and G.GAME.mp_settings
    if type(s) ~= "table" and bom_match and bom_match.get_settings then s = bom_match.get_settings() end
    return type(s) == "table" and s or {}
end

local function match_over()
    local bm = rawget(_G, "bom_match")
    return bm and bm.get_phase and bm.PHASE and bm.get_phase() == bm.PHASE.MATCH_END or false
end

local function live_watch_seed_hidden(pb)
    local S = pb.state and pb.state()
    if type(S) ~= "table" or S.mode ~= "live" or S.live_over then return false end
    local h = type(S.header) == "table" and S.header or {}
    local s = type(h.settings) == "table" and h.settings or {}
    return h.ranked == true or s.show_seed ~= true
end

function F.allowed(what)
    local pb = rawget(_G, "bom_playback")
    if pb and pb.active and pb.active() then return not (what == "seed" and live_watch_seed_hidden(pb)) end
    if not mp_run() then return true end
    if what == "seed" and match_over() then return true end
    if ranked() then return false end
    return settings()[F.KEYS[what]] == true
end

function F.limited(what) return not F.allowed(what) end

F.LABELS = {
    {key = "allow_fast_speed", label = "Game speed over 4x"},
    {key = "allow_score_speed", label = "Score speed"},
    {key = "allow_skip_score", label = "Skip score animation"},
    {key = "show_seed", label = "Show the seed"},
}

function F.recap_line(s)
    if ranked() then return nil end
    s = s or settings()
    local on = {}
    for _, d in ipairs(F.LABELS) do
        if s[d.key] == true then on[#on + 1] = L(d.label) end
    end
    if #on == 0 then return nil end
    return L("Fair play") .. ": " .. table.concat(on, ", ")
end

function F.seed_hidden() return not F.allowed("seed") end

local function seed_text()
    local g = G and G.GAME
    return g and g.pseudorandom and g.pseudorandom.seed and tostring(g.pseudorandom.seed) or nil
end

local function dyna_strings(o)
    if type(o) ~= "table" or type(o.config) ~= "table" or type(o.config.string) ~= "table" then return {} end
    return o.config.string
end

local function scan(node, seed, out, depth)
    if type(node) ~= "table" or depth > 60 then return end
    local c = node.config
    if type(c) == "table" then
        if c.button then
            if F.SEED_BUTTONS[c.button] then out.button = true else out.other = true end
        end
        if c.text ~= nil and tostring(c.text) == seed then out.seed = true end
        for _, x in ipairs(dyna_strings(c.object)) do
            if tostring(type(x) == "table" and x.string or x) == seed then out.seed = true end
        end
    end
    for _, ch in pairs(type(node.nodes) == "table" and node.nodes or {}) do scan(ch, seed, out, depth + 1) end
end

local function drop_objects(node, depth)
    if type(node) ~= "table" or depth > 60 then return end
    local o = type(node.config) == "table" and node.config.object
    if type(o) == "table" and o.remove then pcall(o.remove, o) end
    for _, ch in pairs(type(node.nodes) == "table" and node.nodes or {}) do drop_objects(ch, depth + 1) end
end

local function hide_text(node, seed, label)
    local c = node.config
    if type(c) ~= "table" then return end
    if c.text ~= nil and tostring(c.text) == seed then c.text = label end
    local o = c.object
    for _, x in ipairs(dyna_strings(o)) do
        if tostring(type(x) == "table" and x.string or x) == seed then
            local oc = o.config
            pcall(o.remove, o)
            c.object = DynaText({string = {label}, colours = oc.colours, shadow = oc.shadow, float = oc.float, scale = oc.scale})
            return
        end
    end
end

function F.hide_seed_in(node, depth, label)
    depth = depth or 0
    label = label or L("Hidden in MP")
    local seed = seed_text()
    if not seed or type(node) ~= "table" or depth > 60 then return node end
    hide_text(node, seed, label)
    local kids = type(node.nodes) == "table" and node.nodes or {}
    local keys = {}
    for k in pairs(kids) do keys[#keys + 1] = k end
    for _, k in ipairs(keys) do
        local m = {}
        scan(kids[k], seed, m, 0)
        if m.button and not m.other and not m.seed then
            drop_objects(kids[k], 0)
            kids[k] = nil
        elseif m.seed or m.button then
            F.hide_seed_in(kids[k], depth + 1, label)
        end
    end
    return node
end

local function wrap_ui(get, set)
    local orig = get()
    if type(orig) ~= "function" then return end
    set(function(...)
        local t = orig(...)
        if F.seed_hidden() then F.hide_seed_in(t) end
        return t
    end)
end

local function wrap_func(name)
    local orig = G.FUNCS[name]
    if type(orig) ~= "function" then return end
    G.FUNCS[name] = function(...)
        if F.seed_hidden() then
            pcall(play_sound, 'cancel')
            return
        end
        return orig(...)
    end
end

local function pack_state(st)
    local S = G.STATES
    return st ~= nil and (st == S.TAROT_PACK or st == S.PLANET_PACK or st == S.SPECTRAL_PACK or st == S.STANDARD_PACK
        or st == S.BUFFOON_PACK or (S.SMODS_BOOSTER_OPENED ~= nil and st == S.SMODS_BOOSTER_OPENED))
end

local function guard_on()
    if not mp_run() then return false end
    local pb = rawget(_G, "bom_playback")
    if pb and pb.active and pb.active() then return false end
    local rj = rawget(_G, "bom_rejoin")
    return rj ~= nil and rj.has_match_session ~= nil and rj.has_match_session() and true or false
end

function F.update()
    if not (G and G.STATES and G.GAME) then return end
    local rj = rawget(_G, "bom_rejoin")
    local t = rj and rj.pending_table
    if type(t) == "table" and t.ACTION and t ~= F.forced and guard_on() then
        F.forced = t
        F.action_uploads = (F.action_uploads or 0) + 1
        pcall(rj.upload_pending, true)
    end
    if F.save_after_use then
        if not guard_on() then
            F.save_after_use = nil
        elseif (G.GAME.STOP_USE or 0) == 0 and (G.STATE == G.STATES.SHOP or G.STATE == G.STATES.SELECTING_HAND or G.STATE == G.STATES.BLIND_SELECT) then
            F.save_after_use = nil
            F.use_saves = (F.use_saves or 0) + 1
            pcall(save_run)
        end
    end
end

local function hook_actions()
    local use = G.FUNCS.use_card
    if type(use) == "function" then
        G.FUNCS.use_card = function(e, ...)
            local card = e and e.config and e.config.ref_table
            local st = G.STATE
            local r = use(e, ...)
            if card and card.ability and card.ability.consumeable and not pack_state(st) and guard_on() then F.save_after_use = true end
            return r
        end
    end
end

function F.register_strings()
    if not mod_loc_register then return end
    mod_loc_register{
        fr = {
            ["Fair play"] = "Fair-play",
            ["Game speed over 4x"] = "Vitesse de jeu au-delà de 4x",
            ["Players can pick any game speed"] = "Les joueurs choisissent n'importe quelle vitesse",
            ["Score speed"] = "Vitesse du score",
            ["Players can speed up the scoring count"] = "Les joueurs peuvent accélérer le décompte",
            ["Skip score animation"] = "Passer l'animation du score",
            ["Players can jump to the final score"] = "Les joueurs peuvent sauter au score final",
            ["Show the seed"] = "Afficher la seed",
            ["Seed in the pause menu and Run Info"] = "Seed dans le menu pause et les infos de partie",
            ["Hidden in MP"] = "Masquée en MP",
        },
        es = {
            ["Fair play"] = "Juego limpio",
            ["Game speed over 4x"] = "Velocidad de juego mayor a 4x",
            ["Players can pick any game speed"] = "Los jugadores eligen cualquier velocidad",
            ["Score speed"] = "Velocidad de puntuación",
            ["Players can speed up the scoring count"] = "Los jugadores pueden acelerar el conteo",
            ["Skip score animation"] = "Saltar la animación de puntuación",
            ["Players can jump to the final score"] = "Los jugadores pueden saltar a la puntuación final",
            ["Show the seed"] = "Mostrar el código",
            ["Seed in the pause menu and Run Info"] = "Código en el menú de pausa y la info de partida",
            ["Hidden in MP"] = "Oculta en MP",
        },
    }
end

function F.init()
    if F._installed then return end
    F._installed = true
    F.register_strings()
    wrap_ui(function() return rawget(_G, "create_UIBox_options") end, function(f) create_UIBox_options = f end)
    wrap_ui(function() return G.UIDEF.run_seed end, function(f) G.UIDEF.run_seed = f end)
    wrap_func("copy_seed")
    wrap_func("seed_lib_save_current")
    hook_actions()
end

MPFair = F
return F
