local Hooks = require("overhaul.hooks")

local M = {HOLD = 0.5}

local base = Controller.queue_R_cursor_press
local function guarded(self, x, y)
    if M.synthetic then return end
    return base(self, x, y)
end
Controller.queue_R_cursor_press = guarded

function M.mods_listen()
    return Controller.queue_R_cursor_press ~= guarded
end

local function right_press(c, x, y)
    M.synthetic = true
    local ok, err = pcall(c.queue_R_cursor_press, c, x, y)
    M.synthetic = false
    if not ok then print("[touch_mouse] right click: " .. tostring(err)) end
end

local function right_release(c, x, y)
    if type(c.R_cursor_release) ~= "function" then return end
    local ok, err = pcall(c.R_cursor_release, c, x, y)
    if not ok then print("[touch_mouse] right release: " .. tostring(err)) end
end

function M.update(c)
    local down = c.cursor_down
    if M.fired and not (c.is_cursor_down and down.time == M.fired) then
        M.fired = nil
        right_release(c, M.x, M.y)
    end
    if not (c.HID and c.HID.touch and c.is_cursor_down and down.time and down.duration) then return end
    if M.fired or M.done == down.time then return end
    if down.duration < M.HOLD then return end
    M.done = down.time
    if (down.distance or 0) >= G.MIN_CLICK_DIST or not M.mods_listen() then return end
    M.fired, M.x, M.y = down.time, c.cursor_position.x, c.cursor_position.y
    right_press(c, M.x, M.y)
end

local function update_after(self, ...)
    if self == G.CONTROLLER then M.update(self) end
    return ...
end

Hooks.wrap(Controller, "update", function(orig) return function(self, ...)
    return update_after(self, orig(self, ...))
end end, {id = "overhaul.touch_mouse"})

return M
