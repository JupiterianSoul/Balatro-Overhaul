local Q = QOL
local M = Q.feature("window_memory", {})

M.KEY = "qol_window"
M.EVERY = 1
M.SETTLE = 2
M.MIN_W, M.MIN_H = 480, 270

Q.default("qol_window_memory", true)

function M.mobile()
    local os_name = love and love.system and love.system.getOS and love.system.getOS()
    return os_name == "Android" or os_name == "iOS"
end

function M.windowed()
    local w = G and G.SETTINGS and G.SETTINGS.WINDOW
    return (w and w.screenmode or "Windowed") == "Windowed"
end

function M.active()
    return not M.mobile() and M.windowed() and Q.on("qol_window_memory") and love.window and love.window.getPosition ~= nil
end

function M.read()
    local w, h, flags = love.window.getMode()
    local x, y, display = love.window.getPosition()
    if not (w and h and x and y) then return nil end
    return {w = math.floor(w), h = math.floor(h), x = math.floor(x), y = math.floor(y), display = display or (flags and flags.display) or 1}
end

function M.fit(g, count, desktop)
    if type(g) ~= "table" then return nil end
    local w, h, x, y = tonumber(g.w), tonumber(g.h), tonumber(g.x), tonumber(g.y)
    local display = math.floor(tonumber(g.display) or 1)
    if not (w and h and x and y) then return nil end
    if display < 1 or display > (count or 1) then display = 1 end
    local dw, dh = desktop(display)
    if not (dw and dh and dw > 0 and dh > 0) then return nil end
    w = math.max(math.min(M.MIN_W, dw), math.min(math.floor(w), dw))
    h = math.max(math.min(M.MIN_H, dh), math.min(math.floor(h), dh))
    x = math.max(0, math.min(math.floor(x), dw - w))
    y = math.max(0, math.min(math.floor(y), dh - h))
    return {w = w, h = h, x = x, y = y, display = display}
end

function M.same(a, b)
    if not (a and b) then return false end
    return a.w == b.w and a.h == b.h and a.x == b.x and a.y == b.y and a.display == b.display
end

function M.restore()
    if not M.active() then return false end
    local g = M.fit(G.SETTINGS[M.KEY], love.window.getDisplayCount and love.window.getDisplayCount() or 1, love.window.getDesktopDimensions)
    if not g then return false end
    local cur = M.read()
    if cur and M.same(cur, g) then return true end
    local _, _, flags = love.window.getMode()
    flags = flags or {}
    flags.display = g.display
    flags.resizable = true
    if not cur or cur.w ~= g.w or cur.h ~= g.h or cur.display ~= g.display then
        love.window.updateMode(g.w, g.h, flags)
    end
    love.window.setPosition(g.x, g.y, g.display)
    M.last = M.read()
    return true
end

function M.tick(dt)
    M.t = (M.t or 0) + dt
    if M.t < M.EVERY then return end
    M.t = 0
    if not M.active() then return end
    local cur = M.read()
    if not cur then return end
    if not M.same(cur, M.last) then
        M.last = cur
        M.since = 0
        return
    end
    M.since = (M.since or 0) + M.EVERY
    if M.since < M.SETTLE or M.same(cur, G.SETTINGS[M.KEY]) then return end
    G.SETTINGS[M.KEY] = cur
    Q.save()
end

Q.row("Window", function()
    if M.mobile() or UIK.touch() then return nil end
    return Q.toggle('set_qol_window', "Remember window", "Opens where you left it, same size", 'qol_window_memory')
end)

local function strings()
    if not mod_loc_register then return end
    mod_loc_register{
        fr = {["Window"] = "Fenêtre", ["Remember window"] = "Mémoriser la fenêtre", ["Opens where you left it, same size"] = "S'ouvre là où vous l'avez laissée, même taille"},
        es = {["Window"] = "Ventana", ["Remember window"] = "Recordar la ventana", ["Opens where you left it, same size"] = "Se abre donde la dejaste, mismo tamaño"},
    }
end

local function wrap_apply()
    if M._apply or not (G and G.FUNCS and G.FUNCS.apply_window_changes) then return end
    M._apply = true
    local apply = G.FUNCS.apply_window_changes
    G.FUNCS.apply_window_changes = function(initial, ...)
        local r = apply(initial, ...)
        if initial == true and not M.restored then
            M.restored = true
            local ok, err = pcall(M.restore)
            if not ok then print("[QoL] window restore: " .. tostring(err)) end
        end
        return r
    end
end

function M.init()
    strings()
    wrap_apply()
    if not M.restored then
        M.restored = true
        local ok, err = pcall(M.restore)
        if ok and err then pcall(love.resize, love.graphics.getDimensions()) end
        if not ok then print("[QoL] window restore: " .. tostring(err)) end
    end
    if M._wrapped or not G then return end
    M._wrapped = true
    local upd = G.update
    G.update = function(self, dt, ...)
        local r = upd(self, dt, ...)
        local ok, err = pcall(M.tick, dt or 0)
        if not ok and not M._warned then M._warned = true print("[QoL] window tick: " .. tostring(err)) end
        return r
    end
end

strings()
wrap_apply()

return M
