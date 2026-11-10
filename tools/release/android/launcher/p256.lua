local M = {}

local L = 16
local B = 65536
local floor = math.floor

local function from_hex(h)
    local a = {}
    h = h:gsub("%s", "")
    h = string.rep("0", 64 - #h) .. h
    for i = 1, L do
        local s = 64 - i * 4 + 1
        a[i] = tonumber(h:sub(s, s + 3), 16)
    end
    return a
end

local function from_bytes(s)
    local a = {}
    s = string.rep("\0", 32 - #s) .. s
    for i = 1, L do
        local p = 33 - i * 2
        a[i] = s:byte(p) * 256 + s:byte(p + 1)
    end
    return a
end

local function to_bytes(a)
    local t = {}
    for i = L, 1, -1 do
        t[#t + 1] = string.char(floor(a[i] / 256), a[i] % 256)
    end
    return table.concat(t)
end

local function copy(a)
    local r = {}
    for i = 1, L do r[i] = a[i] end
    return r
end

local function is_zero(a)
    for i = 1, L do
        if a[i] ~= 0 then return false end
    end
    return true
end

local function cmp(a, b)
    for i = L, 1, -1 do
        if a[i] ~= b[i] then return a[i] > b[i] and 1 or -1 end
    end
    return 0
end

local function add(a, b)
    local r, c = {}, 0
    for i = 1, L do
        local s = a[i] + b[i] + c
        if s >= B then r[i] = s - B; c = 1 else r[i] = s; c = 0 end
    end
    return r, c
end

local function sub(a, b)
    local r, c = {}, 0
    for i = 1, L do
        local s = a[i] - b[i] - c
        if s < 0 then r[i] = s + B; c = 1 else r[i] = s; c = 0 end
    end
    return r, c
end

local function field(hex)
    local m = from_hex(hex)
    local x = 1
    for _ = 1, 4 do x = (x * (2 - m[1] * x % B)) % B end
    local F = {m = m, minv = (B - x) % B}
    local r2 = {1}
    for i = 2, L do r2[i] = 0 end
    for _ = 1, 512 do
        local s, c = add(r2, r2)
        if c == 1 or cmp(s, m) >= 0 then s = sub(s, m) end
        r2 = s
    end
    F.r2 = r2
    return F
end

local function mul(F, a, b)
    local m, minv = F.m, F.minv
    local t = {}
    for i = 1, L + 2 do t[i] = 0 end
    for i = 1, L do
        local ai, c = a[i], 0
        for j = 1, L do
            local s = t[j] + ai * b[j] + c
            c = floor(s / B)
            t[j] = s - c * B
        end
        local s = t[L + 1] + c
        c = floor(s / B)
        t[L + 1] = s - c * B
        t[L + 2] = c
        local q = (t[1] * minv) % B
        s = t[1] + q * m[1]
        c = floor(s / B)
        for j = 2, L do
            s = t[j] + q * m[j] + c
            c = floor(s / B)
            t[j - 1] = s - c * B
        end
        s = t[L + 1] + c
        c = floor(s / B)
        t[L] = s - c * B
        t[L + 1] = t[L + 2] + c
    end
    local r = {}
    for i = 1, L do r[i] = t[i] end
    if t[L + 1] ~= 0 or cmp(r, m) >= 0 then r = sub(r, m) end
    return r
end

local ONE = {1}
for i = 2, L do ONE[i] = 0 end

local function addm(F, a, b)
    local r, c = add(a, b)
    if c == 1 or cmp(r, F.m) >= 0 then r = sub(r, F.m) end
    return r
end

local function subm(F, a, b)
    local r, c = sub(a, b)
    if c == 1 then r = add(r, F.m) end
    return r
end

local function to_m(F, a) return mul(F, a, F.r2) end
local function from_m(F, a) return mul(F, a, ONE) end

local function pow(F, a, e)
    local r = to_m(F, ONE)
    for i = L, 1, -1 do
        local w = e[i]
        for bit = 15, 0, -1 do
            r = mul(F, r, r)
            if floor(w / 2 ^ bit) % 2 == 1 then r = mul(F, r, a) end
        end
    end
    return r
end

local function inv(F, a)
    local two = {2}
    for i = 2, L do two[i] = 0 end
    return pow(F, a, sub(F.m, two))
end

local P = field("FFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF")
local N = field("FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551")
local GX = to_m(P, from_hex("6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296"))
local GY = to_m(P, from_hex("4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5"))
local CB = to_m(P, from_hex("5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B"))

local function dbl(p)
    if p.inf then return p end
    local X, Y, Z = p.x, p.y, p.z
    local delta = mul(P, Z, Z)
    local gamma = mul(P, Y, Y)
    local beta = mul(P, X, gamma)
    local t = mul(P, subm(P, X, delta), addm(P, X, delta))
    local alpha = addm(P, addm(P, t, t), t)
    local b4 = addm(P, beta, beta)
    b4 = addm(P, b4, b4)
    local b8 = addm(P, b4, b4)
    local X3 = subm(P, mul(P, alpha, alpha), b8)
    local yz = addm(P, Y, Z)
    local Z3 = subm(P, subm(P, mul(P, yz, yz), gamma), delta)
    local g2 = mul(P, gamma, gamma)
    local g8 = addm(P, g2, g2)
    g8 = addm(P, g8, g8)
    g8 = addm(P, g8, g8)
    local Y3 = subm(P, mul(P, alpha, subm(P, b4, X3)), g8)
    return {x = X3, y = Y3, z = Z3}
end

local function padd(p, q)
    if p.inf then return q end
    if q.inf then return p end
    local z1z1 = mul(P, p.z, p.z)
    local z2z2 = mul(P, q.z, q.z)
    local u1 = mul(P, p.x, z2z2)
    local u2 = mul(P, q.x, z1z1)
    local s1 = mul(P, mul(P, p.y, q.z), z2z2)
    local s2 = mul(P, mul(P, q.y, p.z), z1z1)
    local h = subm(P, u2, u1)
    local r = subm(P, s2, s1)
    if is_zero(h) then
        if is_zero(r) then return dbl(p) end
        return {inf = true}
    end
    r = addm(P, r, r)
    local h2 = addm(P, h, h)
    local i = mul(P, h2, h2)
    local j = mul(P, h, i)
    local v = mul(P, u1, i)
    local x3 = subm(P, subm(P, subm(P, mul(P, r, r), j), v), v)
    local sj = mul(P, s1, j)
    local y3 = subm(P, subm(P, mul(P, r, subm(P, v, x3)), sj), sj)
    local zz = addm(P, p.z, q.z)
    local z3 = mul(P, subm(P, subm(P, mul(P, zz, zz), z1z1), z2z2), h)
    return {x = x3, y = y3, z = z3}
end

local function smul(k, pt)
    local r = {inf = true}
    for i = L, 1, -1 do
        local w = k[i]
        for bit = 15, 0, -1 do
            r = dbl(r)
            if floor(w / 2 ^ bit) % 2 == 1 then r = padd(r, pt) end
        end
    end
    return r
end

local function affine(p)
    if p.inf then return nil end
    local zi = inv(P, p.z)
    local zi2 = mul(P, zi, zi)
    return from_m(P, mul(P, p.x, zi2)), from_m(P, mul(P, p.y, mul(P, zi2, zi)))
end

local G = {x = GX, y = GY, z = to_m(P, ONE)}

local function on_curve(x, y)
    local xm, ym = to_m(P, x), to_m(P, y)
    local x3 = mul(P, mul(P, xm, xm), xm)
    local three_x = addm(P, addm(P, xm, xm), xm)
    local rhs = addm(P, subm(P, x3, three_x), CB)
    return cmp(mul(P, ym, ym), rhs) == 0
end

local function mod_n(a)
    if cmp(a, N.m) >= 0 then return sub(a, N.m) end
    return a
end

function M.valid_private(d32)
    if type(d32) ~= "string" or #d32 ~= 32 then return false end
    local d = from_bytes(d32)
    return not is_zero(d) and cmp(d, N.m) < 0
end

function M.private_from_seed(seed32)
    local d = mod_n(from_bytes(seed32))
    if is_zero(d) then return nil end
    return to_bytes(d)
end

function M.public(d32)
    local x, y = affine(smul(from_bytes(d32), G))
    if not x or not on_curve(x, y) then return nil end
    return "\4" .. to_bytes(x) .. to_bytes(y)
end

local function der_int(b)
    b = b:gsub("^%z+", "")
    if b == "" then b = "\0" end
    if b:byte(1) >= 128 then b = "\0" .. b end
    return "\2" .. string.char(#b) .. b
end

function M.sign(d32, hash32, nonce)
    local d = from_bytes(d32)
    local z = mod_n(from_bytes(hash32))
    local dm, zm = to_m(N, d), to_m(N, z)
    for counter = 0, 255 do
        local k = mod_n(from_bytes(nonce(d32, hash32, counter)))
        if not is_zero(k) then
            local x = affine(smul(k, G))
            if x then
                local r = mod_n(x)
                if not is_zero(r) then
                    local km = to_m(N, k)
                    local s = from_m(N, mul(N, inv(N, km), addm(N, zm, mul(N, to_m(N, r), dm))))
                    if not is_zero(s) then
                        local body = der_int(to_bytes(r)) .. der_int(to_bytes(s))
                        return "\48" .. string.char(#body) .. body
                    end
                end
            end
        end
    end
    return nil
end

M._from_hex, M._to_bytes = from_hex, to_bytes

return M
