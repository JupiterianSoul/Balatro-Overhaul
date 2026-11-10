local bit = require("bit")

local M = {}

M.SLOTS = {"1", "2", "3"}
M.VANILLA_FILES = {"profile.jkr", "meta.jkr", "unlock_notify.jkr"}
M.SKIP_DIRS = {
    backups = true, exports = true, imports = true, crash_reports = true, bot = true, mods = true, Mods = true,
    lovely = true, workshop = true, cache = true, shots = true, updates = true, Overhaul = true, ["Overhaul.new"] = true,
}
M.SKIP_FILES = {["settings.jkr"] = true, ["modded_settings.jkr"] = true, ["version.jkr"] = true}
M.MAX_FILE = 16 * 1024 * 1024
M.MAX_TOTAL = 96 * 1024 * 1024

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

function M.crc32(s)
    local c = 0xFFFFFFFF
    for i = 1, #s do
        c = bit.bxor(CRC[bit.band(bit.bxor(c, s:byte(i)), 0xFF)], bit.rshift(c, 8))
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

local function default_inflate(raw)
    return love.data.decompress("string", "deflate", raw)
end

function M.unzip(data, inflate)
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
    local p = cd_offset + concat + 1
    for _ = 1, count do
        if data:sub(p, p + 3) ~= "PK\1\2" then return nil, "bad_zip" end
        local method, csize, size = u16(data, p + 10), u32(data, p + 20), u32(data, p + 24)
        local nlen, xlen, clen = u16(data, p + 28), u16(data, p + 30), u16(data, p + 32)
        local name = data:sub(p + 46, p + 45 + nlen):gsub("\\", "/")
        local lp = u32(data, p + 42) + concat + 1
        p = p + 46 + nlen + xlen + clen
        if name:sub(-1) ~= "/" and size <= M.MAX_FILE then
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
        end
    end
    return files, list
end

function M.skip(name)
    local top = name:match("^([^/]+)/")
    if top and M.SKIP_DIRS[top] then return true end
    if M.SKIP_FILES[name] then return true end
    if name:match("%.log$") or name:match("debug%.txt$") or name:match("/%.") or name:match("^%.") then return true end
    if name:match("keys?%.lua$") or name:match("token") or name:match("secret") then return true end
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
            if rel ~= "" and not rel:match("^__MACOSX/") and not M.skip(rel) then out[rel] = data end
        end
    end
    return out
end

function M.read_jkr(data)
    if type(data) ~= "string" or data == "" then return nil end
    local ok, s = pcall(love.data.decompress, "string", "deflate", data)
    if not ok or type(s) ~= "string" then s = data end
    if s:sub(1, 6) ~= "return" then return nil end
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

function M.apply(fs, files)
    local wrote = 0
    for _, slot in ipairs(M.slots(files)) do
        if fs.getInfo(slot) then
            for _, item in ipairs(fs.getDirectoryItems(slot)) do
                local p = slot .. "/" .. item
                local info = fs.getInfo(p)
                if info and info.type == "file" and (not fs.getRealDirectory or fs.getRealDirectory(p) == fs.getSaveDirectory()) then
                    fs.remove(p)
                end
            end
        end
    end
    for _, e in ipairs(M.entries(files)) do
        if not M.skip(e.name) and not e.name:match("%.%.") then
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

function M.prune(fs, dir, keep)
    local items = {}
    for _, name in ipairs(fs.getDirectoryItems(dir)) do
        if name:match("%.zip$") then items[#items + 1] = name end
    end
    table.sort(items)
    for i = 1, #items - keep do fs.remove(dir .. "/" .. items[i]) end
end

return M
