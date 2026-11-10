local BT = {}

local W, H = 71, 95
local GOLD = {36/360, 62/360}

BT.CELLS = {
    ["0,0"] = {rot = 48, gold = true}, ["1,0"] = {rot = 48, gold = true}, ["2,0"] = {rot = 48, gold = true}, ["3,0"] = {rot = 48, gold = true},
    ["0,1"] = {rot = 62, gold = true, sat = 1.1}, ["1,1"] = {rot = 62, gold = true, sat = 1.1}, ["2,1"] = {rot = 62, gold = true, sat = 1.1}, ["3,1"] = {rot = 62, gold = true, sat = 1.1},
    ["0,2"] = {rot = -40, gold = true}, ["1,2"] = {rot = 40, gold = true}, ["2,2"] = {rot = -70, gold = true, sat = 1.2}, ["3,2"] = {rot = -70, gold = true, sat = 1.2},
    ["0,3"] = {rot = 110, gold = true, sat = 1.15}, ["1,3"] = {rot = -40, gold = true, sat = 1.1}, ["2,3"] = {rot = -60, gold = true, sat = 1.15}, ["3,3"] = {rot = -60, gold = true, sat = 1.15},
    ["0,4"] = {rot = -42, gold = true, sat = 1.1}, ["1,4"] = {rot = -42, gold = true, sat = 1.1}, ["2,4"] = {rot = 55, gold = true, sat = 1.15}, ["3,4"] = {rot = -75, gold = true, sat = 1.2},
    ["0,6"] = {rot = 32}, ["1,6"] = {rot = 32}, ["2,6"] = {rot = 32}, ["3,6"] = {rot = 32},
    ["0,7"] = {rot = -45}, ["1,7"] = {rot = -45}, ["2,7"] = {rot = 75, sat = 1.1}, ["3,7"] = {rot = 75, sat = 1.1},
    ["0,8"] = {rot = 28}, ["1,8"] = {rot = 28}, ["2,8"] = {rot = -32}, ["3,8"] = {rot = 40, sat = 1.1},
}

BT.PACKS = {
    {x = 0, y = 0, hue = 305, cards = {{"Vouchers.png", 7, 3}}},
    {x = 1, y = 0, hue = 275, cards = {{"Vouchers.png", 7, 2}, {"Vouchers.png", 7, 3}}},
    {x = 2, y = 0, hue = 8, cards = {{"Jokers.png", 0, 0}}},
    {x = 3, y = 0, hue = 340, cards = {{"Jokers.png", 2, 0}, {"Jokers.png", 0, 0}}},
    {x = 4, y = 0, hue = 212, cards = {{"Enhancers.png", 0, 0}}},
    {x = 0, y = 1, hue = 186, cards = {{"Tarots.png", 4, 4}}},
    {x = 1, y = 1, hue = 140, cards = {{"Jokers.png", 8, 8}}},
    {x = 2, y = 1, hue = 28, dark = 0.8, cards = {{"Enhancers.png", 0, 0}, {"Jokers.png", 0, 0}, {"Tarots.png", 4, 4}}},
    {x = 3, y = 1, hue = 48, sat = 0.75, cards = {{"Jokers.png", 3, 8, soul = {3, 9}}, {"Jokers.png", 4, 8, soul = {4, 9}}, {"Jokers.png", 7, 8, soul = {7, 9}}}},
}
BT.FAN = {{{0, 0}}, {{-5, -4}, {5, 4}}, {{-7, -6}, {0, -1}, {7, 4}}}
BT.BLANK = {0, 5}

local orig_image = love.graphics.newImage
local cache = {}

local function release_on()
    return rawget(_G, "RELEASE_BUILD") == true or (os.getenv and os.getenv("BOM_RELEASE_ART") == "1")
end

local function hls(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local l = (mx + mn)/2
    if mx == mn then return 0, l, 0 end
    local d = mx - mn
    local s = l > 0.5 and d/(2 - mx - mn) or d/(mx + mn)
    local h
    if mx == r then h = (g - b)/d + (g < b and 6 or 0)
    elseif mx == g then h = (b - r)/d + 2
    else h = (r - g)/d + 4 end
    return h/6, l, s
end

local function hue2(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1/6 then return p + (q - p)*6*t end
    if t < 1/2 then return q end
    if t < 2/3 then return p + (q - p)*(2/3 - t)*6 end
    return p
end

local function rgb(h, l, s)
    if s == 0 then return l, l, l end
    local q = l < 0.5 and l*(1 + s) or l + s - l*s
    local p = 2*l - q
    return hue2(p, q, h + 1/3), hue2(p, q, h), hue2(p, q, h - 1/3)
end

BT.hls, BT.rgb = hls, rgb

function BT.recolour(r, g, b, rule)
    local h, l, s = hls(r, g, b)
    if s < 0.08 or l > 0.88 or l < 0.06 then return r, g, b end
    if (rule.pull or rule.gold) and h >= GOLD[1] and h <= GOLD[2] and s >= 0.3 then return r, g, b end
    if rule.pull then
        local d = (rule.pull/360 - h + 0.5) % 1 - 0.5
        h = (h + d*(rule.k or 0.65)) % 1
    else
        h = (h + (rule.rot or 0)/360) % 1
    end
    s = math.min(1, s*(rule.sat or 1.05))
    return rgb(h, l, s)
end

local function build_boosters(path, s)
    local data = love.image.newImageData(path)
    local cw, ch = W*s, H*s
    local cols, rows = math.floor(data:getWidth()/cw), math.floor(data:getHeight()/ch)
    for cy = 0, rows - 1 do
        for cx = 0, cols - 1 do
            local rule = BT.CELLS[cx .. "," .. cy]
            if rule then
                data:mapPixel(function(_, _, r, g, b, a)
                    if a <= 0 then return r, g, b, a end
                    local nr, ng, nb = BT.recolour(r, g, b, rule)
                    return nr, ng, nb, a
                end, cx*cw, cy*ch, cw, ch)
            end
        end
    end
    return data
end

local function stamp(dst, src, dx, dy, sx, sy, w, h)
    local dw, dh = dst:getDimensions()
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local r, g, b, a = src:getPixel(sx + x, sy + y)
            local tx, ty = dx + x, dy + y
            if a > 0 and tx >= 0 and ty >= 0 and tx < dw and ty < dh then
                local br, bg, bb, ba = dst:getPixel(tx, ty)
                dst:setPixel(tx, ty, r*a + br*(1 - a), g*a + bg*(1 - a), b*a + bb*(1 - a), math.max(a, ba))
            end
        end
    end
end

local function shrink(src, sx, sy, w, h, f)
    local out = love.image.newImageData(math.floor(w/f), math.floor(h/f))
    local n = f*f
    out:mapPixel(function(x, y)
        local r, g, b, a = 0, 0, 0, 0
        for j = 0, f - 1 do
            for i = 0, f - 1 do
                local pr, pg, pb, pa = src:getPixel(sx + x*f + i, sy + y*f + j)
                r, g, b, a = r + pr*pa, g + pg*pa, b + pb*pa, a + pa
            end
        end
        if a <= 0 then return 0, 0, 0, 0 end
        return r/a, g/a, b/a, a/n
    end)
    return out
end

local function shadow(dst, src, dx, dy, k)
    local dw, dh = dst:getDimensions()
    local w, h = src:getDimensions()
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local a = select(4, src:getPixel(x, y))*k
            local tx, ty = dx + x, dy + y
            if a > 0 and tx >= 0 and ty >= 0 and tx < dw and ty < dh then
                local br, bg, bb, ba = dst:getPixel(tx, ty)
                if ba > 0 then dst:setPixel(tx, ty, br*(1 - a), bg*(1 - a), bb*(1 - a), ba) end
            end
        end
    end
end

local function build_packs(path, s)
    local base = "resources/textures/" .. s .. "x/"
    local boosters = love.image.newImageData(base .. "boosters.png")
    local atlases = {}
    local function atlas(name)
        atlases[name] = atlases[name] or love.image.newImageData("resources/textures/1x/" .. name)
        return atlases[name]
    end
    local cw, ch = W*s, H*s
    local f = 2/s
    local out = love.image.newImageData(cw*5, ch*2)
    local top, bottom = 14*s, 85*s
    for _, p in ipairs(BT.PACKS) do
        local ox, oy = p.x*cw, p.y*ch
        out:paste(boosters, ox, oy, BT.BLANK[1]*cw, BT.BLANK[2]*ch, cw, ch)
        out:mapPixel(function(_, y, r, g, b, a)
            if a <= 0 then return r, g, b, a end
            local _, l = hls(r, g, b)
            if l > 0.78 then return r, g, b, 1 end
            local t = math.min(1, math.max(0, (y - oy - top)/(bottom - top)))
            local nl = (0.56 - 0.2*t)*(l/0.62)*(p.dark or 1)
            local nr, ng, nb = rgb(p.hue/360, math.min(0.8, nl), p.sat or 0.72)
            return nr, ng, nb, 1
        end, ox, oy, cw, ch)
        local fan = BT.FAN[#p.cards]
        for i, c in ipairs(p.cards) do
            local src = atlas(c[1])
            local card = shrink(src, c[2]*W, c[3]*H, W, H, f)
            if c.soul then
                local soul = shrink(src, c.soul[1]*W, c.soul[2]*H, W, H, f)
                stamp(card, soul, 0, 0, 0, 0, soul:getDimensions())
                soul:release()
            end
            local w, h = card:getDimensions()
            local dx = ox + math.floor((cw - w)/2) + fan[i][1]*s
            local dy = oy + math.floor((top + bottom - h)/2) + fan[i][2]*s
            shadow(out, card, dx + s, dy + s, 0.55)
            stamp(out, card, dx, dy, 0, 0, w, h)
            card:release()
        end
    end
    boosters:release()
    for _, a in pairs(atlases) do a:release() end
    return out
end

local function target(path)
    if type(path) ~= "string" then return nil end
    local s, name = path:match("resources/textures/(%d)x/([^/]+)$")
    if not s then return nil end
    if name == "boosters.png" then return build_boosters, tonumber(s), name end
    if name == "TavernPacks.png" and release_on() then return build_packs, tonumber(s), name end
    return nil
end

function BT.has(path)
    return target(path) ~= nil
end

function BT.data(path)
    local fn, s, name = target(path)
    if not fn then return nil end
    local key = name .. s
    if not cache[key] then
        local ok, data = pcall(fn, path, s)
        if not ok then
            print("[booster_tints] " .. tostring(data))
            return nil
        end
        cache[key] = data
    end
    return cache[key]
end

function love.graphics.newImage(a, ...)
    local data = type(a) == "string" and BT.data(a)
    if data then return orig_image(data, ...) end
    return orig_image(a, ...)
end

booster_tints = BT
return BT
