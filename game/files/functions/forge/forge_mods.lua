local json = require("bot.sim.json")
local Store = require("functions/forge/forge_store")
local Rules = require("functions/forge/forge_rules")

local M = {}

M.DIR = "forge/mods"
M.EXPORT_DIR = "forge/exports"
M.IMPORT_DIR = "forge/import"
M.INDEX = "forge/mods/index.json"
M.EXT = ".forgemod"
M.FORMAT = "forgemod"
M.V = 3
M.MAX_BYTES = 2 * 1024 * 1024
M.MAX_ITEMS = 60
M.MAX_FILE = 64 * 1024
M.MAX_FILES = 200
M.MAX_NAME = 24
M.MAX_ABOUT = 48

M.list = {}
M.jokers = {}
M.items = {}
M.badges = {}
M.index = nil

local function fs() return rawget(_G, "love") and love.filesystem end

local function write(path, data)
  local ok, F = pcall(require, "functions/fast_fs")
  if ok and F and F.write then return F.write(path, data) end
  local f = fs()
  return f and f.write(path, data) or false
end

local function ensure(dir)
  local f = fs()
  if not f then return end
  local path = ""
  for part in dir:gmatch("[^/]+") do
    path = path == "" and part or (path .. "/" .. part)
    if not f.getInfo(path) then f.createDirectory(path) end
  end
end
M.ensure = ensure

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INV = {}
for i = 1, 64 do B64_INV[B64:byte(i)] = i - 1 end

function M.b64_encode(s)
  local L = rawget(_G, "love")
  if L and L.data and L.data.encode then
    local ok, r = pcall(L.data.encode, "string", "base64", s)
    if ok and type(r) == "string" then return r end
  end
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local q = {math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64}
    out[#out + 1] = B64:sub(q[1] + 1, q[1] + 1) .. B64:sub(q[2] + 1, q[2] + 1) .. (b and B64:sub(q[3] + 1, q[3] + 1) or "=") .. (c and B64:sub(q[4] + 1, q[4] + 1) or "=")
  end
  return table.concat(out)
end

function M.b64_decode(s)
  if type(s) ~= "string" or #s % 4 ~= 0 or s:find("[^%w%+/=]") then return nil end
  local L = rawget(_G, "love")
  if L and L.data and L.data.decode then
    local ok, r = pcall(L.data.decode, "string", "base64", s)
    if ok and type(r) == "string" then return r end
    return nil
  end
  local out = {}
  for i = 1, #s, 4 do
    local a, b, c, d = s:byte(i, i + 3)
    local va, vb, vc, vd = B64_INV[a], B64_INV[b], B64_INV[c], B64_INV[d]
    if not (va and vb) then return nil end
    local n = va * 262144 + vb * 4096 + (vc or 0) * 64 + (vd or 0)
    out[#out + 1] = string.char(math.floor(n / 65536) % 256)
    if vc then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
    if vd then out[#out + 1] = string.char(n % 256) end
  end
  return table.concat(out)
end

function M.png_size(s)
  if type(s) ~= "string" or #s < 24 or s:sub(1, 8) ~= "\137PNG\r\n\26\n" or s:sub(13, 16) ~= "IHDR" then return nil end
  local function u32(i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return u32(17), u32(21)
end

local function line(s, max)
  return (tostring(s or ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", ""):sub(1, max))
end

local function about_lines(t)
  local out = {}
  if type(t) == "string" then t = {t} end
  for _, l in ipairs(type(t) == "table" and t or {}) do
    local s = type(l) == "string" and line(l, M.MAX_ABOUT) or ""
    if s ~= "" and #out < 2 then out[#out + 1] = s end
  end
  return out
end

function M.clean_id(id)
  if type(id) ~= "string" then return nil end
  id = id:lower()
  if not id:match("^[a-z0-9]+$") or #id < 4 or #id > 8 then return nil end
  return id
end

function M.new_id()
  local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
  for _ = 1, 50 do
    local t = {}
    for i = 1, 6 do
      local n = math.random(1, #chars)
      t[i] = chars:sub(n, n)
    end
    local id = table.concat(t)
    if not M.get(id) then return id end
  end
  return "m" .. tostring(os.time() % 100000)
end

local function base(path) return type(path) == "string" and path:match("^forge/art/([%w_]+)%.png$") or nil end

function M.art_path(mod_id, b) return "forge/art/fm_" .. mod_id .. "_" .. b .. ".png" end

local function own_joker(id) for _, c in ipairs(Store.all()) do if c.id == id then return c end end end
local function own_item(id) for _, c in ipairs(Store.items()) do if c.id == id then return c end end end
M.own_joker, M.own_item = own_joker, own_item

local function files_of(c)
  local out = {}
  if c.art and c.art.file then out[#out + 1] = c.art.file end
  for _, r in ipairs({"J", "Q", "K"}) do if c.faces and c.faces[r] then out[#out + 1] = c.faces[r] end end
  return out
end

function M.pack(info, ids)
  info = info or {}
  local f = fs()
  local out = {
    format = M.FORMAT, v = M.V, id = M.clean_id(info.id) or M.new_id(),
    name = line(info.name, M.MAX_NAME), author = line(info.author, M.MAX_NAME), about = about_lines(info.about),
    version = math.max(1, math.floor(tonumber(info.version) or 1)), made = os.time(),
    jokers = {}, creations = {}, files = {},
  }
  if out.name == "" then out.name = "Forge mod" end
  local seen = {}
  for _, id in ipairs(ids or {}) do
    local j = own_joker(id)
    local c = j or own_item(id)
    if c and not seen[c.id] and #out.jokers + #out.creations < M.MAX_ITEMS then
      seen[c.id] = true
      local x = Store.copy(c)
      x.enabled = true
      local packed = {}
      for _, p in ipairs(files_of(c)) do
        local b = base(p)
        if b and not out.files[b] and f and f.getInfo(p) then
          local data = f.read(p)
          local w, h = M.png_size(data)
          if type(data) == "string" and #data <= M.MAX_FILE and w == 71 and h == 95 then out.files[b] = M.b64_encode(data) end
        end
        if b and out.files[b] then packed[p] = true end
      end
      if x.art and x.art.file and not packed[x.art.file] then x.art = nil end
      for _, r in ipairs({"J", "Q", "K"}) do
        if x.faces and x.faces[r] and not packed[x.faces[r]] then x.faces[r] = nil end
      end
      if j then out.jokers[#out.jokers + 1] = x else out.creations[#out.creations + 1] = x end
    end
  end
  if #out.jokers + #out.creations == 0 then return nil, "empty" end
  out.v = M.needs_v(out.jokers, out.creations)
  if next(out.files) == nil then out.files = nil end
  local ok, raw = pcall(json.encode, out)
  if not ok then return nil, "encode" end
  if #raw > M.MAX_BYTES then return nil, "too_big" end
  return raw, out
end

function M.needs_v(jokers, creations)
  local v = 1
  for _, x in ipairs(jokers or {}) do v = math.max(v, Rules.need_v(x.rules, x.vars)) end
  local Cat = package.loaded["functions/forge/forge_catalog"]
  if Cat and Cat.need_v then
    for _, c in ipairs(creations or {}) do v = math.max(v, Cat.need_v(c)) end
  end
  return v
end

function M.for_old_server(raw)
  if type(raw) ~= "string" then return nil end
  local ok, t = pcall(json.decode, raw)
  if not ok or type(t) ~= "table" or t.format ~= M.FORMAT then return nil end
  local v = tonumber(t.v) or 1
  if v <= 1 then return nil end
  t.v, t.need = 1, math.max(v, tonumber(t.need) or 0)
  local ok2, out = pcall(json.encode, t)
  if not ok2 or type(out) ~= "string" or #out > M.MAX_BYTES then return nil end
  return out
end

function M.parse(raw)
  if type(raw) ~= "string" or raw == "" then return nil, "empty" end
  if #raw > M.MAX_BYTES then return nil, "too_big" end
  local ok, t = pcall(json.decode, raw)
  if not ok or type(t) ~= "table" or t.format ~= M.FORMAT then return nil, "not_forge" end
  if math.max(tonumber(t.v) or 0, tonumber(t.need) or 0) > M.V then return nil, "newer" end
  local id = M.clean_id(t.id)
  if not id then return nil, "not_forge" end
  local mod = {
    id = id, name = line(t.name, M.MAX_NAME), author = line(t.author, M.MAX_NAME), about = about_lines(t.about),
    version = math.max(1, math.min(9999, math.floor(tonumber(t.version) or 1))), made = tonumber(t.made) or 0,
    jokers = {}, creations = {}, files = {},
  }
  if mod.name == "" then mod.name = "Forge mod" end
  local nfiles = 0
  if type(t.files) == "table" then
    for k, v in pairs(t.files) do
      if type(k) == "string" and k:match("^[%w_]+$") and #k <= 40 and type(v) == "string" and nfiles < M.MAX_FILES then
        local data = M.b64_decode(v)
        local w, h = M.png_size(data)
        if data and #data <= M.MAX_FILE and w == 71 and h == 95 then
          mod.files[k] = data
          nfiles = nfiles + 1
        end
      end
    end
  end
  local function art(p)
    local b = base(p)
    if b and mod.files[b] then return M.art_path(id, b) end
    return nil
  end
  local seen, n = {}, 0
  local function take(c, joker)
    if type(c) ~= "table" or n >= M.MAX_ITEMS then return end
    local src = tostring(c.id or ""):gsub("[^%w]", ""):sub(1, 10)
    if src == "" then return end
    c.id = id .. src:sub(1, 16 - #id)
    if type(c.art) == "table" and c.art.file then
      local p = art(c.art.file)
      c.art = p and {file = p} or nil
    end
    if type(c.faces) == "table" then
      local faces = {}
      for _, r in ipairs({"J", "Q", "K"}) do faces[r] = art(c.faces[r]) end
      c.faces = faces
    end
    local clean
    if joker then clean = Store.clean(c) else clean = Store.clean_item(c) end
    if not clean or seen[clean.id] then return end
    seen[clean.id] = true
    clean.src = src
    clean.mod_id = id
    n = n + 1
    local list = joker and mod.jokers or mod.creations
    list[#list + 1] = clean
  end
  for _, c in ipairs(type(t.jokers) == "table" and t.jokers or {}) do take(c, true) end
  for _, c in ipairs(type(t.creations) == "table" and t.creations or {}) do take(c, false) end
  if n == 0 then return nil, "empty" end
  return mod
end

function M.get_index()
  if M.index then return M.index end
  local f = fs()
  local t
  if f and f.getInfo(M.INDEX) then
    local ok, data = pcall(json.decode, f.read(M.INDEX) or "")
    if ok and type(data) == "table" then t = data end
  end
  M.index = type(t) == "table" and type(t.mods) == "table" and t.mods or {}
  return M.index
end

function M.save_index()
  ensure(M.DIR)
  local ok, raw = pcall(json.encode, {v = 1, mods = M.get_index()})
  if ok then write(M.INDEX, raw) end
end

local function remove_art(mod_id)
  local f = fs()
  if not (f and f.getInfo("forge/art")) then return end
  local prefix = "fm_" .. mod_id .. "_"
  for _, name in ipairs(f.getDirectoryItems("forge/art")) do
    if name:sub(1, #prefix) == prefix then pcall(f.remove, "forge/art/" .. name) end
  end
end

function M.extract(mod, force)
  local f = fs()
  if not f then return end
  ensure("forge/art")
  for b, data in pairs(mod.files or {}) do
    local p = M.art_path(mod.id, b)
    if force or not f.getInfo(p) then write(p, data) end
  end
end

function M.badge(mod)
  local b = M.badges[mod.id] or {id = "forge_" .. mod.id, prefix = "forge", can_load = true, config = {}}
  b.name, b.display_name = mod.name, mod.name
  b.badge_colour = G and G.C and (G.C.SECONDARY_SET and G.C.SECONDARY_SET.Spectral or G.C.PURPLE) or {0.3, 0.4, 0.8, 1}
  b.badge_text_colour = G and G.C and G.C.WHITE or {1, 1, 1, 1}
  M.badges[mod.id] = b
  return b
end

function M.rebuild()
  local own = {}
  for _, c in ipairs(Store.all()) do own[c.id] = true end
  for _, c in ipairs(Store.items()) do own[c.id] = true end
  local jokers, items, seen = {}, {}, {}
  for _, mod in ipairs(M.list) do
    if mod.on then
      local badge = M.badge(mod)
      for _, pair in ipairs({{mod.jokers, jokers}, {mod.creations, items}}) do
        for _, c in ipairs(pair[1]) do
          c.forge_mod = badge
          if not seen[c.id] and not own[c.id] and not (mod.mine and own[c.src]) then
            seen[c.id] = true
            pair[2][#pair[2] + 1] = c
          end
        end
      end
    end
  end
  M.jokers, M.items = jokers, items
end

local function sort_mods(list)
  table.sort(list, function(a, b)
    if a.mine ~= b.mine then return a.mine end
    if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
    return a.id < b.id
  end)
end

function M.load()
  local f = fs()
  M.list = {}
  if f and f.getInfo(M.DIR) then
    local idx = M.get_index()
    local names = f.getDirectoryItems(M.DIR)
    table.sort(names)
    for _, name in ipairs(names) do
      local id = name:match("^([%w]+)%.forgemod$")
      local path = M.DIR .. "/" .. name
      if id and not M.get(id:lower()) then
        local raw = f.read(path)
        local mod = M.parse(raw)
        if mod and mod.id == id:lower() then
          local e = type(idx[mod.id]) == "table" and idx[mod.id] or {}
          mod.on = e.on ~= false
          mod.mine = e.mine == true
          mod.added = tonumber(e.added) or 0
          mod.file = path
          M.extract(mod, false)
          mod.files = nil
          M.list[#M.list + 1] = mod
        end
      end
    end
    sort_mods(M.list)
  end
  M.rebuild()
  return M.list
end

function M.get(id)
  for _, m in ipairs(M.list) do if m.id == id then return m end end
  return nil
end

function M.refresh_game()
  local FJ = package.loaded["functions/forge/forge_joker"]
  if FJ and FJ.register_all then
    local ok, err = pcall(FJ.register_all)
    if not ok then print("[FORGE] mods: " .. tostring(err)) end
  end
  local K = rawget(_G, "ForgeKinds")
  if K and K.register_all then
    local ok, err = pcall(K.register_all)
    if not ok then print("[FORGE] mods: " .. tostring(err)) end
  end
end

function M.install(raw, opts)
  opts = type(opts) == "table" and opts or {}
  local mod, err = M.parse(raw)
  if not mod then return nil, err end
  ensure(M.DIR)
  local path = M.DIR .. "/" .. mod.id .. M.EXT
  if not write(path, raw) then return nil, "write" end
  local idx = M.get_index()
  local prev = type(idx[mod.id]) == "table" and idx[mod.id] or nil
  idx[mod.id] = {on = not (prev and prev.on == false), mine = opts.mine or (prev and prev.mine) or false, added = prev and prev.added or os.time()}
  M.save_index()
  remove_art(mod.id)
  M.extract(mod, true)
  M.load()
  M.refresh_game()
  return M.get(mod.id) or mod
end

function M.export(info, ids)
  local raw, out = M.pack(info, ids)
  if not raw then return nil, out end
  local mod, err = M.install(raw, {mine = true})
  if not mod then return nil, err end
  local path = M.write_share(mod, raw)
  return mod, path
end

local function safe_name(s)
  local n = tostring(s or ""):gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  return n ~= "" and n:sub(1, 32) or "Forge_mod"
end

function M.share_path(mod)
  return M.EXPORT_DIR .. "/" .. safe_name(mod.name) .. "_" .. mod.id .. M.EXT
end

function M.write_share(mod, raw)
  local f = fs()
  if not raw then raw = f and mod.file and f.getInfo(mod.file) and f.read(mod.file) or nil end
  if type(raw) ~= "string" then return nil end
  ensure(M.EXPORT_DIR)
  local path = M.share_path(mod)
  if not write(path, raw) then return nil end
  return path
end

function M.share(id)
  local mod = M.get(id)
  if not mod then return nil end
  return M.write_share(mod)
end

function M.set_on(id, on)
  local mod = M.get(id)
  if not mod then return end
  local idx = M.get_index()
  local e = type(idx[id]) == "table" and idx[id] or {}
  e.on = on and true or false
  idx[id] = e
  mod.on = e.on
  M.save_index()
  M.rebuild()
  M.refresh_game()
end

function M.delete(id)
  local mod = M.get(id)
  if not mod then return false end
  local f = fs()
  if f and mod.file and f.getInfo(mod.file) then pcall(f.remove, mod.file) end
  remove_art(id)
  M.get_index()[id] = nil
  M.save_index()
  M.load()
  M.refresh_game()
  return true
end

function M.import_folder()
  local f = fs()
  local done, bad = {}, {}
  if not f then return done, bad end
  ensure(M.IMPORT_DIR)
  local names = f.getDirectoryItems(M.IMPORT_DIR)
  table.sort(names)
  for _, name in ipairs(names) do
    if name:lower():match("%.forgemod$") then
      local path = M.IMPORT_DIR .. "/" .. name
      local raw = f.read(path)
      local mod, err = M.install(raw)
      if mod then
        done[#done + 1] = mod
        pcall(f.remove, path)
      else
        bad[#bad + 1] = {name = name, err = err}
      end
    end
  end
  return done, bad
end

function M.read_dropped(file)
  local name = file and file.getFilename and file:getFilename()
  if type(name) ~= "string" or not name:lower():match("%.forgemod$") then return nil end
  local ok = pcall(file.open, file, "r")
  if not ok then return false, "read" end
  local ok2, raw = pcall(file.read, file)
  pcall(file.close, file)
  if not ok2 or type(raw) ~= "string" then return false, "read" end
  return raw
end

function M.dropped(file)
  local raw, err = M.read_dropped(file)
  if raw == nil then return false end
  local mod
  if raw then mod, err = M.install(raw) end
  if M.on_dropped then pcall(M.on_dropped, mod, err) end
  return true
end

function M.folder_url(dir)
  local f = fs()
  if not f then return nil end
  ensure(dir)
  return "file://" .. f.getSaveDirectory() .. "/" .. dir
end

function M.summary(mod)
  local Cat = require("functions/forge/forge_catalog")
  local counts, order = {}, {}
  local function add(kind)
    if not counts[kind] then counts[kind] = 0; order[#order + 1] = kind end
    counts[kind] = counts[kind] + 1
  end
  for _ = 1, #mod.jokers do add("joker") end
  for _, c in ipairs(mod.creations) do add(c.kind) end
  local parts = {}
  for _, kind in ipairs(order) do
    local k = Cat.kind(kind)
    local label = counts[kind] == 1 and k.label or k.plural
    parts[#parts + 1] = counts[kind] .. " " .. (mod_loc and mod_loc(label) or label)
  end
  return table.concat(parts, ", ")
end

function M.all_of(mod)
  local out = {}
  for _, c in ipairs(mod.jokers) do out[#out + 1] = c end
  for _, c in ipairs(mod.creations) do out[#out + 1] = c end
  return out
end

function M.badge_key(mod_id) return "forge_mod_" .. mod_id end

function M.label_badge(key)
  local id = type(key) == "string" and key:match("^forge_mod_([%w]+)$")
  local mod = id and M.get(id)
  if not (mod and G and G.localization and G.localization.misc) then return false end
  G.localization.misc.labels = G.localization.misc.labels or {}
  G.localization.misc.labels[key] = mod.name
  if type(get_badge_colour) == "function" then pcall(get_badge_colour, key) end
  if G.BADGE_COL then G.BADGE_COL[key] = G.C.PURPLE end
  return true
end

function M.install_hooks()
  if M.hooked or not rawget(_G, "love") then return end
  M.hooked = true
  if Card and Card.generate_UIBox_ability_table then
    local orig_aut = Card.generate_UIBox_ability_table
    Card.generate_UIBox_ability_table = function(self, ...)
      local r = orig_aut(self, ...)
      local center = self and self.config and self.config.center
      local key = center and center.forge_mod_badge
      if key and type(r) == "table" and type(r.badges) == "table" and M.label_badge(key) then r.badges[#r.badges + 1] = key end
      return r
    end
  end
  local orig = love.filedropped
  love.filedropped = function(file, ...)
    local ok, used = pcall(M.dropped, file)
    if ok and used then return end
    if orig then return orig(file, ...) end
  end
end

Store.extra = M

return M
