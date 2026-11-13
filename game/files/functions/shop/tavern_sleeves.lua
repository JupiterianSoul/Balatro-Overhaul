local math = require("functions.pure_math")
local SL = {}

local W, H = 71, 95
SL.CUT = 32
SL.COLS = 8

local MAT = {stone = {5, 0}, gold = {6, 0}, glass = {5, 1}, steel = {6, 1}, parchment = {4, 1}}

local function sleeve(id, name, rarity, mat, tone, emblem)
  return {id = id, name = name, rarity = rarity, mat = mat, tone = tone, emblem = emblem}
end

SL.LIST = {
  sleeve("granite_wall", "Granite Wall", "common", "stone", nil),
  sleeve("jade_serpent", "Jade Serpent", "uncommon", "stone", {"0f3a2a", "8fe0b0"}),
  sleeve("obsidian_mind", "Obsidian Mind", "rare", "stone", {"120c1e", "9a7ad8"}),
  sleeve("rose_quartz", "Rose Quartz", "uncommon", "stone", {"4a1430", "ffb0cc"}),
  sleeve("gilded_seal", "Gilded Seal", "rare", "glass", {"2a0a0a", "e8c050"}, {seal = {2, 0}}),
  sleeve("copper_flint", "Copper Flint", "common", "gold", {"3a1606", "f0905a"}),
  sleeve("silver_bell", "Silver Bell", "uncommon", "gold", {"262a36", "f2f4ff"}),
  sleeve("iron_ox", "Iron Ox", "common", "steel", nil),
  sleeve("cobalt_wheel", "Cobalt Wheel", "common", "steel", {"0a1a4a", "7fc8ff"}),
  sleeve("ember_mouth", "Ember Mouth", "uncommon", "steel", {"3a0808", "ffa040"}),
  sleeve("glass_eye", "Glass Eye", "common", "glass", nil),
  sleeve("frost_water", "Frost Water", "uncommon", "glass", {"0a3a44", "c8fbff"}),
  sleeve("amethyst_seal", "Amethyst Seal", "rare", "glass", {"260a40", "d8a8ff"}, {seal = {5, 4}}),
  sleeve("old_map", "Old Map", "common", "parchment", nil),
  sleeve("moss_garden", "Moss Garden", "common", "parchment", {"1a2a08", "c8e070"}),
  sleeve("midnight_vessel", "Midnight Vessel", "rare", "parchment", {"0a0e2a", "e8c860"}),
}

SL.RETIRED = {
  crimson_crest = true, azure_crest = true, teal_crest = true, gilded_slate = true, silver_filigree = true, duel_crest = true,
  emerald_crest = true, snowfall = true, twin_moons = true, frost_crest = true, rose_crest = true, lilac_crest = true,
  rose_diamonds = true, checkerboard = true, pink_lightning = true, firebrand = true,
}

function SL.art()
  local out = {}
  for i, s in ipairs(SL.LIST) do
    out[#out + 1] = {id = s.id, name = s.name, rarity = s.rarity, atlas = "tavern_sleeves", pos = {x = (i - 1) % SL.COLS, y = math.floor((i - 1) / SL.COLS)}}
  end
  return out
end

local function rgb(hex)
  return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

local function stamp(dst, src, dx, dy, sx, sy, w, h)
  local dw, dh = dst:getDimensions()
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = src:getPixel(sx + x, sy + y)
      local tx, ty = dx + x, dy + y
      if a > 0 and tx >= 0 and ty >= 0 and tx < dw and ty < dh then
        local br, bg, bb, ba = dst:getPixel(tx, ty)
        dst:setPixel(tx, ty, r * a + br * (1 - a), g * a + bg * (1 - a), b * a + bb * (1 - a), math.max(a, ba))
      end
    end
  end
end

local function luma(r, g, b) return 0.3 * r + 0.59 * g + 0.11 * b end

local function range_of(data, x, y, w, h)
  local lo, hi = 1, 0
  data:mapPixel(function(_, _, r, g, b, a)
    if a > 0 then
      local l = luma(r, g, b)
      if l < 0.97 then lo, hi = math.min(lo, l), math.max(hi, l) end
    end
    return r, g, b, a
  end, x, y, w, h)
  if hi - lo < 0.05 then return 0, 1 end
  return lo, hi
end

local function tone_fn(tone, lo, hi)
  local dr, dg, db = rgb(tone[1])
  local lr, lg, lb = rgb(tone[2])
  return function(r, g, b)
    local l = luma(r, g, b)
    if l >= 0.97 then return r, g, b end
    l = math.min(1, math.max(0, (l - lo) / (hi - lo)))
    return dr + (lr - dr) * l, dg + (lg - dg) * l, db + (lb - db) * l
  end
end

local function ink_box(data, x, y, w, h)
  local x0, y0, x1, y1
  data:mapPixel(function(px, py, r, g, b, a)
    if a > 0.5 then
      x0, x1 = math.min(x0 or px, px), math.max(x1 or px, px)
      y0, y1 = math.min(y0 or py, py), math.max(y1 or py, py)
    end
    return r, g, b, a
  end, x, y, w, h)
  return x0, y0, x1, y1
end

local function stamp_centred(dst, src, cx, cy, sx, sy, w, h)
  local x0, y0, x1, y1 = ink_box(src, sx, sy, w, h)
  if not x0 then return end
  local bw, bh = x1 - x0 + 1, y1 - y0 + 1
  stamp(dst, src, cx - math.floor(bw / 2), cy - math.floor(bh / 2), x0, y0, bw, bh)
end

function SL.coat(data, ox, oy, s)
  local cw, ch = W * s, H * s
  local cut = SL.CUT * s
  data:mapPixel(function(_, y, r, g, b, a)
    local ry = y - oy
    if ry < cut - s then return r, g, b, 0 end
    if ry < cut then return 0.05, 0.04, 0.08, a > 0 and 0.4 or 0 end
    if ry < cut + s then return math.min(1, r * 0.55 + 0.45), math.min(1, g * 0.55 + 0.45), math.min(1, b * 0.55 + 0.45), a end
    if ry < cut + 3 * s then return r * 0.6, g * 0.6, b * 0.6, a end
    return r, g, b, a
  end, ox, oy, cw, ch)
end

function SL.coat_all(data, s)
  local cw, ch = W * s, H * s
  local cols, rows = math.floor(data:getWidth() / cw), math.floor(data:getHeight() / ch)
  for cy = 0, rows - 1 do
    for cx = 0, cols - 1 do SL.coat(data, cx * cw, cy * ch, s) end
  end
  return data
end

function SL.build(s)
  local base = "resources/textures/" .. s .. "x/"
  local enh = love.image.newImageData(base .. "Enhancers.png")
  local cw, ch = W * s, H * s
  local rows = math.ceil(#SL.LIST / SL.COLS)
  local out = love.image.newImageData(cw * SL.COLS, ch * rows)
  local mid = math.floor((SL.CUT + (H - SL.CUT) / 2) * s)
  for i, sl in ipairs(SL.LIST) do
    local ox, oy = ((i - 1) % SL.COLS) * cw, math.floor((i - 1) / SL.COLS) * ch
    local m = MAT[sl.mat]
    out:paste(enh, ox, oy, m[1] * cw, m[2] * ch, cw, ch)
    out:mapPixel(function(_, _, r, g, b, a)
      if a <= 0 then return r, g, b, a end
      return r * a + 0.16 * (1 - a), g * a + 0.2 * (1 - a), b * a + 0.24 * (1 - a), 1
    end, ox, oy, cw, ch)
    if sl.tone then
      local fn = tone_fn(sl.tone, range_of(out, ox, oy, cw, ch))
      out:mapPixel(function(_, _, r, g, b, a)
        if a <= 0 then return r, g, b, a end
        local nr, ng, nb = fn(r, g, b)
        return nr, ng, nb, a
      end, ox, oy, cw, ch)
    end
    local e = sl.emblem or {}
    if e.seal then
      stamp_centred(out, enh, ox + math.floor(cw / 2), oy + mid, e.seal[1] * cw, e.seal[2] * ch, cw, ch)
    end
    SL.coat(out, ox, oy, s)
  end
  enh:release()
  return out
end

return SL
