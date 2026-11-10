local M = {}

M.SIZES = {16, 24, 32, 48, 64, 128, 256}
local S = 256
local CW, CH = 142, 190
local ACE = {x = 12, y = 0}
local BASE_CARD = {x = 1, y = 0}
local HOLO = {x = 4, y = 12}
local HOLO_SOUL = {x = 2, y = 9}
M.LAYOUT = {
    back = {x = 86, y = 111, r = -0.13, s = 0.845},
    front = {x = 166, y = 140, r = 0.187, s = 0.86},
}
M.ORIGINAL = "official_icon.png"

local SWIRL = [[
extern vec4 c1;
extern vec4 c2;
vec4 effect(vec4 colour, Image tex, vec2 tc, vec2 sc) {
    vec2 p = sc / love_ScreenSize.xy - 0.5;
    float r = length(p);
    float a = atan(p.y, p.x) + 4.2 * r;
    vec2 q = vec2(cos(a), sin(a)) * r * 9.0;
    for (int i = 0; i < 4; i++) {
        q += 0.6 * vec2(sin(q.y * 1.3 + 1.7), cos(q.x * 1.1 - 0.4));
    }
    float w = 0.5 + 0.5 * sin(q.x + q.y);
    float side = clamp(0.5 + 1.6 * (p.x - p.y) + 0.35 * (w - 0.5), 0.0, 1.0);
    vec3 col = mix(c2.rgb, c1.rgb, smoothstep(0.35, 0.65, side));
    float shade = 0.55 + 0.45 * w;
    col *= mix(0.55, 1.0, shade) * (1.0 - 0.35 * r);
    return vec4(col, 1.0);
}
]]

local POLY = [[
extern float shift;
vec3 hue(float h) {
    return clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
}
vec4 effect(vec4 colour, Image tex, vec2 tc, vec2 sc) {
    vec4 t = Texel(tex, tc) * colour;
    float lum = dot(t.rgb, vec3(0.299, 0.587, 0.114));
    float h = fract((sc.x + sc.y) / (love_ScreenSize.x * 1.1) + shift);
    vec3 rb = hue(h);
    vec3 mixed = mix(t.rgb, t.rgb * 0.6 + rb * 0.5, 0.42 * smoothstep(0.25, 0.95, lum));
    return vec4(mixed, t.a);
}
]]

local function read_from(dir)
    return function(rel)
        local f = io.open(dir .. "/" .. rel, "rb")
        if not f then return nil end
        local d = f:read("*a")
        f:close()
        return d
    end
end
M.read_from = read_from

local function image(read, rel)
    local raw = read(rel)
    if not raw then return nil end
    local ok, img = pcall(love.graphics.newImage, love.image.newImageData(love.filesystem.newFileData(raw, rel:match("[^/]+$"))))
    if not ok then return nil end
    img:setFilter("linear", "linear")
    return img
end

local function shader(code)
    local ok, sh = pcall(love.graphics.newShader, code)
    return ok and sh or nil
end

local function send(sh, name, ...)
    pcall(sh.send, sh, name, ...)
end

local function vanilla_shader(read, name)
    local raw = read("resources/shaders/" .. name .. ".fs")
    return raw and shader(raw) or nil
end

local function background()
    local g = love.graphics
    local sh = shader(SWIRL)
    if sh then
        send(sh, "c1", {0.80, 0.10, 0.12, 1})
        send(sh, "c2", {0.04, 0.33, 0.74, 1})
        g.setShader(sh)
    end
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", 0, 0, S, S)
    g.setShader()
end

local function edition_shader(read, name)
    local sh = read and vanilla_shader(read, name)
    if not sh then return nil end
    send(sh, name, {0.65, 20})
    send(sh, "time", 20)
    send(sh, "dissolve", 0)
    send(sh, "shadow", false)
    send(sh, "burn_colour_1", {0, 0, 0, 0})
    send(sh, "burn_colour_2", {0, 0, 0, 0})
    send(sh, "hovering", 0)
    send(sh, "mouse_screen_pos", {0, 0})
    send(sh, "screen_scale", 1)
    return sh
end

local function original(read)
    local raw = read and read(M.ORIGINAL)
    if not raw and love.filesystem.getInfo(M.ORIGINAL) then raw = love.filesystem.read(M.ORIGINAL) end
    if not raw then return nil end
    local ok, img = pcall(love.graphics.newImage, love.image.newImageData(love.filesystem.newFileData(raw, M.ORIGINAL)))
    if not ok then return nil end
    img:setFilter("linear", "linear")
    return img
end
M.original = original

local function backdrop(read)
    local img = original(read)
    if not img then return background() end
    local g = love.graphics
    g.setColor(1, 1, 1, 1)
    g.draw(img, 0, 0, 0, S / img:getWidth(), S / img:getHeight())
    return true
end

local function poly_shader(read)
    local sh = read and vanilla_shader(read, "polychrome")
    if sh then
        send(sh, "polychrome", {0.65, 20})
        send(sh, "time", 20)
        send(sh, "dissolve", 0)
        send(sh, "shadow", false)
        send(sh, "burn_colour_1", {0, 0, 0, 0})
        send(sh, "burn_colour_2", {0, 0, 0, 0})
        send(sh, "hovering", 0)
        send(sh, "mouse_screen_pos", {0, 0})
        send(sh, "screen_scale", 1)
        return sh, true
    end
    sh = shader(POLY)
    if sh then send(sh, "shift", 0.1) end
    return sh, false
end

local function shadow(img, quad, at)
    local g = love.graphics
    for i = 1, 3 do
        g.setColor(0, 0, 0, 0.13)
        g.draw(img, quad, at.x - 2 - i, at.y + 2 + i, at.r, at.s, at.s, CW / 2, CH / 2)
    end
end

local function sprite(img, pos, at, poly, vanilla_poly)
    local g = love.graphics
    local iw, ih = img:getDimensions()
    local quad = g.newQuad(pos.x * CW, pos.y * CH, CW, CH, iw, ih)
    if poly then
        if vanilla_poly then
            send(poly, "texture_details", {pos.x, pos.y, CW, CH})
            send(poly, "image_details", {iw, ih})
        end
        g.setShader(poly)
    end
    g.setColor(1, 1, 1, 1)
    g.draw(img, quad, at.x, at.y, at.r, at.s, at.s, CW / 2, CH / 2)
    g.setShader()
    return quad
end

local function begin_canvas(size)
    local g = love.graphics
    size = size or S
    local canvas = g.newCanvas(size, size, {msaa = 4, dpiscale = 1})
    g.push("all")
    g.setCanvas({canvas, stencil = true})
    g.clear(0, 0, 0, 0)
    g.origin()
    g.scale(size / S)
    return canvas
end

local function end_canvas(canvas)
    local g = love.graphics
    g.setShader()
    g.setStencilTest()
    g.setCanvas()
    g.pop()
    return canvas
end

local function l_card(read, enh, deck)
    local g = love.graphics
    local font_raw = read("resources/fonts/m6x11plus.ttf")
    if not font_raw then return nil end
    local fd = love.filesystem.newFileData(font_raw, "m6x11plus.ttf")
    local big = g.newFont(fd, 132, "mono")
    local small = g.newFont(love.filesystem.newFileData(font_raw, "m6x11plus.ttf"), 44, "mono")
    big:setFilter("nearest", "nearest")
    small:setFilter("nearest", "nearest")
    local red = {0.9, 0.12, 0.15, 1}
    local ok, dd = pcall(function() return love.image.newImageData(love.filesystem.newFileData(read("resources/textures/2x/8BitDeck.png"), "deck.png")) end)
    if ok and dd then
        local r, gg, b = dd:getPixel(ACE.x * CW + 71, ACE.y * CH + 95)
        if r > 0.5 and gg < 0.4 then red = {r, gg, b, 1} end
    end
    local c = g.newCanvas(CW, CH, {dpiscale = 1})
    g.push("all")
    g.setCanvas(c)
    g.clear(0, 0, 0, 0)
    g.origin()
    g.setShader()
    g.setColor(1, 1, 1, 1)
    g.draw(enh, g.newQuad(BASE_CARD.x * CW, BASE_CARD.y * CH, CW, CH, enh:getDimensions()), 0, 0)
    g.setColor(red)
    local function ink(font, ch)
        local w, h = font:getWidth(ch) + 8, font:getHeight() + 8
        local t = g.newCanvas(w, h, {dpiscale = 1})
        g.push("all")
        g.setCanvas(t)
        g.clear(0, 0, 0, 0)
        g.origin()
        g.setColor(1, 1, 1, 1)
        g.setFont(font)
        g.print(ch, 4, 4)
        g.pop()
        local d = t:newImageData()
        local x0, y0, x1, y1 = w, h, -1, -1
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local _, _, _, a = d:getPixel(x, y)
                if a > 0.5 then
                    if x < x0 then x0 = x end
                    if x > x1 then x1 = x end
                    if y < y0 then y0 = y end
                    if y > y1 then y1 = y end
                end
            end
        end
        return x0 - 4, y0 - 4, x1 - x0 + 1, y1 - y0 + 1
    end
    g.setFont(big)
    local bx, by, bw, bh = ink(big, "L")
    g.print("L", math.floor(CW / 2 - bw / 2 - bx + 0.5), math.floor(CH / 2 - bh / 2 - by + 0.5))
    g.setFont(small)
    local sx, sy = ink(small, "L")
    g.print("L", 14 - sx, 12 - sy)
    g.pop()
    return c
end

local function shaded_card(img, at, sh)
    local g = love.graphics
    local w, h = img:getDimensions()
    if sh then
        send(sh, "texture_details", {0, 0, w, h})
        send(sh, "image_details", {w, h})
        g.setShader(sh)
    end
    g.setColor(1, 1, 1, 1)
    g.draw(img, at.x, at.y, at.r, at.s, at.s, w / 2, h / 2)
    g.setShader()
end

function M.compose_game(read, size, launcher)
    local deck = image(read, "resources/textures/2x/8BitDeck.png")
    local enh = image(read, "resources/textures/2x/Enhancers.png")
    local jok = image(read, "resources/textures/2x/Jokers.png")
    if not (deck and enh and jok) then return nil end
    local g = love.graphics
    local lc = launcher and l_card(read, enh, deck)
    if launcher and not lc then return nil end
    local canvas = begin_canvas(size)
    local had = backdrop(read)
    local poly, vp = poly_shader(read)
    local L = M.LAYOUT
    local q = g.newQuad(BASE_CARD.x * CW, BASE_CARD.y * CH, CW, CH, enh:getDimensions())
    if not had then shadow(enh, q, L.back) end
    if not lc then
        lc = g.newCanvas(CW, CH, {dpiscale = 1})
        g.push("all")
        g.setCanvas(lc)
        g.clear(0, 0, 0, 0)
        g.origin()
        g.setShader()
        g.setColor(1, 1, 1, 1)
        g.draw(enh, q, 0, 0)
        g.draw(deck, g.newQuad(ACE.x * CW, ACE.y * CH, CW, CH, deck:getDimensions()), 0, 0)
        g.pop()
    end
    local neg = edition_shader(read, "negative")
    if neg then
        shaded_card(lc, L.back, neg)
        shaded_card(lc, L.back, edition_shader(read, "negative_shine"))
    else
        shaded_card(lc, L.back, poly)
    end
    local hq = g.newQuad(HOLO.x * CW, HOLO.y * CH, CW, CH, jok:getDimensions())
    if not had then shadow(jok, hq, L.front) end
    sprite(jok, HOLO, L.front, poly, vp)
    local iw, ih = jok:getDimensions()
    local sq = g.newQuad(HOLO_SOUL.x * CW, HOLO_SOUL.y * CH, CW, CH, iw, ih)
    local f = L.front
    g.setColor(0.45, 0.95, 1, 0.92)
    g.draw(jok, sq, f.x, f.y - 3, f.r, f.s, f.s, CW / 2, CH / 2)
    g.setBlendMode("add")
    g.setColor(0.25, 0.75, 1, 0.35)
    g.draw(jok, sq, f.x + 1.5, f.y - 4, f.r, f.s, f.s, CW / 2, CH / 2)
    g.setBlendMode("alpha")
    return end_canvas(canvas)
end

local function ink_box(font, ch)
    local g = love.graphics
    local w, h = font:getWidth(ch) + 8, font:getHeight() + 8
    local c = g.newCanvas(w, h, {dpiscale = 1})
    g.push("all")
    g.setCanvas(c)
    g.clear(0, 0, 0, 0)
    g.origin()
    g.setColor(1, 1, 1, 1)
    g.setFont(font)
    g.print(ch, 4, 4)
    g.setCanvas()
    g.pop()
    local d = c:newImageData()
    local x0, y0, x1, y1 = w, h, -1, -1
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local _, _, _, a = d:getPixel(x, y)
            if a > 0.5 then
                if x < x0 then x0 = x end
                if x > x1 then x1 = x end
                if y < y0 then y0 = y end
                if y > y1 then y1 = y end
            end
        end
    end
    if x1 < 0 then return 0, 0 end
    return (x0 + x1 + 1) / 2 - 4, (y0 + y1 + 1) / 2 - 4
end

local function letter_card(at, ch, col, font, small, poly, k)
    local g = love.graphics
    local w, h = CW * at.s, CH * at.s
    g.push()
    g.translate(at.x, at.y)
    g.rotate(at.r)
    for i = 1, 3 do
        g.setColor(0, 0, 0, 0.13)
        g.rectangle("fill", -w / 2 - 2 - i, -h / 2 + 2 + i, w, h, 9, 9, 12)
    end
    if poly then g.setShader(poly) end
    g.setColor(0.97, 0.97, 0.98, 1)
    g.rectangle("fill", -w / 2, -h / 2, w, h, 9, 9, 12)
    g.setColor(0.84, 0.86, 0.9, 1)
    g.setLineWidth(2)
    g.rectangle("line", -w / 2 + 1, -h / 2 + 1, w - 2, h - 2, 8, 8, 12)
    g.setColor(col)
    g.setFont(font)
    local cx, cy = ink_box(font, ch)
    g.print(ch, -cx / k, -cy / k, 0, 1 / k)
    g.setFont(small)
    local sx, sy = ink_box(small, ch)
    local ix, iy = -w / 2 + 15, -h / 2 + 17
    g.print(ch, ix - sx / k, iy - sy / k, 0, 1 / k)
    g.print(ch, -ix + sx / k, -iy + sy / k, math.pi, 1 / k)
    g.setShader()
    g.pop()
end

function M.compose_launcher(size)
    local g = love.graphics
    local k = (size or S) / S
    local big = g.newFont(math.floor(92 * k + 0.5))
    local small = g.newFont(math.floor(22 * k + 0.5))
    local canvas = begin_canvas(size)
    background()
    local poly = poly_shader(nil)
    local L = M.LAYOUT
    letter_card(L.back, "O", {0.89, 0.13, 0.13, 1}, big, small, poly, k)
    letter_card(L.front, "L", {0.12, 0.2, 0.36, 1}, big, small, poly, k)
    return end_canvas(canvas)
end

local function scaled(canvas, size)
    local g = love.graphics
    if size == canvas:getWidth() then return canvas:newImageData() end
    local c = g.newCanvas(size, size, {dpiscale = 1})
    canvas:setFilter("linear", "linear")
    g.push("all")
    g.setCanvas(c)
    g.clear(0, 0, 0, 0)
    g.origin()
    g.setColor(1, 1, 1, 1)
    g.draw(canvas, 0, 0, 0, size / canvas:getWidth())
    g.setCanvas()
    g.pop()
    return c:newImageData()
end
M.scaled = scaled

local function u16(v) return string.char(v % 256, math.floor(v / 256) % 256) end
local function u32(v) return u16(v % 65536) .. u16(math.floor(v / 65536)) end

function M.ico(pngs)
    local head = u16(0) .. u16(1) .. u16(#pngs)
    local dir, blobs, off = {}, {}, 6 + 16 * #pngs
    for i, p in ipairs(pngs) do
        local s = p.size >= 256 and 0 or p.size
        dir[i] = string.char(s, s, 0, 0) .. u16(1) .. u16(32) .. u32(#p.data) .. u32(off)
        blobs[i] = p.data
        off = off + #p.data
    end
    return head .. table.concat(dir) .. table.concat(blobs)
end

function M.build(canvas)
    local pngs, big = {}, nil
    for _, s in ipairs(M.SIZES) do
        local d = scaled(canvas, s)
        if s == 256 then big = d end
        pngs[#pngs + 1] = {size = s, data = d:encode("png"):getString()}
    end
    return big, pngs[#pngs].data, M.ico(pngs)
end

function M.compose(kind, read, size)
    if kind == "launcher" then
        return (read and M.compose_game(read, size, true)) or M.compose_launcher(size)
    end
    return M.compose_game(read, size)
end

function M.png(kind, read, size)
    local canvas = M.compose(kind, read, size > S and size or nil)
    if not canvas then return nil end
    return scaled(canvas, size):encode("png"):getString()
end

function M.write_files(game_dir, out_dir, kind, name)
    local canvas = M.compose(kind, read_from(game_dir))
    if not canvas then return nil end
    local big, png, ico = M.build(canvas)
    name = name or (kind == "launcher" and "launcher_icon" or "app_icon")
    local ok = true
    for ext, data in pairs({png = png, ico = ico}) do
        local o = io.open(out_dir .. "/" .. name .. "." .. ext, "wb")
        if o then o:write(data) o:close() else ok = false end
    end
    return ok and (out_dir .. "/" .. name) or nil, big
end

function M.game_start()
    if not (love.graphics and love.window and love.window.setIcon) then return end
    local ok, canvas = pcall(M.compose_game, love.filesystem.read)
    if not ok or not canvas then return end
    local ok2, big, png, ico = pcall(M.build, canvas)
    if not ok2 or not big then return end
    pcall(love.window.setIcon, big)
    pcall(love.filesystem.write, "app_icon.png", png)
    pcall(love.filesystem.write, "app_icon.ico", ico)
end

return M
