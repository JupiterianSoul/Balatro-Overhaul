local C = require("core")
local I = require("overhaul_install")
local has_json, json = pcall(require, "json")

local P = {}

P.FORMAT = 2

local THREAD = [[
require("love.filesystem")
local url, notes, agent, channel = ...
local out = love.thread.getChannel(channel)
local ok, https = pcall(function()
    return love.filesystem.load("https.lua")()
end)
if not ok or type(https) ~= "table" then
    out:push({code = 0, err = "no https: " .. tostring(https)})
    return
end
local function get(u)
    local ok2, code, body = pcall(https.request, u, {headers = {["User-Agent"] = agent}})
    if not ok2 then
        return 0, tostring(code)
    end
    return tonumber(code) or 0, body
end
local code, body = get(url)
if code ~= 200 then
    out:push({code = code, err = code == 0 and tostring(body) or ("HTTP " .. tostring(code))})
    return
end
local r = {code = 200, body = body}
if notes ~= "" then
    local c2, b2 = get(notes)
    if c2 == 200 then
        r.notes = b2
    end
end
out:push(r)
]]

local count = 0

function P.url()
    local e = os.getenv("OVERHAUL_FEED")
    if e and e ~= "" then
        return e
    end
    return C.SERVER .. "/version?platform=" .. I.feed() .. "&link=1"
end

function P.notes_url()
    local e = os.getenv("OVERHAUL_NOTES_FEED")
    if e then
        return e
    end
    local feed = os.getenv("OVERHAUL_FEED")
    if feed and feed ~= "" then
        local origin = feed:match("^(%a[%w+.-]*://[^/]+)")
        return origin and (origin .. "/release/feed.json") or ""
    end
    return C.NOTES_URL
end

function P.enabled()
    return os.getenv("OVERHAUL_NO_UPDATE_CHECK") ~= "1" and P.url() ~= ""
end

function P.start()
    count = count + 1
    local channel = "phone_feed_" .. count
    love.thread.getChannel(channel):clear()
    local ok, thread = pcall(love.thread.newThread, THREAD)
    if not ok then
        return {done = {code = 0, err = tostring(thread)}}
    end
    thread:start(P.url(), P.notes_url(), require("net").AGENT, channel)
    return {thread = thread, channel = channel}
end

P.newer = I.newer

local function decode(body)
    if not has_json then
        return nil
    end
    local ok, data = pcall(json.decode, body or "")
    return ok and type(data) == "table" and data or nil
end

function P.parse(body, notes)
    local data = decode(body)
    if not data then
        return nil, "bad_feed"
    end
    local b = data.build
    if type(b) ~= "table" then
        return nil, "no_build"
    end
    if b.version == nil or type(b.url) ~= "string" or type(b.sha256) ~= "string" or not tonumber(b.size) then
        return nil, "bad_feed"
    end
    local e = {
        version = tostring(b.version),
        name = type(b.name) == "string" and b.name ~= "" and b.name or nil,
        url = b.url,
        size = tonumber(b.size),
        sha256 = b.sha256:lower(),
        patch_format = 1,
    }
    local n = decode(notes)
    local l = n and n.latest
    if type(l) == "table" and tostring(l.version) == e.version then
        e.changelog = l.changelog
        e.name = e.name or (type(l.name) == "string" and l.name ~= "" and l.name or nil)
        e.page = type(n.page) == "string" and n.page or nil
    end
    return e
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
    return "new"
end

function P.result(r)
    if not r or r.code ~= 200 then
        return nil, r and r.err or "offline"
    end
    return P.parse(r.body, r.notes)
end

function P.restore()
    return false
end

local function fetch(url, wait)
    local net = require("net")
    if not wait then
        return net.fetch(url)
    end
    local job = net.start(url)
    local r
    repeat
        wait()
        r = net.poll(job)
    until r
    return r
end

function P.download(e, wait)
    local fresh = P.result(fetch(P.url(), wait))
    if fresh and fresh.version == e.version then
        fresh.changelog, fresh.page = e.changelog, e.page
        e = fresh
    end
    local r = fetch(e.url, wait)
    if r.code ~= 200 then
        return nil, {code = "download", detail = r.err}
    end
    local body = r.body
    r = nil
    if type(body) ~= "string" or #body ~= e.size or C.sha256(body) ~= e.sha256 then
        return nil, {code = "damaged"}
    end
    I.drop_update()
    love.filesystem.createDirectory("update")
    if not love.filesystem.write(I.UPDATE, body) then
        return nil, {code = "write", file = I.UPDATE}
    end
    love.filesystem.write(I.UPDATE_SUM, e.sha256 .. "  patch.zip\n")
    return e
end

function P.update(e, path, progress, wait)
    progress("downloading")
    local got, err = P.download(e, wait)
    collectgarbage()
    if not got then
        return nil, err
    end
    local res, ierr = C.install(path, progress)
    if not res and type(ierr) == "table" then
        ierr.overhaul = got.name or got.version
    end
    return res, ierr
end

return P
