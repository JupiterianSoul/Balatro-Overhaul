local bit = require("bit")

local M = {}

M.SLOTS = {"1", "2", "3"}
M.VANILLA_FILES = {"profile.jkr", "meta.jkr", "unlock_notify.jkr"}
M.SKIP_DIRS = {
    backups = true, exports = true, imports = true, crash_reports = true, bot = true, mods = true, Mods = true,
    lovely = true, workshop = true, cache = true, shots = true, updates = true, Overhaul = true, ["Overhaul.new"] = true,
}
M.LOCK = "overhaul_running.lock"
M.LOCK_STALE = 30
M.SKIP_FILES = {["settings.jkr"] = true, ["modded_settings.jkr"] = true, ["version.jkr"] = true, [M.LOCK] = true}
M.MAX_FILE = 16 * 1024 * 1024
M.MAX_TOTAL = 96 * 1024 * 1024
M.SOURCE_DIRS = {
    engine = true, functions = true, localization = true, modloader = true, multiplayer = true, resources = true,
    smods = true, dexopt = true, lovely = true, bot = true, patch = true, patcher = true, android = true,
}
M.ROOT_LUA = {["minigames.lua"] = true, ["run_history.lua"] = true, ["run_splits.lua"] = true}

local CRC = {}
for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
        if bit.band(c, 1) == 1 then
            c = bit.bxor(bit.rshift(c, 1), 0xEDB88320)
        else
            c = bit.rshift(c, 1)
        end
    end
    CRC[i] = c
end

function M.crc32(s, c)
    c = c and bit.bxor(c, 0xFFFFFFFF) or 0xFFFFFFFF
    local n = #s
    local i = 1
    local band, bxor, rshift, byte = bit.band, bit.bxor, bit.rshift, string.byte
    while i + 7 <= n do
        local a, b, d, e, f, g, h, k = byte(s, i, i + 7)
        c = bxor(CRC[band(bxor(c, a), 0xFF)], rshift(c, 8))
        c = bxor(CRC[band(bxor(c, b), 0xFF)], rshift(c, 8))
        c = bxor(CRC[band(bxor(c, d), 0xFF)], rshift(c, 8))
        c = bxor(CRC[band(bxor(c, e), 0xFF)], rshift(c, 8))
        c = bxor(CRC[band(bxor(c, f), 0xFF)], rshift(c, 8))
        c = bxor(CRC[band(bxor(c, g), 0xFF)], rshift(c, 8))
        c = bxor(CRC[band(bxor(c, h), 0xFF)], rshift(c, 8))
        c = bxor(CRC[band(bxor(c, k), 0xFF)], rshift(c, 8))
        i = i + 8
    end
    while i <= n do
        c = bxor(CRC[band(bxor(c, byte(s, i)), 0xFF)], rshift(c, 8))
        i = i + 1
    end
    c = bit.bxor(c, 0xFFFFFFFF)
    if c < 0 then c = c + 4294967296 end
    return c
end

local function le(n, bytes)
    local out = {}
    for i = 1, bytes do
        out[i] = string.char(n % 256)
        n = math.floor(n / 256)
    end
    return table.concat(out)
end

local function u16(s, i)
    local a, b = s:byte(i, i + 1)
    return a + b * 256
end

local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function dos_time(t)
    local d = os.date("*t", t or os.time())
    local time = math.floor(d.sec / 2) + d.min * 32 + d.hour * 2048
    local date = d.day + d.month * 32 + math.max(0, d.year - 1980) * 512
    return time, date
end

function M.zip(entries, when)
    local time, date = dos_time(when)
    local parts, central = {}, {}
    local offset = 0
    for _, e in ipairs(entries) do
        local name, data = e.name, e.data
        local crc = M.crc32(data)
        local head = "PK\3\4" .. le(20, 2) .. le(0x0800, 2) .. le(0, 2) .. le(time, 2) .. le(date, 2) ..
            le(crc, 4) .. le(#data, 4) .. le(#data, 4) .. le(#name, 2) .. le(0, 2) .. name
        parts[#parts + 1] = head
        parts[#parts + 1] = data
        central[#central + 1] = "PK\1\2" .. le(20, 2) .. le(20, 2) .. le(0x0800, 2) .. le(0, 2) .. le(time, 2) .. le(date, 2) ..
            le(crc, 4) .. le(#data, 4) .. le(#data, 4) .. le(#name, 2) .. le(0, 2) .. le(0, 2) .. le(0, 2) .. le(0, 2) ..
            le(0, 4) .. le(offset, 4) .. name
        offset = offset + #head + #data
    end
    local cd = table.concat(central)
    return table.concat(parts) .. cd .. "PK\5\6" .. le(0, 2) .. le(0, 2) .. le(#entries, 2) .. le(#entries, 2) ..
        le(#cd, 4) .. le(offset, 4) .. le(0, 2)
end

function M.zip_stream(fs, list, out, progress, when)
    local time, date = dos_time(when)
    local central = {}
    local offset = 0
    local count = 0
    if not fs.write(out, "") then return nil, "write" end
    for i, e in ipairs(list) do
        local data = fs.read(e.path)
        if data then
            local name = e.name
            local crc = M.crc32(data)
            local head = "PK\3\4" .. le(20, 2) .. le(0x0800, 2) .. le(0, 2) .. le(time, 2) .. le(date, 2) ..
                le(crc, 4) .. le(#data, 4) .. le(#data, 4) .. le(#name, 2) .. le(0, 2) .. name
            if not (fs.append(out, head) and fs.append(out, data)) then return nil, "write" end
            central[#central + 1] = "PK\1\2" .. le(20, 2) .. le(20, 2) .. le(0x0800, 2) .. le(0, 2) .. le(time, 2) .. le(date, 2) ..
                le(crc, 4) .. le(#data, 4) .. le(#data, 4) .. le(#name, 2) .. le(0, 2) .. le(0, 2) .. le(0, 2) .. le(0, 2) ..
                le(0, 4) .. le(offset, 4) .. name
            offset = offset + #head + #data
            count = count + 1
        end
        data = nil
        if progress then progress(i, #list) end
    end
    local cd = table.concat(central)
    if not fs.append(out, cd .. "PK\5\6" .. le(0, 2) .. le(0, 2) .. le(count, 2) .. le(count, 2) ..
        le(#cd, 4) .. le(offset, 4) .. le(0, 2)) then return nil, "write" end
    return count
end

local function default_inflate(raw)
    return love.data.decompress("string", "deflate", raw .. "\0\0\0\0\0\0\0\0")
end

M.ZIP_SKIP = {mods = true, Mods = true, lovely = true, backups = true, crash_reports = true, cache = true, workshop = true, shots = true, updates = true}

function M.save_entry(name)
    for part in name:gmatch("([^/]+)/") do
        if M.ZIP_SKIP[part] then return false end
    end
    return true
end

local function dos_unix(date, time)
    if date == 0 then return nil end
    local ok, t = pcall(os.time, {year = 1980 + math.floor(date / 512), month = math.floor(date / 32) % 16, day = date % 32,
        hour = math.floor(time / 2048), min = math.floor(time / 32) % 64, sec = (time % 32) * 2})
    return ok and t or nil
end

function M.unzip(data, inflate, keep)
    inflate = inflate or default_inflate
    if type(data) ~= "string" or #data < 22 then return nil, "not_zip" end
    local eocd
    for i = #data - 21, math.max(1, #data - 65557), -1 do
        if data:byte(i) == 0x50 and data:sub(i, i + 3) == "PK\5\6" then
            eocd = i
            break
        end
    end
    if not eocd then return nil, "not_zip" end
    local count = u16(data, eocd + 10)
    local cd_size = u32(data, eocd + 12)
    local cd_offset = u32(data, eocd + 16)
    local concat = (eocd - 1) - cd_size - cd_offset
    if concat < 0 then return nil, "bad_zip" end
    local files, list = {}, {}
    local total = 0
    local newest = 0
    local p = cd_offset + concat + 1
    for _ = 1, count do
        if data:sub(p, p + 3) ~= "PK\1\2" then return nil, "bad_zip" end
        local method, csize, size = u16(data, p + 10), u32(data, p + 20), u32(data, p + 24)
        local stamp = u16(data, p + 14) * 65536 + u16(data, p + 12)
        local nlen, xlen, clen = u16(data, p + 28), u16(data, p + 30), u16(data, p + 32)
        local name = data:sub(p + 46, p + 45 + nlen):gsub("\\", "/")
        local lp = u32(data, p + 42) + concat + 1
        p = p + 46 + nlen + xlen + clen
        if name:sub(-1) ~= "/" and size <= M.MAX_FILE and (not keep or keep(name)) then
            total = total + size
            if total > M.MAX_TOTAL or csize > M.MAX_FILE then return nil, "too_big" end
            if data:sub(lp, lp + 3) ~= "PK\3\4" then return nil, "bad_zip" end
            local start = lp + 30 + u16(data, lp + 26) + u16(data, lp + 28)
            local raw = data:sub(start, start + csize - 1)
            local out
            if method == 0 then
                out = raw
            elseif method == 8 then
                local ok, r = pcall(inflate, raw, size)
                out = ok and type(r) == "string" and r or nil
            end
            if not out or #out ~= size then return nil, "bad_zip" end
            files[name] = out
            list[#list + 1] = name
            if stamp > newest then newest = stamp end
        end
    end
    return files, list, dos_unix(math.floor(newest / 65536), newest % 65536)
end

function M.skip(name)
    local top = name:match("^([^/]+)/")
    if top and M.SKIP_DIRS[top] then return true end
    if M.SKIP_FILES[name] then return true end
    if name:match("%.log$") or name:match("debug%.txt$") or name:match("/%.") or name:match("^%.") then return true end
    if name:match("keys?%.lua$") or name:match("token") or name:match("secret") then return true end
    return false
end

function M.unsafe(name)
    if type(name) ~= "string" or name == "" or #name > 260 then return true end
    if name:find("%z") or name:find("\\", 1, true) or name:find(":", 1, true) then return true end
    if name:sub(1, 1) == "/" or name:sub(-1) == "/" then return true end
    for part in name:gmatch("[^/]+") do
        if part == ".." or part == "." then return true end
    end
    if name:find("//", 1, true) then return true end
    local low = name:lower()
    local top = low:match("^([^/]+)/")
    if top and M.SOURCE_DIRS[top] then return true end
    if low:match("%.so$") or low:match("%.dll$") or low:match("%.dylib$") or low:match("%.exe$") then return true end
    if not top and low:match("%.lua$") and not M.ROOT_LUA[low] then return true end
    if not top and (low == "conf.lua" or low == "main.lua" or low == "version.jkr") then return true end
    return false
end

function M.slot_of(name)
    return name:match("^([^/]+)/profile%.jkr$") or name:match("^([^/]+)/meta%.jkr$")
end

function M.normalize(files)
    local best
    for name in pairs(files) do
        local prefix = name:match("^(.-)[^/]+/profile%.jkr$") or name:match("^(.-)[^/]+/meta%.jkr$")
        if prefix and (not best or #prefix < #best) then best = prefix end
    end
    if not best then return nil, "no_profile" end
    local out = {}
    for name, data in pairs(files) do
        if name:sub(1, #best) == best then
            local rel = name:sub(#best + 1)
            if rel ~= "" and not rel:match("^__MACOSX/") and not M.skip(rel) and not M.unsafe(rel) then out[rel] = data end
        end
    end
    return out
end

local DATA_WORDS = {["return"] = true, ["true"] = true, ["false"] = true, ["nil"] = true, inf = true, nan = true}

function M.plain_data(str)
    if type(str) ~= "string" or str:byte(1) == 27 then return false end
    local i = 1
    while true do
        local q = str:find('"', i, true)
        local rest = str:sub(i, q and q - 1 or -1)
        if rest:find("[^%w%s{}%[%]=,.+%-_]") then return false end
        if rest:find("--", 1, true) or rest:find("[[", 1, true) or rest:find("[=", 1, true) then return false end
        for word in rest:gmatch("%f[%w_][%a_][%w_]*") do
            if not DATA_WORDS[word] then return false end
        end
        if not q then return true end
        local j = q + 1
        while true do
            local k = str:find('["\\]', j)
            if not k then return false end
            if str:byte(k) == 92 then j = k + 2 else j = k + 1 break end
        end
        i = j
    end
end

function M.text_of(data)
    if type(data) ~= "string" or data == "" then return nil end
    if data:sub(1, 6) == "return" then return data end
    local ok, s = pcall(love.data.decompress, "string", "deflate", data .. "\0\0\0\0\0\0\0\0")
    if not ok or type(s) ~= "string" then s = data end
    return s
end

function M.read_jkr(data)
    local s = M.text_of(data)
    if not s or s:sub(1, 6) ~= "return" or not M.plain_data(s) then return nil end
    local chunk = loadstring(s)
    if not chunk then return nil end
    setfenv(chunk, {})
    local ok2, t = pcall(chunk)
    return ok2 and type(t) == "table" and t or nil
end

function M.slots(files)
    local found, seen = {}, {}
    for name in pairs(files) do
        local slot = M.slot_of(name)
        if slot and not seen[slot] then
            seen[slot] = true
            found[#found + 1] = slot
        end
    end
    table.sort(found)
    return found
end

function M.describe(files)
    local out = {}
    for _, slot in ipairs(M.slots(files)) do
        local p = M.read_jkr(files[slot .. "/profile.jkr"]) or {}
        local cs = type(p.career_stats) == "table" and p.career_stats or {}
        out[#out + 1] = {slot = slot, name = type(p.name) == "string" and p.name or nil,
            wins = tonumber(cs.c_wins) or 0, rounds = tonumber(cs.c_rounds) or 0, valid = next(p) ~= nil}
    end
    return out
end

function M.check(files)
    local slots = M.slots(files)
    if #slots == 0 then return nil, "no_profile" end
    local good = 0
    for _, slot in ipairs(slots) do
        local any = false
        for _, f in ipairs({"profile.jkr", "meta.jkr"}) do
            if files[slot .. "/" .. f] then
                if not M.read_jkr(files[slot .. "/" .. f]) then return nil, "damaged" end
                any = true
            end
        end
        if any then good = good + 1 end
    end
    return good > 0 and slots or nil, good > 0 and nil or "damaged"
end

function M.code_file(name)
    local low = tostring(name):lower()
    return low:match("%.jkr$") ~= nil or low:match("%.lua$") ~= nil
end

function M.validate(files)
    local ok, err = M.check(files)
    if not ok then return nil, err end
    local out, dropped = {}, {}
    for name, data in pairs(files) do
        if M.skip(name) or M.unsafe(name) or (M.code_file(name) and not M.plain_data(M.text_of(data) or "")) then
            dropped[#dropped + 1] = name
        else
            out[name] = data
        end
    end
    table.sort(dropped)
    if not M.check(out) then return nil, "damaged" end
    return out, dropped
end

M.MODDED = {{"1", "modded"}, {"2", "modded2"}, {"3", "modded3"}}

function M.mirror_modded(files)
    local out = {}
    for k, v in pairs(files) do out[k] = v end
    for _, pair in ipairs(M.MODDED) do
        local slot, m = pair[1], pair[2]
        local has = files[slot .. "/profile.jkr"] or files[slot .. "/meta.jkr"]
        if has and not (files[m .. "/profile.jkr"] or files[m .. "/meta.jkr"]) then
            for _, f in ipairs({"profile.jkr", "meta.jkr"}) do
                if files[slot .. "/" .. f] then out[m .. "/" .. f] = files[slot .. "/" .. f] end
            end
        end
    end
    return out
end

M.JKR_NAMES = {["profile.jkr"] = true, ["meta.jkr"] = true, ["unlock_notify.jkr"] = true, ["save.jkr"] = true}

function M.read_any(data, name)
    if type(data) ~= "string" or data == "" then return nil, "not_zip" end
    if #data > M.MAX_TOTAL then return nil, "too_big" end
    local files, when
    if data:sub(1, 2) == "PK" then
        local raw, err, w = M.unzip(data, nil, M.save_entry)
        if not raw then return nil, err end
        local nerr
        files, nerr = M.normalize(raw)
        if not files then return nil, nerr end
        when = w
    else
        local base = tostring(name or ""):gsub("\\", "/"):match("([^/]+)$") or ""
        base = base:lower()
        if not M.JKR_NAMES[base] then return nil, "not_zip" end
        files = {["1/" .. base] = data}
    end
    local good, derr = M.validate(files)
    if not good then return nil, derr end
    return good, nil, {dropped = derr, when = when}
end

local function count(t)
    local n = 0
    if type(t) == "table" then
        for _, flag in pairs(t) do
            if flag then n = n + 1 end
        end
    end
    return n
end

function M.preview(files)
    local out = {}
    local twin = {}
    for _, pair in ipairs(M.MODDED) do twin[pair[2]] = pair[1] end
    for _, slot in ipairs(M.slots(files)) do
        local base = twin[slot]
        local copy = base and files[slot .. "/profile.jkr"] and files[slot .. "/profile.jkr"] == files[base .. "/profile.jkr"]
        if not copy then
            local p = M.read_jkr(files[slot .. "/profile.jkr"]) or {}
            local meta = M.read_jkr(files[slot .. "/meta.jkr"]) or {}
            local cs = type(p.career_stats) == "table" and p.career_stats or {}
            local e = {slot = slot, name = type(p.name) == "string" and p.name ~= "" and p.name or nil,
                wins = tonumber(cs.c_wins) or 0, rounds = tonumber(cs.c_rounds) or 0,
                discovered = count(meta.discovered), unlocked = count(meta.unlocked), modded = slot:match("^modded") ~= nil}
            local run = files[slot .. "/save.jkr"] and M.read_jkr(files[slot .. "/save.jkr"])
            local game = type(run) == "table" and type(run.GAME) == "table" and run.GAME or nil
            if game then
                local rr = type(game.round_resets) == "table" and game.round_resets or {}
                e.run = {ante = tonumber(rr.ante) or 1, round = tonumber(game.round) or 0}
            end
            out[#out + 1] = e
        end
    end
    return out
end

function M.export_name(when)
    return "Balatro Overhaul save " .. os.date("%Y-%m-%d", when or os.time()) .. ".zip"
end

local function sh(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

function M.pick_command(osn, title, filter)
    title = tostring(title or ""):gsub("[%c]", " ")
    local label = filter and tostring(filter.label or "Files"):gsub("[^%w%s]", "") or "Balatro save"
    local exts = {}
    for _, e in ipairs(filter and filter.exts or {"zip", "jkr"}) do
        e = tostring(e):gsub("[^%w]", "")
        if e ~= "" then exts[#exts + 1] = "*." .. e end
    end
    if #exts == 0 then exts[1] = "*.*" end
    if osn == "Windows" then
        return 'powershell -NoProfile -NonInteractive -STA -Command "Add-Type -AssemblyName System.Windows.Forms; '
            .. "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; "
            .. "$d = New-Object System.Windows.Forms.OpenFileDialog; "
            .. "$d.Filter = '" .. label .. " (" .. table.concat(exts, ";") .. ")|" .. table.concat(exts, ";") .. "|*.*|*.*'; "
            .. 'if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $d.FileName }"'
    elseif osn == "OS X" then
        local as = 'POSIX path of (choose file with prompt "' .. title:gsub("\\", "\\\\"):gsub('"', '\\"') .. '")'
        return "osascript -e " .. sh(as) .. " 2>/dev/null"
    end
    local t = sh(title)
    local pats = table.concat(exts, " ")
    return "if command -v zenity >/dev/null 2>&1; then zenity --file-selection --title=" .. t ..
        " --file-filter='" .. pats .. "' 2>/dev/null; elif command -v kdialog >/dev/null 2>&1; then kdialog --title " .. t ..
        " --getopenfilename \"$HOME\" '" .. pats .. "' 2>/dev/null; else echo 'rc:none'; fi"
end

function M.save_command(osn, title, name)
    title = tostring(title or ""):gsub("[%c]", " ")
    name = tostring(name or "save.zip"):gsub("[^%w%s%-%._]", "")
    if osn == "Windows" then
        return 'powershell -NoProfile -NonInteractive -STA -Command "Add-Type -AssemblyName System.Windows.Forms; '
            .. "[Console]::OutputEncoding = [System.Text.Encoding]::UTF8; "
            .. "$d = New-Object System.Windows.Forms.SaveFileDialog; "
            .. "$d.Filter = 'Zip (*.zip)|*.zip'; $d.FileName = '" .. name .. "'; "
            .. 'if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { Write-Output $d.FileName }"'
    elseif osn == "OS X" then
        local as = 'POSIX path of (choose file name with prompt "' .. title:gsub("\\", "\\\\"):gsub('"', '\\"') .. '" default name "' .. name .. '")'
        return "osascript -e " .. sh(as) .. " 2>/dev/null"
    end
    local t = sh(title)
    return "if command -v zenity >/dev/null 2>&1; then zenity --file-selection --save --confirm-overwrite --title=" .. t ..
        " --filename=\"$HOME/\"" .. sh(name) .. " 2>/dev/null; elif command -v kdialog >/dev/null 2>&1; then kdialog --title " .. t ..
        " --getsavefilename \"$HOME/\"" .. sh(name) .. " '*.zip' 2>/dev/null; else echo 'rc:none'; fi"
end

M.DIALOG_THREAD = [[
require("love.thread")
local cmd, chan = ...
local h = io.popen(cmd)
local out = h and h:read("*a") or "rc:none"
if h then h:close() end
love.thread.getChannel(chan):push(out)
]]

function M.dialog_osn(osn)
    return osn == "Windows" or osn == "OS X" or osn == "Linux"
end

function M.dialog_start(cmd)
    local chan = "save_dialog_" .. tostring(math.random(100000, 999999))
    local ok, th = pcall(love.thread.newThread, M.DIALOG_THREAD)
    if not ok or not th then return nil end
    love.thread.getChannel(chan):clear()
    th:start(cmd, chan)
    return {thread = th, chan = chan}
end

function M.dialog_poll(job)
    local out = love.thread.getChannel(job.chan):pop()
    if out == nil then
        if job.thread:getError() then return "none" end
        return nil
    end
    if out:match("rc:none") then return "none" end
    for line in out:gmatch("[^\r\n]+") do
        if not line:match("^%s*$") then return "ok", (line:gsub("^%s+", ""):gsub("%s+$", "")) end
    end
    return "cancel"
end

function M.write_file(path, data)
    local tmp = path .. ".part"
    local f = io.open(tmp, "wb")
    if not f then return nil end
    local ok = f:write(data)
    f:close()
    local back = io.open(tmp, "rb")
    local same = back and back:read("*a") == data
    if back then back:close() end
    if not ok or not same then
        os.remove(tmp)
        return nil
    end
    os.remove(path)
    if not os.rename(tmp, path) then
        os.remove(tmp)
        return nil
    end
    return true
end

function M.read_path(path)
    local f = io.open(path, "rb")
    if not f then return nil, "not_found" end
    local size = f:seek("end")
    if size and size > M.MAX_TOTAL then
        f:close()
        return nil, "too_big"
    end
    f:seek("set", 0)
    local data = f:read("*a")
    f:close()
    return data
end

function M.read_folder_io(dir, read)
    read = read or function(p) return (M.read_path(p)) end
    local files, n = {}, 0
    for _, slot in ipairs(M.SLOTS) do
        for f in pairs(M.JKR_NAMES) do
            local data = read(dir .. "/" .. slot .. "/" .. f)
            if data and #data > 0 and #data <= M.MAX_FILE then
                files[slot .. "/" .. f] = data
                n = n + 1
            end
        end
    end
    if n == 0 then return nil, "no_profile" end
    return M.validate(files)
end

function M.entries(files)
    local names = {}
    for name in pairs(files) do names[#names + 1] = name end
    table.sort(names)
    local out = {}
    for _, name in ipairs(names) do out[#out + 1] = {name = name, data = files[name]} end
    return out
end

function M.collect(fs, root, skip)
    local files, total = {}, 0
    local save = fs.getSaveDirectory and fs.getSaveDirectory()
    local function walk(dir)
        for _, item in ipairs(fs.getDirectoryItems(dir)) do
            local path = dir == "" and item or (dir .. "/" .. item)
            local real = fs.getRealDirectory and fs.getRealDirectory(path)
            if not save or real == save then
                local info = fs.getInfo(path)
                if info and info.type == "directory" then
                    if not (skip or M.skip)(path .. "/x") then walk(path) end
                elseif info and info.type == "file" and not (skip or M.skip)(path) and (info.size or 0) <= M.MAX_FILE then
                    local data = fs.read(path)
                    if data and total + #data <= M.MAX_TOTAL then
                        files[path] = data
                        total = total + #data
                    end
                end
            end
        end
    end
    walk(root or "")
    return files, total
end

function M.vanilla_only(files)
    local out = {}
    for _, slot in ipairs(M.slots(files)) do
        for _, f in ipairs(M.VANILLA_FILES) do
            local name = slot .. "/" .. f
            if files[name] then out[name] = files[name] end
        end
    end
    return out
end

local function own(fs, p)
    return not fs.getRealDirectory or fs.getRealDirectory(p) == fs.getSaveDirectory()
end

function M.touched(fs, files)
    local out = {}
    for _, slot in ipairs(M.slots(files)) do
        if fs.getInfo(slot) then
            for _, item in ipairs(fs.getDirectoryItems(slot)) do
                local p = slot .. "/" .. item
                local info = fs.getInfo(p)
                if info and info.type == "file" and own(fs, p) then out[p] = true end
            end
        end
    end
    for name in pairs(files) do
        local info = fs.getInfo(name)
        if info and info.type == "file" and own(fs, name) then out[name] = true end
    end
    return out
end

function M.with_touched(fs, files, base)
    local out = {}
    for k, v in pairs(base or {}) do out[k] = v end
    for p in pairs(M.touched(fs, files)) do
        if out[p] == nil then out[p] = fs.read(p) end
    end
    return out
end

function M.apply(fs, files, backed)
    if backed then
        for p in pairs(M.touched(fs, files)) do
            if backed[p] == nil or backed[p] ~= fs.read(p) then return nil, "changed" end
        end
    end
    local wrote = 0
    for _, slot in ipairs(M.slots(files)) do
        if fs.getInfo(slot) then
            for _, item in ipairs(fs.getDirectoryItems(slot)) do
                local p = slot .. "/" .. item
                local info = fs.getInfo(p)
                if info and info.type == "file" and own(fs, p) then
                    fs.remove(p)
                end
            end
        end
    end
    for _, e in ipairs(M.entries(files)) do
        if not M.skip(e.name) and not M.unsafe(e.name) then
            local dir = e.name:match("^(.*)/[^/]*$")
            if dir then fs.createDirectory(dir) end
            if not fs.write(e.name, e.data) then return nil, e.name end
            wrote = wrote + 1
        end
    end
    return wrote
end

function M.stamp(t)
    return os.date("%Y-%m-%d_%H-%M-%S", t or os.time())
end

function M.same(files, back)
    if type(back) ~= "table" then return false end
    local n = 0
    for name, data in pairs(files) do
        if back[name] ~= data then return false end
        n = n + 1
    end
    for _ in pairs(back) do n = n - 1 end
    return n == 0
end

function M.free_name(fs, dir, tag, when)
    local base = dir .. "/" .. tag .. "-" .. M.stamp(when)
    local name = base .. ".zip"
    local i = 1
    while fs.getInfo(name) do
        i = i + 1
        name = base .. "-" .. i .. ".zip"
    end
    return name
end

function M.backup(fs, dir, tag, files)
    if not files or not next(files) then return true end
    fs.createDirectory(dir)
    local name = M.free_name(fs, dir, tag)
    local data = M.zip(M.entries(files))
    if not fs.write(name, data) then return nil, "backup" end
    local back = M.unzip(fs.read(name) or "")
    if not M.same(files, back) then return nil, "backup" end
    return name
end

function M.lock_text(pid, now)
    return string.format("%d %d\n", tonumber(pid) or 0, now or os.time())
end

function M.lock_alive(text, now, pid_alive)
    if type(text) ~= "string" then return false end
    local pid, t = text:match("^(%d+)%s+(%d+)")
    t = tonumber(t)
    if not t then return false end
    now = now or os.time()
    if math.abs(now - t) > M.LOCK_STALE then return false end
    pid = tonumber(pid)
    if pid and pid > 0 and pid_alive and pid_alive(pid) == false then return false end
    return true
end

return M
