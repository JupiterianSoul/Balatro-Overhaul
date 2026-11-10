local A = {}

A.ATLAS = 'mp_jokers_art'

A.SOURCES = {
    { 'j_mp_truce', 'j_smiley', 0.50 },
    { 'j_mp_bulwark', 'j_castle', 0.33 },
    { 'j_mp_shortcut', 'j_runner', 0.60 },
    { 'j_mp_tariff', 'j_credit_card', 0.45 },
    { 'j_mp_mirror_match', 'j_mime', 0.75 },
    { 'j_mp_envy', 'j_green_joker', 0.15 },
    { 'j_mp_leftovers', 'j_popcorn', 0.55 },
    { 'j_mp_photo_finish', 'j_photograph', 0.40 },
    { 'j_mp_high_roller', 'j_lucky_cat', 0.70 },
    { 'j_mp_grudge', 'j_ceremonial', 0.85 },
    { 'j_mp_summit', 'j_mystic_summit', 0.50 },
    { 'j_mp_base_camp', 'j_campfire', 0.60 },
    { 'j_mp_slipstream', 'j_rocket', 0.40 },
    { 'j_mp_pace_car', 'j_drivers_license', 0.30 },
    { 'j_mp_underdog', 'j_luchador', 0.50 },
    { 'j_mp_vulture', 'j_vampire', 0.35 },
    { 'j_mp_wingman', 'j_duo', 0.20 },
    { 'j_mp_huddle', 'j_family', 0.80 },
    { 'j_mp_war_banner', 'j_banner', 0.15 },
    { 'j_mp_supply_drop', 'j_gift', 0.55 },
}

A.SLOT = {}
for i, s in ipairs(A.SOURCES) do A.SLOT[s[1]] = { index = i - 1, src = s[2], shift = s[3] } end

local function hls(r, g, b)
    local mx, mn = math.max(r, g, b), math.min(r, g, b)
    local l = (mx + mn) / 2
    if mx == mn then return 0, l, 0 end
    local d = mx - mn
    local s = l > 0.5 and d / (2 - mx - mn) or d / (mx + mn)
    local h
    if mx == r then h = (g - b) / d + (g < b and 6 or 0)
    elseif mx == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    return h / 6, l, s
end

local function hue2(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
end

local function rgb(h, l, s)
    if s == 0 then return l, l, l end
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    return hue2(p, q, h + 1 / 3), hue2(p, q, h), hue2(p, q, h - 1 / 3)
end

A.hls, A.rgb = hls, rgb

function A.shift_pixel(r, g, b, shift)
    local h, l, s = hls(r, g, b)
    if s < 0.18 or l > 0.93 or l < 0.1 then return r, g, b end
    return rgb((h + shift) % 1, l, s)
end

function A.build(scale, centers)
    local sc = scale or 1
    local ok, src = pcall(love.image.newImageData, "resources/textures/" .. sc .. "x/Jokers.png")
    if not ok or not src then return nil end
    local cw, ch = 71 * sc, 95 * sc
    local out = love.image.newImageData(cw * #A.SOURCES, ch)
    local sw, sh = src:getWidth(), src:getHeight()
    local ok_ra, ra = pcall(require, "functions/art/release_art")
    if not (ok_ra and type(ra) == "table" and ra.mp_tint and ra.mp_mark) then ra = nil end
    for i, s in ipairs(A.SOURCES) do
        local c = centers[s[2]]
        local pos = c and c.pos
        if pos then
            local sx, sy = pos.x * cw, pos.y * ch
            if sx + cw <= sw and sy + ch <= sh then
                local ox = (i - 1) * cw
                for y = 0, ch - 1 do
                    for x = 0, cw - 1 do
                        local r, g, b, al = src:getPixel(sx + x, sy + y)
                        if al > 0 then
                            if ra then r, g, b = ra.mp_tint(r, g, b) else r, g, b = A.shift_pixel(r, g, b, s[3]) end
                        end
                        out:setPixel(ox + x, y, r, g, b, al)
                    end
                end
                if ra then ra.mp_mark(out, ox, sc) end
            end
        end
    end
    src:release()
    return out
end

function A.register()
    if not (G and G.ASSET_ATLAS and G.P_CENTERS and G.SETTINGS and love and love.graphics) then return false end
    if G.ASSET_ATLAS[A.ATLAS] then return true end
    local s = (G.SETTINGS.GRAPHICS and G.SETTINGS.GRAPHICS.texture_scaling) or 2
    local ok, data = pcall(A.build, s, G.P_CENTERS)
    if not ok or not data then
        if mp_log then mp_log.warn('BOM_JOKER_ART', 'joker art failed: %s', tostring(data)) end
        return false
    end
    G.ASSET_ATLAS[A.ATLAS] = {
        name = A.ATLAS, image = love.graphics.newImage(data, { mipmaps = true, dpiscale = s }),
        type = 'asset_atli', px = 71, py = 95,
    }
    return true
end

function A.slot(key)
    local s = A.SLOT[key]
    if not s or not A.register() then return nil end
    return { atlas = A.ATLAS, pos = { x = s.index, y = 0 } }
end

function A.apply()
    if not A.register() then return false end
    local o = rawget(_G, 'bom_custom_objects')
    for key, s in pairs(A.SLOT) do
        local c = G.P_CENTERS[key]
        if c and c.key == key then
            c.atlas, c.pos, c.ai_art = A.ATLAS, { x = s.index, y = 0 }, false
        end
        local d = o and o.DEFS and o.DEFS[key]
        if d then d.atlas, d.pos = A.ATLAS, { x = s.index, y = 0 } end
    end
    return true
end

return A
