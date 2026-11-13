local SM = rawget(_G, "social_mg") or {}
social_mg = SM

local function L(s) return mod_loc and mod_loc(s) or s end
local function now() return love.timer.getTime() end
local function touch() return UIK and UIK.touch and UIK.touch() end
local function MG() return rawget(_G, "Minigames") end

SM.ASK_GAP = 20
SM.board = SM.board or nil
SM.view = SM.view or {name = "-", score = ""}
SM.page_rows = SM.page_rows or nil

local function online()
    local B = rawget(_G, "bom_social")
    return bom_core and bom_core.is_connected and bom_core.is_connected() and B and B.S and B.S.hello and true or false
end

local function sent()
    local s = G and G.SETTINGS
    if not s then return {} end
    if type(s.social_mg_sent) ~= "table" then s.social_mg_sent = {} end
    return s.social_mg_sent
end

local function send_best(key, score)
    local mg = MG()
    local def = mg and mg.def and mg.def(key)
    if not def or type(score) ~= "number" or score < 0 or score ~= math.floor(score) then return false end
    if not online() then return false end
    if not bom_core.send({type = "mg_best", game = key, score = score, low = def.lower_better == true or nil}) then return false end
    sent()[key] = score
    if G.save_settings then pcall(G.save_settings, G) end
    return true
end

function SM.on_best(key, score)
    send_best(key, score)
    SM.asked_at = nil
end

function SM.sync()
    local mg = MG()
    if not (mg and mg.GAMES and mg.best) then return end
    local done = sent()
    for _, d in ipairs(mg.GAMES) do
        local b = mg.best(d.key)
        if type(b) == "number" and done[d.key] ~= b then send_best(d.key, b) end
    end
end

function SM.ask(force)
    if not online() then return end
    local t = now()
    if not force and SM.asked_at and t - SM.asked_at < SM.ASK_GAP then return end
    SM.asked_at = t
    bom_core.send({type = "mg_friends"})
end

local function pick_open()
    local mg = MG()
    return mg and mg.pick and mg.pick.is_open and mg.pick.is_open() or false
end

local function board_of(key)
    local g = SM.board and SM.board.games
    return type(g) == "table" and type(g[key]) == "table" and g[key] or nil
end

local function fmt(key, v)
    local mg = MG()
    local d = mg and mg.def and mg.def(key)
    if d and d.format then
        local ok, s = pcall(d.format, v)
        if ok and s then return tostring(s) end
    end
    return tostring(v)
end

function SM.top_friend(key)
    for _, r in ipairs(board_of(key) or {}) do
        if not r.me then return r end
    end
end

function SM.my_rank(key)
    for _, r in ipairs(board_of(key) or {}) do
        if r.me then return tonumber(r.rank) end
    end
end

function SM.fill(key, w)
    local v = SM.view
    local d = bom_kit and bom_kit.dims and bom_kit.dims()
    local scale = touch() and 0.54 or 0.5
    local r = SM.top_friend(key)
    if r then
        v.score = fmt(key, r.score)
        local name = tostring(r.name ~= "" and r.name or "?")
        local room = (w or 2.6) - 0.35 - (UIK.text_w and UIK.text_w(v.score, scale) or 0.8)
        v.name = (bom_kit and bom_kit.fit and bom_kit.fit(name, room, scale, scale) or name) .. " "
    elseif SM.board and (tonumber(SM.board.friends) or 0) == 0 then
        v.name, v.score = L("No friends yet"), ""
    elseif SM.board then
        v.name, v.score = L("No scores yet"), ""
    else
        v.name, v.score = "-", ""
    end
    v.scale = scale
    return v
end

function SM.best_row(d, sz, mine_box)
    local iw = sz.iw or (sz.pw - sz.cw - 0.1)
    local gap = 0.2
    local bw = math.min(sz.aw, (iw - 0.4 - gap) / 2)
    local mine = mine_box(d, {aw = bw, ah = sz.ah, pw = sz.pw, cw = sz.cw})
    local mine_c = mine and mine.nodes and mine.nodes[1]
    SM.last_w = bw
    local v = SM.fill(d.key, bw)
    local friends = {n = G.UIT.C, config = {align = "cm", minw = bw, maxw = bw, minh = sz.ah, r = 0.1, colour = G.C.BLACK, padding = 0.04, emboss = 0.05,
        button = "social_mg_board", hover = true, shadow = true, id = "social_mg_friends"}, nodes = {
        {n = G.UIT.R, config = {align = "cm", padding = 0}, nodes = {
            {n = G.UIT.T, config = {text = L("Friends' best"), scale = touch() and 0.34 or 0.32, colour = UIK.C.muted}},
        }},
        {n = G.UIT.R, config = {align = "cm", padding = 0}, nodes = {
            {n = G.UIT.T, config = {ref_table = v, ref_value = "name", scale = v.scale, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
            {n = G.UIT.T, config = {ref_table = v, ref_value = "score", scale = v.scale, colour = G.C.GOLD, shadow = true}},
        }},
    }}
    return {n = G.UIT.R, config = {align = "cm", padding = 0}, nodes = {
        mine_c or mine,
        {n = G.UIT.C, config = {minw = gap}, nodes = {}},
        friends,
    }}
end

local function board_window(key)
    local mg = MG()
    local d = mg and mg.def and mg.def(key)
    if not d then return end
    local t = touch()
    local w = t and 8.6 or 7.6
    local rh = t and 0.66 or 0.56
    local sc = t and 0.42 or 0.38
    local rows = {}
    local list = board_of(key) or {}
    for _, r in ipairs(list) do
        local col = r.me and G.C.GOLD or G.C.UI.TEXT_LIGHT
        local name = tostring(r.me and L("You") or (r.name ~= "" and r.name) or "?")
        local nw = w - 0.8 - 2.2 - 0.6
        local nm, ns = name, sc
        if bom_kit and bom_kit.fit then nm, ns = bom_kit.fit(name, nw - 0.2, sc) end
        rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", minw = w, minh = rh, r = 0.08, colour = r.me and {1, 1, 1, 0.08} or UIK.C.section, padding = 0.02}, nodes = {
            {n = G.UIT.C, config = {align = "cm", minw = 0.8}, nodes = {UIK.text(tostring(r.rank or "") .. ".", {scale = sc, colour = col})}},
            {n = G.UIT.C, config = {align = "cl", minw = nw}, nodes = {UIK.text(nm, {scale = ns, colour = col, shadow = true})}},
            {n = G.UIT.C, config = {align = "cr", minw = 2.2}, nodes = {UIK.text(fmt(key, r.score), {scale = sc, colour = G.C.GOLD, shadow = true})}},
        }}
        rows[#rows + 1] = UIK.spacer(0.06)
    end
    if #list == 0 then
        local msg = not SM.board and L("Go online to see your friends' scores.")
            or (tonumber(SM.board.friends) or 0) == 0 and L("Add friends to compare scores.") or L("No scores yet")
        rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", minw = w, minh = 1.2}, nodes = {UIK.text(msg, {scale = sc, colour = UIK.C.muted})}}
    end
    G.FUNCS.overlay_menu{definition = UIK.window{
        id = "social_mg_board",
        compact = true,
        w = w + 0.6,
        title = L("FRIENDS' SCORES"),
        tabs = {{key = "board", label = L(d.name), build = function()
            return {n = G.UIT.R, config = {align = "cm", padding = 0}, nodes = {
                {n = G.UIT.C, config = {align = "cm", padding = 0.1}, nodes = {
                    {n = G.UIT.R, config = {align = "cm", minw = w, padding = 0.02}, nodes = {
                        UIK.text(L(d.name), {scale = t and 0.55 or 0.5, colour = G.C.GOLD, shadow = true}),
                    }},
                    {n = G.UIT.R, config = {align = "cm", minw = w, padding = 0.04}, nodes = {
                        UIK.text(L(d.score or "Score"), {scale = t and 0.36 or 0.32, colour = UIK.C.muted}),
                    }},
                    {n = G.UIT.R, config = {align = "cm", padding = 0}, nodes = {{n = G.UIT.C, config = {align = "cm"}, nodes = rows}}},
                }},
            }}
        end}},
        back_func = "open_minigames",
    }}
end
SM.board_window = board_window

local function refresh_pick()
    local mg = MG()
    local P = mg and mg.pick
    if P and P.current then SM.fill(P.current(), SM.last_w) end
end

function SM.on_message(d)
    if type(d) ~= "table" or d.type ~= "mg_friends" then return end
    SM.board = {games = type(d.games) == "table" and d.games or {}, friends = tonumber(d.friends) or 0, at = now()}
    refresh_pick()
end

function SM.update()
    local B = rawget(_G, "bom_social")
    local hello = B and B.S and B.S.hello and online()
    if hello and not SM.synced then
        SM.synced = true
        pcall(SM.sync)
    elseif not hello then
        SM.synced = false
    end
    if pick_open() then
        if not SM.was_open then
            SM.was_open = true
            SM.ask(true)
        else
            SM.ask(false)
        end
    else
        SM.was_open = false
    end
end

local function register_funcs()
    G.FUNCS.social_mg_board = function()
        local mg = MG()
        local P = mg and mg.pick
        if not (P and P.current) then return end
        board_window(P.current())
    end
end

function SM.init()
    register_funcs()
    if bom_events and bom_events.register then
        bom_events.register("mg_friends", function(d)
            SM.on_message(d)
            return true
        end)
    end
    if not mod_loc_register then return end
    mod_loc_register{
        fr = {
            ["Friends' best"] = "Record des amis",
            ["No friends yet"] = "Pas encore d'amis",
            ["No scores yet"] = "Pas encore de score",
            ["FRIENDS' SCORES"] = "SCORES DES AMIS",
            ["You"] = "Vous",
            ["Go online to see your friends' scores."] = "Connectez-vous pour voir les scores de vos amis.",
            ["Add friends to compare scores."] = "Ajoutez des amis pour comparer vos scores.",
        },
        es = {
            ["Friends' best"] = "Récord de amigos",
            ["No friends yet"] = "Aún sin amigos",
            ["No scores yet"] = "Aún sin puntos",
            ["FRIENDS' SCORES"] = "PUNTOS DE AMIGOS",
            ["You"] = "Tú",
            ["Go online to see your friends' scores."] = "Conéctate para ver los puntos de tus amigos.",
            ["Add friends to compare scores."] = "Añade amigos para comparar puntos.",
        },
    }
end

return SM
