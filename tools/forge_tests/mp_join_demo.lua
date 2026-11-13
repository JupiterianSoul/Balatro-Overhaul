MPJ = MPJ or {}
local function read(path)
  local f = io.open(path, "rb")
  local s = f and f:read("*a")
  if f then f:close() end
  return s
end
local function Mods() return package.loaded["functions/forge/forge_mods"] end
local function ids_of(list)
  local out = {}
  for _, m in ipairs(list or {}) do out[#out + 1] = tostring(m.id) end
  return #out > 0 and table.concat(out, ",") or "none"
end
function MPJ.room()
  local line = read(os.getenv("MPM_ROOM_FILE") or "/tmp/mpm_room.txt") or ""
  return line:match("^(%w+)%s+(%w+)")
end
function MPJ.hooks()
  if MPJ.hooked then return end
  MPJ.hooked = true
  local err0 = bom_ui.show_error
  bom_ui.show_error = function(text, ...)
    HLOG("mpj_error", tostring(text))
    MPJ.last_error = tostring(text)
    return err0(text, ...)
  end
  local send0 = bom_core.send
  bom_core.send = function(data, ...)
    if type(data) == "table" and (data.type == "join_room" or data.type == "list_rooms" or data.type == "forge_room_get") then
      HLOG("mpj_send", data.type, "code", tostring(data.code), "id", tostring(data.id or data.room), "mods", data.mods == nil and "nil" or ids_of(data.mods))
    end
    return send0(data, ...)
  end
  local err1 = bom_room.on_room_error
  bom_room.on_room_error = function(d, ...)
    HLOG("mpj_room_error", tostring(d and d.reason), "hostMods", ids_of(d and d.hostMods), "yourMods", ids_of(d and d.yourMods))
    return err1(d, ...)
  end
end
function MPJ.prep(tag, forge)
  G.PROFILES[G.SETTINGS.profile].name = "Tester" .. tag
  local st = G.SETTINGS
  st.tutorial_complete, st.tutorial_progress = true, nil
  G.FUNCS.trigger_sub_showcase_multiplayer = function() end
  G.FUNCS.trigger_sub_showcase_tavern = function() end
  G.SETTINGS.sub_showcases_seen = setmetatable({}, {__index = function() return true end})
  MPJ.hooks()
  local M = Mods()
  if forge == "on" or forge == "off" then
    local mod, err = M.install(read(os.getenv("MPM_FORGEMOD")))
    HLOG("mpj_install", tostring(mod and mod.id), tostring(err))
    if forge == "off" then M.set_on(mod.id, false) end
  end
  G:save_progress()
  local fh = G.FILE_HANDLER
  fh.force = true
  MPJ.state("prep_" .. tag)
end
function MPJ.forge_off()
  for _, m in ipairs(Mods().list) do Mods().set_on(m.id, false) end
end
local function join_input()
  local i = 1
  while true do
    local n, v = debug.getupvalue(G.FUNCS.mp_confirm_join_room, i)
    if not n then return nil end
    if n == "_mp_join_input" then return v end
    i = i + 1
  end
end
function MPJ.type_code(code)
  local c = code or MPJ.room()
  join_input().room_code = c
  HLOG("mpj_type_code", tostring(c))
  MPJ.last_error = nil
  G.FUNCS.mp_confirm_join_room()
end
function MPJ.join_code(code)
  bom_ui.overlay({ definition = create_UIBox_join_room_input() })
  MPJ.type_code(code)
end
function MPJ.browse() bom_browse.show() end
function MPJ.refresh() bom_browse.refresh() end
function MPJ.row()
  local _, id = MPJ.room()
  for _, r in ipairs(bom_browse.state.rooms or {}) do
    if r.id == id then return r end
  end
end
function MPJ.listed() return bom_browse.state.status == "ok" and MPJ.row() ~= nil end
function MPJ.pick()
  local r = MPJ.row()
  HLOG("mpj_row", "sameMods", tostring(r.sameMods), "private", tostring(r.private), "modded", tostring(r.modded), "joinable", tostring(r.joinable))
  MPJ.last_error = nil
  bom_browse.join_room(r)
end
function MPJ.mods_open() return bom_browse.mods_overlay ~= nil and G.OVERLAY_MENU == bom_browse.mods_overlay end
function MPJ.code_open()
  if not G.OVERLAY_MENU or MPJ.mods_open() or bom_browse.is_open() then return false end
  local ok, f = pcall(function() return G.FUNCS.mp_confirm_join_room and G.OVERLAY_MENU:get_UIE_by_ID("text_input") end)
  return ok and f ~= nil and f ~= false
end
function MPJ.yes() MPJ.last_error = nil; G.FUNCS.mp_mods_yes() end
function MPJ.no() G.FUNCS.mp_mods_no() end
function MPJ.in_room()
  local seat = bom_room.seat
  return seat ~= nil and seat.code ~= nil and bom_match.get_phase() == bom_match.PHASE.LOBBY
end
function MPJ.step(tag)
  local did = "nothing"
  if MPJ.mods_open() then
    did = "yes"
    MPJ.yes()
  elseif MPJ.code_open() then
    did = "type_code"
    MPJ.type_code()
  end
  HLOG("mpj_step", tag, did)
end
function MPJ.settled() return MPJ.in_room() or MPJ.mods_open() or MPJ.code_open() or MPJ.last_error ~= nil end
function MPJ.state(tag)
  local M = Mods()
  local f = {}
  for _, m in ipairs(M.list) do f[#f + 1] = m.id .. (m.on and "+" or "-") end
  local set = {}
  for k in pairs(bom_forge.room or {}) do set[#set + 1] = k end
  local L = rawget(_G, "MODLOADER")
  local field = bom_core.mods_field()
  HLOG("mpj_state", tag, "forge", #f > 0 and table.concat(f, ",") or "none", "sends", field == nil and "nil" or ("[" .. ids_of(field) .. "]"),
    "modded_session", tostring(L and L.modded), "in_room", tostring(MPJ.in_room()), "mods_popup", tostring(MPJ.mods_open()), "code_prompt", tostring(MPJ.code_open()),
    "browse", tostring(bom_browse.is_open()), "overlay", tostring(G.OVERLAY_MENU ~= nil), "room_forge", #set > 0 and table.concat(set, ",") or "none", "error", tostring(MPJ.last_error))
end
function MPJ.write_pending()
  local code, id = MPJ.room()
  bom_browse.write_pending({ id = id, private = true })
  HLOG("mpj_write_pending", tostring(love.filesystem.read("mp_pending_join.txt")))
end
function MPJ.as_workshop()
  ModWorkshop.not_from_workshop = function() return {} end
end
