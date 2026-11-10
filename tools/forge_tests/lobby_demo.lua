FLOB = {}

local function walk(e, key)
  if type(e) ~= "table" then return nil end
  local c = e.config
  if c and c.func == "toggle" and type(c.ref_table) == "table" and c.ref_table.ref_value == key then return e end
  for _, ch in pairs(e.children or {}) do
    local r = walk(ch, key)
    if r then return r end
  end
  if c and type(c.object) == "table" and c.object.UIRoot then return walk(c.object.UIRoot, key) end
  return nil
end

function FLOB.empty()
  local S = JokerForge.store
  S.list, S.items_list = {}, {}
  S.save()
  S.save_items()
  HLOG("lobby_empty", #S.base_jokers(), #S.base_items())
end

function FLOB.enter()
  bom_match.enter_lobby(true, "AB12")
  local st = bom_match.get_state()
  st.visibility, st.opp_name = "private", "Jimbo"
  bom_ui.show_lobby()
end

function FLOB.show(tab, key)
  for page = 1, 6 do
    UIK._pages["mpls_" .. tab] = page
    bom_lobby_settings.show(tab)
    if G.OVERLAY_MENU and walk(G.OVERLAY_MENU.UIRoot, key) then
      HLOG("lobby_page", tab, key, page)
      return
    end
  end
  HLOG("lobby_page", tab, key, "none")
end

function FLOB.press(key)
  local box = G.OVERLAY_MENU
  local e = box and walk(box.UIRoot, key)
  HLOG("lobby_press", key, e and "found" or "missing", e and e.config.button or "disabled")
  if e and e.config.button then G.FUNCS.toggle_button(e) end
end

function FLOB.report(tag)
  local s = bom_match.get_settings()
  local raw = ForgeRoom.raw_of(s.forge_room)
  HLOG("lobby_state", tag, "on", tostring(s.forge_room_on), "bytes", raw and #raw or 0, "hash", raw and ForgeRoom.hash(raw) or "none",
    "refused", ForgeRoom.refused or "none", "describe", table.concat(bom_lobby_settings.describe(s), " / "))
  ForgeRoom.refused = nil
end
