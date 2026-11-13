local json = require("bot.sim.json")
local Rules = require("functions/forge/forge_rules")

local S = {}

S.DIR = "forge"
S.ART_DIR = "forge/art"
S.IMPORT_DIR = "forge/import"
S.FILE = "forge/jokers.json"
S.SETTINGS_FILE = "forge/settings.json"
S.VERSION = 1
S.MAX_NAME = 24

S.list = nil
S.settings = nil
S.room = nil

local function fs() return rawget(_G, "love") and love.filesystem end

local function write(path, data)
  local ok, F = pcall(require, "functions/fast_fs")
  if ok and F and F.write then return F.write(path, data) end
  local f = fs()
  return f and f.write(path, data) or false
end

local function ensure_dirs()
  local f = fs()
  if not f then return end
  if not f.getInfo(S.DIR) then f.createDirectory(S.DIR) end
  if not f.getInfo(S.ART_DIR) then f.createDirectory(S.ART_DIR) end
  if not f.getInfo(S.IMPORT_DIR) then f.createDirectory(S.IMPORT_DIR) end
end
S.ensure_dirs = ensure_dirs

local function read_json(path)
  local f = fs()
  if not (f and f.getInfo(path)) then return nil end
  local raw = f.read(path)
  if type(raw) ~= "string" or raw == "" then return nil end
  local ok, data = pcall(json.decode, raw)
  if ok and type(data) == "table" then return data end
  return nil
end

local function clamp(v, lo, hi, def)
  v = tonumber(v)
  if not v then return def end
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

function S.clean_text(t)
  if type(t) ~= "table" then return nil end
  local out, any = {}, false
  for _, l in ipairs({"en", "fr", "es"}) do
    if type(t[l]) == "table" then
      local lines = {}
      for _, line in ipairs(t[l]) do
        if type(line) == "string" and #lines < 6 then lines[#lines + 1] = line:gsub("%c", ""):sub(1, 80) end
      end
      if #lines > 0 then out[l] = lines; any = true end
    end
  end
  return any and out or nil
end

function S.clean(c)
  if type(c) ~= "table" then return nil end
  local id = tostring(c.id or ""):gsub("[^%w]", "")
  if id == "" then return nil end
  local out = {
    id = id:sub(1, 16),
    v = S.VERSION,
    name = tostring(c.name or ""):gsub("%c", ""):sub(1, S.MAX_NAME),
    rarity = math.floor(clamp(c.rarity, 1, 4, 1)),
    cost = math.floor(clamp(c.cost, 1, 20, 4)),
    enabled = c.enabled ~= false,
    rules = Rules.clean_rules(c.rules),
    vars = Rules.clean_vars(c.vars),
    text = S.clean_text(c.text),
    created = tonumber(c.created) or 0,
    art = nil,
    mode = c.mode == "advanced" and "advanced" or "simple",
    compat = {blueprint = not (type(c.compat) == "table" and c.compat.blueprint == false), eternal = not (type(c.compat) == "table" and c.compat.eternal == false), perishable = not (type(c.compat) == "table" and c.compat.perishable == false)},
  }
  local a = type(c.art) == "table" and c.art or {}
  if type(a.file) == "string" and a.file:match("^forge/art/[%w_]+%.png$") then
    out.art = {file = a.file}
  elseif type(a.atlas) == "string" then
    out.art = {atlas = a.atlas, x = math.floor(clamp(a.x, 0, 99, 0)), y = math.floor(clamp(a.y, 0, 99, 0))}
  else
    out.art = {atlas = "Joker", x = 0, y = 0}
  end
  if out.name == "" then out.name = "Joker" end
  if type(c.requires) == "string" and c.requires:match("^v_[%w_]+$") and #c.requires <= 40 then out.requires = c.requires end
  return out
end

function S.load()
  local data = read_json(S.FILE)
  local list = {}
  local seen = {}
  for _, c in ipairs(type(data) == "table" and type(data.jokers) == "table" and data.jokers or {}) do
    local clean = S.clean(c)
    if clean and not seen[clean.id] then
      seen[clean.id] = true
      list[#list + 1] = clean
    end
  end
  S.list = list
  return list
end

function S.all()
  if not S.list then S.load() end
  return S.list
end

local function extra(which)
  local E = S.extra
  local list = E and E[which]
  return type(list) == "table" and #list > 0 and list or nil
end

local function joined(own, more)
  if not more then return own end
  local out = {}
  for _, c in ipairs(own) do out[#out + 1] = c end
  for _, c in ipairs(more) do out[#out + 1] = c end
  return out
end

local function in_room(which, id)
  local R = S.room
  for _, c in ipairs(R and R[which] or {}) do
    if c.id == id then return c end
  end
  return nil
end

function S.get(id)
  local r = in_room("jokers", id)
  if r then return r end
  for _, c in ipairs(S.all()) do
    if c.id == id then return c end
  end
  for _, c in ipairs(extra("jokers") or {}) do
    if c.id == id then return c end
  end
  return nil
end

function S.base_jokers() return joined(S.all(), extra("jokers")) end
function S.base_items() return joined(S.items(), extra("items")) end

function S.live_jokers()
  if S.room then return S.room.jokers end
  return S.base_jokers()
end

function S.live_items()
  local R = S.room
  if not R then return S.base_items() end
  local out = {}
  for _, c in ipairs(R.items) do out[#out + 1] = c end
  for _, c in ipairs(S.base_items()) do
    if c.kind == "collab" then out[#out + 1] = c end
  end
  return out
end

function S.save()
  ensure_dirs()
  local ok, raw = pcall(json.encode, {v = S.VERSION, jokers = S.all()})
  if not ok then return false end
  return write(S.FILE, raw)
end

local function rand_id()
  local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
  local t = {}
  local seed = (os.time() % 100000) + math.floor((os.clock() * 1000) % 1000)
  for i = 1, 6 do
    local n = (math.random(1, #chars) + seed + i) % #chars + 1
    t[i] = chars:sub(n, n)
  end
  return table.concat(t)
end

function S.new_id()
  for _ = 1, 50 do
    local id = rand_id()
    if not S.find(id) then return id end
  end
  return rand_id() .. tostring(#S.all())
end

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end
S.copy = copy

function S.put(c)
  local clean = S.clean(c)
  if not clean then return nil end
  local list = S.all()
  for i, old in ipairs(list) do
    if old.id == clean.id then
      list[i] = clean
      S.save()
      return clean
    end
  end
  if clean.created == 0 then clean.created = os.time() end
  list[#list + 1] = clean
  S.save()
  return clean
end

function S.set_enabled(id, on)
  local c = S.get(id)
  if not c then return end
  c.enabled = on and true or false
  S.save()
end

function S.art_path(id)
  return S.ART_DIR .. "/" .. id .. ".png"
end

local function copy_file(from, to)
  local f = fs()
  if not (f and f.getInfo(from)) then return false end
  local data = f.read(from)
  if not data then return false end
  return write(to, data)
end

function S.duplicate(id, suffix)
  local c = S.get(id)
  if not c then return nil end
  local d = copy(c)
  d.id = S.new_id()
  d.created = os.time()
  d.name = (tostring(c.name) .. " " .. (suffix or "2")):sub(1, S.MAX_NAME)
  if c.art and c.art.file then
    ensure_dirs()
    local to = S.art_path(d.id)
    if copy_file(c.art.file, to) then d.art = {file = to} else d.art = {atlas = "Joker", x = 0, y = 0} end
  end
  local list = S.all()
  local at = #list + 1
  for i, old in ipairs(list) do if old.id == id then at = i + 1 break end end
  local clean = S.clean(d)
  table.insert(list, at, clean)
  S.save()
  return clean
end

function S.delete(id)
  local list = S.all()
  for i, c in ipairs(list) do
    if c.id == id then
      table.remove(list, i)
      local f = fs()
      if c.art and c.art.file and f and f.getInfo(c.art.file) then pcall(f.remove, c.art.file) end
      S.save()
      return true
    end
  end
  return false
end

function S.get_setting(key, default)
  if not S.settings then S.settings = read_json(S.SETTINGS_FILE) or {} end
  local v = S.settings[key]
  if v == nil then return default end
  return v
end

function S.set_setting(key, value)
  if not S.settings then S.settings = read_json(S.SETTINGS_FILE) or {} end
  if S.settings[key] == value then return end
  S.settings[key] = value
  ensure_dirs()
  local ok, raw = pcall(json.encode, S.settings)
  if ok then write(S.SETTINGS_FILE, raw) end
end

S.ITEMS_FILE = "forge/creations.json"
S.items_list = nil

local function clean_art(a)
  a = type(a) == "table" and a or {}
  if type(a.file) == "string" and a.file:match("^forge/art/[%w_]+%.png$") then return {file = a.file} end
  if type(a.atlas) == "string" then return {atlas = a.atlas, x = math.floor(clamp(a.x, 0, 99, 0)), y = math.floor(clamp(a.y, 0, 99, 0))} end
  return nil
end

function S.clean_faces(f)
  if type(f) ~= "table" then return nil end
  local out, any = {}, false
  for _, r in ipairs({"J", "Q", "K"}) do
    if type(f[r]) == "string" and f[r]:match("^forge/art/[%w_]+%.png$") then out[r] = f[r]; any = true end
  end
  return any and out or nil
end

function S.clean_item(c)
  if type(c) ~= "table" then return nil end
  local Cat = require("functions/forge/forge_catalog")
  if not Cat.BY_ID[c.kind] or c.kind == "joker" then return nil end
  local id = tostring(c.id or ""):gsub("[^%w]", "")
  if id == "" then return nil end
  local out = {
    id = id:sub(1, 16), v = 2, kind = c.kind,
    name = tostring(c.name or ""):gsub("%c", ""):sub(1, S.MAX_NAME),
    mode = c.mode == "advanced" and "advanced" or "simple",
    enabled = c.enabled ~= false,
    created = tonumber(c.created) or 0,
    fields = Cat.clean_fields(c.kind, c.fields),
    effects = Cat.clean_effects(c.kind, c.effects),
    text = S.clean_text(c.text),
    art = clean_art(c.art),
    from = type(c.from) == "string" and c.from:match("^[%w_]+$") and c.from:sub(1, 40) or nil,
    faces = S.clean_faces(c.faces),
  }
  if out.name == "" then out.name = Cat.kind(c.kind).label end
  return out
end

function S.items()
  if S.items_list then return S.items_list end
  local data = read_json(S.ITEMS_FILE)
  local list, seen = {}, {}
  for _, c in ipairs(type(data) == "table" and type(data.creations) == "table" and data.creations or {}) do
    local clean = S.clean_item(c)
    if clean and not seen[clean.id] then
      seen[clean.id] = true
      list[#list + 1] = clean
    end
  end
  S.items_list = list
  return list
end

function S.save_items()
  ensure_dirs()
  local ok, raw = pcall(json.encode, {v = 2, creations = S.items()})
  if not ok then return false end
  return write(S.ITEMS_FILE, raw)
end

function S.get_item(id)
  local r = in_room("items", id)
  if r then return r end
  for _, c in ipairs(S.items()) do if c.id == id then return c end end
  for _, c in ipairs(extra("items") or {}) do if c.id == id then return c end end
  return nil
end

function S.find(id)
  return S.get(id) or S.get_item(id)
end

function S.kind_of(id)
  if S.get(id) then return "joker" end
  local c = S.get_item(id)
  return c and c.kind or nil
end

function S.put_item(c)
  local clean = S.clean_item(c)
  if not clean then return nil end
  local list = S.items()
  for i, old in ipairs(list) do
    if old.id == clean.id then
      list[i] = clean
      S.save_items()
      return clean
    end
  end
  if clean.created == 0 then clean.created = os.time() end
  list[#list + 1] = clean
  S.save_items()
  return clean
end

function S.delete_item(id)
  local list = S.items()
  for i, c in ipairs(list) do
    if c.id == id then
      table.remove(list, i)
      local f = fs()
      if c.art and c.art.file and f and f.getInfo(c.art.file) then pcall(f.remove, c.art.file) end
      for _, file in pairs(c.faces or {}) do if f and f.getInfo(file) then pcall(f.remove, file) end end
      S.save_items()
      return true
    end
  end
  return false
end

function S.of_kind(kind)
  if kind == "joker" then return S.all() end
  local out = {}
  for _, c in ipairs(S.items()) do if not kind or c.kind == kind then out[#out + 1] = c end end
  return out
end

function S.count(kind)
  if kind == nil then return #S.all() + #S.items() end
  return #S.of_kind(kind)
end

return S
