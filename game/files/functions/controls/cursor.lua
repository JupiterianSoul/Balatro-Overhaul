local M = {}

M.STEPS = {50, 75, 100, 125, 150, 200, 250, 300}
M.BASE_AXIS = 20

function M.get()
    local v = G and G.SETTINGS and tonumber(G.SETTINGS.cursor_speed) or 100
    if v < 25 then v = 25 elseif v > 400 then v = 400 end
    return v
end

function M.set(v)
    if not (G and G.SETTINGS) then return end
    G.SETTINGS.cursor_speed = v
    M.apply()
end

function M.apply()
    if G and G.CONTROLLER then G.CONTROLLER.axis_cursor_speed = M.BASE_AXIS * M.get() / 100 end
end

local warp

function M.init()
    M.apply()
    if M._wrapped then return end
    M._wrapped = true
    local mm = love.mousemoved
    love.mousemoved = function(x, y, dx, dy, istouch, ...)
        local s = M.get() / 100
        if not istouch and s ~= 1 and dx and dy and not love.mouse.getRelativeMode() then
            if warp and math.abs(x - warp[1]) < 1.5 and math.abs(y - warp[2]) < 1.5 then
                warp = nil
            else
                local w, h = love.graphics.getDimensions()
                local nx = math.max(0, math.min(w - 1, x - dx + dx * s))
                local ny = math.max(0, math.min(h - 1, y - dy + dy * s))
                if math.abs(nx - x) >= 1 or math.abs(ny - y) >= 1 then
                    warp = {nx, ny}
                    love.mouse.setPosition(nx, ny)
                end
                x, y, dx, dy = nx, ny, dx * s, dy * s
            end
        end
        if mm then return mm(x, y, dx, dy, istouch, ...) end
    end
end

return M
