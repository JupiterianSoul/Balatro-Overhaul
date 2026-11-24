local Hooks = {
    list = {},
    by_id = {},
    ours = setmetatable({}, {__mode = "k"}),
    base_of = setmetatable({}, {__mode = "k"}),
    thru = setmetatable({}, {__mode = "k"}),
    rewraps = 0,
    fallbacks = {},
    fallbacks_run = {},
}

local function resolve(owner)
    if type(owner) ~= "string" then return owner end
    local t = _G
    for part in owner:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[part]
    end
    return t
end

local function install(h)
    local owner = resolve(h.owner)
    if type(owner) ~= "table" then return false end
    local current = owner[h.key]
    while current ~= nil and Hooks.ours[current] == h do current = Hooks.base_of[current] end
    if type(current) ~= "function" and not h.allow_missing then return false end
    local inner = h.make(current)
    if type(inner) ~= "function" then return false end
    local fn
    if h.recursive then
        fn = inner
    else
        local function leave(...)
            h.depth = h.depth - 1
            return ...
        end
        fn = function(...)
            if h.depth > 0 and current then return current(...) end
            h.depth = h.depth + 1
            return leave(inner(...))
        end
    end
    Hooks.ours[fn] = h
    Hooks.base_of[fn] = current
    h.fn = fn
    h.base = current
    h.installs = h.installs + 1
    owner[h.key] = fn
    return true
end

function Hooks.pack(...)
    return {n = select("#", ...), ...}
end

function Hooks.unpack(t)
    return unpack(t, 1, t.n)
end

function Hooks.wrap(owner, key, make, opts)
    opts = opts or {}
    local id = opts.id or (type(owner) == "string" and owner or tostring(owner)) .. "." .. key
    local h = Hooks.by_id[id]
    if not h then
        h = {id = id, installs = 0, depth = 0}
        Hooks.by_id[id] = h
        Hooks.list[#Hooks.list + 1] = h
    end
    h.owner, h.key, h.make = owner, key, make
    h.recursive, h.allow_missing = opts.recursive, opts.allow_missing
    h.fn = nil
    install(h)
    return h
end

local function in_chain(f, target)
    local guard = 0
    while f ~= nil and guard < 64 do
        if f == target then return true end
        if not (Hooks.ours[f] or Hooks.thru[f]) then return false end
        f = Hooks.base_of[f]
        guard = guard + 1
    end
    return false
end

function Hooks.adopt(fn, base)
    if type(fn) ~= "function" then return end
    Hooks.thru[fn] = true
    Hooks.base_of[fn] = base
end

function Hooks.chain_has(f, set)
    local guard = 0
    while f ~= nil and guard < 256 do
        if set[f] then return true end
        if not (Hooks.ours[f] or Hooks.thru[f]) then return false end
        f = Hooks.base_of[f]
        guard = guard + 1
    end
    return false
end

function Hooks.reapply()
    local n = 0
    for _, h in ipairs(Hooks.list) do
        h.depth = 0
        local owner = resolve(h.owner)
        if type(owner) == "table" and not (h.fn and in_chain(owner[h.key], h.fn)) and install(h) then
            n = n + 1
            if h.installs > 1 then Hooks.rewraps = Hooks.rewraps + 1 end
        end
    end
    local engine = package.loaded["modloader.lovely"]
    if type(engine) == "table" and engine.late_misses and #engine.late_misses > 0 then Hooks.run_fallbacks(engine.late_misses) end
    return n
end

function Hooks.tick(dt)
    if #Hooks.list == 0 then return end
    Hooks.clock = (Hooks.clock or 0) + (dt or 0)
    if Hooks.clock < 0.5 then return end
    Hooks.clock = 0
    Hooks.reapply()
end

function Hooks.installed(id)
    local h = Hooks.by_id[id]
    if not h or not h.fn then return false end
    local owner = resolve(h.owner)
    return type(owner) == "table" and in_chain(owner[h.key], h.fn)
end

function Hooks.on_late_miss(id, fn)
    Hooks.fallbacks[id] = fn
end

function Hooks.run_fallbacks(misses)
    local n = 0
    for _, m in ipairs(misses or {}) do
        local fn = m.id and Hooks.fallbacks[m.id]
        if fn and not Hooks.fallbacks_run[m.id] then
            Hooks.fallbacks_run[m.id] = true
            local ok = pcall(fn, m)
            if ok then n = n + 1 end
        end
    end
    return n
end

Hooks.wrap("love", "update", function(orig) return function(dt, ...)
    local r = Hooks.pack(orig(dt, ...))
    pcall(Hooks.tick, dt)
    return Hooks.unpack(r)
end end, {id = "hooks.tick"})

Hooks.wrap(_G, "set_main_menu_UI", function(orig) return function(...)
    local r = Hooks.pack(orig(...))
    pcall(Hooks.reapply)
    return Hooks.unpack(r)
end end, {id = "hooks.menu", recursive = true})

return Hooks
