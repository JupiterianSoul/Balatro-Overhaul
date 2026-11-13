local SR = rawget(_G, "social_recent") or {}
social_recent = SR

local function L(s) return mod_loc and mod_loc(s) or s end
local function now() return love.timer.getTime() end
local function touch() return UIK and UIK.touch and UIK.touch() end
local function state() return require("multiplayer.mps_state") end
local function friends() return require("multiplayer.mps_friends") end

SR.ASK_GAP = 15

local function online()
    local B = rawget(_G, "bom_social")
    return bom_core and bom_core.is_connected and bom_core.is_connected() and B and B.S and B.S.hello and true or false
end

function SR.ask(force)
    if not online() then return false end
    if not force and SR.asked_at and now() - SR.asked_at < SR.ASK_GAP then return false end
    if not bom_core.send({type = "social_recent"}) then return false end
    SR.asked_at = now()
    if SR.items == nil and not SR.first_ask then SR.first_ask = now() end
    return true
end

local function on_tab()
    local F = friends()
    return F.is_open() and UIK._win and UIK._win._cur == "recent"
end

function SR.on_message(d)
    if type(d) ~= "table" or d.type ~= "social_recent" then return end
    SR.items = type(d.items) == "table" and d.items or {}
    SR.first_ask = nil
    if on_tab() then friends().refresh() end
end

local function when_text(r)
    local T = state()
    local mode = r.ranked and L("Ranked") or (T.mode_name(r.mode) or L("Match"))
    local ago = T.ago(r.at)
    if ago == "" then return mode end
    return mode .. ", " .. ago
end

local function row(r, k)
    local T = state()
    local d = bom_kit.dims()
    local bh = touch() and 0.62 or 0.5
    local rh = touch() and 0.72 or 0.6
    local bw = k.BTN_W
    local label, colour, btn
    if r.friend then
        label, colour = L("Already a friend"), G.C.GREEN
    elseif r.incoming then
        label, colour = L("Wants to be your friend"), G.C.GOLD
        btn = T.btn{label = L("Accept"), button = "social_recent_accept", ref_table = {code = r.code}, colour = G.C.GREEN, w = bw, h = bh}
    elseif r.pending then
        label, colour = L("Request sent"), bom_kit.colour("muted")
    else
        label, colour = r.online and L("Online") or L("Offline"), r.online and G.C.GREEN or bom_kit.colour("muted")
        btn = T.btn{label = L("Add"), button = "social_recent_add", ref_table = {code = r.code}, colour = G.C.GREEN, w = bw, h = bh}
    end
    local nw = 2.8
    local recw = 1.3
    local rest = k.W - 0.16 - 0.3 - nw - d.badge_w - bw - recw - 6 * d.gap - 0.2
    local ww = math.floor(rest * 0.55 * 100) / 100
    local sc = rawget(_G, "social_card")
    local rec = sc and sc.record_text and sc.record_text(r.h2h)
    if UIK.portrait() and k.two_line then
        local inner = k.W - 0.08
        local lw = inner - recw - bw - 3 * d.gap - 0.1
        return k.two_line({
            T.dot(r.online and G.C.GREEN or G.C.UI.TEXT_INACTIVE, {h = rh}),
            bom_kit.name_bar(r.name ~= "" and r.name or "?", {w = nw, h = rh, colour = bom_kit.colour("name_light"), text_colour = bom_kit.colour("dark_text"), shadow = false}),
            bom_badges.slot({name = r.name, rank = r.rank, dev = r.dev}, {h = rh}),
            T.label(when_text(r), inner - 0.3 - nw - d.badge_w - 3 * d.gap - 0.1, {h = rh, colour = G.C.UI.TEXT_LIGHT, scale = bom_kit.note_scale(), align = "cl"}),
        }, {
            T.label(label, lw, {h = bh, colour = colour, scale = bom_kit.note_scale(), align = "cl"}),
            rec and T.label(rec, recw, {h = bh, colour = G.C.GOLD, scale = bom_kit.note_scale()}) or k.empty_btn(recw),
            btn or k.empty_btn(bw),
        }, k.W, {bottom_align = "cl"})
    end
    return bom_kit.row({
        T.dot(r.online and G.C.GREEN or G.C.UI.TEXT_INACTIVE, {h = rh}),
        bom_kit.name_bar(r.name ~= "" and r.name or "?", {w = nw, h = rh, colour = bom_kit.colour("name_light"), text_colour = bom_kit.colour("dark_text"), shadow = false}),
        bom_badges.slot({name = r.name, rank = r.rank, dev = r.dev}, {h = rh}),
        T.label(when_text(r), ww, {h = rh, colour = G.C.UI.TEXT_LIGHT, scale = bom_kit.note_scale()}),
        rec and T.label(rec, recw, {h = rh, colour = G.C.GOLD, scale = bom_kit.note_scale()}) or k.empty_btn(recw),
        T.label(label, rest - ww, {h = rh, colour = colour, scale = bom_kit.note_scale()}),
        btn or k.empty_btn(bw),
    }, {w = k.W, h = rh})
end

function SR.tab()
    local F = friends()
    local k = F.kit
    SR.ask(false)
    local list = SR.items
    local rows = {}
    local muted = bom_kit.colour("muted")
    if not online() then
        rows[1] = k.centre(L("Could not connect."), k.W, {h = 0.8, colour = muted})
    elseif list == nil and SR.first_ask and now() - SR.first_ask > 8 then
        rows[1] = k.centre(L("Recent players are not available yet."), k.W, {h = 0.8, colour = muted})
    elseif list == nil then
        rows[1] = k.centre(L("Loading..."), k.W, {h = 0.8, colour = muted})
    elseif #list == 0 then
        rows[1] = k.centre(L("No one yet. Players you meet in a match show up here."), k.W, {h = 0.8})
    else
        for _, r in ipairs(k.slice(list, "recent")) do rows[#rows + 1] = row(r, k) end
    end
    local hint_h = 0.5
    return k.block({
        k.centre(L("Players from your last matches"), k.W, {h = hint_h, colour = muted, scale = bom_kit.note_scale()}),
        k.block(rows, k.W, k.body_h() - 1.4 - hint_h),
        k.pager("recent", list and #list or 0, k.W),
        k.note_row(k.W),
    }, k.W, k.body_h())
end

local function mark(code, fn)
    for _, r in ipairs(SR.items or {}) do
        if r.code == code then fn(r) end
    end
end

local function ref(e) return e and e.config and e.config.ref_table or {} end

function SR.init()
    G.FUNCS.social_recent_add = function(e)
        local code = ref(e).code
        if not code then return end
        local T = state()
        T.send({type = "social_add", code = code})
        mark(code, function(r) r.pending = true end)
        friends().refresh()
    end
    G.FUNCS.social_recent_accept = function(e)
        local code = ref(e).code
        if not code then return end
        local T = state()
        T.send({type = "social_accept", code = code})
        mark(code, function(r) r.friend, r.incoming, r.pending = true, nil, nil end)
        friends().refresh()
    end
    if bom_events and bom_events.register then
        bom_events.register("social_recent", function(d)
            SR.on_message(d)
            return true
        end)
    end
    if not mod_loc_register then return end
    mod_loc_register{
        fr = {
            ["Recent"] = "Récents",
            ["Players from your last matches"] = "Les joueurs de vos derniers matchs",
            ["No one yet. Players you meet in a match show up here."] = "Personne pour l'instant. Les joueurs que vous affrontez apparaissent ici.",
            ["Match"] = "Match",
            ["Recent players are not available yet."] = "Les joueurs récents ne sont pas encore disponibles.",
        },
        es = {
            ["Recent"] = "Recientes",
            ["Players from your last matches"] = "Jugadores de tus últimas partidas",
            ["No one yet. Players you meet in a match show up here."] = "Nadie todavía. Aquí aparecen los jugadores con los que juegas.",
            ["Match"] = "Partida",
            ["Recent players are not available yet."] = "Los jugadores recientes aún no están disponibles.",
        },
    }
end

return SR
