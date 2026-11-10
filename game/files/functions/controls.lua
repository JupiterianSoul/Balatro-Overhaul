Controls = Controls or {}
local C = Controls

C.MODES = {"mouse", "keyboard", "trackpad", "trackpad_keys"}
C.MODULES = {"trackpad", "tpk", "pad", "page", "toast", "touch", "cursor"}
C.modules = C.modules or {}

function C.valid(m)
    for _, v in ipairs(C.MODES) do if v == m then return true end end
    return false
end

function C.mode()
    local S = G and G.SETTINGS
    local m = S and S.input_mode
    if C.valid(m) then return m end
    if S and S.keyboard_play == false then return "mouse" end
    return "keyboard"
end

function C.touch()
    return UIK and UIK.touch and UIK.touch() or false
end

function C.keys_on()
    local m = C.mode()
    return m == "keyboard" or m == "trackpad_keys"
end

function C.trackpad_on()
    local m = C.mode()
    return (m == "trackpad" or m == "trackpad_keys") and not C.touch()
end

function C.screen_keyboard()
    return C.mode() == "trackpad" and not C.touch()
end

function C.refuse(key)
    local FL = rawget(_G, "FairLock")
    if not (FL and FL.refuse) then return false end
    local ok, r = pcall(FL.refuse, key)
    return ok and r and true or false
end

function C.set_mode(m)
    if not (G and G.SETTINGS and C.valid(m)) then return end
    local was = C.mode()
    G.SETTINGS.input_mode = m
    local keys = m == "keyboard" or m == "trackpad_keys"
    if Extras and Extras.set then Extras.set("keyboard_play", keys) else G.SETTINGS.keyboard_play = keys end
    local kp = Extras and Extras.modules and Extras.modules.keyboard_play
    if kp and kp.refresh then kp.capture = nil pcall(kp.refresh) end
    for _, name in ipairs(C.MODULES) do
        local mod = C.modules[name]
        if mod and mod.on_mode then pcall(mod.on_mode, m, was) end
    end
end

function C.init()
    for _, name in ipairs(C.MODULES) do
        local mod = C.modules[name]
        if mod and mod.init then
            local ok, err = pcall(mod.init)
            if not ok then print("[Controls] init " .. name .. ": " .. tostring(err)) end
        end
    end
end

for _, name in ipairs(C.MODULES) do
    local ok, mod = pcall(require, "functions/controls/" .. name)
    if ok and type(mod) == "table" then C.modules[name] = mod
    elseif not ok then print("[Controls] load " .. name .. ": " .. tostring(mod)) end
end

return C
