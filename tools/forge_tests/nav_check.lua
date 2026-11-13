FNAV = FNAV or {}

local function walk(node, out, depth)
  if type(node) ~= "table" or (depth or 0) > 80 then return end
  out[#out + 1] = node
  for _, c in pairs(node.children or {}) do walk(c, out, (depth or 0) + 1) end
  local o = node.config and node.config.object
  if o and o.UIRoot then walk(o.UIRoot, out, (depth or 0) + 1) end
end

local function name_of(n)
  local c = n.config or {}
  return tostring(c.id or c.button or (c.focus_args and c.focus_args.type) or "node")
end

local function focusables()
  local all = {}
  if type(G.OVERLAY_MENU) == "table" then walk(G.OVERLAY_MENU.UIRoot, all) end
  local out = {}
  for _, n in ipairs(all) do
    if n.states and n.T and G.CONTROLLER:is_node_focusable(n) then out[#out + 1] = n end
  end
  return out
end

local function step(from, dir)
  local C = G.CONTROLLER
  C.focused.target = from
  from.states.focus.is = true
  C.HID.axis_cursor = false
  local had = rawget(from, "collides_with_point")
  from.collides_with_point = function() return true end
  local hov = C.hovering.target
  C.hovering.target = from
  C:update_focus(dir)
  C.hovering.target = hov
  from.collides_with_point = had
  return C.focused.target
end

function FNAV.run(tag)
  local C = G.CONTROLLER
  local was = C.HID.controller
  C.HID.controller = true
  local list = focusables()
  local index = {}
  for i, n in ipairs(list) do index[n] = i end
  local seen, queue = {}, {}
  if list[1] then seen[list[1]] = true; queue[1] = list[1] end
  local head = 1
  local ok, err = pcall(function()
    while queue[head] do
      local n = queue[head]
      head = head + 1
      for _, dir in ipairs({"U", "D", "L", "R"}) do
        local t = step(n, dir)
        if t and index[t] and not seen[t] then seen[t] = true; queue[#queue + 1] = t end
      end
    end
  end)
  local missed, small = {}, {}
  for _, n in ipairs(list) do
    if not seen[n] then missed[#missed + 1] = name_of(n) .. string.format("@%.1f,%.1f", n.T.x, n.T.y) end
    if n.config and n.config.button and (n.T.w < 0.5 or n.T.h < 0.3) then small[#small + 1] = name_of(n) .. string.format("(%.2fx%.2f)", n.T.w, n.T.h) end
  end
  if C.focused.target then C.focused.target.states.focus.is = false end
  C.focused.target = nil
  C.HID.controller = was
  HLOG("forge_nav", tag, "focusable", #list, "reached", head - 1, "missed", #missed, table.concat(missed, " "), "tiny", table.concat(small, " "), ok and "" or ("error " .. tostring(err)))
end

function FNAV.dump(tag)
  local C = G.CONTROLLER
  local was = C.HID.controller
  C.HID.controller = true
  for _, n in ipairs(focusables()) do
    local moves = {}
    for _, dir in ipairs({"U", "D", "L", "R"}) do
      local ok, t = pcall(step, n, dir)
      moves[#moves + 1] = dir .. "=" .. ((ok and t and t ~= n) and (name_of(t) .. string.format("@%.1f,%.1f", t.T.x, t.T.y)) or "-")
    end
    HLOG("forge_nav_dump", tag, name_of(n) .. string.format("@%.1f,%.1f", n.T.x, n.T.y), table.concat(moves, " "))
  end
  if C.focused.target then C.focused.target.states.focus.is = false end
  C.focused.target = nil
  C.HID.controller = was
end

return FNAV
