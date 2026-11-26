PERF_AUTO = PERF_AUTO or {}
local A = PERF_AUTO
local Hooks = require("overhaul.hooks")

A.CAPS = {30, 40, 60, 90, 120, 144, 165, 9999}
A.WINDOW = 2
A.DOWN_WINDOWS = 2
A.UP_WINDOWS = 8
A.UP_WAIT = 30
A.FLOOR_TIME = 300
A.LEVELS = {
    {perf_particle_amount = 2, shadows = 'Off'},
    {perf_shader_quality = 2, perf_background = 2},
    {perf_resolution = 2},
    {perf_shader_quality = 1, perf_background = 3, perf_particle_amount = 3, perf_offscreen_culling = true},
    {perf_resolution = 3},
}

local LIGHTER = {
    perf_particle_amount = function(v, cur) return v > (cur or 1) end,
    perf_background = function(v, cur) return v > (cur or 1) end,
    perf_resolution = function(v, cur) return v > (cur or 1) end,
    perf_shader_quality = function(v, cur) return v < (cur or 3) end,
    shadows = function(v, cur) return v == 'Off' and cur ~= 'Off' end,
    perf_offscreen_culling = function(v, cur) return v == true and cur ~= true end,
}

A.level = A.level or 0
A.user = A.user or {}
A.applied = A.applied or {}

local function GR() return G and G.SETTINGS and G.SETTINGS.GRAPHICS end

function A.enabled()
    local g = GR()
    return g and g.perf_auto ~= false
end

local function side_effects(changed)
    local P = rawget(_G, "PERF_OPTS")
    local g = GR()
    if changed.perf_particle_amount and P and P.set_particles then P.set_particles(g.perf_particle_amount) end
    if changed.perf_background and P and P.set_background then pcall(P.set_background, g.perf_background) end
    if changed.perf_resolution and love.resize then love.resize(love.graphics.getDimensions()) end
end

local function restore(changed)
    local g = GR()
    for k, v in pairs(A.user) do
        if g[k] ~= v then g[k] = v changed[k] = true end
    end
    A.user, A.applied = {}, {}
end

local function adopt_user_edits()
    local g = GR()
    for k, v in pairs(A.applied) do
        if g[k] ~= v then
            A.user[k] = g[k]
            A.applied[k] = nil
        end
    end
end

function A.apply(level)
    local g = GR()
    if not g then return end
    adopt_user_edits()
    local changed = {}
    restore(changed)
    level = math.max(0, math.min(level or 0, #A.LEVELS))
    for i = 1, level do
        for k, v in pairs(A.LEVELS[i]) do
            local cur = A.user[k]
            if cur == nil then cur = g[k] end
            if LIGHTER[k](v, cur) then
                if A.user[k] == nil then A.user[k] = g[k] end
                if g[k] ~= v then changed[k] = true end
                g[k] = v
                A.applied[k] = v
            end
        end
    end
    A.level = level
    side_effects(changed)
end

function A.target()
    local g = GR()
    local cap = A.CAPS[g and g.fps_cap or 3] or 60
    return math.min(60, cap)
end

local function settings_open()
    local U = rawget(_G, "UIK")
    return G.OVERLAY_MENU ~= nil and U and U._win and U._win.id == 'settings'
end

local function reset_window()
    A.acc, A.n, A.low, A.high = 0, 0, 0, 0
end

function A.tick()
    local g = GR()
    if not g then return end
    if not A.started then
        A.started = true
        local P = rawget(_G, "PERF_OPTS")
        if P and P.fill_defaults then P.fill_defaults() end
        reset_window()
        local saved = tonumber(g.perf_auto_level) or 0
        if A.enabled() and saved > 0 then A.apply(saved) end
    end
    if not A.enabled() then
        if A.level > 0 or next(A.user) then A.apply(0) end
        return
    end
    if settings_open() then
        if not A.paused then
            A.paused = A.level
            local changed = {}
            adopt_user_edits()
            restore(changed)
            side_effects(changed)
        end
        reset_window()
        return
    elseif A.paused then
        local lv = A.paused
        A.paused = nil
        A.apply(lv)
        reset_window()
        return
    end
    local w = love.window
    if w and w.hasFocus and not w.hasFocus() then reset_window() return end
    local dt = love.timer.getDelta()
    if dt > 0.25 then return end
    A.acc, A.n = A.acc + dt, A.n + 1
    if A.acc < A.WINDOW then return end
    local fps = A.n / A.acc
    A.acc, A.n = 0, 0
    local target = A.target()
    local now = love.timer.getTime()
    if target ~= A.last_target then
        A.last_target, A.floor, A.floor_until, A.low, A.high = target, nil, nil, 0, 0
    end
    if fps < target * 0.92 then
        A.low, A.high = A.low + 1, 0
    elseif fps >= target * 0.985 then
        A.high, A.low = A.high + 1, 0
    else
        A.low, A.high = 0, 0
    end
    if A.low >= A.DOWN_WINDOWS and A.level < #A.LEVELS then
        if A.raised_at and now - A.raised_at < 20 then
            A.floor, A.floor_until = A.level + 1, now + A.FLOOR_TIME
        end
        A.apply(A.level + 1)
        A.lowered_at, A.low, A.high = now, 0, 0
        A.stable_since = now
    elseif A.high >= A.UP_WINDOWS and A.level > 0 and (not A.lowered_at or now - A.lowered_at >= A.UP_WAIT) then
        local floor = (A.floor_until and now < A.floor_until) and A.floor or 0
        if A.level > floor then
            A.apply(A.level - 1)
            A.raised_at, A.high = now, 0
            A.stable_since = now
        end
    end
    if A.stable_since and now - A.stable_since > 30 and tonumber(g.perf_auto_level) ~= A.level then
        g.perf_auto_level = A.level
    end
end

Hooks.wrap(love, "update", function(orig) return function(...)
    local r = orig(...)
    local ok, err = pcall(A.tick)
    if not ok and not A.warned then A.warned = true print("[PERF_AUTO] " .. tostring(err)) end
    return r
end end, {id = "perf_auto.update"})

function A.user_settings()
    local g = GR()
    if not (g and next(A.user)) then return G.SETTINGS end
    adopt_user_edits()
    local copy, gc = {}, {}
    for k, v in pairs(G.SETTINGS) do copy[k] = v end
    for k, v in pairs(g) do gc[k] = v end
    for k in pairs(A.applied) do gc[k] = A.user[k] end
    copy.GRAPHICS = gc
    return copy
end

for _, name in ipairs({"save_settings", "empty_profile"}) do
    Hooks.wrap("Game", name, function(orig) return function(self, ...)
        local r = orig(self, ...)
        if next(A.user) and G.ARGS and G.ARGS.save_settings == G.SETTINGS then G.ARGS.save_settings = A.user_settings() end
        return r
    end end, {id = "perf_auto." .. name})
end

return A
