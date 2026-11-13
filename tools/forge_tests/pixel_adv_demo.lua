local P = require("functions/forge/forge_pixel")
local PX = ForgePixelUI

FPA = FPA or {}

local function push(...) FPD.queue[#FPD.queue + 1] = {...} end
local function lua(f) push("lua", f) end
local function ref(t) return {config = {ref_table = t}} end

function FPA.mode(m) G.FUNCS.forge_px_mode(ref({mode = m})) end
function FPA.group(g) PX.state.group = g end
function FPA.act(a) lua(function() G.FUNCS.forge_px_act(ref({act = a})) end) end
function FPA.panel(p) G.FUNCS.forge_px_panel(ref({panel = p})) end

local function hex_at(x, y)
  local c = P.get(PX.doc, x, y)
  return c and P.to_hex(c) .. string.format("%02x", select(4, P.unpack(c))) or "nil"
end

function FPA.draw()
  lua(function() FPA.group("shape") end)
  FPD.stroke("block", "4f6367", {{5, 8}, {65, 86}})
  FPD.stroke("oval", "fda200", {{10, 12}, {60, 50}})
  FPD.stroke("disc", "fe5f55", {{25, 20}, {45, 40}})
  FPD.stroke("box", "ffffff", {{8, 55}, {62, 84}})
  lua(function() FPA.group("draw"); PX.state.brush = 3 end)
  FPD.stroke("dither", "009dff", {{12, 60}, {58, 60}})
  lua(function() PX.state.brush = 1; PX.state.colour2 = P.hex("8867a5") end)
  FPD.stroke("gradient", "4bc292", {{12, 66}, {58, 80}})
  lua(function() PX.state.brush = 4 end)
  FPD.stroke("shade", nil, {{30, 25}, {40, 35}})
  FPD.stroke("light", nil, {{26, 38}, {32, 38}})
  lua(function() PX.state.brush = 1 end)
  lua(function()
    HLOG("adv_draw", hex_at(6, 9), hex_at(10, 31), hex_at(35, 30), hex_at(12, 60), hex_at(13, 60), hex_at(12, 67), hex_at(57, 79), hex_at(8, 55), #PX.doc.undo)
    UIK.refresh()
  end)
end

function FPA.select_move()
  lua(function() FPA.group("select") end)
  FPD.stroke("select", nil, {{20, 15}, {50, 45}})
  FPA.act("copy")
  FPA.act("paste")
  FPD.stroke("move", nil, {{30, 30}, {33, 40}, {36, 48}})
  lua(function()
    local s = PX.doc.sel
    HLOG("adv_move", s and s.x0, s and s.y0, s and s.x1, s and s.y1, PX.clip and PX.clip.w, PX.state.tool)
  end)
end

function FPA.edit()
  lua(function() FPA.group("select") end)
  FPD.stroke("wand", nil, {{6, 9}})
  lua(function() HLOG("adv_wand", PX.doc.sel and PX.doc.sel.x0, PX.doc.sel and PX.doc.sel.y1) end)
  FPA.act("deselect")
  FPD.stroke("lasso", nil, {{2, 2}, {20, 2}, {20, 20}, {2, 20}})
  lua(function() HLOG("adv_lasso", PX.doc.sel and PX.doc.sel.x0, PX.doc.sel and PX.doc.sel.x1) end)
  FPA.act("deselect")
  lua(function() FPA.group("edit"); PX.state.colour = P.hex("000000") end)
  FPA.act("outline")
  FPA.act("flip_v")
  lua(function() HLOG("adv_edit", hex_at(4, 7), hex_at(6, 85), #PX.doc.undo) end)
  FPA.act("flip_v")
end

function FPA.layers()
  lua(function() FPA.group("edit") end)
  FPA.act("soul")
  FPD.stroke("pencil", "f3b958", {{30, 4}, {40, 4}, {40, 10}})
  lua(function() PX.state.brush = 1 end)
  FPA.act("layer")
  lua(function()
    local d = PX.doc
    local roles = {}
    for _, l in ipairs(d.layers) do roles[#roles + 1] = l.role end
    HLOG("adv_layers", table.concat(roles, ","), d.active, PX.has_soul, love.filesystem.getInfo(PX.paths().soul) ~= nil, love.filesystem.getInfo(PX.paths().x2) ~= nil)
    FPA.panel("layers")
  end)
end

function FPA.edition(i)
  PX.state.panel = "view"
  PX.state.edition = i
  UIK.refresh()
  local c = PX.preview_card
  HLOG("adv_edition", PX.EDITIONS[i], c and c.edition and c.edition.type or "none")
end

function FPA.palettes()
  PX.state.pal = "art"
  UIK.refresh()
  HLOG("adv_art_palette", #PX.palette())
end

function FPA.mine()
  PX.state.pal = "mine"
  G.FUNCS.forge_px_mine_add()
  PX.state.colour = P.hex("13afce")
  G.FUNCS.forge_px_mine_add()
  HLOG("adv_mine", #PX.palette())
end

function FPA.put_import()
  love.filesystem.createDirectory("forge")
  love.filesystem.createDirectory("forge/import")
  local data = love.image.newImageData(142, 190)
  data:mapPixel(function(x, y)
    if (x - 71) ^ 2 + (y - 95) ^ 2 < 60 ^ 2 then return 0.99, 0.37, 0.33, 1 end
    return 0, 0, 0, 0
  end)
  love.filesystem.write("forge/import/round.png", data:encode("png"):getString())
end

function FPA.import_check()
  HLOG("adv_import", PX.doc.w, PX.doc.h, hex_at(35, 47), hex_at(0, 0))
end

function FPA.kind_check()
  HLOG("adv_kind", PX.state.kind, PX.doc.w, PX.doc.h, PX.guide_image ~= nil, hex_at(17, 17))
end

function FPA.pad()
  local C = G.CONTROLLER
  lua(function()
    PX.state.tool = "pencil"
    PX.state.colour = P.hex("fe5f55")
    PX.state.brush = 1
    PX.pad.x, PX.pad.y = 0, 0
    C.focused.target = G.OVERLAY_MENU:get_UIE_by_ID("forge_px_canvas")
    C:button_press_update("a", 0)
  end)
  lua(function() C:button_release_update("a", 0) end)
  lua(function() C:button_press_update("a", 0) end)
  for _ = 1, 5 do lua(function() C:button_press_update("dpright", 0) end) end
  lua(function() C:button_release_update("a", 0) end)
  lua(function() HLOG("adv_pad", PX.pad.on, PX.pad.x, PX.pad.y, hex_at(35, 47), hex_at(40, 47), hex_at(41, 47), #PX.doc.undo) end)
end

function FPA.pad_end()
  local C = G.CONTROLLER
  lua(function() C:button_press_update("x", 0) end)
  lua(function()
    C:button_press_update("b", 0)
    HLOG("adv_pad_end", PX.pad.on, hex_at(38, 47), #PX.doc.undo)
  end)
end

function FPA.inputs()
  local C = G.CONTROLLER
  local real = love.keyboard.isDown
  local held = {}
  love.keyboard.isDown = function(...)
    for _, k in ipairs({...}) do if held[k] then return true end end
    return real(...)
  end
  local function key(k, mods)
    lua(function()
      held = mods or {}
      C:key_press_update(k, 0)
      held = {}
    end)
  end
  local out = {}
  local function note(name, v) lua(function() out[#out + 1] = name .. "=" .. tostring(v()) end) end
  lua(function() PX.state.colour, PX.state.colour2 = P.hex("fe5f55"), P.hex("009dff"); PX.state.zoom_i = 1 end)
  key("g") note("g", function() return PX.state.tool end)
  key("b") note("b", function() return PX.state.tool end)
  key("]") key("]") key("[") note("brush", function() return PX.state.brush end)
  key("x") note("swap", function() return P.to_hex(PX.state.colour) end)
  key("=") note("zoom_in", function() return PX.state.zoom_i end)
  key("-") note("zoom_out", function() return PX.state.zoom_i end)
  key("a", {lctrl = true}) note("all", function() return PX.doc.sel and PX.doc.sel.x1 end)
  key("delete") note("cleared", function() return hex_at(35, 47) end)
  key("z", {lctrl = true}) note("undo", function() return hex_at(35, 47) end)
  key("y", {lctrl = true}) note("redo", function() return hex_at(35, 47) end)
  key("z", {lctrl = true})
  FPA.act("deselect")
  lua(function()
    local cv = PX.canvas
    local m = cv and cv.map
    if not m then return "retry" end
    local ox, oy, ps = cv:origin()
    FPD.mouse = {m.x + (ox + 35.5 * ps) * m.k, m.y + (oy + 47.5 * ps) * m.k}
    love.wheelmoved(0, 1)
  end)
  note("wheel", function() return PX.state.zoom_i end)
  local mouse_down = love.mouse.isDown
  lua(function()
    PX.state.colour = P.hex("ffffff")
    love.mouse.isDown = function(b, ...) if b == 2 then return true end return mouse_down(b, ...) end
  end)
  for _ = 1, 16 do lua(function() end) end
  lua(function() love.mouse.isDown = mouse_down end)
  note("right_pick", function() return P.to_hex(PX.state.colour) end)
  local pan0
  lua(function()
    pan0 = PX.state.pan.x
    love.mouse.isDown = function(b, ...) if b == 3 then return true end return mouse_down(b, ...) end
  end)
  for _ = 1, 16 do lua(function() end) end
  lua(function() FPD.mouse = {FPD.mouse[1] + 40, FPD.mouse[2]} end)
  for _ = 1, 16 do lua(function() end) end
  lua(function() love.mouse.isDown = mouse_down end)
  note("middle_pan", function() return PX.state.pan.x > pan0 end)
  lua(function()
    love.wheelmoved(0, -1)
    FPD.mouse = nil
    local data = love.image.newImageData(71, 95)
    data:mapPixel(function() return 0.29, 0.76, 0.57, 1 end)
    local raw = data:encode("png"):getString()
    local file = {open = function() return true end, read = function() return raw end, close = function() return true end}
    love.filedropped(file)
  end)
  note("dropped", function() return hex_at(10, 10) end)
  lua(function() P.select_rect(PX.doc, 0, 0, 9, 9) end)
  FPA.act("cut")
  note("cut", function() return hex_at(5, 5) .. "/" .. tostring(PX.clip and PX.clip.w) end)
  FPA.act("deselect")
  lua(function() P.select_rect(PX.doc, 20, 20, 29, 24); PX.state.colour = P.hex("000000") end)
  FPA.act("clear")
  note("clear_sel", function() return hex_at(25, 22) .. "/" .. hex_at(25, 26) end)
  FPA.act("rotate")
  note("rotate", function() return hex_at(25, 18) .. "/" .. hex_at(21, 22) end)
  FPA.act("deselect")
  FPA.act("flip")
  note("flip", function() return hex_at(65, 5) .. "/" .. hex_at(5, 5) end)
  lua(function()
    love.keyboard.isDown = real
    HLOG("adv_inputs", table.concat(out, " "))
    UIK.refresh()
  end)
end

HLOG("pixel_adv_demo", PX ~= nil and FPD ~= nil)
