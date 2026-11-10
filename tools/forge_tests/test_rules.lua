package.path = "assets/?.lua;" .. package.path
local R = require("functions/forge/forge_rules")
local T = require("functions/forge/forge_text")

local fails, total = 0, 0
local function check(name, ok)
  total = total + 1
  if not ok then fails = fails + 1; print("FAIL " .. name) end
end

local log = {}
local rnd = 0.5
local function reset_game()
  log = {dollars = 0, hands = 0, discards = 0, levels = 0, created = {}, status = {}, sounds = 0}
  G = {
    play = {name = "play"}, hand = {name = "hand"},
    jokers = {cards = {}, config = {card_limit = 5}, emplace = function(self, c) self.cards[#self.cards + 1] = c end},
    consumeables = {cards = {}, config = {card_limit = 2}, emplace = function(self, c) self.cards[#self.cards + 1] = c end},
    GAME = {dollars = 10, probabilities = {normal = 1}, current_round = {hands_left = 3, discards_left = 2, hands_played = 0}, round_resets = {ante = 2}, blind = {boss = false}, joker_buffer = 0, consumeable_buffer = 0},
    C = {MONEY = {}, MULT = {}, CHIPS = {}, BLUE = {}, RED = {}, FILTER = {}, SECONDARY_SET = {Planet = {}, Tarot = {}, Spectral = {}}},
    E_MANAGER = {add_event = function(_, e) e.func() end},
    P_CENTERS = {m_gold = {key = "m_gold"}, m_glass = {key = "m_glass"}},
    P_CARDS = {H_K = {suit = "Hearts", value = "King"}, S_A = {suit = "Spades", value = "Ace"}},
  }
end
reset_game()
Event = function(t) return t end
localize = function(a)
  if type(a) == "table" then return a.key .. ":" .. table.concat(a.vars or {}, ",") end
  return a
end
card_eval_status_text = function(card, kind, amt, pct, dir, extra) log.status[#log.status + 1] = extra and extra.message end
ease_dollars = function(n) log.dollars = log.dollars + n end
ease_hands_played = function(n) log.hands = log.hands + n end
ease_discard = function(n) log.discards = log.discards + n end
level_up_hand = function(card, hand) log.levels = log.levels + 1; log.level_hand = hand end
play_sound = function() log.sounds = log.sounds + 1 end
pseudorandom = function() return rnd end
create_card = function(kind, area)
  log.created[#log.created + 1] = kind
  return {add_to_deck = function() end, start_materialize = function() end}
end

local function pcard(suit, id, o)
  o = o or {}
  local c = {base = {suit = suit, id = id}, config = {center = {key = o.enh or "c_base"}}, seal = o.seal, edition = o.edition, debuff = o.debuff}
  function c:get_id() return self.base.id end
  function c:is_face() return self.base.id >= 11 and self.base.id <= 13 end
  function c:is_suit(s) return self.base.suit == s end
  function c:change_suit(s) self.base.suit = s end
  function c:set_base(p) self.base.suit = p.suit; self.base.id = ({King = 13, Ace = 14})[p.value] end
  function c:set_seal(s) self.seal = s end
  function c:set_ability(center) self.config.center = center end
  function c:juice_up() end
  return c
end

local function joker()
  local j = {ability = {extra = {chips = 0, mult = 0, xmult = 1}}, config = {center = {forge_id = "t1", key = "j_forge_t1"}}, T = {}, children = {center = {pinch = {}}}, states = {drag = {}}}
  function j:juice_up() end
  function j:remove() self.removed = true end
  j.area = {remove_card = function() end}
  return j
end

local function ctx_for(when, extra)
  local ace = pcard("Hearts", 14)
  local hand = {ace, pcard("Spades", 14)}
  local ph = {Pair = {{}}, ["High Card"] = {{}}}
  local base = {
    card_scored = {cardarea = G.play, individual = true, other_card = ace, full_hand = hand, scoring_hand = hand, scoring_name = "Pair", poker_hands = ph},
    card_held = {cardarea = G.hand, individual = true, other_card = pcard("Clubs", 5), full_hand = hand, scoring_hand = hand, scoring_name = "Pair", poker_hands = ph},
    hand_played = {cardarea = G.jokers, joker_main = true, full_hand = hand, scoring_hand = hand, scoring_name = "Pair", poker_hands = ph},
    before = {cardarea = G.jokers, before = true, full_hand = hand, scoring_hand = hand, scoring_name = "Pair", poker_hands = ph},
    after = {cardarea = G.jokers, after = true, full_hand = hand, scoring_hand = hand, scoring_name = "Pair", poker_hands = ph},
    discard = {discard = true, other_card = ace, full_hand = hand},
    first_hand = {first_hand_drawn = true},
    blind_selected = {setting_blind = true},
    round_end = {end_of_round = true},
    blind_skipped = {skip_blind = true},
    reroll = {reroll_shop = true},
    shop_end = {ending_shop = true},
    card_sold = {selling_card = true, card = {}},
    self_sold = {selling_self = true},
    pack_opened = {open_booster = true, card = {}},
    consumable_used = {using_consumeable = true, consumeable = {}},
    card_bought = {buying_card = true, card = {}},
    pack_skipped = {skipping_booster = true},
    cards_destroyed = {remove_playing_cards = true, removed = {}},
    card_added = {playing_card_added = true, cards = {}},
  }
  local c = base[when]
  for k, v in pairs(extra or {}) do c[k] = v end
  return c
end

for _, rule_when in ipairs(R.WHEN) do
  for _, ctx_when in ipairs(R.WHEN) do
    reset_game()
    local rules = R.clean_rules({{when = rule_when, give = {{id = "money", n = 2}}}})
    local ret = R.calculate(joker(), ctx_for(ctx_when), rules)
    local got = log.dollars + (ret and ret.dollars or 0)
    check("trigger " .. rule_when .. " in " .. ctx_when, (got == 2) == (rule_when == ctx_when))
  end
end

check("repetition is not an individual trigger", R.trigger_of({repetition = true, cardarea = G.play}) == "card_scored")
check("held cards at round end do not trigger", R.trigger_of({individual = true, cardarea = G.hand, end_of_round = true}) == nil)

local function fires(only, when, extra)
  reset_game()
  local rules = R.clean_rules({{when = when or "card_scored", only = {only}, give = {{id = "mult", n = 3}}}})
  if #rules[1].only == 0 then return "dropped" end
  local ret = R.calculate(joker(), ctx_for(when or "card_scored", extra), rules)
  return ret ~= nil and ret.mult == 3 or (ret ~= nil and ret.mult_mod == 3 or (ret ~= nil and ret.h_mult == 3))
end

check("hand contains", fires({id = "hand", v = "Pair"}) == true)
check("hand contains fails", fires({id = "hand", v = "Flush"}) == false)
check("hand is", fires({id = "hand", v = "Pair", mode = "is"}, "hand_played") == true)
check("hand is fails", fires({id = "hand", v = "High Card", mode = "is"}, "hand_played") == false)
check("suit", fires({id = "suit", v = "Hearts"}) == true)
check("suit fails", fires({id = "suit", v = "Clubs"}) == false)
check("suit red", fires({id = "suit", v = "red"}) == true)
check("suit black fails", fires({id = "suit", v = "black"}) == false)
check("rank", fires({id = "rank", v = 14}) == true)
check("rank fails", fires({id = "rank", v = 2}) == false)
check("rank face fails on ace", fires({id = "rank", v = "face"}) == false)
check("rank face", fires({id = "rank", v = "face"}, "card_scored", {other_card = pcard("Spades", 12)}) == true)
check("rank number", fires({id = "rank", v = "number"}, "card_held") == true)
check("rank odd", fires({id = "rank", v = "odd"}) == true)
check("rank even fails", fires({id = "rank", v = "even"}) == false)
check("enhancement", fires({id = "enhancement", v = "m_gold"}, "card_scored", {other_card = pcard("Hearts", 3, {enh = "m_gold"})}) == true)
check("enhancement fails", fires({id = "enhancement", v = "m_gold"}) == false)
check("seal", fires({id = "seal", v = "Red"}, "card_scored", {other_card = pcard("Hearts", 3, {seal = "Red"})}) == true)
check("seal fails", fires({id = "seal", v = "Blue"}) == false)
check("edition", fires({id = "edition", v = "foil"}, "card_scored", {other_card = pcard("Hearts", 3, {edition = {foil = true}})}) == true)
check("edition fails", fires({id = "edition", v = "holo"}) == false)
check("cards played", fires({id = "cards_played", op = "at_most", n = 2}) == true)
check("cards played fails", fires({id = "cards_played", op = "at_least", n = 5}) == false)
check("money", fires({id = "money", op = "at_least", n = 10}) == true)
check("money fails", fires({id = "money", op = "at_least", n = 20}) == false)
check("hands left", fires({id = "hands_left", op = "exactly", n = 3}) == true)
check("discards left fails", fires({id = "discards_left", op = "exactly", n = 0}) == false)
check("first hand", fires({id = "first_hand"}) == true)
check("last hand fails", fires({id = "last_hand"}) == false)
check("ante", fires({id = "ante", op = "at_least", n = 2}) == true)
check("ante fails", fires({id = "ante", op = "at_least", n = 3}) == false)
check("jokers", fires({id = "jokers", op = "at_most", n = 2}) == true)
check("boss fails", fires({id = "boss"}) == false)
rnd = 0.2
check("chance hits", fires({id = "chance", n = 4}) == true)
rnd = 0.3
check("chance misses", fires({id = "chance", n = 4}) == false)
rnd = 0.3
reset_game()
G.GAME.probabilities.normal = 2
do
  local rules = R.clean_rules({{when = "card_scored", only = {{id = "chance", n = 4}}, give = {{id = "mult", n = 3}}}})
  check("chance uses the game's probability (Oops All 6s)", R.calculate(joker(), ctx_for("card_scored"), rules) ~= nil)
end
rnd = 0.5
check("card condition is dropped on a hand trigger", fires({id = "suit", v = "Hearts"}, "hand_played") == "dropped")

local function run(when, give, extra, card)
  reset_game()
  local rules = R.clean_rules({{when = when, give = {give}}})
  local j = card or joker()
  return R.calculate(j, ctx_for(when, extra), rules), j, rules
end

local ret = run("card_scored", {id = "chips", n = 30})
check("chips on a scored card", ret and ret.chips == 30 and ret.card ~= nil)
ret = run("hand_played", {id = "chips", n = 30})
check("chips on the hand", ret and ret.chip_mod == 30 and ret.message == "a_chips:30")
ret = run("card_scored", {id = "mult", n = 4})
check("mult on a scored card", ret and ret.mult == 4)
ret = run("card_held", {id = "mult", n = 4})
check("mult from a held card", ret and ret.h_mult == 4 and ret.mult == nil)
ret = run("hand_played", {id = "mult", n = 4})
check("mult on the hand", ret and ret.mult_mod == 4)
ret = run("card_scored", {id = "xmult", n = 1.5})
check("xmult on a scored card", ret and ret.x_mult == 1.5)
ret = run("hand_played", {id = "xmult", n = 2})
check("xmult on the hand", ret and ret.Xmult_mod == 2 and ret.message == "a_xmult:2")
ret = run("card_scored", {id = "money", n = 3})
check("money on a scored card goes through the engine", ret and ret.dollars == 3 and log.dollars == 0)
ret = run("round_end", {id = "money", n = 3})
check("money at round end", ret == nil and log.dollars == 3)
reset_game()
do
  local rules = R.clean_rules({{when = "card_scored", give = {{id = "retrigger", n = 2}}}})
  local r = R.calculate(joker(), ctx_for("card_scored", {repetition = true, individual = false}), rules)
  check("retrigger", r and r.repetitions == 2)
  check("retrigger gives nothing on the scoring pass", R.calculate(joker(), ctx_for("card_scored"), rules) == nil)
end
do
  local j = joker()
  run("round_end", {id = "gain_mult", n = 2}, nil, j)
  run("round_end", {id = "gain_mult", n = 2}, nil, j)
  run("discard", {id = "gain_chips", n = 5}, nil, j)
  run("blind_selected", {id = "gain_xmult", n = 0.25}, nil, j)
  check("scaling is stored on the card", j.ability.extra.mult == 4 and j.ability.extra.chips == 5 and j.ability.extra.xmult == 1.25)
  local r = R.calculate(j, ctx_for("hand_played"), {})
  check("scaling is given when a hand is played", r and r.mult_mod == 4 and r.chip_mod == 5 and r.Xmult_mod == 1.25)
  local bp = joker()
  local r2 = R.calculate(j, ctx_for("round_end", {blueprint = 1, blueprint_card = bp}), R.clean_rules({{when = "round_end", give = {{id = "gain_mult", n = 2}}}}))
  check("blueprint does not scale the original", j.ability.extra.mult == 4 and r2 == nil)
  local r3 = R.calculate(j, ctx_for("hand_played", {blueprint = 1, blueprint_card = bp}), {})
  check("blueprint copies the current value", r3 and r3.mult_mod == 4)
end
ret = run("blind_selected", {id = "create", v = "Tarot"})
check("create a tarot", log.created[1] == "Tarot" and #G.consumeables.cards == 1)
reset_game()
G.consumeables.cards = {{}, {}}
R.calculate(joker(), ctx_for("blind_selected"), R.clean_rules({{when = "blind_selected", give = {{id = "create", v = "Planet"}}}}))
check("create needs room", #log.created == 0)
ret = run("round_end", {id = "create", v = "Joker"})
check("create a joker", log.created[1] == "Joker" and #G.jokers.cards == 1)
ret = run("before", {id = "level_up"})
check("level up the played hand", log.levels == 1 and log.level_hand == "Pair")
ret = run("first_hand", {id = "level_up"})
check("level up not allowed on first hand", log.levels == 0)
do
  reset_game()
  local a, b = pcard("Hearts", 5), pcard("Spades", 9)
  local hand = {a, b}
  local rules = R.clean_rules({{when = "card_scored", only = {{id = "suit", v = "Hearts"}}, give = {{id = "change", what = "enhancement", v = "m_gold"}, {id = "mult", n = 1}}}})
  local r = R.calculate(joker(), ctx_for("before", {scoring_hand = hand, full_hand = hand}), rules)
  check("change the card happens before scoring, only on matching cards", a.config.center.key == "m_gold" and b.config.center.key == "c_base" and r and r.message == "k_upgrade_ex")
  R.calculate(joker(), ctx_for("before", {scoring_hand = hand}), R.clean_rules({{when = "card_scored", give = {{id = "change", what = "suit", v = "Clubs"}}}}))
  check("change suit", a.base.suit == "Clubs" and b.base.suit == "Clubs")
  R.calculate(joker(), ctx_for("before", {scoring_hand = hand}), R.clean_rules({{when = "card_scored", give = {{id = "change", what = "seal", v = "Gold"}}}}))
  check("change seal", a.seal == "Gold")
  G.P_CARDS.C_A = {suit = "Clubs", value = "Ace"}
  R.calculate(joker(), ctx_for("before", {scoring_hand = hand}), R.clean_rules({{when = "card_scored", give = {{id = "change", what = "rank", v = 14}}}}))
  check("change rank", a.base.id == 14)
end
ret = run("blind_selected", {id = "hand", n = 1})
check("+1 hand", log.hands == 1)
ret = run("discard", {id = "discard", n = 2})
check("+2 discards", log.discards == 2)
ret = run("hand_played", {id = "hand", n = 1})
check("+hand allowed while playing", log.hands == 1)
ret = run("shop_end", {id = "hand", n = 1})
check("+hand not allowed in the shop", log.hands == 0)
do
  local j = joker()
  run("round_end", {id = "destroy_self"}, nil, j)
  check("destroy this joker", j.removed == true and j.forge_dying == true)
end

reset_game()
do
  local bad = pcard("Hearts", 14)
  bad.get_id = function() error("broken card") end
  local rules = R.clean_rules({
    {when = "card_scored", only = {{id = "rank", v = 14}}, give = {{id = "mult", n = 5}}},
    {when = "card_scored", give = {{id = "chips", n = 10}}},
  })
  local before = R.errors
  local r = R.calculate(joker(), ctx_for("card_scored", {other_card = bad}), rules)
  check("a bad rule does nothing, the others still work", r and r.chips == 10 and r.mult == nil)
  R.calculate(joker(), ctx_for("card_scored", {other_card = bad}), rules)
  check("a bad rule logs once", R.errors == before + 1)
end

local cleaned = R.clean_rules({
  {when = "nope", give = {{id = "mult"}}},
  {when = "card_scored", only = {{id = "nope"}, {id = "money", op = "weird", n = 999}}, give = {{id = "mult", n = 999}, {id = "level_up"}, {id = "chips", n = -5}}},
  "junk",
})
check("clean drops unknown triggers and junk", #cleaned == 1)
check("clean drops unknown conditions and keeps big numbers", #cleaned[1].only == 1 and cleaned[1].only[1].n == 999 and cleaned[1].only[1].op == "at_least")
check("clean drops effects the trigger cannot run and keeps big numbers", #cleaned[1].give == 2 and cleaned[1].give[1].n == 999 and cleaned[1].give[2].n == 5)
do
  local many = {}
  for i = 1, 20 do many[i] = {when = "card_scored"} end
  check("clean keeps up to the rule limit", #R.clean_rules(many) == R.MAX_RULES and R.MAX_RULES >= 8)
end
check("xmult keeps what was typed", R.num("xmult", 1.33) == 1.33 and R.num("xmult", 0) == 1.1)
check("numbers have no small cap", R.num("retrigger", 50) == 50 and R.num("mult", 123456789) == 123456789 and R.num("chips", 1e12) == 1e12 and R.num("money", 777) == 777)
check("only a hidden safety bound", R.num("retrigger", 1e9) == R.MANY and R.num("mult", 1e30) == R.BIG)
check("whole numbers stay whole", R.num("mult", 4.6) == 5 and R.num("chips", 37) == 37)

local bad_text = 0
for _, lang in ipairs({"en", "fr", "es"}) do
  for _, when in ipairs(R.WHEN) do
    local onlys, gives = {}, {}
    for _, id in ipairs(R.ONLY) do if R.allowed_only(when, id) then onlys[#onlys + 1] = R.default_only(id) end end
    for _, id in ipairs(R.GIVE) do if R.allowed_give(when, id) then gives[#gives + 1] = R.default_give(id) end end
    for _, o in ipairs(onlys) do
      for _, g in ipairs(gives) do
        local s = T.sentence({when = when, only = {o}, give = {g}}, lang)
        if not s or s:find("%%") or s:find("nil") or T.visible_len(s) < 10 then bad_text = bad_text + 1; print("BAD " .. lang .. " " .. tostring(s)) end
      end
    end
  end
end
check("every sentence is written in en, fr and es", bad_text == 0)
local lines = T.lines({rules = R.clean_rules({{when = "card_scored", only = {{id = "suit", v = "Hearts"}}, give = {{id = "mult", n = 4}}}, {when = "round_end", give = {{id = "gain_mult", n = 1}, {id = "create", v = "Planet"}}}})}, "en")
local wide = false
for _, l in ipairs(lines) do if T.visible_len(l) > T.WIDTH and l:find(" ") and not l:find("^{C:inactive}") then wide = true end end
check("lines are wrapped", #lines >= 4 and not wide)
check("first sentence", lines[1] == "When a card scores, if it is" and lines[2]:find("{C:hearts}Heart{}", 1, true) ~= nil)
check("currently line", lines[#lines - 1]:find("#3#", 1, true) ~= nil and lines[#lines] == "{C:inactive}(Must have room){}")
local span = T.wrap("aaaa {C:attention}Full House{} bbbb cccc dddd", 12)
check("a coloured span is never split", span[2] == "{C:attention}Full House{}" or span[1]:find("Full House", 1, true) ~= nil)
check("own text wins", T.lines({rules = {}, text = {en = {"Hi"}}}, "en")[1] == "Hi")
check("vars", table.concat(T.vars({ability = {extra = {chips = 5, mult = 2, xmult = 1.5}}}), ",") == "1,5,2,1.5,0,0,0,0")

do
  local hearts = pcard("Hearts", 5)
  local spades = pcard("Spades", 5)
  local neg = R.clean_rules({{when = "card_scored", only = {{id = "suit", v = "Hearts", neg = true}}, give = {{id = "mult", n = 4}}}})
  check("not: kept by clean", neg[1].only[1].neg == true)
  check("not: a Heart does not fire", R.calculate(joker(), ctx_for("card_scored", {other_card = hearts}), neg) == nil)
  local r = R.calculate(joker(), ctx_for("card_scored", {other_card = spades}), neg)
  check("not: a Spade fires", r ~= nil and r.mult == 4)
  check("not: chance can not be flipped", R.clean_rules({{when = "card_scored", only = {{id = "chance", n = 2, neg = true}}, give = {{id = "mult", n = 1}}}})[1].only[1].neg == nil)
  local alt = R.clean_rules({{when = "card_scored", only = {{id = "suit", v = "Hearts"}}, give = {{id = "mult", n = 4}}, alt = {{id = "chips", n = 10}, {id = "change", what = "suit", v = "Clubs"}}}})
  check("otherwise: kept, change dropped", alt[1].alt and #alt[1].alt == 1 and alt[1].alt[1].id == "chips")
  local a = R.calculate(joker(), ctx_for("card_scored", {other_card = hearts}), alt)
  check("otherwise: the rule fires when it matches", a ~= nil and a.mult == 4 and a.chips == nil)
  local b = R.calculate(joker(), ctx_for("card_scored", {other_card = spades}), alt)
  check("otherwise: the other list fires when it does not", b ~= nil and b.chips == 10 and b.mult == nil)
  check("otherwise: dropped with no condition", R.clean_rules({{when = "hand_played", give = {{id = "mult", n = 1}}, alt = {{id = "chips", n = 5}}}})[1].alt == nil)
  local hp = R.calculate(joker(), ctx_for("hand_played", {scoring_name = "Flush"}), R.clean_rules({{when = "hand_played", only = {{id = "hand", mode = "is", v = "Pair"}}, give = {{id = "mult", n = 8}}, alt = {{id = "chips", n = 30}}}}))
  check("otherwise: hand played", hp ~= nil and hp.chip_mod == 30 and hp.mult_mod == nil)
  local txt = table.concat(T.lines({rules = R.clean_rules({{when = "card_scored", only = {{id = "rank", v = "face", neg = true}}, give = {{id = "mult", n = 4}}, alt = {{id = "money", n = 1}}}})}, "en"), " ")
  check("text: unless and otherwise", txt:find("unless", 1, true) ~= nil and txt:find("otherwise", 1, true) ~= nil)
  for _, l in ipairs({"fr", "es"}) do
    local t2 = table.concat(T.lines({rules = R.clean_rules({{when = "card_scored", only = {{id = "rank", v = "face", neg = true}}, give = {{id = "mult", n = 4}}, alt = {{id = "money", n = 1}}}})}, l), " ")
    check("text: unless and otherwise in " .. l, t2:find(l == "fr" and "sauf si" or "salvo si", 1, true) ~= nil and t2:find(l == "fr" and "sinon" or "si no", 1, true) ~= nil)
  end
end

do
  reset_game()
  local defs = R.clean_vars({{name = "Charge", start = 2}, {name = " Bad{#}%Name ", start = 5000}, {name = ""}, {name = "x"}, {name = "too many"}})
  check("vars: at most 4", #defs == 4)
  check("vars: start kept", defs[1].name == "Charge" and defs[1].start == 2)
  check("vars: name cleaned and start kept", defs[2].name == "BadName" and defs[2].start == 5000)
  check("vars: empty name gets a fallback", defs[3].name == "V3")
  check("vars: long name cut", #R.clean_name("abcdefghijklmnopq") == R.VAR_NAME)
  local rules = R.clean_rules({
    {when = "card_scored", only = {{id = "suit", v = "Hearts"}}, give = {{id = "var_add", var = 1, n = 1}}},
    {when = "hand_played", give = {{id = "var_mult", var = 1, n = 2}}},
    {when = "hand_played", only = {{id = "var", var = 1, op = "at_least", n = 4}}, give = {{id = "money", n = 3}, {id = "var_set", var = 1, n = 0}}},
    {when = "card_held", give = {{id = "var_chips", var = 9, n = 5}}},
  })
  check("vars: rules kept", #rules == 4 and rules[1].give[1].var == 1 and rules[3].only[1].var == 1)
  check("vars: var chips not allowed for held cards", #rules[4].give == 0)
  local j = joker()
  local hearts = pcard("Hearts", 5)
  R.calculate(j, ctx_for("card_scored", {other_card = hearts}), rules, defs)
  check("vars: start value then +1", R.var_val(j, 1) == 3)
  local hp = R.calculate(j, ctx_for("hand_played"), rules, defs)
  check("vars: mult for each point", hp ~= nil and hp.mult_mod == 6 and log.dollars == 0)
  R.calculate(j, ctx_for("card_scored", {other_card = hearts}), rules, defs)
  local hp2 = R.calculate(j, ctx_for("hand_played"), rules, defs)
  check("vars: condition reads it and set resets it", hp2 ~= nil and hp2.mult_mod == 8 and log.dollars == 3 and R.var_val(j, 1) == 0)
  local bp = R.calculate(j, ctx_for("card_scored", {other_card = hearts, blueprint = true, blueprint_card = joker()}), rules, defs)
  check("vars: blueprint does not change them", R.var_val(j, 1) == 0 and bp == nil)
  local sub = R.clean_rules({{when = "round_end", give = {{id = "var_add", var = 1, n = -5}}}})
  R.calculate(j, ctx_for("round_end"), sub, defs)
  check("vars: never below zero", R.var_val(j, 1) == 0)
  local vv = T.vars(nil, defs)
  check("vars: card text vars use the start", vv[5] == "2" and vv[6] == "5000" and vv[8] == "0")
  local lines = table.concat(T.lines({rules = rules, vars = defs}, "en"), " ")
  check("vars: text names the variable", lines:find("Charge", 1, true) ~= nil and lines:find("#5#", 1, true) ~= nil)
  check("vars: text has no stray braces from the name", T.give_text({id = "var_add", var = 2, n = 1}, "en", defs):find("BadName", 1, true) ~= nil)
  for _, l in ipairs({"fr", "es"}) do
    local t2 = table.concat(T.lines({rules = rules, vars = defs}, l), " ")
    check("vars: text in " .. l, t2:find("Charge", 1, true) ~= nil and not t2:find("%%s"))
  end
  check("vars: take text for a negative change", T.give_text({id = "var_add", var = 1, n = -2}, "en", defs):find("take", 1, true) ~= nil)
end

do
  reset_game()
  local rules = R.clean_rules({{when = "card_scored", only = {{id = "rank", v = 14}}, give = {{id = "destroy_card"}, {id = "mult", n = 2}}}})
  check("new: destroy_card kept on card_scored", #rules[1].give == 2)
  local ace, two = pcard("Hearts", 14), pcard("Spades", 2)
  check("new: destroying an ace", R.calculate(joker(), {destroying_card = ace, full_hand = {ace}}, rules) == true)
  check("new: not destroying a two", R.calculate(joker(), {destroying_card = two, full_hand = {two}}, rules) == nil)
  check("new: blueprint never destroys", R.calculate(joker(), {destroying_card = ace, full_hand = {ace}, blueprint = 1}, rules) == nil)
  local sc = R.calculate(joker(), ctx_for("card_scored"), rules)
  check("new: destroy rule still gives on scoring", sc ~= nil and sc.mult == 2)
  local old = R.clean_rules({{when = "card_scored", give = {{id = "mult", n = 2}}}})
  check("new: old rules never destroy", R.calculate(joker(), {destroying_card = ace, full_hand = {ace}}, old) == nil)
  local dr = R.clean_rules({{when = "discard", give = {{id = "destroy_card"}}}})
  local d = R.calculate(joker(), ctx_for("discard"), dr)
  check("new: discard destroy returns remove", d ~= nil and d.remove == true)
  check("new: destroy_card not on hand_played", #R.clean_rules({{when = "hand_played", give = {{id = "destroy_card"}}}})[1].give == 0)
end

do
  reset_game()
  local made = 0
  G.deck = {cards = {1, 2, 3}, config = {card_limit = 52}}
  G.P_CARDS.S_A = G.P_CARDS.S_A
  G.P_CENTERS.c_base = {key = "c_base"}
  G.P_CENTERS.m_stone = {key = "m_stone"}
  G.C.SECONDARY_SET.Enhanced = {}
  pseudorandom_element = function(t) return t.S_A end
  pseudoseed = function(s) return s end
  create_playing_card = function(init, area) made = made + 1; log.made_center = init.center end
  local rules = R.clean_rules({{when = "blind_selected", give = {{id = "add_card", v = "m_stone"}}}, {when = "round_end", give = {{id = "add_card", v = "bogus"}}}})
  check("new: add_card bad value falls back", rules[2].give[1].v == "c_base")
  R.calculate(joker(), ctx_for("blind_selected"), rules)
  check("new: add_card makes a stone card", made == 1 and log.made_center == G.P_CENTERS.m_stone and G.deck.config.card_limit == 53)
  local j = joker()
  j.ability.extra_value = 0
  j.set_cost = function(self) self.cost_set = true end
  R.calculate(j, ctx_for("round_end"), R.clean_rules({{when = "round_end", give = {{id = "sell_value", n = 3}}}}))
  check("new: sell_value grows", j.ability.extra_value == 3 and j.cost_set)
end

do
  reset_game()
  G.deck = {cards = {1, 2, 3, 4}}
  G.hand.cards = {1, 2}
  G.GAME.hands = {Pair = {level = 4}}
  G.GAME.round = 7
  G.GAME.blind = {name = "Big Blind", boss = false}
  local function fires(o, when)
    local rules = R.clean_rules({{when = when or "hand_played", only = {o}, give = {{id = "mult", n = 1}}}})
    return R.calculate(joker(), ctx_for(when or "hand_played"), rules) ~= nil
  end
  check("new: big blind", fires({id = "blind", v = "Big"}) and not fires({id = "blind", v = "Small"}) and not fires({id = "blind", v = "Boss"}))
  check("new: deck cards", fires({id = "deck_cards", op = "at_most", n = 4}) and not fires({id = "deck_cards", op = "at_least", n = 5}))
  check("new: held cards", fires({id = "held_cards", op = "exactly", n = 2}))
  check("new: hand level", fires({id = "hand_level", op = "at_least", n = 4}) and not fires({id = "hand_level", op = "at_least", n = 5}))
  check("new: round", fires({id = "round", op = "at_least", n = 7}))
  check("new: hand_level only on hand triggers", #R.clean_rules({{when = "round_end", only = {{id = "hand_level"}}, give = {{id = "money", n = 1}}}})[1].only == 0)
end

do
  check("uses_new: old card is old", not R.uses_new(R.clean_rules({{when = "card_scored", give = {{id = "chips", n = 300}}}}), {{name = "a", start = 100}}))
  check("uses_new: big chips are new", R.uses_new(R.clean_rules({{when = "card_scored", give = {{id = "chips", n = 305}}}})))
  check("uses_new: new trigger is new", R.uses_new({{when = "card_bought", give = {{id = "money", n = 1}}}}))
  check("uses_new: new var start is new", R.uses_new({}, {{name = "a", start = 101}}))
  for _, l in ipairs({"en", "fr", "es"}) do
    check("text: new ids in " .. l, T.give_text({id = "add_card", v = "m_stone"}, l) ~= "" and T.only_text({id = "blind", v = "Small"}, l) ~= "" and T.when_text("card_added", l) ~= "")
  end
end

do
  reset_game()
  local big = R.clean_rules({{when = "card_scored", give = {{id = "mult", n = 1e6}, {id = "chips", n = 5e9}}}, {when = "hand_played", give = {{id = "xmult", n = 1000}}}})
  local r = R.calculate(joker(), ctx_for("card_scored"), big)
  check("big: card gives a million mult and five billion chips", r and r.mult == 1e6 and r.chips == 5e9)
  local m = R.calculate(joker(), ctx_for("hand_played"), big)
  check("big: X1000 mult", m and m.Xmult_mod == 1000)
  local reps = R.clean_rules({{when = "card_scored", give = {{id = "retrigger", n = 50}}}})
  local rr = R.calculate(joker(), ctx_for("card_scored", {repetition = true, individual = false}), reps)
  check("big: retrigger 50 times", rr and rr.repetitions == 50)
  local two = R.clean_rules({{when = "card_scored", give = {{id = "retrigger", n = 800}}}, {when = "card_scored", give = {{id = "retrigger", n = 800}}}})
  local r2 = R.calculate(joker(), ctx_for("card_scored", {repetition = true, individual = false}), two)
  check("big: stacked retriggers stop at the safety bound", r2 and r2.repetitions == R.MANY)
  local money = R.clean_rules({{when = "round_end", give = {{id = "money", n = 250}}}})
  R.calculate(joker(), ctx_for("round_end"), money)
  check("big: $250 at the end of the round", log.dollars == 250)
  check("big: text shows the real number", T.give_text({id = "retrigger", n = 50}, "en"):find("50", 1, true) ~= nil and T.fmt_n(1234567) == "1234567" and T.fmt_n(5e12) == "5e12" and T.fmt_n(1.5e15) == "1.5e15")
end

do
  reset_game()
  local ace = pcard("Hearts", 14)
  ace.ability = {perma_bonus = 0}
  local perma = R.clean_rules({{when = "card_scored", give = {{id = "perma_chips", n = 15}}}})
  R.calculate(joker(), ctx_for("card_scored", {other_card = ace}), perma)
  check("new: the card gains chips forever", ace.ability.perma_bonus == 15)
  check("new: perma chips only when a card scores", #R.clean_rules({{when = "round_end", give = {{id = "perma_chips", n = 1}}}})[1].give == 0)
  local made = {}
  copy_card = function(c) local x = {src = c} function x:add_to_deck() end return x end
  G.deck = {config = {card_limit = 52}, emplace = function(_, c) made[#made + 1] = c end}
  G.playing_cards = {}
  R.calculate(joker(), ctx_for("card_scored", {other_card = ace}), R.clean_rules({{when = "card_scored", give = {{id = "copy_card"}}}}))
  check("new: copy the card into the deck", #made == 1 and made[1].src == ace and G.deck.config.card_limit == 53 and #G.playing_cards == 1)
  local tags = {}
  G.P_TAGS = {tag_double = {}, tag_d_six = {}}
  Tag = function(k) return {key = k} end
  add_tag = function(t) tags[#tags + 1] = t.key end
  R.calculate(joker(), ctx_for("round_end"), R.clean_rules({{when = "round_end", give = {{id = "tag", v = "tag_d_six"}}}}))
  R.calculate(joker(), ctx_for("round_end"), R.clean_rules({{when = "round_end", give = {{id = "tag", v = "tag_bogus"}}}}))
  check("new: create a tag, unknown tags become Double", tags[1] == "tag_d_six" and tags[2] == "tag_double")
  local disabled = 0
  G.GAME.blind = {boss = true, disable = function(self) self.disabled = true; disabled = disabled + 1 end}
  local db = R.clean_rules({{when = "blind_selected", give = {{id = "disable_boss"}}}})
  R.calculate(joker(), ctx_for("blind_selected"), db)
  R.calculate(joker(), ctx_for("blind_selected"), db)
  check("new: disable the boss once", disabled == 1 and G.GAME.blind.disabled == true)
  G.GAME.blind = {boss = false, disable = function() disabled = disabled + 1 end}
  R.calculate(joker(), ctx_for("blind_selected"), db)
  check("new: a small blind is left alone", disabled == 1)
  pseudorandom_element = function(list) return list[1] end
  pseudoseed = function(s) return s end
  local self_j = joker()
  local other_j, eternal_j = joker(), joker()
  eternal_j.ability.eternal = true
  G.jokers.cards = {self_j, eternal_j, other_j}
  R.calculate(self_j, ctx_for("round_end"), R.clean_rules({{when = "round_end", give = {{id = "destroy_joker"}}}}))
  check("new: destroy a random other joker, never itself or an eternal one", other_j.removed == true and not self_j.removed and not eternal_j.removed)
  local ed = pcard("Hearts", 14)
  function ed:set_edition(e) self.edition = e end
  R.calculate(joker(), ctx_for("before", {scoring_hand = {ed}}), R.clean_rules({{when = "card_scored", give = {{id = "change", what = "edition", v = "polychrome"}}}}))
  check("new: change the card's edition", type(ed.edition) == "table" and ed.edition.polychrome == true)
  check("new: text for every new action", T.give_text({id = "perma_chips", n = 15}, "en"):find("15", 1, true) and T.give_text({id = "copy_card"}, "fr") ~= "" and T.give_text({id = "disable_boss"}, "es") ~= "" and T.give_text({id = "destroy_joker"}, "en") ~= "" and T.give_text({id = "change", what = "edition", v = "foil"}, "en") ~= "")
end

do
  check("need_v: old card is v1", R.need_v(R.clean_rules({{when = "card_scored", give = {{id = "chips", n = 300}}}})) == 1)
  check("need_v: 2.0 values are v2", R.need_v(R.clean_rules({{when = "card_scored", give = {{id = "mult", n = 104}, {id = "retrigger", n = 5}}}})) == 2)
  check("need_v: values above 2.0 are v3", R.need_v(R.clean_rules({{when = "card_scored", give = {{id = "retrigger", n = 6}}}})) == 3)
  check("need_v: new actions are v3", R.need_v(R.clean_rules({{when = "card_scored", give = {{id = "perma_chips", n = 1}}}})) == 3)
  check("need_v: edition change is v3", R.need_v(R.clean_rules({{when = "card_scored", give = {{id = "change", what = "edition", v = "foil"}}}})) == 3)
  local seven = {}
  for i = 1, 7 do seven[i] = {when = "card_scored", give = {{id = "mult", n = 1}}} end
  check("need_v: more than six rules is v3", R.need_v(R.clean_rules(seven)) == 3)
end

print(string.format("%d checks, %d failed", total, fails))
os.exit(fails == 0 and 0 or 1)
