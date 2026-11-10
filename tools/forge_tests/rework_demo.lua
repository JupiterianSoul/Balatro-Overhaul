FRW = FRW or {}
local json = require("bot.sim.json")
local Store = JokerForge.store
local D = require("functions/forge/forge_doc")

local function build(name, rules, art, vars)
  local B = ForgeBuilder
  B.new_draft{kind = "joker"}
  local d = B.state.draft
  d.name, d.rules, d.art, d.vars, d.rarity, d.cost = name, rules, art, vars, 2, 6
  local c = B.save()
  HLOG("frw_built", name, c and c.id, c and json.encode(c.rules))
  return c and c.id
end

function FRW.make()
  FRW.ids = {}
  FRW.ids.breaker = build("Ace Breaker", {{when = "card_scored", only = {{id = "rank", v = 14}}, give = {{id = "chips", n = 250}, {id = "destroy_card"}}}}, {atlas = "Joker", x = 5, y = 2})
  FRW.ids.stone = build("Stonemason", {{when = "blind_selected", give = {{id = "add_card", v = "m_stone"}}}}, {atlas = "Joker", x = 7, y = 0})
  FRW.ids.hunter = build("Small Game", {{when = "hand_played", only = {{id = "blind", v = "Small"}}, give = {{id = "xmult", n = 3}}, alt = {{id = "money", n = 1}}}}, {atlas = "Joker", x = 2, y = 9})
  FRW.ids.climber = build("Climber", {{when = "hand_played", only = {{id = "hand_level", op = "at_least", n = 1}}, give = {{id = "mult", n = 100}}}}, {atlas = "Joker", x = 8, y = 4})
  FRW.ids.piggy = build("Piggy", {{when = "round_end", give = {{id = "sell_value", n = 3}}}}, {atlas = "Joker", x = 1, y = 5})
  FRW.ids.counter = build("Counter", {{when = "card_bought", give = {{id = "var_add", var = 1, n = 25}}}, {when = "hand_played", give = {{id = "var_chips", var = 1, n = 2}}}}, {atlas = "Joker", x = 3, y = 8}, {{name = "Buys", start = 150}})
  Store.put({id = "oldie", name = "Old Timer", rarity = 1, cost = 4, enabled = true, mode = "simple", created = 1, art = {atlas = "Joker", x = 3, y = 3},
    rules = {{when = "card_scored", only = {{id = "suit", v = "Hearts"}}, give = {{id = "mult", n = 50}}}}})
  local t = D.from_template("tarot", D.templates("tarot")[1])
  t.id, t.kind, t.mode, t.name, t.enabled, t.created = "oldtarot", "tarot", "simple", "Old Fool", true, 2
  Store.put_item(t)
  JokerForge.joker.register_all()
  local K = rawget(_G, "ForgeKinds")
  if K and K.refresh then pcall(K.refresh, "oldtarot") end
  FRW.old_rules = json.encode(Store.get("oldie").rules)
  HLOG("frw_old", FRW.old_rules, Store.get_item("oldtarot") and Store.get_item("oldtarot").mode)
end

function FRW.resave_old()
  local B = ForgeBuilder
  B.edit("oldie")
  local d = B.state.draft
  HLOG("frw_old_edit", d and d.mode, d and #d.rules)
  B.save()
  local now = json.encode(Store.get("oldie").rules)
  HLOG("frw_old_resave", now == FRW.old_rules and "SAME" or ("CHANGED " .. now))
  B.edit("oldtarot")
  HLOG("frw_old_tarot_edit", B.state.draft and B.state.draft.mode)
end

function FRW.add(name) FPLAY.add(FRW.ids[name] or name) end

function FRW.clear()
  for i = #G.jokers.cards, 1, -1 do
    local c = G.jokers.cards[i]
    c:remove_from_deck()
    G.jokers:remove_card(c)
    c:remove()
  end
end

function FRW.deck(tag)
  HLOG("frw_deck", tag, #G.playing_cards, G.deck and #G.deck.cards, G.deck and G.deck.config.card_limit)
  FRW.last = #G.playing_cards
end

local function find(name)
  local key = "j_forge_" .. tostring(FRW.ids[name] or name)
  for _, c in ipairs(G.jokers.cards) do if c.config.center.key == key then return c end end
end

function FRW.piggy()
  local c = find("piggy")
  local before = c and c.sell_cost
  if c then c:calculate_joker({end_of_round = true}) end
  HLOG("frw_piggy", before, c and c.sell_cost, c and c.sell_cost == before + 3 and "OK" or "BAD")
end

function FRW.buy()
  local c = find("counter")
  if c then c:calculate_joker({buying_card = true, card = {}}) end
  local v = c and c.ability.extra.vars and c.ability.extra.vars[1]
  HLOG("frw_counter", v, v == 175 and "OK" or "BAD")
end

function FRW.hover(name)
  local c = find(name)
  if c then c:hover() end
end
