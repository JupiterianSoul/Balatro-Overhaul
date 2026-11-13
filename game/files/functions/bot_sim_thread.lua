require("love.filesystem")
require "love.timer"

local REQ = love.thread.getChannel("bot_sim_req")
local RES = love.thread.getChannel("bot_sim_res")

local function lf_loader(name)
    local path = name:gsub("%.", "/") .. ".lua"
    if not love.filesystem.getInfo(path) then return "\n\tno file '" .. path .. "' in the game files" end
    local chunk, err = love.filesystem.load(path)
    if not chunk then error(err) end
    return chunk
end
local loaders = package.loaders
table.insert(loaders, 2, lf_loader)

local json = require("bot.sim.json")
local C = require("bot.ingame.core")

local core

local function handle(m)
    local r = {id = m.id, cmd = m.cmd}
    local t0 = love.timer.getTime()
    if m.cmd == "new" then
        if m.noffi then
            local BUF = require("bot.nn.buf")
            BUF.set_ffi(false)
        end
        core = C.new(m.kind, m.setup, m.budget)
        r.ok = true
        r.snap = core:snap()
        r.weights = (m.kind == "w14" or m.kind == "fair") and C.WEIGHTS_NAME or nil
    elseif not core then
        r.ok = false
        r.err = "no run"
    elseif m.cmd == "step" then
        r.ok = core:step(m.action)
        if r.ok then r.snap = core:snap() else r.err = "sim refused the action" end
    elseif m.cmd == "decide" then
        if m.budget then core:set_budget(m.budget) end
        local a, why, think = core:decide()
        r.ok = a ~= nil
        r.action = a
        r.why = why
        r.think = think
    end
    r.secs = love.timer.getTime() - t0
    return r
end

while true do
    local raw = REQ:demand()
    if raw == "quit" then break end
    local okd, m = pcall(json.decode, raw)
    local r
    if not okd or type(m) ~= "table" then
        r = {ok = false, err = "bad message"}
    else
        local ok, res = pcall(handle, m)
        if ok then r = res else
            r = {id = m.id, cmd = m.cmd, ok = false, err = tostring(res)}
            if m.cmd == "new" then core = nil end
        end
    end
    RES:push(json.encode(r))
end
