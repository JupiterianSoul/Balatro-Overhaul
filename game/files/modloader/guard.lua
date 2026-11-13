local Guard = {blocked = {}, installed = false}

local lfs = love.filesystem
local system = love.system and love.system.getOS() or ""
local windows = system == "Windows"
local android = system == "Android"

local function norm(p)
    local abs = p:sub(1, 1) == "/"
    local drive = p:match("^(%a:)/")
    local out = {}
    for seg in p:gmatch("[^/]+") do
        if seg == ".." then
            if #out > 0 and not (drive and #out == 1) then out[#out] = nil end
        elseif seg ~= "." then
            out[#out + 1] = seg
        end
    end
    local s = table.concat(out, "/")
    if abs then s = "/" .. s end
    return s
end

local function fold(p)
    if windows then return p:lower() end
    return p
end

local function root_of(p)
    p = tostring(p or ""):gsub("\\", "/")
    if p == "" then return "" end
    return fold(norm(p))
end

local real
do
    local ok, ffi = pcall(require, "ffi")
    if ok and not windows then
        pcall(ffi.cdef, "char *realpath(const char *path, char *resolved_path); void free(void *ptr); long readlink(const char *path, char *buf, size_t size);")
        local okc = pcall(function() return ffi.C.realpath and ffi.C.free and ffi.C.readlink end)
        if okc then
            local buf = ffi.new("char[8]")
            real = {
                path = function(p)
                    local r = ffi.C.realpath(p, nil)
                    if r == nil then return nil end
                    local s = ffi.string(r)
                    ffi.C.free(r)
                    return s
                end,
                is_link = function(p) return tonumber(ffi.C.readlink(p, buf, 8)) >= 0 end,
            }
        end
    end
end

local function resolve_links(p)
    if not real or p:sub(1, 1) ~= "/" then return p end
    local rest = {}
    local cur = p
    while cur ~= "" and cur ~= "/" do
        local r = real.path(cur)
        if r then
            if #rest == 0 then return r end
            return (r == "/" and "" or r) .. "/" .. table.concat(rest, "/")
        end
        if real.is_link(cur) then return nil end
        local parent, last = cur:match("^(.*)/([^/]+)$")
        if not parent then break end
        table.insert(rest, 1, last)
        cur = parent
    end
    return p
end

local save_root = root_of(lfs.getSaveDirectory())
if real and save_root ~= "" then save_root = real.path(save_root) or save_root end
local source_root = root_of(lfs.getSourceBaseDirectory and lfs.getSourceBaseDirectory() or "")
local game_root = root_of(lfs.getSource and lfs.getSource() or "")
if real then
    source_root = source_root ~= "" and real.path(source_root) or source_root
    game_root = game_root ~= "" and real.path(game_root) or game_root
end

local function absolute(p)
    p = tostring(p):gsub("\\", "/")
    if not (p:sub(1, 1) == "/" or p:match("^%a:/")) then
        local base = android and (lfs.getSaveDirectory() or "") or (lfs.getWorkingDirectory and lfs.getWorkingDirectory() or "")
        p = tostring(base):gsub("\\", "/") .. "/" .. p
    end
    local r = resolve_links(norm(p))
    if not r then return "" end
    return fold(r)
end

local function inside(p, root)
    if root == "" or root == "/" then return false end
    return p == root or p:sub(1, #root + 1) == root .. "/"
end

function Guard.can_write(path)
    if type(path) ~= "string" or path == "" or path:find("%z") then return false end
    return inside(absolute(path), save_root)
end

function Guard.can_read(path)
    if type(path) ~= "string" or path == "" or path:find("%z") then return false end
    local p = absolute(path)
    return inside(p, save_root) or inside(p, game_root) or inside(p, source_root)
end

local function mod_of(src)
    local id = src:match("^=%[SMODS ([^ ]+) ")
    if id then
        if id == "_" then return nil end
        return id
    end
    id = src:match("^=%[lovely ([^ ]+) ")
    if id then
        if id:sub(1, 6) == "SMODS." then return nil end
        return id
    end
    return src:match("^@mods/([^/]+)/") or src:match("^@.-/mods/([^/]+)/")
end

function Guard.caller()
    for level = 3, 80 do
        local info = debug.getinfo(level, "S")
        if not info then return nil end
        local src = info.source or ""
        if src ~= "=[C]" and not src:find("modloader/nfs.lua", 1, true) and not src:find("modloader/guard.lua", 1, true) then
            return mod_of(src)
        end
    end
end

local function refuse(mod, what, arg)
    local line = string.format("BLOCKED %s %s %s", tostring(mod), what, tostring(arg))
    if #Guard.blocked < 200 then Guard.blocked[#Guard.blocked + 1] = line end
    print("[modloader] " .. line)
    if Guard.log then pcall(lfs.append, Guard.log, line .. "\n") end
    return nil, "Blocked by the Overhaul: mods may only change files in the game's own folder", 13
end

local function writes(mode)
    mode = tostring(mode or "r")
    return mode:find("[wa+]") ~= nil
end

function Guard.install(opts)
    if Guard.installed then return end
    Guard.installed = true
    opts = opts or {}
    Guard.log = opts.log
    local o = {
        open = io.open, lines = io.lines, output = io.output, input = io.input, popen = io.popen,
        execute = os.execute, remove = os.remove, rename = os.rename, tmpname = os.tmpname,
        loadlib = package.loadlib,
        openURL = love.system and love.system.openURL,
    }
    Guard.originals = o
    rawset(io, "open", function(name, mode, ...)
        local mod = Guard.caller()
        if mod then
            if writes(mode) then
                if not Guard.can_write(name) then return refuse(mod, "io.open(" .. tostring(mode) .. ")", name) end
            elseif not Guard.can_read(name) then
                return refuse(mod, "io.open(r)", name)
            end
        end
        return o.open(name, mode, ...)
    end)
    rawset(io, "lines", function(name, ...)
        if name ~= nil then
            local mod = Guard.caller()
            if mod and not Guard.can_read(name) then error("Blocked by the Overhaul: " .. tostring(name), 2) end
        end
        return o.lines(name, ...)
    end)
    rawset(io, "output", function(f, ...)
        if type(f) == "string" then
            local mod = Guard.caller()
            if mod and not Guard.can_write(f) then error("Blocked by the Overhaul: " .. tostring(f), 2) end
        end
        return o.output(f, ...)
    end)
    rawset(io, "input", function(f, ...)
        if type(f) == "string" then
            local mod = Guard.caller()
            if mod and not Guard.can_read(f) then error("Blocked by the Overhaul: " .. tostring(f), 2) end
        end
        return o.input(f, ...)
    end)
    rawset(io, "popen", function(cmd, ...)
        local mod = Guard.caller()
        if mod then return refuse(mod, "io.popen", cmd) end
        return o.popen(cmd, ...)
    end)
    rawset(os, "execute", function(cmd, ...)
        local mod = Guard.caller()
        if mod then
            refuse(mod, "os.execute", cmd)
            if cmd == nil then return 0 end
            return -1
        end
        return o.execute(cmd, ...)
    end)
    rawset(os, "remove", function(name, ...)
        local mod = Guard.caller()
        if mod and not Guard.can_write(name) then return refuse(mod, "os.remove", name) end
        return o.remove(name, ...)
    end)
    rawset(os, "rename", function(a, b, ...)
        local mod = Guard.caller()
        if mod and not (Guard.can_write(a) and Guard.can_write(b)) then return refuse(mod, "os.rename", tostring(a) .. " -> " .. tostring(b)) end
        return o.rename(a, b, ...)
    end)
    if o.loadlib then
        rawset(package, "loadlib", function(path, ...)
            local mod = Guard.caller()
            if mod then return refuse(mod, "package.loadlib", path) end
            return o.loadlib(path, ...)
        end)
    end
    local loaders = rawget(package, "loaders") or rawget(package, "searchers")
    if loaders then
        for i = 1, #loaders do
            local loader = loaders[i]
            if type(loader) == "function" then
                loaders[i] = function(name, ...)
                    local res, extra = loader(name, ...)
                    if type(res) == "function" and res ~= rawget(package.preload, name) then
                        local info = debug.getinfo(res, "S")
                        if info and info.what == "C" then
                            local mod = Guard.caller()
                            if mod then
                                refuse(mod, "require (native)", name)
                                return "\n\tnative modules are blocked for mods"
                            end
                        end
                    end
                    return res, extra
                end
            end
        end
    end
    if o.openURL then
        love.system.openURL = function(url, ...)
            local mod = Guard.caller()
            if mod and not (type(url) == "string" and url:lower():match("^https?://[^%s]+$")) then
                refuse(mod, "openURL", url)
                return false
            end
            return o.openURL(url, ...)
        end
    end
end

return Guard
