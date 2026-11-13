local math = require("functions.pure_math")
local P = {}

P.W, P.H = 71, 95
P.CLEAR = 0
P.UNDO_LIMIT = 60

P.PALETTE = {
  "fe5f55", "009dff", "4bc292", "56a887", "fda200", "ff9a00", "eac058", "f3b958", "8867a5", "374244", "4f6367", "5f7377",
  "bfc7d5", "cb724c", "646eb7", "c75985", "4f5da1", "b18f43", "f03464", "f06b3f", "403995", "235955", "f83b2f", "e29000",
  "4f31b9", "008ee6", "b8d8d8", "7a9e9f", "d8d8d8", "cdd9dc", "424e54", "708b91", "a782d1", "13afce", "4584fa", "fd682b",
  "ffffff", "000000",
}

local floor = math.floor

function P.pack(r, g, b, a)
  return ((floor(r) * 256 + floor(g)) * 256 + floor(b)) * 256 + floor(a == nil and 255 or a)
end

function P.unpack(c)
  c = c or 0
  local a = c % 256
  c = (c - a) / 256
  local b = c % 256
  c = (c - b) / 256
  local g = c % 256
  local r = (c - g) / 256
  return r, g, b, a
end

function P.hex(s)
  s = tostring(s or ""):gsub("#", "")
  local r, g, b = tonumber(s:sub(1, 2), 16), tonumber(s:sub(3, 4), 16), tonumber(s:sub(5, 6), 16)
  if not (r and g and b) then return P.pack(0, 0, 0, 255) end
  return P.pack(r, g, b, 255)
end

function P.to_hex(c)
  local r, g, b = P.unpack(c)
  return string.format("%02x%02x%02x", r, g, b)
end

local function new_layer(n, fill, name, role)
  local px = {}
  for i = 1, n do px[i] = fill end
  return {name = name or "Art", role = role or "art", px = px, visible = true}
end

function P.new(w, h, fill)
  local d = {w = w or P.W, h = h or P.H, undo = {}, redo = {}, mirror = false, active = 1, sel = nil}
  d.layers = {new_layer(d.w * d.h, fill or P.CLEAR)}
  d.px = d.layers[1].px
  return d
end

function P.layer(d)
  return d.layers[d.active]
end

function P.relink(d)
  if not d.layers or #d.layers == 0 then d.layers = {new_layer(d.w * d.h, P.CLEAR)} end
  d.active = math.max(1, math.min(#d.layers, d.active or 1))
  d.px = d.layers[d.active].px
end

function P.inside(d, x, y)
  return x >= 0 and y >= 0 and x < d.w and y < d.h
end

function P.get(d, x, y)
  if not P.inside(d, x, y) then return nil end
  return d.px[y * d.w + x + 1]
end

function P.in_sel(d, x, y)
  local s = d.sel
  if not s then return true end
  return s.mask[y * d.w + x + 1] == true
end

local function raw_set(d, x, y, c)
  if P.inside(d, x, y) and P.in_sel(d, x, y) then d.px[y * d.w + x + 1] = c end
end

function P.set(d, x, y, c)
  raw_set(d, x, y, c)
  if d.mirror then raw_set(d, d.w - 1 - x, y, c) end
end

local function copy(t)
  local o = {}
  for i = 1, #t do o[i] = t[i] end
  return o
end

local function copy_sel(s)
  if not s then return nil end
  local m = {}
  for k, v in pairs(s.mask) do m[k] = v end
  return {mask = m, x0 = s.x0, y0 = s.y0, x1 = s.x1, y1 = s.y1}
end

function P.snapshot(d)
  local ls = {}
  for i, l in ipairs(d.layers) do ls[i] = {name = l.name, role = l.role, visible = l.visible, px = copy(l.px)} end
  return {layers = ls, active = d.active, sel = copy_sel(d.sel)}
end

local function live(d)
  return {layers = d.layers, active = d.active, sel = d.sel}
end

local function restore(d, snap)
  d.layers, d.active, d.sel = snap.layers, snap.active, snap.sel
  P.relink(d)
end

function P.begin(d)
  d.undo[#d.undo + 1] = P.snapshot(d)
  if #d.undo > P.UNDO_LIMIT then table.remove(d.undo, 1) end
  d.redo = {}
end

function P.cancel(d)
  local last = table.remove(d.undo)
  if last then restore(d, last) end
end

function P.same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

local function same_state(snap, d)
  if #snap.layers ~= #d.layers or snap.active ~= d.active then return false end
  for i, l in ipairs(d.layers) do
    local o = snap.layers[i]
    if o.name ~= l.name or o.role ~= l.role or o.visible ~= l.visible or not P.same(o.px, l.px) then return false end
  end
  return true
end

function P.finish(d)
  local last = d.undo[#d.undo]
  if last and same_state(last, d) then
    table.remove(d.undo)
    return false
  end
  return true
end

function P.can_undo(d) return #d.undo > 0 end
function P.can_redo(d) return #d.redo > 0 end

function P.undo_step(d)
  local last = table.remove(d.undo)
  if not last then return false end
  d.redo[#d.redo + 1] = live(d)
  restore(d, last)
  return true
end

function P.redo_step(d)
  local nxt = table.remove(d.redo)
  if not nxt then return false end
  d.undo[#d.undo + 1] = live(d)
  restore(d, nxt)
  return true
end

function P.line_points(x0, y0, x1, y1)
  local pts = {}
  local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
  local sx, sy = x0 < x1 and 1 or -1, y0 < y1 and 1 or -1
  local err = dx + dy
  local x, y = x0, y0
  for _ = 1, 4 * (dx - dy) + 2 do
    pts[#pts + 1] = {x, y}
    if x == x1 and y == y1 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x = x + sx end
    if e2 <= dx then err = err + dx; y = y + sy end
  end
  return pts
end

function P.line(d, x0, y0, x1, y1, c)
  for _, p in ipairs(P.line_points(x0, y0, x1, y1)) do P.set(d, p[1], p[2], c) end
end

function P.rect(d, x0, y0, x1, y1, c, filled)
  local ax, bx = math.min(x0, x1), math.max(x0, x1)
  local ay, by = math.min(y0, y1), math.max(y0, y1)
  for y = ay, by do
    for x = ax, bx do
      if filled or x == ax or x == bx or y == ay or y == by then P.set(d, x, y, c) end
    end
  end
end

function P.dist(a, b)
  local r1, g1, b1, a1 = P.unpack(a)
  local r2, g2, b2, a2 = P.unpack(b)
  if a1 == 0 and a2 == 0 then return 0 end
  return math.max(math.abs(r1 - r2), math.abs(g1 - g2), math.abs(b1 - b2), math.abs(a1 - a2))
end

local function tol_of(tol)
  return math.floor((tol or 0) * 255 / 100 + 0.5)
end

function P.region(d, x, y, tol, every)
  local target = P.get(d, x, y)
  if target == nil then return {} end
  local lim = tol_of(tol)
  local w, h, px = d.w, d.h, d.px
  local function ok(i)
    if d.sel and not d.sel.mask[i] then return false end
    local c = px[i]
    return c == target or (lim > 0 and P.dist(c, target) <= lim)
  end
  local out = {}
  if every then
    for i = 1, w * h do if ok(i) then out[#out + 1] = i end end
    return out
  end
  if not ok(y * w + x + 1) then return out end
  local seen = {[y * w + x + 1] = true}
  local stack = {y * w + x + 1}
  while #stack > 0 do
    local i = table.remove(stack)
    out[#out + 1] = i
    local qx, qy = (i - 1) % w, math.floor((i - 1) / w)
    local nb = {}
    if qx > 0 then nb[#nb + 1] = i - 1 end
    if qx < w - 1 then nb[#nb + 1] = i + 1 end
    if qy > 0 then nb[#nb + 1] = i - w end
    if qy < h - 1 then nb[#nb + 1] = i + w end
    for _, j in ipairs(nb) do
      if not seen[j] then
        seen[j] = true
        if ok(j) then stack[#stack + 1] = j end
      end
    end
  end
  return out
end

local function paint_list(d, list, c)
  local n = 0
  for _, i in ipairs(list) do
    if d.px[i] ~= c then d.px[i] = c; n = n + 1 end
  end
  return n
end

function P.fill(d, x, y, c, tol, every)
  local n = paint_list(d, P.region(d, x, y, tol, every), c)
  if d.mirror and not every then n = n + paint_list(d, P.region(d, d.w - 1 - x, y, tol, false), c) end
  return n
end

function P.brush_offsets(size)
  size = math.max(1, math.floor(size or 1))
  local out = {}
  local lo = -math.floor((size - 1) / 2)
  local hi = lo + size - 1
  local c = (lo + hi) / 2
  local r2 = (size / 2) ^ 2 + 0.01
  for dy = lo, hi do
    for dx = lo, hi do
      if size <= 2 or (dx - c) ^ 2 + (dy - c) ^ 2 <= r2 then out[#out + 1] = {dx, dy} end
    end
  end
  return out
end

local function darker(c)
  local r, g, b, a = P.unpack(c)
  return P.pack(r * 0.78, g * 0.78, b * 0.78, a)
end

local function lighter(c)
  local r, g, b, a = P.unpack(c)
  return P.pack(r + (255 - r) * 0.28, g + (255 - g) * 0.28, b + (255 - b) * 0.28, a)
end

P.shade_of, P.light_of = darker, lighter

local function dab(d, x, y, c, mode, seen)
  if not (P.inside(d, x, y) and P.in_sel(d, x, y)) then return end
  local i = y * d.w + x + 1
  if mode == "dither" then
    if (x + y) % 2 == 0 then d.px[i] = c end
  elseif mode == "shade" or mode == "light" then
    if seen then
      if seen[i] then return end
      seen[i] = true
    end
    local o = d.px[i]
    if select(4, P.unpack(o)) > 0 then d.px[i] = mode == "shade" and darker(o) or lighter(o) end
  else
    d.px[i] = c
  end
end

function P.stamp(d, x, y, c, size, mode, seen)
  for _, o in ipairs(P.brush_offsets(size)) do
    dab(d, x + o[1], y + o[2], c, mode, seen)
    if d.mirror then dab(d, d.w - 1 - (x + o[1]), y + o[2], c, mode, seen) end
  end
end

function P.stroke(d, x0, y0, x1, y1, c, size, mode, seen)
  for _, p in ipairs(P.line_points(x0, y0, x1, y1)) do P.stamp(d, p[1], p[2], c, size, mode, seen) end
end

function P.ellipse_points(x0, y0, x1, y1, filled)
  local ax, bx = math.min(x0, x1), math.max(x0, x1)
  local ay, by = math.min(y0, y1), math.max(y0, y1)
  local cx, cy = (ax + bx) / 2, (ay + by) / 2
  local rx, ry = (bx - ax + 1) / 2, (by - ay + 1) / 2
  local function inside(x, y)
    if x < ax or x > bx or y < ay or y > by then return false end
    return ((x - cx) / rx) ^ 2 + ((y - cy) / ry) ^ 2 <= 1.0001
  end
  local pts = {}
  for y = ay, by do
    for x = ax, bx do
      if inside(x, y) then
        if filled or not (inside(x - 1, y) and inside(x + 1, y) and inside(x, y - 1) and inside(x, y + 1)) then pts[#pts + 1] = {x, y} end
      end
    end
  end
  return pts
end

function P.ellipse(d, x0, y0, x1, y1, c, filled)
  for _, p in ipairs(P.ellipse_points(x0, y0, x1, y1, filled)) do P.set(d, p[1], p[2], c) end
end

local function mix(a, b, t)
  local r1, g1, b1, a1 = P.unpack(a)
  local r2, g2, b2, a2 = P.unpack(b)
  return P.pack(r1 + (r2 - r1) * t + 0.5, g1 + (g2 - g1) * t + 0.5, b1 + (b2 - b1) * t + 0.5, a1 + (a2 - a1) * t + 0.5)
end
P.mix = mix

local BAYER = {0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5}

function P.gradient(d, x0, y0, x1, y1, c1, c2, style, tol, every)
  local list
  if d.sel then
    list = {}
    for i in pairs(d.sel.mask) do list[#list + 1] = i end
  else
    list = P.region(d, x0, y0, tol, every)
  end
  local vx, vy = x1 - x0, y1 - y0
  local len = vx * vx + vy * vy
  local n = 0
  for _, i in ipairs(list) do
    local x, y = (i - 1) % d.w, math.floor((i - 1) / d.w)
    local t = len > 0 and ((x - x0) * vx + (y - y0) * vy) / len or 0
    t = math.max(0, math.min(1, t))
    local c
    if style == "dither" then
      c = t * 16 > BAYER[(y % 4) * 4 + (x % 4) + 1] + 0.5 and c2 or c1
    else
      c = mix(c1, c2, math.floor(t * 5 + 0.5) / 5)
    end
    if d.px[i] ~= c then d.px[i] = c; n = n + 1 end
  end
  return n
end

local function bbox(mask, w)
  local x0, y0, x1, y1
  for i in pairs(mask) do
    local x, y = (i - 1) % w, math.floor((i - 1) / w)
    if not x0 then x0, y0, x1, y1 = x, y, x, y else
      x0, y0, x1, y1 = math.min(x0, x), math.min(y0, y), math.max(x1, x), math.max(y1, y)
    end
  end
  return x0, y0, x1, y1
end

local function set_mask(d, mask, mode)
  local cur = d.sel and d.sel.mask or {}
  local m = {}
  if mode == "add" then
    for k in pairs(cur) do m[k] = true end
    for k in pairs(mask) do m[k] = true end
  elseif mode == "subtract" then
    for k in pairs(cur) do if not mask[k] then m[k] = true end end
  else
    m = mask
  end
  local x0, y0, x1, y1 = bbox(m, d.w)
  if not x0 then d.sel = nil; return false end
  d.sel = {mask = m, x0 = x0, y0 = y0, x1 = x1, y1 = y1}
  return true
end
P.set_mask = set_mask

function P.select_rect(d, x0, y0, x1, y1, mode)
  local m = {}
  for y = math.max(0, math.min(y0, y1)), math.min(d.h - 1, math.max(y0, y1)) do
    for x = math.max(0, math.min(x0, x1)), math.min(d.w - 1, math.max(x0, x1)) do m[y * d.w + x + 1] = true end
  end
  return set_mask(d, m, mode)
end

function P.select_all(d)
  local m = {}
  for i = 1, d.w * d.h do m[i] = true end
  return set_mask(d, m)
end

function P.select_none(d)
  d.sel = nil
end

function P.select_lasso(d, pts, mode)
  local m = {}
  if #pts >= 3 then
    for y = 0, d.h - 1 do
      for x = 0, d.w - 1 do
        local px, py, inside = x + 0.5, y + 0.5, false
        local j = #pts
        for i = 1, #pts do
          local xi, yi = pts[i][1] + 0.5, pts[i][2] + 0.5
          local xj, yj = pts[j][1] + 0.5, pts[j][2] + 0.5
          if (yi > py) ~= (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi then inside = not inside end
          j = i
        end
        if inside then m[y * d.w + x + 1] = true end
      end
    end
  end
  for k = 1, #pts do
    local a, b = pts[k], pts[k % #pts + 1]
    for _, q in ipairs(P.line_points(a[1], a[2], b[1], b[2])) do
      if P.inside(d, q[1], q[2]) then m[q[2] * d.w + q[1] + 1] = true end
    end
  end
  return set_mask(d, m, mode)
end

function P.select_wand(d, x, y, tol, every, mode)
  local keep = d.sel
  d.sel = nil
  local list = P.region(d, x, y, tol, every)
  d.sel = keep
  local m = {}
  for _, i in ipairs(list) do m[i] = true end
  return set_mask(d, m, mode)
end

local function area(d)
  if d.sel then return d.sel.x0, d.sel.y0, d.sel.x1, d.sel.y1, d.sel.mask end
  return 0, 0, d.w - 1, d.h - 1, nil
end

local function take(d)
  local x0, y0, x1, y1, mask = area(d)
  local items = {}
  for y = y0, y1 do
    for x = x0, x1 do
      local i = y * d.w + x + 1
      if not mask or mask[i] then
        items[#items + 1] = {x, y, d.px[i]}
        d.px[i] = P.CLEAR
      end
    end
  end
  return items, x0, y0, x1, y1
end

local function put(d, items, map)
  local m = d.sel and {} or nil
  for _, it in ipairs(items) do
    local x, y = map(it[1], it[2])
    if P.inside(d, x, y) then
      local i = y * d.w + x + 1
      if select(4, P.unpack(it[3])) > 0 then d.px[i] = it[3] end
      if m then m[i] = true end
    end
  end
  if m then set_mask(d, m) end
end

function P.move(d, dx, dy)
  local items = take(d)
  put(d, items, function(x, y) return x + dx, y + dy end)
end

function P.flip(d)
  local items, x0, _, x1 = take(d)
  put(d, items, function(x, y) return x0 + x1 - x, y end)
end

function P.flip_v(d)
  local items, _, y0, _, y1 = take(d)
  put(d, items, function(x, y) return x, y0 + y1 - y end)
end

function P.rotate(d)
  local items, x0, y0, x1, y1 = take(d)
  local w, h = x1 - x0 + 1, y1 - y0 + 1
  local nx0, ny0 = x0 + math.floor((w - h) / 2), y0 + math.floor((h - w) / 2)
  put(d, items, function(x, y) return nx0 + (h - 1 - (y - y0)), ny0 + (x - x0) end)
end

function P.copy(d)
  local x0, y0, x1, y1, mask = area(d)
  local clip = {x = x0, y = y0, w = x1 - x0 + 1, h = y1 - y0 + 1, px = {}}
  for y = y0, y1 do
    for x = x0, x1 do
      local i = y * d.w + x + 1
      clip.px[(y - y0) * clip.w + (x - x0) + 1] = (not mask or mask[i]) and d.px[i] or P.CLEAR
    end
  end
  return clip
end

function P.cut(d)
  local clip = P.copy(d)
  P.clear(d)
  return clip
end

function P.paste(d, clip, x, y)
  if not clip then return false end
  x, y = x or clip.x, y or clip.y
  local m = {}
  for cy = 0, clip.h - 1 do
    for cx = 0, clip.w - 1 do
      local c = clip.px[cy * clip.w + cx + 1]
      local tx, ty = x + cx, y + cy
      if P.inside(d, tx, ty) and select(4, P.unpack(c)) > 0 then
        local i = ty * d.w + tx + 1
        d.px[i] = c
        m[i] = true
      end
    end
  end
  return set_mask(d, m)
end

function P.outline(d, c)
  local x0, y0, x1, y1 = area(d)
  local src = copy(d.px)
  local w, h = d.w, d.h
  local function solid(x, y)
    if x < 0 or y < 0 or x >= w or y >= h then return false end
    return select(4, P.unpack(src[y * w + x + 1])) > 0
  end
  local n = 0
  for y = y0, y1 do
    for x = x0, x1 do
      local i = y * w + x + 1
      if P.in_sel(d, x, y) and not solid(x, y) and (solid(x - 1, y) or solid(x + 1, y) or solid(x, y - 1) or solid(x, y + 1)) then
        d.px[i] = c
        n = n + 1
      end
    end
  end
  return n
end

function P.clear(d, c)
  local v = c or P.CLEAR
  if d.sel then
    for i in pairs(d.sel.mask) do d.px[i] = v end
    return
  end
  for i = 1, #d.px do d.px[i] = v end
end

local function art_count(d, role)
  local n = 0
  for _, l in ipairs(d.layers) do if l.role == role then n = n + 1 end end
  return n
end
P.count_role = art_count
P.MAX_ART = 4

function P.add_layer(d, role, name)
  role = role or "art"
  if role == "soul" and art_count(d, "soul") > 0 then return false end
  if role == "art" and art_count(d, "art") >= P.MAX_ART then return false end
  local l = new_layer(d.w * d.h, P.CLEAR, name, role)
  local at = #d.layers + 1
  if role == "art" then
    for i, o in ipairs(d.layers) do if o.role == "soul" then at = i; break end end
  end
  table.insert(d.layers, at, l)
  d.active = at
  P.relink(d)
  return true
end

function P.delete_layer(d, i)
  i = i or d.active
  local l = d.layers[i]
  if not l or (l.role == "art" and art_count(d, "art") <= 1) then return false end
  table.remove(d.layers, i)
  d.active = math.max(1, math.min(#d.layers, i - 1 > 0 and i - 1 or 1))
  P.relink(d)
  return true
end

function P.move_layer(d, i, step)
  i = i or d.active
  local j = i + step
  local a, b = d.layers[i], d.layers[j]
  if not (a and b) or a.role ~= b.role then return false end
  d.layers[i], d.layers[j] = b, a
  if d.active == i then d.active = j elseif d.active == j then d.active = i end
  P.relink(d)
  return true
end

local function over(dst, src)
  local sr, sg, sb, sa = P.unpack(src)
  if sa == 0 then return dst end
  if sa == 255 then return src end
  local dr, dg, db, da = P.unpack(dst)
  local a = sa / 255
  local oa = a + (da / 255) * (1 - a)
  if oa <= 0 then return P.CLEAR end
  local function ch(s, t) return (s * a + t * (da / 255) * (1 - a)) / oa end
  return P.pack(ch(sr, dr) + 0.5, ch(sg, dg) + 0.5, ch(sb, db) + 0.5, oa * 255 + 0.5)
end

function P.merge_down(d, i)
  i = i or d.active
  local a, b = d.layers[i], d.layers[i - 1]
  if not (a and b) or a.role ~= b.role then return false end
  for k = 1, #a.px do b.px[k] = over(b.px[k], a.px[k]) end
  table.remove(d.layers, i)
  d.active = i - 1
  P.relink(d)
  return true
end

function P.flatten(d, role)
  role = role or "art"
  local out = {}
  for k = 1, d.w * d.h do out[k] = P.CLEAR end
  for _, l in ipairs(d.layers) do
    if l.role == role and l.visible then
      for k = 1, #out do out[k] = over(out[k], l.px[k]) end
    end
  end
  return out
end

function P.has_pixels(px)
  for k = 1, #px do if select(4, P.unpack(px[k])) > 0 then return true end end
  return false
end

function P.flat_doc(d, role)
  local o = P.new(d.w, d.h)
  o.layers[1].px = P.flatten(d, role)
  P.relink(o)
  return o
end

function P.colours(d, limit)
  local count, order = {}, {}
  for _, l in ipairs(d.layers) do
    if l.visible then
      for k = 1, #l.px do
        local c = l.px[k]
        if select(4, P.unpack(c)) > 0 then
          if not count[c] then count[c] = 0; order[#order + 1] = c end
          count[c] = count[c] + 1
        end
      end
    end
  end
  table.sort(order, function(a, b) if count[a] ~= count[b] then return count[a] > count[b] end return a < b end)
  local out = {}
  for k = 1, math.min(#order, limit or 48) do out[k] = order[k] end
  return out
end

function P.nearest(c, palette)
  local r, g, b = P.unpack(c)
  local best, bd
  for _, p in ipairs(palette) do
    local pr, pg, pb = P.unpack(p)
    local dd = (pr - r) ^ 2 + (pg - g) ^ 2 + (pb - b) ^ 2
    if not bd or dd < bd then best, bd = p, dd end
  end
  return best or c
end

function P.fit(src, sw, sh, w, h, palette)
  local o = P.new(w, h)
  local k = math.max(sw / w, sh / h, 1)
  local ow, oh = math.min(w, math.floor(sw / k + 0.5)), math.min(h, math.floor(sh / k + 0.5))
  local ox, oy = math.floor((w - ow) / 2), math.floor((h - oh) / 2)
  for y = 0, oh - 1 do
    local sy0 = math.floor(y * k + 0.0001)
    local sy1 = math.max(sy0, math.min(sh - 1, math.ceil((y + 1) * k - 0.0001) - 1))
    for x = 0, ow - 1 do
      local sx0 = math.floor(x * k + 0.0001)
      local sx1 = math.max(sx0, math.min(sw - 1, math.ceil((x + 1) * k - 0.0001) - 1))
      local tr, tg, tb, ta, n = 0, 0, 0, 0, 0
      for yy = sy0, sy1 do
        for xx = sx0, sx1 do
          local r, g, b, a = P.unpack(src[yy * sw + xx + 1])
          tr, tg, tb, ta, n = tr + r * a, tg + g * a, tb + b * a, ta + a, n + 1
        end
      end
      local c = P.CLEAR
      if n > 0 and ta / n >= 128 then
        c = P.pack(tr / ta + 0.5, tg / ta + 0.5, tb / ta + 0.5, 255)
        if palette then c = P.nearest(c, palette) end
      end
      o.px[(oy + y) * w + ox + x + 1] = c
    end
  end
  return o
end

function P.palette_colours()
  local out = {}
  for i, h in ipairs(P.PALETTE) do out[i] = P.hex(h) end
  return out
end

function P.to_2x(d)
  local o = P.new(d.w * 2, d.h * 2)
  for y = 0, d.h - 1 do
    for x = 0, d.w - 1 do
      local c = d.px[y * d.w + x + 1]
      local i = (2 * y) * o.w + 2 * x + 1
      o.px[i], o.px[i + 1] = c, c
      o.px[i + o.w], o.px[i + o.w + 1] = c, c
    end
  end
  return o
end

function P.from_image_data(data)
  local w, h = data:getDimensions()
  local d = P.new(w, h)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = data:getPixel(x, y)
      d.px[y * w + x + 1] = P.pack(r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5, a * 255 + 0.5)
    end
  end
  return d
end

function P.write_image_data(d, data)
  local w = d.w
  data:mapPixel(function(x, y)
    local r, g, b, a = P.unpack(d.px[y * w + x + 1])
    return r / 255, g / 255, b / 255, a / 255
  end)
  return data
end

return P
