local Hooks = require("overhaul.hooks")

local K = {}
IngameKeyboard = K

function K.phone()
    return (G and G.F_MOBILE) or rawget(_G, "_IS_DESKTOP") == false or false
end

function K.on()
    local s = G and G.SETTINGS
    if not s then return K.phone() end
    if s.ingame_keyboard == nil then s.ingame_keyboard = K.phone() end
    return s.ingame_keyboard and true or false
end

local function system_keys(on)
    if not (love.keyboard and love.keyboard.setTextInput) then return end
    if not on and not K.phone() then return end
    pcall(love.keyboard.setTextInput, on)
end

Hooks.wrap("G.FUNCS", "text_input", function(orig) return function(e, ...)
    local c = G.CONTROLLER
    local on = K.on()
    local C, T = rawget(_G, "Controls"), rawget(_G, "TouchInput")
    local mob, ctl = G.F_MOBILE, c and c.HID and c.HID.controller
    local sk, osk = C and C.screen_keyboard, T and T.osk
    if on then
        if C then C.screen_keyboard = function() return true end end
    else
        G.F_MOBILE = false
        if c and c.HID then c.HID.controller = false end
        if C then C.screen_keyboard = function() return false end end
        if T then T.osk = function() return false end end
    end
    local r = Hooks.pack(pcall(orig, e, ...))
    G.F_MOBILE = mob
    if c and c.HID then c.HID.controller = ctl end
    if C then C.screen_keyboard = sk end
    if T then T.osk = osk end
    if not on and c and c.text_input_hook == e and K.sys ~= e then
        K.sys = e
        system_keys(true)
    end
    if not r[1] then error(r[2], 0) end
    return select(2, Hooks.unpack(r))
end end, {id = "overhaul.ingame_keyboard"})

Hooks.wrap("G.FUNCS", "select_text_input", function(original) return function(element, ...)
    local results = Hooks.pack(original(element, ...))
    local controller = G.CONTROLLER
    if K.sys and controller and controller.text_input_hook == K.sys and not K.on() then system_keys(true) end
    return Hooks.unpack(results)
end end, {id = "overhaul.ingame_keyboard.select"})

local function update_after(...)
    local controller = G and G.CONTROLLER
    if K.sys and (not controller or controller.text_input_hook ~= K.sys or K.on()) then
        K.sys = nil
        if not (controller and controller.text_input_hook) or K.on() then system_keys(false) end
    end
    return ...
end

Hooks.wrap("love", "update", function(original) return function(delta_time, ...)
    return update_after(original(delta_time, ...))
end end, {id = "overhaul.ingame_keyboard.update"})

return K
