local Q = QOL
local M = Q.feature("hotkeys", {})

M.SPEEDS = {0.5, 1, 2, 4, 6, 8, 10, 12, 16, 20}
M.KEYS = {f = "speed", m = "mute", n = "music"}

Q.default("qol_speed_key", true)
Q.default("qol_mute_keys", true)

local function kp()
    return Extras and Extras.modules and Extras.modules.keyboard_play
end

function M.taken(key)
    local k = kp()
    if not (k and k.enabled and k.enabled() and k.action_for) then return false end
    local ok, sc = pcall(love.keyboard.getScancodeFromKey, key)
    return k.action_for(ok and sc or key) ~= nil
end

function M.speed_allowed()
    if not Q.solo() then return false end
    if bom_match and bom_match.speed_rules_on and bom_match.speed_rules_on() then return false end
    if bom_playback and bom_playback.active and bom_playback.active() then return false end
    return true
end

local function fmt(v)
    return (v == math.floor(v) and tostring(math.floor(v)) or tostring(v)) .. "x"
end

function M.cycle_speed(back)
    local S = G.SETTINGS
    local cur = S.GAMESPEED or 1
    local list, idx = M.SPEEDS, nil
    if back then
        idx = 1
        for i, v in ipairs(list) do
            if v < cur - 1e-6 then idx = i end
        end
    else
        idx = 2
        for i, v in ipairs(list) do
            if v > cur + 1e-6 then idx = i break end
        end
    end
    G.FUNCS.change_gamespeed{to_key = idx, to_val = list[idx]}
    Q.save()
    Q.toast(mod_loc("Game speed") .. " " .. fmt(list[idx]))
    return list[idx]
end

function M.toggle_volume(field, prev, on_text, off_text)
    local snd = G.SETTINGS.SOUND
    if not snd then return end
    if (snd[field] or 0) > 0 then
        G.SETTINGS[prev] = snd[field]
        snd[field] = 0
        Q.toast(mod_loc(off_text))
    else
        local back = tonumber(G.SETTINGS[prev]) or 0
        snd[field] = back > 0 and back or 50
        G.SETTINGS[prev] = nil
        Q.toast(mod_loc(on_text))
    end
    Q.save()
    return snd[field]
end

function M.handle(key, ctrl)
    local what = M.KEYS[key]
    if not what then return false end
    if ctrl.text_input_hook or (ctrl.locks and ctrl.locks.frame) then return false end
    if ctrl.held_keys and (ctrl.held_keys.lctrl or ctrl.held_keys.rctrl or ctrl.held_keys.lalt or ctrl.held_keys.ralt or ctrl.held_keys.lgui or ctrl.held_keys.rgui) then return false end
    if G.STATE == G.STATES.SPLASH or M.taken(key) then return false end
    local shift = ctrl.held_keys and (ctrl.held_keys.lshift or ctrl.held_keys.rshift)
    if what == "speed" then
        if not Q.on("qol_speed_key") then return false end
        if Controls and Controls.refuse and Controls.refuse("speed_key") then return true end
        if not M.speed_allowed() then return false end
        M.cycle_speed(shift)
        return true
    end
    if not Q.on("qol_mute_keys") then return false end
    if what == "mute" then
        M.toggle_volume("volume", "qol_volume_before_mute", "Sound on", "Sound off")
    else
        M.toggle_volume("music_volume", "qol_music_before_mute", "Music on", "Music off")
    end
    return true
end

Q.row("Shortcuts", function()
    if UIK.touch() then return nil end
    return Q.toggle('set_qol_speed_key', "Speed key", "F speeds up a solo run, Shift+F slows it", 'qol_speed_key')
end)
Q.row("Shortcuts", function()
    if UIK.touch() then return nil end
    return Q.toggle('set_qol_mute_keys', "Mute keys", "M mutes every sound, N only the music", 'qol_mute_keys')
end)

local function strings()
    if not mod_loc_register then return end
    mod_loc_register{
        fr = {["Speed key"] = "Touche vitesse", ["F speeds up a solo run, Shift+F slows it"] = "F accélère une partie solo, Maj+F ralentit",
            ["Mute keys"] = "Touches muet", ["M mutes every sound, N only the music"] = "M coupe tout le son, N seulement la musique",
            ["Game speed"] = "Vitesse du jeu", ["Sound on"] = "Son activé", ["Sound off"] = "Son coupé", ["Music on"] = "Musique activée", ["Music off"] = "Musique coupée"},
        es = {["Speed key"] = "Tecla de velocidad", ["F speeds up a solo run, Shift+F slows it"] = "F acelera una partida solo, Mayús+F la frena",
            ["Mute keys"] = "Teclas de silencio", ["M mutes every sound, N only the music"] = "M silencia todo, N solo la música",
            ["Game speed"] = "Velocidad del juego", ["Sound on"] = "Sonido activado", ["Sound off"] = "Sonido apagado", ["Music on"] = "Música activada", ["Music off"] = "Música apagada"},
    }
end

function M.init()
    strings()
    if M._wrapped or not Controller then return end
    M._wrapped = true
    local kpu = Controller.key_press_update
    Controller.key_press_update = function(self, key, ...)
        local ok, used = pcall(M.handle, key, self)
        if not ok then print("[QoL] hotkeys: " .. tostring(used)) end
        if ok and used then return end
        return kpu(self, key, ...)
    end
end

strings()

return M
