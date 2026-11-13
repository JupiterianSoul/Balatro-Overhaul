local S = require("functions/shop/tavern_store")

local R = {last = {}}

R.SLOTS = {
  {key = "portrait", types = {"portrait", "icon"}},
  {key = "effect", types = {"effect"}},
  {key = "title", types = {"title"}},
  {key = "palette", types = {"palette"}},
  {key = "felt", types = {"felt"}},
  {key = "back", types = {"back"}},
  {key = "flame", types = {"flame"}},
  {key = "celebration", types = {"celebration"}},
  {key = "jimbo", types = {"jimbo"}},
}

local BY_KEY, OF_TYPE = {}, {}
for _, s in ipairs(R.SLOTS) do
  BY_KEY[s.key] = s
  for _, t in ipairs(s.types) do OF_TYPE[t] = s.key end
end

local function ui() return require("functions/shop/tavern_custom_ui") end

local function save()
  pcall(function() if G and G.save_progress then G:save_progress() end end)
end

function R.slot_of(it)
  if not it then return nil end
  if it.random or it.none then return BY_KEY[it.type] and it.type or nil end
  return OF_TYPE[it.type]
end

function R.on(slot)
  local st = S.state()
  return st ~= nil and type(st.random) == "table" and st.random[slot] == true
end

function R.any_on()
  local st = S.state()
  return st ~= nil and type(st.random) == "table" and next(st.random) ~= nil
end

function R.set(slot, on)
  local st = S.state()
  if not st or not BY_KEY[slot] then return false end
  if type(st.random) ~= "table" then st.random = {} end
  st.random[slot] = on and true or nil
  save()
  return true
end

function R.banned(slot, id)
  local st = S.state()
  local b = st and type(st.random_bans) == "table" and st.random_bans[slot]
  return type(b) == "table" and b[id] == true
end

function R.set_banned(slot, id, on)
  local st = S.state()
  if not st or not BY_KEY[slot] or not id then return false end
  if type(st.random_bans) ~= "table" then st.random_bans = {} end
  local b = st.random_bans
  if on then
    if type(b[slot]) ~= "table" then b[slot] = {} end
    b[slot][id] = true
  elseif type(b[slot]) == "table" then
    b[slot][id] = nil
    if next(b[slot]) == nil then b[slot] = nil end
  end
  save()
  return true
end

function R.owned(slot)
  local V = ui()
  local out = {V.default_item(slot)}
  for _, t in ipairs(BY_KEY[slot].types) do
    local list = t == "icon" and V.won_icons() or S.items(t)
    for _, it in ipairs(list) do
      if V.owns(it) then out[#out + 1] = it end
    end
  end
  return out
end

function R.pool(slot)
  local all = R.owned(slot)
  local out = {}
  for _, it in ipairs(all) do
    if not R.banned(slot, it.id) then out[#out + 1] = it end
  end
  return out, #all
end

function R.current(slot)
  local V = ui()
  for _, it in ipairs(R.owned(slot)) do
    if V.equipped_raw(it) then return it end
  end
  return nil
end

function R.roll(slot, rand)
  local pool = R.pool(slot)
  if #pool == 0 then return nil end
  local cur = R.current(slot)
  if #pool > 1 and cur then
    for i, it in ipairs(pool) do
      if it.id == cur.id then table.remove(pool, i) break end
    end
  end
  local it = pool[math.min(#pool, math.floor((rand or S.rand)() * #pool) + 1)]
  if cur and cur.id == it.id then return it end
  ui().equip(it, true)
  return it
end

function R.roll_all(rand)
  local out = {}
  if not R.any_on() then R.last = out return out end
  S.invalidate()
  for _, s in ipairs(R.SLOTS) do
    if R.on(s.key) then
      local ok, it = pcall(R.roll, s.key, rand)
      out[s.key] = ok and it and it.id or false
    end
  end
  R.last = out
  return out
end

if Game and Game.start_run and not R._wrapped then
  R._wrapped = true
  local orig = Game.start_run
  Game.start_run = function(self, args, ...)
    if not (args and args.savetext) then pcall(R.roll_all) end
    return orig(self, args, ...)
  end
end

return R
