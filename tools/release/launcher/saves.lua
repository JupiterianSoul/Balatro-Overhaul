local SIO = require("save_io")
local C = require("core")

local V = {}

V.APPID = "2379780"
V.BACKUPS = "backups"
V.EXPORTS = "exports"
V.KEEP = 20
V.PHONE_SKIP = {overhaul_game = true, ["overhaul_game.new"] = true, update = true, vanilla = true, launcher = true, patch = true, android = true, carry = true}
V.PHONE_FILES = {["official.zip"] = true, ["launcher_settings.lua"] = true, ["launcher_play"] = true, ["BalatroOverhaul.apk"] = true,
    ["BalatroOverhaul.apk.part"] = true, ["app_info.txt"] = true, ["carry_done"] = true, ["direct_play"] = true,
    ["app_icon.png"] = true, ["app_icon.ico"] = true, ["app_pending"] = true}

function V.supported()
    if C.PHONE then
        return true
    end
    local osn = C.os()
    return osn ~= "Android" and osn ~= "iOS"
end

function V.overhaul_identity()
    if not love.filesystem.isFused() then
        return C.GAME_FOLDER
    end
    return (C.os() == "Linux" and "love/" or "LOVE/") .. C.GAME_FOLDER
end

function V.with_overhaul(fn)
    if C.PHONE then
        local ok, a, b = pcall(fn, love.filesystem)
        if not ok then
            print("launcher: overhaul save: " .. tostring(a))
            return nil, "write"
        end
        return a, b
    end
    local id = love.filesystem.getIdentity()
    local ok, a, b = pcall(function()
        love.filesystem.setIdentity(V.overhaul_identity())
        return fn(love.filesystem)
    end)
    love.filesystem.setIdentity(id)
    if not ok then
        print("launcher: overhaul save: " .. tostring(a))
        return nil, "write"
    end
    return a, b
end

local function norm(p)
    return (p:gsub("\\", "/"):gsub("/+$", ""))
end

function V.candidates(games)
    local list, seen = {}, {}
    local function add(path, where)
        if not path or path == "" then
            return
        end
        path = norm(path)
        if not seen[path] then
            seen[path] = true
            list[#list + 1] = {path = path, where = where}
        end
    end
    local env = os.getenv("OVERHAUL_BALATRO_SAVES")
    if env and env ~= "" then
        for p in env:gmatch("[^;]+") do
            add(p, "steam")
        end
    end
    if C.PHONE or os.getenv("OVERHAUL_NO_SCAN") == "1" or os.getenv("OVERHAUL_NO_SAVE_SCAN") == "1" then
        return list
    end
    local osn = C.os()
    local home = os.getenv("HOME") or ""
    if osn == "Windows" then
        add(os.getenv("APPDATA") and os.getenv("APPDATA") .. "/Balatro", "steam")
    elseif osn == "OS X" then
        add(home .. "/Library/Application Support/Balatro", "steam")
    elseif home ~= "" then
        local roots = {}
        for _, g in ipairs(games or {}) do
            local r = norm(g.path or ""):match("^(.*)/steamapps/common/")
            if r then
                roots[#roots + 1] = r
            end
        end
        for _, r in ipairs({"/.local/share/Steam", "/.steam/steam", "/.steam/root", "/.var/app/com.valvesoftware.Steam/.local/share/Steam",
            "/snap/steam/common/.local/share/Steam"}) do
            roots[#roots + 1] = home .. r
        end
        for _, r in ipairs(roots) do
            add(r .. "/steamapps/compatdata/" .. V.APPID .. "/pfx/drive_c/users/steamuser/AppData/Roaming/Balatro", "steam")
        end
        local xdg = os.getenv("XDG_DATA_HOME")
        xdg = (xdg and xdg ~= "") and xdg or (home .. "/.local/share")
        add(xdg .. "/Balatro", "local")
        add(xdg .. "/love/Balatro", "local")
    end
    return list
end

function V.read_folder(dir)
    local files, n = {}, 0
    for _, slot in ipairs(SIO.SLOTS) do
        for _, f in ipairs(SIO.VANILLA_FILES) do
            local data = C.read_file(dir .. "/" .. slot .. "/" .. f)
            if data and #data > 0 then
                files[slot .. "/" .. f] = data
                n = n + 1
            end
        end
    end
    if n == 0 then
        return nil, "no_profile"
    end
    local ok, err = SIO.check(files)
    if not ok then
        return nil, err
    end
    return files
end

function V.find(games)
    local out = {}
    for _, c in ipairs(V.candidates(games)) do
        local files = V.read_folder(c.path)
        if files then
            c.files = files
            c.info = SIO.describe(files)
            out[#out + 1] = c
        end
    end
    return out
end

local function keep_settings(name)
    return SIO.skip(name) and not SIO.SKIP_FILES[name]
end

local function phone_skip(base)
    return function(name)
        local top = name:match("^([^/]+)/")
        if (top and V.PHONE_SKIP[top]) or V.PHONE_FILES[name] then
            return true
        end
        return base(name)
    end
end

function V.overhaul_files(full)
    local skip = full and keep_settings or SIO.skip
    if C.PHONE then
        skip = phone_skip(skip)
    end
    return V.with_overhaul(function(fs)
        return SIO.collect(fs, "", skip)
    end)
end

function V.overhaul_info()
    local files = V.with_overhaul(function(fs)
        local out = {}
        for _, slot in ipairs(SIO.SLOTS) do
            for _, f in ipairs({"profile.jkr", "meta.jkr"}) do
                local name = slot .. "/" .. f
                if fs.getInfo(name) then
                    out[name] = fs.read(name)
                end
            end
        end
        return out
    end) or {}
    return SIO.describe(files)
end

function V.backup(kind, files)
    if not files or not next(files) then
        return true
    end
    love.filesystem.createDirectory(V.BACKUPS)
    local name = V.BACKUPS .. "/" .. kind .. "-" .. SIO.stamp() .. ".zip"
    local ok = love.filesystem.write(name, SIO.zip(SIO.entries(files)))
    SIO.prune(love.filesystem, V.BACKUPS, V.KEEP)
    return ok and name or nil
end

function V.load(files, kind)
    local ok, err = SIO.check(files)
    if not ok then
        return nil, err
    end
    if kind == "balatro" and not V.backup("balatro", files) then
        return nil, "backup"
    end
    local current = V.overhaul_files(true)
    if current and next(current) and not V.backup("overhaul", current) then
        return nil, "backup"
    end
    local wrote, werr = V.with_overhaul(function(fs)
        return SIO.apply(fs, files)
    end)
    if not wrote then
        return nil, werr or "write"
    end
    return wrote
end

function V.export()
    local files = V.overhaul_files(false)
    if not files or not SIO.check(files) then
        return nil, "empty"
    end
    love.filesystem.createDirectory(V.EXPORTS)
    local name = V.EXPORTS .. "/Overhaul-save-" .. SIO.stamp() .. ".zip"
    local data = SIO.zip(SIO.entries(files))
    if not love.filesystem.write(name, data) then
        return nil, "write"
    end
    local shared = C.export_dir and C.export_dir()
    if shared then
        local path = shared .. "/" .. name:match("[^/]+$")
        local f = io.open(path, "wb")
        if f then
            local ok = f:write(data)
            f:close()
            if ok then
                return path
            end
        end
    end
    return love.filesystem.getSaveDirectory() .. "/" .. name
end

function V.read_import(path)
    path = norm(C.clean_path and C.clean_path(path) or path)
    local data = C.read_file(path)
    if data and data:sub(1, 2) == "PK" then
        local raw, err = SIO.unzip(data)
        if not raw then
            return nil, err
        end
        local files, nerr = SIO.normalize(raw)
        if not files then
            return nil, nerr
        end
        local ok, cerr = SIO.check(files)
        if not ok then
            return nil, cerr
        end
        return files
    elseif data then
        return nil, "not_zip"
    end
    local files = V.read_folder(path)
    if files then
        return files
    end
    local parent = path:match("^(.*)/[123]$")
    if parent then
        return V.read_folder(parent)
    end
    return nil, "no_profile"
end

function V.is_save_path(path)
    path = norm(path or "")
    local low = path:lower()
    if low:match("%.zip$") then
        return true
    end
    return V.read_folder(path) ~= nil or (path:match("/[123]$") and V.read_folder(path:match("^(.*)/[123]$")) ~= nil) or false
end

function V.open_folder(sub)
    love.filesystem.createDirectory(sub)
    if C.PHONE then
        return
    end
    love.system.openURL("file://" .. love.filesystem.getSaveDirectory() .. "/" .. sub)
end

return V
