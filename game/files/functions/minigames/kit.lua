local MG = Minigames
local K = MG.kit or {}
MG.kit = K

local floor, min, max, abs, sin, cos, pi, exp = math.floor, math.min, math.max, math.abs, math.sin, math.cos, math.pi, math.exp

function K.now() return love.timer.getTime() end

function K.rng()
    local t = love.timer.getTime()
    return love.math.newRandomGenerator(os.time() + floor((t - floor(t)) * 1000003))
end

function K.sound(name, pitch, vol)
    if play_sound then pcall(play_sound, name, pitch or 1, vol or 0.6) end
end

function K.card_w() return G.CARD_W or 2.05 end
function K.card_h() return G.CARD_H or 2.75 end

local cache = {}
local sprites = {}
local blinds = {}
local skins = {}

local function quiet(s)
    s.states.collide.can = false
    s.states.hover.can = false
    s.states.click.can = false
    s.states.drag.can = false
    s.created_on_pause = true
end

local function sprite(atlas, pos)
    if not (atlas and pos) then return nil end
    local per = cache[atlas]
    if not per then per = {} cache[atlas] = per end
    local id = (pos.y or 0) * 1000 + (pos.x or 0)
    local s = per[id]
    if s == nil then
        local ok, made = pcall(Sprite, 0, 0, 1, 1, atlas, pos)
        s = ok and made or false
        if s then quiet(s) sprites[#sprites + 1] = s end
        per[id] = s
    end
    return s or nil
end

function K.jokers()
    local all, seen = {}, {}
    for _, c in ipairs(G.P_CENTER_POOLS and G.P_CENTER_POOLS.Joker or {}) do
        if c.key and c.pos and not c.display_size and not c.pixel_size and not c.no_collection and not seen[c.key] then
            seen[c.key] = true
            all[#all + 1] = c
        end
    end
    local found = {}
    for _, c in ipairs(all) do if c.discovered then found[#found + 1] = c.key end end
    if #found >= 24 then return found end
    for i = 1, #all do all[i] = all[i].key end
    return all
end

function K.clear()
    for i = #sprites, 1, -1 do
        pcall(function() sprites[i]:remove() end)
        sprites[i] = nil
    end
    cache = {}
    blinds = {}
    skins = {}
end

local function put(s, x, y, w, h, r)
    local T, V = s.T, s.VT
    T.x, T.y, T.w, T.h, T.r, T.scale = x - w / 2, y - h / 2, w, h, r or 0, 1
    V.x, V.y, V.w, V.h, V.r, V.scale = T.x, T.y, w, h, T.r, 1
end

local alpha_col = {1, 1, 1, 1}

local function draw_sprite(s, x, y, w, h, r, a, shadow)
    if not s or w <= 0.001 or h <= 0.001 then return end
    s.dissolve = (a and a < 0.999) and min(1, 1 - a) or 0
    local keep = G.BRUTE_OVERLAY
    if a and a < 0.999 then
        alpha_col[4] = max(0, a)
        G.BRUTE_OVERLAY = alpha_col
    end
    if shadow then
        put(s, x, y, w, h, r)
        s:draw_shader("dissolve", shadow)
    end
    put(s, x, y, w, h, r)
    s:draw_shader("dissolve")
    G.BRUTE_OVERLAY = keep
end

function K.blind(key, x, y, size, o)
    local b = G.P_BLINDS and G.P_BLINDS[key or "bl_hook"]
    if not (b and b.pos) then return end
    local s = blinds[key]
    if s == nil then
        local atlas = (b.atlas and G.ANIMATION_ATLAS[b.atlas]) or G.ANIMATION_ATLAS.blind_chips
        local ok, made = pcall(AnimatedSprite, 0, 0, 1, 1, atlas, b.pos)
        s = ok and made or false
        if s then quiet(s) sprites[#sprites + 1] = s end
        blinds[key] = s
    end
    if s and s.scale then s.scale_mag = min(s.scale.x / size, s.scale.y / size) end
    draw_sprite(s or nil, x, y, size, size, o and o.r or 0, o and o.a or 1, (not o or o.shadow ~= false) and 0.1 or nil)
end

local function center_atlas(c)
    if not c then return nil end
    if c.atlas and G.ASSET_ATLAS[c.atlas] then return G.ASSET_ATLAS[c.atlas] end
    if c.set == "Joker" then return G.ASSET_ATLAS.Joker end
    if c.set == "Tarot" or c.set == "Planet" or c.set == "Spectral" then return G.ASSET_ATLAS.Tarot end
    if c.set == "Voucher" then return G.ASSET_ATLAS.Voucher end
    if c.set == "Booster" then return G.ASSET_ATLAS.Booster end
    return G.ASSET_ATLAS.centers
end

local function front_info(key)
    local f = G.P_CARDS and G.P_CARDS[key]
    if not f then return nil end
    if get_front_spriteinfo then
        local ok, atlas, pos = pcall(get_front_spriteinfo, f)
        if ok and atlas and pos then return atlas, pos end
    end
    return G.ASSET_ATLAS.cards_1, f.pos
end

function K.center_sprite(key)
    local c = G.P_CENTERS and G.P_CENTERS[key]
    if not (c and c.pos) then return nil end
    return sprite(center_atlas(c), c.pos)
end

function K.front_sprite(key)
    local atlas, pos = front_info(key)
    return sprite(atlas, pos)
end

function K.flip_k(flip)
    return abs(cos(pi * (flip or 0)))
end

function K.card(front, x, y, s, o)
    s = s or 1
    local w, h = K.card_w() * s, K.card_h() * s
    local r = o and o.r or 0
    local a = o and o.a or 1
    local flip = o and o.flip or 0
    local back = flip > 0.5 or not front
    local fw = w * K.flip_k(flip)
    local sh = (not o or o.shadow ~= false) and 0.15 or nil
    if back then
        draw_sprite(K.center_sprite(o and o.back or "b_red"), x, y, fw, h, r, a, sh)
    else
        draw_sprite(K.center_sprite(o and o.enh or "c_base"), x, y, fw, h, r, a, sh)
        draw_sprite(K.front_sprite(front), x, y, fw, h, r, a, nil)
    end
end

function K.center(key, x, y, s, o)
    s = s or 1
    local w, h = K.card_w() * s, K.card_h() * s * (o and o.vk or 1)
    local flip = o and o.flip or 0
    local fw = w * K.flip_k(flip)
    local sh = (not o or o.shadow ~= false) and 0.15 or nil
    if flip > 0.5 then
        draw_sprite(K.center_sprite(o and o.back or "b_red"), x, y, fw, h, o and o.r or 0, o and o.a or 1, sh)
        return
    end
    draw_sprite(K.center_sprite(key), x, y, fw, h, o and o.r or 0, o and o.a or 1, sh)
    local c = G.P_CENTERS and G.P_CENTERS[key]
    if c and c.soul_pos then
        draw_sprite(sprite(center_atlas(c), c.soul_pos), x, y, fw, h, o and o.r or 0, o and o.a or 1, nil)
    end
end

function K.skin_key()
    local key = "j_joker"
    if JimboSkinManager_get_equipped then
        local ok, k = pcall(JimboSkinManager_get_equipped)
        local c = ok and k and G.P_CENTERS and G.P_CENTERS[k]
        if c and c.pos then key = k end
    end
    return key
end

function K.skin_shape(key)
    local c = G.P_CENTERS and G.P_CENTERS[key]
    local wk, hk, cw, ch = 1, 1, 1, 1
    if not c then return wk, hk, cw, ch end
    local atlas = center_atlas(c)
    local px, py = atlas and atlas.px or 71, atlas and atlas.py or 95
    if c.name == "Half Joker" then hk, ch = 1 / 1.7, 1 / 1.7
    elseif c.name == "Photograph" then hk, ch = 1 / 1.2, 1 / 1.2
    elseif c.name == "Square Joker" then hk, ch = K.card_w() / K.card_h(), px / py
    elseif c.name == "Wee Joker" then wk, hk = 0.7, 0.7 end
    if c.display_size then
        wk = (c.display_size.w or 71) / 71
        hk = (c.display_size.h or 95) / 95
    end
    if c.pixel_size then
        if c.pixel_size.w then cw = c.pixel_size.w / px end
        if c.pixel_size.h then ch = c.pixel_size.h / py end
    end
    return wk, hk, cw, ch
end

local function skin_sprite(key, pos, cw, ch, soul)
    local id = key .. (soul and "|s" or "")
    local s = skins[id]
    if s == nil then
        local c = G.P_CENTERS[key]
        local ok, made = pcall(Sprite, 0, 0, 1, 1, center_atlas(c), pos)
        s = ok and made or false
        if s then
            quiet(s)
            if not soul and (cw ~= 1 or ch ~= 1) then
                s.scale.x, s.scale.y = s.atlas.px * cw, s.atlas.py * ch
                s:set_sprite_pos(pos)
            end
            sprites[#sprites + 1] = s
        end
        skins[id] = s
    end
    return s or nil
end

function K.skin(key, x, y, s, o)
    local c = G.P_CENTERS and G.P_CENTERS[key]
    if not (c and c.pos) then return K.center("j_joker", x, y, s, o) end
    local wk, hk, cw, ch = K.skin_shape(key)
    local w, h = K.card_w() * s * wk, K.card_h() * s * hk * (o and o.vk or 1)
    local r, a = o and o.r or 0, o and o.a or 1
    local sh = (not o or o.shadow ~= false) and 0.15 or nil
    draw_sprite(skin_sprite(key, c.pos, cw, ch), x, y, w, h, r, a, sh)
    if c.soul_pos then
        local f = sin(K.now() * 2) * 0.02 * h
        draw_sprite(skin_sprite(key, c.soul_pos, cw, ch, true), x, y - f, w, h, r, a, nil)
    end
    return w, h
end

function K.chip(stake, x, y, size, o)
    local st = G.P_STAKES and G.P_STAKES[stake or "stake_white"]
    local s = sprite(G.ASSET_ATLAS.chips, st and st.pos or {x = 0, y = 0})
    draw_sprite(s, x, y, size, size, o and o.r or 0, o and o.a or 1, (not o or o.shadow ~= false) and 0.1 or nil)
end

local function font()
    return G.LANG and G.LANG.font
end

function K.text_w(str, scale)
    local f = font()
    if not (f and f.FONT) then return #str * scale * 0.3 end
    return f.FONT:getWidth(str) * (f.squish or 1) * scale * (f.FONTSCALE or 0.1) / G.TILESIZE
end

local text_col = {1, 1, 1, 1}

function K.text(str, x, y, scale, colour, align, a, shadow)
    local f = font()
    if not (f and f.FONT and str) then return 0 end
    local fs = (f.FONTSCALE or 0.1) / G.TILESIZE
    local sx, sy = scale * (f.squish or 1) * fs, scale * fs
    local w = f.FONT:getWidth(str) * sx
    local h = f.FONT:getHeight() * sy * (f.TEXT_HEIGHT_SCALE or 1)
    local x0 = (align == "l" and x) or (align == "r" and x - w) or (x - w / 2)
    local y0 = y - h / 2
    local ox, oy = (f.TEXT_OFFSET and f.TEXT_OFFSET.x or 0) * scale * fs, (f.TEXT_OFFSET and f.TEXT_OFFSET.y or 0) * scale * fs
    local c = colour or G.C.WHITE
    a = a or 1
    local prev = love.graphics.getFont()
    love.graphics.push()
    love.graphics.scale(G.TILESCALE * G.TILESIZE)
    love.graphics.setFont(f.FONT)
    if shadow ~= false then
        love.graphics.setColor(0, 0, 0, 0.3 * a * (c[4] or 1))
        love.graphics.print(str, x0 + ox + 0.025 * scale, y0 + oy + 0.04 * scale, 0, sx, sy)
    end
    text_col[1], text_col[2], text_col[3], text_col[4] = c[1], c[2], c[3], (c[4] or 1) * a
    love.graphics.setColor(text_col)
    love.graphics.print(str, x0 + ox, y0 + oy, 0, sx, sy)
    love.graphics.pop()
    if prev then love.graphics.setFont(prev) end
    return w
end

local dark = {0, 0, 0, 1}

function K.rect(x, y, w, h, colour, r, a)
    local c = colour or G.C.BLACK
    a = a or 1
    love.graphics.push()
    love.graphics.scale(G.TILESCALE * G.TILESIZE)
    text_col[1], text_col[2], text_col[3], text_col[4] = c[1], c[2], c[3], (c[4] or 1) * a
    love.graphics.setColor(text_col)
    love.graphics.rectangle("fill", x, y, w, h, r or 0.1, r or 0.1, 8)
    love.graphics.pop()
end

function K.panel(x, y, w, h, colour, r, a, emboss)
    local c = colour or G.C.BLACK
    emboss = emboss or 0.06
    a = a or 1
    dark[1], dark[2], dark[3], dark[4] = c[1] * 0.6, c[2] * 0.6, c[3] * 0.6, (c[4] or 1)
    K.rect(x, y + emboss, w, h, dark, r, a)
    K.rect(x, y, w, h, c, r, a)
end

function K.outline(x, y, w, h, colour, r, lw, a)
    local c = colour or G.C.WHITE
    love.graphics.push()
    love.graphics.scale(G.TILESCALE * G.TILESIZE)
    text_col[1], text_col[2], text_col[3], text_col[4] = c[1], c[2], c[3], (c[4] or 1) * (a or 1)
    love.graphics.setColor(text_col)
    love.graphics.setLineWidth(lw or 0.04)
    love.graphics.rectangle("line", x, y, w, h, r or 0.1, r or 0.1, 8)
    love.graphics.pop()
end

function K.clip(x, y, w, h)
    love.graphics.push()
    love.graphics.scale(G.TILESCALE * G.TILESIZE)
    local x1, y1 = love.graphics.transformPoint(x, y)
    local x2, y2 = love.graphics.transformPoint(x + w, y + h)
    love.graphics.pop()
    love.graphics.setScissor(floor(x1), floor(y1), max(0, floor(x2 - x1 + 0.5)), max(0, floor(y2 - y1 + 0.5)))
end

function K.unclip()
    love.graphics.setScissor()
end

function K.circle(x, y, rad, colour, a)
    local c = colour or G.C.WHITE
    love.graphics.push()
    love.graphics.scale(G.TILESCALE * G.TILESIZE)
    text_col[1], text_col[2], text_col[3], text_col[4] = c[1], c[2], c[3], (c[4] or 1) * (a or 1)
    love.graphics.setColor(text_col)
    love.graphics.circle("fill", x, y, rad, 32)
    love.graphics.pop()
end

function K.arc(x, y, rad, a1, a2, colour, a)
    local c = colour or G.C.WHITE
    love.graphics.push()
    love.graphics.scale(G.TILESCALE * G.TILESIZE)
    text_col[1], text_col[2], text_col[3], text_col[4] = c[1], c[2], c[3], (c[4] or 1) * (a or 1)
    love.graphics.setColor(text_col)
    love.graphics.arc("fill", "pie", x, y, rad, a1, a2, 24)
    love.graphics.pop()
end

function K.poly(colour, a, ...)
    local c = colour or G.C.WHITE
    love.graphics.push()
    love.graphics.scale(G.TILESCALE * G.TILESIZE)
    text_col[1], text_col[2], text_col[3], text_col[4] = c[1], c[2], c[3], (c[4] or 1) * (a or 1)
    love.graphics.setColor(text_col)
    love.graphics.polygon("fill", ...)
    love.graphics.pop()
end

function K.bar(x, y, w, h, u, colour, a)
    u = max(0, min(1, u))
    K.rect(x, y, w, h, G.C.UI.TRANSPARENT_DARK or G.C.BLACK, h / 2, a)
    if u > 0 then K.rect(x, y, max(h, w * u), h, colour or G.C.GREEN, h / 2, a) end
end

function K.set_cursor(x, y)
    K.mx, K.my = x, y
end

local hover_col = {0, 0, 0, 0.2}

function K.hovered(x, y, w, h)
    local mx, my = K.mx, K.my
    return mx ~= nil and my ~= nil and mx >= x and mx <= x + w and my >= y and my <= y + h
end

function K.button(b, a, ox, oy)
    ox, oy = ox or 0, oy or 0
    local now = K.now()
    local down = b.down_t and now - b.down_t < 0.12
    local col = b.disabled and G.C.UI.BACKGROUND_INACTIVE or (b.colour or G.C.BLUE)
    local e = down and 0.02 or 0.07
    local hov = not b.disabled and (a or 1) > 0.5 and K.hovered(ox + b.x, oy + b.y, b.w, b.h)
    if hov and not b.hov then K.juice(b, 0.12) end
    b.hov = hov
    local jk = K.jk(b)
    local w, h = b.w * jk, b.h * jk
    local x, y = ox + b.x + (b.w - w) / 2, oy + b.y + (b.h - h) / 2
    dark[1], dark[2], dark[3], dark[4] = col[1] * 0.6, col[2] * 0.6, col[3] * 0.6, 1
    K.rect(x, y + 0.07, w, h, dark, 0.1, a)
    K.rect(x, y + (0.07 - e), w, h, col, 0.1, a)
    if hov or down then K.rect(x, y + (0.07 - e), w, h, hover_col, 0.1, a) end
    local sc = b.scale or 0.45
    local tw = K.text_w(b.label, sc)
    if tw > w - 0.2 then sc = sc * (w - 0.2) / tw end
    K.text(b.label, x + w / 2, y + (0.07 - e) + h / 2, sc, b.disabled and G.C.UI.TEXT_INACTIVE or G.C.UI.TEXT_LIGHT, "c", a)
end

function K.hit(b, x, y, pad)
    pad = pad or 0
    return x >= b.x - pad and x <= b.x + b.w + pad and y >= b.y - pad and y <= b.y + b.h + pad
end

function K.press(b)
    b.down_t = K.now()
    K.juice(b, 0.25)
    K.sound("button", 1, 0.3)
end

function K.fit(str, scale, width)
    local tw = K.text_w(str, scale)
    if tw > width then return scale * width / tw end
    return scale
end

function K.wrap2(str, scale, width, cache)
    if cache.src == str and cache.width == width and cache.scale == scale then return cache.l1, cache.l2, cache.sc end
    cache.src, cache.width, cache.scale, cache.l1, cache.l2, cache.sc = str, width, scale, str, nil, scale
    local nl = str:find("\n", 1, true)
    if nl then
        cache.l1, cache.l2 = str:sub(1, nl - 1), str:sub(nl + 1)
        local w = max(K.text_w(cache.l1, scale), K.text_w(cache.l2, scale))
        if w > width then cache.sc = scale * width / w end
    elseif K.text_w(str, scale) > width then
        local mid, cut = #str / 2, nil
        for i = 1, #str do
            if str:sub(i, i) == " " and (not cut or abs(i - mid) < abs(cut - mid)) then cut = i end
        end
        if cut then cache.l1, cache.l2 = str:sub(1, cut - 1), str:sub(cut + 1) end
        local w = max(K.text_w(cache.l1, scale), cache.l2 and K.text_w(cache.l2, scale) or 0)
        if w > width then cache.sc = scale * width / w end
    end
    return cache.l1, cache.l2, cache.sc
end

function K.juice(o, amt)
    o.jt = K.now()
    o.ja = amt or 0.3
end

function K.jk(o)
    if not o.jt then return 1 end
    local t = K.now() - o.jt
    if t > 0.6 then return 1 end
    return 1 + (o.ja or 0.3) * sin(t * 28) * exp(-t * 7) * 0.4
end

function K.jr(o)
    if not o.jt then return 0 end
    local t = K.now() - o.jt
    if t > 0.6 then return 0 end
    return (o.ja or 0.3) * sin(t * 22) * exp(-t * 7) * 0.15
end

function K.shake(amt)
    local now = K.now()
    local keep = (K.sh_t and K.sh_a and now - K.sh_t < 0.15) and K.sh_a or 0
    K.sh_t, K.sh_a = now, max(amt or 0.08, keep)
end

function K.shake_off()
    if not K.sh_t then return 0, 0 end
    local t = K.now() - K.sh_t
    if t > 0.4 then return 0, 0 end
    local a = (K.sh_a or 0.08) * exp(-t * 10)
    return sin(t * 61) * a, cos(t * 47) * a * 0.6
end

local flash_col = {1, 1, 1, 1}

function K.flash(colour, a)
    local c = colour or G.C.WHITE
    flash_col[1], flash_col[2], flash_col[3] = c[1], c[2], c[3]
    K.fl_t, K.fl_a = K.now(), a or 0.25
end

function K.draw_flash(x, y, w, h)
    if not K.fl_t then return end
    local t = K.now() - K.fl_t
    if t > 0.35 then return end
    K.rect(x, y, w, h, flash_col, 0.12, (K.fl_a or 0.25) * (1 - t / 0.35))
end

function K.hover(o, x, y, w, h)
    local hov = K.hovered(x, y, w, h)
    if hov and not o.hov then K.juice(o, 0.15) end
    o.hov = hov
    return hov
end

function K.out_back(u)
    if u >= 1 then return 1 end
    if u <= 0 then return 0 end
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (u - 1) ^ 3 + c1 * (u - 1) ^ 2
end

function K.smooth(u)
    if u >= 1 then return 1 end
    if u <= 0 then return 0 end
    return u * u * (3 - 2 * u)
end

function K.lerp(a, b, u) return a + (b - a) * u end

function K.pops(n)
    local list = {}
    for i = 1, n or 6 do list[i] = {t = -10, text = "", x = 0, y = 0, colour = nil, scale = 0.6} end
    list.i = 0
    return list
end

function K.pop(list, text, x, y, colour, scale)
    list.i = list.i % #list + 1
    local p = list[list.i]
    p.t, p.text, p.x, p.y, p.colour, p.scale = K.now(), text, x, y, colour, scale or 0.6
end

function K.draw_pops(list, ox, oy)
    local now = K.now()
    for i = 1, #list do
        local p = list[i]
        local t = now - p.t
        if t >= 0 and t < 0.9 then
            local k = K.out_back(min(1, t / 0.18))
            local a = t < 0.6 and 1 or (1 - (t - 0.6) / 0.3)
            K.text(p.text, ox + p.x, oy + p.y - t * 0.6, p.scale * k, p.colour or G.C.WHITE, "c", a)
        end
    end
end

function K.shuffle(rng, t)
    for i = #t, 2, -1 do
        local j = rng:random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

K.SUITS = {"H", "C", "D", "S"}
K.RANKS = {"2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"}

function K.deck(rng)
    local d = {}
    for _, s in ipairs(K.SUITS) do
        for r = 1, 13 do d[#d + 1] = {suit = s, rank = r + 1, key = s .. "_" .. K.RANKS[r]} end
    end
    return K.shuffle(rng, d)
end

return K
