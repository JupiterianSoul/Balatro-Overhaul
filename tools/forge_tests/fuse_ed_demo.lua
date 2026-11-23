FE = FE or {}
FE.results = {}

local Store = JokerForge.store

local function check(tag, ok, ...)
  FE.results[#FE.results + 1] = ok and true or false
  HLOG("fe_check", tag, ok and "OK" or "BAD", ...)
end

local function B() return ForgeBuilder end
local function reopen() JokerForge.ui.reopen("builder") end

local function draft(t, sec)
  B().new_draft(t)
  G.FUNCS.forge_b_mode({config = {ref_table = {mode = "advanced"}}})
  B().state.sec = sec or "rules"
  reopen()
end

local GIVE = {{when = "hand_played", only = {}, give = {{id = "mult", n = 2}}}}
function FE.a() draft({kind = "joker", id = "feina", name = "Ein A", rules = GIVE}) end
function FE.b() draft({kind = "joker", id = "feinb", name = "Ein B", rules = GIVE}) end
function FE.out() draft({kind = "joker", id = "feout", name = "Poly Out", always_ed = FE.ED or "polychrome", rules = GIVE}) end
function FE.fusion()
  draft({kind = "fusion", id = "fefuse", name = "Poly Fuse", fields = {a = "j_forge_feina", b = "j_forge_feinb", c = "j_none", out = "j_forge_feout", on = "Jokers", auto = false, keep = FE.KEEP ~= false, cost = 0}}, "basics")
end
function FE.save() G.FUNCS.forge_b_save() end
function FE.saved()
  local o = Store.get("feout")
  check("output saved with Always comes with", o and o.always_ed == (FE.ED or "polychrome"), o and tostring(o.always_ed))
  check("center has forge_start_ed", G.P_CENTERS.j_forge_feout and G.P_CENTERS.j_forge_feout.forge_start_ed ~= nil, G.P_CENTERS.j_forge_feout and tostring(G.P_CENTERS.j_forge_feout.forge_start_ed))
end

function FE.start() G.FUNCS.start_run(nil, {stake = 1, seed = "FUSEED"}) end

local function add(key, ed)
  local c = create_card("Joker", G.jokers, nil, nil, nil, nil, key, "fe")
  if ed then c:set_edition(ed, true, true) end
  c:add_to_deck()
  G.jokers:emplace(c)
  return c
end

local function ed_of(c) local e = c and c.edition return e and (e.type or e.key or next(e)) or "none" end

function FE.set_out(ed)
  local K = require("functions/forge/forge_kinds")
  if ed:sub(1, 6) == "forge_" and not Store.get_item("fe1") then
    Store.put_item({id = "fe1", kind = "edition", name = "Fe Shine", mode = "advanced", fields = {shader = "holo", chips = 20, mult = 5}})
    Store.save()
  end
  local o = Store.get("feout")
  o.always_ed = ed
  Store.put(o)
  K.register_all()
  JokerForge.joker.register_all()
  FE.want = ed
  check("output now " .. ed, G.P_CENTERS.j_forge_feout.forge_start_ed == ed, tostring(G.P_CENTERS.j_forge_feout.forge_start_ed))
end

local function has_want(c)
  local e = c and c.edition
  if not e then return false end
  local w = FE.want or "polychrome"
  if w:sub(1, 6) == "forge_" then return tostring(e.forge) == w:sub(7) end
  return (e[w] or e.type == w) and not e.forge and true or false
end

function FE.round(tag, in_ed)
  for i = #G.jokers.cards, 1, -1 do local c = G.jokers.cards[i] c:remove() end
  local a = add("j_forge_feina", in_ed)
  add("j_forge_feinb", in_ed)
  local F = require("functions/forge/forge_fusion")
  local made = F.fuse(a)
  FE.made = made
  FE.tag = tag
  check(tag .. " fused", made ~= nil)
  check(tag .. " made has the output edition right away", has_want(made), ed_of(made), made and made.edition and tostring(made.edition.forge))
end

function FE.later()
  local made = FE.made
  check(FE.tag .. " still has it a moment later", has_want(made), ed_of(made), made and made.edition and tostring(made.edition.forge))
end

function FE.after_reload()
  local made
  for _, c in ipairs(G.jokers.cards) do if c.config.center.key == "j_forge_feout" then made = c end end
  check(FE.tag .. " keeps it after save and reload", has_want(made), made and ed_of(made) or "missing", made and made.edition and tostring(made.edition.forge))
end

function FE.summary()
  local bad = 0
  for _, ok in ipairs(FE.results) do if not ok then bad = bad + 1 end end
  HLOG("fe_summary", #FE.results, "checks", bad, "bad")
end
