local P = require("functions/forge/forge_pixel")
local PX = ForgePixelUI

FPD = FPD or {queue = {}, mouse = nil}

if not FPD.hooked then
  FPD.hooked = true
  local get = love.mouse.getPosition
  love.mouse.getPosition = function()
    if FPD.mouse then return FPD.mouse[1], FPD.mouse[2] end
    return get()
  end
  local upd = love.update
  love.update = function(dt)
    FPD.tick()
    return upd(dt)
  end
end

local function screen_of(px, py)
  local cv = PX.canvas
  local m = cv and cv.map
  if not m then return nil end
  local ox, oy, ps = cv:origin()
  return m.x + (ox + (px + 0.5) * ps) * m.k, m.y + (oy + (py + 0.5) * ps) * m.k
end

function FPD.tick()
  local a = table.remove(FPD.queue, 1)
  if not a then return end
  if a[1] == "tool" then
    G.FUNCS.forge_px_tool({config = {ref_table = {tool = a[2]}}})
  elseif a[1] == "colour" then
    G.FUNCS.forge_px_colour({config = {ref_table = {c = P.hex(a[2])}}})
  elseif a[1] == "move" then
    local x, y = screen_of(a[2], a[3])
    if x then FPD.mouse = {x, y} else table.insert(FPD.queue, 1, a) end
  elseif a[1] == "press" then
    if not FPD.mouse then return table.insert(FPD.queue, 1, a) end
    love.mousepressed(FPD.mouse[1], FPD.mouse[2], 1, false)
  elseif a[1] == "release" then
    love.mousereleased(FPD.mouse[1], FPD.mouse[2], 1)
  elseif a[1] == "free" then
    FPD.mouse = nil
  elseif a[1] == "lua" then
    if a[2]() == "retry" then table.insert(FPD.queue, 1, a) end
  end
end

local function push(...) FPD.queue[#FPD.queue + 1] = {...} end

function FPD.stroke(tool, hex, pts)
  push("tool", tool)
  if hex then push("colour", hex) end
  push("wait")
  push("move", pts[1][1], pts[1][2])
  push("wait")
  push("press")
  for _, p in ipairs(pts) do
    push("move", p[1], p[2])
    push("wait")
  end
  push("release")
  push("wait")
  push("free")
  push("wait")
end

function FPD.draw()
  FPD.stroke("fill", "fda200", {{35, 47}})
  FPD.stroke("box", "009dff", {{10, 12}, {30, 40}, {60, 82}})
  push("lua", function() PX.state.mirror = true; if PX.doc then PX.doc.mirror = true end end)
  FPD.stroke("line", "fe5f55", {{14, 18}, {30, 45}, {32, 50}})
  FPD.stroke("pencil", "374244", {{22, 60}, {26, 63}, {30, 65}, {35, 66}})
  FPD.stroke("eraser", nil, {{12, 30}, {12, 34}, {12, 38}})
  FPD.stroke("pencil", "4bc292", {{20, 25}, {24, 25}, {24, 29}})
  push("lua", function()
    local d = PX.doc
    HLOG("pixel_draw", P.to_hex(P.get(d, 35, 47)), P.to_hex(P.get(d, 10, 50)), P.to_hex(P.get(d, 56, 18)), select(4, P.unpack(P.get(d, 12, 34))), #d.undo, love.filesystem.getInfo("forge/art/scratch.png") ~= nil)
    UIK.refresh()
  end)
end

function FPD.check_undo()
  push("lua", function()
    local d = PX.doc
    local before = P.to_hex(P.get(d, 21, 25))
    G.FUNCS.forge_px_undo()
    local undone = P.get(d, 21, 25)
    G.FUNCS.forge_px_redo()
    HLOG("pixel_undo", before, P.to_hex(undone), P.to_hex(P.get(PX.doc, 21, 25)), #PX.doc.undo, #PX.doc.redo)
  end)
end

function FPD.zoom()
  PX.state.grid = true
  G.FUNCS.forge_px_zoom({config = {ref_table = {d = 1}}})
  G.FUNCS.forge_px_zoom({config = {ref_table = {d = 1}}})
  G.FUNCS.forge_px_zoom({config = {ref_table = {d = 1}}})
end

function FPD.pan()
  FPD.stroke("pan", nil, {{35, 47}, {30, 40}, {25, 35}})
end

function FPD.hover()
  local c = PX.preview_card
  if c then c:hover() end
end

function FPD.unhover()
  local c = PX.preview_card
  if c then c:stop_hover() end
end

HLOG("pixel_demo", PX ~= nil)
