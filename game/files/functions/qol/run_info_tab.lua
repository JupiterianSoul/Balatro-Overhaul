local Q = QOL
local M = Q.feature("run_info_tab", {})

local function helpers() return rawget(_G, "OVERLAY_MENU_HELPERS") or {} end

function M.restore()
    local h = helpers()
    if not (M.last and h.restore_tabs and type(G.OVERLAY_MENU) == "table") then return end
    M.restoring = true
    local ok, err = pcall(h.restore_tabs, M.last)
    M.restoring = false
    if not ok then error(err) end
end

function M.init()
    if M._wrapped or not (G and G.FUNCS and G.FUNCS.run_info and G.FUNCS.change_tab) then return end
    M._wrapped = true
    local open = G.FUNCS.run_info
    G.FUNCS.run_info = function(...)
        local r = open(...)
        if type(G.OVERLAY_MENU) == "table" then
            M.box = G.OVERLAY_MENU
            local ok, err = pcall(M.restore)
            if not ok then print("[QoL] run info tab: " .. tostring(err)) end
        end
        return r
    end
    local change = G.FUNCS.change_tab
    G.FUNCS.change_tab = function(...)
        local r = change(...)
        local e = ...
        local id = type(e) == "table" and e.config and e.config.id
        if M.box and G.OVERLAY_MENU == M.box and not M.restoring and type(id) == "string" and id:sub(1, 8) == "tab_but_" then M.last = {id} end
        return r
    end
end

return M
