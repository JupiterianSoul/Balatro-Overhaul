local X = {}

local OWN_BG = [[
extern number time;
extern vec4 colour_1;
extern vec4 colour_2;
extern vec4 colour_3;
extern number contrast;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    float px = length(love_ScreenSize.xy) / 700.0;
    vec2 uv = (floor(sc / px) * px - 0.5 * love_ScreenSize.xy) / length(love_ScreenSize.xy);
    float r = length(uv);
    float a = atan(uv.y, uv.x) + 3.0 * r - time * 0.05;
    vec2 p = vec2(cos(a), sin(a)) * r * 9.0;
    for (int i = 0; i < 4; i++) {
        p += 0.6 * vec2(sin(p.y * 1.3 + time * 0.21), cos(p.x * 1.1 - time * 0.17));
    }
    float w = 0.5 + 0.5 * sin(p.x + p.y);
    float k = smoothstep(0.3, 0.7, w);
    vec3 c = mix(colour_2.rgb, colour_1.rgb, k);
    c = mix(c, colour_3.rgb, clamp(0.15 + 0.25 * r, 0.0, 0.6) / contrast);
    return vec4(c, 1.0) * color;
}
]]

local OWN_CRT = [[
extern number time;
extern number crt_intensity;
extern number scanlines;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
    vec2 cc = tc - 0.5;
    float d = dot(cc, cc);
    vec2 uv = 0.5 + cc * (1.0 + d * 0.06 * crt_intensity / 0.112);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return vec4(0.0, 0.0, 0.0, 1.0);
    }
    float ca = 0.0012 * crt_intensity / 0.112;
    vec4 c = Texel(tex, uv);
    c.r = Texel(tex, uv + vec2(ca, 0.0)).r;
    c.b = Texel(tex, uv - vec2(ca, 0.0)).b;
    float line = 0.5 + 0.5 * sin(uv.y * scanlines * 3.14159);
    c.rgb *= 1.0 - crt_intensity * 0.6 * (1.0 - line);
    float vig = smoothstep(0.75, 0.25, length(cc * vec2(1.0, 1.15)));
    c.rgb *= mix(0.72, 1.0, vig);
    return vec4(c.rgb, 1.0) * color;
}
]]

local SOUNDS = {"button", "cancel", "card1", "paper1", "highlight1", "whoosh"}

X.borrowed = false
X.sounds = {}
X.crt_on = true
X.mute = false

local function rgb(h)
    return {tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255, 1}
end

X.colours = {rgb("FE5F55"), rgb("009DFF"), {0.13, 0.16, 0.17, 1}}

local function shader(src)
    if not src then
        return nil
    end
    local ok, sh = pcall(love.graphics.newShader, src)
    if ok then
        return sh
    end
    print("launcher: shader: " .. tostring(sh))
end

local function send(sh, name, ...)
    pcall(sh.send, sh, name, ...)
end

function X.init()
    X.bg = shader(OWN_BG)
    X.crt = shader(OWN_CRT)
    X.own_crt = true
    X.time = 0
end

local function image(z, name)
    local data = z:read(name)
    if not data then
        return nil
    end
    local ok, img = pcall(function()
        return love.graphics.newImage(love.image.newImageData(love.filesystem.newFileData(data, name)))
    end)
    if ok then
        img:setFilter("linear", "linear")
        return img
    end
end

function X.borrow(z, U)
    if X.borrowed or not z then
        return
    end
    X.borrowed = true
    local font = z:read("resources/fonts/m6x11plus.ttf")
    if font then
        U.set_font_data(love.filesystem.newFileData(font, "m6x11plus.ttf"))
    end
    local bg = shader(z:read("resources/shaders/background.fs"))
    if bg then
        X.bg = bg
    end
    local crt = shader(z:read("resources/shaders/CRT.fs"))
    if crt then
        X.crt, X.own_crt = crt, false
    end
    X.jokers = image(z, "resources/textures/2x/Jokers.png")
    if X.jokers then
        X.joker_quad = love.graphics.newQuad(0, 0, 142, 190, X.jokers:getDimensions())
    end
    X.backs = image(z, "resources/textures/2x/Enhancers.png")
    if X.backs then
        X.back_quad = love.graphics.newQuad(0, 0, 142, 190, X.backs:getDimensions())
    end
    if love.audio and love.sound then
        for _, name in ipairs(SOUNDS) do
            local data = z:read("resources/sounds/" .. name .. ".ogg")
            if data then
                local ok, src = pcall(function()
                    local sd = love.sound.newSoundData(love.filesystem.newFileData(data, name .. ".ogg"))
                    return love.audio.newSource(sd, "static")
                end)
                if ok and src then
                    X.sounds[name] = src
                end
            end
        end
    end
end

function X.play(name, pitch, vol)
    if X.mute then
        return
    end
    local s = X.sounds[name]
    if not s then
        return
    end
    pcall(function()
        local c = s:clone()
        c:setPitch((pitch or 1) * (0.97 + math.random() * 0.06))
        c:setVolume((vol or 1) * 0.5)
        c:play()
    end)
end

function X.update(dt)
    X.time = X.time + dt
end

local canvas

local function ensure_canvas(w, h)
    if not canvas or canvas:getWidth() ~= w or canvas:getHeight() ~= h then
        if canvas then
            canvas:release()
        end
        canvas = love.graphics.newCanvas(w, h)
        canvas:setFilter("linear", "linear")
    end
    return canvas
end

function X.background(w, h)
    if X.bg then
        local c = X.colours
        send(X.bg, "time", X.time)
        send(X.bg, "spin_time", X.time * 0.1)
        send(X.bg, "colour_1", c[1])
        send(X.bg, "colour_2", c[2])
        send(X.bg, "colour_3", c[3])
        send(X.bg, "contrast", 1)
        send(X.bg, "spin_amount", 0)
        love.graphics.setShader(X.bg)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, w, h)
        love.graphics.setShader(nil)
    else
        love.graphics.clear(0.13, 0.16, 0.17, 1)
    end
end

function X.frame(w, h, draw)
    if not X.crt_on or not X.crt then
        draw()
        return
    end
    local cv = ensure_canvas(w, h)
    love.graphics.push("all")
    love.graphics.setCanvas(cv)
    love.graphics.clear(0, 0, 0, 1)
    draw()
    love.graphics.pop()
    local sh = X.crt
    local crt = h > w and 22 or 60
    send(sh, "distortion_fac", {1.0 + 0.07 * crt / 100, 1.0 + 0.1 * crt / 100})
    send(sh, "scale_fac", {1.0 - 0.008 * crt / 100, 1.0 - 0.008 * crt / 100})
    send(sh, "feather_fac", 0.01)
    send(sh, "bloom_fac", 0)
    send(sh, "time", 400 + X.time)
    send(sh, "crt_intensity", 0.16 * crt / 100)
    send(sh, "glitch_intensity", 0)
    send(sh, "scanlines", h * 0.75 * (love.graphics.getDPIScale and love.graphics.getDPIScale() or 1))
    local mx, my = love.mouse.getPosition()
    send(sh, "mouse_screen_pos", {mx, my})
    send(sh, "screen_scale", math.min(w, h) / 10)
    send(sh, "hovering", 1)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setShader(sh)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(cv, 0, 0)
    love.graphics.setShader(nil)
    X.crt_frames = (X.crt_frames or 0) + 1
    if X.crt_frames == 30 and not X.crt_checked and love.graphics.captureScreenshot then
        X.crt_checked = true
        pcall(love.graphics.captureScreenshot, function(img)
            local share = X.black_share(function(x, y) return img:getPixel(x, y) end, img:getWidth(), img:getHeight())
            print(string.format("launcher: crt check, black %.2f", share))
            if share > 0.35 then
                X.crt_on = false
                if X.on_crt_broken then X.on_crt_broken() end
            end
        end)
    end
end

function X.black_share(get, w, h)
    local black, total = 0, 0
    for i = 1, 24 do
        for j = 1, 12 do
            local x = math.floor((i - 0.5) / 24 * w)
            local y = math.floor((j - 0.5) / 12 * h)
            local r, g, b = get(x, y)
            total = total + 1
            if r + g + b < 0.04 then black = black + 1 end
        end
    end
    return total > 0 and black / total or 0
end

return X
