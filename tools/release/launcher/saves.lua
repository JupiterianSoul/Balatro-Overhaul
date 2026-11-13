local SIO = require("save_io")
local C = require("core")

local V = {}

V.APPID = "2379780"
V.BACKUPS = "backups"
V.EXPORTS = "exports"
V.PHONE_SKIP = {overhaul_game = true, ["overhaul_game.new"] = true, update = true, vanilla = true, launcher = true, patch = true, android = true, carry = true}
V.PHONE_FILES = {["official.zip"] = true, ["launcher_settings.lua"] = true, ["launcher_play"] = true, ["BalatroOverhaul.apk"] = true,
    ["BalatroOverhaul.apk.part"] = true, ["app_info.txt"] = true, ["carry_done"] = true, ["direct_play"] = true,
    ["app_icon.png"] = true, ["app_icon.ico"] = true, ["app_pending"] = true, ["import_pending"] = true}

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
    return SIO.validate(files)
end

local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    if not d then
        return nil
    end
    return a + b * 256 + c * 65536 + d * 16777216
end

local function utf16(s, i, n)
    if n < 0 or n > 1024 or i + n * 2 - 1 > #s then
        return nil
    end
    local out = {}
    for k = 0, n - 1 do
        local a, b = s:byte(i + k * 2, i + k * 2 + 1)
        local c = a + b * 256
        if c == 0 then
            break
        elseif c < 0x80 then
            out[#out + 1] = string.char(c)
        elseif c < 0x800 then
            out[#out + 1] = string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64)
        else
            out[#out + 1] = string.char(0xE0 + math.floor(c / 4096), 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64)
        end
    end
    return table.concat(out)
end

local function wstr(s, p)
    local n = u32(s, p)
    if not n then
        return nil
    end
    local str = utf16(s, p + 4, n)
    if not str then
        return nil
    end
    return str, p + 4 + n * 2
end

function V.guid_hex(b)
    if type(b) ~= "string" or #b ~= 16 then
        return nil
    end
    local order = {4, 3, 2, 1, 6, 5, 8, 7, 9, 10, 11, 12, 13, 14, 15, 16}
    local out = {}
    for i, k in ipairs(order) do
        out[i] = string.format("%02X", b:byte(k))
    end
    return table.concat(out)
end

function V.xbox_index(data)
    if type(data) ~= "string" or #data < 12 then
        return nil, "damaged"
    end
    local count = u32(data, 5)
    if not count or count > 4096 then
        return nil, "damaged"
    end
    local p = 13
    local _
    _, p = wstr(data, p)
    if not p then
        return nil, "damaged"
    end
    p = p + 12
    _, p = wstr(data, p)
    if not p then
        return nil, "damaged"
    end
    p = p + 8
    local list = {}
    for _ = 1, count do
        local name, name2, num
        name, p = wstr(data, p)
        if not p then
            return nil, "damaged"
        end
        name2, p = wstr(data, p)
        if not p then
            return nil, "damaged"
        end
        _, p = wstr(data, p)
        if not p or p + 44 > #data then
            return nil, "damaged"
        end
        num = data:byte(p)
        local guid = V.guid_hex(data:sub(p + 5, p + 20))
        p = p + 21 + 8 + 16
        list[#list + 1] = {name = name, name2 = name2, number = num, guid = guid}
    end
    return list
end

function V.xbox_container(data)
    if type(data) ~= "string" or #data < 8 then
        return nil, "damaged"
    end
    local count = u32(data, 5)
    if not count or count > 1024 or 8 + count * 160 > #data then
        return nil, "damaged"
    end
    local list = {}
    for i = 0, count - 1 do
        local p = 9 + i * 160
        local name = utf16(data, p, 64)
        local g1 = V.guid_hex(data:sub(p + 128, p + 143))
        local g2 = V.guid_hex(data:sub(p + 144, p + 159))
        list[#list + 1] = {name = name or "", guid = (g1 == g2) and g1 or g2}
    end
    return list
end

local VANILLA = {}
for _, f in ipairs(SIO.VANILLA_FILES) do
    VANILLA[f] = true
end

local function xbox_name(cname, fname)
    for _, n in ipairs({cname .. "/" .. fname, fname, cname, cname .. "/" .. fname .. ".jkr", fname .. ".jkr"}) do
        local slot, f = n:match("^([123])/([%w_]+%.jkr)$")
        if slot and VANILLA[f] then
            return slot .. "/" .. f
        end
    end
end

function V.xbox_read(dir, read)
    read = read or C.read_file
    local list, err = V.xbox_index(read(dir .. "/containers.index"))
    if not list then
        return nil, err
    end
    local files, n = {}, 0
    for _, c in ipairs(list) do
        if c.guid and c.number then
            local inner = V.xbox_container(read(dir .. "/" .. c.guid .. "/container." .. c.number))
            for _, f in ipairs(inner or {}) do
                local name = f.guid and xbox_name(c.name or "", f.name)
                if name and not files[name] then
                    local data = read(dir .. "/" .. c.guid .. "/" .. f.guid)
                    if data and #data > 0 and #data <= SIO.MAX_FILE then
                        files[name] = data
                        n = n + 1
                    end
                end
            end
        end
    end
    if n == 0 then
        return nil, "no_profile"
    end
    local ok, cerr = SIO.check(files)
    if not ok then
        return nil, cerr
    end
    return files
end

function V.xbox_dirs()
    local out = {}
    local env = os.getenv("OVERHAUL_XBOX_SAVES")
    if env and env ~= "" then
        for p in env:gmatch("[^;]+") do
            out[#out + 1] = norm(p)
        end
    end
    if C.PHONE or os.getenv("OVERHAUL_NO_SCAN") == "1" or os.getenv("OVERHAUL_NO_SAVE_SCAN") == "1" or C.os() ~= "Windows" then
        return out
    end
    local la = os.getenv("LOCALAPPDATA")
    if not la or la == "" or not C.list_dir then
        return out
    end
    local pk = norm(la) .. "/Packages"
    for _, name in ipairs(C.list_dir(pk .. "/*") or {}) do
        if name:lower():match("^playstack%.balatro_") then
            local wgs = pk .. "/" .. name .. "/SystemAppData/wgs"
            for _, user in ipairs(C.list_dir(wgs .. "/*") or {}) do
                local d = wgs .. "/" .. user
                if C.read_file(d .. "/containers.index") then
                    out[#out + 1] = d
                end
            end
        end
    end
    return out
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
    for _, d in ipairs(V.xbox_dirs()) do
        local files = V.xbox_read(d)
        if files then
            out[#out + 1] = {path = d, where = "xbox", files = files, info = SIO.describe(files)}
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
    return SIO.backup(love.filesystem, V.BACKUPS, kind, files)
end

local function pid_alive(pid)
    if C.os() ~= "Linux" or C.PHONE then
        return nil
    end
    local f = io.open("/proc/" .. pid .. "/stat", "rb")
    if f then
        f:close()
        return true
    end
    local d = io.open("/proc/self/stat", "rb")
    if d then
        d:close()
        return false
    end
    return nil
end

function V.running()
    if C.PHONE then
        return false
    end
    local text = V.with_overhaul(function(fs)
        return fs.getInfo(SIO.LOCK) and fs.read(SIO.LOCK) or nil
    end)
    return SIO.lock_alive(text, os.time(), pid_alive)
end

function V.load(files, kind)
    local valid, err = SIO.validate(files or {})
    if not valid then
        return nil, err
    end
    files = SIO.mirror_modded(valid)
    if V.running() then
        return nil, "running"
    end
    if (kind == "balatro" or kind == "xbox") and not V.backup(kind, files) then
        return nil, "backup"
    end
    local current = V.overhaul_files(true) or {}
    local backed = V.with_overhaul(function(fs)
        return SIO.with_touched(fs, files, current)
    end)
    if not backed then
        return nil, "backup"
    end
    if next(backed) and not V.backup("overhaul", backed) then
        return nil, "backup"
    end
    local wrote, werr = V.with_overhaul(function(fs)
        return SIO.apply(fs, files, backed)
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
    local name = V.EXPORTS .. "/" .. SIO.export_name()
    local data = SIO.zip(SIO.entries(files))
    if not love.filesystem.write(name, data) then
        return nil, "write"
    end
    return love.filesystem.getSaveDirectory() .. "/" .. name
end

local function too_big(path)
    local f = io.open(path, "rb")
    if not f then
        return false
    end
    local size = f:seek("end")
    f:close()
    return size and size > SIO.MAX_TOTAL
end

function V.read_import(path)
    path = norm(C.clean_path and C.clean_path(path) or path)
    if too_big(path) then
        return nil, "too_big"
    end
    local root = path:lower():match("%.jkr$") and path:match("^(.*)/[123]/[^/]+$")
    if root then
        local files, dropped = V.read_folder(root)
        if files then
            return files, nil, {dropped = dropped}
        end
    end
    local data = C.read_file(path)
    if data then
        return SIO.read_any(data, path)
    end
    local files, dropped = V.read_folder(path)
    if files then
        return files, nil, {dropped = dropped}
    end
    local parent = path:match("^(.*)/[123]$")
    if parent then
        files, dropped = V.read_folder(parent)
        if files then
            return files, nil, {dropped = dropped}
        end
        return nil, dropped
    end
    return nil, "no_profile"
end

function V.is_save_path(path)
    path = norm(path or "")
    local low = path:lower()
    if low:match("%.zip$") or low:match("%.jkr$") then
        return true
    end
    return V.read_folder(path) ~= nil or (path:match("/[123]$") and V.read_folder(path:match("^(.*)/[123]$")) ~= nil) or false
end

function V.export_to(src)
    if not src or src.where ~= "steam" and src.where ~= "local" then
        return nil, "read_only"
    end
    local dir = src.path
    local mine = V.with_overhaul(function(fs)
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
    local send, n = {}, 0
    for name, data in pairs(mine) do
        local slot = name:match("^(%d)/")
        if data and #data > 0 and (C.read_file(dir .. "/" .. slot .. "/profile.jkr") or C.read_file(dir .. "/" .. slot .. "/meta.jkr")) then
            send[name] = data
            n = n + 1
        end
    end
    if n == 0 or not SIO.check(send) then
        return nil, "empty"
    end
    local old = {}
    for _, slot in ipairs(SIO.SLOTS) do
        for _, f in ipairs({"profile.jkr", "meta.jkr", "unlock_notify.jkr", "save.jkr"}) do
            local data = C.read_file(dir .. "/" .. slot .. "/" .. f)
            if data then
                old[slot .. "/" .. f] = data
            end
        end
    end
    if next(old) and not V.backup(src.where == "local" and "local-before-export" or "steam-before-export", old) then
        return nil, "backup"
    end
    for _, e in ipairs(SIO.entries(send)) do
        local dest = dir .. "/" .. e.name
        local tmp = dest .. ".overhaul-new"
        local f = io.open(tmp, "wb")
        if not f then
            return nil, "write"
        end
        local okw = f:write(e.data)
        f:close()
        if not okw or C.read_file(tmp) ~= e.data then
            os.remove(tmp)
            return nil, "write"
        end
        if not os.rename(tmp, dest) then
            local prev = C.read_file(dest)
            local g = io.open(dest, "wb")
            local okd = g and g:write(e.data)
            if g then g:close() end
            os.remove(tmp)
            if not okd or C.read_file(dest) ~= e.data then
                if prev then
                    local r = io.open(dest, "wb")
                    if r then
                        r:write(prev)
                        r:close()
                    end
                end
                return nil, "write"
            end
        end
    end
    return n
end

V.pick_command = SIO.pick_command
V.save_command = SIO.save_command
V.PICK_THREAD = SIO.DIALOG_THREAD
V.pick_poll = SIO.dialog_poll

local function dialog(cmd)
    if C.PHONE or not SIO.dialog_osn(C.os()) then
        return nil
    end
    return SIO.dialog_start(cmd)
end

function V.pick_start(title)
    return dialog(SIO.pick_command(C.os(), title))
end

function V.save_start(title, name)
    return dialog(SIO.save_command(C.os(), title, name))
end

function V.copy_out(src, dest)
    local data = C.read_file(src)
    return data and SIO.write_file(dest, data) or nil
end

V.APP_DIR = "app_saves"
V.APP_RESULT = "app_saves_result.txt"

function V.app_supported()
    return C.PHONE == true and type(C.bridge) == "function"
end

local function app_prepare(clear)
    local fs = love.filesystem
    fs.remove(V.APP_RESULT)
    fs.createDirectory(V.APP_DIR)
    if clear then
        for _, f in ipairs(fs.getDirectoryItems(V.APP_DIR)) do
            fs.remove(V.APP_DIR .. "/" .. f)
        end
    end
    return fs.getSaveDirectory()
end

function V.app_start(mode, token, name)
    if not V.app_supported() then
        return false
    end
    local base = app_prepare(mode == "import")
    return C.bridge("appsave", table.concat({mode, C.APP, base .. "/" .. V.APP_RESULT, base .. "/" .. V.APP_DIR,
        tostring(token or ""), tostring(name or "")}, "|"))
end

function V.pick_phone()
    if not V.app_supported() then
        return false
    end
    local base = app_prepare(true)
    return C.bridge("pick", table.concat({"zip", base .. "/" .. V.APP_DIR, base .. "/" .. V.APP_RESULT, "zip,jkr", tostring(SIO.MAX_TOTAL)}, "|"))
end

function V.app_result()
    local data = love.filesystem.read(V.APP_RESULT)
    if not data then
        return nil
    end
    love.filesystem.remove(V.APP_RESULT)
    local res = {status = data:match("^(%a+)") or "error", file = data:match("\n%+([^\r\n]+)"),
        token = data:match("\n#(%x+)"), name = data:match("\n@([^\r\n]+)")}
    if res.status == "ok" and not res.file and not res.name then
        if data:match("\n>") then
            res.status = "big"
        elseif data:match("\n%-") then
            res.status = "wrong"
        elseif data:match("\n=") then
            res.file = data:match("\n=([^\r\n]+)")
        end
    end
    return res
end

function V.open_folder(sub)
    love.filesystem.createDirectory(sub)
    if C.PHONE then
        return
    end
    love.system.openURL("file://" .. love.filesystem.getSaveDirectory() .. "/" .. sub)
end

return V
