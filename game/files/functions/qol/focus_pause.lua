local Q = QOL
local M = Q.feature("focus_pause", {})

Q.default("qol_focus_pause", true)

function M.should_pause()
    if not (Q.on("qol_focus_pause") and Q.solo()) then return false end
    if G.OVERLAY_MENU or G.SETTINGS.paused then return false end
    if G.STATE == G.STATES.GAME_OVER then return false end
    if bom_playback and bom_playback.active and bom_playback.active() then return false end
    if not (G.FUNCS and G.FUNCS.options) then return false end
    return true
end

function M.focus(focused)
    if focused then return false end
    if not M.should_pause() then return false end
    G.FUNCS.options()
    return true
end

Q.row("Run", function()
    return Q.toggle('set_qol_focus_pause', "Pause when away", "Pauses a solo run when you tab out", 'qol_focus_pause')
end)

local function strings()
    if not mod_loc_register then return end
    mod_loc_register{
        fr = {["Pause when away"] = "Pause en arrière-plan", ["Pauses a solo run when you tab out"] = "Met la partie solo en pause si vous changez de fenêtre"},
        es = {["Pause when away"] = "Pausa al salir", ["Pauses a solo run when you tab out"] = "Pausa la partida en solitario si cambias de ventana"},
    }
end

function M.init()
    strings()
    if M._wrapped then return end
    M._wrapped = true
    local prev = love.focus
    love.focus = function(focused, ...)
        if prev then prev(focused, ...) end
        local ok, err = pcall(M.focus, focused)
        if not ok then print("[QoL] focus pause: " .. tostring(err)) end
    end
end

strings()

return M
