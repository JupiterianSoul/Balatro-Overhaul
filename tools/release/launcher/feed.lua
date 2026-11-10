local A = require("patcher.apply")
local C = require("core")
local has_json, json = pcall(require, "json")

local P = {}

P.FORMAT = 2
P.DIR = "updates"

function P.url()
    local e = os.getenv("OVERHAUL_FEED")
    if e and e ~= "" then
        return e
    end
    return C.FEED_URL
end

function P.enabled()
    return os.getenv("OVERHAUL_NO_UPDATE_CHECK") ~= "1" and P.url() ~= ""
end

function P.newer(a, b)
    local pa, pb = {}, {}
    for n in tostring(a):gmatch("%d+") do
        pa[#pa + 1] = tonumber(n)
    end
    for n in tostring(b):gmatch("%d+") do
        pb[#pb + 1] = tonumber(n)
    end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then
            return x > y
        end
    end
    return false
end

local function resolve(base, url)
    if url:match("^%a[%w+.-]*://") then
        return url
    end
    if url:sub(1, 1) == "/" then
        return (base:match("^(%a[%w+.-]*://[^/]+)") or "") .. url
    end
    return (base:gsub("[?#].*$", ""):match("^(.*/)") or "") .. url
end

function P.parse(body, base)
    if not has_json then
        return nil, "no json"
    end
    local ok, data = pcall(json.decode, body or "")
    if not ok or type(data) ~= "table" or tonumber(data.format) ~= 1 or type(data.latest) ~= "table" then
        return nil, "bad_feed"
    end
    local l = data.latest
    if type(l.version) ~= "string" or type(l.url) ~= "string" or type(l.sha256) ~= "string" or not tonumber(l.size) then
        return nil, "bad_feed"
    end
    return {
        version = l.version,
        name = type(l.name) == "string" and l.name ~= "" and l.name or nil,
        game_version = type(l.game_version) == "string" and l.game_version or nil,
        url = resolve(base, l.url),
        size = tonumber(l.size),
        sha256 = l.sha256:lower(),
        patch_format = tonumber(l.patch_format) or 1,
        changelog = l.changelog,
        page = type(data.page) == "string" and data.page or nil,
    }
end

function P.changelog(e, lang)
    local c = e and e.changelog
    if type(c) == "table" then
        c = c[lang] or c.en
    end
    if type(c) ~= "string" or c == "" then
        return nil
    end
    return c
end

function P.status(e)
    if not e then
        return "offline"
    end
    local m = C.manifest()
    if not P.newer(e.version, m and m.overhaul_version or "0") then
        return "latest"
    end
    if e.patch_format > P.FORMAT then
        return "launcher"
    end
    return "new"
end

function P.result(r)
    if not r or r.code ~= 200 then
        return nil, r and r.err or "offline"
    end
    return P.parse(r.body, P.url())
end

local function safe(v)
    return (tostring(v):gsub("[^%w%.%-]", "_"))
end

function P.mount(file, version)
    local root = "patchset_" .. safe(version)
    if not love.filesystem.mount(file, root) then
        return nil, "bad"
    end
    local m = A.load_manifest(love.filesystem.read(root .. "/manifest.lua"))
    if not m or m.overhaul_version ~= version then
        love.filesystem.unmount(file)
        return nil, "bad"
    end
    return root, m
end

function P.accept(e, body)
    if type(body) ~= "string" or #body ~= e.size or C.sha256(body) ~= e.sha256 then
        return nil, "damaged"
    end
    love.filesystem.createDirectory(P.DIR)
    local file = P.DIR .. "/patchset-" .. safe(e.version) .. ".zip"
    if not love.filesystem.write(file, body) then
        return nil, "write"
    end
    local root, err = P.mount(file, e.version)
    if not root then
        love.filesystem.remove(file)
        return nil, err
    end
    return {file = file, root = root, version = e.version, sha256 = e.sha256}
end

function P.commit(acc)
    C.settings().patchset = {file = acc.file, version = acc.version, sha256 = acc.sha256}
    C.save_settings()
    for _, name in ipairs(love.filesystem.getDirectoryItems(P.DIR)) do
        local p = P.DIR .. "/" .. name
        if p ~= acc.file then
            love.filesystem.unmount(p)
            love.filesystem.remove(p)
        end
    end
end

function P.revert(acc, root)
    C.use_root(root)
    love.filesystem.unmount(acc.file)
    love.filesystem.remove(acc.file)
end

function P.restore()
    local saved = C.settings().patchset
    if type(saved) ~= "table" or type(saved.file) ~= "string" then
        return false
    end
    local bundled = C.manifest()
    local data = love.filesystem.read(saved.file)
    if not data or C.sha256(data) ~= saved.sha256 or (bundled and not P.newer(saved.version, bundled.overhaul_version)) then
        return false
    end
    data = nil
    local root = P.mount(saved.file, saved.version)
    if not root then
        return false
    end
    C.use_root(root)
    return true
end

function P.download(e, wait)
    local net = require("net")
    local r
    if wait then
        local job = net.start(e.url)
        repeat
            wait()
            r = net.poll(job)
        until r
    else
        r = net.fetch(e.url)
    end
    if r.code ~= 200 then
        return nil, {code = "download", detail = r.err}
    end
    local acc, err = P.accept(e, r.body)
    if not acc then
        return nil, {code = err}
    end
    return acc
end

function P.update(e, path, progress, wait)
    progress("downloading")
    local acc, err = P.download(e, wait)
    if not acc then
        return nil, err
    end
    collectgarbage()
    local old = C.root
    C.use_root(acc.root)
    local res, ierr = C.install(path, progress)
    if not res then
        P.revert(acc, old)
        if type(ierr) == "table" then
            ierr.overhaul = e.name or e.version
        end
        return nil, ierr
    end
    P.commit(acc)
    return res
end

return P
