FBIG = FBIG or {}

local Store = JokerForge.store

function FBIG.make()
  Store.put({id = "bigre", name = "Big Echo", rarity = 3, cost = 8, enabled = true, art = {atlas = "Joker", x = 5, y = 5},
    text = {en = {"{C:hearts}Hearts{} give {C:mult}+100{} Mult", "and retrigger {C:attention}9{} times"}},
    rules = {{when = "card_scored", only = {{id = "suit", v = "Hearts"}}, give = {{id = "mult", n = 100}, {id = "retrigger", n = 9}}}}})
  Store.put({id = "perma", name = "Whetstone", rarity = 1, cost = 4, enabled = true, art = {atlas = "Joker", x = 8, y = 4},
    rules = {{when = "card_scored", give = {{id = "perma_chips", n = 25}}}}})
  Store.put({id = "huge", name = "Thousand", rarity = 4, cost = 20, enabled = true, art = {atlas = "Joker", x = 3, y = 7},
    rules = {{when = "hand_played", give = {{id = "xmult", n = 1000}}}}})
  Store.put({id = "bossy", name = "Gatekeeper", rarity = 2, cost = 6, enabled = true, art = {atlas = "Joker", x = 1, y = 9},
    rules = {{when = "blind_selected", give = {{id = "disable_boss"}}}, {when = "round_end", give = {{id = "tag", v = "tag_d_six"}}}}})
  JokerForge.joker.register_all()
  local c = Store.get and Store.get("bigre")
  HLOG("forge_big_made", #Store.all(), c and c.rules and c.rules[1].give[2].n)
end

function FBIG.clear()
  for i = #G.jokers.cards, 1, -1 do
    local j = G.jokers.cards[i]
    j:remove()
  end
  G.jokers.cards = {}
end

function FBIG.check_perma()
  local best = 0
  for _, c in ipairs(G.discard.cards) do best = math.max(best, tonumber(c.ability and c.ability.perma_bonus) or 0) end
  FPLAY.results[#FPLAY.results + 1] = best == 25
  HLOG("forge_score", "played card gained chips forever", "got", best, "expect", 25, best == 25 and "OK" or "BAD")
end

function FBIG.hover(key)
  for _, j in ipairs(G.jokers.cards) do
    if j.config.center.key == key then j:hover() end
  end
end
