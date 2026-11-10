local X = Extras
local KEY = "spectate_follow"
local M = X.feature(KEY, {follow = true})
local L = function(s) return mod_loc(s) end

M.CHECK_S = 0.5
M.GRACE_S = 1.5
M.GAP_S = 3

local function SP() return rawget(_G, "bom_spectate") end

function M.fighting(p)
    return type(p) == "table" and p.alive ~= false and p.connected ~= false and not p.finished
        and type(p.live) == "table" and p.live.where == "blind"
end

function M.pick(list)
    local best
    for _, p in ipairs(list or {}) do
        if M.fighting(p) then
            local s = tonumber(p.live.score) or 0
            if not best or s > best.s or (s == best.s and (tonumber(p.pid) or 0) < (tonumber(best.p.pid) or 0)) then best = {p = p, s = s} end
        end
    end
    return best and best.p
end

function M.spectate_open()
    M.at, M.away, M.fresh = nil, nil, true
end

function M.spectate_manual()
    if M.follow then M.follow = false end
end

function M.spectate_tick()
    local sp = SP()
    if not (M.follow and sp and sp.is_open()) then return end
    local now = love.timer.getTime()
    if M.at and now - M.at < M.CHECK_S then return end
    M.at = now
    local cur = sp.current()
    if cur and M.fighting(cur) then
        M.away, M.fresh = nil, false
        return
    end
    local best = M.pick(sp.others())
    if not best then
        M.away = nil
        return
    end
    M.away = M.away or now
    if cur and not M.fresh then
        if now - M.away < M.GRACE_S then return end
        if M.last and now - M.last < M.GAP_S then return end
    end
    M.away, M.fresh, M.last = nil, false, now
    sp.watch_pid(best.pid)
end

function M.spectate_top_bar(cells)
    local k = rawget(_G, "bom_kit")
    if not (k and type(cells) == "table") then return cells end
    local touch = UIK.touch()
    local h = k.dims().row_h + 0.12
    local w = touch and 2.7 or 2.5
    local scale = touch and 0.39 or 0.34
    local label = L(M.follow and "Follow: on" or "Follow: off")
    if k.fit then label, scale = k.fit(label, w - 0.25, scale, scale * 0.75) end
    cells[#cells + 1] = k.icon_button({label = label, button = "spec_follow_toggle", w = w, h = h, scale = scale, id = "spec_follow_toggle",
        colour = M.follow and G.C.GREEN or G.C.UI.BACKGROUND_INACTIVE})
    return cells
end

function M.on_toggle(v)
    M.follow = v
    M.at, M.away, M.fresh = nil, nil, v
end

G.FUNCS.spec_follow_toggle = function()
    if not X.on(KEY) then return end
    M.follow = not M.follow
    M.at, M.away, M.fresh = nil, nil, M.follow
    local sp = SP()
    if sp and sp.is_open() and sp.rebuild then sp.rebuild() end
end

mod_loc_register{
    fr = {["Spectate follow"] = "Suivi en spectateur", ["Spectate follows whoever is in a blind"] = "Le spectateur suit celui qui joue une blinde",
        ["Follow: on"] = "Suivi : oui", ["Follow: off"] = "Suivi : non"},
    es = {["Spectate follow"] = "Seguir como espectador", ["Spectate follows whoever is in a blind"] = "El espectador sigue a quien juega una ciega",
        ["Follow: on"] = "Seguir: sí", ["Follow: off"] = "Seguir: no"},
}

return M
