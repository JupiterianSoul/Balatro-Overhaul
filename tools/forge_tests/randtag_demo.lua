FRT = FRT or {runs = {}}

local Store = JokerForge.store
local Rules = require("functions/forge/forge_rules")

function FRT.make()
  Store.put({id = "rtag", name = "Lucky Dip", rarity = 2, cost = 6, enabled = true, art = {atlas = "Joker", x = 5, y = 5},
    rules = {{when = "round_end", give = {{id = "tag", v = "random"}}}}})
  Store.put({id = "ftag", name = "Six Shooter", rarity = 2, cost = 6, enabled = true, art = {atlas = "Joker", x = 2, y = 9},
    rules = {{when = "round_end", give = {{id = "tag", v = "tag_d_six"}}}}})
  JokerForge.joker.register_all()
  local c, f = Store.find("rtag"), Store.find("ftag")
  print("FRT made", c and c.rules[1].give[1].v, "need_v", Rules.need_v(c and c.rules), "fixed need_v", Rules.need_v(f and f.rules))
end

local function joker(id)
  for _, j in ipairs(G.jokers.cards) do
    if j.config.center.key == "j_forge_" .. id then return j end
  end
end

function FRT.fire(n, tag)
  local card = joker("rtag")
  local real = add_tag
  local got = {}
  add_tag = function(t) got[#got + 1] = t.key end
  for _ = 1, n do card:calculate_joker({end_of_round = true, game_over = false}) end
  FRT.pending = {got = got, real = real, n = n, tag = tag}
end

function FRT.done()
  return FRT.pending ~= nil and #FRT.pending.got >= FRT.pending.n
end

function FRT.collect()
  local p = FRT.pending
  add_tag = p.real
  FRT.pending = nil
  FRT.runs[p.tag] = p.got
  local allowed = {}
  for _, k in ipairs(Rules.tag_pool()) do allowed[k] = true end
  local kinds, seen, bad = 0, {}, 0
  for _, k in ipairs(p.got) do
    if not seen[k] then seen[k] = true kinds = kinds + 1 end
    if not allowed[k] then bad = bad + 1 end
  end
  print("FRT tags", p.tag, table.concat(p.got, " "))
  print("FRT check", p.tag, "fired=" .. #p.got, "kinds=" .. kinds, "invalid=" .. bad, "pool=" .. #Rules.tag_pool())
end

function FRT.compare(a, b)
  local x, y = FRT.runs[a] or {}, FRT.runs[b] or {}
  local same = #x == #y
  for i = 1, #x do if x[i] ~= y[i] then same = false end end
  print("FRT compare", a, b, same and "same" or "different")
end

function FRT.real()
  FRT.before = #G.GAME.tags
  joker("rtag"):calculate_joker({end_of_round = true, game_over = false})
end

function FRT.real_done()
  return FRT.before ~= nil and #G.GAME.tags > FRT.before
end

function FRT.real_log()
  local t = G.GAME.tags[#G.GAME.tags]
  print("FRT real tag on the HUD", t and t.key, "errors", Rules.errors)
end

function FRT.hover()
  local j = joker("rtag")
  if j then j:hover() end
end

function FRT.text(lang)
  local T = require("functions/forge/forge_text")
  print("FRT text", lang, T.sentence({when = "round_end", give = {{id = "tag", v = "random"}}}, lang))
end

function FRT.make_card()
  Store.put_item({id = "rtc", kind = "tarot", name = "Tag Dip", effects = {{id = "tag", v = "random", n = 1}}})
  ForgeKinds.register_all()
  local Cat = require("functions/forge/forge_catalog")
  local c = Store.get_item("rtc")
  print("FRT card made", c and c.kind, c and c.effects[1].id, c and c.effects[1].v, "need_v", Cat.need_v(c))
end

function FRT.use_card()
  FRT.before = #G.GAME.tags
  FRT.gave = ForgeKinds.try_give(Store.get_item("rtc"))
  local card
  for _, c in ipairs(G.consumeables.cards) do
    if c.config.center.forge_id == "rtc" or tostring(c.config.center.key):find("rtc", 1, true) then card = c end
  end
  FRT.card = card
  if card then G.FUNCS.use_card({config = {ref_table = card}}) end
end

function FRT.card_log()
  local t = G.GAME.tags[#G.GAME.tags]
  local allowed = {}
  for _, k in ipairs(Rules.tag_pool()) do allowed[k] = true end
  local ok = FRT.card ~= nil and #G.GAME.tags == FRT.before + 1 and t ~= nil and allowed[t.key] == true and G.P_TAGS[t.key] ~= nil
  print("FRT card tag", "given=" .. tostring(FRT.gave), "card=" .. tostring(FRT.card and FRT.card.config.center.key), "tags_before=" .. tostring(FRT.before), "tags_after=" .. #G.GAME.tags, "tag=" .. tostring(t and t.key), ok and "OK" or "BAD")
end
