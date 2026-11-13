local E = require("android.p256")
local bit = require("bit")
local has_ffi, ffi = pcall(require, "ffi")

local M = {}

M.RUNTIME = "android/runtime.apk"
M.BOOTSTRAP = "android/bootstrap"
M.PATCHER = {"patcher/apply.lua", "patcher/zipread.lua", "android/patcher/love_ctx.lua"}
M.KEY = "android/player-key.txt"
M.CHUNK = 1048576
M.GAME_TMP = "android/game.part"
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

local function inflate(raw)
    local ok, out = pcall(love.data.decompress, "string", "deflate", raw .. "\0\0\0\0\0\0\0\0")
    return ok and type(out) == "string" and out or nil
end

local function b64(s)
    return love.data.encode("string", "base64", s)
end

local function plen(p)
    return type(p) == "string" and #p or p:getSize()
end

local function piece(p, i, n)
    if type(p) ~= "string" then
        return ffi.string(ffi.cast("const char *", p:getFFIPointer()) + (i - 1), n)
    end
    if i == 1 and n == #p then return p end
    return p:sub(i, i + n - 1)
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
        w.pos = w.pos + plen(data)
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
            local out = inflate(r)
            if out and #out == e.size then return out end
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

local function cert_id(pub)
    return name("Balatro Overhaul player build"), der_uint(sha256(pub):sub(1, 8))
end

function M.certificate(d)
    local pub = E.public(d)
    if not pub then return nil end
    local alg = seq(oid("1.2.840.10045.4.3.2"))
    local who, serial = cert_id(pub)
    local tbs = seq(
        serial, alg, who,
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
        local i, n = 1, plen(p)
        while i <= n do
            local take = math.min(M.CHUNK - have, n - i + 1)
            buf[#buf + 1] = piece(p, i, take)
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

local function mf_line(out, key, value)
    local s = key .. ": " .. value
    out[#out + 1] = s:sub(1, 72)
    for i = 73, #s, 71 do
        out[#out + 1] = "\r\n " .. s:sub(i, i + 70)
    end
    out[#out + 1] = "\r\n"
end

local function mf_section(entry, digest)
    local out = {}
    mf_line(out, "Name", entry)
    mf_line(out, "SHA-256-Digest", b64(digest))
    out[#out + 1] = "\r\n"
    return table.concat(out)
end

function M.v1_files(digests, d, cert, pub)
    local by = "Created-By: 1.0 (Balatro Overhaul)\r\n"
    local mf, sf = {"Manifest-Version: 1.0\r\n" .. by .. "\r\n"}, {}
    for _, e in ipairs(digests) do
        local section = mf_section(e[1], e[2])
        mf[#mf + 1] = section
        sf[#sf + 1] = mf_section(e[1], sha256(section))
    end
    local manifest = table.concat(mf)
    local signed = "Signature-Version: 1.0\r\n" .. by .. "SHA-256-Digest-Manifest: " .. b64(sha256(manifest))
        .. "\r\nX-Android-APK-Signed: 2\r\n\r\n" .. table.concat(sf)
    local sha = seq(oid("2.16.840.1.101.3.4.2.1"), "\5\0")
    local signer = seq("\2\1\1", seq(cert_id(pub)), sha, seq(oid("1.2.840.10045.2.1"), "\5\0"), tlv(0x04, M.sign(d, signed)))
    local data = seq("\2\1\1", tlv(0x31, sha), seq(oid("1.2.840.113549.1.7.1")), tlv(0xA0, cert), tlv(0x31, signer))
    return manifest, signed, seq(oid("1.2.840.113549.1.7.2"), tlv(0xA0, data))
end

local function one_block(parts, size)
    if has_ffi then
        love.filesystem.createDirectory("android")
        local f = love.filesystem.newFile(M.GAME_TMP)
        local ok = f:open("w")
        for i = 1, #parts do
            if not ok then break end
            ok = f:write(parts[i])
        end
        f:close()
        if ok then
            for i = #parts, 1, -1 do parts[i] = nil end
            collectgarbage()
            collectgarbage()
            local read, data = pcall(love.filesystem.newFileData, M.GAME_TMP)
            love.filesystem.remove(M.GAME_TMP)
            if read and data and data:getSize() == size then return data end
            return nil
        end
        love.filesystem.remove(M.GAME_TMP)
    end
    return table.concat(parts)
end

function M.assemble(runtime, game_parts, game_size, game_crc, icons, d, yield)
    local z, err = M.read_zip(runtime)
    if not z then return nil, err end
    local cert, pub = M.certificate(d)
    if not cert then return nil, "key" end
    local w = writer()
    local seen, digests = {}, {}
    for _, e in ipairs(z.list) do
        local n = e.name
        if not seen[n] and not drop_meta(n) then
            seen[n] = true
            if n == "assets/game.love" then return nil, "runtime_has_game" end
            local icon = icons and icons[n]
            if icon then
                digests[#digests + 1] = {n, sha256(icon)}
                w_add(w, n, 0, M.crc32(icon), #icon, #icon, icon, 4)
            else
                local raw = z.raw(e)
                if not raw then return nil, "bad_runtime" end
                local plain = raw
                if e.method ~= 0 then
                    plain = e.method == 8 and inflate(raw)
                    if not plain or #plain ~= e.size then return nil, "bad_runtime" end
                end
                digests[#digests + 1] = {n, sha256(plain)}
                local align = e.method == 0 and (n:sub(-3) == ".so" and 4096 or 4) or nil
                w_add(w, n, e.method, e.crc, e.csize, e.size, raw, align)
            end
        end
    end
    if not seen["AndroidManifest.xml"] or not seen["assets/overhaul_runtime.json"] then return nil, "bad_runtime" end
    local game = one_block(game_parts, game_size)
    if not game then return nil, "read" end
    if yield then yield() end
    digests[#digests + 1] = {"assets/game.love", sha256(game)}
    w_add(w, "assets/game.love", 0, game_crc, game_size, game_size, game, 4)
    local manifest, signed, pkcs = M.v1_files(digests, d, cert, pub)
    w_file(w, "META-INF/MANIFEST.MF", manifest)
    w_file(w, "META-INF/OVERHAUL.SF", signed)
    w_file(w, "META-INF/OVERHAUL.EC", pkcs)
    local cd, eocd = w_central(w)
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

function M.write(path, parts)
    local f = io.open(path .. ".part", "wb")
    if not f then return nil, "write" end
    for _, p in ipairs(parts) do
        local i, n = 1, plen(p)
        local step = type(p) == "string" and n or M.CHUNK
        while i <= n do
            local take = math.min(step, n - i + 1)
            if not f:write(piece(p, i, take)) then
                f:close()
                os.remove(path .. ".part")
                return nil, "write"
            end
            i = i + take
        end
    end
    f:close()
    os.remove(path)
    if not os.rename(path .. ".part", path) then return nil, "write" end
    return path
end

local function save(path, apk)
    local res, err = M.write(path, apk)
    for _, p in ipairs(apk) do
        if type(p) ~= "string" then p:release() end
    end
    return res, err
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

M.APP_FILES = {"conf.lua", "main.lua", "overhaul_install.lua", "updating.lua", "https.lua", "json.lua"}
M.APP_DIRS = {"launcher", "patcher", "patch", "patch_pc"}
M.APP_SKIP = "launcher/android/"
M.APP_PATCH_DIRS = {patch = true, patch_pc = true}
M.APP_SHARED = {["https.lua"] = true, ["json.lua"] = true}
M.APP_RESERVED = {"vanilla/", "carry/", "direct_play", "overhaul_safe_token"}

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
    local g = o.game
    local taken, same, by_rel = {}, {}, {}
    if g then
        taken[g.marker_name], taken[g.shared_name] = true, true
        for _, e in ipairs(g.man.files) do
            local name = g.rename[e.path] or e.path
            if taken[name] then return nil, "clash " .. name end
            for _, r in ipairs(M.APP_RESERVED) do
                if name:sub(1, #r) == r then return nil, "clash " .. name end
            end
            taken[name] = true
            local v = (e.kind == "keep" or e.kind == "copy") and g.man.vanilla[e.src]
            if v and v.path == e.path and name == e.path then same[e.path] = true end
        end
        for _, e in ipairs(o.vanilla.list) do by_rel[e.rel] = e end
    end
    local function own_vanilla(e)
        return not same[e.rel] or e.rel == "version.jkr"
    end
    local files = {}
    for _, f in ipairs(o.files or {}) do
        if taken[f.name] and not M.APP_SHARED[f.name] then return nil, "clash " .. f.name end
        if not taken[f.name] then files[#files + 1] = f end
    end
    for _, n in ipairs(o.files and {} or M.APP_FILES) do
        if taken[n] and not M.APP_SHARED[n] then return nil, "clash " .. n end
        if from_source(n) and not taken[n] then files[#files + 1] = {path = n, name = n} end
    end
    for _, dir in ipairs(o.files and {} or M.APP_DIRS) do
        if not (g and M.APP_PATCH_DIRS[dir]) then
            for _, f in ipairs(walk(dir, dir .. "/", {})) do
                if from_source(f.path) and f.name:sub(1, #M.APP_SKIP) ~= M.APP_SKIP then
                    if taken[f.name] then return nil, "clash " .. f.name end
                    files[#files + 1] = f
                end
            end
        end
    end
    local function official(name, e)
        if o.vanilla.data then
            local data = o.vanilla.data(e)
            if not data then return false end
            w_file(w, name, data, M.STORE_EXT[ext_of(name)])
            return true
        end
        local raw = o.vanilla.raw(e)
        if not raw then return false end
        w_add(w, name, e.method, e.crc, e.csize, e.size, raw)
        return true
    end
    local total = #files + (g and #g.man.files or 0)
    for _, e in ipairs(o.vanilla.list) do
        if own_vanilla(e) then total = total + 1 end
    end
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
    if o.safe and o.safe ~= "" then
        w_file(w, "overhaul_safe_token", tostring(o.safe) .. "\n")
    end
    local names = {}
    for n in pairs(o.carry or {}) do names[#names + 1] = n end
    table.sort(names)
    for _, n in ipairs(names) do
        w_file(w, "carry/" .. n, o.carry[n])
    end
    if g then
        local shared = {}
        local function emit(path, data)
            local name = g.rename[path] or path
            local e = same[path] and by_rel[path]
            if not (e and o.vanilla.raw and official(name, e)) then
                w_file(w, name, data, M.STORE_EXT[ext_of(name)])
            end
            if same[path] then shared[#shared + 1] = path end
            tick()
        end
        g.ctx.yield = nil
        local built, berr = g.build(g.man, g.z, g.ctx, emit)
        if not built then
            return nil, "patch " .. tostring(berr.code) .. " " .. tostring(berr.file or berr.detail or "")
        end
        w_file(w, g.marker_name, g.marker)
        w_file(w, g.shared_name, table.concat(shared, "\n") .. "\n")
    end
    for _, e in ipairs(o.vanilla.list) do
        if own_vanilla(e) then
            if not official("vanilla/" .. e.rel, e) then return nil, "read" end
            tick()
        end
    end
    return finish_love(w, o.yield)
end

function M.game_love(C, path, yield, check_yield)
    local game, gerr = C.apk_game(path, check_yield)
    if not game then return nil, gerr end
    local files = walk(M.BOOTSTRAP, "", {})
    for _, p in ipairs(M.PATCHER) do
        files[#files + 1] = {path = p, name = "patcher/" .. p:match("([^/]+)$")}
    end
    local vanilla = {list = {}}
    if C.is_loose(path) then
        local list = loose_files(path)
        if not list or #list == 0 then return nil, "read" end
        for _, f in ipairs(list) do
            if f.name:sub(1, 7) ~= "dexopt/" then
                vanilla.list[#vanilla.list + 1] = {rel = f.name, full = f.full}
            end
        end
        vanilla.data = function(e) return read_abs(e.full) end
    else
        local data = read_abs(path)
        local z = data and M.read_zip(data)
        if not z then return nil, "read" end
        for _, e in ipairs(z.list) do
            if e.name:sub(1, 7) ~= "dexopt/" and (e.method == 0 or e.method == 8) then
                e.rel = e.name
                vanilla.list[#vanilla.list + 1] = e
            end
        end
        vanilla.raw = z.raw
    end
    local parts, size, crc = M.phone_love({files = files, vanilla = vanilla, game = game, yield = yield})
    if not parts then return nil, size end
    return parts, size, crc, game.man
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
    return save(o.out, apk)
end

function M.run(o)
    local C = require("core")
    local yield = function(i, n)
        if o.progress then o.progress(i or 1, n or 1) end
    end
    local runtime = love.filesystem.read(M.RUNTIME)
    if not runtime then return nil, "no runtime" end
    local parts, size, crc, m = M.game_love(C, o.game_path, yield, function() coroutine.yield() end)
    if not parts then
        return nil, type(size) == "table" and size or tostring(size)
    end
    local icons = M.icons(runtime, o.icon)
    local d = M.player_key()
    local apk, err = M.assemble(runtime, parts, size, crc, icons, d, yield)
    if not apk then return nil, err end
    local file = (o.out_dir or love.filesystem.getSaveDirectory()) .. "/BalatroOverhaul-" .. (tostring(m.overhaul_name or ""):match("^[%d.]+") or tostring(m.overhaul_version)) .. ".apk"
    return save(file, apk)
end

return M
