local Boot = {
    root = "mods",
    fork_name = "smods",
    fork_dir = "smods",
    fork_id = "Steamodded",
    active = false,
    modded = false,
    enabled = {},
    refused = {},
    threads = setmetatable({}, {__mode = "k"}),
    log = {},
}

local function note(msg)
    Boot.log[#Boot.log + 1] = msg
    print("[modloader] " .. msg)
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

function Boot.paths()
    local root = Boot.root
    return {
        enabled = root .. "/enabled.txt",
        cache = root .. "/.cache",
        log = root .. "/lovely/log.txt",
        boot_log = root .. "/.boot_log.txt",
        running = root .. "/.running.txt",
        exit_log = root .. "/.exit_log.txt",
        refused = root .. "/.refused.txt",
        session = root .. "/session.txt",
        crash = root .. "/.crash.txt",
        last_crash = root .. "/.last_crash.txt",
        boot_crashes = root .. "/.boot_crashes.txt",
    }
end

function Boot.read_session()
    local data = love.filesystem.read(Boot.paths().session) or ""
    local lines = {}
    for line in data:gmatch("[^\r\n]+") do lines[#lines + 1] = trim(line) end
    return lines[1] == "modded", lines[2] ~= "" and lines[2] or nil
end

function Boot.write_session(modded, after)
    love.filesystem.createDirectory(Boot.root)
    if not modded and not after then
        love.filesystem.remove(Boot.paths().session)
        return true
    end
    return love.filesystem.write(Boot.paths().session, (modded and "modded" or "plain") .. "\n" .. (after and (after .. "\n") or ""))
end

function Boot.read_enabled()
    local list, set = {}, {}
    local data = love.filesystem.read(Boot.paths().enabled)
    if data then
        for line in data:gmatch("[^\r\n]+") do
            line = trim(line)
            if line ~= "" and line:sub(1, 1) ~= "#" and not set[line] then
                set[line] = true
                list[#list + 1] = line
            end
        end
    end
    return list, set
end

function Boot.read_enabled_set()
    local _, set = Boot.read_enabled()
    return set
end

function Boot.write_enabled(list)
    love.filesystem.createDirectory(Boot.root)
    return love.filesystem.write(Boot.paths().enabled, table.concat(list, "\n") .. (#list > 0 and "\n" or ""))
end

local function is_steamodded(dir)
    return love.filesystem.getInfo(dir .. "/src/preflight/loader.lua", "file") ~= nil
end

function Boot.mod_folders()
    local out = {}
    for _, name in ipairs(love.filesystem.getDirectoryItems(Boot.root)) do
        if name:sub(1, 1) ~= "." and name ~= "lovely" and love.filesystem.getInfo(Boot.root .. "/" .. name, "directory") then
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

function Boot.download_dirs()
    local env = os.getenv("MODLOADER_DOWNLOADS")
    if env == nil then return nil end
    local dirs = {}
    for d in env:gmatch("[^;]+") do dirs[#dirs + 1] = d end
    return dirs
end

function Boot.run_installer()
    local ok, err = pcall(function()
        local installer = require("modloader.installer")
        local res = installer.run({dirs = Boot.download_dirs()})
        Boot.installed = res and res.installed or {}
        if #Boot.installed > 0 then note("installed " .. #Boot.installed .. " mod(s) from Downloads") end
    end)
    if not ok then note("installer failed: " .. tostring(err)) end
end

function Boot.forced()
    local v = os.getenv("MODLOADER_FORK")
    return v ~= nil and v ~= "" and v ~= "0"
end

function Boot.migrate()
    local list, set = Boot.read_enabled()
    if not set[Boot.fork_id] then return false end
    local out = {}
    for _, name in ipairs(list) do
        if name ~= Boot.fork_id then out[#out + 1] = name end
    end
    Boot.write_enabled(out)
    note("enabled list: dropped " .. Boot.fork_id .. " (it loads by itself when a mod is on)")
    return true
end

function Boot.wanted()
    local list, set = Boot.read_enabled()
    local folders = Boot.mod_folders()
    local on = Boot.forced()
    local mods = {}
    for _, name in ipairs(folders) do
        if set[name] and not is_steamodded(Boot.root .. "/" .. name) then
            mods[#mods + 1] = name
            on = true
        end
    end
    return on, mods, folders, list
end

local function load_lib(path)
    local ok, lib = pcall(function() return love.filesystem.load(path)() end)
    return ok and lib or nil
end

local function libs()
    if Boot._libs then return Boot._libs end
    if not rawget(_G, "sendWarnMessage") then sendWarnMessage = function(msg) print("[modloader] " .. tostring(msg)) end end
    Boot._libs = {
        json = load_lib(Boot.fork_dir .. "/libs/json/json.lua"),
        util = load_lib(Boot.fork_dir .. "/src/preflight/sharedUtil.lua"),
    }
    return Boot._libs
end

local function read_manifest(dir, depth)
    local json = libs().json
    if not json then return nil end
    local subdirs = {}
    for _, item in ipairs(love.filesystem.getDirectoryItems(dir)) do
        local path = dir .. "/" .. item
        local info = love.filesystem.getInfo(path)
        if info and info.type == "file" and item:lower():match("%.json$") then
            local ok, data = pcall(json.decode, love.filesystem.read(path) or "")
            if ok and type(data) == "table" and type(data.id) == "string" and type(data.main_file) == "string" then
                data._dir = dir
                return data
            end
        elseif info and info.type == "directory" and item:sub(1, 1) ~= "." then
            subdirs[#subdirs + 1] = path
        end
    end
    if depth < 2 then
        for _, sub in ipairs(subdirs) do
            local m = read_manifest(sub, depth + 1)
            if m then return m end
        end
    end
end

function Boot.manifest(name)
    Boot._manifests = Boot._manifests or {}
    if Boot._manifests[name] == nil then
        Boot._manifests[name] = read_manifest(Boot.root .. "/" .. name, 1) or false
    end
    return Boot._manifests[name] or nil
end

local function fork_version()
    local v = love.filesystem.read(Boot.fork_dir .. "/version.lua") or ""
    return v:match('"(.-)"') or "0.0.0"
end

local ops = {
    ["<<"] = function(a, b) return a < b end,
    [">>"] = function(a, b) return a > b end,
    ["<="] = function(a, b) return a <= b end,
    [">="] = function(a, b) return a >= b end,
    ["=="] = function(a, b) return a == b end,
}

local function parse_dep(part)
    local dep = {id = part:match("^%s*([^(%s<>=]+)"), checks = {}}
    for vs in part:gmatch("%((.-)%)") do
        vs = vs:gsub("%s", "")
        local op, ver = vs:match("^(..)(.*)$")
        if op and ops[op] then dep.checks[#dep.checks + 1] = {op = op, ver = ver} end
    end
    if #dep.checks == 0 then
        local op, ver = part:match("^%s*[^%s%(<>=]+%s*([<>=][<>=])%s*([^%s%)]+)")
        if op and ops[op] then dep.checks[1] = {op = op, ver = ver} end
    end
    return dep
end

local function version_ok(have, checks)
    local util = libs().util
    if not util or not util.V then return true end
    for _, c in ipairs(checks) do
        local ok, res = pcall(function()
            local a, b = util.V(have), util.V(c.ver)
            if not (a:is_valid(true) and b:is_valid(true)) then return true end
            return ops[c.op](a, b)
        end)
        if ok and not res then return false end
    end
    return true
end

function Boot.state_key(list, folders)
    return table.concat(list, ",") .. "|" .. table.concat(folders, ",")
end

function Boot.read_refused(key)
    local out = {}
    local data = love.filesystem.read(Boot.paths().refused)
    if not data then return out end
    local first = true
    for line in data:gmatch("[^\r\n]+") do
        if first then
            if line ~= key then return {} end
            first = false
        else
            local name, mod, needs = line:match("^(.-)\t(.-)\t(.*)$")
            if name then out[name] = {name = name, mod = mod, needs = needs} end
        end
    end
    return out
end

function Boot.refuse(entries)
    local list = Boot.read_enabled()
    local key = Boot.state_key(list, Boot.mod_folders())
    local known = Boot.read_refused(key)
    for _, e in ipairs(entries) do
        known[e.name] = e
        note("refused " .. e.name .. ": " .. tostring(e.needs))
    end
    local lines = {key}
    for _, e in pairs(known) do
        lines[#lines + 1] = table.concat({e.name, e.mod or e.name, (tostring(e.needs or ""):gsub("[\t\r\n]", " "))}, "\t")
    end
    love.filesystem.createDirectory(Boot.root)
    love.filesystem.write(Boot.paths().refused, table.concat(lines, "\n") .. "\n")
end

function Boot.check(mods, folders, list)
    local enabled = {}
    for _, name in ipairs(mods) do enabled[name] = true end
    local installed = {}
    for _, name in ipairs(folders) do
        local m = not is_steamodded(Boot.root .. "/" .. name) and Boot.manifest(name)
        if m then installed[m.id] = installed[m.id] or name end
    end
    local refused, order = {}, {}
    local function refuse(name, mod, needs)
        if refused[name] then return end
        refused[name] = {name = name, mod = mod, needs = needs}
        order[#order + 1] = refused[name]
    end
    for name, e in pairs(Boot.read_refused(Boot.state_key(list, folders))) do
        if enabled[name] then refuse(name, e.mod, e.needs) end
    end
    local builtin = {Steamodded = fork_version(), Lovely = true, Balatro = true}
    local changed = true
    while changed do
        changed = false
        local provided = {}
        for _, name in ipairs(mods) do
            local m = not refused[name] and Boot.manifest(name)
            if m then
                provided[m.id] = provided[m.id] or {}
                table.insert(provided[m.id], m.version or "0.0.0")
                for _, p in ipairs(type(m.provides) == "table" and m.provides or {}) do
                    local d = parse_dep(tostring(p))
                    if d.id then
                        provided[d.id] = provided[d.id] or {}
                        table.insert(provided[d.id], (tostring(p):match("%((.-)%)")) or m.version or "0.0.0")
                    end
                end
            end
        end
        for _, name in ipairs(mods) do
            local m = not refused[name] and Boot.manifest(name)
            for _, dep in ipairs(m and type(m.dependencies) == "table" and m.dependencies or {}) do
                if type(dep) == "table" then
                    local lo = dep.min_version and (" (>=" .. tostring(dep.min_version) .. ")") or ""
                    local hi = dep.max_version and (" (<=" .. tostring(dep.max_version) .. ")") or ""
                    dep = tostring(dep.id or dep.name or "") .. lo .. hi
                end
                dep = tostring(dep)
                local ok, why = false, nil
                for part in dep:gmatch("[^|]+") do
                    local d = parse_dep(part)
                    if d.id then
                        local b = builtin[d.id]
                        if b == true or (b and version_ok(b, d.checks)) then ok = true break end
                        for _, v in ipairs(provided[d.id] or {}) do
                            if version_ok(v, d.checks) then ok = true break end
                        end
                        if ok then break end
                        if not why then
                            if b or provided[d.id] then why = "a different version is installed"
                            elseif installed[d.id] and enabled[installed[d.id]] and refused[installed[d.id]] then why = "that mod is turned off too"
                            elseif installed[d.id] then why = "that mod is installed but not enabled"
                            else why = "that mod is not installed" end
                        end
                    end
                end
                if not ok then
                    refuse(name, m.name or m.id or name, "needs " .. dep:gsub("^%s+", ""):gsub("%s+$", "") .. ", but " .. (why or "it is missing"))
                    changed = true
                    break
                end
            end
        end
    end
    local keep = {}
    for _, name in ipairs(mods) do
        if not refused[name] then keep[#keep + 1] = name end
    end
    return keep, order
end

local function sync_ignores(folders, enabled)
    for _, name in ipairs(folders) do
        local dir = Boot.root .. "/" .. name
        local ignore = dir .. "/.lovelyignore"
        local want = enabled[name] and not is_steamodded(dir)
        local has = love.filesystem.getInfo(ignore, "file") ~= nil
        if want and has then
            love.filesystem.remove(ignore)
        elseif not want and not has then
            love.filesystem.write(ignore, "")
        end
    end
end

function Boot.build_id()
    local v = love.filesystem.read("version.jkr") or ""
    return v
end

function Boot.start()
    Boot.run_installer()
    pcall(Boot.migrate)
    local modded, after = Boot.read_session()
    Boot.modded = modded or Boot.forced()
    Boot.after_boot = after
    Boot.fast_boot = after ~= nil
    if after then Boot.write_session(modded) end
    local had_crash = love.filesystem.getInfo(Boot.paths().crash) ~= nil
    pcall(Boot.take_crash)
    if Boot.modded and not had_crash and not Boot.forced() then pcall(Boot.check_stall) end
    if Boot.modded then note("modded session") end
    if not Boot.modded then return false end
    local on, mods, folders, list = Boot.wanted()
    if #mods > 0 then
        local refused
        mods, refused = Boot.check(mods, folders, list)
        Boot.refused = refused
        for _, r in ipairs(refused) do note("refused " .. r.name .. ": " .. r.needs) end
        on = #mods > 0 or Boot.forced()
        if not on then sync_ignores(folders, {}) end
    end
    if not on then return false end
    local ok_ls, ls = pcall(require, "functions/loading_screen")
    if ok_ls then
        LOADING_SCREEN = ls
        pcall(ls.draw, "Preparing mods", true)
    end
    local set = {}
    for _, name in ipairs(mods) do set[name] = true end
    sync_ignores(folders, set)
    Boot.enabled = mods
    Boot.enabled_set = set
    pcall(Boot.guard_crashes)
    local paths = Boot.paths()
    love.filesystem.createDirectory(Boot.root .. "/lovely")
    love.filesystem.write(paths.log, "")
    local Engine = require("modloader.lovely")
    Boot.engine = Engine
    Engine.on_warn = function(msg) love.filesystem.append(paths.log, "WARN " .. msg .. "\n") end
    local extra = {}
    if love.filesystem.getInfo(Boot.fork_dir .. "/lovely", "directory") then extra[Boot.fork_name] = Boot.fork_dir end
    local t0 = love.timer and love.timer.getTime() or os.clock()
    Engine.load(Boot.root, {extra = extra, build = Boot.build_id(), enabled = set})
    Engine.use_cache(paths.cache)
    if Boot.aliases then for k, v in pairs(Boot.aliases) do Engine.aliases[k] = v end end
    Engine.install()
    local nfs = require("modloader.nfs")
    package.loaded["SMODS.nativefs"] = nil
    package.loaded.nativefs = nil
    package.preload["SMODS.nativefs"] = function() return nfs end
    package.preload.nativefs = function() return nfs end
    local ffi_ok, ffi = pcall(require, "ffi")
    if ffi_ok and not Boot.ffi_load then
        Boot.ffi_load = ffi.load
        ffi.load = function(name, ...)
            local ok, lib = pcall(Boot.ffi_load, name, ...)
            if ok then return lib end
            if name == "love" then
                return {PHYSFS_mount = function(dir, mount_point, append)
                    return nfs.mount(dir, mount_point, append ~= nil and append ~= 0) and 1 or 0
                end}
            end
            error(lib, 0)
        end
    end
    for _, p in ipairs(Engine.patches) do
        if p.kind == "module" and p.name and type(p.content) == "string"
            and p.content:find("PHYSFS_", 1, true) and p.content:find("megagrump", 1, true) then
            package.loaded[p.name] = nil
            package.preload[p.name] = function() return nfs end
        end
    end
    if not Boot.io_open and love.system and love.system.getOS() == "Android" then
        Boot.io_open = io.open
        local save_dir = (love.filesystem.getSaveDirectory() or ""):gsub("/$", "")
        rawset(io, "open", function(name, mode, ...)
            local f, err, code = Boot.io_open(name, mode, ...)
            if f or type(name) ~= "string" or name == "" or name:sub(1, 1) == "/" or save_dir == "" then return f, err, code end
            local g = Boot.io_open(save_dir .. "/" .. name:gsub("\\", "/"), mode, ...)
            if g then return g end
            return f, err, code
        end)
    end
    Boot.active = true
    pcall(Boot.mark_running, mods)
    Boot.load_seconds = (love.timer and love.timer.getTime() or os.clock()) - t0
    note(string.format("mods on: %s, %d patches, fingerprint %s, load %.3fs",
        #mods > 0 and table.concat(mods, ", ") or "(fork only, MODLOADER_FORK)", #Engine.patches, tostring(Engine.fingerprint), Boot.load_seconds))
    return true
end

function Boot.set_enabled(name, on)
    if not name or name == "" or name == Boot.fork_id then return end
    local list, set = Boot.read_enabled()
    if on and not set[name] then
        list[#list + 1] = name
    elseif not on and set[name] then
        for i = #list, 1, -1 do
            if list[i] == name then table.remove(list, i) end
        end
    else
        return
    end
    Boot.write_enabled(list)
    local dir = Boot.root .. "/" .. name
    if love.filesystem.getInfo(dir, "directory") and not is_steamodded(dir) then
        local ignore = dir .. "/.lovelyignore"
        if on then love.filesystem.remove(ignore) else love.filesystem.write(ignore, "") end
    end
    note((on and "enabled " or "disabled ") .. name)
end

function Boot.is_fork_copy(name)
    return is_steamodded(Boot.root .. "/" .. name)
end

local function remove_tree(path)
    local info = love.filesystem.getInfo(path)
    if not info then return end
    if info.type == "directory" then
        for _, item in ipairs(love.filesystem.getDirectoryItems(path)) do remove_tree(path .. "/" .. item) end
    end
    love.filesystem.remove(path)
end

function Boot.remove_mod(name)
    if not name or name == "" or name:find("[/\\]") or name:sub(1, 1) == "." or name == "lovely" then return false end
    local dir = Boot.root .. "/" .. name
    if not love.filesystem.getInfo(dir, "directory") then return false end
    Boot.set_enabled(name, false)
    remove_tree(dir)
    if Boot._manifests then Boot._manifests[name] = nil end
    note("removed " .. name)
    return love.filesystem.getInfo(dir) == nil
end

function Boot.scan_downloads()
    Boot._manifests = nil
    Boot.run_installer()
    Boot._manifests = nil
    return Boot.installed or {}
end

function Boot.status()
    local on, mods, folders, list = Boot.wanted()
    local keep, refused = mods, {}
    if #mods > 0 then keep, refused = Boot.check(mods, folders, list) end
    local why = {}
    for _, r in ipairs(refused) do why[r.name] = r.needs end
    local want = {}
    for _, name in ipairs(keep) do want[name] = true end
    local loaded = Boot.active and (Boot.enabled_set or {}) or {}
    local _, set = Boot.read_enabled()
    local entries = {}
    for _, name in ipairs(folders) do
        if not is_steamodded(Boot.root .. "/" .. name) then
            local m = Boot.manifest(name) or {}
            local author = m.author
            if type(author) == "table" then author = table.concat(author, ", ") end
            entries[#entries + 1] = {
                folder = name,
                id = m.id,
                name = m.display_name or m.name or name,
                version = m.version,
                author = type(author) == "string" and author ~= "" and author or nil,
                icon_path = m.icon_path,
                icon_width = m.icon_width,
                dir = m._dir or (Boot.root .. "/" .. name),
                prefix = m.prefix,
                enabled = set[name] == true,
                refused = why[name],
                loaded = loaded[name] == true,
            }
        end
    end
    local restart = false
    if not Boot.modded then
        restart = false
    elseif (#keep > 0 or Boot.forced()) ~= Boot.active then
        restart = true
    elseif Boot.active then
        for name in pairs(want) do if not loaded[name] then restart = true end end
        for name in pairs(loaded) do if not want[name] then restart = true end end
    end
    return {mods = entries, restart = restart, active = Boot.active, modded = Boot.modded}
end

Boot.kill_channels = {sound_request = {type = "kill"}, save_request = {type = "kill"}, http_request = {type = "kill"}, load_request = {type = "kill"}, aws_cmd = "QUIT"}
Boot.thread_channels = {"sound_request", "save_request", "http_request", "load_request",
    "load_channel", "save_return", "http_response", "load_return", "aws_cmd", "aws_msg", "aws_status"}

function Boot.stop_threads(timeout)
    for name, msg in pairs(Boot.kill_channels) do love.thread.getChannel(name):push(msg) end
    local deadline = love.timer.getTime() + (timeout or 3)
    local hard = deadline + 12
    local saves = love.thread.getChannel("save_request")
    local running, names
    repeat
        running, names = 0, {}
        for t, label in pairs(Boot.threads) do
            local ok, alive = pcall(t.isRunning, t)
            if not ok then
                Boot.threads[t] = nil
            elseif alive then
                running = running + 1
                names[#names + 1] = tostring(label)
            end
        end
        if running > 0 then love.timer.sleep(0.01) end
    until running == 0 or (love.timer.getTime() > deadline and (love.timer.getTime() > hard or saves:getCount() == 0))
    for _, name in ipairs(Boot.thread_channels) do love.thread.getChannel(name):clear() end
    return running, names
end

local function write_boot_log()
    pcall(love.filesystem.write, Boot.paths().boot_log, table.concat(Boot.log, "\n") .. "\n")
end

function Boot.mark_running(mods)
    local p = Boot.paths()
    local prev = love.filesystem.read(p.running)
    if prev and prev ~= "" then
        note("previous modded session did not quit cleanly (error screen, crash or kill): " .. prev:gsub("%s+$", ""))
        local old = love.filesystem.read(p.exit_log) or ""
        if #old > 20000 then old = old:sub(-10000) end
        love.filesystem.write(p.exit_log, old .. os.date("%Y-%m-%d %H:%M:%S") .. " unclean end of session started " .. prev:gsub("%s+$", "") .. "\n")
    end
    love.filesystem.write(p.running, os.date("%Y-%m-%d %H:%M:%S") .. " mods " .. table.concat(mods or {}, ",") .. "\n")
end

function Boot.check_stall()
    local p = Boot.paths()
    local prev = love.filesystem.read(p.running)
    if not prev or prev == "" or prev:find("\ntitle", 1, true) then return end
    local first = prev:match("^[^\n]*") or ""
    local old = love.filesystem.read(p.exit_log) or ""
    if #old > 20000 then old = old:sub(-10000) end
    love.filesystem.write(p.exit_log, old .. os.date("%Y-%m-%d %H:%M:%S") .. " start never reached the title, session started " .. first .. ", normal game started\n")
    love.filesystem.remove(p.running)
    Boot.write_session(false)
    Boot.modded = false
    local mods = first:match(" mods (.*)$") or ""
    Boot.stall_off = {mods = mods:gsub(",", ", ")}
    note("previous modded start never reached the title (" .. first .. "), starting the normal game")
end

function Boot.clean_exit(reason)
    if not Boot.active then return end
    local p = Boot.paths()
    if reason then
        local old = love.filesystem.read(p.exit_log) or ""
        if #old > 20000 then old = old:sub(-10000) end
        love.filesystem.write(p.exit_log, old .. os.date("%Y-%m-%d %H:%M:%S") .. " " .. reason .. "\n")
    end
    love.filesystem.remove(p.running)
end

local function one_line(s, max)
    s = tostring(s or ""):gsub("[\r\n\t]+", " "):gsub("[^\32-\126]", "?")
    s = trim(s)
    if #s > max then s = s:sub(1, max - 3) .. "..." end
    return s
end

function Boot.blame(text)
    local ids = {}
    for _, name in ipairs(Boot.enabled or {}) do
        local m = Boot.manifest(name)
        if m and m.id then ids[m.id] = name end
    end
    local set = Boot.enabled_set or {}
    local best, best_at
    local function consider(at, name)
        if at and name and set[name] and (not best_at or at < best_at) then best, best_at = name, at end
    end
    local init = 1
    while true do
        local a, _, id = text:find('%[SMODS ([^%s%]]+) "', init)
        if not a then break end
        consider(a, ids[id] or id)
        init = a + 1
    end
    init = 1
    while true do
        local a, _, dir = text:find('%f[%w]mods/([^/%s"%]]+)/', init)
        if not a then break end
        consider(a, dir)
        init = a + 1
    end
    return best
end

function Boot.crash_report(msg, trace, rich, phase, blamed)
    local mods = {}
    for _, name in ipairs(Boot.enabled or {}) do
        local m = Boot.manifest(name)
        mods[#mods + 1] = "  " .. name .. (m and m.version and (" " .. tostring(m.version)) or "")
    end
    local out = {
        "Balatro Overhaul crash report",
        "Date: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "Overhaul version: " .. tostring(rawget(_G, "OVERHAUL_VERSION") or "?"),
        "Game build: " .. one_line(Boot.build_id(), 80),
        "Platform: " .. tostring(love.system and love.system.getOS() or "?"),
        "Session: " .. (Boot.modded and "modded" or "normal"),
        "Steamodded: " .. (Boot.modded and tostring(rawget(_G, "MODDED_VERSION") or fork_version() or "?") or "not loaded"),
        "Phase: " .. phase .. (phase ~= "boot" and " s after the title" or ""),
        "Blamed mod: " .. (blamed ~= "" and blamed or "none"),
        "Enabled mods:",
        #mods > 0 and table.concat(mods, "\n") or "  (none)",
        "",
        "Error:",
        tostring(msg),
        "",
        rich or ("Traceback:" .. tostring(trace or "")),
    }
    local info = rawget(_G, "getDebugInfoForCrash")
    if type(info) == "function" then
        local ok, r = pcall(info)
        if ok and r then out[#out + 1] = "\n" .. tostring(r) end
    end
    return table.concat(out, "\n")
end

function Boot.record_crash(msg, trace, rich)
    if Boot.crash_recorded or not Boot.modded then return end
    Boot.crash_recorded = true
    local now = love.timer and love.timer.getTime() or os.clock()
    local phase = Boot.t_menu and string.format("%.1f", now - Boot.t_menu) or "boot"
    local text = tostring(msg) .. "\n" .. tostring(trace or "")
    local blamed = Boot.blame(text) or ""
    note("crash (" .. phase .. ")" .. (blamed ~= "" and (", blamed on " .. blamed) or "") .. ": " .. one_line(msg, 200))
    love.filesystem.createDirectory(Boot.root)
    love.filesystem.write(Boot.paths().crash, table.concat({
        phase, blamed, table.concat(Boot.enabled or {}, ","), os.date("%Y-%m-%d %H:%M:%S"), one_line(msg, 400), tostring(trace or ""),
    }, "\n"))
    local ok, report = pcall(Boot.crash_report, msg, trace, rich, phase, blamed)
    report = ok and report or (tostring(msg) .. "\n" .. tostring(trace or ""))
    love.filesystem.write(Boot.paths().last_crash, report)
    pcall(Boot.save_pending_report, report)
    write_boot_log()
end

Boot.PENDING_REPORT = "crash_reports/pending.txt"

function Boot.save_pending_report(report)
    if Boot.pending_written then return end
    Boot.pending_written = true
    love.filesystem.createDirectory("crash_reports")
    love.filesystem.write(Boot.PENDING_REPORT, tostring(report):sub(1, 60000))
    love.filesystem.remove("crash_reports/attempts.txt")
end

function Boot.record_plain_crash(msg, trace)
    if Boot.pending_written then return end
    local now = love.timer and love.timer.getTime() or os.clock()
    local phase = Boot.t_menu and string.format("%.1f", now - Boot.t_menu) or "boot"
    local ok, report = pcall(Boot.crash_report, msg, trace, nil, phase, "")
    Boot.save_pending_report(ok and report or (tostring(msg) .. "\n" .. tostring(trace or "")))
end

function Boot.guard_crashes()
    if Boot.guarding or getmetatable(love) then return end
    Boot.guarding = true
    local held = {errorhandler = rawget(love, "errorhandler"), errhand = rawget(love, "errhand")}
    rawset(love, "errorhandler", nil)
    rawset(love, "errhand", nil)
    local function wrapper(msg, ...)
        local rich
        local stp = rawget(_G, "loadStackTracePlus")
        if type(stp) == "function" then
            local ok, r = pcall(function() return stp().stacktrace("", 3) end)
            if ok and type(r) == "string" then rich = r end
        end
        pcall(Boot.record_crash, msg, debug.traceback("", 2), rich)
        local h = held.errorhandler or held.errhand
        if h then return h(msg, ...) end
        print(debug.traceback(tostring(msg), 2))
    end
    setmetatable(love, {
        __index = function(_, k)
            if k == "errorhandler" then return wrapper end
            if k == "errhand" then return held.errhand end
        end,
        __newindex = function(t, k, v)
            if k == "errorhandler" or k == "errhand" then held[k] = v else rawset(t, k, v) end
        end,
    })
end

function Boot.take_crash()
    local p = Boot.paths()
    local data = love.filesystem.read(p.crash)
    if not data then return end
    local info, last = love.filesystem.getInfo(p.crash), love.filesystem.getInfo(p.last_crash)
    love.filesystem.remove(p.crash)
    if not last or not info or (last.modtime or 0) < (info.modtime or 0) then love.filesystem.write(p.last_crash, data) end
    if not Boot.modded then return end
    local lines = {}
    for line in (data .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
        if #lines >= 5 then break end
    end
    local phase, blamed, msg = lines[1], lines[2] or "", lines[5] or ""
    local secs = tonumber(phase)
    if phase ~= "boot" and not (secs and secs <= 20) then return end
    local _, set = Boot.read_enabled()
    if blamed ~= "" and set[blamed] then
        Boot.set_enabled(blamed, false)
        local m = Boot.manifest(blamed)
        Boot.crash_off = {name = blamed, mod = m and m.name or blamed, err = msg}
        love.filesystem.remove(p.boot_crashes)
        return
    end
    if phase ~= "boot" then return end
    local count = (tonumber(love.filesystem.read(p.boot_crashes) or "") or 0) + 1
    if count < 2 then
        love.filesystem.write(p.boot_crashes, tostring(count))
        return
    end
    love.filesystem.remove(p.boot_crashes)
    Boot.write_session(false)
    Boot.modded = false
    Boot.crash_fallback = {err = msg}
    note("modded game crashed twice at start without a clear culprit, starting the normal game")
end

function Boot.switch(modded, after)
    if Boot.restarting then return true end
    Boot.write_session(modded, after or "title")
    note((modded and "switching to the modded profile" or "switching to the normal profile") .. (after and (", then " .. after) or ""))
    return Boot.restart()
end

function Boot.restart()
    if Boot.restarting then return true end
    Boot.restarting = true
    note("restarting")
    local prev = love.quit
    love.quit = function(...)
        if prev then
            local abort = prev(...)
            if abort then
                love.quit = prev
                Boot.restarting = nil
                return abort
            end
        end
        local running, names = Boot.stop_threads(3)
        if running > 0 then
            note(running .. " thread(s) did not stop (" .. table.concat(names, ", ") .. "), quitting instead of restarting")
            pcall(Boot.clean_exit, "restart refused, threads still running: " .. table.concat(names, ", "))
            write_boot_log()
            love.quit = prev
            love.event.quit()
            return true
        end
        pcall(Boot.clean_exit)
        write_boot_log()
        return false
    end
    write_boot_log()
    love.event.quit("restart")
    return true
end

function Boot.show_notice()
    if not Boot.t_menu then
        Boot.t_menu = love.timer and love.timer.getTime() or os.clock()
        if Boot.modded then
            pcall(love.filesystem.remove, Boot.paths().boot_crashes)
            pcall(love.filesystem.append, Boot.paths().running, "title\n")
        end
    end
    if Boot.notice_shown or (#Boot.refused == 0 and not Boot.crash_off and not Boot.crash_fallback and not Boot.stall_off) then return end
    local G = rawget(_G, "G")
    if not (G and G.FUNCS and G.FUNCS.overlay_menu and rawget(_G, "create_UIBox_generic_options")) then return end
    Boot.notice_shown = true
    local crash = Boot.crash_off or Boot.crash_fallback
    local count = #Boot.refused + (Boot.crash_off and 1 or 0)
    local title = Boot.stall_off and "The modded game did not finish starting"
        or Boot.crash_fallback and "The modded game crashed at start"
        or count == 1 and "A mod was turned off" or "Some mods were turned off"
    local rows = {
        {n = G.UIT.R, config = {align = "cm", padding = 0.1}, nodes = {
            {n = G.UIT.T, config = {text = title, scale = 0.6, colour = G.C.WHITE, shadow = true}},
        }},
    }
    if crash then
        if Boot.crash_off then
            rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
                {n = G.UIT.T, config = {text = Boot.crash_off.mod, scale = 0.5, colour = G.C.GOLD, shadow = true}},
            }}
            rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
                {n = G.UIT.T, config = {text = "It crashed the game at start:", scale = 0.4, colour = G.C.UI.TEXT_LIGHT}},
            }}
        end
        rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
            {n = G.UIT.T, config = {text = one_line(crash.err, 70), scale = 0.32, colour = G.C.RED}},
        }}
        if Boot.crash_fallback then
            rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.1}, nodes = {
                {n = G.UIT.T, config = {text = "The normal game was started instead.", scale = 0.35, colour = G.C.UI.TEXT_LIGHT}},
            }}
        end
    end
    if Boot.stall_off then
        if Boot.stall_off.mods ~= "" then
            rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
                {n = G.UIT.T, config = {text = one_line(Boot.stall_off.mods, 70), scale = 0.45, colour = G.C.GOLD, shadow = true}},
            }}
        end
        rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
            {n = G.UIT.T, config = {text = "The last start with these mods was closed before the menu.", scale = 0.35, colour = G.C.UI.TEXT_LIGHT}},
        }}
        rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
            {n = G.UIT.T, config = {text = "The normal game was started instead. Open Mods to try again", scale = 0.35, colour = G.C.UI.TEXT_LIGHT}},
        }}
        rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
            {n = G.UIT.T, config = {text = "or to turn a mod off.", scale = 0.35, colour = G.C.UI.TEXT_LIGHT}},
        }}
    end
    for _, r in ipairs(Boot.refused) do
        rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
            {n = G.UIT.T, config = {text = r.mod or r.name, scale = 0.5, colour = G.C.GOLD, shadow = true}},
        }}
        rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
            {n = G.UIT.T, config = {text = "It " .. r.needs .. ".", scale = 0.4, colour = G.C.UI.TEXT_LIGHT}},
        }}
    end
    if not Boot.crash_fallback and not Boot.stall_off then
        rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.1}, nodes = {
            {n = G.UIT.T, config = {text = count == 1 and "The game started without it." or "The game started without them.", scale = 0.35, colour = G.C.UI.TEXT_LIGHT}},
        }}
    end
    G.FUNCS.overlay_menu({definition = create_UIBox_generic_options({contents = {
        {n = G.UIT.C, config = {align = "cm", padding = 0.1}, nodes = rows},
    }})})
end

function Boot.track_threads()
    if Boot.tracking then return end
    if not love.thread then pcall(require, "love.thread") end
    local raw_new_thread = love.thread and love.thread.newThread
    if not raw_new_thread then return end
    Boot.tracking = true
    love.thread.newThread = function(src, ...)
        local t = raw_new_thread(src, ...)
        if t then
            local label = type(src) == "string" and not src:find("\n") and src
                or (type(src) == "userdata" and src.getFilename and src:getFilename())
                or (type(src) == "string" and (src:match("^%s*([^\n]*)") or ""):sub(1, 40))
                or tostring(src)
            Boot.threads[t] = label
        end
        return t
    end
end

function Boot.hook()
    local fired = false
    local loaders = package.loaders or package.searchers
    table.insert(loaders, 1, function(name)
        if fired or name ~= "main" then return nil end
        fired = true
        Boot.t_hook = love.timer and love.timer.getTime() or nil
        pcall(Boot.track_threads)
        local alias = os.getenv("MODLOADER_MAIN_ALIAS")
        if alias and alias ~= "" then Boot.aliases = {[alias] = "main.lua", ["main.lua"] = "\0"} end
        local ok, err = pcall(Boot.start)
        if not ok then
            note("boot failed: " .. tostring(err))
            if Boot.engine and Boot.engine.installed then error(err, 0) end
        end
        Boot.t_ready = love.timer and love.timer.getTime() or nil
        if Boot.t_hook and Boot.t_ready then note(string.format("boot %.3fs", Boot.t_ready - Boot.t_hook)) end
        write_boot_log()
        return nil
    end)
end

MODLOADER = Boot

return Boot
