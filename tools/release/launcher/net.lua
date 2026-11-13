local N = {}

N.AGENT = "BalatroOverhaulLauncher"

local THREAD = [[
require("love.filesystem")
local url, agent, channel = ...
local out = love.thread.getChannel(channel)
local ok, https = pcall(function()
    return love.filesystem.load("https.lua")()
end)
if not ok or type(https) ~= "table" then
    out:push({code = 0, err = "no https: " .. tostring(https)})
    return
end
local ok2, code, body = pcall(https.request, url, {headers = {["User-Agent"] = agent}})
if not ok2 then
    out:push({code = 0, err = tostring(code)})
elseif tonumber(code) ~= 200 then
    out:push({code = tonumber(code) or 0, err = tonumber(code) == 0 and tostring(body) or ("HTTP " .. tostring(code))})
else
    out:push({code = 200, body = body})
end
]]

local count = 0

function N.start(url)
    count = count + 1
    local channel = "launcher_net_" .. count
    love.thread.getChannel(channel):clear()
    local ok, thread = pcall(love.thread.newThread, THREAD)
    if not ok then
        return {done = {code = 0, err = tostring(thread)}}
    end
    thread:start(url, N.AGENT, channel)
    return {thread = thread, channel = channel}
end

function N.poll(job)
    if job.done then
        return job.done
    end
    local r = love.thread.getChannel(job.channel):pop()
    if r then
        job.done = r
        return r
    end
    local err = job.thread:getError()
    if err then
        job.done = {code = 0, err = err}
        return job.done
    end
end

function N.fetch(url)
    local ok, https = pcall(function()
        return love.filesystem.load("https.lua")()
    end)
    if not ok or type(https) ~= "table" then
        return {code = 0, err = "no https: " .. tostring(https)}
    end
    local ok2, code, body = pcall(https.request, url, {headers = {["User-Agent"] = N.AGENT}})
    if not ok2 then
        return {code = 0, err = tostring(code)}
    elseif tonumber(code) ~= 200 then
        return {code = tonumber(code) or 0, err = tonumber(code) == 0 and tostring(body) or ("HTTP " .. tostring(code))}
    end
    return {code = 200, body = body}
end

return N
