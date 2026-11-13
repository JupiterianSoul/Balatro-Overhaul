local zipread = require("patcher.zipread")

local A = {}

local function count(s, pat)
    local n, pos = 0, 1
    while true do
        local a, b = s:find(pat, pos, true)
        if not a then
            return n
        end
        n, pos = n + 1, b + 1
    end
end

local function split(body, sep, out)
    local pos = 1
    while true do
        local a, b = body:find(sep, pos, true)
        if not a then
            out[#out + 1] = body:sub(pos)
            return out
        end
        out[#out + 1] = body:sub(pos, a - 1)
        pos = b + 1
    end
end

function A.split_lines(data)
    local n_lf = count(data, "\n")
    local crlf = n_lf > 0 and count(data, "\r\n") == n_lf
    local sep = crlf and "\r\n" or "\n"
    local final = #data >= #sep and data:sub(-#sep) == sep
    local body = final and data:sub(1, #data - #sep) or data
    local lines = {}
    if body ~= "" or final then
        split(body, sep, lines)
    end
    return lines, crlf, final
end

local function strip(s)
    local a = s:find("[^ \t\n\r\v\f]")
    if not a then
        return ""
    end
    local b = #s
    while true do
        local c = s:byte(b)
        if c ~= 32 and (c < 9 or c > 13) then
            break
        end
        b = b - 1
    end
    return s:sub(a, b)
end

local function unpct(s)
    if s == "-" then
        return ""
    end
    return (s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

local function apply_edits(src, edits)
    local out, pos = {}, 1
    for tok in edits:gmatch("[^,]+") do
        local k, v = tok:sub(1, 1), tok:sub(2)
        local n = tonumber(v)
        if (k == "=" or k == "-") and n and n >= 0 and pos + n - 1 <= #src then
            if k == "=" then
                out[#out + 1] = src:sub(pos, pos + n - 1)
            end
            pos = pos + n
        elseif k == "+" and v ~= "" then
            out[#out + 1] = unpct(v)
        else
            return nil
        end
    end
    if pos ~= #src + 1 then
        return nil
    end
    return table.concat(out)
end

local bit = require("bit")

function A.line_hash(line)
    local h = -2128831035
    for i = 1, #line do
        h = bit.bxor(h, line:byte(i))
        h = bit.tobit(bit.band(h, 0xffff) * 403 + bit.band(bit.rshift(h, 16), 0xffff) * 403 * 65536 + bit.lshift(h, 24))
    end
    return bit.band(h, 0xffffff)
end

local function lis(seq)
    local tails, prev, idx = {}, {}, {}
    for i, v in ipairs(seq) do
        local lo, hi = 1, #tails + 1
        while lo < hi do
            local mid = math.floor((lo + hi) / 2)
            if seq[tails[mid]] < v then lo = mid + 1 else hi = mid end
        end
        tails[lo] = i
        prev[i] = lo > 1 and tails[lo - 1] or nil
        idx[lo] = i
    end
    local out, k = {}, tails[#tails]
    while k do
        table.insert(out, 1, k)
        k = prev[k]
    end
    return out
end

local function fill_gap(old, new, x, xe, y, ye, map)
    local n, m = xe - x + 1, ye - y + 1
    if n <= 0 or m <= 0 then
        return
    end
    if n == m then
        for k = 0, n - 1 do map[x + k] = y + k end
        return
    end
    if n * m > 1000000 then
        return
    end
    local w = m + 2
    local L = {}
    for i = n + 1, 1, -1 do
        for j = m + 1, 1, -1 do
            local v
            if i > n or j > m then
                v = 0
            elseif old[x + i - 1] == new[y + j - 1] then
                v = L[(i + 1) * w + j + 1] + 1
            else
                local a, b = L[(i + 1) * w + j], L[i * w + j + 1]
                v = a > b and a or b
            end
            L[i * w + j] = v
        end
    end
    local pi, pj = 0, 0
    local i, j = 1, 1
    local function even(i1, j1)
        if i1 - pi == j1 - pj then
            for k = 1, i1 - pi - 1 do map[x + pi + k - 1] = y + pj + k - 1 end
        end
    end
    while i <= n and j <= m do
        if old[x + i - 1] == new[y + j - 1] then
            even(i, j)
            map[x + i - 1] = y + j - 1
            pi, pj = i, j
            i, j = i + 1, j + 1
        elseif L[(i + 1) * w + j] >= L[i * w + j + 1] then
            i = i + 1
        else
            j = j + 1
        end
    end
    even(n + 1, m + 1)
end

function A.align(old, new)
    local n, m = #old, #new
    local cnt_o, cnt_n, pos_n = {}, {}, {}
    for i = 1, n do cnt_o[old[i]] = (cnt_o[old[i]] or 0) + 1 end
    for j = 1, m do
        cnt_n[new[j]] = (cnt_n[new[j]] or 0) + 1
        pos_n[new[j]] = j
    end
    local ao, an = {}, {}
    for i = 1, n do
        local h = old[i]
        if cnt_o[h] == 1 and cnt_n[h] == 1 then
            ao[#ao + 1] = i
            an[#an + 1] = pos_n[h]
        end
    end
    local keep = lis(an)
    local map = {}
    local anchors = {{0, 0}}
    for _, k in ipairs(keep) do anchors[#anchors + 1] = {ao[k], an[k]} end
    anchors[#anchors + 1] = {n + 1, m + 1}
    for a = 1, #anchors - 1 do
        local i0, j0 = anchors[a][1], anchors[a][2]
        local i1, j1 = anchors[a + 1][1], anchors[a + 1][2]
        if i0 >= 1 then map[i0] = j0 end
        local x, y = i0 + 1, j0 + 1
        while x < i1 and y < j1 and old[x] == new[y] do
            map[x] = y
            x, y = x + 1, y + 1
        end
        local xe, ye = i1 - 1, j1 - 1
        while xe >= x and ye >= y and old[xe] == new[ye] do
            map[xe] = ye
            xe, ye = xe - 1, ye - 1
        end
        fill_gap(old, new, x, xe, y, ye, map)
    end
    return map
end

function A.drift_lines(data, hashes)
    local new = A.split_lines(data)
    local old = {}
    for h in hashes:gmatch("%x%x%x%x%x%x") do old[#old + 1] = tonumber(h, 16) end
    local known = {}
    for i = 1, #old do known[old[i]] = true end
    local nh = {}
    for j = 1, #new do
        nh[j] = A.line_hash(new[j])
        if not known[nh[j]] and new[j]:sub(-1) == "\r" then
            new[j] = new[j]:sub(1, -2)
            nh[j] = A.line_hash(new[j])
        end
    end
    local map = A.align(old, nh)
    return setmetatable({drift = true, map = map, new = new}, {__index = function(_, i)
        local j = type(i) == "number" and map[i]
        return j and new[j] or nil
    end})
end

function A.apply_bop(patch, vanilla_lines, lenient)
    local plines = split(patch, "\n", {})
    local i = 1
    local function nextline()
        local l = plines[i]
        i = i + 1
        return l
    end
    local fmt = (nextline() or ""):match("^BOP (%d)$")
    if fmt ~= "1" and fmt ~= "2" then
        return nil, "bad_patch"
    end
    local eol = (nextline() or ""):match("^eol (%a+)$")
    local final = (nextline() or ""):match("^final (%d)$")
    local base_idx = tonumber((nextline() or ""):match("^base (%d+)$") or "")
    if not eol or not final or not base_idx then
        return nil, "bad_patch"
    end
    local base = base_idx > 0 and vanilla_lines(base_idx) or {}
    if not base then
        return nil, "missing_base"
    end
    local out, cursor = {}, 1
    while true do
        local op = nextline()
        if op == nil then
            return nil, "bad_patch"
        end
        if op == "end" then
            break
        end
        local kind, a, b, c, d = op:match("^(%a) (%S+) ?(%S*) ?(%S*) ?(%S*)$")
        local n = tonumber(a)
        local es, el, elead, etrail, edits
        if fmt == "2" and op:sub(1, 2) == "e " then
            es, el, elead, etrail, edits = op:match("^e (%d+) (%d+) (%S+) (%S+) (%S+)$")
        end
        if es then
            local lines = vanilla_lines(tonumber(es))
            local src = lines and lines[tonumber(el)]
            if not src and not lenient then
                return nil, "missing_base"
            end
            local line = src and apply_edits(strip(src), edits)
            if src and not line then
                return nil, "bad_patch"
            end
            out[#out + 1] = line and (unpct(elead) .. line .. unpct(etrail)) or ""
        elseif kind == "c" and n and base.drift then
            local lo, hi
            for k = cursor, cursor + n - 1 do
                local j = base.map[k]
                if j then
                    lo = lo or j
                    hi = j
                end
            end
            if lo then
                for j = lo, hi do
                    out[#out + 1] = base.new[j]
                end
            end
            cursor = cursor + n
        elseif kind == "c" and n then
            for _ = 1, n do
                if base[cursor] == nil then
                    return nil, "bad_patch"
                end
                out[#out + 1] = base[cursor]
                cursor = cursor + 1
            end
        elseif kind == "s" and n then
            cursor = cursor + n
        elseif kind == "l" and n then
            for _ = 1, n do
                local l = nextline()
                if l == nil then
                    return nil, "bad_patch"
                end
                out[#out + 1] = l
            end
        elseif kind == "r" and n and tonumber(b) and c ~= "" and d ~= "" then
            local lines = vanilla_lines(n)
            local src = lines and lines[tonumber(b)]
            if not src and not lenient then
                return nil, "missing_base"
            end
            out[#out + 1] = src and (unpct(c) .. strip(src) .. unpct(d)) or ""
        else
            return nil, "bad_patch"
        end
    end
    local sep = eol == "crlf" and "\r\n" or "\n"
    local data = table.concat(out, sep)
    if final == "1" then
        data = data .. sep
    end
    return data
end

function A.load_manifest(src)
    if type(src) ~= "string" then
        return nil, "no_manifest"
    end
    local chunk = (loadstring or load)(src, "=manifest")
    if not chunk then
        return nil, "bad_manifest"
    end
    if setfenv then
        setfenv(chunk, {})
    end
    local ok, m = pcall(chunk)
    if not ok or type(m) ~= "table" or (m.format ~= 1 and m.format ~= 2) or type(m.files) ~= "table" then
        return nil, "bad_manifest"
    end
    return m
end

function A.open_game(data, ctx)
    local z, err = zipread.open(data, ctx.inflate)
    if not z then
        return nil, {code = "not_game", detail = err}
    end
    return z
end

function A.game_version(z)
    local v = z:read("version.jkr")
    if not v then
        return nil
    end
    return strip((v:match("^[^\n]*")) or "")
end

function A.check(m, z, ctx)
    local version = A.game_version(z)
    if not version or not z.entries["main.lua"] then
        return nil, {code = "not_game"}
    end
    local bad, drift = {}, {}
    for i, v in ipairs(m.vanilla) do
        local data = z:read(v.path)
        if not data then
            bad[#bad + 1] = v.path
        elseif #data ~= v.size or ctx.sha256(data) ~= v.sha256 then
            drift[i] = true
            drift[#drift + 1] = v.path
        end
        if ctx.yield then
            ctx.yield()
        end
    end
    if #bad > 0 then
        return nil, {code = "modded", files = bad, found = version}
    end
    return {version = version, files = #m.files, drift = drift, exact = #drift == 0}
end

function A.is_drift(m, z, ctx, idx, cache)
    if cache[idx] == nil then
        local v = m.vanilla[idx]
        local data = v and z:read(v.path)
        cache[idx] = data ~= nil and (#data ~= v.size or ctx.sha256(data) ~= v.sha256)
    end
    return cache[idx]
end

function A.build(m, z, ctx, emit)
    local text_cache, drift_cache = {}, {}
    local touched
    local function vanilla_lines(idx)
        local v = m.vanilla[idx]
        if not v then
            return nil
        end
        if not text_cache[idx] then
            local data = z:read(v.path)
            if not data then
                return nil
            end
            local hashes = v.lines and A.is_drift(m, z, ctx, idx, drift_cache) and ctx.read_patch(v.lines)
            text_cache[idx] = hashes and A.drift_lines(data, hashes) or A.split_lines(data)
        end
        if text_cache[idx].drift then
            touched = true
        end
        return text_cache[idx]
    end
    local total = #m.files
    for i, e in ipairs(m.files) do
        local data, err
        touched = false
        if e.kind == "keep" or e.kind == "copy" then
            local v = m.vanilla[e.src]
            touched = A.is_drift(m, z, ctx, e.src, drift_cache)
            data = v and z:read(v.path)
            err = "missing_vanilla"
        elseif e.kind == "own" then
            data = ctx.read_patch(e.file)
            err = "missing_patch"
        elseif e.kind == "patch" then
            local p = ctx.read_patch(e.patch)
            if p then
                data, err = A.apply_bop(p, vanilla_lines)
                if not data and err == "missing_base" and touched and e.path:find("localization/", 1, true) then
                    data = A.apply_bop(p, vanilla_lines, true)
                    if data and e.path:sub(-4) == ".lua" and not (loadstring or load)(data, "=" .. e.path) then
                        data = nil
                    end
                end
            else
                err = "missing_patch"
            end
        elseif e.kind == "image" then
            local v = m.vanilla[e.src]
            local base = v and z:read(v.path)
            local own = e.image.own and ctx.read_patch(e.image.own)
            local mask = e.image.mask and ctx.read_patch(e.image.mask)
            if base and (own or not e.image.own) and (mask or not e.image.mask) then
                local pixels
                data, pixels = ctx.image(base, own, mask, e.image)
                if pixels ~= e.image.pixels and not A.is_drift(m, z, ctx, e.src, drift_cache) then
                    data, err = nil, "image_mismatch"
                end
            else
                err = "missing_patch"
            end
        else
            err = "bad_manifest"
        end
        if not data then
            return nil, {code = err or "failed", file = e.path}
        end
        if e.kind ~= "image" and not touched and (#data ~= e.size or ctx.sha256(data) ~= e.sha256) then
            return nil, {code = "mismatch", file = e.path}
        end
        local ok, werr = emit(e.path, data, i, total)
        if ok == false then
            return nil, {code = "write", file = e.path, detail = werr}
        end
        if ctx.yield then
            ctx.yield(i, total, e.path)
        end
    end
    return {files = total}
end

return A
