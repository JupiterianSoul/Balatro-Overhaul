FMOD = FMOD or {}

local Store = JokerForge.store
local Mods = ForgeMods

FMOD.results = FMOD.results or {}
local function ok(tag, cond, ...)
  FMOD.results[#FMOD.results + 1] = cond and true or false
  HLOG("forge_mods", tag, cond and "OK" or "BAD", ...)
end

function FMOD.make()
  Store.ensure_dirs()
  local src = love.image.newImageData("resources/textures/1x/Jokers.png")
  local art = love.image.newImageData(71, 95)
  art:paste(src, 0, 0, 9 * 71, 2 * 95, 71, 95)
  love.filesystem.write("forge/art/hthief.png", art:encode("png"):getString())
  Store.list = {}
  Store.items_list = {}
  Store.put({id = "hthief", name = "Heart Thief", rarity = 1, cost = 5, art = {file = "forge/art/hthief.png"},
    rules = {{when = "card_scored", only = {{id = "suit", v = "Hearts"}}, give = {{id = "mult", n = 4}}}}})
  Store.put({id = "gtooth", name = "Gold Tooth", rarity = 2, cost = 6, art = {atlas = "Joker", x = 4, y = 4}, rules = {{when = "round_end", give = {{id = "money", n = 2}}}}})
  Store.put_item({id = "ccoin", kind = "tarot", name = "Coin Card", fields = {cost = 3, select = 0}, effects = {{id = "money", n = 5}}, art = {atlas = "Tarot", x = 1, y = 0}})
  Store.put_item({id = "sember", kind = "seal", name = "Ember Seal", from = "Red", effects = {{id = "scored_mult", n = 3}}})
  JokerForge.joker.register_all()
  ForgeKinds.register_all()
  HLOG("forge_mods_make", #Store.all(), #Store.items())
end

function FMOD.fill_export()
  local st = ForgeModsUI.export
  st.info.name = "Heart Pack"
  st.info.a1 = "Hearts get stronger."
  st.info.a2 = "Two jokers, a tarot and a seal."
end

function FMOD.check_author()
  local m = Mods.list[1]
  local share = m and Mods.share_path(m)
  ok("author has one mod", #Mods.list == 1 and m.mine == true, m and m.id, m and m.name)
  ok("share file written", share and love.filesystem.getInfo(share) ~= nil, share)
  ok("installed file", m and love.filesystem.getInfo("forge/mods/" .. m.id .. ".forgemod") ~= nil)
  ok("author sees no doubles", #Mods.jokers == 0 and #Mods.items == 0 and #Store.live_jokers() == 2)
  local raw = share and love.filesystem.read(share)
  local out = os.getenv("SHOT_OUT")
  if raw and out then
    local f = io.open(out .. "/shared.forgemod", "wb")
    if f then f:write(raw) f:close() end
  end
  HLOG("forge_mods_size", raw and #raw or 0, "bytes")
end

function FMOD.fresh()
  Store.list = {}
  Store.items_list = {}
  Store.save()
  Store.save_items()
  for _, m in ipairs(Mods.list) do Mods.delete(m.id) end
  JokerForge.joker.register_all()
  ForgeKinds.register_all()
  local path = os.getenv("FMOD_SHARED")
  local f = path and io.open(path, "rb")
  local raw = f and f:read("*a")
  if f then f:close() end
  Mods.ensure(Mods.IMPORT_DIR)
  if raw then love.filesystem.write(Mods.IMPORT_DIR .. "/Heart_Pack.forgemod", raw) end
  love.filesystem.write(Mods.IMPORT_DIR .. "/broken.forgemod", "{\"format\": \"forgemod\", \"v\": 1}")
  ok("fresh profile", #Store.all() == 0 and #Mods.list == 0 and raw ~= nil, raw and #raw)
end

function FMOD.check_import()
  local m = Mods.list[1]
  ok("imported one mod", #Mods.list == 1 and m and not m.mine and m.on, m and m.name)
  if not m then return end
  FMOD.id = m.id
  local key = "j_forge_" .. m.id .. "hthief"
  local c = G.P_CENTERS[key]
  local in_pool = false
  for _, v in ipairs(G.P_CENTER_POOLS.Joker) do if v == c then in_pool = true end end
  ok("joker registered", c ~= nil and in_pool, key)
  ok("joker badge", c and c.mod and c.mod.display_name == "Heart Pack", c and c.mod and c.mod.display_name)
  ok("joker art", c and c.atlas == "forge_" .. m.id .. "hthief", c and c.atlas)
  local t = G.P_CENTERS["c_forge_" .. m.id .. "ccoin"]
  local t_pool = false
  for _, v in ipairs(G.P_CENTER_POOLS.Tarot) do if v == t then t_pool = true end end
  ok("tarot registered", t ~= nil and t_pool)
  ok("seal registered", G.P_SEALS["Forge_" .. m.id .. "sember"] ~= nil)
  ok("broken file left in import", love.filesystem.getInfo(Mods.IMPORT_DIR .. "/broken.forgemod") ~= nil)
  ok("own creations still empty", #Store.all() == 0 and #Store.items() == 0)
end

function FMOD.add_joker()
  FPLAY.add(FMOD.id .. "hthief")
end

function FMOD.hover()
  for _, c in ipairs(G.jokers.cards) do
    if c.config.center.forge then c:hover() end
  end
end

function FMOD.check_badge()
  local found = false
  for _, c in ipairs(G.jokers.cards) do
    local aut = c.ability_UIBox_table
    for _, b in ipairs(aut and aut.badges or {}) do if b == "forge_mod_" .. FMOD.id then found = true end end
  end
  ok("mod badge in the popup", found and G.localization.misc.labels["forge_mod_" .. FMOD.id] == "Heart Pack")
end

function FMOD.unhover()
  for _, c in ipairs(G.jokers.cards) do c:stop_hover() end
end

function FMOD.check_off()
  Mods.set_on(FMOD.id, false)
  local c = G.P_CENTERS["j_forge_" .. FMOD.id .. "hthief"]
  local in_pool = false
  for _, v in ipairs(G.P_CENTER_POOLS.Joker) do if v == c then in_pool = true end end
  ok("off leaves the pool", not in_pool and c and c.forge_on == false)
  Mods.set_on(FMOD.id, true)
  in_pool = false
  for _, v in ipairs(G.P_CENTER_POOLS.Joker) do if v == c then in_pool = true end end
  ok("on joins the pool", in_pool)
end

function FMOD.summary()
  local bad = 0
  for _, r in ipairs(FMOD.results) do if not r then bad = bad + 1 end end
  local fp = 0
  for _, r in ipairs(FPLAY and FPLAY.results or {}) do if not r then fp = fp + 1 end end
  HLOG("forge_mods_summary", #FMOD.results, "checks", bad, "bad", "scores bad", fp)
end

function FMOD.use_local_server()
  local url = os.getenv("FMOD_URL")
  local set = false
  for i = 1, 80 do
    local n = debug.getupvalue(bom_core.connect, i)
    if not n then break end
    if n == "SERVER_URL" then debug.setupvalue(bom_core.connect, i, url) set = true end
  end
  HLOG("forge_online_url", url, set)
end

function FMOD.quick_export()
  local ids = {}
  for _, c in ipairs(Store.all()) do ids[#ids + 1] = c.id end
  for _, c in ipairs(Store.items()) do ids[#ids + 1] = c.id end
  local m = Mods.export({name = "Heart Pack", author = "Tester", about = {"Hearts get stronger."}}, ids)
  ok("quick export", m ~= nil, m and m.id)
  FMOD.id = m and m.id
end

function FMOD.publish()
  G.FUNCS.forge_mods_publish({config = {ref_table = {id = FMOD.id}}})
end

function FMOD.online_ready()
  return ForgeOnline.state.status == "ready" or ForgeOnline.state.status == "offline"
end

function FMOD.check_online(tag, want_mine)
  local d = ForgeOnline.state.data
  local m = d and d.mods and d.mods[1]
  ok(tag, ForgeOnline.state.status == "ready" and m ~= nil and m.name == "Heart Pack" and (m.mine == true) == want_mine, ForgeOnline.state.status, m and m.id, m and tostring(m.mine))
  FMOD.remote = m and m.id
end

function FMOD.get()
  G.FUNCS.forge_online_get({config = {ref_table = {id = FMOD.remote}}})
end

function FMOD.check_got()
  local m = Mods.get(FMOD.remote)
  ok("got from the server", m ~= nil and not m.mine and m.on, m and m.name)
  local c = G.P_CENTERS["j_forge_" .. tostring(FMOD.remote) .. "hthief"]
  ok("downloaded joker live", c ~= nil and c.forge_on == true)
end

function FMOD.report()
  G.FUNCS.forge_online_report({config = {ref_table = {id = FMOD.remote, name = "Heart Pack"}}})
end

function FMOD.install_repro()
  local path = os.getenv("FMOD_REPRO")
  local f = path and io.open(path, "rb")
  local raw = f and f:read("*a")
  if f then f:close() end
  local mod, err = raw and Mods.install(raw, {mine = true})
  ok("repro installed as mine", mod ~= nil, mod and mod.id or err)
  FMOD.id = mod and mod.id
  FMOD.repro_raw = raw
end

function FMOD.check_published()
  local d = ForgeOnline.state.data
  local m = d and d.mods and d.mods[1]
  ok("published and listed as mine", m ~= nil and m.id == FMOD.id and m.mine == true, m and m.id, "retried", tostring(ForgeOnline.state.publish_retried))
end

local function gives(m)
  local out = {}
  for _, j in ipairs(m and m.jokers or {}) do
    for _, r in ipairs(j.rules or {}) do
      for _, g in ipairs(r.give or {}) do out[#out + 1] = tostring(g.id) .. "=" .. tostring(g.n) end
    end
  end
  return table.concat(out, ",")
end

function FMOD.check_got_repro(want)
  local m = Mods.get(FMOD.remote)
  local g = gives(m)
  ok("got repro from the server", m ~= nil and not m.mine and m.on, m and m.name, g)
  ok("repro values kept", g == want, g)
end
