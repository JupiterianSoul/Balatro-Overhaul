local json = require("bot.sim.json")
local Store = require("functions/forge/forge_store")
local Mods = require("functions/forge/forge_mods")

local R = {}

R.V = 5
R.KEY = "forge_room"
R.KEY_ON = "forge_room_on"
R.ID = "mproom"
R.MAX_BYTES = 40 * 1024
R.raw = nil
R.info = nil
R.manual = false

local function fs() return rawget(_G, "love") and love.filesystem end
local function L(s) return mod_loc and mod_loc(s) or s end

local function match_api()
  local M = rawget(_G, "bom_match")
  if type(M) == "table" and M.get_phase and M.get_settings then return M end
  return nil
end

local function raw_of(v)
  if type(v) == "string" and v ~= "" then return v end
  if type(v) == "table" and type(v.raw) == "string" and v.raw ~= "" then return v.raw end
  return nil
end
R.raw_of = raw_of

function R.ranked()
  local M = match_api()
  local ok, st = pcall(function() return M and M.get_state and M.get_state() end)
  if ok and type(st) == "table" and st.ranked then return true end
  local FL = rawget(_G, "FairLock")
  local okc, ctx = pcall(function() return FL and FL.context and FL.context() end)
  return okc and (ctx == "ranked" or ctx == "speedrun") or false
end

local function files_of(c)
  local out = {}
  if c.art and c.art.file then out[#out + 1] = {"art", c.art.file} end
  for _, r in ipairs({"J", "Q", "K"}) do if c.faces and c.faces[r] then out[#out + 1] = {r, c.faces[r]} end end
  return out
end

local function sources()
  local saved = Store.room
  Store.room = nil
  local list = {}
  for _, c in ipairs(Store.base_jokers()) do
    if c.enabled then list[#list + 1] = {c = c, joker = true} end
  end
  for _, c in ipairs(Store.base_items()) do
    if c.enabled ~= false and c.kind ~= "collab" then list[#list + 1] = {c = c, joker = false} end
  end
  Store.room = saved
  return list
end

local function size_of(t)
  local ok, raw = pcall(json.encode, t)
  if not ok then return nil end
  local ok2, quoted = pcall(json.encode, raw)
  return ok2 and #quoted or nil, raw
end

function R.pack(max_bytes)
  max_bytes = tonumber(max_bytes) or R.MAX_BYTES
  local out = {format = Mods.FORMAT, v = Mods.V, room = R.V, id = R.ID, name = "Room", author = "", about = {}, version = 1, made = 0, jokers = {}, creations = {}}
  local arts = {}
  for i, s in ipairs(sources()) do
    if #out.jokers + #out.creations >= Mods.MAX_ITEMS then break end
    local x = Store.copy(s.c)
    x.id = string.format("%02d", i)
    x.enabled = true
    x.forge_mod, x.mod_id, x.src = nil, nil, nil
    x.art = type(x.art) == "table" and x.art.file == nil and x.art or nil
    x.faces = nil
    for _, pair in ipairs(files_of(s.c)) do arts[#arts + 1] = {x = x, slot = pair[1], path = pair[2], key = "r" .. x.id .. pair[1]} end
    local list = s.joker and out.jokers or out.creations
    list[#list + 1] = x
  end
  local n = #out.jokers + #out.creations
  if n == 0 then return nil, "empty" end
  out.room = Mods.needs_v(out.jokers, out.creations)
  out.v = out.room
  local size = size_of(out)
  if not size then return nil, "encode" end
  if size > max_bytes then return nil, "too_big" end
  local f = fs()
  local files, kept, dropped = {}, 0, 0
  for _, a in ipairs(arts) do
    local data = f and f.getInfo(a.path) and f.read(a.path)
    local w, h = Mods.png_size(data)
    local ok = type(data) == "string" and #data <= Mods.MAX_FILE and w == 71 and h == 95
    if ok then
      local b = Mods.b64_encode(data)
      local more = #b + #a.key + 8
      if size + more <= max_bytes then
        files[a.key] = b
        size = size + more
        local p = "forge/art/" .. a.key .. ".png"
        if a.slot == "art" then a.x.art = {file = p} else a.x.faces = a.x.faces or {}; a.x.faces[a.slot] = p end
        kept = kept + 1
      else
        dropped = dropped + 1
      end
    end
  end
  if next(files) then out.files = files end
  local final, raw = size_of(out)
  if not final then return nil, "encode" end
  if final > max_bytes then return nil, "too_big" end
  return raw, {count = n, jokers = #out.jokers, items = #out.creations, art = kept, dropped = dropped, bytes = final}
end

local function remove_art()
  local f = fs()
  if not (f and f.getInfo("forge/art")) then return end
  local prefix = "fm_" .. R.ID .. "_"
  for _, name in ipairs(f.getDirectoryItems("forge/art")) do
    if name:sub(1, #prefix) == prefix then pcall(f.remove, "forge/art/" .. name) end
  end
end

function R.refresh()
  local FJ = package.loaded["functions/forge/forge_joker"]
  if FJ then
    for k in pairs(FJ.atlas_cache or {}) do
      if type(k) == "string" and k:find(R.ID, 1, true) then FJ.atlas_cache[k] = nil end
    end
  end
  Mods.refresh_game()
end

function R.active() return Store.room ~= nil end

function R.hash(raw)
  local h = 5381
  for i = 1, #raw do h = (h * 33 + raw:byte(i)) % 4294967296 end
  return string.format("%08x", h)
end

function R.enter(raw, opts)
  opts = type(opts) == "table" and opts or {}
  if type(raw) ~= "string" or raw == "" then
    R.leave()
    return nil, "empty"
  end
  if raw == R.raw and Store.room then
    R.manual = opts.manual == true
    return true
  end
  local ok, t = pcall(json.decode, raw)
  if not ok or type(t) ~= "table" or tonumber(t.room) == nil or t.id ~= R.ID then
    R.leave()
    return nil, "not_room"
  end
  if tonumber(t.room) > R.V then
    R.leave()
    return nil, "newer"
  end
  local mod, err = Mods.parse(raw)
  if not mod then
    R.leave()
    return nil, err
  end
  remove_art()
  Mods.extract(mod, true)
  Store.room = {jokers = mod.jokers, items = mod.creations}
  R.raw = raw
  R.manual = opts.manual == true
  R.info = {jokers = #mod.jokers, items = #mod.creations, hash = R.hash(raw)}
  R.refresh()
  print(string.format("[FORGE] room on: %d creations, %d bytes, %s", R.info.jokers + R.info.items, #raw, R.info.hash))
  return true
end

function R.leave()
  if not (Store.room or R.raw) then return end
  Store.room = nil
  R.raw, R.info, R.manual = nil, nil, false
  remove_art()
  R.refresh()
  print("[FORGE] room off")
end

function R.wanted()
  local M = match_api()
  if not M then return nil end
  local okp, ph = pcall(M.get_phase)
  if not okp or ph == nil or ph == "none" then return nil end
  if R.ranked() then return nil end
  local oks, s = pcall(M.get_settings)
  return oks and type(s) == "table" and raw_of(s[R.KEY]) or nil
end

function R.sync()
  if R.busy then return end
  R.busy = true
  pcall(R.install)
  local ok, err = pcall(function()
    local want = R.wanted()
    if want then
      if want ~= R.raw then R.enter(want) end
    elseif R.raw and not R.manual then
      R.leave()
    end
  end)
  R.busy = false
  if not ok then print("[FORGE] room: " .. tostring(err)) end
end

function R.lobby_ready()
  local M = match_api()
  if not (M and M.update_settings and M.sync_settings) then return false end
  R.install()
  local ok, s = pcall(M.get_settings)
  return ok and type(s) == "table" and s[R.KEY] ~= nil or false
end

function R.host_on()
  local M = match_api()
  local ok, s = pcall(function() return M and M.get_settings() end)
  return ok and type(s) == "table" and raw_of(s[R.KEY]) ~= nil or false
end

R.REASONS = {
  empty = "Make or turn on a creation first",
  too_big = "Too much to share: turn some creations off",
  ranked = "Off in Ranked",
  lobby = "This lobby cannot share creations",
  host = "Only the host chooses",
}

function R.reason_text(why) return L(R.REASONS[why] or R.REASONS.lobby) end

function R.host_set(on)
  local M = match_api()
  if not M then return nil, "lobby" end
  if R.ranked() then return nil, "ranked" end
  local okh, host = pcall(function() return M.is_host_player and M.is_host_player() end)
  if okh and host == false then return nil, "host" end
  if not R.lobby_ready() then return nil, "lobby" end
  local value, info = {}, nil
  if on then
    local r, i = R.pack()
    if not r then return nil, i end
    value, info = {raw = r}, i
  end
  pcall(M.update_settings, {[R.KEY] = value, [R.KEY_ON] = on and true or false})
  pcall(M.sync_settings)
  return true, info
end

local function now() return rawget(_G, "love") and love.timer and love.timer.getTime() or os.clock() end

function R.refuse(why)
  R.refused = R.reason_text(why)
  R.refused_key = R.REASONS[why] or R.REASONS.lobby
  R.refused_at = now()
  if rawget(_G, "play_sound") then pcall(play_sound, "cancel", 0.8, 0.6) end
end

function R.before_sync()
  local M = match_api()
  if not M then return end
  local okh, host = pcall(function() return M.is_host_player and M.is_host_player() end)
  if not (okh and host) then return end
  local okm, inm = pcall(function() return M.is_in_match and M.is_in_match() end)
  if okm and inm then return end
  local ok, s = pcall(M.get_settings)
  if not (ok and type(s) == "table") or s[R.KEY_ON] == nil then return end
  R.refused_key = nil
  if s[R.KEY_ON] ~= true or R.ranked() then
    if raw_of(s[R.KEY]) then s[R.KEY] = {} end
    return
  end
  if raw_of(s[R.KEY]) then return end
  local raw, info = R.pack()
  if raw then
    s[R.KEY] = {raw = raw}
    return
  end
  s[R.KEY_ON] = false
  s[R.KEY] = {}
  R.refuse(info)
end

R.HELP = "Everyone plays with the host's creations"

function R.row_help()
  if R.refused_key and R.refused_at and now() - R.refused_at < 8 then return R.refused_key end
  return R.HELP
end

function R.lobby_defs()
  local function show() return not R.ranked() end
  return {
    {header = "The Forge", tab = "match", show = show},
    {key = R.KEY_ON, tab = "match", kind = "toggle", label = "Forge creations", info = R.HELP, info_fn = R.row_help, refresh = true, show = show},
  }
end

function R.add_lobby_row()
  local LS = rawget(_G, "bom_lobby_settings")
  if not (type(LS) == "table" and type(LS.DEFS) == "table") then return false end
  for _, d in ipairs(LS.DEFS) do if d.key == R.KEY_ON then return true end end
  local at = #LS.DEFS
  for i, d in ipairs(LS.DEFS) do if d.tab == "match" then at = i end end
  local defs = R.lobby_defs()
  for i, d in ipairs(defs) do table.insert(LS.DEFS, at + i, d) end
  if type(LS.BY_KEY) == "table" then LS.BY_KEY[R.KEY_ON] = defs[2] end
  return true
end

function R.install()
  local M = match_api()
  local d = M and M.DEFAULT_SETTINGS
  if type(d) ~= "table" then return false end
  if type(d[R.KEY]) ~= "table" then d[R.KEY] = {} end
  if d[R.KEY_ON] == nil then d[R.KEY_ON] = false end
  local ok, st = pcall(function() return M.get_state and M.get_state() end)
  if ok and type(st) == "table" and type(st.settings) == "table" then
    if st.settings[R.KEY] == nil or st.settings[R.KEY] == "" then st.settings[R.KEY] = {} end
    if st.settings[R.KEY_ON] == nil then st.settings[R.KEY_ON] = false end
  end
  if not R.sync_hooked and type(M.sync_settings) == "function" then
    R.sync_hooked = true
    local orig = M.sync_settings
    M.sync_settings = function(...)
      local okb, err = pcall(R.before_sync)
      if not okb then print("[FORGE] room: " .. tostring(err)) end
      return orig(...)
    end
  end
  R.add_lobby_row()
  return true
end

function R.summary()
  local info = R.info
  if not (info and Store.room) then return nil end
  local n = info.jokers + info.items
  return string.format(L(n == 1 and "%d Forge creation in this match" or "%d Forge creations in this match"), n)
end

function R.lobby_row()
  local locked = R.ranked() and L("Off in Ranked") or nil
  return {
    id = R.KEY,
    label = L("Forge creations"),
    help = L(R.HELP),
    locked = locked,
    get = function() return R.host_on() end,
    set = function(on)
      local ok, why = R.host_set(on)
      if not ok then return false, R.reason_text(why) end
      return true
    end,
  }
end

local function register_strings()
  if not mod_loc_register then return end
  mod_loc_register{
    fr = {
      ["The Forge"] = "La Forge",
      ["Forge creations"] = "Créations de la Forge",
      ["Everyone plays with the host's creations"] = "Tout le monde joue avec les créations de l'hôte",
      ["Make or turn on a creation first"] = "Créez ou activez d'abord une création",
      ["Too much to share: turn some creations off"] = "Trop à partager : désactivez des créations",
      ["Off in Ranked"] = "Désactivé en classé",
      ["This lobby cannot share creations"] = "Ce salon ne peut pas partager de créations",
      ["Only the host chooses"] = "Seul l'hôte choisit",
      ["%d Forge creation in this match"] = "%d création de la Forge dans ce match",
      ["%d Forge creations in this match"] = "%d créations de la Forge dans ce match",
    },
    es = {
      ["The Forge"] = "La Forja",
      ["Forge creations"] = "Creaciones de la Forja",
      ["Everyone plays with the host's creations"] = "Todos juegan con las creaciones del anfitrión",
      ["Make or turn on a creation first"] = "Crea o activa una creación primero",
      ["Too much to share: turn some creations off"] = "Demasiado para compartir: desactiva algunas creaciones",
      ["Off in Ranked"] = "Desactivado en clasificatoria",
      ["This lobby cannot share creations"] = "Esta sala no puede compartir creaciones",
      ["Only the host chooses"] = "Solo el anfitrión elige",
      ["%d Forge creation in this match"] = "%d creación de la Forja en esta partida",
      ["%d Forge creations in this match"] = "%d creaciones de la Forja en esta partida",
    },
  }
end

function R.install_hooks()
  if R.hooked or not rawget(_G, "Game") then return end
  R.hooked = true
  for _, name in ipairs({"start_run", "main_menu"}) do
    local orig = Game[name]
    if type(orig) == "function" then
      Game[name] = function(self, ...)
        R.sync()
        return orig(self, ...)
      end
    end
  end
end

register_strings()
remove_art()
R.install_hooks()
pcall(R.install)
_G.ForgeRoom = R

return R
