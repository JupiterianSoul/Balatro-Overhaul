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
            local ok, out = pcall(love.data.decompress, "string", "deflate", raw .. "\0\0\0\0\0\0\0\0")
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

C.INNER = "steam_game.zip"
C.INNER_STAMP = "steam_game.txt"

local function open_game_file(path)
    return C.open_apk(path, path:find(C.INNER, 1, true) and "" or "assets/")
end
C.open_game_file = open_game_file

local function is_game(path)
    local z = path and path ~= "" and open_game_file(path)
    return z and z.entries["version.jkr"] and z.entries["main.lua"] and true or false
end

local function unpack_inner(src)
    local z = src and src ~= "" and C.open_apk(src)
    if not z or z.entries["version.jkr"] or not z.entries["game.love"] then
        return nil
    end
    local stamp
    for _, e in ipairs(z.list) do
        if e.rel == "game.love" then
            stamp = e.crc .. " " .. e.size .. "\n"
        end
    end
    local out = love.filesystem.getSaveDirectory() .. "/" .. C.INNER
    if stamp and love.filesystem.read(C.INNER_STAMP) == stamp and is_game(out) then
        return out
    end
    love.filesystem.remove(C.INNER_STAMP)
    local data = z:read("game.love")
    if not data then
        return nil
    end
    if not love.filesystem.write(C.INNER, data) then
        return nil
    end
    data = nil
    collectgarbage()
    if not is_game(out) then
        love.filesystem.remove(C.INNER)
        return nil
    end
    love.filesystem.write(C.INNER_STAMP, stamp or "")
    return out
end

local function game_at(src)
    if is_game(src) then
        return src
    end
    return unpack_inner(src)
end

function C.scan()
    if love.filesystem.getInfo(I.VANILLA .. "/version.jkr") then
        return {{path = I.VANILLA, where = "bundled"}}
    end
    local src = os.getenv("OVERHAUL_OFFICIAL_APK")
    local found = game_at(src)
    if found then
        C.game_pkg = C.OFFICIAL
        return {{path = found, where = "play", maker = found ~= src or nil}}
    end
    if love.system.getOS() ~= "Android" then
        return {}
    end
    for _, pkg in ipairs(C.GAMES) do
        local info = C.package_info(pkg)
        local hit = info and game_at(info.source)
        if hit then
            C.game_pkg = pkg
            return {{path = hit, where = "play", maker = pkg ~= C.OFFICIAL or nil}}
        end
    end
    return {}
end

function C.quick_check(path)
    local z = path == I.VANILLA and open_bundled() or C.open_game_file(path)
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
    if cmd == "save" then
        local src, result, name = arg:match("^([^|]*)|([^|]*)|(.*)$")
        local data = src and C.read_file(src)
        local f = data and io.open(dir .. "/saved-" .. name, "wb")
        local r = io.open(result or "", "wb")
        if not r then
            return false
        end
        if f then
            f:write(data)
            f:close()
        end
        r:write(f and ("ok\n+" .. name .. "\n") or "error\n")
        r:close()
        return true
    end
    if cmd == "appsave" or cmd == "pick" then
        return C.fake_appsave(dir, cmd, arg)
    end
    return cmd == "allow_install" or cmd == "open"
end

function C.fake_appsave(dir, cmd, arg)
    local p = {}
    for part in (arg .. "|"):gmatch("([^|]*)|") do p[#p + 1] = part end
    local function put(path, data)
        local f = io.open(path, "wb")
        if not f then return false end
        f:write(data)
        f:close()
        return true
    end
    if cmd == "pick" then
        local name = C.read_file(dir .. "/pick_name.txt")
        local data = name and C.read_file(dir .. "/pick/" .. name)
        if not data then return put(p[3], "cancel\n") end
        put(p[2] .. "/" .. name, data)
        return put(p[3], "ok\n+" .. name .. "\n")
    end
    local mode, result, dest, token, name = p[1], p[3], p[4], p[5], p[6]
    if C.read_file(dir .. "/app_old") then return put(result, "old\n") end
    if C.read_file(dir .. "/app_running") then return put(result, "running\n") end
    local SIO = require("save_io")
    local game = dir .. "/app_save"
    if mode == "export" then
        local files = SIO.read_folder_io(game)
        if not files then return put(result, "empty\n") end
        put(dir .. "/saved-" .. name, SIO.zip(SIO.entries(files)))
        return put(result, "ok\n@" .. name .. "\n")
    elseif mode == "import" then
        local pick = C.read_file(dir .. "/pick_name.txt")
        local data = pick and C.read_file(dir .. "/pick/" .. pick)
        if not data then return put(result, "cancel\n") end
        put(dir .. "/staged.zip", data)
        put(dest .. "/app_import.zip", data)
        return put(result, "ok\n+app_import.zip\n#0123456789abcdef0123456789abcdef\n@" .. pick .. "\n")
    elseif mode == "apply" then
        local data = token == "0123456789abcdef0123456789abcdef" and C.read_file(dir .. "/staged.zip")
        if not data then return put(result, "error\n") end
        os.execute('mkdir -p "' .. game .. '/imports"')
        put(game .. "/imports/pending.zip", data)
        os.remove(dir .. "/staged.zip")
        return put(result, "ok\n")
    end
    return false
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
    local pick = I.bundled()
    if not pick then
        h:close()
        return nil, {code = "app_build", file = "patch"}
    end
    local man, ctx = I.choose(pick, z, function()
        if o.yield then o.yield(0, 1) end
    end)
    if not man then
        h:close()
        return nil, {code = "version", found = I.check_text(ctx, info.version), wanted = pick.man.game_version}
    end
    local game = {
        man = man, ctx = ctx, z = z, build = A.build,
        marker_name = I.BUILT, marker = I.marker_text(pick.id, pick.version, info.version, man.overhaul_name),
        shared_name = I.SHARED, rename = {["main.lua"] = I.BUILT_MAIN, ["conf.lua"] = I.BUILT_CONF},
    }
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
        game = game,
        carry = o.carry,
        safe = o.safe,
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

C.SAVE_RESULT = "save_as_result.txt"

function C.save_as(path, name)
    love.filesystem.remove(C.SAVE_RESULT)
    return C.bridge("save", path .. "|" .. love.filesystem.getSaveDirectory() .. "/" .. C.SAVE_RESULT .. "|" .. name)
end

function C.save_as_result()
    local data = love.filesystem.read(C.SAVE_RESULT)
    if not data then
        return nil
    end
    love.filesystem.remove(C.SAVE_RESULT)
    local status = data:match("^(%a+)") or "error"
    return status, data:match("\n%+([^\n]+)") or ""
end

return C
