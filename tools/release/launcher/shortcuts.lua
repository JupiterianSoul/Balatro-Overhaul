local M = {}

M.NAME = "Balatro Overhaul"
M.EXE = "Balatro Overhaul Launcher.exe"

local bit = require("bit")

local function utf16le(s)
    local out = {}
    local i, n = 1, #s
    while i <= n do
        local c = s:byte(i)
        local cp, len
        if c < 0x80 then cp, len = c, 1
        elseif c < 0xE0 then cp, len = bit.band(c, 0x1F), 2
        elseif c < 0xF0 then cp, len = bit.band(c, 0x0F), 3
        else cp, len = bit.band(c, 0x07), 4 end
        for k = 1, len - 1 do
            cp = bit.bor(bit.lshift(cp, 6), bit.band(s:byte(i + k) or 0x80, 0x3F))
        end
        i = i + len
        if cp >= 0x10000 then
            cp = cp - 0x10000
            local hi, lo = 0xD800 + bit.rshift(cp, 10), 0xDC00 + bit.band(cp, 0x3FF)
            out[#out + 1] = string.char(bit.band(hi, 0xFF), bit.rshift(hi, 8), bit.band(lo, 0xFF), bit.rshift(lo, 8))
        else
            out[#out + 1] = string.char(bit.band(cp, 0xFF), bit.rshift(cp, 8))
        end
    end
    return table.concat(out)
end
M.utf16le = utf16le

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local v = a * 65536 + (b or 0) * 256 + (c or 0)
        local n = (not b and 2) or (not c and 3) or 4
        for k = 1, 4 do
            if k <= n then
                local idx = bit.band(bit.rshift(v, (4 - k) * 6), 63) + 1
                out[#out + 1] = B64:sub(idx, idx)
            else
                out[#out + 1] = "="
            end
        end
    end
    return table.concat(out)
end
M.base64 = base64

local function psq(s)
    return "'" .. tostring(s):gsub("'", "''") .. "'"
end

function M.lnk_script(exe, workdir, icon)
    return "$w=New-Object -ComObject WScript.Shell;"
        .. "foreach($d in @([Environment]::GetFolderPath('Desktop'),[Environment]::GetFolderPath('Programs'))){"
        .. "if($d){$s=$w.CreateShortcut((Join-Path $d " .. psq(M.NAME .. ".lnk") .. "));"
        .. "$s.TargetPath=" .. psq(exe) .. ";$s.Arguments='--play';$s.WorkingDirectory=" .. psq(workdir) .. ";"
        .. "$s.IconLocation=" .. psq(icon or (exe .. ",0")) .. ";$s.Description=" .. psq(M.NAME) .. ";$s.Save()}}"
end

local CRC
local function crc32(s)
    if not CRC then
        CRC = {}
        for i = 0, 255 do
            local c = i
            for _ = 1, 8 do
                if bit.band(c, 1) == 1 then c = bit.bxor(bit.rshift(c, 1), 0xEDB88320) else c = bit.rshift(c, 1) end
            end
            CRC[i] = c
        end
    end
    local c = 0xFFFFFFFF
    for i = 1, #s do
        c = bit.bxor(CRC[bit.band(bit.bxor(c, s:byte(i)), 0xFF)], bit.rshift(c, 8))
    end
    return bit.bnot(c)
end

local function int32(v)
    v = bit.tobit(v)
    return string.char(bit.band(v, 0xFF), bit.band(bit.rshift(v, 8), 0xFF), bit.band(bit.rshift(v, 16), 0xFF), bit.band(bit.rshift(v, 24), 0xFF))
end

local function str(k, v) return "\1" .. k .. "\0" .. v .. "\0" end
local function num(k, v) return "\2" .. k .. "\0" .. int32(v) end

function M.vdf_entry(index, exe, startdir, icon)
    local q = '"' .. exe .. '"'
    local appid = bit.bor(crc32(q .. M.NAME), 0x80000000)
    return "\0" .. tostring(index) .. "\0"
        .. num("appid", appid)
        .. str("AppName", M.NAME)
        .. str("Exe", q)
        .. str("StartDir", '"' .. startdir .. '"')
        .. str("icon", icon or exe)
        .. str("ShortcutPath", "")
        .. str("LaunchOptions", "--play")
        .. num("IsHidden", 0) .. num("AllowDesktopConfig", 1) .. num("AllowOverlay", 1) .. num("OpenVR", 0)
        .. num("Devkit", 0) .. str("DevkitGameID", "") .. num("DevkitOverrideAppID", 0) .. num("LastPlayTime", 0)
        .. str("FlatpakAppID", "")
        .. "\0tags\0\8"
        .. "\8"
end

function M.has_entry(data)
    local lower = (data or ""):lower()
    return lower:find("\1appname\0" .. M.NAME:lower() .. "\0", 1, true) ~= nil
end

function M.add_to_vdf(data, exe, startdir, icon)
    if data and M.has_entry(data) then return nil end
    local body
    if not data or #data < 13 or data:sub(1, 11) ~= "\0shortcuts\0" or data:sub(-2) ~= "\8\8" then
        if data and #data > 0 then return nil end
        body = "\0shortcuts\0"
    else
        body = data:sub(1, -3)
    end
    local idx = 0
    while body:find("\0" .. idx .. "\0\2", 1, true) or body:find("\0" .. idx .. "\0\1", 1, true) do
        idx = idx + 1
    end
    return body .. M.vdf_entry(idx, exe, startdir, icon) .. "\8\8"
end

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
end

local function write(path, data)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

local function steam_running()
    local p = io.popen('tasklist /FI "IMAGENAME eq steam.exe" /NH 2>NUL')
    if not p then return false end
    local out = p:read("*a") or ""
    p:close()
    return out:lower():find("steam.exe", 1, true) ~= nil
end

local function user_dirs(root, list_dir)
    local out = {}
    for _, id in ipairs(list_dir(root .. "/userdata/*") or {}) do
        if id:match("^%d+$") and id ~= "0" then
            out[#out + 1] = root .. "/userdata/" .. id .. "/config"
        end
    end
    return out
end

function M.add_to_steam(roots, list_dir, exe, startdir, icon)
    if steam_running() then return "running" end
    local added, found = 0, 0
    for _, root in ipairs(roots) do
        for _, cfg in ipairs(user_dirs(root, list_dir)) do
            found = found + 1
            local path = cfg .. "/shortcuts.vdf"
            local cur = read(path)
            local nu = M.add_to_vdf(cur, exe, startdir, icon)
            if nu then
                if cur then write(path .. ".bak", cur) end
                if write(path, nu) then added = added + 1 end
            elseif cur and M.has_entry(cur) then
                added = added + 1
            end
        end
    end
    if found == 0 then return "nosteam" end
    return added > 0 and "ok" or "failed"
end

local function desktop_quote(s)
    return '"' .. s:gsub('[\\"`$]', function(c) return "\\" .. c end) .. '"'
end
M.desktop_quote = desktop_quote

function M.desktop_entry(name, exec, icon, comment)
    return table.concat({
        "[Desktop Entry]",
        "Type=Application",
        "Name=" .. name,
        "Comment=" .. comment,
        "Exec=" .. exec,
        "Icon=" .. icon,
        "Categories=Game;",
        "Terminal=false",
        "",
    }, "\n")
end

local function read_all(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
end

function M.linux_launcher()
    local img = os.getenv("APPIMAGE")
    if img and img ~= "" then return img end
    local dir = os.getenv("APPDIR")
    if dir and dir ~= "" then return dir .. "/AppRun" end
end

local function ls(dir)
    local out = {}
    local p = io.popen("ls -1 " .. desktop_quote(dir) .. " 2>/dev/null")
    if not p then return out end
    for line in p:lines() do out[#out + 1] = line end
    p:close()
    return out
end
M.ls = ls

function M.install_linux(C, list_dir)
    list_dir = list_dir or ls
    local home = os.getenv("HOME")
    local launcher = M.linux_launcher()
    if not (home and home ~= "" and launcher) then return nil end
    local data = os.getenv("XDG_DATA_HOME")
    if not data or data == "" then data = home .. "/.local/share" end
    local apps = data .. "/applications"
    local gd = C.game_dir()
    local ok_icon, AI = pcall(require, "app_icon")
    local game_icon, launcher_icon
    if ok_icon then
        local ok1, base = pcall(AI.write_files, gd, gd, "game", "app_icon")
        local ok2, lbase = pcall(AI.write_files, gd, gd, "launcher", "launcher_icon")
        if ok1 and type(base) == "string" then game_icon = base .. ".png" end
        if ok2 and type(lbase) == "string" then launcher_icon = lbase .. ".png" end
    end
    os.execute("mkdir -p " .. desktop_quote(apps))
    local mine = {[M.LINUX_PLAY .. ".desktop"] = true, [M.LINUX_LAUNCHER .. ".desktop"] = true}
    for _, f in ipairs(list_dir(apps)) do
        if f:match("%.desktop$") and not mine[f] then
            local d = read_all(apps .. "/" .. f)
            if d and d:find(launcher, 1, true) then return {lnk = false, steam = nil, linux = "own"} end
        end
    end
    local q = desktop_quote(launcher)
    local files = {
        [M.LINUX_PLAY] = M.desktop_entry(M.NAME, q .. " --play", game_icon or "applications-games", "Play the Balatro Overhaul"),
        [M.LINUX_LAUNCHER] = M.desktop_entry(M.NAME .. " Launcher", q, launcher_icon or game_icon or "applications-games", "Install and update the Balatro Overhaul"),
    }
    local wrote = 0
    for id, body in pairs(files) do
        local f = io.open(apps .. "/" .. id .. ".desktop", "wb")
        if f then f:write(body) f:close() wrote = wrote + 1 end
    end
    return {lnk = wrote == 2, steam = nil, linux = wrote == 2 and "ok" or "failed"}
end

M.LINUX_PLAY = "balatro-overhaul-play"
M.LINUX_LAUNCHER = "balatro-overhaul-launcher-app"

function M.install(C, F)
    if C.os() == "Linux" then return M.install_linux(C) end
    if C.os() ~= "Windows" then return nil end
    local base = love.filesystem.getSourceBaseDirectory():gsub("/", "\\")
    local exe = base .. "\\" .. M.EXE
    local workdir = C.game_dir():gsub("/", "\\")
    local icon
    local ok_icon, AI = pcall(require, "app_icon")
    if ok_icon then
        local gd = C.game_dir()
        local base_icon = select(2, pcall(AI.write_files, gd, gd, "game", "app_icon"))
        pcall(AI.write_files, gd, gd, "launcher", "launcher_icon")
        if type(base_icon) == "string" then icon = (base_icon .. ".ico"):gsub("/", "\\") end
    end
    local script = M.lnk_script(exe, workdir, icon)
    local ok_lnk = os.execute("powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand " .. base64(utf16le(script)))
    local roots = {}
    for _, r in ipairs(F.steam_roots("Windows", os.getenv, C.reg) or {}) do
        roots[#roots + 1] = (r:gsub("\\", "/"))
    end
    local steam = M.add_to_steam(roots, C.list_dir, exe, base, icon)
    return {lnk = ok_lnk == 0 or ok_lnk == true, steam = steam}
end

return M
