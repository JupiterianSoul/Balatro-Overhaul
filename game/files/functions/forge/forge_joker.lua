local Store = require("functions/forge/forge_store")
local Rules = require("functions/forge/forge_rules")

local FJ = {}

FJ.PREFIX = "j_forge_"
FJ.LOST = "j_forge_lost"
FJ.ORDER = 3000
FJ.MOD = {id = "JokerForge", name = "The Forge", display_name = "The Forge", prefix = "forge", can_load = true, config = {}}
FJ.text_for = nil
FJ.vars_for = nil
FJ.atlas_cache = {}
FJ.warned = {}

local function log_once(key, msg)
  if FJ.warned[key] then return end
  FJ.warned[key] = true
  print("[FORGE] " .. tostring(msg))
end
FJ.log_once = log_once

function FJ.key_of(id) return FJ.PREFIX .. tostring(id) end

function FJ.id_of(key)
  if type(key) ~= "string" or key:sub(1, #FJ.PREFIX) ~= FJ.PREFIX then return nil end
  local id = key:sub(#FJ.PREFIX + 1)
  if id == "lost" then return nil end
  return id
end

function FJ.lang()
  local l = G and G.SETTINGS and G.SETTINGS.language or "en-us"
  if l == "fr" then return "fr" end
  if type(l) == "string" and l:sub(1, 2) == "es" then return "es" end
  return "en"
end

local function scale_setting()
  local s = G and G.SETTINGS and G.SETTINGS.GRAPHICS and G.SETTINGS.GRAPHICS.texture_scaling
  return (s and s > 1) and 2 or 1
end

function FJ.doubled(data)
  local w, h = data:getDimensions()
  local out = love.image.newImageData(w * 2, h * 2)
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = data:getPixel(x, y)
      out:setPixel(x * 2, y * 2, r, g, b, a)
      out:setPixel(x * 2 + 1, y * 2, r, g, b, a)
      out:setPixel(x * 2, y * 2 + 1, r, g, b, a)
      out:setPixel(x * 2 + 1, y * 2 + 1, r, g, b, a)
    end
  end
  return out
end

function FJ.atlas_from_data(name, data)
  if not (data and G and G.ASSET_ATLAS) then return nil end
  local s = scale_setting()
  local src = s == 2 and FJ.doubled(data) or data
  local ok, img = pcall(love.graphics.newImage, src, {mipmaps = true, dpiscale = s})
  if not ok or not img then return nil end
  local filter = (s == 1 or (G.SETTINGS.GRAPHICS.perf_texture_filter == 2)) and "nearest" or "linear"
  pcall(img.setFilter, img, filter, filter)
  local old = G.ASSET_ATLAS[name]
  local atlas = old or {name = name, px = 71, py = 95, type = "asset_atli"}
  atlas.image = img
  atlas.px, atlas.py = 71, 95
  G.ASSET_ATLAS[name] = atlas
  FJ.atlas_cache[name] = data
  return atlas
end

local function load_art(c)
  local a = c.art or {}
  if a.file then
    local name = "forge_" .. c.id
    local ok, data = pcall(love.image.newImageData, a.file)
    if ok and data then
      local w, h = data:getDimensions()
      if w == 71 and h == 95 then
        if FJ.atlas_from_data(name, data) then return name, {x = 0, y = 0} end
      else
        log_once("size_" .. c.id, "art for " .. c.id .. " is " .. w .. "x" .. h .. ", not 71x95")
      end
    else
      log_once("art_" .. c.id, "could not read art " .. tostring(a.file))
    end
    return "Joker", {x = 0, y = 0}
  end
  if a.atlas and G.ASSET_ATLAS and G.ASSET_ATLAS[a.atlas] then return a.atlas, {x = a.x or 0, y = a.y or 0} end
  return "Joker", {x = 0, y = 0}
end

local function badge_colours()
  FJ.MOD.name = mod_loc and mod_loc("The Forge") or "The Forge"
  FJ.MOD.display_name = FJ.MOD.name
  FJ.MOD.badge_colour = G.C and (G.C.SECONDARY_SET and G.C.SECONDARY_SET.Spectral or G.C.PURPLE) or {0.3, 0.4, 0.8, 1}
  FJ.MOD.badge_text_colour = G.C and G.C.WHITE or {1, 1, 1, 1}
end

local function base_center(key, name, order)
  return {
    key = key, order = order, unlocked = true, discovered = true, alerted = true, set = "Joker", effect = "", cost_mult = 1.0,
    name = name, rarity = 1, cost = 4, pos = {x = 0, y = 0}, atlas = "Joker", config = {extra = {chips = 0, mult = 0, xmult = 1}},
    blueprint_compat = true, eternal_compat = true, perishable_compat = true, mod = FJ.MOD, forge = true,
  }
end

function FJ.center_for(c, index)
  local key = FJ.key_of(c.id)
  local center = G.P_CENTERS[key]
  if not center then
    center = base_center(key, "Forge " .. c.id, FJ.ORDER + (index or 1))
    G.P_CENTERS[key] = center
  end
  center.order = FJ.ORDER + (index or 1)
  center.name = "Forge " .. c.id
  center.rarity = c.rarity
  center.cost = c.cost
  center.forge_id = c.id
  center.forge_on = c.enabled
  center.mod = c.forge_mod or FJ.MOD
  center.forge_mod_badge = c.mod_id and ("forge_mod_" .. c.mod_id) or nil
  local cp = type(c.compat) == "table" and c.compat or {}
  center.blueprint_compat = cp.blueprint ~= false
  center.eternal_compat = cp.eternal ~= false
  center.perishable_compat = cp.perishable ~= false
  local atlas, pos = load_art(c)
  center.atlas = atlas
  center.pos = pos
  return center
end

local function lost_center()
  if G.P_CENTERS[FJ.LOST] then return G.P_CENTERS[FJ.LOST] end
  local c = base_center(FJ.LOST, "Lost joker", FJ.ORDER)
  c.forge_lost = true
  c.no_collection = true
  G.P_CENTERS[FJ.LOST] = c
  return c
end

local function pool_has(pool, center)
  for i, v in ipairs(pool) do if v == center then return i end end
  return nil
end

local function sort_pool(pool)
  table.sort(pool, function(a, b)
    local oa, ob = a.order or 9999, b.order or 9999
    if oa ~= ob then return oa < ob end
    return tostring(a.key) < tostring(b.key)
  end)
end

function FJ.allowed_here()
  local R = rawget(_G, "ForgeRoom")
  if R and R.sync then R.sync() end
  local FL = rawget(_G, "FairLock")
  local okc, ctx = pcall(function() return FL and FL.context and FL.context() end)
  if okc and (ctx == "ranked" or ctx == "speedrun") then return false end
  local mp = G and G.GAME and G.GAME.multiplayer and true or false
  local M = rawget(_G, "bom_match") or package.loaded["multiplayer.bom_match"] or package.loaded["multiplayer/bom_match"]
  if not mp and M and M.get_phase then
    local ok, ph = pcall(M.get_phase)
    if ok and ph and ph ~= "none" and ph ~= "lobby" then mp = true end
  end
  if mp or ctx == "mp" then return R and R.active and R.active() and not R.ranked() or false end
  if R and R.active and R.active() then return true end
  if FL and FL.blocks and FL.blocks("forge_creations") then return false end
  return true
end

function FJ.sync_pools()
  if not (G and G.P_CENTERS and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Joker and G.P_JOKER_RARITY_POOLS) then return end
  local here = FJ.allowed_here()
  local touched = {}
  local live = {}
  for _, c in ipairs(Store.live_jokers()) do live[FJ.key_of(c.id)] = c end
  for key, center in pairs(G.P_CENTERS) do
    if center.forge and not center.forge_lost then
      local c = live[key]
      local on = c and c.enabled and here or false
      for _, pool in ipairs({G.P_CENTER_POOLS.Joker, G.P_JOKER_RARITY_POOLS[center.rarity]}) do
        local i = pool_has(pool, center)
        if on and not i then
          pool[#pool + 1] = center
          touched[pool] = true
        elseif not on and i then
          table.remove(pool, i)
        end
      end
      for r = 1, 4 do
        local pool = G.P_JOKER_RARITY_POOLS[r]
        if pool and r ~= center.rarity then
          local i = pool_has(pool, center)
          if i then table.remove(pool, i) end
        end
      end
    end
  end
  for pool in pairs(touched) do sort_pool(pool) end
end

local function clone(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = clone(x) end
  return t
end

local function parsed(entry)
  local e = {name = entry.name, text = clone(entry.text or {})}
  if loc_parse_string then
    e.text_parsed = {}
    for _, line in ipairs(e.text) do e.text_parsed[#e.text_parsed + 1] = loc_parse_string(line) end
    e.name_parsed = {}
    for _, line in ipairs(type(e.name) == "table" and e.name or {e.name}) do e.name_parsed[#e.name_parsed + 1] = loc_parse_string(line) end
  end
  return e
end

FJ.parsed = parsed
FJ.load_art = load_art

function FJ.lines_for(c)
  if FJ.text_for then
    local ok, lines = pcall(FJ.text_for, c, FJ.lang())
    if ok and type(lines) == "table" and #lines > 0 then return lines end
    if not ok then log_once("text_" .. c.id, "text failed for " .. c.id .. ": " .. tostring(lines)) end
  end
  return {mod_loc and mod_loc("Does nothing yet") or "Does nothing yet"}
end

function FJ.inject_loc(only)
  if not (G and G.localization and G.localization.descriptions) then return end
  badge_colours()
  local d = G.localization.descriptions
  d.Joker = d.Joker or {}
  for _, c in ipairs(Store.live_jokers()) do
    if not only or only == c.id then
      d.Joker[FJ.key_of(c.id)] = parsed({name = c.name, text = FJ.lines_for(c)})
    end
  end
  if G.P_CENTERS and G.P_CENTERS[FJ.LOST] then d.Joker[FJ.LOST] = parsed({name = mod_loc and mod_loc("Lost joker") or "Lost joker", text = {mod_loc and mod_loc("This creation was deleted") or "This creation was deleted"}}) end
end

function FJ.set_loc(key, name, lines)
  if not (G and G.localization and G.localization.descriptions) then return end
  local d = G.localization.descriptions
  d.Joker = d.Joker or {}
  d.Joker[key] = parsed({name = name, text = lines})
end

function FJ.register_all()
  if not (G and G.P_CENTERS) then return end
  badge_colours()
  local live = {}
  for i, c in ipairs(Store.live_jokers()) do
    FJ.center_for(c, i)
    live[FJ.key_of(c.id)] = true
  end
  for key, center in pairs(G.P_CENTERS) do
    if center.forge and not center.forge_lost and not live[key] then center.forge_on = false end
  end
  FJ.inject_loc()
  FJ.sync_pools()
end

function FJ.refresh(id)
  local list = Store.live_jokers()
  for i, c in ipairs(list) do
    if c.id == id then
      FJ.center_for(c, i)
      FJ.inject_loc(id)
    end
  end
  FJ.sync_pools()
end

function FJ.center_of(id)
  return G and G.P_CENTERS and G.P_CENTERS[FJ.key_of(id)] or nil
end

function FJ.install_hooks()
  if FJ.hooked then return end
  FJ.hooked = true
  if Game and Game.init_item_prototypes then
    local orig = Game.init_item_prototypes
    Game.init_item_prototypes = function(self, ...)
      local r = orig(self, ...)
      local ok, err = pcall(FJ.register_all)
      if not ok then log_once("register", "register failed: " .. tostring(err)) end
      return r
    end
  end
  if type(init_localization) == "function" then
    local orig = init_localization
    init_localization = function(...)
      local r = orig(...)
      pcall(FJ.inject_loc)
      return r
    end
  end
  if type(get_current_pool) == "function" then
    local orig = get_current_pool
    get_current_pool = function(...)
      pcall(FJ.sync_pools)
      return orig(...)
    end
  end
  if Card and Card.calculate_joker then
    local orig = Card.calculate_joker
    Card.calculate_joker = function(self, context)
      local center = self.config and self.config.center
      if center and center.forge then
        if self.debuff or center.forge_lost then return nil end
        local c = Store.get(center.forge_id)
        if not (c and c.rules and #c.rules > 0) then return nil end
        local ok, r = pcall(Rules.calculate, self, context, c.rules, c.vars)
        if ok then return r end
        log_once("calc_" .. tostring(center.forge_id), "joker " .. tostring(center.key) .. " failed: " .. tostring(r))
        return nil
      end
      return orig(self, context)
    end
  end
  if Card and Card.generate_UIBox_ability_table then
    local orig = Card.generate_UIBox_ability_table
    Card.generate_UIBox_ability_table = function(self, ...)
      local center = self.config and self.config.center
      if center and center.forge and not center.forge_lost then
        FJ.describing = self
        local ok, r = pcall(orig, self, ...)
        FJ.describing = nil
        if ok then return r end
        log_once("ui_" .. tostring(center.key), "card text failed: " .. tostring(r))
        return orig(self, ...)
      end
      return orig(self, ...)
    end
  end
  if type(generate_card_ui) == "function" then
    local orig = generate_card_ui
    generate_card_ui = function(_c, full_UI_table, specific_vars, ...)
      if _c and _c.forge and specific_vars == nil and FJ.vars_for then
        local card = FJ.describing
        local ok, v = pcall(FJ.vars_for, _c, card)
        if ok and type(v) == "table" then specific_vars = v end
      end
      return orig(_c, full_UI_table, specific_vars, ...)
    end
  end
  if Card and Card.load then
    local orig = Card.load
    Card.load = function(self, cardTable, other_card)
      pcall(function()
        local sf = cardTable and cardTable.save_fields
        local key = sf and sf.center
        if type(key) == "string" and key:sub(1, #FJ.PREFIX) == FJ.PREFIX and not G.P_CENTERS[key] then
          lost_center()
          FJ.inject_loc()
          sf.center = FJ.LOST
        end
      end)
      return orig(self, cardTable, other_card)
    end
  end
  if G and G.P_CENTERS and next(G.P_CENTERS) then pcall(FJ.register_all) end
end

return FJ
