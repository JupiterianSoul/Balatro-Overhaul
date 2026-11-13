FV = FV or {}

local R = require("functions/forge/forge_rules")

FV.RULES = {
  {when = "card_scored", only = {{id = "suit", v = "Hearts"}}, give = {{id = "var_add", var = 1, n = 1}}},
  {when = "hand_played", give = {{id = "var_mult", var = 1, n = 2}}},
  {when = "hand_played", only = {{id = "var", var = 1, op = "at_least", n = 3}}, give = {{id = "money", n = 3}, {id = "var_set", var = 1, n = 0}}},
}

function FV.make()
  local c = JokerForge.store.put({id = "charger", name = "Charger", rarity = 2, cost = 6, enabled = true, mode = "advanced", art = {atlas = "Joker", x = 4, y = 2}, vars = {{name = "Charge", start = 0}}, rules = FV.RULES})
  JokerForge.joker.register_all()
  FPLAY.id = "charger"
  HLOG("forge_vars_make", c and c.id, c and c.vars and #c.vars, c and #c.rules)
end

function FV.draft()
  local B = JokerForge.builder
  B.new_draft({kind = "joker", mode = "advanced", name = "Charger"})
  local d = B.state.draft
  d.vars = {{name = "Charge", start = 0}, {name = "Combo", start = 2}}
  d.rules = {
    {when = "card_scored", only = {{id = "suit", v = "Hearts"}, {id = "rank", v = "face", neg = true}}, give = {{id = "var_add", var = 1, n = 1}}, alt = {{id = "chips", n = 10}}},
    {when = "hand_played", only = {{id = "var", var = 1, op = "at_least", n = 3}}, give = {{id = "var_mult", var = 1, n = 2}, {id = "var_set", var = 1, n = 0}}},
  }
  B.state.rule_i = 1
  B.state.sec = "rules"
  JokerForge.ui.reopen("builder")
end

function FV.sec(s)
  JokerForge.builder.state.sec = s
  JokerForge.ui.reopen("builder")
end

function FV.rule(i)
  JokerForge.builder.state.rule_i = i
  JokerForge.ui.reopen("builder")
end

function FV.charge()
  for _, c in ipairs(G.jokers.cards) do
    if c.config.center.key == "j_forge_charger" then return R.var_val(c, 1) end
  end
  return -1
end

function FV.log(tag)
  HLOG("forge_vars", tag, "charge", FV.charge(), "dollars", G.GAME.dollars)
end

return FV
