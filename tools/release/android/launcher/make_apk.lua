local E = require("android.p256")
local bit = require("bit")
local has_ffi, ffi = pcall(require, "ffi")

local M = {}

M.RUNTIME = "android/runtime.apk"
M.BOOTSTRAP = "android/bootstrap"
M.PATCHER = {"patcher/apply.lua", "patcher/zipread.lua", "android/patcher/love_ctx.lua"}
M.KEY = "android/player-key.txt"
M.CHUNK = 1048576
M.STORE_EXT = {ogg = true, png = true, jpg = true, jpeg = true, mp3 = true, ogv = true, zip = true, love = true}
M.ICON_DENSITY = {mdpi = 48, hdpi = 72, xhdpi = 96, xxhdpi = 144, xxxhdpi = 192}

local floor = math.floor
local DOS_DATE = (2026 - 1980) * 512 + 1 * 32 + 1
local DOS_TIME = 0

local function u16(n)
    return string.char(n % 256, floor(n / 256) % 256)
end

local function u32(n)
    return string.char(n % 256, floor(n / 256) % 256, floor(n / 65536) % 256, floor(n / 16777216) % 256)
end

local function u64(n)
    return u32(n % 4294967296) .. u32(floor(n / 4294967296))
end

local function r16(s, i)
    local a, b = s:byte(i, i + 1)
    return a + b * 256
end

local function r32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function sha256(s)
    return love.data.hash("sha256", s)
end

local function hex(s)
    return love.data.encode("string", "hex", s)
end

local CRC = {}
for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
        if bit.band(c, 1) == 1 then
            c = bit.bxor(0xEDB88320, bit.rshift(c, 1))
        else
            c = bit.rshift(c, 1)
        end
    end
    CRC[i] = c
end

local crc_ffi
if has_ffi then
    local T = ffi.new("uint32_t[256]")
    for i = 0, 255 do T[i] = CRC[i] end
    crc_ffi = function(s, c)
        local p = ffi.cast("const uint8_t*", s)
        local v = bit.bnot(c)
        for i = 0, #s - 1 do
            v = bit.bxor(T[bit.band(bit.bxor(v, p[i]), 255)], bit.rshift(v, 8))
        end
        return bit.bnot(v)
    end
end

local function crc_update(c, s)
    if crc_ffi then return crc_ffi(s, c) end
    c = bit.bnot(c)
    for i = 1, #s do
        c = bit.bxor(CRC[bit.band(bit.bxor(c, s:byte(i)), 255)], bit.rshift(c, 8))
    end
    return bit.bnot(c)
end

local function unsigned(c)
    c = c % 4294967296
    if c < 0 then c = c + 4294967296 end
    return c
end

function M.crc32(s)
    return unsigned(crc_update(0, s))
end

local function ext_of(name)
    return (name:match("%.([%w]+)$") or ""):lower()
end

local function writer()
    return {parts = {}, pos = 0, cd = {}}
end

local function w_add(w, name, method, crc, csize, usize, data, align)
    local extra = ""
    if align then
        local base = w.pos + 30 + #name
        local pad = (align - (base + 6) % align) % align
        extra = u16(0xD935) .. u16(2 + pad) .. u16(align) .. string.rep("\0", pad)
    end
    local flags = name:find("[\128-\255]") and 0x0800 or 0
    local need = method == 8 and 20 or 10
    local lh = "PK\3\4" .. u16(need) .. u16(flags) .. u16(method) .. u16(DOS_TIME) .. u16(DOS_DATE) .. u32(crc)
        .. u32(csize) .. u32(usize) .. u16(#name) .. u16(#extra) .. name .. extra
    w.cd[#w.cd + 1] = "PK\1\2" .. u16(20) .. u16(need) .. u16(flags) .. u16(method) .. u16(DOS_TIME) .. u16(DOS_DATE)
        .. u32(crc) .. u32(csize) .. u32(usize) .. u16(#name) .. u16(0) .. u16(0) .. u16(0) .. u16(0) .. u32(0)
        .. u32(w.pos) .. name
    w.parts[#w.parts + 1] = lh
    w.pos = w.pos + #lh
    if type(data) == "table" then
        for _, p in ipairs(data) do
            w.parts[#w.parts + 1] = p
            w.pos = w.pos + #p
        end
    else
        w.parts[#w.parts + 1] = data
        w.pos = w.pos + #data
    end
end

local function w_file(w, name, data, store)
    local crc = M.crc32(data)
    if not store then
        local packed = love.data.compress("string", "deflate", data, 9)
        if #packed < #data then
            return w_add(w, name, 8, crc, #packed, #data, packed)
        end
    end
    return w_add(w, name, 0, crc, #data, #data, data)
end

local function w_central(w, cd_offset)
    local cd = table.concat(w.cd)
    local n = #w.cd
    local eocd = "PK\5\6" .. u16(0) .. u16(0) .. u16(n) .. u16(n) .. u32(#cd) .. u32(cd_offset or w.pos) .. u16(0)
    return cd, eocd
end

function M.read_zip(data)
    if type(data) ~= "string" or #data < 22 then return nil, "not_zip" end
    local eocd
    for i = #data - 21, math.max(1, #data - 65557), -1 do
        if data:byte(i) == 0x50 and data:sub(i, i + 3) == "PK\5\6" then
            eocd = i
            break
        end
    end
    if not eocd then return nil, "not_zip" end
    local count, cd_size, cd_offset = r16(data, eocd + 10), r32(data, eocd + 12), r32(data, eocd + 16)
    local concat = (eocd - 1) - cd_size - cd_offset
    if concat < 0 then return nil, "bad_zip" end
    local list = {}
    local p = cd_offset + concat + 1
    for _ = 1, count do
        if data:sub(p, p + 3) ~= "PK\1\2" then return nil, "bad_zip" end
        local nlen, xlen, clen = r16(data, p + 28), r16(data, p + 30), r16(data, p + 32)
        local e = {
            method = r16(data, p + 10), crc = r32(data, p + 16), csize = r32(data, p + 20),
            size = r32(data, p + 24), offset = r32(data, p + 42) + concat,
            name = data:sub(p + 46, p + 45 + nlen),
        }
        p = p + 46 + nlen + xlen + clen
        if e.name:sub(-1) ~= "/" then
            list[#list + 1] = e
        end
    end
    local function raw(e)
        local q = e.offset + 1
        if data:sub(q, q + 3) ~= "PK\3\4" then return nil end
        local start = q + 30 + r16(data, q + 26) + r16(data, q + 28)
        return data:sub(start, start + e.csize - 1)
    end
    local function read(e)
        local r = raw(e)
        if not r then return nil end
        if e.method == 0 then return r end
        if e.method == 8 then
            local ok, out = pcall(love.data.decompress, "string", "deflate", r)
            if ok and type(out) == "string" and #out == e.size then return out end
        end
        return nil
    end
    return {list = list, raw = raw, read = read}
end

local function der_len(n)
    if n < 128 then return string.char(n) end
    if n < 256 then return "\129" .. string.char(n) end
    if n < 65536 then return "\130" .. string.char(floor(n / 256), n % 256) end
    return "\131" .. string.char(floor(n / 65536), floor(n / 256) % 256, n % 256)
end

local function tlv(tag, body)
    return string.char(tag) .. der_len(#body) .. body
end

local function seq(...)
    return tlv(0x30, table.concat({...}))
end

local function oid(s)
    local arcs = {}
    for n in s:gmatch("%d+") do arcs[#arcs + 1] = tonumber(n) end
    local out = {string.char(arcs[1] * 40 + arcs[2])}
    for i = 3, #arcs do
        local v, t = arcs[i], {}
        t[1] = string.char(v % 128)
        v = floor(v / 128)
        while v > 0 do
            table.insert(t, 1, string.char(128 + v % 128))
            v = floor(v / 128)
        end
        out[#out + 1] = table.concat(t)
    end
    return tlv(0x06, table.concat(out))
end

local function der_uint(b)
    b = b:gsub("^%z+", "")
    if b == "" then b = "\0" end
    if b:byte(1) >= 128 then b = "\0" .. b end
    return tlv(0x02, b)
end

local function name(cn)
    return seq(
        tlv(0x31, seq(oid("2.5.4.3"), tlv(0x0C, cn))),
        tlv(0x31, seq(oid("2.5.4.10"), tlv(0x0C, "Balatro Overhaul"))))
end

function M.spki(pub)
    return seq(seq(oid("1.2.840.10045.2.1"), oid("1.2.840.10045.3.1.7")), tlv(0x03, "\0" .. pub))
end

local function nonce(d, h, counter)
    return sha256(d .. h .. string.char(counter) .. "overhaul apk nonce")
end

function M.sign(d, data)
    return E.sign(d, sha256(data), nonce)
end

function M.certificate(d)
    local pub = E.public(d)
    if not pub then return nil end
    local alg = seq(oid("1.2.840.10045.4.3.2"))
    local who = name("Balatro Overhaul player build")
    local serial = sha256(pub):sub(1, 8)
    local tbs = seq(
        der_uint(serial), alg, who,
        seq(tlv(0x17, "260101000000Z"), tlv(0x18, "21260101000000Z")),
        who, M.spki(pub))
    return seq(tbs, alg, tlv(0x03, "\0" .. M.sign(d, tbs))), pub
end

local function random_seed()
    local bits = {}
    local f = io.open("/dev/urandom", "rb")
    if f then
        bits[#bits + 1] = f:read(64) or ""
        f:close()
    end
    bits[#bits + 1] = tostring(os.time()) .. tostring(os.clock()) .. tostring({}) .. tostring(love.timer.getTime())
    for _ = 1, 64 do
        bits[#bits + 1] = tostring(love.math.random()) .. tostring(love.timer.getTime())
    end
    return sha256(table.concat(bits))
end

function M.player_key()
    local saved = love.filesystem.read(M.KEY)
    local h = saved and saved:match("^(%x+)")
    if h and #h == 64 then
        local d = love.data.decode("string", "hex", h)
        if E.valid_private(d) then return d end
    end
    local d
    repeat
        d = E.private_from_seed(random_seed())
    until d
    love.filesystem.createDirectory("android")
    love.filesystem.write(M.KEY, hex(d) .. "\n")
    return d
end

local function chunk_digests(parts, out, yield)
    local buf, have = {}, 0
    local function flush()
        local chunk = table.concat(buf)
        out[#out + 1] = sha256("\165" .. u32(#chunk) .. chunk)
        buf, have = {}, 0
        if yield then yield() end
    end
    for _, p in ipairs(parts) do
        local i = 1
        while i <= #p do
            local take = math.min(M.CHUNK - have, #p - i + 1)
            buf[#buf + 1] = (i == 1 and take == #p) and p or p:sub(i, i + take - 1)
            have = have + take
            i = i + take
            if have == M.CHUNK then flush() end
        end
    end
    if have > 0 then flush() end
end

function M.v2_block(parts, cd, eocd, d, cert, pub, yield)
    local digs = {}
    chunk_digests(parts, digs, yield)
    chunk_digests({cd}, digs)
    chunk_digests({eocd}, digs)
    local top = sha256("\90" .. u32(#digs) .. table.concat(digs))
    local function lp(s) return u32(#s) .. s end
    local signed = lp(lp(u32(0x0201) .. lp(top))) .. lp(lp(cert)) .. lp("")
    local sig = M.sign(d, signed)
    local signer = lp(signed) .. lp(lp(u32(0x0201) .. lp(sig))) .. lp(M.spki(pub))
    local value = lp(lp(signer))
    local pair = u64(4 + #value) .. u32(0x7109871A) .. value
    local size = #pair + 8 + 16
    return u64(size) .. pair .. u64(size) .. "APK Sig Block 42"
end

local SKIP_META = {SF = true, RSA = true, DSA = true, EC = true}

local function drop_meta(n)
    if n:sub(1, 9) ~= "META-INF/" then return false end
    if n == "META-INF/MANIFEST.MF" then return true end
    return SKIP_META[n:match("%.(%u+)$") or ""] or false
end

function M.assemble(runtime, game_parts, game_size, game_crc, icons, d, yield)
    local z, err = M.read_zip(runtime)
    if not z then return nil, err end
    local w = writer()
    local seen = {}
    for _, e in ipairs(z.list) do
        local n = e.name
        if not seen[n] and not drop_meta(n) then
            seen[n] = true
            if n == "assets/game.love" then return nil, "runtime_has_game" end
            local icon = icons and icons[n]
            if icon then
                w_add(w, n, 0, M.crc32(icon), #icon, #icon, icon, 4)
            else
                local raw = z.raw(e)
                if not raw then return nil, "bad_runtime" end
                local align = e.method == 0 and (n:sub(-3) == ".so" and 4096 or 4) or nil
                w_add(w, n, e.method, e.crc, e.csize, e.size, raw, align)
            end
        end
    end
    if not seen["AndroidManifest.xml"] or not seen["assets/overhaul_runtime.json"] then return nil, "bad_runtime" end
    w_add(w, "assets/game.love", 0, game_crc, game_size, game_size, game_parts, 4)
    local cd, eocd = w_central(w)
    local cert, pub = M.certificate(d)
    if not cert then return nil, "key" end
    local block = M.v2_block(w.parts, cd, eocd, d, cert, pub, yield)
    local _, final_eocd = w_central(w, w.pos + #block)
    local out = w.parts
    out[#out + 1] = block
    out[#out + 1] = cd
    out[#out + 1] = final_eocd
    return out, cert
end

local function walk(dir, prefix, out)
    for _, item in ipairs(love.filesystem.getDirectoryItems(dir)) do
        local p = dir .. "/" .. item
        local info = love.filesystem.getInfo(p)
        if info and info.type == "directory" then
            walk(p, prefix .. item .. "/", out)
        elseif info then
            out[#out + 1] = {path = p, name = prefix .. item}
        end
    end
    return out
end

local function loose_files(dir)
    local base = dir:gsub("[/\\]+$", "")
    local cmd
    if love.system.getOS() == "Windows" then
        cmd = 'dir /s /b /a-d "' .. base:gsub("/", "\\") .. '"'
    else
        cmd = "find '" .. base:gsub("'", "'\\''") .. "' -type f"
    end
    local h = io.popen(cmd)
    if not h then return nil end
    local list = {}
    for line in h:lines() do
        line = line:gsub("\r$", "")
        local rel = line:sub(#base + 2):gsub("\\", "/")
        if rel ~= "" then list[#list + 1] = {full = line, name = rel} end
    end
    h:close()
    return list
end

local function read_abs(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

function M.game_love(C, path, yield)
    local m = C.manifest()
    if not m then return nil, "no_patch" end
    local w = writer()
    local count = 0
    local function tick()
        count = count + 1
        if count % 40 == 0 and yield then yield() end
    end
    for _, f in ipairs(walk(M.BOOTSTRAP, "", {})) do
        w_file(w, f.name, love.filesystem.read(f.path))
    end
    for _, p in ipairs(M.PATCHER) do
        local data = love.filesystem.read(p)
        if not data then return nil, "missing " .. p end
        w_file(w, "patcher/" .. p:match("([^/]+)$"), data)
    end
    for _, f in ipairs(walk(C.root, "", {})) do
        w_file(w, "patch/" .. f.name, love.filesystem.read(f.path), M.STORE_EXT[ext_of(f.name)])
        tick()
    end
    if C.is_loose(path) then
        local list = loose_files(path)
        if not list or #list == 0 then return nil, "read" end
        for _, f in ipairs(list) do
            if f.name:sub(1, 7) ~= "dexopt/" then
                local data = read_abs(f.full)
                if not data then return nil, "read" end
                w_file(w, "vanilla/" .. f.name, data, M.STORE_EXT[ext_of(f.name)])
                tick()
            end
        end
    else
        local data = read_abs(path)
        local z = data and M.read_zip(data)
        if not z then return nil, "read" end
        for _, e in ipairs(z.list) do
            if e.name:sub(1, 7) ~= "dexopt/" and (e.method == 0 or e.method == 8) then
                local raw = z.raw(e)
                if not raw then return nil, "read" end
                w_add(w, "vanilla/" .. e.name, e.method, e.crc, e.csize, e.size, raw)
                tick()
            end
        end
    end
    local cd, eocd = w_central(w)
    local parts = w.parts
    parts[#parts + 1] = cd
    parts[#parts + 1] = eocd
    local size, crc = 0, 0
    for i, p in ipairs(parts) do
        size = size + #p
        crc = crc_update(crc, p)
        if i % 200 == 0 and yield then yield() end
    end
    return parts, size, unsigned(crc), m
end

function M.write(path, parts)
    local f = io.open(path .. ".part", "wb")
    if not f then return nil, "write" end
    for _, p in ipairs(parts) do
        if not f:write(p) then
            f:close()
            os.remove(path .. ".part")
            return nil, "write"
        end
    end
    f:close()
    os.remove(path)
    if not os.rename(path .. ".part", path) then return nil, "write" end
    return path
end

function M.icons(runtime, make)
    if type(make) ~= "function" then return nil end
    local z = M.read_zip(runtime)
    if not z then return nil end
    local out = {}
    for _, e in ipairs(z.list) do
        local dens = e.name:match("^res/drawable%-(%a+)dpi[^/]*/love%.png$") or e.name:match("^res/mipmap%-(%a+)dpi[^/]*/love%.png$")
        local size = dens and M.ICON_DENSITY[dens .. "dpi"]
        if size then
            local ok, png = pcall(make, size)
            if ok and type(png) == "string" then out[e.name] = png end
        end
    end
    return out
end

M.APP_FILES = {"conf.lua", "main.lua", "overhaul_install.lua", "https.lua", "json.lua"}
M.APP_DIRS = {"launcher", "patcher", "patch", "patch_pc"}
M.APP_SKIP = "launcher/android/"

local function finish_love(w, yield)
    local cd, eocd = w_central(w)
    local parts = w.parts
    parts[#parts + 1] = cd
    parts[#parts + 1] = eocd
    local size, crc = 0, 0
    for i, p in ipairs(parts) do
        size = size + #p
        crc = crc_update(crc, p)
        if i % 200 == 0 and yield then yield() end
    end
    return parts, size, unsigned(crc)
end

function M.phone_love(o)
    local w = writer()
    local save = love.filesystem.getSaveDirectory()
    local function from_source(p)
        return love.filesystem.getRealDirectory(p) ~= save
    end
    local files = {}
    for _, n in ipairs(M.APP_FILES) do
        if from_source(n) then files[#files + 1] = {path = n, name = n} end
    end
    for _, dir in ipairs(M.APP_DIRS) do
        for _, f in ipairs(walk(dir, dir .. "/", {})) do
            if from_source(f.path) and f.name:sub(1, #M.APP_SKIP) ~= M.APP_SKIP then files[#files + 1] = f end
        end
    end
    local total = #files + #o.vanilla.list
    local count = 0
    local function tick()
        count = count + 1
        if count % 25 == 0 and o.yield then o.yield(count, total) end
    end
    for _, f in ipairs(files) do
        local data = love.filesystem.read(f.path)
        if not data then return nil, "missing " .. f.name end
        w_file(w, f.name, data, M.STORE_EXT[ext_of(f.name)])
        tick()
    end
    w_file(w, "direct_play", "1\n")
    local names = {}
    for n in pairs(o.carry or {}) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        w_file(w, "carry/" .. n, o.carry[n])
    end
    for _, e in ipairs(o.vanilla.list) do
        local raw = o.vanilla.raw(e)
        if not raw then return nil, "read" end
        w_add(w, "vanilla/" .. e.rel, e.method, e.crc, e.csize, e.size, raw)
        tick()
    end
    return finish_love(w, o.yield)
end

function M.build_phone_app(o)
    local runtime = love.filesystem.read(M.RUNTIME)
    if not runtime then return nil, "no_runtime" end
    local parts, size, crc = M.phone_love(o)
    if not parts then return nil, size end
    local icons = M.icons(runtime, o.icon)
    local d = M.player_key()
    local apk, err = M.assemble(runtime, parts, size, crc, icons, d, o.yield)
    if not apk then return nil, err end
    parts = nil
    return M.write(o.out, apk)
end

function M.run(o)
    local C = require("core")
    local yield = function()
        if o.progress then o.progress(1, 1) end
    end
    local ok_check, cerr = C.full_check(o.game_path, function() coroutine.yield() end)
    if not ok_check then
        return nil, type(cerr) == "table" and cerr or tostring(cerr)
    end
    local runtime = love.filesystem.read(M.RUNTIME)
    if not runtime then return nil, "no runtime" end
    local parts, size, crc, m = M.game_love(C, o.game_path, yield)
    if not parts then return nil, size end
    local icons = M.icons(runtime, o.icon)
    local d = M.player_key()
    local apk, err = M.assemble(runtime, parts, size, crc, icons, d, yield)
    if not apk then return nil, err end
    local file = (o.out_dir or love.filesystem.getSaveDirectory()) .. "/BalatroOverhaul-" .. (tostring(m.overhaul_name or ""):match("^[%d.]+") or tostring(m.overhaul_version)) .. ".apk"
    return M.write(file, apk)
end

return M
