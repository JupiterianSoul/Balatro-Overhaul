local F = {}
local base

local function save_dir()
    if base == nil then
        local ok, dir = pcall(love.filesystem.getSaveDirectory)
        base = ok and type(dir) == "string" and dir ~= "" and dir or false
    end
    return base
end

local function direct(path, data, mode)
    local dir = save_dir()
    if not dir then return false end
    local f = io.open(dir .. "/" .. path, mode)
    if not f then return false end
    local ok = f:write(data)
    f:close()
    return ok and true or false
end

function F.write(path, data)
    data = tostring(data)
    if direct(path, data, "wb") then return true end
    return love.filesystem.write(path, data)
end

function F.append(path, data)
    data = tostring(data)
    if direct(path, data, "ab") then return true end
    return love.filesystem.append(path, data)
end

return F
