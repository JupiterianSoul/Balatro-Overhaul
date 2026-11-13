local cfg = require("multiplayer.mp_config")
local url = os.getenv("MP_TEST_URL")
if url and url ~= "" then
    cfg.SERVER_URL = url
end
cfg.CONNECT_TIMEOUT = tonumber(os.getenv("MP_TEST_CONNECT_TIMEOUT") or "") or 20
local lvl = os.getenv("MP_TEST_LOG_LEVEL")
if lvl and lvl ~= "" then
    cfg.LOG_LEVEL = lvl
end

require("game_main")
love.system.openURL = function() return true end
if os.getenv("MP_TEST_PADS") ~= "1" then
    for _, name in ipairs({"gamepadpressed", "gamepadreleased", "gamepadaxis", "joystickpressed", "joystickreleased", "joystickaxis", "joystickhat"}) do
        local orig = love[name]
        if orig then
            love[name] = function(joystick, ...)
                if type(joystick) == "userdata" then return end
                return orig(joystick, ...)
            end
        end
    end
end
if os.getenv("MP_TEST_PHONE") == "1" then _G._IS_DESKTOP = false end
require("turbo").install()
pcall(love.audio.setVolume, 0)
local load_ref = love.load
love.load = function(...)
    local r = load_ref(...)
    pcall(love.audio.setVolume, 0)
    return r
end
require("mp_test_driver")
local rotate_every = tonumber(os.getenv("MP_TEST_ROTATE_EVERY") or "")
if rotate_every and rotate_every > 0 then
    local upd = love.update
    local next_turn, turns = nil, 0
    love.update = function(dt)
        upd(dt)
        if not (G and G.STAGE == G.STAGES.RUN and G.window_prev) then return end
        local t = love.timer.getTime()
        next_turn = next_turn or t + rotate_every
        if t < next_turn then return end
        next_turn = t + rotate_every
        local w, h = love.graphics.getDimensions()
        love.window.updateMode(h, w, {fullscreen = false, resizable = true})
        love.resize(love.graphics.getDimensions())
        turns = turns + 1
        print(string.format("[mp_test] rotate %d %dx%d to %dx%d portrait=%s state=%s", turns, w, h, love.graphics.getWidth(), love.graphics.getHeight(), tostring(PORTRAIT and PORTRAIT.on()), tostring(G.STATE)))
    end
end
