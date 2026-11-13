local U = {}

local function hexc(h, a)
    return {tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, a or 1}
end

U.C = {
    red = hexc("FE5F55"),
    blue = hexc("009DFF"),
    green = hexc("4BC292"),
    orange = hexc("FDA200"),
    gold = hexc("EAC058"),
    black = hexc("374244"),
    l_black = hexc("4F6367"),
    grey = hexc("5F7377"),
    rim = hexc("BFC7D5"),
    inactive = hexc("88888899"),
    inactive_text = hexc("BBBBBB"),
    white = {1, 1, 1, 1},
    soft = hexc("C9D1DD"),
    dark = hexc("1E2B2D"),
    shadow = {0, 0, 0, 0.3},
}

function U.darken(c, f)
    return {c[1] * (1 - f), c[2] * (1 - f), c[3] * (1 - f), c[4] or 1}
end

function U.lighten(c, f)
    return {c[1] + (1 - c[1]) * f, c[2] + (1 - c[2]) * f, c[3] + (1 - c[3]) * f, c[4] or 1}
end

U.u = 60
U.touch_mode = false
U.time = 0

function U.px(v)
    return math.floor(v * U.u + 0.5)
end

local fonts, inks, caps = {}, {}, {}
local font_data

function U.set_font_data(data)
    font_data = data
    fonts, inks, caps = {}, {}, {}
end

function U.has_game_font()
    return font_data ~= nil
end

local function font_px(scale)
    local k = (font_data and 1.0 or 0.62) * (U.text_k or 1)
    return math.max(8, math.floor(scale * U.u * k + 0.5))
end

function U.font(scale)
    local size = font_px(scale)
    if not fonts[size] then
        local ok, f = false, nil
        if font_data then
            ok, f = pcall(love.graphics.newFont, font_data, size)
        end
        if not ok or not f then
            f = love.graphics.newFont(size)
        end
        fonts[size] = f
    end
    return fonts[size]
end

local function measure(font, text)
    local w = math.max(1, font:getWidth(text)) + 8
    local h = font:getHeight() + 8
    local canvas = love.graphics.newCanvas(w, h)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setShader(nil)
    love.graphics.replaceTransform(love.math.newTransform())
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(font)
    love.graphics.print(text, 4, 4)
    love.graphics.setCanvas(nil)
    love.graphics.pop()
    local img = canvas:newImageData()
    local pw, ph = img:getDimensions()
    local k = pw / w
    local x0, y0, x1, y1 = pw, ph, -1, -1
    for y = 0, ph - 1 do
        for x = 0, pw - 1 do
            local _, _, _, a = img:getPixel(x, y)
            if a > 0.2 then
                if x < x0 then x0 = x end
                if x > x1 then x1 = x end
                if y < y0 then y0 = y end
                if y > y1 then y1 = y end
            end
        end
    end
    canvas:release()
    img:release()
    if x1 < 0 then
        return 0, 0, font:getWidth(text), font:getHeight()
    end
    return x0 / k - 4, y0 / k - 4, (x1 + 1) / k - 4, (y1 + 1) / k - 4
end

local function ink_x(font, text)
    inks[font] = inks[font] or {}
    local c = inks[font][text]
    if not c then
        local l, _, r = measure(font, text)
        c = {l, r}
        inks[font][text] = c
    end
    return c[1], c[2]
end

local function cap_band(font)
    local c = caps[font]
    if not c then
        local _, t, _, b = measure(font, "HEXO")
        c = {t, b}
        caps[font] = c
    end
    return c[1], c[2]
end

function U.text_width(text, scale)
    local f = U.font(scale)
    local l, r = ink_x(f, text)
    return r - l
end

function U.raw_width(text, scale)
    return U.font(scale):getWidth(text)
end

function U.print_center(text, cx, cy, scale, color, shadow)
    local f = U.font(scale)
    local l, r = ink_x(f, text)
    local t, b = cap_band(f)
    local x = math.floor(cx - (l + r) / 2 + 0.5)
    local y = math.floor(cy - (t + b) / 2 + 0.5)
    love.graphics.setFont(f)
    if shadow ~= false then
        local d = math.max(1, math.floor(f:getHeight() / 16 + 0.5))
        love.graphics.setColor(0, 0, 0, 0.35 * ((color and color[4]) or 1))
        love.graphics.print(text, x + d, y + d)
    end
    love.graphics.setColor(color or U.C.white)
    love.graphics.print(text, x, y)
end

function U.print_left(text, x, cy, scale, color, shadow)
    local f = U.font(scale)
    local l = ink_x(f, text)
    local t, b = cap_band(f)
    x = math.floor(x - l + 0.5)
    local y = math.floor(cy - (t + b) / 2 + 0.5)
    love.graphics.setFont(f)
    if shadow ~= false then
        local d = math.max(1, math.floor(f:getHeight() / 16 + 0.5))
        love.graphics.setColor(0, 0, 0, 0.35)
        love.graphics.print(text, x + d, y + d)
    end
    love.graphics.setColor(color or U.C.white)
    love.graphics.print(text, x, y)
end

function U.fit(text, scale, w)
    local f = U.font(scale)
    if f:getWidth(text) <= w then
        return text
    end
    local s = text
    while #s > 1 and f:getWidth("..." .. s) > w do
        s = s:sub(2)
        while #s > 1 and s:byte(1) >= 128 and s:byte(1) < 192 do
            s = s:sub(2)
        end
    end
    return "..." .. s
end

function U.fit_scale(text, scale, w, min)
    local s = scale
    while s > (min or scale * 0.6) and U.font(s):getWidth(text) > w do
        s = s * 0.94
    end
    return s
end

function U.wrap(text, scale, w)
    local f = U.font(scale)
    local _, lines = f:getWrap(text, w)
    return lines
end

function U.line_h(scale)
    return math.floor(U.font(scale):getHeight() * 1.15 + 0.5)
end

function U.paragraph(text, x, y, w, scale, color)
    local lines = U.wrap(text, scale, w)
    local lh = U.line_h(scale)
    for i, line in ipairs(lines) do
        U.print_center(line, x + w / 2, y + (i - 0.5) * lh, scale, color, false)
    end
    return #lines * lh
end

function U.paragraph_height(text, scale, w)
    return #U.wrap(text, scale, w) * U.line_h(scale)
end

function U.rrect(mode, x, y, w, h, r)
    r = math.min(r, w / 2, h / 2)
    love.graphics.rectangle(mode, x, y, w, h, r, r, 10)
end

function U.window(x, y, w, h)
    local rim = U.px(0.07)
    local emb = U.px(0.1)
    love.graphics.setColor(U.darken(U.C.rim, 0.45))
    U.rrect("fill", x - rim, y - rim + emb, w + 2 * rim, h + 2 * rim, U.px(0.3))
    love.graphics.setColor(U.C.rim)
    U.rrect("fill", x - rim, y - rim, w + 2 * rim, h + 2 * rim, U.px(0.3))
    love.graphics.setColor(U.C.l_black)
    U.rrect("fill", x, y, w, h, U.px(0.2))
end

function U.box(x, y, w, h, color, r)
    love.graphics.setColor(color or U.C.black)
    U.rrect("fill", x, y, w, h, r or U.px(0.12))
end

U.hits = {}
U.focus = nil
U.anim = {}

function U.begin_frame()
    U.hits = {}
end

local function inside(h, mx, my)
    return mx >= h.x and mx <= h.x + h.w and my >= h.y and my <= h.y + h.h
end

local function anim(id)
    local a = U.anim[id]
    if not a then
        a = {hover = 0, juice = 0, seen = U.time}
        U.anim[id] = a
    end
    a.seen = U.time
    return a
end

function U.juice(id)
    anim(id).juice = U.time
end

function U.step_anims(dt)
    for id, a in pairs(U.anim) do
        local want = a.hot and 1 or 0
        a.hover = a.hover + (want - a.hover) * math.min(1, dt * 14)
        a.hot = false
        if U.time - a.seen > 2 then
            U.anim[id] = nil
        end
    end
end

local function hovered(x, y, w, h)
    if U.touch_mode or U.pointer_hidden then
        return false
    end
    local mx, my = love.mouse.getPosition()
    return mx >= x and mx <= x + w and my >= y and my <= y + h
end

function U.add_hit(id, x, y, w, h, action, opts)
    U.hits[#U.hits + 1] = {id = id, x = x, y = y, w = w, h = h, action = action, opts = opts}
end

function U.button(id, label, x, y, w, h, color, scale, action, opts)
    opts = opts or {}
    local a = anim(id)
    local off = opts.inactive
    local hot = not off and (U.focus == id or hovered(x, y, w, h))
    a.hot = hot
    local r = U.px(0.1)
    local drop = math.max(2, U.px(0.06))
    local pressed = U.pressed == id and not off
    local j = U.time - a.juice
    local bounce = j < 0.4 and math.sin(j * 28) * math.exp(-j * 9) * 0.07 or 0
    local grow = 1 + a.hover * 0.025 + bounce
    local lift = pressed and 0 or math.floor(-a.hover * U.px(0.04))
    local cw, ch = w * grow, h * grow
    local cx, cy = x + (w - cw) / 2, y + (h - ch) / 2 + lift
    local c = off and U.C.inactive or color
    if not off then
        love.graphics.setColor(U.darken(color, 0.45))
        U.rrect("fill", cx, y + (h - ch) / 2 + drop, cw, ch, r)
    end
    local oy = pressed and drop or 0
    love.graphics.setColor(c)
    U.rrect("fill", cx, cy + oy, cw, ch, r)
    if hot and a.hover > 0.01 then
        love.graphics.setColor(1, 1, 1, 0.1 * a.hover)
        U.rrect("fill", cx, cy + oy, cw, ch, r)
    end
    if U.focus == id and U.show_focus then
        love.graphics.setLineWidth(math.max(2, U.px(0.04)))
        love.graphics.setColor(1, 1, 1, 0.85)
        U.rrect("line", cx - U.px(0.06), cy + oy - U.px(0.06), cw + U.px(0.12), ch + U.px(0.12), r + U.px(0.06))
    end
    local tc = off and U.C.inactive_text or (opts.text_color or U.C.white)
    if type(label) == "table" then
        local lh = U.line_h(scale)
        for i, line in ipairs(label) do
            U.print_center(line, x + w / 2, cy + oy + ch / 2 + (i - (#label + 1) / 2) * lh, scale, tc, not off)
        end
    else
        local s = U.fit_scale(label, scale, w - U.px(0.3), scale * 0.55)
        U.print_center(U.fit(label, s, w - U.px(0.3)), x + w / 2, cy + oy + ch / 2, s * grow, tc, not off)
    end
    U.add_hit(id, x, y, w, h + drop, (not off) and action or nil, opts)
end

function U.pointer(cx, y, size, color)
    love.graphics.setColor(color)
    love.graphics.polygon("fill", cx - size, y, cx + size, y, cx, y + size)
end

function U.status_card(x, y, w, h, label, value, value_color)
    U.box(x, y, w, h, U.C.black)
    local ls, vs = U.phone and 0.4 or 0.34, U.phone and 0.5 or 0.42
    U.print_center(U.fit(label, ls, w - U.px(0.3)), x + w / 2, y + h * 0.3, ls, U.C.gold, false)
    local s = U.fit_scale(value, vs, w - U.px(0.3), 0.3)
    U.print_center(U.fit(value, s, w - U.px(0.3)), x + w / 2, y + h * 0.66, s, value_color or U.C.white)
end

function U.progress(x, y, w, h, frac, label)
    U.box(x, y, w, h, U.C.black, U.px(0.1))
    if frac and frac > 0 then
        love.graphics.setColor(U.C.green)
        U.rrect("fill", x, y, math.max(U.px(0.2), w * math.min(1, frac)), h, U.px(0.1))
    else
        local t = U.time * 1.6 % 1
        love.graphics.setColor(U.C.green[1], U.C.green[2], U.C.green[3], 0.7)
        local bw = w * 0.25
        local bx = x + (w + bw) * t - bw
        local x0, x1 = math.max(x, bx), math.min(x + w, bx + bw)
        if x1 > x0 then
            U.rrect("fill", x0, y, x1 - x0, h, U.px(0.1))
        end
    end
    U.print_center(U.fit(label, 0.42, w - U.px(0.3)), x + w / 2, y + h / 2, 0.42)
end

function U.toggle(id, label, x, y, w, h, value, action)
    local bs = U.px(U.phone and 0.8 or (U.touch_mode and 0.55 or 0.45))
    local gap = U.px(0.25)
    local fs = U.phone and 0.5 or 0.4
    local lw = U.text_width(label, fs)
    local total = lw + gap + bs
    local bx, by = x + math.floor(w * 0.62), y + (h - bs) / 2
    local lx = bx - gap - lw
    U.print_left(label, lx, y + h / 2, fs, U.C.white)
    local a = anim(id)
    local hot = U.focus == id or hovered(x, y, w, h)
    a.hot = hot
    local j = U.time - a.juice
    local bounce = j < 0.4 and math.sin(j * 28) * math.exp(-j * 9) * 0.12 or 0
    local g = 1 + bounce + a.hover * 0.06
    local gs = bs * g
    local gx, gy = bx + (bs - gs) / 2, by + (bs - gs) / 2
    love.graphics.setColor(U.C.black)
    U.rrect("fill", gx - U.px(0.05), gy - U.px(0.05), gs + U.px(0.1), gs + U.px(0.1), U.px(0.1))
    love.graphics.setColor(value and U.C.red or U.C.black)
    U.rrect("fill", gx, gy, gs, gs, U.px(0.08))
    love.graphics.setLineWidth(math.max(2, U.px(0.04)))
    love.graphics.setColor(U.C.white)
    U.rrect("line", gx, gy, gs, gs, U.px(0.08))
    if value then
        love.graphics.setLineWidth(math.max(2, U.px(0.07)))
        love.graphics.line(gx + gs * 0.24, gy + gs * 0.52, gx + gs * 0.43, gy + gs * 0.72, gx + gs * 0.77, gy + gs * 0.3)
    end
    if U.focus == id and U.show_focus then
        love.graphics.setLineWidth(math.max(2, U.px(0.04)))
        love.graphics.setColor(1, 1, 1, 0.85)
        U.rrect("line", lx - U.px(0.15), y, total + U.px(0.3), h, U.px(0.1))
    end
    U.add_hit(id, x, y, w, h, action)
end

function U.cycle(id, label, x, y, w, h, value, idx, count, prev, nxt)
    local ls = U.phone and 0.48 or 0.4
    U.print_center(label, x + w / 2, y + U.px(0.25), ls, U.C.white)
    local by = y + U.px(0.55)
    local bh = h - U.px(0.55) - U.px(0.25)
    local aw = U.phone and bh or U.px(0.7)
    U.button(id .. "_prev", "<", x, by, aw, bh, U.C.red, 0.5, prev)
    U.button(id .. "_next", ">", x + w - aw, by, aw, bh, U.C.red, 0.5, nxt)
    local mx, mw = x + aw + U.px(0.1), w - 2 * aw - U.px(0.2)
    U.box(mx, by, mw, bh, U.C.black, U.px(0.1))
    U.print_center(value, mx + mw / 2, by + bh / 2, U.phone and 0.52 or 0.42, U.C.white)
    local pr = math.max(3, U.px(0.065))
    local pg = U.px(0.28)
    local px0 = x + w / 2 - (count - 1) * pg / 2
    for i = 1, count do
        love.graphics.setColor(i == idx and U.C.white or U.C.black)
        love.graphics.circle("fill", px0 + (i - 1) * pg, by + bh + U.px(0.14), pr)
    end
end

function U.badge(text, x, cy, scale, color)
    local w = U.text_width(text, scale) + U.px(0.3)
    local h = U.px(scale * 1.15)
    U.box(x, cy - h / 2, w, h, color, U.px(0.08))
    U.print_center(text, x + w / 2, cy, scale, U.C.white)
    return w
end

function U.card(img, quad, cx, cy, h, t, tilt)
    local _, _, qw, qh = quad:getViewport()
    local s = h / qh
    local rot = math.sin(t * 1.3) * 0.03 + (tilt or 0) * 0.06
    local fy = math.sin(t * 1.7) * h * 0.012
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.draw(img, quad, cx + h * 0.04, cy + h * 0.05 + fy, rot, s, s, qw / 2, qh / 2)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(img, quad, cx, cy + fy, rot, s, s, qw / 2, qh / 2)
end

function U.blank_card(cx, cy, h, t, color)
    local w = h * 71 / 95
    local rot = math.sin(t * 1.3) * 0.03
    local fy = math.sin(t * 1.7) * h * 0.012
    love.graphics.push()
    love.graphics.translate(cx, cy + fy)
    love.graphics.rotate(rot)
    love.graphics.setColor(0, 0, 0, 0.3)
    U.rrect("fill", -w / 2 + h * 0.04, -h / 2 + h * 0.05, w, h, h * 0.06)
    love.graphics.setColor(U.C.white)
    U.rrect("fill", -w / 2, -h / 2, w, h, h * 0.06)
    love.graphics.setColor(color or U.C.red)
    U.rrect("fill", -w / 2 + h * 0.045, -h / 2 + h * 0.045, w - h * 0.09, h - h * 0.09, h * 0.04)
    love.graphics.pop()
    U.print_center("?", cx, cy + fy, h / U.u * 0.4, U.C.white)
end

function U.hit_at(mx, my)
    for i = #U.hits, 1, -1 do
        if inside(U.hits[i], mx, my) then
            return U.hits[i]
        end
    end
end

local function center(h)
    return h.x + h.w / 2, h.y + h.h / 2
end

function U.move_focus(dx, dy)
    local list = {}
    for _, h in ipairs(U.hits) do
        if h.action then
            list[#list + 1] = h
        end
    end
    if #list == 0 then
        return
    end
    local cur
    for _, h in ipairs(list) do
        if h.id == U.focus then
            cur = h
        end
    end
    if not cur then
        U.focus = list[1].id
        for _, h in ipairs(list) do
            if h.opts and h.opts.default then
                U.focus = h.id
                break
            end
        end
        return
    end
    local cx, cy = center(cur)
    local best, best_d
    for _, h in ipairs(list) do
        if h ~= cur then
            local hx, hy = center(h)
            local ax, ay = hx - cx, hy - cy
            local along = ax * dx + ay * dy
            if along > 1 then
                local across = math.abs(ax * dy - ay * dx)
                local d = along + across * 2.5
                if not best_d or d < best_d then
                    best, best_d = h, d
                end
            end
        end
    end
    if best then
        U.focus = best.id
    end
end

function U.focus_cycle(dir)
    local list = {}
    for _, h in ipairs(U.hits) do
        if h.action then
            list[#list + 1] = h
        end
    end
    if #list == 0 then
        return
    end
    local idx = 0
    for i, h in ipairs(list) do
        if h.id == U.focus then
            idx = i
        end
    end
    idx = (idx - 1 + dir) % #list + 1
    U.focus = list[idx].id
end

function U.activate_focus()
    for _, h in ipairs(U.hits) do
        if h.id == U.focus and h.action then
            U.juice(h.id)
            h.action()
            return true
        end
    end
end

return U
