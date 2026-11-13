local Q = QOL
local M = Q.feature("touch_hint", {})

M.STAY = 6
M.MIN_SHOW = 0.6

local function L(s) return mod_loc and mod_loc(s) or s end

local function strings()
    if not mod_loc_register then return end
    mod_loc_register{
        fr = {
            ["Swipe over cards to select several."] = "Glissez sur les cartes pour en choisir plusieurs.",
            ["Hold, then drag to move one."] = "Maintenez, puis glissez pour en déplacer une.",
            ["Swipe over cards to pick several."] = "Glissez sur les cartes pour en choisir plusieurs.",
        },
        es = {
            ["Swipe over cards to select several."] = "Desliza sobre las cartas para elegir varias.",
            ["Hold, then drag to move one."] = "Mantén pulsado y arrastra para mover una.",
            ["Swipe over cards to pick several."] = "Desliza sobre las cartas para elegir varias.",
        },
    }
end

function M.touch()
    return UIK and UIK.thumb and UIK.thumb() or false
end

function M.due()
    if not (G and G.SETTINGS and G.STAGES and G.STATES) then return false end
    if G.SETTINGS.touch_hint_seen or M.box then return false end
    if not M.touch() then return false end
    if G.STAGE ~= G.STAGES.RUN or G.STATE ~= G.STATES.SELECTING_HAND then return false end
    if G.OVERLAY_MENU or G.OVERLAY_TUTORIAL or G.SETTINGS.paused then return false end
    if bom_playback and bom_playback.active and bom_playback.active() then return false end
    if not (G.hand and G.hand.T and G.hand.cards and #G.hand.cards > 0) then return false end
    return not (G.CONTROLLER and G.CONTROLLER.locked)
end

local function line(str, scale, colour)
    return {n = G.UIT.R, config = {align = "cm", padding = 0.03}, nodes = {
        {n = G.UIT.T, config = {text = str, scale = scale, colour = colour or G.C.WHITE, shadow = true}},
    }}
end

function M.def()
    local k = UIK.portrait() and 1.45 or 1
    local s = 0.42 * k
    return {n = G.UIT.ROOT, config = {align = "cm", r = 0.12, padding = 0.06, colour = G.C.UI.TRANSPARENT_DARK}, nodes = {
        {n = G.UIT.R, config = {align = "cm", r = 0.1, padding = 0.16 * k, colour = G.C.BLACK, emboss = 0.05,
            button = "qol_touch_hint_close", hover = true}, nodes = {
            {n = G.UIT.C, config = {align = "cm"}, nodes = {
                line(L("Swipe over cards to select several."), s, G.C.WHITE),
                line(L("Hold, then drag to move one."), s, G.C.GOLD),
            }},
        }},
    }}
end

function M.place()
    local b = M.box
    if not (b and G.hand and G.hand.T) then return end
    b:set_alignment({major = G.hand, type = "tm", bond = "Weak", offset = {x = 0, y = -0.25}})
end

function M.show()
    G.SETTINGS.touch_hint_seen = true
    if G.save_settings then pcall(function() G:save_settings() end) end
    M.box = UIBox{definition = M.def(), config = {align = "tm", offset = {x = 0, y = -0.25}, major = G.hand, bond = "Weak", instance_type = "ALERT"}}
    M.shown_at = love.timer.getTime()
    M.port = UIK.portrait()
end

function M.hide()
    if M.box then pcall(function() M.box:remove() end) end
    M.box = nil
end

local function pressed()
    if love.mouse and love.mouse.isDown and love.mouse.isDown(1) then return true end
    if love.touch and love.touch.getTouches then return #love.touch.getTouches() > 0 end
    return false
end

function M.tick()
    if M.box then
        local t = love.timer.getTime() - (M.shown_at or 0)
        local gone = G.STAGE ~= G.STAGES.RUN or G.STATE ~= G.STATES.SELECTING_HAND or G.OVERLAY_MENU
        if gone or t > M.STAY or (t > M.MIN_SHOW and pressed()) then return M.hide() end
        if M.port ~= UIK.portrait() then
            M.hide()
            M.box = UIBox{definition = M.def(), config = {align = "tm", offset = {x = 0, y = -0.25}, major = G.hand, bond = "Weak", instance_type = "ALERT"}}
            M.port = UIK.portrait()
        end
        return
    end
    if M.due() then M.show() end
end

local TUT_LINE = "Swipe over cards to pick several."
M.marked = setmetatable({}, {__mode = "k"})

function M.tutorial_line()
    local misc = G and G.localization and G.localization.misc
    local raw = misc and misc.tutorial and misc.tutorial.fh_5_touch
    local parsed = G.localization.tutorial_parsed and G.localization.tutorial_parsed.fh_5_touch
    if type(raw) ~= "table" or type(parsed) ~= "table" or M.marked[raw] then return end
    local str = L(TUT_LINE)
    raw[#raw + 1] = str
    M.marked[raw] = true
    if loc_parse_string then parsed[#parsed + 1] = loc_parse_string(str) end
end

function M.init()
    strings()
    G.FUNCS.qol_touch_hint_close = function() M.hide() end
    pcall(M.tutorial_line)
    if not M._loc_wrapped and init_localization then
        M._loc_wrapped = true
        local base = init_localization
        init_localization = function(...)
            local r = base(...)
            pcall(M.tutorial_line)
            return r
        end
    end
    if not M._tick_wrapped and love and love.update then
        M._tick_wrapped = true
        local prev_update = love.update
        love.update = function(dt, ...)
            if prev_update then prev_update(dt, ...) end
            pcall(M.tick)
        end
    end
end

strings()

return M
