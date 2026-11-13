local M = {}

M.BUILD = 2
M.DIR = "launcher_code"
M.STATE = M.DIR .. "/state.txt"
M.MAX_TRIES = 2
M.PROBE = "launcher_code_probe"

local function sha(s)
    return love.data.encode("string", "hex", love.data.hash("sha256", s))
end

local function read_state()
    local s = love.filesystem.read(M.STATE)
    local build, hash, file, tries = (s or ""):match("^(%d+)\n(%x+)\n([^\n]+)\n(%d+)")
    if not build then
        return nil
    end
    return {build = tonumber(build), sha256 = hash, file = file, tries = tonumber(tries)}
end

local function write_state(st)
    if not st then
        love.filesystem.remove(M.STATE)
        return true
    end
    love.filesystem.createDirectory(M.DIR)
    return love.filesystem.write(M.STATE, string.format("%d\n%s\n%s\n%d\n", st.build, st.sha256, st.file, st.tries or 0))
end

local function clean(keep)
    for _, name in ipairs(love.filesystem.getDirectoryItems(M.DIR)) do
        local p = M.DIR .. "/" .. name
        if p ~= keep and p ~= M.STATE then
            love.filesystem.remove(p)
        end
    end
end

function M.zip_build(file, prefix)
    if not love.filesystem.mount(file, M.PROBE) then
        return nil
    end
    local src = love.filesystem.read(M.PROBE .. "/" .. (prefix or "") .. "lcode.lua")
    love.filesystem.unmount(file)
    return src and tonumber(src:match("\nM%.BUILD = (%d+)\n")) or nil
end

function M.boot(prefix, extra)
    local info = {bundled = M.BUILD, build = M.BUILD, prefix = prefix or ""}
    for k, v in pairs(extra or {}) do
        info[k] = v
    end
    rawset(_G, "LAUNCHER_CODE", info)
    local st = read_state()
    if not st then
        clean()
        return info
    end
    local ok = st.build > M.BUILD and st.tries < M.MAX_TRIES
    local data = ok and love.filesystem.read(st.file)
    ok = data and sha(data) == st.sha256
    data = nil
    ok = ok and M.zip_build(st.file, info.prefix) == st.build
    if not ok then
        info.dropped = st.build
        write_state(nil)
        clean()
        return info
    end
    st.tries = st.tries + 1
    write_state(st)
    clean(st.file)
    if not love.filesystem.mount(st.file, "", false) then
        info.dropped = st.build
        write_state(nil)
        return info
    end
    info.build, info.file = st.build, st.file
    return info
end

function M.info()
    return rawget(_G, "LAUNCHER_CODE") or {bundled = M.BUILD, build = M.BUILD, prefix = ""}
end

function M.started()
    local st = read_state()
    if st and st.tries > 0 and st.build == M.info().build then
        st.tries = 0
        write_state(st)
    end
end

function M.staged()
    local st = read_state()
    if st and st.build > M.info().build then
        return st.build
    end
    return nil
end

function M.wanted(e)
    if type(e) ~= "table" or not tonumber(e.build) then
        return nil
    end
    local have = math.max(M.info().build, M.staged() or 0)
    if tonumber(e.build) <= have then
        return nil
    end
    return e
end

function M.accept(e, body)
    if type(body) ~= "string" or #body ~= e.size or sha(body) ~= e.sha256 then
        return nil, "damaged"
    end
    love.filesystem.createDirectory(M.DIR)
    local file = M.DIR .. "/launcher-code-" .. e.build .. ".zip"
    if file == M.info().file then
        return nil, "write"
    end
    if not love.filesystem.write(file, body) or sha(love.filesystem.read(file) or "") ~= e.sha256 then
        love.filesystem.remove(file)
        return nil, "write"
    end
    if M.zip_build(file, M.info().prefix) ~= e.build then
        love.filesystem.remove(file)
        return nil, "bad"
    end
    if not write_state({build = e.build, sha256 = e.sha256, file = file, tries = 0}) then
        love.filesystem.remove(file)
        return nil, "write"
    end
    return e.build
end

function M.parse(raw, resolve)
    if type(raw) ~= "table" then
        return nil
    end
    local build, size = tonumber(raw.build), tonumber(raw.size)
    if not build or build ~= math.floor(build) or not size or type(raw.url) ~= "string" or type(raw.sha256) ~= "string" then
        return nil
    end
    return {build = build, url = resolve and resolve(raw.url) or raw.url, size = size, sha256 = raw.sha256:lower()}
end

return M
