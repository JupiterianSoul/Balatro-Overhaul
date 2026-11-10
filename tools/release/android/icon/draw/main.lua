local function repo_path(rel)
    local base = love.filesystem.getSource():gsub("[/\\]+$", "")
    return base .. "/../../../../../" .. rel
end

local function load_icon_module()
    local path = os.getenv("ICON_LUA") or repo_path("assets/functions/app_icon.lua")
    local f = assert(io.open(path, "rb"))
    local src = f:read("*a")
    f:close()
    return assert(loadstring(src, "=app_icon.lua"))()
end

local function slurp(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
end

local function u32be(v)
    return string.char(math.floor(v / 16777216) % 256, math.floor(v / 65536) % 256, math.floor(v / 256) % 256, v % 256)
end

local function write(path, data)
    local f = assert(io.open(path, "wb"))
    f:write(data)
    f:close()
end

local function shrink(canvas, size)
    local g = love.graphics
    local src = canvas
    while src:getWidth() >= size * 2 do
        local w = math.floor(src:getWidth() / 2)
        local c = g.newCanvas(w, w)
        src:setFilter("linear", "linear")
        g.push("all")
        g.setCanvas(c)
        g.clear(0, 0, 0, 0)
        g.origin()
        g.setBlendMode("replace", "premultiplied")
        g.setColor(1, 1, 1, 1)
        g.draw(src, 0, 0, 0, 0.5)
        g.pop()
        src = c
    end
    if src:getWidth() == size then return src:newImageData() end
    local c = g.newCanvas(size, size)
    src:setFilter("linear", "linear")
    g.push("all")
    g.setCanvas(c)
    g.clear(0, 0, 0, 0)
    g.origin()
    g.setBlendMode("replace", "premultiplied")
    g.setColor(1, 1, 1, 1)
    g.draw(src, 0, 0, 0, size / src:getWidth())
    g.pop()
    return c:newImageData()
end

function love.load()
    local AI = load_icon_module()
    local out = os.getenv("OUT_DIR") or "."
    local game = os.getenv("GAME_DIR") or repo_path("assets")
    local official = os.getenv("OFFICIAL_ICON")
    local base = AI.read_from(game)
    local read = function(rel)
        if rel == AI.ORIGINAL and official then return slurp(official) end
        return base(rel)
    end
    if not read(AI.ORIGINAL) then error("no " .. AI.ORIGINAL .. " (set OFFICIAL_ICON)") end
    local big = AI.compose("launcher", read, 1024)
    assert(big, "launcher icon needs the game textures in " .. game)
    local pngs = {}
    for _, s in ipairs({16, 24, 32, 48, 64, 72, 96, 128, 144, 192, 256, 512}) do
        pngs[s] = shrink(big, s):encode("png"):getString()
    end
    write(out .. "/launcher.png", pngs[512])
    write(out .. "/launcher_256.png", pngs[256])
    local list = {}
    for _, s in ipairs({16, 24, 32, 48, 64, 128, 256}) do list[#list + 1] = {size = s, data = pngs[s]} end
    write(out .. "/launcher.ico", AI.ico(list))
    local body = ""
    for _, e in ipairs({{"ic07", 128}, {"ic08", 256}, {"ic09", 512}}) do
        body = body .. e[1] .. u32be(8 + #pngs[e[2]]) .. pngs[e[2]]
    end
    write(out .. "/launcher.icns", "icns" .. u32be(8 + #body) .. body)
    local inst = os.getenv("INSTALLER_DIR")
    if inst then
        write(inst .. "/installer.png", pngs[512])
        for _, s in ipairs({48, 72, 96, 144, 192}) do write(inst .. "/installer_" .. s .. ".png", pngs[s]) end
    end
    love.event.quit()
end
