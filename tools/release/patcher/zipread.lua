local M = {}

local function u16(s, i)
    local a, b = s:byte(i, i + 1)
    return a + b * 256
end

local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

function M.open(data, inflate)
    if type(data) ~= "string" or #data < 22 then
        return nil, "not_zip"
    end
    local eocd
    local stop = math.max(1, #data - 65557)
    for i = #data - 21, stop, -1 do
        if data:byte(i) == 0x50 and data:sub(i, i + 3) == "PK\5\6" then
            eocd = i
            break
        end
    end
    if not eocd then
        return nil, "not_zip"
    end
    local count = u16(data, eocd + 10)
    local cd_size = u32(data, eocd + 12)
    local cd_offset = u32(data, eocd + 16)
    local concat = (eocd - 1) - cd_size - cd_offset
    if concat < 0 then
        return nil, "bad_zip"
    end
    local z = {data = data, concat = concat, entries = {}, list = {}, inflate = inflate}
    local p = cd_offset + concat + 1
    for _ = 1, count do
        if data:sub(p, p + 3) ~= "PK\1\2" then
            return nil, "bad_zip"
        end
        local e = {
            method = u16(data, p + 10),
            csize = u32(data, p + 20),
            size = u32(data, p + 24),
            local_offset = u32(data, p + 42),
        }
        local nlen, xlen, clen = u16(data, p + 28), u16(data, p + 30), u16(data, p + 32)
        e.name = data:sub(p + 46, p + 45 + nlen)
        p = p + 46 + nlen + xlen + clen
        if e.name:sub(-1) ~= "/" then
            z.entries[e.name] = e
            z.list[#z.list + 1] = e.name
        end
    end
    return setmetatable(z, {__index = M})
end

function M:read(name)
    local e = self.entries[name]
    if not e then
        return nil, "missing"
    end
    local p = e.local_offset + self.concat + 1
    local data = self.data
    if data:sub(p, p + 3) ~= "PK\3\4" then
        return nil, "bad_zip"
    end
    local start = p + 30 + u16(data, p + 26) + u16(data, p + 28)
    local raw = data:sub(start, start + e.csize - 1)
    if e.method == 0 then
        return raw
    elseif e.method == 8 then
        local ok, out = pcall(self.inflate, raw, e.size)
        if ok and type(out) == "string" and #out == e.size then
            return out
        end
        return nil, "bad_zip"
    end
    return nil, "bad_zip"
end

return M
