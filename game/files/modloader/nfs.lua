local lfs = love.filesystem
local nfs = {}

local save_dir = (lfs.getSaveDirectory() or ""):gsub("\\", "/"):gsub("/$", "")
local cwd = save_dir
local redirects = {}

local function norm(p)
    p = tostring(p):gsub("\\", "/")
    local parts, out = {}, {}
    local abs = p:sub(1, 1) == "/"
    local drive = p:match("^(%a:)/")
    for seg in p:gmatch("[^/]+") do parts[#parts + 1] = seg end
    for _, seg in ipairs(parts) do
        if seg == ".." then
            if #out > 0 and out[#out] ~= ".." and not (drive and #out == 1) then out[#out] = nil end
        elseif seg ~= "." then
            out[#out + 1] = seg
        end
    end
    local s = table.concat(out, "/")
    if abs then s = "/" .. s end
    return s
end

local function is_abs(p)
    return p:sub(1, 1) == "/" or p:match("^%a:[/\\]") ~= nil
end

local function absolute(p)
    p = tostring(p):gsub("\\", "/")
    if is_abs(p) then return norm(p) end
    if p == "" or p == "." then return cwd end
    return norm(cwd .. "/" .. p)
end

local function redirect(abs)
    for real, target in pairs(redirects) do
        if abs == real then return target end
        if abs:sub(1, #real + 1) == real .. "/" then return target .. "/" .. abs:sub(#real + 2) end
    end
end

local function nocase(rel)
    if rel == "" or lfs.getInfo(rel) then return rel end
    local cur = ""
    for seg in rel:gmatch("[^/]+") do
        local path = cur == "" and seg or (cur .. "/" .. seg)
        if not lfs.getInfo(path) then
            local low, found = seg:lower(), nil
            for _, item in ipairs(lfs.getDirectoryItems(cur)) do
                if item:lower() == low then found = item break end
            end
            if not found then return rel end
            path = cur == "" and found or (cur .. "/" .. found)
        end
        cur = path
    end
    return cur
end

local function resolve(p)
    local abs = absolute(p)
    local r = redirect(abs)
    if r then return nocase(r) end
    if abs == save_dir then return "" end
    if abs:sub(1, #save_dir + 1) == save_dir .. "/" then return nocase(abs:sub(#save_dir + 2)) end
    return nil, abs
end

local function io_read(abs, size)
    local f = io.open(abs, "rb")
    if not f then return nil, "Could not open " .. abs end
    local s = (size and size ~= "all") and f:read(size) or f:read("*a")
    f:close()
    return s, #(s or "")
end

function nfs.read(a, b, c)
    local container, name, size
    if c ~= nil then
        container, name, size = a, b, c
    elseif b ~= nil and type(b) ~= "number" and b ~= "all" then
        container, name = a, b
    else
        name, size = a, b
    end
    if size == "all" then size = nil end
    local rel, abs = resolve(name)
    if rel then
        if container then return lfs.read(container, rel, size) end
        return lfs.read(rel, size)
    end
    local s, n = io_read(abs, size)
    if s and container == "data" then return lfs.newFileData(s, name), n end
    return s, n
end

function nfs.write(name, data, size)
    local rel = resolve(name)
    if not rel then return false, "Outside the save folder: " .. tostring(name) end
    return lfs.write(rel, data, size)
end

function nfs.append(name, data, size)
    local rel = resolve(name)
    if not rel then return false, "Outside the save folder: " .. tostring(name) end
    return lfs.append(rel, data, size)
end

function nfs.lines(name)
    local rel, abs = resolve(name)
    if rel then return lfs.lines(rel) end
    local f = io.open(abs, "rb")
    if not f then error("Could not open " .. abs) end
    return f:lines()
end

function nfs.load(name)
    local s, err = nfs.read(name)
    if not s then return nil, err end
    return loadstring(s, "@" .. name)
end

function nfs.getInfo(path, filtertype)
    local rel, abs = resolve(path)
    if rel then return lfs.getInfo(rel, filtertype) end
    local f = io.open(abs, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    if size and (filtertype == nil or filtertype == "file") then return {type = "file", size = size} end
    return nil
end

function nfs.getDirectoryItems(dir)
    local rel = resolve(dir)
    if not rel then return {} end
    return lfs.getDirectoryItems(rel)
end

function nfs.getDirectoryItemsInfo(path, filtertype)
    local rel = resolve(path)
    local items = {}
    if not rel then return items end
    for _, name in ipairs(lfs.getDirectoryItems(rel)) do
        local info = lfs.getInfo(rel == "" and name or (rel .. "/" .. name), filtertype)
        if info then
            info.name = name
            items[#items + 1] = info
        end
    end
    return items
end

function nfs.createDirectory(path)
    local rel = resolve(path)
    if not rel then return false, "Outside the save folder: " .. tostring(path) end
    if rel == "" then return true end
    return lfs.createDirectory(rel)
end

function nfs.remove(name)
    local rel = resolve(name)
    if not rel then return false, "Outside the save folder: " .. tostring(name) end
    if not lfs.getInfo(rel) then return false, "Could not remove " .. tostring(name) end
    return lfs.remove(rel)
end

function nfs.newFile(name)
    local rel = resolve(name)
    return lfs.newFile(rel or name)
end

function nfs.newFileData(filepath)
    local rel, abs = resolve(filepath)
    if rel then return lfs.newFileData(rel) end
    local s, err = io_read(abs)
    if not s then return nil, err end
    return lfs.newFileData(s, filepath)
end

function nfs.mount(archive, mount_point, append)
    local rel = resolve(archive)
    if not rel then return false end
    return lfs.mount(rel, mount_point, append)
end

function nfs.unmount(archive)
    local rel = resolve(archive)
    if not rel then return false end
    return lfs.unmount(rel)
end

function nfs.getWorkingDirectory()
    return cwd
end

function nfs.setWorkingDirectory(path)
    cwd = absolute(path)
    return true
end

function nfs.getDriveList()
    return {"/"}
end

function nfs.smodsAddRedirect(real_path, lfs_path)
    real_path = absolute(real_path)
    if redirects[real_path] then return false, 'A redirect with path "' .. real_path .. '" already exists' end
    redirects[real_path] = lfs_path
    return true
end

function nfs.getNormalizedPath(path)
    if nfs.getInfo(path) then return path end
    path = path:gsub("\\", "/"):gsub("/$", "")
    local parent = path:gsub("/[^/]*$", "")
    if parent == path or parent == "" then return path end
    parent = nfs.getNormalizedPath(parent)
    for _, v in ipairs(nfs.getDirectoryItems(parent)) do
        if (parent .. "/" .. v):lower() == path:lower() then return parent .. "/" .. v end
    end
    return path
end

nfs.resolve = resolve

return nfs
