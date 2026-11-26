local LR = {}

local function lang_path(lang)
    return "localization/" .. tostring(lang) .. ".lua"
end

local function loads(path)
    local src = love.filesystem.read(path)
    if type(src) ~= "string" then return false end
    return loadstring(src) ~= nil
end

function LR.repair(lang)
    local path = lang_path(lang)
    if not love.filesystem.getInfo(path) or loads(path) then return false end
    local real = love.filesystem.getRealDirectory and love.filesystem.getRealDirectory(path)
    if real and real == love.filesystem.getSaveDirectory() then
        love.filesystem.remove(path)
        print("[LOC] removed a broken copy of " .. path .. " from the save folder")
        if loads(path) then return true end
    end
    if lang == "en-us" then return false end
    print("[LOC] " .. path .. " is broken, falling back to English")
    G.SETTINGS.language = "en-us"
    return true
end

local set_language = Game and Game.set_language
if set_language and not LR.wrapped then
    LR.wrapped = true
    function Game:set_language(...)
        local res = {n = select("#", ...) + 1, pcall(set_language, self, ...)}
        if res[1] then return unpack(res, 2, res.n) end
        if not LR.repair(G and G.SETTINGS and G.SETTINGS.language) then error(res[2], 0) end
        return set_language(self, ...)
    end
end

LOC_RESCUE = LR
return LR
