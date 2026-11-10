local A = require("patcher.apply")
local I = require("overhaul_install")

local C = {}

C.PHONE = true
C.GAME_FOLDER = I.GAME_DIR
C.SETTINGS = "launcher_settings.lua"
C.SERVER = "https://balatro-overhaul-muliplayer.onrender.com"
C.NOTES_URL = C.SERVER .. "/release/feed.json"
C.root = "patch"
C.APP = "com.jupiteriansoul.balatrooverhaul"
C.OFFICIAL = "com.playstack.balatro.android"
C.APP_APK = "BalatroOverhaul.apk"
C.APP_INFO = "app_info.txt"

local function hex(s)
    return love.data.encode("string", "hex", s)
end

function C.sha256(s)
    return hex(love.data.hash("sha256", s))
end

local function load_table(name)
    local src = love.filesystem.read(name)
    if not src then
        return nil
    end
    local chunk = loadstring(src, "=" .. name)
    if not chunk then
        return nil
    end
    setfenv(chunk, {})
    local ok, t = pcall(chunk)
    return ok and type(t) == "table" and t or nil
end

local function ser(v)
    if type(v) == "string" then
        return string.format("%q", v)
    elseif type(v) == "table" then
        local parts = {}
        for k, x in pairs(v) do
            parts[#parts + 1] = "[" .. ser(k) .. "]=" .. ser(x)
        end
        table.sort(parts)
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(v)
end

local function save_table(name, t)
    return love.filesystem.write(name, "return " .. ser(t) .. "\n")
end

C.load_table, C.save_table = load_table, save_table

function C.settings()
    C._settings = C._settings or load_table(C.SETTINGS) or {}
    return C._settings
end

function C.save_settings()
    save_table(C.SETTINGS, C.settings())
end

function C.os()
    return love.system.getOS()
end

function C.plan()
    C._plan = C._plan or I.plan()
    return C._plan
end

function C.refresh()
    C._plan, C._bundled = nil, nil
end

local function bundled()
    if C._bundled == nil then
        C._bundled = A.load_manifest(love.filesystem.read("patch/manifest.lua") or "") or false
    end
    return C._bundled or nil
end

local function installed_info(have)
    return {
        overhaul_version = have.version,
        overhaul_name = have.name or I.installed_name(),
        game_version = have.vanilla ~= "" and have.vanilla or nil,
    }
end

function C.manifest()
    local plan = C.plan()
    if plan.want then
        return plan.want.man
    elseif plan.have then
        return installed_info(plan.have)
    end
    return bundled()
end

function C.stamp()
    local have = I.installed()
    if not have then
        return nil
    end
    local info = love.filesystem.getInfo(I.MARKER)
    local st = installed_info(have)
    st.time = info and info.modtime or 0
    st.patch = have.id
    return st
end

local function u16(s, i)
    local a, b = s:byte(i, i + 1)
    return a + b * 256
end

local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

function C.open_apk(path, prefix)
    prefix = prefix or "assets/"
    local f = io.open(path, "rb")
    if not f then
        return nil, "open"
    end
    local size = f:seek("end")
    local tail_len = math.min(size, 65557)
    f:seek("set", size - tail_len)
    local tail = f:read(tail_len) or ""
    local eocd
    for i = #tail - 21, 1, -1 do
        if tail:byte(i) == 0x50 and tail:sub(i, i + 3) == "PK\5\6" then
            eocd = i
            break
        end
    end
    if not eocd then
        f:close()
        return nil, "not_zip"
    end
    local count, cd_size, cd_at = u16(tail, eocd + 10), u32(tail, eocd + 12), u32(tail, eocd + 16)
    f:seek("set", cd_at)
    local cd = f:read(cd_size) or ""
    local list, entries, order, pos = {}, {}, {}, 1
    for _ = 1, count do
        if cd:sub(pos, pos + 3) ~= "PK\1\2" then
            break
        end
        local nlen, xlen, clen = u16(cd, pos + 28), u16(cd, pos + 30), u16(cd, pos + 32)
        local name = cd:sub(pos + 46, pos + 45 + nlen)
        if name:sub(1, #prefix) == prefix and name:sub(-1) ~= "/" then
            local rel = name:sub(#prefix + 1)
            local e = {rel = rel, method = u16(cd, pos + 10), crc = u32(cd, pos + 16), csize = u32(cd, pos + 20), size = u32(cd, pos + 24), at = u32(cd, pos + 42)}
            list[rel] = e
            order[#order + 1] = e
            entries[rel] = true
        end
        pos = pos + 46 + nlen + xlen + clen
    end
    local z = {entries = entries, path = path, list = order}
    function z.raw(e, h)
        local own = not h
        h = h or io.open(path, "rb")
        if not h then
            return nil
        end
        h:seek("set", e.at)
        local head = h:read(30) or ""
        if #head < 30 or head:sub(1, 4) ~= "PK\3\4" then
            if own then h:close() end
            return nil
        end
        h:seek("set", e.at + 30 + u16(head, 27) + u16(head, 29))
        local raw = h:read(e.csize)
        if own then h:close() end
        if not raw or #raw ~= e.csize then
            return nil
        end
        return raw
    end
    function z.read(_, rel)
        local e = list[rel]
        if not e then
            return nil
        end
        local raw = z.raw(e)
        if not raw then
            return nil
        elseif e.method == 0 then
            return raw
        elseif e.method == 8 then
            local ok, out = pcall(love.data.decompress, "string", "deflate", raw)
            return ok and out or nil
        end
    end
    f:close()
    return z
end

local function open_bundled()
    local root = I.VANILLA .. "/"
    local entries = setmetatable({}, {__index = function(_, name)
        return love.filesystem.getInfo(root .. name, "file") ~= nil or nil
    end})
    return {entries = entries, read = function(_, name) return love.filesystem.read(root .. name) end}
end

C.GAMES = {C.OFFICIAL, "com.unofficial.balatro"}

local function is_game(path)
    local z = path and path ~= "" and C.open_apk(path)
    return z and z.entries["version.jkr"] and z.entries["main.lua"] and true or false
end

function C.scan()
    if love.filesystem.getInfo(I.VANILLA .. "/version.jkr") then
        return {{path = I.VANILLA, where = "bundled"}}
    end
    local src = os.getenv("OVERHAUL_OFFICIAL_APK")
    if is_game(src) then
        C.game_pkg = C.OFFICIAL
        return {{path = src, where = "play"}}
    end
    if love.system.getOS() ~= "Android" then
        return {}
    end
    for _, pkg in ipairs(C.GAMES) do
        local info = C.package_info(pkg)
        if info and is_game(info.source) then
            C.game_pkg = pkg
            return {{path = info.source, where = "play"}}
        end
    end
    return {}
end

function C.quick_check(path)
    local z = path == I.VANILLA and open_bundled() or C.open_apk(path)
    if not z then
        return nil, {code = "read", file = path}
    end
    local version = A.game_version(z)
    if not version or not z.entries["main.lua"] then
        return nil, {code = "not_game"}, z
    end
    return {version = version}, nil, z
end

function C.full_check(path)
    return C.quick_check(path)
end

function C.install(_, progress)
    C.refresh()
    local plan = I.plan(true)
    if not plan.want then
        C.refresh()
        return nil, {code = "no_reinstall"}
    end
    local function report(phase, done, total)
        if phase == "copy" then
            progress("reading", done, total)
        elseif phase == "patch" then
            progress("installing", done, total)
        else
            progress("checking")
        end
    end
    local ok, why, detail = I.run(report, plan)
    C.refresh()
    collectgarbage()
    if ok then
        return {files = #love.filesystem.getDirectoryItems(C.GAME_FOLDER)}
    end
    if why == "not_found" then
        return nil, nil
    elseif why == "bad_version" then
        return nil, {code = "version", found = detail, wanted = plan.want.man.game_version}
    elseif why == "damaged" then
        return nil, {code = "damaged"}
    end
    return nil, {code = "install", file = detail}
end

function C.resolve_pick()
    return nil
end

function C.clean_path(p)
    return (tostring(p or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^file://", ""))
end

function C.read_file(p)
    local f = io.open(p, "rb")
    if not f then
        return nil
    end
    local data = f:read("*a")
    f:close()
    return data
end

function C.game_dir()
    return love.filesystem.getSaveDirectory() .. "/" .. C.GAME_FOLDER
end

function C.game_save_dir()
    return love.filesystem.getSaveDirectory()
end

function C.touchscreen()
    return true
end

function C.write_link()
    return true
end

function C.play()
    if not I.mark_play() then
        return false, "launcher_play"
    end
    love.event.quit("restart")
    return true, ""
end

function C.play_command()
    return "restart"
end

function C.apk_tool()
    return nil
end

local function url_arg(s)
    return (s:gsub("[^%w%-%._~/|:]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

local function fake_bridge(cmd, arg)
    local dir = os.getenv("OVERHAUL_BRIDGE_FAKE")
    if not dir or dir == "" then
        return false
    end
    local log = io.open(dir .. "/calls.txt", "ab")
    if log then
        log:write(cmd .. " " .. arg .. "\n")
        log:close()
    end
    if cmd == "info" then
        local pkg, out = arg:match("^([^|]+)|?(.*)$")
        local data = C.read_file(dir .. "/info-" .. pkg .. ".txt")
        if not data then
            if out ~= "" then os.remove(out) end
            return false
        end
        if out ~= "" then
            local f = io.open(out, "wb")
            if f then
                f:write(data)
                f:close()
            end
        end
        return true
    elseif cmd == "can_install" then
        return C.read_file(dir .. "/can_install") ~= nil
    elseif cmd == "install" then
        local data = C.read_file(arg)
        local f = data and io.open(dir .. "/installed.apk", "wb")
        if not f then
            return false
        end
        f:write(data)
        f:close()
        f = io.open(dir .. "/info-" .. C.APP .. ".txt", "wb")
        if f then
            f:write("2.0 (pre-release)\n400000\n" .. os.time() .. "000\n" .. dir .. "/installed.apk\n")
            f:close()
        end
        return true
    end
    return cmd == "allow_install" or cmd == "open"
end

function C.bridge(cmd, arg)
    arg = arg or ""
    if love.system.getOS() ~= "Android" then
        return fake_bridge(cmd, arg)
    end
    return love.system.openURL("overhaul:" .. cmd .. "?" .. url_arg(arg)) == true
end

function C.package_info(pkg)
    local out = love.filesystem.getSaveDirectory() .. "/" .. C.APP_INFO
    love.filesystem.write(C.APP_INFO, "")
    if not C.bridge("info", pkg .. "|" .. out) then
        return nil
    end
    local data = C.read_file(out)
    os.remove(out)
    if not data then
        return {}
    end
    local lines = {}
    for line in (data .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    local info = {name = lines[1], code = tonumber(lines[2]), time = tonumber(lines[3]), source = lines[4], splits = {}}
    for i = 5, #lines do
        if lines[i] ~= "" then
            info.splits[#info.splits + 1] = lines[i]
        end
    end
    return info
end

function C.app_info()
    return C.package_info(C.APP)
end

function C.can_install()
    return C.bridge("can_install")
end

function C.allow_install()
    return C.bridge("allow_install")
end

function C.open_app()
    return C.bridge("open", C.APP)
end

function C.app_apk()
    return love.filesystem.getSaveDirectory() .. "/" .. C.APP_APK
end

function C.install_app()
    return C.bridge("install", C.app_apk())
end

function C.app_maker()
    if not love.filesystem.getInfo("android/runtime.apk") then
        return nil
    end
    local ok, mod = pcall(require, "android.make_apk")
    if ok and type(mod) == "table" and type(mod.build_phone_app) == "function" then
        return mod
    end
end

function C.official_icon()
    local info = C.package_info(C.game_pkg or C.OFFICIAL) or {}
    local list = {}
    for _, p in ipairs(info.splits or {}) do
        if p:find("dpi", 1, true) then
            list[#list + 1] = p
        end
    end
    list[#list + 1] = info.source or os.getenv("OVERHAUL_OFFICIAL_APK")
    for _, p in ipairs(list) do
        local z = p and C.open_apk(p, "res/")
        if z then
            local best
            for _, e in ipairs(z.list) do
                local dens = e.rel:match("^drawable%-(%a+)dpi[^/]*/love%.png$") or e.rel:match("^mipmap%-(%a+)dpi[^/]*/love%.png$")
                local rank = dens and ({m = 1, h = 2, xh = 3, xxh = 4, xxxh = 5})[dens]
                if rank and (not best or rank > best.rank) then
                    best = {rank = rank, e = e}
                end
            end
            local png = best and z:read(best.e.rel)
            if png then
                return png
            end
        end
    end
    local saved = love.filesystem.read("official_icon.png")
    return saved
end

function C.drop_launcher_game()
    if love.filesystem.getInfo(I.GAME_DIR) or love.filesystem.getInfo(I.NEW_DIR) then
        I.drop_game()
        C.refresh()
    end
end

function C.build_app(o)
    local maker = C.app_maker()
    if not maker then
        return nil, {code = "no_maker"}
    end
    local games = C.scan()
    local path = games[1] and games[1].path
    if not path or games[1].where ~= "play" then
        return nil, {code = "missing"}
    end
    local info, err, z = C.quick_check(path)
    if not info then
        return nil, err
    end
    local h = io.open(path, "rb")
    if not h then
        return nil, {code = "read", file = path}
    end
    local vanilla = {list = {}, raw = function(e)
        return z.raw(e, h)
    end}
    for _, e in ipairs(z.list) do
        if e.rel:sub(1, 7) ~= "dexopt/" and (e.method == 0 or e.method == 8) then
            vanilla.list[#vanilla.list + 1] = e
        end
    end
    local icon_png = C.official_icon()
    local AI = require("app_icon")
    local function read(rel)
        if rel == AI.ORIGINAL then
            return icon_png
        end
        return z:read(rel)
    end
    local ok, res, berr = pcall(maker.build_phone_app, {
        vanilla = vanilla,
        carry = o.carry,
        out = C.app_apk(),
        icon = function(size)
            return AI.png("game", read, size)
        end,
        yield = o.yield,
    })
    h:close()
    collectgarbage()
    collectgarbage()
    if not ok then
        return nil, {code = "app_build", file = tostring(res)}
    elseif not res then
        return nil, {code = "app_build", file = tostring(berr)}
    end
    return res
end

function C.export_dir()
    local env = os.getenv("OVERHAUL_EXPORT_DIR")
    if env and env ~= "" then
        return env
    end
    for _, dir in ipairs({"/storage/emulated/0/Download", "/sdcard/Download"}) do
        local probe = dir .. "/.overhaul_probe"
        local f = io.open(probe, "wb")
        if f then
            f:close()
            os.remove(probe)
            return dir
        end
    end
end

return C
