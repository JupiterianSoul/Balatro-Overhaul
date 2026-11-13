local M = {}

M.ROOT = "mods"
M.SAFE = "safe_start.txt"

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function is_dir(fs, path)
    local info = fs.getInfo(path)
    return info ~= nil and info.type == "directory"
end

local function is_fork(fs, dir)
    return fs.getInfo(dir .. "/src/preflight/loader.lua", "file") ~= nil
end

local function read_enabled(fs)
    local list, set = {}, {}
    local data = fs.read(M.ROOT .. "/enabled.txt")
    for line in (data or ""):gmatch("[^\r\n]+") do
        line = trim(line)
        if line ~= "" and line:sub(1, 1) ~= "#" and not set[line] then
            set[line] = true
            list[#list + 1] = line
        end
    end
    return list, set
end

local function write_enabled(fs, list)
    fs.createDirectory(M.ROOT)
    return fs.write(M.ROOT .. "/enabled.txt", table.concat(list, "\n") .. (#list > 0 and "\n" or ""))
end

local function mod_name(fs, dir, fallback)
    for _, item in ipairs(fs.getDirectoryItems(dir)) do
        if item:lower():match("%.json$") and item:sub(1, 1) ~= "." then
            local text = fs.read(dir .. "/" .. item)
            local name = text and (text:match('"name"%s*:%s*"([^"]+)"') or text:match("'name'%s*:%s*'([^']+)'"))
            if name and name ~= "" then
                return name
            end
        end
    end
    return fallback
end

function M.list(fs)
    local _, set = read_enabled(fs)
    local out = {}
    for _, name in ipairs(fs.getDirectoryItems(M.ROOT)) do
        local dir = M.ROOT .. "/" .. name
        if name:sub(1, 1) ~= "." and name ~= "lovely" and is_dir(fs, dir) and not is_fork(fs, dir) then
            out[#out + 1] = {folder = name, name = mod_name(fs, dir, name), enabled = set[name] == true}
        end
    end
    table.sort(out, function(a, b)
        return a.name:lower() < b.name:lower()
    end)
    return out
end

function M.modded(fs)
    local data = fs.read(M.ROOT .. "/session.txt") or ""
    return data:match("^[^\r\n]*") == "modded"
end

function M.set_enabled(fs, name, on)
    if not name or name == "" or name:find("[/\\]") or name:sub(1, 1) == "." then
        return false
    end
    local dir = M.ROOT .. "/" .. name
    if not is_dir(fs, dir) then
        return false
    end
    local list, set = read_enabled(fs)
    if on and not set[name] then
        list[#list + 1] = name
    elseif not on and set[name] then
        for i = #list, 1, -1 do
            if list[i] == name then
                table.remove(list, i)
            end
        end
    end
    write_enabled(fs, list)
    local ignore = dir .. "/.lovelyignore"
    if on then
        fs.remove(ignore)
    else
        fs.write(ignore, "")
    end
    return true
end

local function remove_tree(fs, path)
    local info = fs.getInfo(path)
    if not info then
        return
    end
    if info.type == "directory" then
        for _, item in ipairs(fs.getDirectoryItems(path)) do
            remove_tree(fs, path .. "/" .. item)
        end
    end
    fs.remove(path)
end

function M.remove(fs, name)
    if not name or name == "" or name:find("[/\\]") or name:sub(1, 1) == "." or name == "lovely" then
        return false
    end
    local dir = M.ROOT .. "/" .. name
    if not is_dir(fs, dir) then
        return false
    end
    M.set_enabled(fs, name, false)
    remove_tree(fs, dir)
    return fs.getInfo(dir) == nil
end

function M.safe_start(fs)
    return fs.write(M.SAFE, "requested") == true
end

function M.trouble(fs)
    local running = fs.read(M.ROOT .. "/.running.txt")
    return fs.getInfo(M.ROOT .. "/.crash.txt") ~= nil
        or fs.getInfo(M.ROOT .. "/.boot_crashes.txt") ~= nil
        or (running ~= nil and running ~= "" and not running:find("\ntitle", 1, true))
end

function M.safe_pending(fs)
    return fs.getInfo(M.SAFE, "file") ~= nil
end

return M
