local C = Controls
local T = {}

T.HOLD = 1.4
T.SCALE = 0.6
T.OFFSET_Y = -2.8

function T.clear()
    local t = T.cur
    T.cur = nil
    if t and t.box and not t.box.REMOVED then t.box:remove() end
end

function T.show(text, colour)
    if not (G and G.ROOM_ATTACH and UIBox and DynaText and G.E_MANAGER) then return end
    T.clear()
    local col = copy_table(colour or G.C.WHITE)
    local hold = ((QOL and QOL.TOAST_HOLD) or T.HOLD) + 0.1
    local dt = DynaText({scale = T.SCALE, string = text, colours = {col}, float = true, shadow = true, silent = true, pop_in = 0, pop_in_rate = 6, maxw = (G.ROOM and G.ROOM.T.w or 20) * 0.6})
    local box = UIBox{
        T = {0, 0, 0, 0},
        definition = {n = G.UIT.ROOT, config = {align = "cm", minw = 0.001, minh = 0.001, padding = 0.03, r = 0.1, colour = G.C.CLEAR}, nodes = {
            {n = G.UIT.O, config = {draw_layer = 1, object = dt}},
        }},
        config = {align = "cm", offset = {x = 0, y = T.OFFSET_Y}, major = G.ROOM_ATTACH},
    }
    box.attention_text = true
    box.over_overlay = true
    dt:pulse(0.5)
    local t = {box = box, text = dt, colour = col}
    T.cur = t
    G.E_MANAGER:add_event(Event({trigger = "after", delay = hold, timer = "REAL", pause_force = true, blockable = false, blocking = false, func = function()
        if T.cur ~= t or box.REMOVED then return true end
        if not t.start then
            t.start = G.TIMERS.REAL
            if dt.pop_out then dt:pop_out(3) end
            return false
        end
        local fade = math.max(0, 1 - 3 * (G.TIMERS.REAL - t.start))
        col[4] = math.min(col[4], fade)
        if fade <= 0 then
            box:remove()
            if T.cur == t then T.cur = nil end
            return true
        end
        return false
    end}))
    return box
end

function T.count()
    local n = 0
    for _, b in pairs(G.I.UIBOX or {}) do
        if type(b) == "table" and b.attention_text and not b.REMOVED then n = n + 1 end
    end
    return n
end

function T.init()
    if T._hooked then return end
    T._hooked = true
    if QOL then QOL.toast = T.show end
end

C.toast = T.show

return T
