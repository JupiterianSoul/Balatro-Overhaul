local Q = QOL
local M = Q.feature("qol_tab", {})

M.SECTIONS = {"Hand", "Scoring", "Shop", "Run", "Shortcuts", "Window", "Multiplayer", "Tavern"}
M.rows = {}

function Q.row(section, build)
    M.rows[#M.rows + 1] = {section = section, build = build}
end

Q.DEFAULTS = Q.DEFAULTS or {}
Q.TOAST_HOLD = 1.4

function Q.default(key, value)
    Q.DEFAULTS[key] = value
end

function Q.fill_defaults()
    local S = G and G.SETTINGS
    if not S then return end
    for k, v in pairs(Q.DEFAULTS) do
        if S[k] == nil then S[k] = v end
    end
end

function Q.on(key)
    local S = G and G.SETTINGS
    if not S then return false end
    local v = S[key]
    if v == nil then v = Q.DEFAULTS[key] end
    return v and true or false
end

function Q.in_run()
    return G and G.STAGES and G.STAGE == G.STAGES.RUN and G.GAME ~= nil or false
end

function Q.solo()
    return Q.in_run() and not G.GAME.multiplayer
end

function Q.toast(text, colour)
    if not (attention_text and G.ROOM_ATTACH) then return end
    attention_text({text = text, scale = 0.6, hold = Q.TOAST_HOLD * (G.SPEEDFACTOR or 1), align = 'cm', offset = {x = 0, y = -2.8}, major = G.ROOM_ATTACH, colour = colour or G.C.WHITE})
end

function Q.save()
    if G and G.save_settings then pcall(function() G:save_settings() end) end
end

function Q.mp_locked(key)
    return (FairLock and FairLock.mp_setting_locked and FairLock.mp_setting_locked(key)) or false
end

function Q.toggle(id, label, info, key, callback, disabled)
    return UIK.toggle{id = id, label = mod_loc(label), info = mod_loc(info), ref_table = G.SETTINGS, ref_value = key,
        disabled = disabled, callback = callback or Q.save}
end

Q.row("Hand", function()
    return Q.toggle('set_drag', "Drag to Select", "Swipe over cards to pick several", 'drag_select')
end)
Q.row("Hand", function()
    if not _G._IS_DESKTOP then return nil end
    local left = G.SETTINGS.drag_select_button == "left"
    return UIK.cycle{id = 'set_drag_button', label = mod_loc("Drag Select Button"),
        info = mod_loc(left and "Start on empty space. Cards can still be moved" or "Hold right click and drag over the cards"),
        options = {mod_loc("Right click"), mod_loc("Left click")}, current = left and 2 or 1,
        callback = function(i) G.SETTINGS.drag_select_button = i == 2 and "left" or "right" Q.save() UIK.refresh() end}
end)
Q.row("Hand", function()
    local S = G.SETTINGS
    return UIK.cycle{id = 'set_hand_sort', label = mod_loc("Default Hand Sort"), info = mod_loc("How your hand is sorted at run start"),
        options = {mod_loc("Rank"), mod_loc("Suit")}, current = S.default_hand_sort == 2 and 2 or 1,
        callback = function(i) G.FUNCS.change_default_hand_sort{to_key = i} end}
end)
Q.row("Scoring", function()
    local lock = Q.mp_locked('score_preview_enabled')
    return UIK.toggle{id = 'set_score_preview', label = mod_loc("Score Preview"), info = lock and mod_loc("Locked by the host") or mod_loc("Shows the score before you play"),
        ref_table = G.SETTINGS, ref_value = 'score_preview_enabled', disabled = lock, callback = Q.save}
end)
Q.row("Shop", function()
    if not (Extras and Extras.set) then return nil end
    return Q.toggle('set_safe_sell', "Safe sell", "Valuable jokers need two presses to sell", 'safe_sell',
        function(v) Extras.set('safe_sell', v) Q.save() end)
end)
Q.row("Multiplayer", function()
    if not (Extras and Extras.set) then return nil end
    return Q.toggle('set_spectate_follow', "Spectate follow", "Spectate follows whoever is in a blind", 'spectate_follow',
        function(v) Extras.set('spectate_follow', v) Q.save() end)
end)

function M.build()
    local items = {}
    for _, section in ipairs(M.SECTIONS) do
        local rows = {}
        for _, r in ipairs(M.rows) do
            if r.section == section then
                local ok, row = pcall(r.build)
                if ok and row then
                    rows[#rows + 1] = row
                elseif not ok then
                    print("[QoL] row " .. section .. ": " .. tostring(row))
                end
            end
        end
        if #rows > 0 then
            items[#items + 1] = UIK.header(mod_loc(section))
            for _, row in ipairs(rows) do items[#items + 1] = row end
        end
    end
    return UIK.flow{id = 'set_qol', items = items, sections = UIK.touch() or nil}
end

function Q.settings_tab()
    Q.fill_defaults()
    return M.build()
end

local function strings()
    if not mod_loc_register then return end
    mod_loc_register{
        fr = {["QoL"] = "QoL", ["Shortcuts"] = "Raccourcis", ["Multiplayer"] = "Multijoueur"},
        es = {["QoL"] = "QoL", ["Shortcuts"] = "Atajos", ["Multiplayer"] = "Multijugador"},
    }
end

function M.init()
    strings()
end

strings()

return M
