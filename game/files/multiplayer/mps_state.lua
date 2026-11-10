local T = {}

local function L(s) return mod_loc and mod_loc(s) or s end
T.L = L

T.S = {
    search = {input = {q = ""}, sent = "", results = nil, status = nil, changed_at = 0, last = ""},
    dms = {}, dm_sel = nil, dm_input = {text = ""},
    notify = {items = {}, unread = 0, loaded = false},
    chat = {enabled = nil, allowed = nil, year = 2000},
    lobby = {key = nil, lines = {}, input = {text = ""}, unread = 0, label = "", mutes = {}},
    mutes = {},
    note = nil, note_bad = false,
    where_sent = nil, menu_active = false, pending = {},
}
local S = T.S

local LISTENERS = {}

function T.listen(fn)
    LISTENERS[#LISTENERS + 1] = fn
end

function T.changed(what)
    for _, fn in ipairs(LISTENERS) do pcall(fn, what) end
end

function T.social()
    return rawget(_G, "bom_social")
end

function T.friends()
    local B = T.social()
    return B and B.S and B.S.friends or {}
end

function T.requests()
    local B = T.social()
    return B and B.S and B.S.requests or {}
end

function T.sent()
    local B = T.social()
    return B and B.S and B.S.sent or {}
end

function T.my_code()
    local B = T.social()
    return B and B.S and B.S.code or nil
end

function T.my_name()
    local p = G and G.PROFILES and G.SETTINGS and G.PROFILES[G.SETTINGS.profile]
    return p and p.name or nil
end

function T.connected()
    return bom_core and bom_core.is_connected and bom_core.is_connected() or false
end

function T.send(msg)
    if not T.connected() then
        S.note, S.note_bad = L("Could not connect."), true
        return false
    end
    return bom_core.send(msg)
end

function T.note(text, bad)
    S.note, S.note_bad = text, bad and true or false
end

function T.now_ms()
    return os.time() * 1000
end

function T.ago(ms)
    ms = tonumber(ms)
    if not ms or ms <= 0 then return "" end
    local s = math.max(0, math.floor((T.now_ms() - ms) / 1000))
    local n, unit
    if s < 60 then n, unit = s, "sec"
    elseif s < 3600 then n, unit = math.floor(s / 60), "min"
    elseif s < 86400 then n, unit = math.floor(s / 3600), "h"
    else n, unit = math.floor(s / 86400), (math.floor(s / 86400) == 1 and "day" or "days") end
    return (L("{n} " .. unit .. " ago"):gsub("{n}", tostring(n)))
end

function T.mode_name(mode)
    if type(mode) ~= "string" or mode == "" then return nil end
    local name
    local bp = rawget(_G, "bom_party")
    if bp and type(bp.KIND_NAME) == "table" and bp.KIND_NAME[mode] then return L(bp.KIND_NAME[mode]) end
    pcall(function()
        local br = rawget(_G, "bom_browse")
        if br and br.mode_name then name = br.mode_name(mode) end
    end)
    return name or (mode:sub(1, 1):upper() .. mode:sub(2))
end

function T.fill(fmt, vars)
    return (L(fmt):gsub("{(%w+)}", function(k) return tostring(vars[k] ~= nil and vars[k] or "") end))
end

function T.is_online(f)
    if f.online ~= nil then return f.online == true end
    return f.where ~= nil and f.where ~= "offline"
end

function T.where_of(f)
    local st = type(f.status) == "table" and f.status or nil
    if st and type(st.where) == "string" then return st.where end
    return f.where or "offline"
end

function T.status_text(f)
    local st = type(f.status) == "table" and f.status or {}
    local where = T.where_of(f)
    if not T.is_online(f) or where == "offline" then
        local ago = T.ago(f.last_seen)
        if ago == "" then return L("Offline") end
        return T.fill("Offline, last seen {ago}", {ago = ago})
    end
    local mode = T.mode_name(st.mode)
    if where == "match" then
        local parts = {L("Online")}
        local opp = type(st.opponents) == "table" and st.opponents or {}
        if mode and #opp > 0 then
            local names = {}
            for i = 1, math.min(#opp, 2) do names[#names + 1] = tostring(opp[i]) end
            local vs = table.concat(names, ", ") .. (#opp > 2 and (" +" .. tostring(#opp - 2)) or "")
            parts[#parts + 1] = T.fill("{mode} vs {names}", {mode = mode, names = vs})
        elseif mode then
            parts[#parts + 1] = mode
        else
            parts[#parts + 1] = L("in a match")
        end
        if tonumber(st.ante) then parts[#parts + 1] = T.fill("Ante {n}", {n = math.floor(tonumber(st.ante))}) end
        return table.concat(parts, ", ")
    elseif where == "lobby" then
        if mode then return T.fill("Online, in a {mode} lobby", {mode = mode}) end
        return L("Online, in a lobby")
    elseif where == "browsing" then
        return L("Online, browsing rooms")
    elseif where == "spectating" then
        return L("Online, spectating")
    elseif where == "solo" then
        return L("Online, playing solo")
    end
    return L("Online, in the menu")
end

function T.status_colour(f)
    if not T.is_online(f) then return G.C.UI.TEXT_INACTIVE end
    local w = T.where_of(f)
    if w == "match" then return G.C.ORANGE end
    if w == "lobby" then return G.C.GOLD end
    return G.C.GREEN
end

function T.sort_friends(list)
    local sc = rawget(_G, "social_card")
    table.sort(list, function(a, b)
        if sc and sc.is_fav then
            local fa, fb = sc.is_fav(a.code), sc.is_fav(b.code)
            if fa ~= fb then return fa end
        end
        local oa, ob = T.is_online(a), T.is_online(b)
        if oa ~= ob then return oa end
        if not oa and (a.last_seen or 0) ~= (b.last_seen or 0) then return (a.last_seen or 0) > (b.last_seen or 0) end
        return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
    end)
    return list
end

function T.friend(code)
    for _, f in ipairs(T.friends()) do
        if f.code == code then return f end
    end
    return nil
end

function T.dm_unread_total()
    local n = 0
    for _, f in ipairs(T.friends()) do n = n + (tonumber(f.unread) or 0) end
    return n
end

function T.d()
    return bom_kit.dims()
end

function T.btn(o)
    local d = T.d()
    local w, h = o.w or 1.6, o.h or (UIK.touch() and 0.62 or 0.5)
    local scale = o.scale or d.small
    local s, sc = bom_kit.fit(o.label or "", w - 0.14, scale, d.min_scale)
    local disabled = o.disabled
    return {n = G.UIT.C, config = {align = "cm", minw = w, maxw = w, minh = h, r = 0.1, padding = 0,
        colour = disabled and G.C.UI.BACKGROUND_INACTIVE or (o.colour or G.C.BLUE),
        button = (not disabled) and o.button or nil, ref_table = o.ref_table, hover = not disabled, shadow = true, emboss = 0.04, id = o.id}, nodes = {
        {n = G.UIT.T, config = {text = s, scale = sc, colour = disabled and G.C.UI.TEXT_INACTIVE or (o.text_colour or G.C.UI.TEXT_LIGHT), shadow = true}},
    }}
end

function T.dot(colour, o)
    o = o or {}
    local w = o.w or 0.3
    local size = o.size or 0.16
    return bom_kit.cell({
        {n = G.UIT.C, config = {align = "cm", minw = size, maxw = size, minh = size, r = size / 2, colour = colour or G.C.CLEAR}, nodes = {}},
    }, {w = w, h = o.h})
end

function T.label(str, w, o)
    o = o or {}
    local d = T.d()
    local s, sc = bom_kit.fit(str, w - 0.1, o.scale or d.scale, o.min_scale)
    return bom_kit.cell({bom_kit.text(s, {scale = sc, colour = o.colour})}, {w = w, h = o.h, align = o.align})
end

function T.wrap(str, maxw, scale)
    str = tostring(str or "")
    local lines, cur = {}, ""
    for word in str:gmatch("%S+") do
        local try = cur == "" and word or (cur .. " " .. word)
        if bom_kit.text_w(try, scale) <= maxw then
            cur = try
        else
            if cur ~= "" then lines[#lines + 1] = cur end
            while bom_kit.text_w(word, scale) > maxw and #word > 1 do
                local cut = #word
                while cut > 1 and bom_kit.text_w(word:sub(1, cut), scale) > maxw do cut = cut - 1 end
                lines[#lines + 1] = word:sub(1, cut)
                word = word:sub(cut + 1)
            end
            cur = word
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    if #lines == 0 then lines[1] = "" end
    return lines
end

function T.swap(id, build)
    if not G.OVERLAY_MENU then return false end
    local slot = G.OVERLAY_MENU:get_UIE_by_ID(id)
    if not slot then return false end
    local ok, def = pcall(build)
    if not ok or not def then return false end
    if slot.config.object then pcall(function() slot.config.object:remove() end) end
    slot.config.object = UIBox{definition = {n = G.UIT.ROOT, config = {align = "cm", colour = G.C.CLEAR, padding = 0}, nodes = {def}},
        config = {offset = {x = 0, y = 0}, parent = slot, type = "cm"}}
    slot.UIBox:recalculate()
    return true
end

function T.slot(id, build)
    local ok, def = pcall(build)
    if not ok or not def then def = {n = G.UIT.R, config = {}, nodes = {}} end
    return {n = G.UIT.O, config = {id = id, object = UIBox{definition = {n = G.UIT.ROOT, config = {align = "cm", colour = G.C.CLEAR, padding = 0}, nodes = {def}},
        config = {offset = {x = 0, y = 0}}}}}
end

function T.typing()
    return G.CONTROLLER and G.CONTROLLER.text_input_hook ~= nil
end

function T.later(what)
    S.pending[what] = true
end

function T.lobby_key()
    local key
    pcall(function()
        if bom_party and bom_party.in_party and bom_party.in_party() and bom_party.S and bom_party.S.code then
            key = "p:" .. tostring(bom_party.S.code)
        end
    end)
    if key then return key end
    pcall(function()
        local st = bom_match and bom_match.get_state and bom_match.get_state()
        if st and st.room_code then key = "r:" .. tostring(st.room_code) end
    end)
    return key
end

function T.set_bell()
    local n = tonumber(S.notify.unread) or 0
    pcall(function()
        local menu = rawget(_G, "mpm_menu")
        if menu and menu.set_unread then menu.set_unread(n) end
    end)
end

local function apply_presence(d)
    local f = T.friend(d.code)
    if not f then return end
    if d.online ~= nil then f.online = d.online == true end
    if type(d.status) == "table" then
        f.status = d.status
        local w = d.status.where
        f.where = (w == "lobby" or w == "match" or w == "offline") and w or (f.online and "menu" or "offline")
    end
    if d.last_seen then f.last_seen = d.last_seen end
    if d.rank ~= nil then f.rank = d.rank end
    T.sort_friends(T.friends())
end

local function dm_other(d)
    local me = T.my_code()
    if d.from == me then return d.to end
    return d.from
end

local function add_dm(code, item)
    local conv = S.dms[code]
    if not conv then
        conv = {items = {}, loaded = false}
        S.dms[code] = conv
    end
    for _, it in ipairs(conv.items) do
        if it.id == item.id then return end
    end
    conv.items[#conv.items + 1] = item
    while #conv.items > 100 do table.remove(conv.items, 1) end
    conv.last = item.at
end

local function upsert_notify(item)
    if type(item) ~= "table" then return end
    local list = S.notify.items
    for i = #list, 1, -1 do
        if list[i].id == item.id then table.remove(list, i) end
    end
    table.insert(list, 1, item)
end

T.REASONS = {
    blocked = "That message was blocked.", rate_limited = "Too fast, wait a moment.", too_long = "That message is too long.",
    not_allowed = "Chat is not available for you.", not_opted_in = "Turn on chat first.", muted = "You can't send messages right now.",
    empty = "Type a message first.", not_friend = "Not on your friends list.", recipient_off = "Your friend has chat turned off.",
    no_lobby = "You are not in a lobby.", age_needed = "Enter your birth year.", bad_year = "That year is not valid.",
    unknown_player = "Player not found.", self = "That is you.", full = "Your mute list is full.",
    unknown_message = "That message can't be reported.", bad_request = "Something went wrong.",
    too_short = "Type at least 2 letters.", slow_down = "Too fast, try again in a moment.",
}

local H = {}

H.social_search_result = function(d)
    local sr = S.search
    sr.results = type(d.results) == "table" and d.results or {}
    sr.status = #sr.results == 0 and "none" or nil
    T.changed("search")
    return true
end

H.social_presence = function(d)
    local st = rawget(_G, "social_toasts")
    if st and st.on_presence then pcall(st.on_presence, d, T.friend(d.code)) end
    apply_presence(d)
    T.changed("friends")
    return true
end

H.chat_state = function(d)
    S.chat.enabled = d.enabled == true
    if d.allowed == nil or d.allowed == false or d.allowed == true then S.chat.allowed = d.allowed end
    T.changed("chat")
    return true
end

H.chat_dm = function(d)
    local code = dm_other(d)
    if not code then return true end
    add_dm(code, {id = d.id, from = d.from, at = d.at, text = tostring(d.text or "")})
    local SE = rawget(_G, "social_chat_emotes")
    if SE and SE.on_dm then pcall(SE.on_dm, code, d) end
    local SX = rawget(_G, "social_more")
    if SX and SX.on_dm then pcall(SX.on_dm, d) end
    if d.from ~= T.my_code() then
        local f = T.friend(code)
        if S.dm_sel == code and S.dm_open then
            T.send({type = "chat_dm_read", with = code})
        elseif f then
            f.unread = (tonumber(f.unread) or 0) + 1
        end
    end
    T.changed("dm")
    return true
end

H.chat_dm_history = function(d)
    local code = d.with
    if not code then return true end
    local conv = S.dms[code] or {items = {}}
    local seen, list = {}, {}
    for _, it in ipairs(type(d.items) == "table" and d.items or {}) do
        if it.id and not seen[it.id] then seen[it.id] = true; list[#list + 1] = {id = it.id, from = it.from, at = it.at, text = tostring(it.text or "")} end
    end
    for _, it in ipairs(conv.items) do
        if it.id and not seen[it.id] then seen[it.id] = true; list[#list + 1] = it end
    end
    table.sort(list, function(a, b) return (a.at or 0) < (b.at or 0) end)
    conv.items, conv.loaded = list, true
    conv.last = list[#list] and list[#list].at or conv.last
    S.dms[code] = conv
    T.changed("dm")
    return true
end

H.chat_lobby = function(d)
    local key = T.lobby_key()
    local lb = S.lobby
    if key ~= lb.key then
        lb.key, lb.lines, lb.unread, lb.mutes = key, {}, 0, {}
    end
    local BL = rawget(_G, "social_bot_lines")
    local text = BL and BL.text and BL.text(d) or tostring(d.text or "")
    lb.lines[#lb.lines + 1] = {id = d.id, pid = d.pid, name = tostring(d.name or ""), at = d.at, text = text, bot = d.bot == true or nil}
    while #lb.lines > 60 do table.remove(lb.lines, 1) end
    if not S.lobby_open and tostring(d.name or "") ~= tostring(T.my_name() or "") then lb.unread = lb.unread + 1 end
    T.lobby_label()
    T.changed("lobby")
    return true
end

H.chat_result = function(d)
    if d.ok then
        if d.action == "mute" and d.code then S.mutes[d.code] = true
        elseif d.action == "unmute" and d.code then S.mutes[d.code] = nil
        elseif d.action == "report" then T.note(L("Report sent. Thank you."), false)
        elseif d.action == "send" then S.note = nil end
    else
        if d.action == "mute" or d.action == "unmute" then
            S.lobby.mutes = {}
        end
        T.note(L(T.REASONS[d.reason] or "Something went wrong."), true)
    end
    T.changed("chat_result")
    return true
end

H.chat_mute_list = function(d)
    S.mutes = {}
    for _, it in ipairs(type(d.items) == "table" and d.items or {}) do
        if it.code then S.mutes[it.code] = true end
    end
    T.changed("mutes")
    return true
end

H.notify_list = function(d)
    S.notify.items = type(d.items) == "table" and d.items or {}
    S.notify.unread = tonumber(d.unread) or 0
    S.notify.loaded = true
    T.set_bell()
    T.changed("notify")
    return true
end

H.notify_new = function(d)
    upsert_notify(d.item)
    if d.unread ~= nil then
        S.notify.unread = tonumber(d.unread) or 0
    else
        S.notify.unread = (tonumber(S.notify.unread) or 0) + 1
    end
    T.set_bell()
    T.changed("notify")
    return true
end

function T.lobby_label()
    local n = S.lobby.unread
    S.lobby.label = n > 0 and (L("Chat") .. " (" .. (n > 9 and "9+" or tostring(n)) .. ")") or L("Chat")
end

function T.on_social(d)
    if d.type == "social_list" then
        local f = T.friends()
        local sx = rawget(_G, "social_more")
        if sx and sx.apply_nicks then pcall(sx.apply_nicks, f) end
        T.sort_friends(f)
        T.changed("friends")
    elseif d.type == "social_me" then
        T.changed("me")
    elseif d.type == "social_result" then
        T.changed("social_result")
    end
end

local function current_where()
    local where = "menu"
    pcall(function()
        local br = rawget(_G, "bom_browse")
        if br and br.is_open and br.is_open() then where = "browsing" end
        local sp = rawget(_G, "bom_spectate")
        if sp and sp.is_open and sp.is_open() then where = "spectating" end
    end)
    return where
end

function T.report_where(force)
    local B = T.social()
    if not (T.connected() and B and B.S and B.S.hello) then return end
    if not (G and G.STAGES and G.STAGE == G.STAGES.MAIN_MENU) then return end
    if bom_match and bom_match.get_phase and bom_match.PHASE and bom_match.get_phase() ~= bom_match.PHASE.NONE then return end
    local w = current_where()
    if force or w ~= S.where_sent then
        S.where_sent = w
        bom_core.send({type = "social_status", where = w})
    end
end

function T.on_menu(active)
    S.menu_active = active and true or false
    S.where_sent = nil
    if active then
        local B = T.social()
        if B and B.ensure_online then B.ensure_online() end
        T.report_where(true)
    end
end

function T.on_hello()
    S.where_sent = nil
    T.report_where(true)
    if T.connected() then bom_core.send({type = "chat_mute_list"}) end
end

local tick_at = 0
function T.tick()
    local now = love.timer.getTime()
    if now < tick_at then return end
    tick_at = now + 0.25
    local key = T.lobby_key()
    if key ~= S.lobby.key and key ~= nil then
        S.lobby.key, S.lobby.lines, S.lobby.unread, S.lobby.mutes = key, {}, 0, {}
        T.lobby_label()
    end
    T.report_where(false)
    if not T.typing() then
        for what in pairs(S.pending) do
            S.pending[what] = nil
            T.changed(what)
        end
    end
end

local STRINGS = {
    fr = {
        ["Could not connect."] = "Connexion impossible.",
        ["{n} sec ago"] = "il y a {n} s", ["{n} min ago"] = "il y a {n} min", ["{n} h ago"] = "il y a {n} h",
        ["{n} day ago"] = "il y a {n} jour", ["{n} days ago"] = "il y a {n} jours",
        ["Offline"] = "Hors ligne", ["Online"] = "En ligne", ["Offline, last seen {ago}"] = "Hors ligne, vu {ago}",
        ["{mode} vs {names}"] = "{mode} contre {names}", ["in a match"] = "en match", ["Ante {n}"] = "Mise initiale {n}",
        ["Online, in a {mode} lobby"] = "En ligne, dans un salon {mode}", ["Online, in a lobby"] = "En ligne, dans un salon",
        ["Online, browsing rooms"] = "En ligne, parcourt les salles", ["Online, spectating"] = "En ligne, regarde un match",
        ["Online, in the menu"] = "En ligne, dans le menu",
        ["That message was blocked."] = "Ce message a été bloqué.", ["Too fast, wait a moment."] = "Trop rapide, patientez un instant.",
        ["That message is too long."] = "Ce message est trop long.", ["Chat is not available for you."] = "Le chat n'est pas disponible pour vous.",
        ["Turn on chat first."] = "Activez d'abord le chat.", ["You can't send messages right now."] = "Vous ne pouvez pas envoyer de message pour le moment.",
        ["Type a message first."] = "Écrivez d'abord un message.", ["Not on your friends list."] = "Pas dans votre liste d'amis.",
        ["Your friend has chat turned off."] = "Votre ami a désactivé le chat.", ["You are not in a lobby."] = "Vous n'êtes pas dans un salon.",
        ["Enter your birth year."] = "Indiquez votre année de naissance.", ["That year is not valid."] = "Cette année n'est pas valide.",
        ["Player not found."] = "Joueur introuvable.", ["That is you."] = "C'est vous.", ["Your mute list is full."] = "Votre liste de joueurs en sourdine est pleine.",
        ["That message can't be reported."] = "Ce message ne peut pas être signalé.", ["Something went wrong."] = "Un problème est survenu.",
        ["Type at least 2 letters."] = "Tapez au moins 2 lettres.", ["Too fast, try again in a moment."] = "Trop rapide, réessayez dans un instant.",
        ["Report sent. Thank you."] = "Signalement envoyé. Merci.", ["Chat"] = "Chat",
    },
    es = {
        ["Could not connect."] = "No se pudo conectar.",
        ["{n} sec ago"] = "hace {n} s", ["{n} min ago"] = "hace {n} min", ["{n} h ago"] = "hace {n} h",
        ["{n} day ago"] = "hace {n} día", ["{n} days ago"] = "hace {n} días",
        ["Offline"] = "Desconectado", ["Online"] = "En línea", ["Offline, last seen {ago}"] = "Desconectado, visto {ago}",
        ["{mode} vs {names}"] = "{mode} contra {names}", ["in a match"] = "en partida", ["Ante {n}"] = "Apuesta inicial {n}",
        ["Online, in a {mode} lobby"] = "En línea, en una sala {mode}", ["Online, in a lobby"] = "En línea, en una sala",
        ["Online, browsing rooms"] = "En línea, buscando salas", ["Online, spectating"] = "En línea, mirando una partida",
        ["Online, in the menu"] = "En línea, en el menú",
        ["That message was blocked."] = "Ese mensaje fue bloqueado.", ["Too fast, wait a moment."] = "Demasiado rápido, espera un momento.",
        ["That message is too long."] = "Ese mensaje es demasiado largo.", ["Chat is not available for you."] = "El chat no está disponible para ti.",
        ["Turn on chat first."] = "Activa primero el chat.", ["You can't send messages right now."] = "No puedes enviar mensajes ahora.",
        ["Type a message first."] = "Escribe primero un mensaje.", ["Not on your friends list."] = "No está en tu lista de amigos.",
        ["Your friend has chat turned off."] = "Tu amigo tiene el chat desactivado.", ["You are not in a lobby."] = "No estás en una sala.",
        ["Enter your birth year."] = "Indica tu año de nacimiento.", ["That year is not valid."] = "Ese año no es válido.",
        ["Player not found."] = "Jugador no encontrado.", ["That is you."] = "Ese eres tú.", ["Your mute list is full."] = "Tu lista de silenciados está llena.",
        ["That message can't be reported."] = "Ese mensaje no se puede denunciar.", ["Something went wrong."] = "Algo salió mal.",
        ["Type at least 2 letters."] = "Escribe al menos 2 letras.", ["Too fast, try again in a moment."] = "Demasiado rápido, inténtalo en un momento.",
        ["Report sent. Thank you."] = "Denuncia enviada. Gracias.", ["Chat"] = "Chat",
    },
}

function T.init()
    if mod_loc_register then mod_loc_register(STRINGS) end
    T.lobby_label()
    if bom_events and bom_events.register then
        for t, fn in pairs(H) do bom_events.register(t, fn) end
    end
end

return T
