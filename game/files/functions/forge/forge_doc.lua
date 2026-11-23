local Cat = require("functions/forge/forge_catalog")
local R = require("functions/forge/forge_rules")
local T = require("functions/forge/forge_text")

local D = {}

D.DRAFT_KEY = {joker = "j_forge_draft", tarot = "c_forge_draft_tarot", planet = "c_forge_draft_planet", spectral = "c_forge_draft_spectral", voucher = "v_forge_draft", enhancement = "m_forge_draft", booster = "p_forge_draft", edition = "j_forge_draft_edition", seal = "c_forge_draft_seal", collab = "c_forge_draft_collab"}
D.CARD_EFFECTS = {enhance = true, seal = true, suit = true, rank_up = true, edition = true, destroy = true, copy = true}
D.MAX_RULES = R.MAX_RULES or 12
D.SIMPLE_RULES = 1

local function lang()
  local l = G and G.SETTINGS and G.SETTINGS.language or "en-us"
  if l == "fr" then return "fr" end
  if type(l) == "string" and l:sub(1, 2) == "es" then return "es" end
  return "en"
end
D.lang = lang

local function copy(v)
  if type(v) ~= "table" then return v end
  local t = {}
  for k, x in pairs(v) do t[k] = copy(x) end
  return t
end
D.copy = copy

function D.new(kind, o)
  o = o or {}
  local k = Cat.kind(kind)
  local d = {id = o.id, kind = k.id, name = o.name or mod_loc("New") .. " " .. mod_loc(k.label), mode = o.mode or "simple", enabled = o.enabled ~= false, created = o.created, text = o.text, art = o.art, from = type(o.from) == "string" and o.from or nil, faces = type(o.faces) == "table" and o.faces or nil, unset = o.unset == true or nil,
    look = require("functions/forge/forge_forcedlook").clean(o.look)}
  if k.rules then
    d.rarity = o.rarity or 1
    d.cost = o.cost or 4
    d.rules = o.rules or {{when = "hand_played", only = {}, give = {R.default_give("mult")}}}
    d.compat = o.compat or {blueprint = true, eternal = true, perishable = true}
    d.vars = o.vars or {}
    d.requires = type(o.requires) == "string" and o.requires ~= "none" and o.requires or nil
    d.always_ed = type(o.always_ed) == "string" and o.always_ed ~= "none" and o.always_ed or nil
    d.own_rarity = R.own_id("rarity", o.own_rarity) and o.own_rarity or nil
  else
    d.fields = Cat.clean_fields(k.id, o.fields)
    d.effects = o.effects or {}
    if R.host_of(k.id) ~= "joker" then
      d.rules = type(o.rules) == "table" and o.rules or {}
      d.vars = type(o.vars) == "table" and o.vars or {}
    end
    if o.effects == nil and (k.simple_max or 0) > 0 and k.id ~= "booster" then
      for _, e in ipairs(Cat.effects_for(k.id)) do
        if e.simple then d.effects[1] = Cat.default_effect(k.id, e.id) break end
      end
    end
  end
  return d
end

D.JOKER_TEMPLATES = {
  {key = "j_joker", rules = {{when = "hand_played", give = {{id = "mult", n = 4}}}}},
  {key = "j_greedy_joker", rules = {{when = "card_scored", only = {{id = "suit", v = "Diamonds"}}, give = {{id = "mult", n = 3}}}}},
  {key = "j_lusty_joker", rules = {{when = "card_scored", only = {{id = "suit", v = "Hearts"}}, give = {{id = "mult", n = 3}}}}},
  {key = "j_jolly", rules = {{when = "hand_played", only = {{id = "hand", v = "Pair"}}, give = {{id = "mult", n = 8}}}}},
  {key = "j_sly", rules = {{when = "hand_played", only = {{id = "hand", v = "Pair"}}, give = {{id = "chips", n = 50}}}}},
  {key = "j_scary_face", rules = {{when = "card_scored", only = {{id = "rank", v = "face"}}, give = {{id = "chips", n = 30}}}}},
  {key = "j_even_steven", rules = {{when = "card_scored", only = {{id = "rank", v = "even"}}, give = {{id = "mult", n = 4}}}}},
  {key = "j_scholar", rules = {{when = "card_scored", only = {{id = "rank", v = 14}}, give = {{id = "chips", n = 20}, {id = "mult", n = 4}}}}},
  {key = "j_business", rules = {{when = "card_scored", only = {{id = "rank", v = "face"}, {id = "chance", n = 2}}, give = {{id = "money", n = 2}}}}},
  {key = "j_8_ball", rules = {{when = "card_scored", only = {{id = "rank", v = 8}, {id = "chance", n = 4}}, give = {{id = "create", v = "Tarot"}}}}},
  {key = "j_dusk", rules = {{when = "card_scored", only = {{id = "last_hand"}}, give = {{id = "retrigger", n = 1}}}}},
  {key = "j_mystic_summit", rules = {{when = "hand_played", only = {{id = "discards_left", op = "exactly", n = 0}}, give = {{id = "mult", n = 15}}}}},
  {key = "j_green_joker", vars = {{name = "Mult", start = 0}}, rules = {
    {when = "before", give = {{id = "var_add", var = 1, n = 1}}},
    {when = "discard", only = {{id = "once_per_discard"}, {id = "var", var = 1, op = "at_least", n = 1}}, give = {{id = "var_add", var = 1, n = -1}}},
    {when = "hand_played", give = {{id = "var_mult", var = 1, n = 1}}},
  }},
  {key = "j_golden", rules = {{when = "round_end", give = {{id = "money", n = 4}}}}},
  {key = "j_gros_michel", rules = {{when = "hand_played", give = {{id = "mult", n = 15}}}, {when = "round_end", only = {{id = "chance", n = 6}}, give = {{id = "destroy_self"}}}}},
  {key = "j_cavendish", rules = {{when = "hand_played", give = {{id = "xmult", n = 3}}}}},
  {key = "j_space", rules = {{when = "before", only = {{id = "chance", n = 4}}, give = {{id = "level_up"}}}}},
  {key = "j_burglar", rules = {{when = "blind_selected", give = {{id = "hand", n = 3}}}}},
  {key = "j_midas_mask", rules = {{when = "card_scored", only = {{id = "rank", v = "face"}}, give = {{id = "change", what = "enhancement", v = "m_gold"}}}}},
  {key = "j_flash", rules = {{when = "reroll", give = {{id = "gain_mult", n = 2}}}}},
  {key = "j_ancient", vars = {{name = "Suit", type = "suit", start = "random"}}, rules = {{when = "card_scored", only = {{id = "suit", v = "var:1"}}, give = {{id = "xmult", n = 1.5}}}, {when = "round_end", give = {{id = "var_pick", var = 1, v = "random"}}}}},
  {key = "j_castle", vars = {{name = "Suit", type = "suit", start = "random"}}, rules = {{when = "discard", only = {{id = "suit", v = "var:1"}}, give = {{id = "gain_chips", n = 3}}}, {when = "round_end", give = {{id = "var_pick", var = 1, v = "random"}}}}},
  {key = "j_idol", vars = {{name = "Suit", type = "suit", start = "random"}, {name = "Rank", type = "rank", start = "random"}}, rules = {{when = "card_scored", only = {{id = "suit", v = "var:1"}, {id = "rank", v = "var:2"}}, give = {{id = "xmult", n = 2}}}, {when = "round_end", give = {{id = "var_pick", var = 1, v = "random"}, {id = "var_pick", var = 2, v = "random"}}}}},
  {key = "j_mail", vars = {{name = "Rank", type = "rank", start = "random"}}, rules = {{when = "discard", only = {{id = "rank", v = "var:1"}}, give = {{id = "money", n = 5}}}, {when = "round_end", give = {{id = "var_pick", var = 1, v = "random"}}}}},
  {key = "j_todo_list", vars = {{name = "Hand", type = "hand", start = "random"}}, rules = {{when = "hand_played", only = {{id = "hand", v = "var:1", mode = "is"}}, give = {{id = "money", n = 4}}}, {when = "round_end", give = {{id = "var_pick", var = 1, v = "random"}}}}},
  {key = "j_yorick", rules = {{when = "discard", only = {{id = "every", v = "event", n = 23}}, give = {{id = "gain_xmult", n = 1}}}}},
}

D.GAME_TEMPLATES = {
  tarot = {
    {key = "c_magician", fields = {select = 2}, effects = {{id = "enhance", v = "m_lucky"}}},
    {key = "c_empress", fields = {select = 2}, effects = {{id = "enhance", v = "m_mult"}}},
    {key = "c_heirophant", fields = {select = 2}, effects = {{id = "enhance", v = "m_bonus"}}},
    {key = "c_chariot", fields = {select = 1}, effects = {{id = "enhance", v = "m_steel"}}},
    {key = "c_devil", fields = {select = 1}, effects = {{id = "enhance", v = "m_gold"}}},
    {key = "c_star", fields = {select = 3}, effects = {{id = "suit", v = "Diamonds"}}},
    {key = "c_strength", fields = {select = 2}, effects = {{id = "rank_up", n = 1}}},
    {key = "c_hanged_man", fields = {select = 2}, effects = {{id = "destroy"}}},
    {key = "c_death", fields = {select = 2}, effects = {{id = "copy"}}},
    {key = "c_hermit", fields = {select = 0}, effects = {{id = "double_money", n = 20}}},
    {key = "c_high_priestess", fields = {select = 0}, effects = {{id = "create", v = "Planet", n = 2}}},
    {key = "c_emperor", fields = {select = 0}, effects = {{id = "create", v = "Tarot", n = 2}}},
    {key = "c_fool", fields = {select = 0}, effects = {{id = "last_used"}}},
    {key = "c_lovers", fields = {select = 1}, effects = {{id = "enhance", v = "m_wild"}}},
    {key = "c_justice", fields = {select = 1}, effects = {{id = "enhance", v = "m_glass"}}},
    {key = "c_wheel_of_fortune", fields = {select = 0}, effects = {{id = "chance", n = 4}, {id = "joker_edition", v = "random"}}},
    {key = "c_temperance", fields = {select = 0}, effects = {{id = "money", n = 20}}, approx = true},
    {key = "c_tower", fields = {select = 1}, effects = {{id = "enhance", v = "m_stone"}}},
    {key = "c_moon", fields = {select = 3}, effects = {{id = "suit", v = "Clubs"}}},
    {key = "c_sun", fields = {select = 3}, effects = {{id = "suit", v = "Hearts"}}},
    {key = "c_judgement", fields = {select = 0}, effects = {{id = "create", v = "Joker", n = 1}}, approx = true},
    {key = "c_world", fields = {select = 3}, effects = {{id = "suit", v = "Spades"}}},
  },
  planet = {
    {key = "c_mercury", fields = {hand = "Pair", levels = 1, chips = 15, mult = 1}},
    {key = "c_jupiter", fields = {hand = "Flush", levels = 1, chips = 15, mult = 2}},
    {key = "c_saturn", fields = {hand = "Straight", levels = 1, chips = 30, mult = 3}},
    {key = "c_black_hole", fields = {hand = "all", levels = 1}},
    {key = "c_venus", fields = {hand = "Three of a Kind", levels = 1, chips = 20, mult = 2}},
    {key = "c_earth", fields = {hand = "Full House", levels = 1, chips = 25, mult = 2}},
    {key = "c_mars", fields = {hand = "Four of a Kind", levels = 1, chips = 30, mult = 3}},
    {key = "c_uranus", fields = {hand = "Two Pair", levels = 1, chips = 20, mult = 1}},
    {key = "c_neptune", fields = {hand = "Straight Flush", levels = 1, chips = 40, mult = 4}},
    {key = "c_pluto", fields = {hand = "High Card", levels = 1, chips = 10, mult = 1}},
    {key = "c_planet_x", fields = {hand = "Five of a Kind", levels = 1, chips = 35, mult = 3}},
    {key = "c_ceres", fields = {hand = "Flush House", levels = 1, chips = 40, mult = 4}},
    {key = "c_eris", fields = {hand = "Flush Five", levels = 1, chips = 50, mult = 3}},
  },
  spectral = {
    {key = "c_familiar", fields = {select = 0}, effects = {{id = "destroy_random", n = 1}, {id = "add_cards", n = 3}}},
    {key = "c_talisman", fields = {select = 1}, effects = {{id = "seal", v = "Gold"}}},
    {key = "c_aura", fields = {select = 1}, effects = {{id = "edition", v = "polychrome"}}},
    {key = "c_wraith", fields = {select = 0}, effects = {{id = "rare_joker", v = 3}, {id = "money_zero"}}},
    {key = "c_ectoplasm", fields = {select = 0}, effects = {{id = "joker_edition", v = "negative"}, {id = "hand_size_minus"}}},
    {key = "c_grim", fields = {select = 0}, effects = {{id = "destroy_random", n = 1}, {id = "add_cards", n = 2}}, approx = true},
    {key = "c_incantation", fields = {select = 0}, effects = {{id = "destroy_random", n = 1}, {id = "add_cards", n = 4}}, approx = true},
    {key = "c_sigil", fields = {select = 0}, effects = {{id = "suit_random_all"}}},
    {key = "c_ouija", fields = {select = 0}, effects = {{id = "rank_random_all"}, {id = "hand_size_minus"}}},
    {key = "c_immolate", fields = {select = 0}, effects = {{id = "destroy_random", n = 5}, {id = "money", n = 20}}},
    {key = "c_ankh", fields = {select = 0}, effects = {{id = "copy_joker"}, {id = "destroy_others"}}},
    {key = "c_deja_vu", fields = {select = 1}, effects = {{id = "seal", v = "Red"}}},
    {key = "c_hex", fields = {select = 0}, effects = {{id = "joker_edition", v = "polychrome"}, {id = "destroy_others"}}},
    {key = "c_trance", fields = {select = 1}, effects = {{id = "seal", v = "Blue"}}},
    {key = "c_medium", fields = {select = 1}, effects = {{id = "seal", v = "Purple"}}},
    {key = "c_cryptid", fields = {select = 2}, effects = {{id = "copy"}}, approx = true},
    {key = "c_soul", fields = {select = 0}, effects = {{id = "rare_joker", v = 4}}},
    {key = "c_black_hole", fields = {select = 0}, effects = {{id = "level_all"}}},
  },
  voucher = {
    {key = "v_overstock_norm", effects = {{id = "shop_slots", n = 1}}},
    {key = "v_grabber", effects = {{id = "hands", n = 1}}},
    {key = "v_wasteful", effects = {{id = "discards", n = 1}}},
    {key = "v_crystal_ball", effects = {{id = "consumable_slots", n = 1}}},
    {key = "v_clearance_sale", effects = {{id = "discount", n = 25}}},
    {key = "v_reroll_surplus", effects = {{id = "reroll_cost", n = -2}}},
    {key = "v_seed_money", effects = {{id = "interest_cap", n = 25}}},
    {key = "v_paint_brush", effects = {{id = "hand_size", n = 1}}},
    {key = "v_overstock_plus", effects = {{id = "shop_slots", n = 1}}},
    {key = "v_liquidation", effects = {{id = "discount", n = 50}}},
    {key = "v_hone", effects = {{id = "edition_rate", n = 2}}},
    {key = "v_glow_up", effects = {{id = "edition_rate", n = 4}}},
    {key = "v_reroll_glut", effects = {{id = "reroll_cost", n = -2}}},
    {key = "v_omen_globe", approx = true},
    {key = "v_telescope", approx = true},
    {key = "v_observatory", approx = true},
    {key = "v_nacho_tong", effects = {{id = "hands", n = 1}}},
    {key = "v_recyclomancy", effects = {{id = "discards", n = 1}}},
    {key = "v_tarot_merchant", effects = {{id = "shop_rate", v = "Tarot", n = 8}}},
    {key = "v_tarot_tycoon", effects = {{id = "shop_rate", v = "Tarot", n = 32}}},
    {key = "v_planet_merchant", effects = {{id = "shop_rate", v = "Planet", n = 8}}},
    {key = "v_planet_tycoon", effects = {{id = "shop_rate", v = "Planet", n = 32}}},
    {key = "v_money_tree", effects = {{id = "interest_cap", n = 50}}},
    {key = "v_blank"},
    {key = "v_antimatter", effects = {{id = "joker_slots", n = 1}}},
    {key = "v_magic_trick", effects = {{id = "shop_rate", v = "Playing", n = 4}}},
    {key = "v_illusion", approx = true},
    {key = "v_hieroglyph", effects = {{id = "ante_now", n = -1}, {id = "hands", n = -1}}},
    {key = "v_petroglyph", effects = {{id = "ante_now", n = -1}, {id = "discards", n = -1}}},
    {key = "v_directors_cut", approx = true},
    {key = "v_retcon", approx = true},
    {key = "v_palette", effects = {{id = "hand_size", n = 1}}},
  },
  enhancement = {
    {key = "m_bonus", fields = {chips = 30}}, {key = "m_mult", fields = {chips = 0, mult = 4}}, {key = "m_glass", fields = {chips = 0, xmult = 2, breaks = 4}},
    {key = "m_steel", fields = {chips = 0, held_xmult = 1.5}}, {key = "m_gold", fields = {chips = 0, held_money = 3}}, {key = "m_stone", fields = {chips = 50, no_rank = true, always = true}}, {key = "m_wild", fields = {chips = 0, any_suit = true}},
    {key = "m_lucky", fields = {chips = 0, mult = 4, money = 1}, approx = true},
  },
  seal = {
    {key = "Red", effects = {{id = "scored_retrigger", n = 1}}}, {key = "Gold", effects = {{id = "scored_money", n = 3}}},
    {key = "Blue", effects = {{id = "held_planet"}}}, {key = "Purple", effects = {{id = "discard_tarot"}}},
  },
  edition = {
    {key = "foil", fields = {shader = "foil", chips = 50}}, {key = "holo", fields = {shader = "holo", chips = 0, mult = 10}},
    {key = "polychrome", fields = {shader = "polychrome", chips = 0, xmult = 1.5}}, {key = "negative", fields = {shader = "negative", chips = 0, slot = true}},
    {key = "tshine_scan", fields = {shader = "tshine_scan", chips = 30}}, {key = "tshine_gleam", fields = {shader = "tshine_gleam", chips = 30}},
    {key = "tshine_sweep", fields = {shader = "tshine_sweep", chips = 30}}, {key = "tshine_gold", fields = {shader = "tshine_gold", chips = 0, mult = 6}},
    {key = "tshine_glitter", fields = {shader = "tshine_glitter", chips = 0, mult = 8}}, {key = "tshine_void", fields = {shader = "tshine_void", chips = 0, xmult = 1.3}},
    {key = "tshine_prism", fields = {shader = "tshine_prism", chips = 0, xmult = 1.5}}, {key = "tshine_molten", fields = {shader = "tshine_molten", chips = 0, mult = 8}},
    {key = "tshine_spotlight", fields = {shader = "tshine_spotlight", chips = 40}}, {key = "tshine_wave", fields = {shader = "tshine_wave", chips = 0, mult = 6}},
    {key = "tshine_noir", fields = {shader = "tshine_noir", chips = 0, xmult = 1.3}}, {key = "tshine_ghost", fields = {shader = "tshine_ghost", chips = 0, xmult = 1.5}},
  },
  tag = {
    {key = "tag_economy", effects = {{id = "money", n = 20}}}, {key = "tag_double", effects = {{id = "double"}}}, {key = "tag_rare", effects = {{id = "free_joker", v = 3}}},
    {key = "tag_charm", effects = {{id = "free_pack", v = "Arcana"}}}, {key = "tag_juggle", effects = {{id = "hand_size", n = 3}}}, {key = "tag_coupon", effects = {{id = "coupon"}}},
    {key = "tag_uncommon", effects = {{id = "free_joker", v = 2}}},
    {key = "tag_negative", effects = {{id = "free_joker", v = 1}}, approx = true},
    {key = "tag_foil", effects = {{id = "free_joker", v = 1}}, approx = true},
    {key = "tag_holo", effects = {{id = "free_joker", v = 1}}, approx = true},
    {key = "tag_polychrome", effects = {{id = "free_joker", v = 1}}, approx = true},
    {key = "tag_investment", effects = {{id = "money", n = 25}}, approx = true},
    {key = "tag_voucher", effects = {{id = "give_voucher", v = "v_overstock_norm"}}, approx = true},
    {key = "tag_boss", approx = true},
    {key = "tag_standard", effects = {{id = "free_pack", v = "Standard"}}},
    {key = "tag_meteor", effects = {{id = "free_pack", v = "Celestial"}}},
    {key = "tag_buffoon", effects = {{id = "free_pack", v = "Buffoon"}}},
    {key = "tag_handy", approx = true},
    {key = "tag_garbage", approx = true},
    {key = "tag_ethereal", effects = {{id = "free_pack", v = "Spectral"}}},
    {key = "tag_d_six", effects = {{id = "free_rerolls", n = 1}}, approx = true},
    {key = "tag_top_up", effects = {{id = "create", v = "Joker", n = 2}}, approx = true},
    {key = "tag_skip", effects = {{id = "money_per_skip", n = 5}}},
    {key = "tag_orbital", effects = {{id = "level_up", v = "Pair", n = 3}}, approx = true},
  },
  blind = {
    {key = "bl_small", fields = {shows_as = "small", size = 1, reward = 3}, effects = {}}, {key = "bl_big", fields = {shows_as = "big", size = 1.5, reward = 4}, effects = {}},
    {key = "bl_club", effects = {{id = "debuff_suit", v = "Clubs"}}}, {key = "bl_plant", effects = {{id = "debuff_face"}}}, {key = "bl_psychic", effects = {{id = "must_play", n = 5}}},
    {key = "bl_needle", fields = {size = 1}, effects = {{id = "one_hand"}}}, {key = "bl_manacle", effects = {{id = "hand_size_minus", n = 1}}}, {key = "bl_wall", fields = {size = 4}, effects = {}},
    {key = "bl_flint", effects = {{id = "halve_base"}}}, {key = "bl_tooth", effects = {{id = "money_per_card", n = 1}}},
    {key = "bl_ox", approx = true},
    {key = "bl_hook", approx = true},
    {key = "bl_mouth", effects = {{id = "only_hand", v = "Pair"}}, approx = true},
    {key = "bl_fish", effects = {{id = "face_down_first"}}, approx = true},
    {key = "bl_house", effects = {{id = "face_down_first"}}},
    {key = "bl_mark", effects = {{id = "face_down_first"}}, approx = true},
    {key = "bl_wheel", effects = {{id = "face_down_first"}}, approx = true},
    {key = "bl_arm", approx = true},
    {key = "bl_goad", effects = {{id = "debuff_suit", v = "Spades"}}},
    {key = "bl_head", effects = {{id = "debuff_suit", v = "Hearts"}}},
    {key = "bl_window", effects = {{id = "debuff_suit", v = "Diamonds"}}},
    {key = "bl_water", effects = {{id = "no_discards"}}},
    {key = "bl_eye", approx = true},
    {key = "bl_serpent", approx = true},
    {key = "bl_pillar", approx = true},
    {key = "bl_final_acorn", fields = {showdown = true, min_ante = 8}, approx = true},
    {key = "bl_final_leaf", fields = {showdown = true, min_ante = 8}, approx = true},
    {key = "bl_final_vessel", fields = {size = 6, showdown = true, min_ante = 8}, effects = {}},
    {key = "bl_final_heart", fields = {showdown = true, min_ante = 8}, approx = true},
    {key = "bl_final_bell", fields = {showdown = true, min_ante = 8}, approx = true},
  },
  stake = {
    {key = "stake_red", effects = {{id = "small_no_reward"}}}, {key = "stake_green", effects = {{id = "blind_scaling", n = 25}}}, {key = "stake_black", effects = {{id = "eternal"}}},
    {key = "stake_blue", effects = {{id = "discards_minus", n = 1}}}, {key = "stake_orange", effects = {{id = "perishable"}}}, {key = "stake_gold", effects = {{id = "rental"}}},
    {key = "stake_white"},
    {key = "stake_purple", effects = {{id = "blind_scaling", n = 25}}},
  },
  deck = {
    {key = "b_red", effects = {{id = "discards", n = 1}}}, {key = "b_blue", effects = {{id = "hands", n = 1}}}, {key = "b_yellow", effects = {{id = "dollars", n = 10}}},
    {key = "b_black", effects = {{id = "joker_slots", n = 1}, {id = "hands", n = -1}}}, {key = "b_abandoned", effects = {{id = "no_faces"}}}, {key = "b_magic", effects = {{id = "start_voucher", v = "v_crystal_ball"}, {id = "start_consumable", v = "Tarot", n = 2}}},
    {key = "b_green", effects = {{id = "money_per_hand", n = 2}, {id = "money_per_discard", n = 1}, {id = "interest_amount", n = -1}}},
    {key = "b_nebula", effects = {{id = "start_voucher", v = "v_telescope"}, {id = "consumable_slots", n = -1}}},
    {key = "b_ghost", effects = {{id = "shop_rate", v = "Spectral", n = 2}, {id = "start_consumable", v = "Spectral", n = 1}}, approx = true},
    {key = "b_checkered", effects = {{id = "remove_suit", v = "Clubs"}, {id = "remove_suit", v = "Diamonds"},
      {id = "add_suit", v = "Spades", n = 1}, {id = "add_suit", v = "Hearts", n = 1}}},
    {key = "b_zodiac", effects = {{id = "start_voucher", v = "v_tarot_merchant"}, {id = "start_voucher", v = "v_planet_merchant"}, {id = "start_voucher", v = "v_overstock_norm"}}},
    {key = "b_painted", effects = {{id = "hand_size", n = 2}, {id = "joker_slots", n = -1}}},
    {key = "b_anaglyph", effects = {{id = "tag", v = "tag_double", n = 1, when = "round_end"}}, approx = true},
    {key = "b_plasma", effects = {{id = "balance"}, {id = "blind_size", n = 2}}},
    {key = "b_erratic", effects = {{id = "erratic"}}},
  },
  booster = {
    {key = "p_arcana_normal_1", fields = {pack = "Arcana", size = "Normal"}}, {key = "p_celestial_jumbo_1", fields = {pack = "Celestial", size = "Jumbo", cost = 6}},
    {key = "p_spectral_normal_1", fields = {pack = "Spectral", size = "Normal"}}, {key = "p_buffoon_mega_1", fields = {pack = "Buffoon", size = "Mega", cost = 8}},
    {key = "p_arcana_jumbo_1", fields = {pack = "Arcana", size = "Jumbo", cost = 6, shown = 5, choose = 1}},
    {key = "p_arcana_mega_1", fields = {pack = "Arcana", size = "Mega", cost = 8, shown = 5, choose = 2}},
    {key = "p_celestial_normal_1", fields = {pack = "Celestial", size = "Normal", cost = 4, shown = 3, choose = 1}},
    {key = "p_celestial_mega_1", fields = {pack = "Celestial", size = "Mega", cost = 8, shown = 5, choose = 2}},
    {key = "p_spectral_jumbo_1", fields = {pack = "Spectral", size = "Jumbo", cost = 6, shown = 4, choose = 1}},
    {key = "p_spectral_mega_1", fields = {pack = "Spectral", size = "Mega", cost = 8, shown = 4, choose = 2}},
    {key = "p_standard_normal_1", fields = {pack = "Standard", size = "Normal", cost = 4, shown = 3, choose = 1}},
    {key = "p_standard_jumbo_1", fields = {pack = "Standard", size = "Jumbo", cost = 6, shown = 5, choose = 1}},
    {key = "p_standard_mega_1", fields = {pack = "Standard", size = "Mega", cost = 8, shown = 5, choose = 2}},
    {key = "p_buffoon_normal_1", fields = {pack = "Buffoon", size = "Normal", cost = 4, shown = 2, choose = 1}},
    {key = "p_buffoon_jumbo_1", fields = {pack = "Buffoon", size = "Jumbo", cost = 6, shown = 4, choose = 1}},
  },
  collab = {{key = "H_K", fields = {suit = "Hearts"}}, {key = "S_K", fields = {suit = "Spades"}}, {key = "D_K", fields = {suit = "Diamonds"}}, {key = "C_K", fields = {suit = "Clubs"}}},
}

function D.templates(kind)
  if kind == "joker" then return D.JOKER_TEMPLATES end
  if kind == "challenge" then return require("functions/forge/forge_challenges").templates() end
  return D.GAME_TEMPLATES[kind] or {}
end

local function game_name(set, key)
  local d = G and G.localization and G.localization.descriptions
  local t = d and d[set] and d[set][key]
  if t and t.name then return type(t.name) == "table" and table.concat(t.name, " ") or t.name end
  return nil
end

function D.template_name(kind, t)
  local k = Cat.kind(kind)
  if kind == "seal" then return Cat.value_label("seal", t.key) end
  if kind == "edition" then return Cat.value_label("shader", t.key) end
  if kind == "collab" then return Cat.value_label("suit", t.fields.suit) end
  if kind == "challenge" then return require("functions/forge/forge_challenges").template_name(t) end
  if kind == "booster" then return game_name("Other", (t.key:gsub("_%d+$", ""))) or t.key end
  local set = ({enhancement = "Enhanced", deck = "Back", blind = "Blind", stake = "Stake", tag = "Tag"})[kind] or k.set
  local c = G and G.P_CENTERS and G.P_CENTERS[t.key]
  return game_name(set, t.key) or (c and c.set and game_name(c.set, t.key)) or t.key
end

function D.sample_art(kind, key)
  local k = Cat.kind(kind)
  key = key or k.sample
  if k.shape == "card" or kind == "enhancement" then
    local c = G.P_CENTERS and G.P_CENTERS[key]
    if c then return {atlas = c.atlas or (k.set == "Joker" and "Joker" or k.set), x = c.pos.x, y = c.pos.y} end
  end
  if kind == "deck" then
    local c = G.P_CENTERS and G.P_CENTERS[key]
    if c then return {atlas = c.atlas or "centers", x = c.pos.x, y = c.pos.y} end
  end
  if kind == "tag" then
    local t = G.P_TAGS and G.P_TAGS[key]
    if t then return {atlas = t.atlas or "tags", x = t.pos.x, y = t.pos.y} end
  end
  if kind == "blind" then
    local b = G.P_BLINDS and G.P_BLINDS[key]
    if b then return {atlas = b.atlas or "blind_chips", x = b.pos.x, y = b.pos.y, anim = true} end
  end
  if kind == "stake" then
    local s = G.P_STAKES and G.P_STAKES[key]
    if s then return {atlas = s.atlas or "chips", x = s.pos.x, y = s.pos.y} end
  end
  return nil
end

D.BLANK_KINDS = {joker = true, tarot = true, planet = true, spectral = true, voucher = true, booster = true, deck = true, enhancement = true, seal = true, tag = true, blind = true, stake = true}
D.BLANK_DIR = "resources/textures/1x/forge_blank/"

function D.blank_art(kind)
  if D.BLANK_KINDS[kind] then return D.BLANK_DIR .. kind .. ".png" end
  return nil
end

D.UNSET_FIELDS = {planet = {hand = true}, blind = {size = true, reward = true}, booster = {pack = true}, collab = {suit = true}, suit = {colour = true}, hand = {pattern = true}, ctype = {colour = true}, rarity = {colour = true}, sticker = {look = true}, fusion = {out = true}}

function D.unset(d, f)
  local u = type(d) == "table" and d.unset == true and D.UNSET_FIELDS[d.kind]
  if not u then return false end
  if f == nil then return true end
  return u[f] == true
end

function D.choose(d, f)
  if D.unset(d, f) then d.unset = nil end
end

D.BLANK_FIELDS = {
  enhancement = {chips = 0, mult = 0, xmult = 1, money = 0, held_xmult = 1, held_money = 0, breaks = 0},
  edition = {shader = "none", chips = 0, mult = 0, xmult = 1},
  planet = {chips = 0, mult = 0},
}

function D.blank(kind)
  local k = Cat.kind(kind)
  local d = D.new(k.id, {name = "", mode = "advanced", rules = {}, vars = {}, effects = {}})
  d.name = ""
  if k.rules then
    d.rules, d.vars = {}, {}
  else
    d.effects = {}
    for f, v in pairs(D.BLANK_FIELDS[k.id] or {}) do if d.fields[f] ~= nil then d.fields[f] = v end end
  end
  if D.UNSET_FIELDS[k.id] then d.unset = true end
  return d
end

function D.from_template(kind, t)
  local base = {name = D.template_name(kind, t), art = D.sample_art(kind, t.key), from = t.key}
  if kind == "joker" then
    local c = G.P_CENTERS[t.key] or {}
    base.rarity, base.cost, base.rules = c.rarity or 1, c.cost or 4, copy(t.rules)
    if t.vars then
      base.vars = copy(t.vars)
      for _, v in ipairs(base.vars) do v.name = mod_loc(v.name) end
    end
    return D.new("joker", base)
  end
  local fields = Cat.default_fields(kind)
  for k2, v in pairs(t.fields or {}) do fields[k2] = v end
  local c = G.P_CENTERS and G.P_CENTERS[t.key]
  if c and c.cost and fields.cost then fields.cost = c.cost end
  if kind == "booster" and c and c.config and c.config.extra then fields.shown, fields.choose = c.config.extra, c.config.choose or fields.choose end
  base.fields = fields
  base.effects = copy(t.effects or {})
  local d = D.new(kind, base)
  d.effects = Cat.clean_effects(kind, base.effects)
  return d
end

function D.needs_cards(d)
  for _, e in ipairs(d.effects or {}) do if D.CARD_EFFECTS[e.id] then return true end end
  return false
end

local function plain_lines(d, l)
  local k = Cat.kind(d.kind)
  local out = {}
  local function add(str) for _, line in ipairs(T.wrap(str)) do out[#out + 1] = line end end
  local f = d.fields or {}
  local kind = D.unset(d) and "" or d.kind
  if kind == "planet" then
    add(string.format(mod_loc("Levels up {C:attention}%s{}"), Cat.value_label("hand", f.hand)) .. (f.levels and f.levels > 1 and (" x" .. f.levels) or ""))
    if d.mode == "advanced" and ((f.mult or 0) > 0 or (f.chips or 0) > 0) then add(string.format(mod_loc("{C:mult}+%s{} Mult and {C:chips}+%s{} Chips per level"), Cat.fmt({}, f.mult), Cat.fmt({}, f.chips))) end
  elseif kind == "enhancement" then
    if (f.chips or 0) > 0 then add(string.format(mod_loc("{C:chips}+%s{} Chips"), Cat.fmt({}, f.chips))) end
    if (f.mult or 0) > 0 then add(string.format(mod_loc("{C:mult}+%s{} Mult"), Cat.fmt({}, f.mult))) end
    if (f.xmult or 1) > 1 then add(string.format(mod_loc("{X:mult,C:white}X%s{} Mult"), Cat.fmt({}, f.xmult))) end
    if (f.money or 0) > 0 then add(string.format(mod_loc("Gives {C:money}$%d{} when scored"), f.money)) end
    if (f.held_xmult or 1) > 1 then add(string.format(mod_loc("{X:mult,C:white}X%s{} Mult while this card stays in hand"), Cat.fmt({}, f.held_xmult))) end
    if (f.held_money or 0) > 0 then add(string.format(mod_loc("Gives {C:money}$%d{} if held at round end"), f.held_money)) end
    local rt = math.floor(tonumber(f.retrigger) or 0)
    if rt > 0 then add(string.format(mod_loc(rt == 1 and "Retriggers this card {C:attention}%d{} time" or "Retriggers this card {C:attention}%d{} times"), rt)) end
    if (f.breaks or 0) > 0 then
      local P3 = require("functions/forge/forge_power3")
      add((string.format(mod_loc("{C:green}1 in %d{} chance to break"), f.breaks):gsub("{C:green}1", "{C:green}" .. P3.prob(), 1)))
    end
    if f.any_suit then add(mod_loc("Can be used as any suit")) end
    if f.no_rank then add(mod_loc("No rank or suit")) end
    if f.always then add(mod_loc("Always scores")) end
  elseif kind == "edition" then
    if (f.chips or 0) > 0 then add(string.format(mod_loc("{C:chips}+%s{} Chips"), Cat.fmt({}, f.chips))) end
    if (f.mult or 0) > 0 then add(string.format(mod_loc("{C:mult}+%s{} Mult"), Cat.fmt({}, f.mult))) end
    if (f.xmult or 1) > 1 then add(string.format(mod_loc("{X:mult,C:white}X%s{} Mult"), Cat.fmt({}, f.xmult))) end
    if f.slot then add(mod_loc("{C:dark_edition}+1{} Joker slot")) end
    if (tonumber(f.sell) or 0) > 0 then add(string.format(mod_loc("{C:money}+$%d{} sell value"), tonumber(f.sell))) end
  elseif kind == "booster" then
    local size = f.size or "Normal"
    local shown = d.mode == "advanced" and f.shown or ({Normal = 3, Jumbo = 5, Mega = 5})[size]
    local choose = d.mode == "advanced" and f.choose or ({Normal = 1, Jumbo = 1, Mega = 2})[size]
    if Cat.chosen_pack(d) then
      add(string.format(mod_loc("Choose {C:attention}%d{} of up to {C:attention}%d{} of these cards:"), choose or 1, shown or 3))
      local names = {}
      for _, v in ipairs(Cat.pack_cards(d)) do
        if not (G and G.P_CENTERS) or R.card_usable(v) then names[#names + 1] = "{C:attention}" .. Cat.value_label("card", v) .. "{}" end
      end
      local cut = #names > 9 and 9 or #names
      for i = 1, cut, 3 do add(table.concat(names, ", ", i, math.min(cut, i + 2))) end
      if #names > cut then add((string.format(mod_loc(" and %d more"), #names - cut):gsub("^ ", ""))) end
    else
      if R.own_id("ctype", f.pack) then
        add(string.format(mod_loc("Choose {C:attention}%d{} of up to {C:attention}%d{} {C:attention}%s{}"), choose or 1, shown or 3, Cat.value_label("ctype", f.pack)))
      else
        add(string.format(mod_loc("Choose {C:attention}%d{} of up to {C:attention}%d{} %s cards"), choose or 1, shown or 3, Cat.value_label("plain", f.pack)))
      end
      if d.mode == "advanced" and f.own_only then add(mod_loc("Only {C:attention}your own{} creations")) end
    end
    local pe = require("functions/forge/forge_editions").pack_edition(d)
    if pe then add(string.format(mod_loc("Every card is {C:dark_edition}%s{}"), require("functions/forge/forge_rules").ed_name(pe))) end
  elseif kind == "collab" then
    add(string.format(mod_loc("Face cards of {C:attention}%s{}"), Cat.value_label("suit", f.suit)))
  elseif kind == "fusion" then
    local Fu = require("functions/forge/forge_fusion")
    local ff = Fu.fields({fields = f})
    if ff.c then add(string.format(mod_loc("{C:attention}%s{} + {C:attention}%s{}"), R.card_label(f.a), R.card_label(f.b)) .. " + {C:attention}" .. R.card_label(ff.c) .. "{}")
    else add(string.format(mod_loc("{C:attention}%s{} + {C:attention}%s{}"), R.card_label(f.a), R.card_label(f.b))) end
    add(string.format(mod_loc("Fuse into {C:attention}%s{} for {C:money}%s{}"), R.card_label(f.out), Cat.fmt({fmt = "$"}, tonumber(f.cost) or 5)))
    add(mod_loc("The best edition stays"))
    if ff.auto then add(mod_loc("Fuses by itself when they meet")) end
    if ff.between then add(mod_loc("Only between rounds")) end
    if ff.sacrifice then add(mod_loc("Also destroys a random Joker")) end
    if ff.keep then add(mod_loc("Keeps stickers and sell value")) end
  elseif kind == "sticker" then
    local SX = require("functions/forge/forge_stickerrules")
    local jokers = SX.fields({fields = f}).on == "Jokers"
    add(mod_loc(jokers and "A sticker for your Jokers" or "A sticker for your cards"))
    local w = tonumber(f.chance) or 10
    local on = jokers and "On {C:attention}%s{} of shop Jokers" or "On {C:attention}%s{} of shop and pack cards"
    if w > 0 then add(string.format(mod_loc(on), Cat.fmt({fmt = "%"}, w))) else add(mod_loc("Never in the shop, only put by effects")) end
    SX.doc_lines(f, add)
  elseif kind == "rarity" then
    add(mod_loc("A new rarity for your Jokers"))
    local w = tonumber(f.chance) or 2
    if w > 0 then add(string.format(mod_loc("Shop odds {C:attention}%s{}"), Cat.fmt({fmt = "%"}, w))) else add(mod_loc("Never in the shop, only made by effects")) end
    require("functions/forge/forge_rarityrules").doc_lines(f, add)
  elseif kind == "ctype" then
    add(mod_loc("Its own family of cards"))
    local shop = tonumber(f.shop) or 2
    if shop > 0 then add(string.format(mod_loc("Shows in the shop with weight {C:attention}%s{}"), Cat.fmt({}, shop))) else add(mod_loc("Only in its own packs")) end
    require("functions/forge/forge_typerules").doc_lines(f, add)
  elseif kind == "hand" then
    local Hands = require("functions/forge/forge_hands")
    local hf = Hands.fields(d)
    for _, l in ipairs(Hands.doc_lines(hf)) do add(l) end
    add(string.format(mod_loc("{C:chips}%s{} Chips, {C:mult}%s{} Mult, ranks above {C:attention}%s{}"), Cat.fmt({}, hf.chips), Cat.fmt({}, hf.mult), Cat.value_label("hand", hf.beats)))
  elseif kind == "suit" then
    require("functions/forge/forge_suitrules").doc_lines(f, add)
  elseif kind == "blind" then
    add(string.format(mod_loc("Size {C:red}X%s{}, reward {C:money}$%d{}"), Cat.fmt({}, f.size), f.reward or 5))  elseif kind == "voucher" then
    if f.requires and f.requires ~= "none" then add(string.format(mod_loc("Needs {C:attention}%s{} first"), Cat.value_label("voucher", f.requires))) end
    if (tonumber(f.max_buys) or 1) > 1 then add(string.format(mod_loc("Can be bought {C:attention}%d{} times"), tonumber(f.max_buys))) end
  end
  local gate = d.kind ~= "voucher" and require("functions/forge/forge_gates").doc(f.requires)
  if gate then add(gate)
  elseif d.kind ~= "voucher" and f.requires and f.requires ~= "none" then add(string.format(mod_loc("Needs {C:attention}%s{} first"), Cat.value_label("voucher", f.requires))) end
  if (d.kind == "tarot" or d.kind == "spectral") and D.needs_cards(d) and (f.select or 0) > 0 then
    add(string.format(mod_loc("Pick up to {C:attention}%d{} cards"), f.select))
  end
  if d.kind ~= "booster" then
    for _, e in ipairs(d.effects or {}) do add(Cat.effect_line(d.kind, e)) end
  end
  return out
end

function D.lines(d, l)
  l = l or lang()
  if type(d.text) == "table" and type(d.text[l]) == "table" and #d.text[l] > 0 then return d.text[l] end
  local out
  if d.kind == "joker" then out = T.lines({rules = R.clean_rules(d.rules), vars = R.clean_vars(d.vars)}, l) else
    out = plain_lines(d, l)
    if R.host_of(d.kind) ~= "joker" and type(d.rules) == "table" and #d.rules > 0 then
      for _, line in ipairs(T.lines({rules = R.clean_rules(d.rules, d.kind), vars = R.clean_vars(d.vars), kind = d.kind}, l)) do out[#out + 1] = line end
    end
  end
  local al = require("functions/forge/forge_always").line(d)
  if al then out[#out + 1] = al end
  return out
end

function D.problems(d)
  local out = {}
  if not d then return out end
  if tostring(d.name or ""):gsub("%s", "") == "" then out[#out + 1] = mod_loc("Give it a name") end
  if d.kind == "joker" then
    local rules = d.rules or {}
    local nv = #(d.vars or {})
    for _, v in ipairs(d.vars or {}) do
      if R.clean_name(v.name) == "" then out[#out + 1] = mod_loc("Give every variable a name") break end
    end
    for i, r in ipairs(rules) do
      if #(r.give or {}) == 0 then out[#out + 1] = string.format(mod_loc("Rule %d does nothing yet: add an effect"), i) end
      local missing = false
      for _, list in ipairs({r.give or {}, r.alt or {}, r.only or {}}) do
        for _, x in ipairs(list) do
          if (R.VAR_GIVE[x.id] or x.id == "var") and (x.var or 1) > nv then missing = true end
        end
      end
      if missing then out[#out + 1] = string.format(mod_loc("Rule %d uses a variable that is gone"), i) end
    end
  else
    if d.kind == "booster" and D.unset(d, "pack") then out[#out + 1] = mod_loc("Pick what it contains") end
    if Cat.chosen_pack(d) and #Cat.pack_cards(d) == 0 then out[#out + 1] = mod_loc("Add at least one card to the pack") end
    if (d.kind == "tarot" or d.kind == "spectral") and D.needs_cards(d) and (d.fields.select or 0) == 0 then out[#out + 1] = mod_loc("Pick at least 1 card for this effect") end
    for _, e in ipairs(d.effects or {}) do
      if e.id == "copy" and (d.fields.select or 0) ~= 2 then out[#out + 1] = mod_loc("Copy needs exactly 2 cards to pick") end
    end
  end
  if d.kind ~= "joker" and R.host_of(d.kind) ~= "joker" then
    local nv = #(d.vars or {})
    for _, v in ipairs(d.vars or {}) do
      if R.clean_name(v.name) == "" then out[#out + 1] = mod_loc("Give every variable a name") break end
    end
    for i, r in ipairs(d.rules or {}) do
      local missing = false
      for _, list in ipairs({r.give or {}, r.alt or {}, r.only or {}}) do
        for _, x in ipairs(list) do
          if (R.VAR_GIVE[x.id] or x.id == "var") and (x.var or 1) > nv then missing = true end
        end
      end
      if missing then out[#out + 1] = string.format(mod_loc("Rule %d uses a variable that is gone"), i) end
    end
  end
  if type(d.text) == "table" then
    for _, lines in pairs(d.text) do if type(lines) == "table" and #lines > 6 then out[#out + 1] = mod_loc("Card text is longer than 6 lines") break end end
  end
  return out
end

local GIVE_POWER = {chips = 1 / 30, mult = 1 / 4, xmult = 4, money = 1 / 3, retrigger = 2, gain_chips = 0.4, gain_mult = 1.2, gain_xmult = 12, create = 1.2, level_up = 1.5, change = 1.2, hand = 0.8, discard = 0.5, destroy_self = -0.5, var_add = 0.15, var_set = 0, var_chips = 0.17, var_mult = 1.2, destroy_card = 0.8, add_card = 0.6, sell_value = 0.3, perma_chips = 0.5, copy_card = 0.8, tag = 1.0, disable_boss = 2, destroy_joker = -0.3}
local ONLY_POWER = {suit = 0.3, rank = 0.35, enhancement = 0.2, seal = 0.15, edition = 0.1, hand = 0.6, first_hand = 0.4, last_hand = 0.4, boss = 0.3, money = 0.7, cards_played = 0.6, hands_left = 0.6, discards_left = 0.5, ante = 0.8, jokers = 0.7, var = 0.5, blind = 0.4, deck_cards = 0.6, held_cards = 0.6, consumables = 0.6, hand_level = 0.6, round = 0.7}
local PER_CARD = {card_scored = 3, card_held = 2, discard = 2}

function D.power(d)
  if d.kind ~= "joker" then return nil end
  local total = 0
  local vars = R.clean_vars(d.vars)
  local function num(e, cond)
    if not R.num_ref(e) then return e.n end
    local v = vars[e.nv]
    return R.live_num(e, v and not v.type and v.start, cond)
  end
  for _, r in ipairs(R.clean_rules(d.rules)) do
    local p = 0
    for _, g in ipairs(r.give) do
      local w = GIVE_POWER[g.id] or 0.5
      local n = num(g)
      if g.id == "xmult" or g.id == "gain_xmult" then p = p + w * ((n or 1) - (g.id == "xmult" and 1 or 0)) else p = p + w * math.abs(n or 1) end
    end
    p = p * (PER_CARD[r.when] or 1)
    for _, o in ipairs(r.only) do
      if o.id == "chance" then p = p / (num(o, true) or 4) else p = p * (ONLY_POWER[o.id] or 0.6) end
    end
    total = total + p
  end
  return total
end

D.RARITY_POWER = {1, 1.8, 3, 5}
D.RARITY_COST = {{4, 6}, {5, 8}, {7, 10}, {20, 20}}

function D.balance(d)
  local p = D.power(d)
  if not p then return nil end
  local want = D.RARITY_POWER[d.rarity or 1] or 1
  if p < want * 0.55 then return "weak" end
  if p > want * 1.7 then return "strong" end
  return "fair"
end

function D.balance_label(b)
  if b == "weak" then return mod_loc("A bit weak") end
  if b == "strong" then return mod_loc("Very strong") end
  return mod_loc("Nicely balanced")
end

function D.cost_hint(d)
  local r = D.RARITY_COST[d.rarity or 1]
  if not r then return "" end
  if r[1] == r[2] then return string.format(mod_loc("Most cost $%d"), r[1]) end
  return string.format(mod_loc("Most cost $%d to $%d"), r[1], r[2])
end

local function register()
  if not mod_loc_register then return end
  mod_loc_register{
    fr = {
      ["New"] = "Nouveau", ["Levels up {C:attention}%s{}"] = "Monte {C:attention}%s{} d'un niveau", ["{C:mult}+%s{} Mult and {C:chips}+%s{} Chips per level"] = "{C:mult}+%s{} Multi et {C:chips}+%s{} Jetons par niveau",
      ["{C:chips}+%s{} Chips"] = "{C:chips}+%s{} Jetons", ["{C:mult}+%s{} Mult"] = "{C:mult}+%s{} Multi", ["{X:mult,C:white}X%s{} Mult"] = "{X:mult,C:white}X%s{} Multi",
      ["{X:mult,C:white}X%s{} Mult while this card stays in hand"] = "{X:mult,C:white}X%s{} Multi tant que la carte reste en main", ["{C:green}1 in %d{} chance to break"] = "{C:green}1 chance sur %d{} de se briser",
      ["{C:dark_edition}+1{} Joker slot"] = "{C:dark_edition}+1{} emplacement de Joker", ["Choose {C:attention}%d{} of up to {C:attention}%d{} %s cards"] = "Choisissez {C:attention}%d{} carte parmi {C:attention}%d{} (%s)", ["Only {C:attention}your own{} creations"] = "Seulement {C:attention}vos{} créations", ["Every card is {C:dark_edition}%s{}"] = "Chaque carte est {C:dark_edition}%s{}",
      ["Face cards of {C:attention}%s{}"] = "Figures de {C:attention}%s{}", ["Size {C:red}X%s{}, reward {C:money}$%d{}"] = "Taille {C:red}X%s{}, récompense {C:money}%d ${}", ["Pick up to {C:attention}%d{} cards"] = "Choisissez jusqu'à {C:attention}%d{} cartes",
      ["Give every variable a name"] = "Donnez un nom à chaque variable", ["Rule %d uses a variable that is gone"] = "La règle %d utilise une variable supprimée",
      ["Pick what it contains"] = "Choisissez ce qu'il contient", ["Not chosen yet"] = "Pas encore choisi",
      ["Give it a name"] = "Donnez-lui un nom", ["Add a rule"] = "Ajoutez une règle", ["Rule %d does nothing yet: add an effect"] = "La règle %d ne fait rien : ajoutez un effet", ["Add an effect"] = "Ajoutez un effet",
      ["Pick at least 1 card for this effect"] = "Choisissez au moins 1 carte pour cet effet", ["Copy needs exactly 2 cards to pick"] = "Copier demande exactement 2 cartes", ["Card text is longer than 6 lines"] = "Le texte dépasse 6 lignes",
      ["A bit weak"] = "Un peu faible", ["Very strong"] = "Très fort", ["Nicely balanced"] = "Bien équilibré", ["Most cost $%d"] = "La plupart coûtent %d $", ["Most cost $%d to $%d"] = "La plupart coûtent de %d à %d $",
    },
    es = {
      ["New"] = "Nuevo", ["Levels up {C:attention}%s{}"] = "Sube {C:attention}%s{} un nivel", ["{C:mult}+%s{} Mult and {C:chips}+%s{} Chips per level"] = "{C:mult}+%s{} multi y {C:chips}+%s{} Fichas por nivel",
      ["{C:chips}+%s{} Chips"] = "{C:chips}+%s{} Fichas", ["{C:mult}+%s{} Mult"] = "{C:mult}+%s{} multi", ["{X:mult,C:white}X%s{} Mult"] = "{X:mult,C:white}X%s{} multi",
      ["{X:mult,C:white}X%s{} Mult while this card stays in hand"] = "{X:mult,C:white}X%s{} multi mientras siga en la mano", ["{C:green}1 in %d{} chance to break"] = "{C:green}1 de %d{} probabilidades de romperse",
      ["{C:dark_edition}+1{} Joker slot"] = "{C:dark_edition}+1{} espacio de comodín", ["Choose {C:attention}%d{} of up to {C:attention}%d{} %s cards"] = "Elige {C:attention}%d{} de hasta {C:attention}%d{} cartas (%s)", ["Only {C:attention}your own{} creations"] = "Solo {C:attention}tus{} creaciones", ["Every card is {C:dark_edition}%s{}"] = "Cada carta es {C:dark_edition}%s{}",
      ["Face cards of {C:attention}%s{}"] = "Figuras de {C:attention}%s{}", ["Size {C:red}X%s{}, reward {C:money}$%d{}"] = "Tamaño {C:red}X%s{}, premio {C:money}$%d{}", ["Pick up to {C:attention}%d{} cards"] = "Elige hasta {C:attention}%d{} cartas",
      ["Give every variable a name"] = "Ponle un nombre a cada variable", ["Rule %d uses a variable that is gone"] = "La regla %d usa una variable borrada",
      ["Pick what it contains"] = "Elige qué contiene", ["Not chosen yet"] = "Sin elegir",
      ["Give it a name"] = "Ponle un nombre", ["Add a rule"] = "Añade una regla", ["Rule %d does nothing yet: add an effect"] = "La regla %d aún no hace nada: añade un efecto", ["Add an effect"] = "Añade un efecto",
      ["Pick at least 1 card for this effect"] = "Elige al menos 1 carta para este efecto", ["Copy needs exactly 2 cards to pick"] = "Copiar necesita exactamente 2 cartas", ["Card text is longer than 6 lines"] = "El texto pasa de 6 líneas",
      ["A bit weak"] = "Algo flojo", ["Very strong"] = "Muy fuerte", ["Nicely balanced"] = "Bien equilibrado", ["Most cost $%d"] = "La mayoría cuestan $%d", ["Most cost $%d to $%d"] = "La mayoría cuestan de $%d a $%d",
    },
  }
end

register()

return D
