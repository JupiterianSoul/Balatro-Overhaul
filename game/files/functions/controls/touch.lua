local T = {}

T.MODES = {"auto", "on", "off"}
T.LABELS = {auto = "Auto", on = "On", off = "Off"}
T.seen = false

function T.phone()
    return _G._IS_DESKTOP == false or (G and G.F_MOBILE) or false
end

function T.mode()
    local m = G and G.SETTINGS and G.SETTINGS.touch_controls
    for _, v in ipairs(T.MODES) do if v == m then return m end end
    return "auto"
end

function T.set_mode(m)
    if not (G and G.SETTINGS) then return end
    for _, v in ipairs(T.MODES) do
        if v == m then
            G.SETTINGS.touch_controls = m
            if m == "off" and G.CONTROLLER and G.CONTROLLER.HID.touch then G.CONTROLLER:set_HID_flags("mouse") end
            return
        end
    end
end

function T.on()
    if T.phone() then return true end
    local m = T.mode()
    if m == "off" then return false end
    return m == "on" or T.seen
end

function T.accept(istouch)
    if not istouch then return false end
    if T.phone() then return true end
    if T.mode() == "off" then return false end
    T.seen = true
    return true
end

function T.active()
    local c = G and G.CONTROLLER
    return c and c.HID and c.HID.touch and T.on() or false
end

function T.osk()
    if T.phone() then return false end
    return T.active()
end

TouchInput = T

return T
