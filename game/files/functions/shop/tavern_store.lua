local C = require("functions/shop/tavern_catalog")
local ok_art, ART = pcall(require, "functions/shop/tavern_art")
if not ok_art or type(ART) ~= "table" then ART = {} end

local SL = require("functions/shop/tavern_sleeves")

local S = {catalog = C, art = ART}

local function release_art_on()
  return rawget(_G, "RELEASE_BUILD") == true or (os and os.getenv and os.getenv("BOM_RELEASE_ART") == "1")
end

local function backs()
  local out = {}
  if not release_art_on() then
    for _, b in ipairs(ART.backs or {}) do
      if not SL.RETIRED[b.id] then out[#out + 1] = b end
    end
  end
  for _, b in ipairs(SL.art()) do out[#out + 1] = b end
  return out
end

local cache = {list = nil, by_id = nil, key = nil}

local function profile()
  if not (G and G.PROFILES and G.SETTINGS and G.SETTINGS.profile) then return nil end
  local p = G.PROFILES[G.SETTINGS.profile]
  if not p then return nil end
  p.progression = p.progression or {}
  return p
end

function S.state()
  local p = profile()
  if not p then return nil end
  local t = p.progression.tavern
  if type(t) ~= "table" then
    t = {}
    p.progression.tavern = t
  end
  t.owned = t.owned or {}
  t.equipped = t.equipped or {}
  t.since_legendary = t.since_legendary or 0
  t.opened = t.opened or 0
  t.cards = t.cards or 0
  return t
end

local function save()
  pcall(function() if G and G.save_progress then G:save_progress() end end)
end

local function discovered_jokers()
  local out = {}
  local pool = G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Joker
  if not pool then return out end
  for _, c in ipairs(pool) do
    if c.key and c.discovered and c.key ~= "j_joker" and not c.no_collection then
      local nm = c.name
      pcall(function()
        local d = G.localization.descriptions.Joker[c.key]
        if d and d.name then nm = d.name end
      end)
      out[#out + 1] = {key = c.key, name = nm or c.key, rarity = math.min(4, math.max(1, tonumber(c.rarity) or 1)), pos = c.pos, atlas = c.atlas}
    end
  end
  return out
end

local function deck_names()
  local out = {}
  local function name_of(id)
    local info = ProfileRewardsManager and ProfileRewardsManager.get_deck_unlock_info and ProfileRewardsManager.get_deck_unlock_info(id)
    return info and info.name or id
  end
  for id in pairs(C.SHOP_DECKS) do out[id] = name_of(id) end
  return out
end

function S.env()
  local poly = rawget(_G, "SHOP_POLYCHROMATIC") ~= nil
  return {
    color_sets = rawget(_G, "SHOP_COLOR_SETS") or {},
    polychromatic = poly,
    effects = rawget(_G, "SHOP_ICON_EFFECTS") or {},
    jokers = discovered_jokers(),
    titles = rawget(_G, "TITLES") or {},
    portraits = ART.portraits or {},
    backs = backs(),
    decks = deck_names(),
  }
end

function S.invalidate() cache.list = nil end

function S.list()
  if not cache.list then cache.list, cache.by_id = C.build(S.env()) end
  return cache.list, cache.by_id
end

function S.get(id)
  local _, by_id = S.list()
  return by_id[id]
end

local function in_list(list, v)
  if type(list) ~= "table" then return false end
  for _, x in ipairs(list) do if x == v then return true end end
  return false
end

function S.owns(it)
  if not it then return false end
  local p = profile()
  if not p then return false end
  local pr = p.progression
  local t = it.type
  if t == "palette" then return in_list(pr.owned_color_sets, it.key)
  elseif t == "effect" then return in_list(pr.owned_icon_effects, it.key)
  elseif t == "jimbo" then return it.key == "j_joker" or in_list(pr.owned_jimbo_skins, it.key)
  elseif t == "title" then return in_list(pr.unlocked_titles, it.key)
  elseif t == "deck" then return in_list(pr.unlocked_decks, it.key)
  end
  local st = S.state()
  return st and st.owned[it.id] == true or false
end

local function push(pr, field, v)
  pr[field] = pr[field] or {}
  local list = pr[field]
  if in_list(list, v) then return end
  list[#list + 1] = v
  list._set = nil
end

function S.grant(it)
  local p = profile()
  if not p or not it then return false end
  local pr = p.progression
  local t = it.type
  if t == "palette" then
    push(pr, "owned_color_sets", it.key)
    pcall(function()
      if it.key ~= "polychromatic" and AshCardManager and AshCardManager.owns_all_color_sets() then push(pr, "owned_color_sets", "polychromatic") end
    end)
  elseif t == "effect" then push(pr, "owned_icon_effects", it.key)
  elseif t == "jimbo" then push(pr, "owned_jimbo_skins", it.key)
  elseif t == "title" then push(pr, "unlocked_titles", it.key)
  elseif t == "deck" then push(pr, "unlocked_decks", it.key)
  else
    local st = S.state()
    st.owned[it.id] = true
  end
  return true
end

function S.balance()
  if ShopManager and ShopManager.get_balance then return ShopManager.get_balance() end
  local p = profile()
  return p and p.progression.balacoin or 0
end

local function spend(n)
  if ShopManager and ShopManager.spend_balacoin then return ShopManager.spend_balacoin(n) end
  local p = profile()
  if not p or (p.progression.balacoin or 0) < n then return false end
  p.progression.balacoin = p.progression.balacoin - n
  return true
end

local function credit(n)
  local p = profile()
  if not p or n <= 0 then return end
  p.progression.balacoin = (p.progression.balacoin or 0) + n
  p.progression.total_balacoin_earned = (p.progression.total_balacoin_earned or 0) + n
end

function S.rand()
  if love and love.math and love.math.random then return love.math.random() end
  return math.random()
end

function S.can_open(pack)
  return pack and S.balance() >= pack.price
end

function S.open(pack_id, rand)
  local pack = C.PACK_BY_ID[pack_id]
  if not pack then return nil, "unknown" end
  local st = S.state()
  if not st then return nil, "profile" end
  if S.balance() < pack.price then return nil, "money" end
  S.invalidate()
  local list = S.list()
  local got, nst = C.roll_pack(pack, list, rand or S.rand, S.owns, {since_legendary = st.since_legendary})
  if #got == 0 then return nil, "empty" end
  if not spend(pack.price) then return nil, "money" end
  local out, refund = {}, 0
  for i, it in ipairs(got) do
    local dupe = S.owns(it)
    local r = {item = it, dupe = dupe, refund = 0, slot = i}
    if dupe then
      r.refund = C.refund(it.rarity)
      refund = refund + r.refund
    else
      S.grant(it)
    end
    out[#out + 1] = r
  end
  credit(refund)
  st.since_legendary = nst.since_legendary or 0
  st.opened = st.opened + 1
  st.cards = st.cards + #out
  st.last_pack = pack_id
  save()
  return {pack = pack, cards = out, refund = refund, price = pack.price}
end

function S.pool_size(pack)
  local n = 0
  for _, b in pairs(C.pool_for(pack, S.list())) do n = n + #b end
  return n
end

function S.pack_progress(pack)
  local have, all = 0, 0
  for _, b in pairs(C.pool_for(pack, S.list())) do
    for _, it in ipairs(b) do
      all = all + 1
      if S.owns(it) then have = have + 1 end
    end
  end
  return have, all
end

function S.pity_left()
  local st = S.state()
  return math.max(1, C.PITY - (st and st.since_legendary or 0))
end

function S.equipped(type_key)
  local p = profile()
  if not p then return nil end
  local pr = p.progression
  if type_key == "palette" then return TAVERN_PALETTES.resolve(pr.equipped_color_set)
  elseif type_key == "effect" then return pr.equipped_icon_effect
  elseif type_key == "jimbo" then return pr.equipped_jimbo_skin or "j_joker"
  elseif type_key == "title" then return pr.equipped_title
  end
  local st = S.state()
  local key = st and st.equipped[type_key] or nil
  if key and not S.get(type_key .. ":" .. key) then return nil end
  return key
end

function S.is_equipped(it)
  return it and S.equipped(it.type) == it.key
end

function S.equip(it)
  if not it or not S.owns(it) then return false end
  local p = profile()
  local pr = p.progression
  local t = it.type
  if t == "palette" then
    pr.equipped_color_set = it.key
    pcall(function() if apply_color_set then apply_color_set(it.key) end end)
  elseif t == "effect" then pr.equipped_icon_effect = it.key
  elseif t == "jimbo" then pr.equipped_jimbo_skin = it.key
  elseif t == "title" then
    pr.equipped_title = it.key
    local SC = rawget(_G, "BO_SHOWCASE")
    if SC and SC.data then SC.data().t = "c:" .. it.key end
  elseif t == "deck" then return false
  else
    S.state().equipped[t] = it.key
  end
  save()
  if S.on_equip then pcall(S.on_equip, it) end
  return true
end

function S.unequip(type_key)
  local p = profile()
  if not p then return false end
  local pr = p.progression
  if type_key == "palette" then
    pr.equipped_color_set = nil
    pcall(function() if reset_colors_to_default then reset_colors_to_default() end end)
  elseif type_key == "effect" then pr.equipped_icon_effect = nil
  elseif type_key == "jimbo" then pr.equipped_jimbo_skin = "j_joker"
  elseif type_key == "title" then
    pr.equipped_title = nil
    local SC = rawget(_G, "BO_SHOWCASE")
    if SC and SC.data then SC.data().t = "" end
  else S.state().equipped[type_key] = nil end
  save()
  if S.on_equip then pcall(S.on_equip, {type = type_key}) end
  return true
end

function S.counts(type_key)
  local list = S.list()
  local have, all = 0, 0
  for _, it in ipairs(list) do
    if not type_key or it.type == type_key then
      all = all + 1
      if S.owns(it) then have = have + 1 end
    end
  end
  return have, all
end

function S.items(type_key)
  local list = S.list()
  local out = {}
  for _, it in ipairs(list) do
    if it.type == type_key then out[#out + 1] = it end
  end
  return out
end

function S.def(type_key, key)
  if not key then return nil end
  local it = S.get(type_key .. ":" .. key)
  return it and (it.def or it) or nil
end

return S
