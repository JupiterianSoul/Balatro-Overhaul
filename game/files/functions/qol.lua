QOL = QOL or {}
local Q = QOL

Q.modules = Q.modules or {}
Q.MODULES = {"nav_back", "qol_tab", "hotkeys", "focus_pause", "run_info_tab", "interest_guard", "pause_menu", "collection_pages", "window_memory", "sell_total", "card_rounds", "fast_packs", "double_tap", "tip_ux", "settings_search"}

function Q.feature(key, module)
    Q.modules[key] = module
    return module
end

function Q.init()
    for _, key in ipairs(Q.MODULES) do
        local m = Q.modules[key]
        if m and m.init then
            local ok, err = pcall(m.init)
            if not ok then print("[QoL] init " .. key .. ": " .. tostring(err)) end
        end
    end
end

for _, name in ipairs(Q.MODULES) do
    local ok, err = pcall(require, "functions/qol/" .. name)
    if not ok then print("[QoL] load " .. name .. ": " .. tostring(err)) end
end

return Q
