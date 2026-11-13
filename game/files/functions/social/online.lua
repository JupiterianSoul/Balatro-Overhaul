local SO = rawget(_G, "social_online") or {}
social_online = SO

local function L(s) return mod_loc and mod_loc(s) or s end
local function now() return love.timer.getTime() end
local function state() return package.loaded["multiplayer.mps_state"] end

SO.RETRY = 20
SO.MAX_RETRY = 300
SO.next_at = SO.next_at or 0
SO.gap = SO.gap or SO.RETRY
SO.view = SO.view or {}

function SO.enabled()
    return not (G and G.SETTINGS and G.SETTINGS.social_stay_online == false)
end

function SO.known()
    local s = G and G.SETTINGS
    if not s then return false end
    local k = s.mp_player_key
    return type(k) == "string" and #k == 24 and s.social_known == true
end

function SO.keep()
    return SO.enabled() and SO.known()
end

local function connected()
    return bom_core and bom_core.is_connected and bom_core.is_connected() or false
end

local function in_room()
    local ok, v = pcall(function()
        if bom_party and bom_party.in_party and bom_party.in_party() then return true end
        return bom_match and bom_match.get_phase and bom_match.PHASE and bom_match.get_phase() ~= bom_match.PHASE.NONE
    end)
    return ok and v and true or false
end

local function mp_menu_open()
    local m = rawget(_G, "mpm_menu")
    return m and m.active and true or false
end

function SO.on_hello()
    SO.gap = SO.RETRY
    if G and G.SETTINGS and not G.SETTINGS.social_known then
        G.SETTINGS.social_known = true
        if G.save_settings then pcall(G.save_settings, G) end
    end
end

local function solo_run()
    if not (G and G.STAGES and G.STAGE == G.STAGES.RUN) then return false end
    if in_room() then return false end
    local ok, v = pcall(function() return bom_playback and bom_playback.active and bom_playback.active() end)
    return not (ok and v)
end

local function report_solo()
    local T = state()
    local B = rawget(_G, "bom_social")
    if not (T and connected() and B and B.S and B.S.hello) then return end
    if solo_run() then
        if T.S.where_sent ~= "solo" then
            T.S.where_sent = "solo"
            bom_core.send({type = "social_status", where = "solo"})
        end
    elseif T.S.where_sent == "solo" and G.STAGE == G.STAGES.MAIN_MENU then
        T.report_where(true)
    end
end

function SO.update()
    report_solo()
    if not SO.keep() then return end
    if not (G and G.STAGES and G.STAGE == G.STAGES.MAIN_MENU) or G.screenwipe then return end
    if connected() or in_room() then return end
    local t = now()
    if t < SO.next_at then return end
    SO.next_at = t + SO.gap
    SO.gap = math.min(SO.MAX_RETRY, SO.gap * 2)
    local B = rawget(_G, "bom_social")
    if B and B.ensure_online then pcall(B.ensure_online) end
end

function SO.toggled(on)
    if on then
        SO.next_at, SO.gap = 0, SO.RETRY
    elseif not mp_menu_open() and not in_room() and connected() and G.STAGE == G.STAGES.MAIN_MENU and not SO.window_open() then
        pcall(bom_core.disconnect)
    end
end

function SO.window_open()
    return G.OVERLAY_MENU and UIK and UIK._win and UIK._win.id == "social" and true or false
end

function SO.tab()
    local t = UIK.touch()
    SO.view.online = SO.enabled()
    SO.view.alerts = not (G.SETTINGS and G.SETTINGS.social_online_alerts == false)
    local more = rawget(_G, "social_more")
    local port = UIK.portrait()
    local w = port and UIK.W - 0.8 or more and UIK.col_w(2) - 0.4 or UIK.col_w(2)
    local rows = {
        UIK.toggle{label = L("Stay online for friends"), info = L("Friends see you and can invite you from the main menu."), w = w,
            ref_table = SO.view, ref_value = "online", id = "social_opt_online", callback = function(v)
                G.SETTINGS.social_stay_online = v and true or false
                if G.save_settings then pcall(G.save_settings, G) end
                SO.toggled(v)
            end},
        UIK.toggle{label = L("Friend online alerts"), info = L("A small card when a friend comes online."), w = w,
            ref_table = SO.view, ref_value = "alerts", id = "social_opt_alerts", callback = function(v)
                G.SETTINGS.social_online_alerts = v and true or false
                if G.save_settings then pcall(G.save_settings, G) end
            end},
    }
    local left = UIK.section(L("Online"), rows, {w = w + 0.4})
    local right = more and UIK.section(L("Privacy"), more.privacy_rows(w), {w = w + 0.4}) or nil
    if right and not port then
        local h = math.max(left.uik_h or 0, right.uik_h or 0)
        left.config.minh, right.config.minh = h, h
    end
    local sections = port and {n = G.UIT.R, config = {align = "tm", padding = 0}, nodes = {
        {n = G.UIT.C, config = {align = "tm", padding = 0}, nodes = {
            left,
            right and UIK.spacer(UIK.GAP or 0.3) or nil,
            right,
        }},
    }} or {n = G.UIT.R, config = {align = "tm", padding = 0}, nodes = {
        {n = G.UIT.C, config = {align = "tm", padding = 0}, nodes = {left}},
        right and {n = G.UIT.C, config = {minw = UIK.GAP or 0.3, padding = 0}, nodes = {}} or nil,
        right and {n = G.UIT.C, config = {align = "tm", padding = 0}, nodes = {right}} or nil,
    }}
    return {n = G.UIT.R, config = {align = "tm", minw = UIK.W, minh = UIK.H - (UIK.TOP or 0) - 0.1, padding = 0}, nodes = {
        {n = G.UIT.C, config = {align = "tm", padding = 0}, nodes = {
            UIK.spacer(t and 0.3 or 0.4),
            sections,
        }},
    }}
end

function SO.init()
    if not mod_loc_register then return end
    mod_loc_register{
        fr = {
            ["Options"] = "Options",
            ["Online"] = "En ligne",
            ["Stay online for friends"] = "Rester en ligne pour les amis",
            ["Friends see you and can invite you from the main menu."] = "Vos amis vous voient et peuvent vous inviter depuis le menu.",
            ["Friend online alerts"] = "Alertes d'amis en ligne",
            ["A small card when a friend comes online."] = "Une petite carte quand un ami se connecte.",
            ["Online, playing solo"] = "En ligne, en partie solo",
        },
        es = {
            ["Options"] = "Opciones",
            ["Online"] = "En línea",
            ["Stay online for friends"] = "Seguir en línea para amigos",
            ["Friends see you and can invite you from the main menu."] = "Tus amigos te ven y pueden invitarte desde el menú.",
            ["Friend online alerts"] = "Avisos de amigos en línea",
            ["A small card when a friend comes online."] = "Una pequeña carta cuando un amigo se conecta.",
            ["Online, playing solo"] = "En línea, en partida solo",
        },
    }
end

return SO
