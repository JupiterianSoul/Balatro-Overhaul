Extras = Extras or {}
local X = Extras

X.modules = X.modules or {}
X.MODULES = {"run_stats", "match_recap", "replay_bar", "spectate_follow", "keyboard_play", "safe_sell"}
X.SETTINGS = {keyboard_play = true, safe_sell = true, spectate_follow = true}
X.DEFAULT_OFF = {safe_sell = true}

function X.on(key)
    if not X.SETTINGS[key] then return true end
    if X.DEFAULT_OFF[key] then return G.SETTINGS and G.SETTINGS[key] == true or false end
    return not (G.SETTINGS and G.SETTINGS[key] == false)
end

function X.set(key, value)
    if G.SETTINGS and X.SETTINGS[key] then G.SETTINGS[key] = value and true or false end
    local m = X.modules[key]
    if m and m.on_toggle then pcall(m.on_toggle, value and true or false) end
end

function X.feature(key, module)
    X.modules[key] = module
    return module
end

function X.run_info_tabs(list)
    for _, key in ipairs(X.MODULES) do
        local m = X.modules[key]
        if m and m.run_info_tab and X.on(key) then
            local ok, tab = pcall(m.run_info_tab)
            if ok and tab then list[#list + 1] = tab end
        end
    end
end

function X.hook(name, value)
    for _, key in ipairs(X.MODULES) do
        local m = X.modules[key]
        if m and m[name] and X.on(key) then
            local ok, r = pcall(m[name], value)
            if ok and r ~= nil then value = r end
        end
    end
    return value
end

function X.init()
    for _, key in ipairs(X.MODULES) do
        local m = X.modules[key]
        if m and m.init then
            local ok, err = pcall(m.init)
            if not ok then print("[Extras] init " .. key .. ": " .. tostring(err)) end
        end
    end
end

for _, name in ipairs(X.MODULES) do
    local ok, err = pcall(require, "functions/extras/" .. name)
    if not ok then print("[Extras] load " .. name .. ": " .. tostring(err)) end
end

return X
