local A = require("patcher.apply")
local F = require("patcher.find")
local bit = require("bit")

local C = {}

C.GAME_FOLDER = "Overhaul"
C.STAMP = "install.lua"
C.SETTINGS = "settings.lua"
C.LINK = "overhaul_launcher_link.lua"
C.FEED_URL = "https://balatro-overhaul-muliplayer.onrender.com/release/feed.json"
C.BUNDLED = "patchset"
C.root = C.BUNDLED

local function hex(s)
    return love.data.encode("string", "hex", s)
end

function C.sha256(s)
    return hex(love.data.hash("sha256", s))
end

function C.use_root(root)
    C.root = root
    C._manifest = nil
end

function C.ctx()
    return {
        inflate = function(raw)
            return love.data.decompress("string", "deflate", raw .. "\0\0\0\0\0\0\0\0")
        end,
        sha256 = function(s)
            return hex(love.data.hash("sha256", s))
        end,
        read_patch = function(rel)
            return love.filesystem.read(C.root .. "/" .. rel)
        end,
        image = function(base, own, mask, e)
            local vd = love.image.newImageData(love.filesystem.newFileData(base, "base.png"))
            local out = love.image.newImageData(e.w, e.h)
            out:paste(vd, 0, 0, 0, 0, math.min(vd:getWidth(), e.w), math.min(vd:getHeight(), e.h))
            if own and mask then
                local od = love.image.newImageData(love.filesystem.newFileData(own, "own.png"))
                local md = love.image.newImageData(love.filesystem.newFileData(mask, "mask.png"))
                for y = 0, md:getHeight() - 1 do
                    for x = 0, md:getWidth() - 1 do
                        if md:getPixel(x, y) > 0.5 then
                            out:setPixel(e.x + x, e.y + y, od:getPixel(x, y))
                        end
                    end
                end
            end
            return out:encode("png"):getString(), hex(love.data.hash("sha256", out:getString()))
        end,
    }
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

function C.manifest()
    if C._manifest == nil then
        C._manifest = A.load_manifest(love.filesystem.read(C.root .. "/manifest.lua")) or false
    end
    return C._manifest or nil
end

function C.settings()
    C._settings = C._settings or load_table(C.SETTINGS) or {}
    return C._settings
end

function C.save_settings()
    save_table(C.SETTINGS, C.settings())
end

function C.stamp()
    return load_table(C.STAMP)
end

function C.os()
    return love.system.getOS()
end

local fake_root = os.getenv("LAUNCHER_FAKE_WIN")
fake_root = fake_root ~= "" and fake_root or nil
local fake_dirs = {}

local function fake_list(dir)
    if fake_dirs[dir] == nil then
        local out = false
        local h = io.popen("ls -1Ap '" .. dir:gsub("'", "'\\''") .. "' 2>/dev/null")
        if h then
            out = {}
            for line in h:lines() do
                out[#out + 1] = line
            end
            h:close()
        end
        fake_dirs[dir] = out
    end
    return fake_dirs[dir] or nil
end

local function fake_path(p)
    local d, rest = p:gsub("\\", "/"):match("^(%a):/*(.*)$")
    if not d then
        return p, false
    end
    local cur = fake_root .. "/" .. d:upper()
    local denied = false
    for part in rest:gmatch("[^/]+") do
        local names = fake_list(cur)
        local hit = part
        for _, n in ipairs(names or {}) do
            if n:gsub("/$", ""):lower() == part:lower() then
                hit = n:gsub("/$", "")
                break
            end
        end
        cur = cur .. "/" .. hit
        local f = io.open(cur .. "/.denied", "rb")
        if f then
            f:close()
            denied = true
        end
    end
    return cur, denied
end

local function real_path(p)
    if not fake_root then
        return p
    end
    local q, denied = fake_path(p)
    return not denied and q or nil
end

local function file_size(p)
    p = real_path(p)
    if not p then
        return nil
    end
    local f = io.open(p, "rb")
    if not f then
        return nil
    end
    local size = f:seek("end")
    f:close()
    return size
end

local function read_file(p)
    p = real_path(p)
    if not p then
        return nil
    end
    local f = io.open(p, "rb")
    if not f then
        return nil
    end
    local data = f:read("*a")
    f:close()
    return data
end

C.read_file = read_file

local function exists(p)
    return file_size(p) ~= nil
end

local WIN_CDEF = [[
typedef struct { uint32_t lo, hi; } BOL_FT;
typedef struct { uint32_t attrs; BOL_FT c, a, w; uint32_t size_hi, size_lo, r0, r1; char name[260]; char alt[14]; } BOL_FINDA;
uint32_t GetLogicalDrives(void);
uint32_t GetDriveTypeA(const char *root);
uint32_t SetErrorMode(uint32_t mode);
void *FindFirstFileA(const char *pattern, BOL_FINDA *data);
int FindNextFileA(void *h, BOL_FINDA *data);
int FindClose(void *h);
]]

local function win_ffi()
    if C._wffi == nil then
        C._wffi = false
        if C.os() == "Windows" then
            local ok, ffi = pcall(require, "ffi")
            if ok and pcall(ffi.cdef, WIN_CDEF) then
                C._wffi = ffi
                pcall(function()
                    ffi.C.SetErrorMode(1)
                end)
            end
        end
    end
    return C._wffi or nil
end

local REG_CDEF = [[
int32_t RegGetValueA(void *hkey, const char *sub, const char *value, uint32_t flags, uint32_t *type, void *data, uint32_t *size);
]]

local HIVES = {HKCU = 0x80000001, HKLM = 0x80000002}

function C.reg(hive, key, value)
    if fake_root then
        local chunk = loadstring(read_file(fake_root .. "/registry.lua") or "return {}")
        local ok, t = pcall(chunk or function() end)
        return ok and type(t) == "table" and t[hive .. "\\" .. key .. "\\" .. value] or nil
    end
    local ffi = win_ffi()
    if not ffi or not HIVES[hive] then
        return nil
    end
    if C._adv == nil then
        C._adv = false
        local ok, lib = pcall(function()
            ffi.cdef(REG_CDEF)
            return ffi.load("advapi32")
        end)
        if ok and lib then
            C._adv = lib
        end
    end
    if not C._adv then
        return nil
    end
    local ok, v = pcall(function()
        local h = ffi.cast("void *", ffi.cast("intptr_t", bit.tobit(HIVES[hive])))
        for _, view in ipairs({0x10000, 0x20000}) do
            local size = ffi.new("uint32_t[1]", 2048)
            local buf = ffi.new("char[2048]")
            if C._adv.RegGetValueA(h, key, value, bit.bor(0x2, view), nil, buf, size) == 0 then
                return ffi.string(buf)
            end
        end
    end)
    return ok and v or nil
end

function C.touchscreen()
    if os.getenv("LAUNCHER_TOUCH") == "1" then
        return true
    end
    local ffi = win_ffi()
    if not ffi then
        return false
    end
    local ok, n = pcall(function()
        pcall(ffi.cdef, "int GetSystemMetrics(int index);")
        return ffi.load("user32").GetSystemMetrics(95)
    end)
    return ok and tonumber(n) ~= nil and tonumber(n) > 0
end

function C.list_dir(pattern)
    if fake_root then
        local dir, denied = fake_path((pattern:gsub("[/\\]%*$", "")))
        if denied then
            return nil
        end
        local names = fake_list(dir)
        if not names then
            return nil
        end
        local out = {}
        for _, n in ipairs(names) do
            if n:sub(-1) == "/" then
                out[#out + 1] = n:sub(1, -2)
            end
        end
        return out
    end
    local ffi = win_ffi()
    if not ffi then
        return nil
    end
    local ok, names = pcall(function()
        local d = ffi.new("BOL_FINDA")
        local h = ffi.C.FindFirstFileA((pattern:gsub("/", "\\")), d)
        if ffi.cast("intptr_t", h) == -1 then
            return nil
        end
        local out = {}
        repeat
            local n = ffi.string(d.name)
            if n ~= "." and n ~= ".." and bit.band(d.attrs, 0x10) ~= 0 then
                out[#out + 1] = n
            end
        until ffi.C.FindNextFileA(h, d) == 0
        ffi.C.FindClose(h)
        return out
    end)
    return ok and names or nil
end

function C.drives()
    if fake_root then
        local out = {}
        for _, n in ipairs(fake_list(fake_root) or {}) do
            if n:match("^%a/$") then
                out[#out + 1] = n:sub(1, 1)
            end
        end
        return out
    end
    local ffi = win_ffi()
    if not ffi then
        return nil
    end
    local ok, list = pcall(function()
        local mask = ffi.C.GetLogicalDrives()
        local out = {}
        for i = 2, 25 do
            if bit.band(mask, bit.lshift(1, i)) ~= 0 then
                local letter = string.char(65 + i)
                local kind = ffi.C.GetDriveTypeA(letter .. ":\\")
                if kind ~= 1 and kind ~= 4 and kind ~= 5 then
                    out[#out + 1] = letter
                end
            end
        end
        return out
    end)
    return ok and list or nil
end

function C.scan()
    local list = {}
    local env = os.getenv("OVERHAUL_GAME")
    if env and env ~= "" then
        list[#list + 1] = {path = env, where = "picked", size = file_size(env)}
    end
    local picked = C.settings().game_path
    if picked and picked ~= env and (exists(picked) or F.is_loose(picked, exists)) then
        list[#list + 1] = {path = picked, where = "picked", size = file_size(picked)}
    end
    if os.getenv("OVERHAUL_NO_SCAN") ~= "1" then
        local seen = {}
        for _, g in ipairs(list) do
            seen[g.path] = true
        end
        local os_name, getenv = C.os(), os.getenv
        if fake_root then
            local fenv = {["ProgramFiles(x86)"] = "C:\\Program Files (x86)", ProgramFiles = "C:\\Program Files",
                ProgramW6432 = "C:\\Program Files", LOCALAPPDATA = "C:\\Users\\Player\\AppData\\Local"}
            os_name, getenv = "Windows", function(k)
                return fenv[k]
            end
        end
        for _, g in ipairs(F.scan(os_name, getenv, read_file, file_size, C.list_dir, C.drives(), C.reg)) do
            if not seen[g.path] then
                list[#list + 1] = g
            end
        end
    end
    return list
end

function C.clean_path(p)
    p = p:gsub("^%s+", ""):gsub("%s+$", ""):gsub('^"(.*)"$', "%1"):gsub("^file://", "")
    return (p:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

function C.resolve_pick(p)
    if not p then
        return nil
    end
    p = C.clean_path(p)
    if p == "" then
        return nil
    end
    local inside = F.in_folder(p, exists)
    if inside then
        return inside
    end
    if exists(p) and not F.is_loose(p, exists) then
        return p
    end
    return nil
end

function C.is_loose(path)
    return F.is_loose(path, exists)
end

local function open_loose(dir)
    local base = dir:gsub("[/\\]+$", "")
    local entries = setmetatable({}, {__index = function(_, name)
        if type(name) == "string" and exists(base .. "/" .. name) then
            return {name = name}
        end
    end})
    return {loose = true, entries = entries, read = function(_, name)
        return read_file(base .. "/" .. name)
    end}
end

function C.open(path, data)
    local ctx = C.ctx()
    if not data and F.is_loose(path, exists) then
        return open_loose(path)
    end
    data = data or read_file(path)
    if not data then
        return nil, {code = "read", file = path}
    end
    local z, err = A.open_game(data, ctx)
    if not z then
        return nil, err
    end
    return z
end

function C.quick_check(path, data)
    local z, err = C.open(path, data)
    if not z then
        return nil, err
    end
    local m = C.manifest()
    local version = A.game_version(z)
    if not version or not z.entries["main.lua"] then
        return nil, {code = "not_game"}
    end
    return {version = version}, nil, z
end

function C.full_check(path, yield)
    local m = C.manifest()
    if not m then
        return nil, {code = "patch", file = "manifest.lua"}
    end
    local z, err = C.open(path)
    if not z then
        return nil, err
    end
    local ctx = C.ctx()
    ctx.yield = yield
    local ok, cerr = A.check(m, z, ctx)
    return ok, cerr, z
end

local function remove_tree(p)
    local info = love.filesystem.getInfo(p)
    if not info then
        return
    end
    if info.type == "directory" then
        for _, name in ipairs(love.filesystem.getDirectoryItems(p)) do
            remove_tree(p .. "/" .. name)
        end
    end
    love.filesystem.remove(p)
end

C.remove_tree = remove_tree

local function copy_tree(from, to)
    local info = love.filesystem.getInfo(from)
    if not info then
        return true
    end
    if info.type == "directory" then
        love.filesystem.createDirectory(to)
        for _, name in ipairs(love.filesystem.getDirectoryItems(from)) do
            if not copy_tree(from .. "/" .. name, to .. "/" .. name) then
                return false
            end
        end
        return true
    end
    local data = love.filesystem.read(from)
    return data ~= nil and love.filesystem.write(to, data) and true or false
end

local function swap_in(staged)
    remove_tree(C.GAME_FOLDER)
    if love.filesystem.getInfo(C.GAME_FOLDER) then
        return false
    end
    local base = love.filesystem.getSaveDirectory() .. "/"
    if os.rename(base .. staged, base .. C.GAME_FOLDER) then
        return true
    end
    local ok = copy_tree(staged, C.GAME_FOLDER)
    remove_tree(staged)
    return ok
end

function C.install(path, progress)
    local m = C.manifest()
    if not m then
        return nil, {code = "patch", file = "manifest.lua"}
    end
    progress("reading")
    local ok, err, z = C.full_check(path, function()
        progress("checking")
    end)
    if not ok then
        return nil, err
    end
    local staged = C.GAME_FOLDER .. ".new"
    remove_tree(staged)
    local made = {}
    local function mkdirs(rel)
        local dir = rel:match("^(.*)/[^/]*$")
        if dir and not made[dir] then
            love.filesystem.createDirectory(staged .. "/" .. dir)
            made[dir] = true
        end
    end
    love.filesystem.createDirectory(staged)
    local ctx = C.ctx()
    ctx.yield = function(i, n)
        if i then
            progress("installing", i, n)
        end
    end
    local res, berr = A.build(m, z, ctx, function(rel, data)
        mkdirs(rel)
        local wok, werr = love.filesystem.write(staged .. "/" .. rel, data)
        return wok and true or false, werr
    end)
    z = nil
    collectgarbage()
    if not res then
        remove_tree(staged)
        return nil, berr
    end
    progress("finishing")
    love.filesystem.remove(C.STAMP)
    if not swap_in(staged) then
        return nil, {code = "in_use", file = C.game_dir()}
    end
    save_table(C.STAMP, {
        overhaul_version = m.overhaul_version,
        overhaul_name = m.overhaul_name,
        game_version = m.game_version,
        game_path = path,
        files = res.files,
        time = os.time(),
    })
    return res
end

function C.game_dir()
    return love.filesystem.getSaveDirectory() .. "/" .. C.GAME_FOLDER
end

function C.game_save_dir()
    local base = love.filesystem.getSaveDirectory():gsub("/[^/]*$", "")
    if love.filesystem.isFused() then
        base = base .. (C.os() == "Linux" and "/love" or "/LOVE")
    end
    return base .. "/" .. C.GAME_FOLDER
end

local function q(s)
    return '"' .. s .. '"'
end

C.RUN_SCRIPT = "run_overhaul.sh"
C.TUNNEL = "tls_tunnel.py"
C.TUNNEL_SRC = "tunnel/tls_tunnel.py"

local RUN_SH = [=[#!/bin/sh
here="$(cd "$(dirname "$0")" && pwd)"
py=""
for c in python3 /opt/homebrew/bin/python3 /usr/local/bin/python3; do
    p="$(command -v "$c" 2>/dev/null)"
    [ -n "$p" ] || continue
    if [ "$(uname)" = "Darwin" ] && [ "$p" = "/usr/bin/python3" ] && ! xcode-select -p >/dev/null 2>&1; then
        continue
    fi
    py="$p"
    break
done
tunnel=""
if [ -n "$py" ] && [ -f "$here/tls_tunnel.py" ]; then
    lib="$LD_LIBRARY_PATH"
    if [ -n "$APPDIR" ]; then
        lib="${lib#"$APPDIR/lib/:"}"
    fi
    LD_LIBRARY_PATH="$lib" "$py" -I "$here/tls_tunnel.py" >/dev/null 2>&1 &
    tunnel=$!
fi
"$@"
code=$?
if [ -n "$tunnel" ]; then
    kill "$tunnel" 2>/dev/null
fi
exit $code
]=]

function C.prepare_run()
    local py = love.filesystem.read(C.TUNNEL_SRC)
    if not py then
        return nil
    end
    love.filesystem.write(C.TUNNEL, py)
    love.filesystem.write(C.RUN_SCRIPT, RUN_SH)
    return love.filesystem.getSaveDirectory() .. "/" .. C.RUN_SCRIPT
end

local function dirname(p)
    return (p:gsub("[/\\][^/\\]*$", ""))
end

function C.native_https(game_path)
    if not game_path then
        return nil
    end
    local osn = C.os()
    local base = C.is_loose(game_path) and game_path or dirname(game_path)
    local name, list
    if osn == "Windows" then
        name, list = "https.dll", {base .. "/https.dll"}
    elseif osn == "OS X" then
        local app = game_path:match("^(.*%.app)/") or base
        name, list = "https.so", {app .. "/Contents/Frameworks/https.so", app .. "/Contents/Resources/https.so", base .. "/https.so"}
    else
        return nil
    end
    local dest = C.GAME_FOLDER .. "/" .. name
    for _, src in ipairs(list) do
        local data = read_file(src)
        if data and #data > 1024 then
            if love.filesystem.read(dest) ~= data then
                love.filesystem.write(dest, data)
            end
            return name
        end
    end
end

function C.play_command()
    local dir = C.game_dir()
    local custom = os.getenv("OVERHAUL_LOVE")
    local osn = C.os()
    local cmd
    if custom and custom ~= "" then
        cmd = q(custom) .. " " .. q(dir)
    elseif osn == "Windows" then
        local base = love.filesystem.getSourceBaseDirectory():gsub("/", "\\")
        local wdir = dir:gsub("/", "\\")
        return 'start "" /D ' .. q(wdir) .. " " .. q(base .. "\\love.exe") .. " " .. q(wdir)
    elseif osn == "OS X" then
        local base = love.filesystem.getSourceBaseDirectory()
        cmd = q(base .. "/runtime/love.app/Contents/MacOS/love") .. " " .. q(dir)
    else
        local appdir = os.getenv("APPDIR")
        if appdir and appdir ~= "" then
            cmd = q(appdir .. "/AppRun") .. " --overhaul-run " .. q(dir)
        else
            cmd = "love " .. q(dir)
        end
    end
    local run = C.prepare_run()
    if run then
        return "cd " .. q(dir) .. " && sh " .. q(run) .. " " .. cmd .. " &"
    end
    return cmd .. " &"
end

function C.self_command()
    local custom = os.getenv("OVERHAUL_LAUNCHER_CMD")
    if custom and custom ~= "" then
        local list = {}
        for part in custom:gmatch("[^|]+") do
            list[#list + 1] = part
        end
        return list
    end
    local osn = C.os()
    local appdir = os.getenv("APPDIR")
    if osn == "Linux" and appdir and appdir ~= "" then
        return {appdir .. "/AppRun"}
    end
    if love.filesystem.isFused() then
        if osn == "OS X" then
            return {love.filesystem.getSourceBaseDirectory() .. "/../MacOS/love"}
        end
        return {love.filesystem.getSource()}
    end
    return {(arg and arg[-2]) or "love", love.filesystem.getSource()}
end

function C.write_link(feed)
    return save_table(C.LINK, {format = 1, feed = feed, launcher = C.self_command(), game_dir = C.game_dir()})
end

function C.play(game_path)
    pcall(C.native_https, game_path or C.settings().game_path)
    local cmd = C.play_command()
    local r = os.execute(cmd)
    return r == 0 or r == true, cmd
end

function C.open_folder()
    local dir = love.filesystem.getSaveDirectory()
    love.system.openURL("file://" .. dir)
end

function C.apk_icon()
    local gd = C.game_dir()
    if not love.graphics or not exists(gd .. "/resources/textures/2x/Jokers.png") then return nil end
    local ok, AI = pcall(require, "app_icon")
    if not ok then return nil end
    return function(size) return AI.png("game", AI.read_from(gd), size) end
end

function C.apk_installer()
    if C._apk_installer == nil then
        package.preload["patcher.love_ctx"] = package.preload["patcher.love_ctx"] or function()
            return require("android.patcher.love_ctx")
        end
        local ok, mod = pcall(function()
            return love.filesystem.load("android/bootstrap/overhaul_install.lua")()
        end)
        C._apk_installer = ok and type(mod) == "table" and mod or false
    end
    return C._apk_installer or nil
end

function C.apk_game(path, yield)
    local I = C.apk_installer()
    local src = love.filesystem.read(C.root .. "/manifest.lua")
    local m = C.manifest()
    if not I or not src or not m then
        return nil, {code = "patch", file = "manifest.lua"}
    end
    local ok, cerr, z = C.full_check(path, yield)
    if not ok then
        return nil, cerr
    end
    return {
        man = m, ctx = C.ctx(), z = z, build = A.build,
        marker_name = I.BUILT,
        marker = I.marker_text(C.sha256(src), tostring(m.overhaul_version or "0"), ok.version, m.overhaul_name),
        shared_name = I.SHARED,
        rename = {["main.lua"] = I.BUILT_MAIN, ["conf.lua"] = I.BUILT_CONF},
    }
end

function C.apk_tool()
    if love.filesystem.getInfo("android/make_apk.lua") then
        local ok, mod = pcall(require, "android.make_apk")
        if ok and type(mod) == "table" and type(mod.run) == "function" then
            return mod
        end
    end
end

return C
