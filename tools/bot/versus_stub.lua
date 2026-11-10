local cfg = require("multiplayer.mp_config")
local url = os.getenv("MP_TEST_URL")
if url and url ~= "" then cfg.SERVER_URL = url end
cfg.CONNECT_TIMEOUT = 20

local OUT = os.getenv("BOT_OUT") or "."
local SHARED = os.getenv("MP_TEST_SHARED") or "."
local logf = io.open(OUT .. "/bot_versus.log", "w")
local function log(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    logf:write(string.format("[%7.1f] %s\n", love.timer.getTime(), table.concat(parts, " ")))
    logf:flush()
end

require("game_main")
require("turbo").install()
pcall(love.audio.setVolume, 0)

local errors = 0
local seen = {}
local function record(kind, msg)
    errors = errors + 1
    local first = tostring(msg):match("^[^\n]*")
    if seen[kind .. first] then return end
    seen[kind .. first] = true
    log("ERROR", kind, "\n" .. tostring(msg))
end

love.errorhandler = function(msg)
    record("FATAL", debug.traceback(tostring(msg), 2))
    log("FATAL_EXIT")
    return nil
end

local wrote_barrier = false
local last_stage
local game_update = love.update
love.update = function(dt)
    local ok, err = xpcall(game_update, debug.traceback, dt)
    if not ok then record("UPDATE", err) end
    if BOT.last_error then record("BOT", BOT.last_error) BOT.last_error = nil end
    if not BOT.versus_hooked then
        BOT.versus_hooked = true
        local prev = BOT.on_note
        BOT.on_note = function(kind, text)
            if kind ~= "act" or os.getenv("BOT_VERBOSE") == "1" then log("BOT", kind, text) end
            if prev then prev(kind, text) end
        end
    end
    local V = BOT.versus
    if V.stage ~= last_stage then
        last_stage = V.stage
        log("STAGE", tostring(V.stage), "phase=" .. tostring(bom_match and bom_match.get_phase()))
    end
    if not wrote_barrier and bom_match and bom_match.get_phase() == "lobby" then
        wrote_barrier = true
        local f = io.open(SHARED .. "/barrier_lobby_guest", "w")
        if f then f:write("1") f:close() end
        log("BARRIER lobby")
    end
end

local _quit = love.event.quit
love.event.quit = function(...)
    local s = BOT.stats or {}
    local types = {}
    for k, v in pairs(s.by_type or {}) do types[#types + 1] = k .. "=" .. v end
    table.sort(types)
    log("QUIT", "matches=" .. tostring(BOT.versus.matches), "actions=" .. tostring(s.actions), "refused=" .. tostring(s.refused),
        "best_ante=" .. tostring(s.best_ante), "errors=" .. errors, "types=" .. table.concat(types, ","))
    return _quit(...)
end
log("VERSUS_STUB_READY code=" .. tostring(os.getenv("BOT_VERSUS_CODE")))
