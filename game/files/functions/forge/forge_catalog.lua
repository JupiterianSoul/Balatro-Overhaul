local Cat = {}

Cat.HANDS = {"High Card", "Pair", "Two Pair", "Three of a Kind", "Straight", "Flush", "Full House", "Four of a Kind", "Straight Flush", "Five of a Kind", "Flush House", "Flush Five"}
Cat.SUITS = {"Hearts", "Diamonds", "Spades", "Clubs"}
Cat.ENHANCEMENTS = {"m_bonus", "m_mult", "m_wild", "m_glass", "m_steel", "m_stone", "m_gold", "m_lucky"}
Cat.SEALS = {"Red", "Blue", "Gold", "Purple"}
Cat.EDITIONS = {"foil", "holo", "polychrome"}
Cat.SHADERS = {"foil", "holo", "polychrome", "negative"}
Cat.SETS = {"Tarot", "Planet", "Spectral", "Joker"}
Cat.RARITY = {1, 2, 3, 4}
Cat.PACKS = {"Arcana", "Celestial", "Spectral", "Standard", "Buffoon", "Forge"}
Cat.PACK_SIZES = {"Normal", "Jumbo", "Mega"}
Cat.TAG_WHEN = {"now", "shop", "round"}
Cat.BLIND_COLOURS = {"RED", "BLUE", "GREEN", "PURPLE", "ORANGE", "GOLD", "BLACK"}
Cat.STAKES = {"stake_white", "stake_red", "stake_green", "stake_black", "stake_blue", "stake_purple", "stake_orange", "stake_gold"}
Cat.VOUCHERS = {"v_overstock_norm", "v_clearance_sale", "v_hone", "v_reroll_surplus", "v_crystal_ball", "v_telescope", "v_grabber", "v_wasteful", "v_tarot_merchant", "v_planet_merchant", "v_seed_money", "v_blank", "v_magic_trick", "v_hieroglyph", "v_directors_cut", "v_paint_brush"}

local R = require("functions/forge/forge_rules")

local function n(lo, hi, def, step, fmt) return {lo = lo, hi = hi, def = def, step = step or 1, fmt = fmt} end

Cat.KINDS = {
  {id = "joker", label = "Joker", plural = "Jokers", set = "Joker", sample = "j_joker", shape = "card", rules = true,
    fields = {{id = "rarity", label = "Rarity", type = "choice", options = Cat.RARITY, def = 1}, {id = "cost", label = "Cost", type = "num", num = n(1, 20, 4, 1, "$")}},
    adv_fields = {{id = "blueprint", label = "Blueprint copies it", type = "toggle", def = true}, {id = "eternal", label = "Can be Eternal", type = "toggle", def = true}, {id = "perishable", label = "Can be Perishable", type = "toggle", def = true}}},
  {id = "tarot", label = "Tarot", plural = "Tarots", set = "Tarot", sample = "c_fool", shape = "card", effects = "use", simple_max = 1, max = 3,
    fields = {{id = "cost", label = "Cost", type = "num", num = n(1, 10, 3, 1, "$")}, {id = "select", label = "Cards to pick", type = "num", num = n(0, 5, 2)}},
    adv_fields = {{id = "requires", label = "Appears in shops", type = "choice", options = Cat.VOUCHERS, def = "none", none = true, dynamic = "voucher", new = true}}},
  {id = "planet", label = "Planet", plural = "Planets", set = "Planet", sample = "c_mercury", shape = "card", effects = "planet", simple_max = 0, max = 2,
    fields = {{id = "hand", label = "Poker hand", type = "choice", options = Cat.HANDS, def = "Pair", all = true}, {id = "levels", label = "Levels", type = "num", num = n(1, 5, 1)}},
    adv_fields = {{id = "chips", label = "Chips per level", type = "num", num = n(0, 100, 15, 5)}, {id = "mult", label = "Mult per level", type = "num", num = n(0, 10, 1)}, {id = "cost", label = "Cost", type = "num", num = n(1, 10, 3, 1, "$")}, {id = "requires", label = "Appears in shops", type = "choice", options = Cat.VOUCHERS, def = "none", none = true, dynamic = "voucher", new = true}}},
  {id = "spectral", label = "Spectral", plural = "Spectrals", set = "Spectral", sample = "c_familiar", shape = "card", effects = "spectral", simple_max = 2, max = 4,
    fields = {{id = "cost", label = "Cost", type = "num", num = n(1, 10, 4, 1, "$")}, {id = "select", label = "Cards to pick", type = "num", num = n(0, 5, 1)}},
    adv_fields = {{id = "requires", label = "Appears in shops", type = "choice", options = Cat.VOUCHERS, def = "none", none = true, dynamic = "voucher", new = true}}},
  {id = "voucher", label = "Voucher", plural = "Vouchers", set = "Voucher", sample = "v_overstock_norm", shape = "card", effects = "voucher", simple_max = 1, max = 3, whens = "run",
    fields = {{id = "cost", label = "Cost", type = "num", num = n(5, 20, 10, 1, "$")}, {id = "requires", label = "Appears in shops", type = "choice", options = Cat.VOUCHERS, def = "none", none = true, dynamic = "voucher"}},
    adv_fields = {{id = "max_buys", label = "Times it can be bought", type = "num", num = n(1, 1, 1), new = true}, {id = "min_ante", label = "Shows from ante", type = "num", num = n(1, 1, 1), new = true}, {id = "weight", label = "How often it shows", type = "num", num = n(0, 1, 1), new = true}}},
  {id = "enhancement", label = "Enhancement", plural = "Enhancements", set = "Enhanced", sample = "m_bonus", shape = "playing",
    fields = {{id = "chips", label = "+Chips when scored", type = "num", num = n(0, 200, 30, 5)}, {id = "mult", label = "+Mult when scored", type = "num", num = n(0, 30, 0)}, {id = "xmult", label = "XMult when scored", type = "num", num = n(1, 4, 1, 0.25, "x")}, {id = "money", label = "$ when scored", type = "num", num = n(0, 10, 0, 1, "$")}},
    adv_fields = {{id = "held_xmult", label = "XMult while held", type = "num", num = n(1, 3, 1, 0.25, "x")}, {id = "held_money", label = "$ held at round end", type = "num", num = n(0, 10, 0, 1, "$")}, {id = "breaks", label = "Breaks: 1 in", type = "num", num = n(0, 10, 0)}, {id = "no_rank", label = "No rank or suit", type = "toggle", def = false}, {id = "retrigger", label = "Scores again", type = "num", num = n(0, 0, 0), new = true}, {id = "always", label = "Always scores", type = "toggle", def = false}}},
  {id = "seal", label = "Seal", plural = "Seals", set = "Seal", sample = "Red", shape = "playing", effects = "seal", simple_max = 1, max = 3, fields = {}},
  {id = "edition", label = "Edition", plural = "Editions", set = "Edition", sample = "foil", shape = "card",
    fields = {{id = "shader", label = "Shine", type = "choice", options = Cat.SHADERS, def = "foil"}, {id = "chips", label = "+Chips", type = "num", num = n(0, 200, 50, 5)}, {id = "mult", label = "+Mult", type = "num", num = n(0, 30, 0)}, {id = "xmult", label = "XMult", type = "num", num = n(1, 3, 1, 0.1, "x")}},
    adv_fields = {{id = "slot", label = "+1 slot (like Negative)", type = "toggle", def = false}, {id = "weight", label = "How often it shows", type = "num", num = n(1, 20, 5)}, {id = "sell", label = "+$ sell value", type = "num", num = n(0, 0, 0, 1, "$"), new = true}}},
  {id = "tag", label = "Tag", plural = "Tags", set = "Tag", sample = "tag_double", shape = "tag", effects = "tag", simple_max = 1, max = 3,
    fields = {},
    adv_fields = {{id = "when", label = "Works", type = "choice", options = Cat.TAG_WHEN, def = "now"}}},
  {id = "blind", label = "Blind", plural = "Blinds", set = "Blind", sample = "bl_wall", shape = "blind", effects = "boss", simple_max = 1, max = 4, whens = "blind",
    fields = {{id = "size", label = "Size", type = "num", num = n(1, 6, 2, 0.5, "x")}, {id = "reward", label = "Reward", type = "num", num = n(1, 10, 5, 1, "$")}},
    adv_fields = {{id = "colour", label = "Colour", type = "choice", options = Cat.BLIND_COLOURS, def = "RED"}, {id = "min_ante", label = "From ante", type = "num", num = n(1, 8, 1)}, {id = "showdown", label = "Final boss (ante 8)", type = "toggle", def = false}}},
  {id = "stake", label = "Stake", plural = "Stakes", set = "Stake", sample = "stake_red", shape = "stake", effects = "stake", simple_max = 2, max = 6, whens = "run",
    fields = {},
    adv_fields = {{id = "base", label = "On top of", type = "choice", options = Cat.STAKES, def = "stake_white"}}},
  {id = "deck", label = "Deck", plural = "Decks", set = "Back", sample = "b_red", shape = "back", effects = "deck", simple_max = 3, max = 8, whens = "run", fields = {}},
  {id = "booster", label = "Booster pack", plural = "Booster packs", set = "Booster", sample = "p_arcana_normal_1", shape = "card",
    fields = {{id = "pack", label = "Cards inside", type = "choice", options = Cat.PACKS, def = "Arcana"}, {id = "size", label = "Size", type = "choice", options = Cat.PACK_SIZES, def = "Normal"}, {id = "cost", label = "Cost", type = "num", num = n(2, 12, 4, 1, "$")}},
    adv_fields = {{id = "shown", label = "Cards shown", type = "num", num = n(2, 6, 3)}, {id = "choose", label = "Cards to take", type = "num", num = n(1, 3, 1)}, {id = "weight", label = "How often it shows", type = "num", num = n(1, 20, 4)}, {id = "requires", label = "Appears in shops", type = "choice", options = Cat.VOUCHERS, def = "none", none = true, dynamic = "voucher", new = true}}},
  {id = "collab", label = "Collab", plural = "Collabs", set = "Collab", sample = "H_K", shape = "playing",
    fields = {{id = "suit", label = "Suit", type = "choice", options = Cat.SUITS, def = "Hearts"}}},
}

Cat.BY_ID = {}
for _, k in ipairs(Cat.KINDS) do Cat.BY_ID[k.id] = k end
Cat.MORE_MAX = {tarot = 6, planet = 4, spectral = 6, voucher = 8, seal = 5, tag = 5, blind = 6, stake = 8, deck = 10}
for _, k in ipairs(Cat.KINDS) do
  k.v3_max = k.max
  if k.id == "blind" then k.v3_max = 3 end
  if Cat.MORE_MAX[k.id] then k.max = Cat.MORE_MAX[k.id] end
end

function Cat.kind(id) return Cat.BY_ID[id] or Cat.BY_ID.joker end

local SHOP_MODS = {
  {id = "hand_size", label = "Hand size", num = n(-2, 3, 1), simple = true, line = "{C:attention}%+d{} hand size"},
  {id = "joker_slots", label = "Joker slots", num = n(-2, 3, 1), simple = true, line = "{C:attention}%+d{} Joker slot"},
  {id = "consumable_slots", label = "Consumable slots", num = n(-2, 3, 1), simple = true, line = "{C:attention}%+d{} consumable slot"},
  {id = "hands", label = "Hands per round", num = n(-2, 3, 1), simple = true, line = "{C:blue}%+d{} hand each round"},
  {id = "discards", label = "Discards per round", num = n(-2, 3, 1), simple = true, line = "{C:red}%+d{} discard each round"},
  {id = "interest_cap", label = "Interest cap", num = n(5, 50, 10, 5, "$"), line = "Interest up to {C:money}$%d{} more"},
  {id = "reroll_cost", label = "Reroll price", num = n(-3, 3, -2), line = "Rerolls cost {C:money}$%+d{}"},
  {id = "discount", label = "Shop discount", num = n(10, 50, 25, 5, "%"), line = "Shop items {C:attention}%d%%{} off"},
  {id = "shop_slots", label = "Shop slots", num = n(1, 2, 1), line = "{C:attention}%+d{} card slot in the shop"},
  {id = "money", label = "Money now", num = n(1, 50, 10, 1, "$"), line = "Gain {C:money}$%d{}"},
}

Cat.EFFECTS = {
  use = {
    {id = "enhance", label = "Enhance them", v = "enhancement", simple = true, line = "Turns the cards into {C:attention}%s{}"},
    {id = "seal", label = "Add a seal", v = "seal", simple = true, line = "Adds a {C:attention}%s{} to the cards"},
    {id = "suit", label = "Change their suit", v = "suit", simple = true, line = "Turns the cards into {C:attention}%s{}"},
    {id = "rank_up", label = "Raise their rank", num = n(1, 3, 1), simple = true, line = "Raises the cards' rank by {C:attention}%d{}"},
    {id = "edition", label = "Add an edition", v = "edition", line = "Adds {C:dark_edition}%s{} to the cards"},
    {id = "destroy", label = "Destroy them", simple = true, line = "Destroys the cards"},
    {id = "copy", label = "Copy the left card onto the right", line = "The right card becomes a copy of the left one"},
    {id = "money", label = "Give money", num = n(1, 20, 5, 1, "$"), simple = true, line = "Gives {C:money}$%d{}"},
    {id = "double_money", label = "Double money", num = n(5, 50, 20, 5, "$"), line = "Doubles your money (max {C:money}$%d{})"},
    {id = "create", label = "Make cards", v = "set", num = n(1, 2, 1), simple = true, line = "Makes {C:attention}%d{} %s card"},
    {id = "level_up", label = "Level up a hand", v = "hand", simple = true, line = "Levels up {C:attention}%s{}"},
    {id = "level_all", label = "Level up every hand", line = "Levels up {C:attention}every{} poker hand"},
  },
  spectral = {},
  planet = {
    {id = "money", label = "Give money", num = n(1, 20, 3, 1, "$"), line = "Gives {C:money}$%d{}"},
    {id = "create", label = "Make cards", v = "set", num = n(1, 2, 1), line = "Makes {C:attention}%d{} %s card"},
  },
  voucher = SHOP_MODS,
  seal = {
    {id = "scored_money", label = "When scored: give $", num = n(1, 10, 3, 1, "$"), simple = true, line = "Gives {C:money}$%d{} when scored"},
    {id = "scored_retrigger", label = "When scored: score again", num = n(1, 3, 1), simple = true, line = "Retriggers this card {C:attention}%d{} time"},
    {id = "scored_mult", label = "When scored: +Mult", num = n(1, 20, 5), simple = true, line = "{C:mult}+%d{} Mult when scored"},
    {id = "scored_chips", label = "When scored: +Chips", num = n(5, 100, 30, 5), simple = true, line = "{C:chips}+%d{} Chips when scored"},
    {id = "scored_xmult", label = "When scored: XMult", num = n(1.1, 3, 1.5, 0.1, "x"), line = "{X:mult,C:white}X%s{} Mult when scored"},
    {id = "held_planet", label = "Held at round end: make a Planet", simple = true, line = "Makes the {C:planet}Planet{} of the last hand if held at round end"},
    {id = "held_money", label = "Held at round end: give $", num = n(1, 10, 2, 1, "$"), line = "Gives {C:money}$%d{} if held at round end"},
    {id = "discard_tarot", label = "When discarded: make a Tarot", simple = true, line = "Makes a {C:tarot}Tarot{} when discarded"},
    {id = "discard_money", label = "When discarded: give $", num = n(1, 5, 1, 1, "$"), line = "Gives {C:money}$%d{} when discarded"},
  },
  tag = {
    {id = "money", label = "Give money", num = n(1, 40, 10, 1, "$"), simple = true, line = "Gives {C:money}$%d{}"},
    {id = "money_per_skip", label = "$ per blind skipped", num = n(1, 10, 5, 1, "$"), line = "Gives {C:money}$%d{} per blind skipped"},
    {id = "free_joker", label = "Free Joker in the shop", v = "rarity", simple = true, line = "The shop has a free {C:attention}%s{} Joker"},
    {id = "free_pack", label = "Free pack", v = "pack", simple = true, line = "Opens a free {C:attention}%s Pack{}"},
    {id = "double", label = "Copy the next tag", simple = true, line = "Copies the next {C:attention}Tag{} you get"},
    {id = "hand_size", label = "Hand size next round", num = n(1, 5, 2), line = "{C:attention}+%d{} hand size next round"},
    {id = "free_rerolls", label = "Free rerolls", num = n(1, 5, 1), line = "{C:green}%d{} free reroll"},
    {id = "coupon", label = "Shop is free", line = "Every card in the next shop is {C:money}free{}"},
    {id = "level_up", label = "Level up a hand", v = "hand", num = n(1, 5, 3), line = "Levels up {C:attention}%s{} %d times"},
  },
  boss = {
    {id = "debuff_suit", label = "Debuff a suit", v = "suit", simple = true, line = "All {C:attention}%s{} are debuffed"},
    {id = "debuff_face", label = "Debuff face cards", simple = true, line = "All face cards are debuffed"},
    {id = "debuff_hand", label = "Debuff a poker hand", v = "hand", simple = true, line = "{C:attention}%s{} scores nothing"},
    {id = "only_hand", label = "Only one poker hand", v = "hand", line = "Only {C:attention}%s{} can score"},
    {id = "must_play", label = "Must play this many cards", num = n(1, 5, 5), simple = true, line = "Must play {C:attention}%d{} cards"},
    {id = "no_discards", label = "No discards", line = "No discards this round"},
    {id = "hand_size_minus", label = "Smaller hand", num = n(1, 3, 1), simple = true, line = "{C:attention}-%d{} hand size"},
    {id = "face_down_first", label = "First hand drawn face down", line = "First hand is drawn face down"},
    {id = "money_per_card", label = "Lose $ per card played", num = n(1, 3, 1, 1, "$"), line = "Lose {C:money}$%d{} per card played"},
    {id = "one_hand", label = "Only one hand", simple = true, line = "Play only {C:attention}1{} hand"},
    {id = "halve_base", label = "Halve base Chips and Mult", line = "Base Chips and Mult are halved"},
  },
  stake = {
    {id = "blind_scaling", label = "Bigger blinds", num = n(10, 100, 25, 5, "%"), simple = true, line = "Blinds are {C:red}%d%%{} bigger"},
    {id = "discards_minus", label = "Fewer discards", num = n(1, 2, 1), simple = true, line = "{C:red}-%d{} discard"},
    {id = "hands_minus", label = "Fewer hands", num = n(1, 2, 1), simple = true, line = "{C:blue}-%d{} hand"},
    {id = "no_interest", label = "No interest", simple = true, line = "No interest"},
    {id = "small_no_reward", label = "Small Blind gives no reward", line = "Small Blind gives no reward money"},
    {id = "prices_plus", label = "Higher prices", num = n(1, 3, 1, 1, "$"), line = "Shop prices {C:money}+$%d{}"},
    {id = "eternal", label = "Eternal Jokers in the shop", simple = true, line = "Shop can have {C:attention}Eternal{} Jokers"},
    {id = "perishable", label = "Perishable Jokers in the shop", line = "Shop can have {C:attention}Perishable{} Jokers"},
    {id = "rental", label = "Rental Jokers in the shop", line = "Shop can have {C:attention}Rental{} Jokers"},
    {id = "win_ante", label = "Win at a later ante", num = n(9, 16, 10), line = "Win at ante {C:attention}%d{}"},
  },
  deck = {
    {id = "dollars", label = "Starting money", num = n(-4, 50, 10, 1, "$"), simple = true, line = "Start with {C:money}%+d{} dollars"},
    {id = "hands", label = "Hands per round", num = n(-2, 3, 1), simple = true, line = "{C:blue}%+d{} hand every round"},
    {id = "discards", label = "Discards per round", num = n(-2, 3, 1), simple = true, line = "{C:red}%+d{} discard every round"},
    {id = "hand_size", label = "Hand size", num = n(-2, 3, 1), simple = true, line = "{C:attention}%+d{} hand size"},
    {id = "joker_slots", label = "Joker slots", num = n(-2, 3, 1), simple = true, line = "{C:attention}%+d{} Joker slot"},
    {id = "consumable_slots", label = "Consumable slots", num = n(-2, 3, 1), line = "{C:attention}%+d{} consumable slot"},
    {id = "interest_cap", label = "Interest cap", num = n(5, 50, 10, 5, "$"), line = "Interest up to {C:money}$%d{} more"},
    {id = "win_ante", label = "Win at ante", num = n(4, 16, 8), line = "Win at ante {C:attention}%d{}"},
    {id = "no_faces", label = "No face cards", simple = true, line = "Start with no face cards"},
    {id = "remove_suit", label = "Remove a suit", v = "suit", line = "Start with no {C:attention}%s{}"},
    {id = "enhance_all", label = "Every card enhanced", v = "enhancement", line = "Every card is a {C:attention}%s{}"},
    {id = "start_voucher", label = "Start with a voucher", v = "voucher", simple = true, line = "Start with {C:attention}%s{}"},
    {id = "start_consumable", label = "Start with consumables", v = "set", num = n(1, 2, 1), line = "Start with {C:attention}%d{} %s card"},
  },
}

for _, e in ipairs(Cat.EFFECTS.use) do Cat.EFFECTS.spectral[#Cat.EFFECTS.spectral + 1] = e end
for _, e in ipairs({
  {id = "destroy_random", label = "Price: destroy cards in hand", num = n(1, 5, 1), simple = true, line = "Destroys {C:attention}%d{} random card in hand"},
  {id = "money_zero", label = "Price: money set to $0", simple = true, line = "Sets money to {C:money}$0{}"},
  {id = "hand_size_minus", label = "Price: -1 hand size", simple = true, line = "{C:red}-1{} hand size"},
  {id = "add_cards", label = "Add cards to the deck", num = n(1, 5, 3), line = "Adds {C:attention}%d{} enhanced face cards to the deck"},
  {id = "joker_edition", label = "Edition on a random Joker", v = "shader", line = "Adds {C:dark_edition}%s{} to a random Joker"},
  {id = "rare_joker", label = "Make a Joker", v = "rarity", line = "Makes a {C:attention}%s{} Joker"},
}) do Cat.EFFECTS.spectral[#Cat.EFFECTS.spectral + 1] = e end

Cat.SHOP_SETS = {"Joker", "Tarot", "Planet", "Spectral", "Playing"}
Cat.RARITY3 = {1, 2, 3}
Cat.RANK_VALUES = {"Ace", "King", "Queen", "Jack", "10", "9", "8", "7", "6", "5", "4", "3", "2"}
Cat.LEVEL_HANDS = {"random", "all"}
for _, h in ipairs(Cat.HANDS) do Cat.LEVEL_HANDS[#Cat.LEVEL_HANDS + 1] = h end

Cat.RUN_WHEN = {"now", "blind_selected", "hand_played", "card_scored", "discard", "round_end", "shop_enter", "reroll", "ante_up"}
Cat.BLIND_WHEN = {"blind_selected", "hand_played", "card_scored", "discard", "round_end"}
Cat.SCORE_WHEN = {"hand_played", "card_scored"}
Cat.ROUND_WHEN = {"blind_selected", "hand_played", "discard"}
Cat.RUN_ONLY = {"hand", "boss", "blind", "ante", "money", "hands_left", "discards_left", "first_hand", "last_hand", "chance", "every", "jokers", "round", "deck_cards", "held_cards", "consumables", "suit", "rank", "enhancement", "seal", "edition"}
Cat.CARD_ONLY = {suit = true, rank = true, enhancement = true, seal = true, edition = true}
Cat.MAX_ONLY = 3
Cat.EVERY = {def = 2, lo = 1, hi = 1e6, step = 1, big = 10}

local function run(id, label, num, line, o)
  o = o or {}
  o.id, o.label, o.num, o.line, o.run, o.new = id, label, num, line, true, o.new ~= false
  return o
end

Cat.RUN = {
  run("interest_amount", "Interest per $5", n(-1e6, 1e6, 1, 1, "$"), "Interest gives {C:money}%s{} more for every $5", {args = {"n"}}),
  run("money_per_hand", "$ per hand left", n(-1e6, 1e6, 1, 1, "$"), "{C:money}%s{} more per hand left at cash out", {args = {"n"}, sign = true}),
  run("money_per_discard", "$ per discard left", n(-1e6, 1e6, 1, 1, "$"), "{C:money}%s{} per discard left at cash out", {args = {"n"}, sign = true}),
  run("blind_size", "Blind size", n(0.01, 1e6, 0.8, 0.05, "x"), "Blinds are {C:attention}%s{} as big", {args = {"n"}, simple = true}),
  run("probability", "Chances", n(0.01, 1e6, 2, 0.5, "x"), "All chances are {C:green}%s{}", {args = {"n"}}),
  run("shop_rate", "Shop weight of a card type", n(-1e6, 1e6, 4, 1), "{C:attention}%s{} cards in the shop: {C:attention}%s{} weight", {v = "shopset", args = {"v", "n"}, sign = true}),
  run("edition_rate", "Edition chance", n(0.01, 1e6, 2, 0.5, "x"), "Editions show up {C:dark_edition}%s{} as often", {args = {"n"}}),
  run("rarity_weight", "Joker rarity weight", n(-1e6, 1e6, 10, 1), "{C:attention}%s{} Jokers: {C:attention}%s{} weight", {v = "rarity3", args = {"v", "n"}, sign = true}),
  run("pack_slots", "Booster pack slots", n(-2, 10, 1), "{C:attention}%s{} booster pack slot in the shop", {args = {"n"}, sign = true, simple = true}),
  run("voucher_slots", "Voucher slots", n(-1, 10, 1), "{C:attention}%s{} voucher slot in the shop", {args = {"n"}, sign = true}),
  run("free_rerolls", "Free rerolls every shop", n(-1e3, 1e6, 1), "{C:green}%s{} free reroll in every shop", {args = {"n"}, sign = true}),
  run("ante_now", "Change the ante", n(-1e3, 1e3, -1), "Ante {C:attention}%s{}", {args = {"n"}, sign = true}),
  run("win_ante", "Win at ante", n(1, 1e6, 10), "Win at ante {C:attention}%d{}"),
  run("create", "Make cards", n(1, 1e3, 1), "Makes {C:attention}%d{} %s card", {v = "set", simple = true}),
  run("level_up", "Level up a hand", n(1, 1e6, 1), "Levels up {C:attention}%s{} %d times", {v = "levelhand"}),
  run("tag", "Give tags", n(1, 1e3, 1), "Gives {C:attention}%d{} %s", {v = "tag"}),
  run("enhance_random", "Enhance random deck cards", n(1, 1e3, 2), "Turns {C:attention}%d{} random cards in your deck into {C:attention}%s{}", {v = "enhancement"}),
  run("add_cards", "Add cards to the deck", n(1, 1e3, 2), "Adds {C:attention}%d{} %s to your deck", {v = "addcard"}),
  run("joker_edition", "Edition on a random Joker", nil, "Adds {C:dark_edition}%s{} to a random Joker", {v = "shader"}),
  run("sell_value", "Jokers gain sell value", n(-1e6, 1e9, 1, 1, "$"), "Every Joker gains {C:money}%s{} sell value", {args = {"n"}}),
  run("hands_round", "+Hands this round", n(-1e3, 1e3, 1), "{C:blue}%s{} hand this round", {args = {"n"}, sign = true, whens = Cat.ROUND_WHEN}),
  run("discards_round", "+Discards this round", n(-1e3, 1e3, 1), "{C:red}%s{} discard this round", {args = {"n"}, sign = true, whens = Cat.ROUND_WHEN}),
  run("disable_boss", "Disable the Boss Blind", nil, "Disables the {C:attention}Boss Blind{}", {whens = Cat.ROUND_WHEN}),
  run("chips", "+Chips", n(-1e15, 1e15, 30, 5), "{C:chips}%s{} Chips", {args = {"n"}, sign = true, whens = Cat.SCORE_WHEN, simple = true}),
  run("mult", "+Mult", n(-1e15, 1e15, 4, 1), "{C:mult}%s{} Mult", {args = {"n"}, sign = true, whens = Cat.SCORE_WHEN, simple = true}),
  run("xmult", "XMult", n(0.05, 1e15, 1.5, 0.05, "x"), "{X:mult,C:white}%s{} Mult", {args = {"n"}, whens = Cat.SCORE_WHEN, simple = true}),
}

local SHOP_BASE = {}
for i, e in ipairs(SHOP_MODS) do SHOP_BASE[i] = e end

local RUN_OLD = {hand_size = true, joker_slots = true, consumable_slots = true, hands = true, discards = true, interest_cap = true, reroll_cost = true, discount = true, shop_slots = true, money = true}
for _, e in ipairs(SHOP_MODS) do
  if RUN_OLD[e.id] then e.run = true end
end
for _, e in ipairs(Cat.EFFECTS.deck) do
  if RUN_OLD[e.id] or e.id == "win_ante" then e.run = true end
  if e.id == "dollars" then e.run = true end
end

local function merge(list, extra, skip)
  local have = {}
  for _, e in ipairs(list) do have[e.id] = true end
  for _, e in ipairs(extra) do
    if not have[e.id] and not (skip and skip[e.id]) then
      local c = {}
      for k2, v in pairs(e) do c[k2] = v end
      list[#list + 1] = c
    end
  end
end
merge(Cat.EFFECTS.voucher, Cat.RUN)
merge(Cat.EFFECTS.deck, Cat.RUN)
merge(Cat.EFFECTS.stake, Cat.RUN)
merge(Cat.EFFECTS.stake, SHOP_BASE)
merge(Cat.EFFECTS.boss, Cat.RUN, {interest_amount = true, money_per_hand = true, money_per_discard = true, blind_size = true, shop_rate = true, edition_rate = true, rarity_weight = true, pack_slots = true, voucher_slots = true, free_rerolls = true, ante_now = true, win_ante = true})
merge(Cat.EFFECTS.boss, SHOP_BASE, {interest_cap = true, reroll_cost = true, discount = true, shop_slots = true})
for _, list in ipairs({Cat.EFFECTS.stake, Cat.EFFECTS.boss}) do
  for _, e in ipairs(list) do if RUN_OLD[e.id] then e.run = true; e.new = true end end
end

for _, e in ipairs({
  {id = "perma_chips", label = "Cards gain Chips for good", num = n(-1e9, 1e15, 10, 5), line = "The cards gain {C:chips}%s{} Chips for good", args = {"n"}, sign = true, new = true},
  {id = "hand_size_plus", label = "+Hand size for good", num = n(-1e3, 1e3, 1), line = "{C:attention}%s{} hand size for the rest of the run", args = {"n"}, sign = true, new = true},
  {id = "joker_slots_plus", label = "+Joker slots for good", num = n(-1e3, 1e3, 1), line = "{C:attention}%s{} Joker slot for the rest of the run", args = {"n"}, sign = true, new = true},
  {id = "level_random", label = "Level up random hands", num = n(1, 1e6, 1), line = "Levels up {C:attention}%d{} random poker hands", new = true},
  {id = "tag", label = "Give tags", v = "tag", num = n(1, 1e3, 1), line = "Gives {C:attention}%d{} %s", new = true},
  {id = "sell_value", label = "Jokers gain sell value", num = n(-1e6, 1e9, 2, 1, "$"), line = "Every Joker gains {C:money}%s{} sell value", args = {"n"}, new = true},
}) do
  Cat.EFFECTS.use[#Cat.EFFECTS.use + 1] = e
  Cat.EFFECTS.spectral[#Cat.EFFECTS.spectral + 1] = e
  if e.id == "level_random" or e.id == "tag" then Cat.EFFECTS.planet[#Cat.EFFECTS.planet + 1] = e end
end
for _, e in ipairs({
  {id = "create", label = "Make cards", v = "set", num = n(1, 1e3, 1), line = "Makes {C:attention}%d{} %s card", new = true},
  {id = "level_all", label = "Level up every hand", num = n(1, 1e6, 1), line = "Levels up every poker hand {C:attention}%d{} times", new = true},
  {id = "hands_next", label = "+Hands next round", num = n(1, 1e3, 1), line = "{C:blue}+%d{} hand next round", new = true},
}) do Cat.EFFECTS.tag[#Cat.EFFECTS.tag + 1] = e end
for _, e in ipairs({
  {id = "held_xmult", label = "Held in hand: XMult", num = n(0.05, 1e15, 1.5, 0.05, "x"), line = "{X:mult,C:white}%s{} Mult while held in hand", args = {"n"}, new = true},
  {id = "held_mult", label = "Held in hand: +Mult", num = n(1, 1e15, 5), line = "{C:mult}+%d{} Mult while held in hand", new = true},
}) do Cat.EFFECTS.seal[#Cat.EFFECTS.seal + 1] = e end
Cat.EFFECTS.boss[#Cat.EFFECTS.boss + 1] = {id = "debuff_rank", label = "Debuff a rank", v = "rankvalue", line = "Every {C:attention}%s{} is debuffed", new = true}

Cat.JOKER = {
  when_simple = {card_scored = true, card_held = true, hand_played = true, discard = true, blind_selected = true, round_end = true},
  only_simple = {hand = true, suit = true, rank = true, first_hand = true, last_hand = true, money = true, boss = true, chance = true},
  give_simple = {chips = true, mult = true, xmult = true, money = true, retrigger = true, gain_mult = true, create = true, level_up = true},
}

Cat.LIFT_IDS = {chips = true, mult = true, scored_chips = true, scored_mult = true, scored_retrigger = true, levels = true, level_up = true, add_cards = true, free_rerolls = true}
Cat.LIFT_SKIP = {cost = true, prices_plus = true}

local function lift(spec, id)
  if type(spec) ~= "table" or spec.old_hi then return end
  local lim
  if spec.fmt == "$" and not Cat.LIFT_SKIP[id] then lim = 1e9
  elseif spec.fmt == "x" then lim = 1e6
  elseif Cat.LIFT_IDS[id] then lim = (id == "scored_retrigger" or id == "levels" or id == "level_up" or id == "add_cards" or id == "free_rerolls") and 1000 or 1e9 end
  if lim and lim > spec.hi then spec.old_hi = spec.hi; spec.hi = lim end
end

Cat.FREE = {
  cost = {0, 1e9}, select = {0, 100}, levels = {1, 1e6}, chips = {0, 1e15}, mult = {0, 1e15}, xmult = {1, 1e15}, money = {0, 1e9},
  held_xmult = {1, 1e15}, held_money = {0, 1e9}, breaks = {0, 1e6}, weight = {0, 1e6}, size = {0.05, 1e6}, reward = {0, 1e9}, min_ante = {1, 1e6},
  shown = {1, 10}, choose = {1, 10}, max_buys = {1, 1e6}, retrigger = {0, 1000}, sell = {0, 1e9},
}
Cat.FREE_EFFECT = {
  hand_size = {-1e3, 1e3}, joker_slots = {-1e3, 1e3}, consumable_slots = {-1e3, 1e3}, hands = {-1e3, 1e3}, discards = {-1e3, 1e3},
  interest_cap = {0, 1e9}, reroll_cost = {-1e6, 1e6}, discount = {0, 100}, shop_slots = {-10, 20}, money = {-1e9, 1e9}, dollars = {-1e9, 1e9},
  rank_up = {-12, 12}, double_money = {1, 1e9}, create = {1, 1e3}, destroy_random = {1, 1e3}, add_cards = {1, 1e3},
  scored_money = {1, 1e9}, scored_retrigger = {1, 1000}, scored_mult = {1, 1e15}, scored_chips = {1, 1e15}, scored_xmult = {0.05, 1e15}, held_money = {1, 1e9}, discard_money = {1, 1e9},
  money_per_skip = {1, 1e9}, free_rerolls = {1, 1e6}, level_up = {1, 1e6},
  must_play = {1, 52}, hand_size_minus = {1, 100}, money_per_card = {1, 1e9},
  blind_scaling = {-99, 1e6}, discards_minus = {1, 1e3}, hands_minus = {1, 1e3}, prices_plus = {1, 1e9}, win_ante = {1, 1e6}, start_consumable = {1, 1e3},
}

local function free(spec, id, lim)
  if type(spec) ~= "table" or spec.v3_hi then return end
  spec.v3_lo, spec.v3_hi = spec.lo, spec.hi
  if lim then
    spec.lo, spec.hi = lim[1], lim[2]
  elseif spec.fmt == "x" then spec.hi = math.max(spec.hi, 1e15)
  else spec.hi = math.max(spec.hi, 1e6) end
  if spec.def < spec.lo then spec.def = spec.lo end
  if spec.def > spec.hi then spec.def = spec.hi end
  spec.big = spec.big or (spec.step < 1 and 1 or spec.step * 10)
end

for _, k in ipairs(Cat.KINDS) do
  for _, list in ipairs({k.fields or {}, k.adv_fields or {}}) do
    for _, f in ipairs(list) do if f.type == "num" then lift(f.num, f.id) end end
  end
end
for _, list in pairs(Cat.EFFECTS) do
  for _, e in ipairs(list) do lift(e.num, e.id) end
end
for _, k in ipairs(Cat.KINDS) do
  for _, list in ipairs({k.fields or {}, k.adv_fields or {}}) do
    for _, f in ipairs(list) do if f.type == "num" then free(f.num, f.id, Cat.FREE[f.id]) end end
  end
end
for _, list in pairs(Cat.EFFECTS) do
  for _, e in ipairs(list) do
    if e.num and not e.new then free(e.num, e.id, Cat.FREE_EFFECT[e.id]) end
    if e.num and e.new and not e.num.big then e.num.big = e.num.step < 1 and 1 or e.num.step * 10 end
  end
end

function Cat.run_whens(kind_id)
  local k = Cat.kind(kind_id)
  if k.whens == "run" then return Cat.RUN_WHEN end
  if k.whens == "blind" then return Cat.BLIND_WHEN end
  return nil
end

function Cat.whens_for(kind_id, id)
  local all = Cat.run_whens(kind_id)
  local spec = Cat.effect(kind_id, id)
  if not (all and spec and spec.run) then return nil end
  local out = {}
  for _, w in ipairs(all) do
    local ok = true
    if spec.whens then
      ok = false
      for _, x in ipairs(spec.whens) do if x == w then ok = true end end
    elseif w == "card_scored" then ok = id == "money"
    end
    if ok then out[#out + 1] = w end
  end
  return out
end

function Cat.default_when(kind_id, id)
  local list = Cat.whens_for(kind_id, id)
  if not list or #list == 0 then return nil end
  return list[1]
end

function Cat.only_allowed(when, id)
  if Cat.CARD_ONLY[id] then return when == "card_scored" end
  if id == "hand" then return when == "hand_played" or when == "card_scored" end
  if id == "first_hand" or id == "last_hand" or id == "hands_left" or id == "discards_left" then
    return when == "hand_played" or when == "card_scored" or when == "discard" or when == "blind_selected" or when == "round_end"
  end
  return true
end

function Cat.only_spec(id)
  if id == "every" then return Cat.EVERY end
  if id == "chance" then return R.NUM.chance end
  if id == "money" then return R.NUM.money_cond end
  return R.NUM[id]
end

Cat.OP_ONLY = {money = true, hands_left = true, discards_left = true, ante = true, jokers = true, round = true, deck_cards = true, held_cards = true, consumables = true}

function Cat.default_only(id)
  if id == "every" then return {id = "every", n = Cat.EVERY.def} end
  local o = R.default_only(id)
  return o
end

local function member(list, v)
  for _, x in ipairs(list or {}) do if x == v or tostring(x) == tostring(v) then return x end end
  return nil
end

function Cat.clean_only(when, list)
  local out = {}
  for _, o in ipairs(type(list) == "table" and list or {}) do
    if type(o) == "table" and member(Cat.RUN_ONLY, o.id) and Cat.only_allowed(when, o.id) and #out < Cat.MAX_ONLY then
      local c = {id = o.id}
      local d = Cat.default_only(o.id)
      if d.v ~= nil then
        local pool = ({hand = R.HANDS, suit = R.SUITS, rank = R.RANKS, enhancement = R.ENHANCEMENTS, seal = R.SEALS, edition = R.EDITIONS, blind = R.BLINDS})[o.id]
        local ok = pool and member(pool, o.v)
        c.v = ok ~= nil and ok or d.v
        if o.id == "hand" then c.mode = o.mode == "is" and "is" or "contains" end
      end
      if d.op then c.op = member(R.OPS, o.op) or d.op end
      local spec = Cat.only_spec(o.id)
      if d.n ~= nil and spec then
        local v = tonumber(o.n) or spec.def
        if v ~= v then v = spec.def end
        v = math.max(spec.lo, math.min(spec.hi, v))
        c.n = math.floor(v + 0.5)
      end
      if o.neg then c.neg = true end
      out[#out + 1] = c
    end
  end
  return out
end

local function off_v3(spec, v)
  if not (spec and spec.v3_hi) then return false end
  if v < spec.v3_lo or v > spec.v3_hi then return true end
  if spec.old_hi and v > spec.old_hi then return false end
  local steps = (v - spec.v3_lo) / spec.step
  return math.abs(steps - math.floor(steps + 0.5)) > 1e-6
end

function Cat.need_v(c)
  if type(c) ~= "table" then return 1 end
  local k = Cat.kind(c.kind)
  local need = 1
  for _, list in ipairs({k.fields or {}, k.adv_fields or {}}) do
    for _, f in ipairs(list) do
      local raw
      if type(c.fields) == "table" then raw = c.fields[f.id] end
      local v = tonumber(raw)
      if f.new and raw ~= nil and raw ~= (f.type == "num" and f.num.def or f.def) then return 4 end
      if f.dynamic and raw ~= nil and raw ~= "none" and not member(f.options, raw) then return 4 end
      if f.type == "num" and v and off_v3(f.num, v) then return 4 end
      if f.type == "num" and v and f.num.old_hi and v > f.num.old_hi then need = 3 end
    end
  end
  for _, e in ipairs(type(c.effects) == "table" and c.effects or {}) do
    local spec = type(e) == "table" and Cat.effect(c.kind, e.id)
    if spec then
      if e.id == "tag" and e.v == R.TAG_RANDOM then return 5 end
      if spec.new or (e.when and e.when ~= "now") or (type(e.only) == "table" and #e.only > 0) then return 4 end
      local v = tonumber(e.n)
      if spec.num and v and off_v3(spec.num, v) then return 4 end
      if spec.num and spec.num.old_hi and v and v > spec.num.old_hi then need = 3 end
    end
  end
  if type(c.effects) == "table" and #c.effects > (k.v3_max or k.max or 0) then return 4 end
  return need
end

function Cat.effects_for(kind_id)
  local k = Cat.kind(kind_id)
  return k.effects and Cat.EFFECTS[k.effects] or {}
end

function Cat.effect(kind_id, id)
  for _, e in ipairs(Cat.effects_for(kind_id)) do if e.id == id then return e end end
  return nil
end

function Cat.values(what)
  if what == "enhancement" then return Cat.ENHANCEMENTS end
  if what == "seal" then return Cat.SEALS end
  if what == "suit" then return Cat.SUITS end
  if what == "edition" then return Cat.EDITIONS end
  if what == "shader" then return Cat.SHADERS end
  if what == "set" then return Cat.SETS end
  if what == "hand" then return Cat.HANDS end
  if what == "rarity" then return Cat.RARITY end
  if what == "pack" then return {"Arcana", "Celestial", "Spectral", "Standard", "Buffoon"} end
  if what == "voucher" then return Cat.VOUCHERS end
  if what == "shopset" then return Cat.SHOP_SETS end
  if what == "rarity3" then return Cat.RARITY3 end
  if what == "levelhand" then return Cat.LEVEL_HANDS end
  if what == "tag" then
    local out = {R.TAG_RANDOM}
    for _, v in ipairs(R.TAGS) do out[#out + 1] = v end
    return out
  end
  if what == "addcard" then return R.ADD_CARDS end
  if what == "rankvalue" then return Cat.RANK_VALUES end
  return {}
end

local RARITY_NAME = {"Common", "Uncommon", "Rare", "Legendary"}
local SHADER_NAME = {foil = "Foil", holo = "Holographic", polychrome = "Polychrome", negative = "Negative"}
local SEAL_NAME = {Red = "Red Seal", Blue = "Blue Seal", Gold = "Gold Seal", Purple = "Purple Seal"}
local PLAIN = {now = "Right away", shop = "At the next shop", round = "At the next round", Normal = "Normal", Jumbo = "Jumbo", Mega = "Mega",
  RED = "Red", BLUE = "Blue", GREEN = "Green", PURPLE = "Purple", ORANGE = "Orange", GOLD = "Gold", BLACK = "Black", none = "Nothing", all = "Every hand",
  Arcana = "Arcana", Celestial = "Celestial", Spectral = "Spectral", Standard = "Standard", Buffoon = "Buffoon", Forge = "Forge creations",
  Tarot = "Tarot", Planet = "Planet", Joker = "Joker"}

local function game_name(set, key)
  local d = G and G.localization and G.localization.descriptions
  local t = d and d[set] and d[set][key]
  if t and t.name then return type(t.name) == "table" and table.concat(t.name, " ") or t.name end
  return nil
end

function Cat.value_label(what, v)
  local T = require("functions/forge/forge_text")
  if v == nil then return "" end
  if what == "rarity3" then what = "rarity" end
  if what == "shopset" and v == "Playing" then return mod_loc("Playing cards") end
  if what == "shopset" then what = "set" end
  if what == "levelhand" then
    if v == "random" then return mod_loc("a random hand") end
    what = "hand"
  end
  if what == "tag" and v == R.TAG_RANDOM then return mod_loc("Random Tag") end
  if what == "tag" then return T and T.tag_name(v) or v end
  if what == "addcard" then
    if v == "c_base" then return mod_loc("Random card") end
    what = "enhancement"
  end
  if what == "rankvalue" then
    local id = ({Ace = 14, King = 13, Queen = 12, Jack = 11})[v] or tonumber(v)
    return T and T.rank_name(id, T.lang and T.lang() or "en") or tostring(v)
  end
  if what == "rarity" then
    local name = RARITY_NAME[tonumber(v) or 1] or "Common"
    local loc = G and G.localization and G.localization.misc and G.localization.misc.dictionary
    local key = ({"k_common", "k_uncommon", "k_rare", "k_legendary"})[tonumber(v) or 1]
    return loc and key and loc[key] or mod_loc(name)
  end
  if what == "enhancement" then return T and T.enh_name(v) or v end
  if what == "seal" then return T and T.seal_name(v) or mod_loc(SEAL_NAME[v] or v) end
  if what == "suit" then return T and T.suit_name(v, true) or v end
  if what == "hand" then
    if v == "all" then return mod_loc("Every hand") end
    return T and T.hand_name(v) or v
  end
  if what == "edition" or what == "shader" then
    local key = ({foil = "e_foil", holo = "e_holo", polychrome = "e_polychrome", negative = "e_negative"})[v]
    return (key and game_name("Edition", key)) or mod_loc(SHADER_NAME[v] or v)
  end
  if what == "voucher" or what == "requires" then
    if v == "none" then return mod_loc("Nothing") end
    return game_name("Voucher", v) or v
  end
  if what == "base" then
    local key = v
    return game_name("Stake", key) or v
  end
  if what == "set" then
    local loc = G and G.localization and G.localization.misc and G.localization.misc.dictionary
    local k = ({Tarot = "k_tarot", Planet = "k_planet", Spectral = "k_spectral", Joker = "k_joker"})[v]
    return loc and k and loc[k] or mod_loc(PLAIN[v] or v)
  end
  if PLAIN[v] then return mod_loc(PLAIN[v]) end
  return tostring(v)
end

function Cat.field_values(f)
  local list = {}
  if f.none then list[1] = "none" end
  for _, v in ipairs(f.options or {}) do list[#list + 1] = v end
  if f.all then list[#list + 1] = "all" end
  return list
end

function Cat.field_what(f)
  if f.id == "rarity" then return "rarity" end
  if f.id == "hand" then return "hand" end
  if f.id == "shader" then return "shader" end
  if f.id == "suit" then return "suit" end
  if f.id == "requires" then return "voucher" end
  if f.id == "base" then return "base" end
  return "plain"
end

function Cat.fmt(spec, v)
  v = tonumber(v) or 0
  local s = (v == math.floor(v)) and tostring(math.floor(v)) or string.format("%.2f", v):gsub("0+$", "")
  if spec and spec.fmt == "$" then return (v < 0 and "-$" .. s:gsub("^%-", "") or "$" .. s) end
  if spec and spec.fmt == "x" then return "X" .. s end
  if spec and spec.fmt == "%" then return s .. "%" end
  return s
end

function Cat.clamp(spec, v)
  v = tonumber(v) or spec.def
  if v ~= v then v = spec.def end
  if v < spec.lo then v = spec.lo end
  if v > spec.hi then v = spec.hi end
  if spec.step % 1 == 0 and spec.lo % 1 == 0 then return math.floor(v + 0.5) end
  return math.floor(v * 100 + 0.5) / 100
end

function Cat.fmt_signed(spec, v, sign)
  local s2 = Cat.fmt(spec, v)
  if sign and (tonumber(v) or 0) >= 0 then return "+" .. s2 end
  return s2
end

function Cat.default_effect(kind_id, id)
  local e = Cat.effect(kind_id, id)
  if not e then return nil end
  local out = {id = id}
  if e.num then out.n = e.num.def end
  if e.v then out.v = Cat.values(e.v)[1] end
  if e.v == "hand" then out.v = "Pair" end
  if e.v == "enhancement" then out.v = "m_gold" end
  if e.v == "rarity" then out.v = 2 end
  if e.v == "rarity3" then out.v = 3 end
  if e.v == "shopset" then out.v = "Tarot" end
  if e.v == "levelhand" then out.v = "random" end
  if e.v == "tag" then out.v = "tag_double" end
  if e.v == "addcard" then out.v = "c_base" end
  out.when = Cat.default_when(kind_id, id)
  if out.when == "now" then out.when = nil end
  return out
end

function Cat.default_fields(kind_id)
  local k = Cat.kind(kind_id)
  local out = {}
  for _, list in ipairs({k.fields or {}, k.adv_fields or {}}) do
    for _, f in ipairs(list) do
      if f.type == "num" then out[f.id] = f.num.def else out[f.id] = f.def end
    end
  end
  return out
end

function Cat.clean_fields(kind_id, t)
  t = type(t) == "table" and t or {}
  local k = Cat.kind(kind_id)
  local out = Cat.default_fields(kind_id)
  for _, list in ipairs({k.fields or {}, k.adv_fields or {}}) do
    for _, f in ipairs(list) do
      local v = t[f.id]
      if f.type == "num" then
        if v ~= nil then out[f.id] = Cat.clamp(f.num, v) end
      elseif f.type == "toggle" then
        if v ~= nil then out[f.id] = v and true or false end
      elseif f.dynamic and type(v) == "string" and v:match("^v_[%w_]+$") and #v <= 40 then
        out[f.id] = v
      else
        for _, ok in ipairs(Cat.field_values(f)) do if ok == v then out[f.id] = v end end
      end
    end
  end
  return out
end

function Cat.clean_effects(kind_id, list)
  local k = Cat.kind(kind_id)
  local out = {}
  for _, e in ipairs(type(list) == "table" and list or {}) do
    local spec = type(e) == "table" and Cat.effect(kind_id, e.id)
    if spec and #out < (k.max or 0) then
      local c = {id = e.id}
      if spec.num then c.n = Cat.clamp(spec.num, e.n) end
      if spec.v then
        local okv = false
        for _, v in ipairs(Cat.values(spec.v)) do if v == e.v or tostring(v) == tostring(e.v) then c.v = v; okv = true end end
        if not okv then c.v = Cat.default_effect(kind_id, e.id).v end
      end
      local whens = Cat.whens_for(kind_id, e.id)
      if whens and #whens > 0 then
        c.when = member(whens, e.when) or whens[1]
        if c.when == "now" and e.when == nil then c.when = nil end
        local only = Cat.clean_only(c.when or "now", e.only)
        if #only > 0 then c.only = only end
      end
      out[#out + 1] = c
    end
  end
  return out
end

local function fill(tmpl, e, spec)
  local v = spec.v and Cat.value_label(spec.v, e.v) or nil
  local num = e.n
  local str = mod_loc(tmpl)
  local ok, r = pcall(function()
    if spec.args then
      local vals = {}
      for i, a in ipairs(spec.args) do vals[i] = a == "v" and tostring(v) or Cat.fmt_signed(spec.num, num, spec.sign) end
      return string.format(str, unpack(vals))
    end
    if spec.num and spec.v then
      if tmpl:find("%%s.*%%d") then return string.format(str, v, num) end
      return string.format(str, num, v)
    end
    if spec.num then
      if tmpl:find("%%s") then return string.format(str, Cat.fmt({}, num)) end
      return string.format(str, math.floor(num))
    end
    if spec.v then return string.format(str, v) end
    return str
  end)
  return ok and r or str
end

Cat.WHEN_LABEL = {now = "Right away", discard = "When you discard", shop_enter = "When you enter the shop", ante_up = "When a new ante starts"}
Cat.NOW_LABEL = {voucher = "When bought", deck = "At the start of the run", stake = "At the start of the run"}

local function lang_of()
  local l = G and G.SETTINGS and G.SETTINGS.language or "en-us"
  if l == "fr" then return "fr" end
  if type(l) == "string" and l:sub(1, 2) == "es" then return "es" end
  return "en"
end
Cat.lang = lang_of

function Cat.when_label(kind_id, w)
  if w == "now" then return mod_loc(Cat.NOW_LABEL[kind_id] or "Right away") end
  if Cat.WHEN_LABEL[w] then return mod_loc(Cat.WHEN_LABEL[w]) end
  local T = require("functions/forge/forge_text")
  return T.when_text(w, lang_of())
end

function Cat.only_line(o)
  local T = require("functions/forge/forge_text")
  if o.id == "every" then return string.format(mod_loc("every {C:attention}%d{} times"), tonumber(o.n) or 2) end
  local p = G and G.GAME and G.GAME.probabilities and G.GAME.probabilities.normal or 1
  return (T.only_text(o, lang_of(), {}):gsub("#1#", tostring(p)))
end

function Cat.effect_line(kind_id, e)
  local spec = Cat.effect(kind_id, e.id)
  if not spec then return "" end
  local body = fill(spec.line, e, spec)
  local only = type(e.only) == "table" and e.only or {}
  if (not e.when or e.when == "now") and #only == 0 then return body end
  local T = require("functions/forge/forge_text")
  local S = T.S[lang_of()] or T.S.en
  local head = e.when and e.when ~= "now" and Cat.when_label(kind_id, e.when) or nil
  local conds, chance = {}, nil
  for _, o in ipairs(only) do
    if o.id == "chance" then chance = Cat.only_line(o) else conds[#conds + 1] = Cat.only_line(o) end
  end
  local cond = #conds > 0 and (S["if"] .. " " .. table.concat(conds, " " .. S["and"] .. " ")) or nil
  if chance then cond = cond and (cond .. ", " .. chance) or chance end
  if head and cond then head = head .. ", " .. cond
  elseif cond then head = cond:sub(1, 1):upper() .. cond:sub(2) end
  return head .. ": " .. body
end

function Cat.effect_label(kind_id, e)
  local spec = Cat.effect(kind_id, e.id)
  if not spec then return "" end
  local parts = {mod_loc(spec.label)}
  if spec.v then parts[#parts + 1] = Cat.value_label(spec.v, e.v) end
  if spec.num then parts[#parts + 1] = Cat.fmt(spec.num, e.n) end
  return table.concat(parts, ": ")
end

local function register()
  if not mod_loc_register then return end
  mod_loc_register{
    fr = {
      ["Joker"] = "Joker", ["Tarot"] = "Tarot", ["Planet"] = "Planète", ["Spectral"] = "Spectral", ["Voucher"] = "Bon", ["Enhancement"] = "Amélioration", ["Seal"] = "Sceau", ["Edition"] = "Édition", ["Tag"] = "Badge", ["Blind"] = "Blinde", ["Stake"] = "Mise", ["Deck"] = "Jeu", ["Booster pack"] = "Paquet", ["Collab"] = "Collab",
      ["Jokers"] = "Jokers", ["Tarots"] = "Tarots", ["Planets"] = "Planètes", ["Spectrals"] = "Spectrales", ["Vouchers"] = "Bons", ["Enhancements"] = "Améliorations", ["Seals"] = "Sceaux", ["Editions"] = "Éditions", ["Tags"] = "Badges", ["Blinds"] = "Blindes", ["Stakes"] = "Mises", ["Decks"] = "Jeux", ["Booster packs"] = "Paquets", ["Collabs"] = "Collabs",
      ["Rarity"] = "Rareté", ["Cost"] = "Prix", ["Blueprint copies it"] = "Copiable par Blueprint", ["Can be Eternal"] = "Peut être Éternel", ["Can be Perishable"] = "Peut être Périssable",
      ["Cards to pick"] = "Cartes à choisir", ["Poker hand"] = "Main de poker", ["Levels"] = "Niveaux", ["Chips per level"] = "Jetons par niveau", ["Mult per level"] = "Multi par niveau", ["Needs first"] = "Demande d'abord",
      ["+Chips when scored"] = "+Jetons si comptée", ["+Mult when scored"] = "+Multi si comptée", ["XMult when scored"] = "XMulti si comptée", ["$ when scored"] = "$ si comptée",
      ["XMult while held"] = "XMulti en main", ["$ held at round end"] = "$ en main en fin de manche", ["Breaks: 1 in"] = "Se brise : 1 sur", ["No rank or suit"] = "Sans valeur ni couleur", ["Always scores"] = "Compte toujours",
      ["Shine"] = "Brillance", ["+Chips"] = "+Jetons", ["+Mult"] = "+Multi", ["XMult"] = "XMulti", ["+1 slot (like Negative)"] = "+1 emplacement (comme Négatif)", ["How often it shows"] = "Fréquence d'apparition",
      ["Works"] = "Agit", ["Size"] = "Taille", ["Reward"] = "Récompense", ["Colour"] = "Couleur", ["From ante"] = "Dès la mise", ["Final boss (ante 8)"] = "Boss final (mise 8)", ["On top of"] = "Par-dessus",
      ["Cards inside"] = "Cartes dedans", ["Cards shown"] = "Cartes montrées", ["Cards to take"] = "Cartes à prendre", ["Suit"] = "Couleur",
      ["Hand size"] = "Taille de main", ["Joker slots"] = "Emplacements de Joker", ["Consumable slots"] = "Emplacements de consommable", ["Hands per round"] = "Mains par manche", ["Discards per round"] = "Défausses par manche",
      ["Interest cap"] = "Plafond d'intérêts", ["Reroll price"] = "Prix de relance", ["Shop discount"] = "Remise en boutique", ["Shop slots"] = "Places en boutique", ["Money now"] = "Argent tout de suite",
      ["{C:attention}%+d{} hand size"] = "{C:attention}%+d{} taille de main", ["{C:attention}%+d{} Joker slot"] = "{C:attention}%+d{} emplacement de Joker", ["{C:attention}%+d{} consumable slot"] = "{C:attention}%+d{} emplacement de consommable",
      ["{C:blue}%+d{} hand each round"] = "{C:blue}%+d{} main par manche", ["{C:red}%+d{} discard each round"] = "{C:red}%+d{} défausse par manche", ["Interest up to {C:money}$%d{} more"] = "Intérêts jusqu'à {C:money}%d $ {}de plus",
      ["Rerolls cost {C:money}$%+d{}"] = "Relances : {C:money}%+d ${}", ["Shop items {C:attention}%d%%{} off"] = "Boutique : {C:attention}-%d%%{}", ["{C:attention}%+d{} card slot in the shop"] = "{C:attention}%+d{} place en boutique", ["Gain {C:money}$%d{}"] = "Gagnez {C:money}%d ${}",
      ["Enhance them"] = "Les améliorer", ["Add a seal"] = "Ajouter un sceau", ["Change their suit"] = "Changer leur couleur", ["Raise their rank"] = "Monter leur valeur", ["Add an edition"] = "Ajouter une édition", ["Destroy them"] = "Les détruire",
      ["Copy the left card onto the right"] = "Copier la carte de gauche sur celle de droite", ["Give money"] = "Donner de l'argent", ["Double money"] = "Doubler l'argent", ["Make cards"] = "Créer des cartes", ["Level up a hand"] = "Monter une main", ["Level up every hand"] = "Monter toutes les mains",
      ["Turns the cards into {C:attention}%s{}"] = "Change les cartes en {C:attention}%s{}", ["Adds a {C:attention}%s{} to the cards"] = "Ajoute un {C:attention}%s{} aux cartes", ["Raises the cards' rank by {C:attention}%d{}"] = "Monte la valeur des cartes de {C:attention}%d{}",
      ["Adds {C:dark_edition}%s{} to the cards"] = "Ajoute {C:dark_edition}%s{} aux cartes", ["Destroys the cards"] = "Détruit les cartes", ["The right card becomes a copy of the left one"] = "La carte de droite devient une copie de celle de gauche",
      ["Gives {C:money}$%d{}"] = "Donne {C:money}%d ${}", ["Doubles your money (max {C:money}$%d{})"] = "Double votre argent (max {C:money}%d ${})", ["Makes {C:attention}%d{} %s card"] = "Crée {C:attention}%d{} carte %s",
      ["Levels up {C:attention}%s{}"] = "Monte {C:attention}%s{} d'un niveau", ["Levels up {C:attention}every{} poker hand"] = "Monte {C:attention}toutes{} les mains de poker",
      ["When scored: give $"] = "Si comptée : donne des $", ["When scored: score again"] = "Si comptée : compte à nouveau", ["When scored: +Mult"] = "Si comptée : +Multi", ["When scored: +Chips"] = "Si comptée : +Jetons", ["When scored: XMult"] = "Si comptée : XMulti",
      ["Held at round end: make a Planet"] = "En main en fin de manche : crée une Planète", ["Held at round end: give $"] = "En main en fin de manche : donne des $", ["When discarded: make a Tarot"] = "Défaussée : crée un Tarot", ["When discarded: give $"] = "Défaussée : donne des $",
      ["Gives {C:money}$%d{} when scored"] = "Donne {C:money}%d ${} si comptée", ["Retriggers this card {C:attention}%d{} time"] = "Redéclenche cette carte {C:attention}%d{} fois", ["{C:mult}+%d{} Mult when scored"] = "{C:mult}+%d{} Multi si comptée", ["{C:chips}+%d{} Chips when scored"] = "{C:chips}+%d{} Jetons si comptée",
      ["{X:mult,C:white}X%s{} Mult when scored"] = "{X:mult,C:white}X%s{} Multi si comptée", ["Makes the {C:planet}Planet{} of the last hand if held at round end"] = "Crée la {C:planet}Planète{} de la dernière main si en main en fin de manche",
      ["Gives {C:money}$%d{} if held at round end"] = "Donne {C:money}%d ${} si en main en fin de manche", ["Makes a {C:tarot}Tarot{} when discarded"] = "Crée un {C:tarot}Tarot{} si défaussée", ["Gives {C:money}$%d{} when discarded"] = "Donne {C:money}%d ${} si défaussée",
      ["$ per blind skipped"] = "$ par blinde passée", ["Free Joker in the shop"] = "Joker gratuit en boutique", ["Free pack"] = "Paquet gratuit", ["Copy the next tag"] = "Copier le badge suivant", ["Hand size next round"] = "Taille de main à la manche suivante",
      ["Free rerolls"] = "Relances gratuites", ["Shop is free"] = "Boutique gratuite", ["Gives {C:money}$%d{} per blind skipped"] = "Donne {C:money}%d ${} par blinde passée", ["The shop has a free {C:attention}%s{} Joker"] = "La boutique a un Joker {C:attention}%s{} gratuit",
      ["Opens a free {C:attention}%s Pack{}"] = "Ouvre un {C:attention}paquet %s{} gratuit", ["Copies the next {C:attention}Tag{} you get"] = "Copie le prochain {C:attention}badge{} obtenu", ["{C:attention}+%d{} hand size next round"] = "{C:attention}+%d{} taille de main à la manche suivante",
      ["{C:green}%d{} free reroll"] = "{C:green}%d{} relance gratuite", ["Every card in the next shop is {C:money}free{}"] = "Tout est {C:money}gratuit{} dans la prochaine boutique", ["Levels up {C:attention}%s{} %d times"] = "Monte {C:attention}%s{} de %d niveaux",
      ["Debuff a suit"] = "Affaiblir une couleur", ["Debuff face cards"] = "Affaiblir les figures", ["Debuff a poker hand"] = "Affaiblir une main", ["Only one poker hand"] = "Une seule main de poker", ["Must play this many cards"] = "Doit jouer ce nombre de cartes", ["No discards"] = "Pas de défausse",
      ["Smaller hand"] = "Main plus petite", ["First hand drawn face down"] = "Première main face cachée", ["Lose $ per card played"] = "Perdre des $ par carte jouée", ["Only one hand"] = "Une seule main", ["Halve base Chips and Mult"] = "Jetons et Multi de base divisés par deux",
      ["All {C:attention}%s{} are debuffed"] = "Tous les {C:attention}%s{} sont affaiblis", ["All face cards are debuffed"] = "Toutes les figures sont affaiblies", ["{C:attention}%s{} scores nothing"] = "{C:attention}%s{} ne compte pas", ["Only {C:attention}%s{} can score"] = "Seule la main {C:attention}%s{} compte",
      ["Must play {C:attention}%d{} cards"] = "Doit jouer {C:attention}%d{} cartes", ["No discards this round"] = "Pas de défausse cette manche", ["{C:attention}-%d{} hand size"] = "{C:attention}-%d{} taille de main", ["First hand is drawn face down"] = "La première main est tirée face cachée",
      ["Lose {C:money}$%d{} per card played"] = "Perdez {C:money}%d ${} par carte jouée", ["Play only {C:attention}1{} hand"] = "Jouez une seule {C:attention}main{}", ["Base Chips and Mult are halved"] = "Jetons et Multi de base divisés par deux",
      ["Bigger blinds"] = "Blindes plus grandes", ["Fewer discards"] = "Moins de défausses", ["Fewer hands"] = "Moins de mains", ["No interest"] = "Pas d'intérêts", ["Small Blind gives no reward"] = "La petite blinde ne rapporte rien", ["Higher prices"] = "Prix plus hauts",
      ["Eternal Jokers in the shop"] = "Jokers Éternels en boutique", ["Perishable Jokers in the shop"] = "Jokers Périssables en boutique", ["Rental Jokers in the shop"] = "Jokers en location en boutique", ["Win at a later ante"] = "Gagner à une mise plus lointaine",
      ["Blinds are {C:red}%d%%{} bigger"] = "Blindes {C:red}%d%%{} plus grandes", ["{C:red}-%d{} discard"] = "{C:red}-%d{} défausse", ["{C:blue}-%d{} hand"] = "{C:blue}-%d{} main", ["Small Blind gives no reward money"] = "La petite blinde ne rapporte pas d'argent",
      ["Shop prices {C:money}+$%d{}"] = "Prix en boutique {C:money}+%d ${}", ["Shop can have {C:attention}Eternal{} Jokers"] = "Jokers {C:attention}Éternels{} en boutique", ["Shop can have {C:attention}Perishable{} Jokers"] = "Jokers {C:attention}Périssables{} en boutique",
      ["Shop can have {C:attention}Rental{} Jokers"] = "Jokers {C:attention}en location{} en boutique", ["Win at ante {C:attention}%d{}"] = "Victoire à la mise {C:attention}%d{}",
      ["Starting money"] = "Argent de départ", ["Win at ante"] = "Victoire à la mise", ["No face cards"] = "Sans figures", ["Remove a suit"] = "Retirer une couleur", ["Every card enhanced"] = "Toutes les cartes améliorées", ["Start with a voucher"] = "Commencer avec un bon", ["Start with consumables"] = "Commencer avec des consommables",
      ["Start with {C:money}%+d{} dollars"] = "Départ avec {C:money}%+d ${}", ["{C:blue}%+d{} hand every round"] = "{C:blue}%+d{} main à chaque manche", ["{C:red}%+d{} discard every round"] = "{C:red}%+d{} défausse à chaque manche",
      ["Start with no face cards"] = "Départ sans figures", ["Start with no {C:attention}%s{}"] = "Départ sans {C:attention}%s{}", ["Every card is a {C:attention}%s{}"] = "Chaque carte est une {C:attention}%s{}", ["Start with {C:attention}%s{}"] = "Départ avec {C:attention}%s{}",
      ["Start with {C:attention}%d{} %s card"] = "Départ avec {C:attention}%d{} carte %s",
      ["Price: destroy cards in hand"] = "Prix : détruire des cartes en main", ["Price: money set to $0"] = "Prix : argent à 0 $", ["Price: -1 hand size"] = "Prix : -1 taille de main", ["Add cards to the deck"] = "Ajouter des cartes au jeu", ["Edition on a random Joker"] = "Édition sur un Joker au hasard", ["Make a Joker"] = "Créer un Joker",
      ["Destroys {C:attention}%d{} random card in hand"] = "Détruit {C:attention}%d{} carte au hasard en main", ["Sets money to {C:money}$0{}"] = "L'argent passe à {C:money}0 ${}", ["{C:red}-1{} hand size"] = "{C:red}-1{} taille de main",
      ["Adds {C:attention}%d{} enhanced face cards to the deck"] = "Ajoute {C:attention}%d{} figures améliorées au jeu", ["Adds {C:dark_edition}%s{} to a random Joker"] = "Ajoute {C:dark_edition}%s{} à un Joker au hasard", ["Makes a {C:attention}%s{} Joker"] = "Crée un Joker {C:attention}%s{}",
      ["Right away"] = "Tout de suite", ["At the next shop"] = "À la prochaine boutique", ["At the next round"] = "À la prochaine manche", ["Normal"] = "Normal", ["Jumbo"] = "Jumbo", ["Mega"] = "Méga",
      ["Red"] = "Rouge", ["Blue"] = "Bleu", ["Green"] = "Vert", ["Purple"] = "Violet", ["Orange"] = "Orange", ["Gold"] = "Or", ["Black"] = "Noir", ["Nothing"] = "Rien", ["Every hand"] = "Toutes les mains",
      ["Arcana"] = "Arcane", ["Celestial"] = "Céleste", ["Standard"] = "Standard", ["Buffoon"] = "Bouffon", ["Forge creations"] = "Créations de la Forge",
      ["Common"] = "Commun", ["Uncommon"] = "Peu commun", ["Rare"] = "Rare", ["Legendary"] = "Légendaire", ["Foil"] = "Brillante", ["Holographic"] = "Holographique", ["Polychrome"] = "Polychrome", ["Negative"] = "Négatif",
      ["Red Seal"] = "Sceau rouge", ["Blue Seal"] = "Sceau bleu", ["Gold Seal"] = "Sceau d'or", ["Purple Seal"] = "Sceau violet",
    },
    es = {
      ["Joker"] = "Comodín", ["Tarot"] = "Tarot", ["Planet"] = "Planeta", ["Spectral"] = "Espectral", ["Voucher"] = "Cupón", ["Enhancement"] = "Mejora", ["Seal"] = "Sello", ["Edition"] = "Edición", ["Tag"] = "Etiqueta", ["Blind"] = "Ciega", ["Stake"] = "Apuesta", ["Deck"] = "Baraja", ["Booster pack"] = "Sobre", ["Collab"] = "Collab",
      ["Jokers"] = "Jokers", ["Tarots"] = "Tarots", ["Planets"] = "Planetas", ["Spectrals"] = "Espectrales", ["Vouchers"] = "Cupones", ["Enhancements"] = "Mejoras", ["Seals"] = "Sellos", ["Editions"] = "Ediciones", ["Tags"] = "Etiquetas", ["Blinds"] = "Ciegas", ["Stakes"] = "Apuestas", ["Decks"] = "Barajas", ["Booster packs"] = "Sobres", ["Collabs"] = "Collabs",
      ["Rarity"] = "Rareza", ["Cost"] = "Precio", ["Blueprint copies it"] = "Blueprint lo copia", ["Can be Eternal"] = "Puede ser Eterno", ["Can be Perishable"] = "Puede ser Perecedero",
      ["Cards to pick"] = "Cartas a elegir", ["Poker hand"] = "Mano de póker", ["Levels"] = "Niveles", ["Chips per level"] = "Fichas por nivel", ["Mult per level"] = "Multi por nivel", ["Needs first"] = "Necesita antes",
      ["+Chips when scored"] = "+Fichas al puntuar", ["+Mult when scored"] = "+multi al puntuar", ["XMult when scored"] = "Xmulti al puntuar", ["$ when scored"] = "$ al puntuar",
      ["XMult while held"] = "Xmulti en la mano", ["$ held at round end"] = "$ en la mano al final", ["Breaks: 1 in"] = "Se rompe: 1 de", ["No rank or suit"] = "Sin valor ni palo", ["Always scores"] = "Siempre puntúa",
      ["Shine"] = "Brillo", ["+Chips"] = "+Fichas", ["+Mult"] = "+multi", ["XMult"] = "Xmulti", ["+1 slot (like Negative)"] = "+1 espacio (como Negativo)", ["How often it shows"] = "Frecuencia",
      ["Works"] = "Actúa", ["Size"] = "Tamaño", ["Reward"] = "Premio", ["Colour"] = "Color", ["From ante"] = "Desde la apuesta", ["Final boss (ante 8)"] = "Jefe final (apuesta 8)", ["On top of"] = "Encima de",
      ["Cards inside"] = "Cartas dentro", ["Cards shown"] = "Cartas a la vista", ["Cards to take"] = "Cartas a tomar", ["Suit"] = "Palo",
      ["Hand size"] = "Tamaño de mano", ["Joker slots"] = "Espacios de comodín", ["Consumable slots"] = "Espacios de consumible", ["Hands per round"] = "Manos por ronda", ["Discards per round"] = "Descartes por ronda",
      ["Interest cap"] = "Tope de interés", ["Reroll price"] = "Precio de cambio", ["Shop discount"] = "Descuento en tienda", ["Shop slots"] = "Espacios en tienda", ["Money now"] = "Dinero ahora",
      ["{C:attention}%+d{} hand size"] = "{C:attention}%+d{} tamaño de mano", ["{C:attention}%+d{} Joker slot"] = "{C:attention}%+d{} espacio de comodín", ["{C:attention}%+d{} consumable slot"] = "{C:attention}%+d{} espacio de consumible",
      ["{C:blue}%+d{} hand each round"] = "{C:blue}%+d{} mano por ronda", ["{C:red}%+d{} discard each round"] = "{C:red}%+d{} descarte por ronda", ["Interest up to {C:money}$%d{} more"] = "Interés hasta {C:money}$%d{} más",
      ["Rerolls cost {C:money}$%+d{}"] = "Cambios: {C:money}$%+d{}", ["Shop items {C:attention}%d%%{} off"] = "Tienda: {C:attention}-%d%%{}", ["{C:attention}%+d{} card slot in the shop"] = "{C:attention}%+d{} espacio en la tienda", ["Gain {C:money}$%d{}"] = "Gana {C:money}$%d{}",
      ["Enhance them"] = "Mejorarlas", ["Add a seal"] = "Añadir un sello", ["Change their suit"] = "Cambiar su palo", ["Raise their rank"] = "Subir su valor", ["Add an edition"] = "Añadir una edición", ["Destroy them"] = "Destruirlas",
      ["Copy the left card onto the right"] = "Copiar la carta izquierda en la derecha", ["Give money"] = "Dar dinero", ["Double money"] = "Doblar el dinero", ["Make cards"] = "Crear cartas", ["Level up a hand"] = "Subir una mano", ["Level up every hand"] = "Subir todas las manos",
      ["Turns the cards into {C:attention}%s{}"] = "Convierte las cartas en {C:attention}%s{}", ["Adds a {C:attention}%s{} to the cards"] = "Añade un {C:attention}%s{} a las cartas", ["Raises the cards' rank by {C:attention}%d{}"] = "Sube el valor de las cartas en {C:attention}%d{}",
      ["Adds {C:dark_edition}%s{} to the cards"] = "Añade {C:dark_edition}%s{} a las cartas", ["Destroys the cards"] = "Destruye las cartas", ["The right card becomes a copy of the left one"] = "La carta derecha pasa a ser copia de la izquierda",
      ["Gives {C:money}$%d{}"] = "Da {C:money}$%d{}", ["Doubles your money (max {C:money}$%d{})"] = "Dobla tu dinero (máx. {C:money}$%d{})", ["Makes {C:attention}%d{} %s card"] = "Crea {C:attention}%d{} carta %s",
      ["Levels up {C:attention}%s{}"] = "Sube {C:attention}%s{} un nivel", ["Levels up {C:attention}every{} poker hand"] = "Sube {C:attention}todas{} las manos de póker",
      ["When scored: give $"] = "Al puntuar: da $", ["When scored: score again"] = "Al puntuar: puntúa otra vez", ["When scored: +Mult"] = "Al puntuar: +multi", ["When scored: +Chips"] = "Al puntuar: +Fichas", ["When scored: XMult"] = "Al puntuar: Xmulti",
      ["Held at round end: make a Planet"] = "En la mano al final: crea un Planeta", ["Held at round end: give $"] = "En la mano al final: da $", ["When discarded: make a Tarot"] = "Al descartar: crea un Tarot", ["When discarded: give $"] = "Al descartar: da $",
      ["Gives {C:money}$%d{} when scored"] = "Da {C:money}$%d{} al puntuar", ["Retriggers this card {C:attention}%d{} time"] = "Reactiva esta carta {C:attention}%d{} vez", ["{C:mult}+%d{} Mult when scored"] = "{C:mult}+%d{} multi al puntuar", ["{C:chips}+%d{} Chips when scored"] = "{C:chips}+%d{} Fichas al puntuar",
      ["{X:mult,C:white}X%s{} Mult when scored"] = "{X:mult,C:white}X%s{} multi al puntuar", ["Makes the {C:planet}Planet{} of the last hand if held at round end"] = "Crea el {C:planet}Planeta{} de la última mano si sigue en la mano al final",
      ["Gives {C:money}$%d{} if held at round end"] = "Da {C:money}$%d{} si sigue en la mano al final", ["Makes a {C:tarot}Tarot{} when discarded"] = "Crea un {C:tarot}Tarot{} al descartarla", ["Gives {C:money}$%d{} when discarded"] = "Da {C:money}$%d{} al descartarla",
      ["$ per blind skipped"] = "$ por ciega saltada", ["Free Joker in the shop"] = "Comodín gratis en la tienda", ["Free pack"] = "Sobre gratis", ["Copy the next tag"] = "Copiar la siguiente etiqueta", ["Hand size next round"] = "Tamaño de mano la próxima ronda",
      ["Free rerolls"] = "Cambios gratis", ["Shop is free"] = "Tienda gratis", ["Gives {C:money}$%d{} per blind skipped"] = "Da {C:money}$%d{} por ciega saltada", ["The shop has a free {C:attention}%s{} Joker"] = "La tienda tiene un comodín {C:attention}%s{} gratis",
      ["Opens a free {C:attention}%s Pack{}"] = "Abre un {C:attention}sobre %s{} gratis", ["Copies the next {C:attention}Tag{} you get"] = "Copia la próxima {C:attention}etiqueta{}", ["{C:attention}+%d{} hand size next round"] = "{C:attention}+%d{} tamaño de mano la próxima ronda",
      ["{C:green}%d{} free reroll"] = "{C:green}%d{} cambio gratis", ["Every card in the next shop is {C:money}free{}"] = "Todo es {C:money}gratis{} en la próxima tienda", ["Levels up {C:attention}%s{} %d times"] = "Sube {C:attention}%s{} %d niveles",
      ["Debuff a suit"] = "Debilitar un palo", ["Debuff face cards"] = "Debilitar las figuras", ["Debuff a poker hand"] = "Debilitar una mano", ["Only one poker hand"] = "Una sola mano de póker", ["Must play this many cards"] = "Jugar este número de cartas", ["No discards"] = "Sin descartes",
      ["Smaller hand"] = "Mano más pequeña", ["First hand drawn face down"] = "Primera mano boca abajo", ["Lose $ per card played"] = "Perder $ por carta jugada", ["Only one hand"] = "Una sola mano", ["Halve base Chips and Mult"] = "Fichas y multi base a la mitad",
      ["All {C:attention}%s{} are debuffed"] = "Todas las {C:attention}%s{} están debilitadas", ["All face cards are debuffed"] = "Todas las figuras están debilitadas", ["{C:attention}%s{} scores nothing"] = "{C:attention}%s{} no puntúa", ["Only {C:attention}%s{} can score"] = "Solo puntúa {C:attention}%s{}",
      ["Must play {C:attention}%d{} cards"] = "Hay que jugar {C:attention}%d{} cartas", ["No discards this round"] = "Sin descartes esta ronda", ["{C:attention}-%d{} hand size"] = "{C:attention}-%d{} tamaño de mano", ["First hand is drawn face down"] = "La primera mano sale boca abajo",
      ["Lose {C:money}$%d{} per card played"] = "Pierdes {C:money}$%d{} por carta jugada", ["Play only {C:attention}1{} hand"] = "Juega solo {C:attention}1{} mano", ["Base Chips and Mult are halved"] = "Fichas y multi base a la mitad",
      ["Bigger blinds"] = "Ciegas más grandes", ["Fewer discards"] = "Menos descartes", ["Fewer hands"] = "Menos manos", ["No interest"] = "Sin interés", ["Small Blind gives no reward"] = "La ciega pequeña no da premio", ["Higher prices"] = "Precios más altos",
      ["Eternal Jokers in the shop"] = "Comodines Eternos en la tienda", ["Perishable Jokers in the shop"] = "Comodines Perecederos en la tienda", ["Rental Jokers in the shop"] = "Comodines de alquiler en la tienda", ["Win at a later ante"] = "Ganar en una apuesta más lejana",
      ["Blinds are {C:red}%d%%{} bigger"] = "Ciegas un {C:red}%d%%{} más grandes", ["{C:red}-%d{} discard"] = "{C:red}-%d{} descarte", ["{C:blue}-%d{} hand"] = "{C:blue}-%d{} mano", ["Small Blind gives no reward money"] = "La ciega pequeña no da dinero",
      ["Shop prices {C:money}+$%d{}"] = "Precios de la tienda {C:money}+$%d{}", ["Shop can have {C:attention}Eternal{} Jokers"] = "Comodines {C:attention}Eternos{} en la tienda", ["Shop can have {C:attention}Perishable{} Jokers"] = "Comodines {C:attention}Perecederos{} en la tienda",
      ["Shop can have {C:attention}Rental{} Jokers"] = "Comodines {C:attention}de alquiler{} en la tienda", ["Win at ante {C:attention}%d{}"] = "Ganas en la apuesta {C:attention}%d{}",
      ["Starting money"] = "Dinero inicial", ["Win at ante"] = "Ganar en la apuesta", ["No face cards"] = "Sin figuras", ["Remove a suit"] = "Quitar un palo", ["Every card enhanced"] = "Todas las cartas mejoradas", ["Start with a voucher"] = "Empezar con un cupón", ["Start with consumables"] = "Empezar con consumibles",
      ["Start with {C:money}%+d{} dollars"] = "Empiezas con {C:money}%+d{} dólares", ["{C:blue}%+d{} hand every round"] = "{C:blue}%+d{} mano cada ronda", ["{C:red}%+d{} discard every round"] = "{C:red}%+d{} descarte cada ronda",
      ["Start with no face cards"] = "Empiezas sin figuras", ["Start with no {C:attention}%s{}"] = "Empiezas sin {C:attention}%s{}", ["Every card is a {C:attention}%s{}"] = "Cada carta es una {C:attention}%s{}", ["Start with {C:attention}%s{}"] = "Empiezas con {C:attention}%s{}",
      ["Start with {C:attention}%d{} %s card"] = "Empiezas con {C:attention}%d{} carta %s",
      ["Price: destroy cards in hand"] = "Precio: destruir cartas de la mano", ["Price: money set to $0"] = "Precio: dinero a $0", ["Price: -1 hand size"] = "Precio: -1 tamaño de mano", ["Add cards to the deck"] = "Añadir cartas a la baraja", ["Edition on a random Joker"] = "Edición en un comodín al azar", ["Make a Joker"] = "Crear un comodín",
      ["Destroys {C:attention}%d{} random card in hand"] = "Destruye {C:attention}%d{} carta al azar de la mano", ["Sets money to {C:money}$0{}"] = "El dinero pasa a {C:money}$0{}", ["{C:red}-1{} hand size"] = "{C:red}-1{} tamaño de mano",
      ["Adds {C:attention}%d{} enhanced face cards to the deck"] = "Añade {C:attention}%d{} figuras mejoradas a la baraja", ["Adds {C:dark_edition}%s{} to a random Joker"] = "Añade {C:dark_edition}%s{} a un comodín al azar", ["Makes a {C:attention}%s{} Joker"] = "Crea un comodín {C:attention}%s{}",
      ["Right away"] = "Al momento", ["At the next shop"] = "En la próxima tienda", ["At the next round"] = "En la próxima ronda", ["Normal"] = "Normal", ["Jumbo"] = "Jumbo", ["Mega"] = "Mega",
      ["Red"] = "Rojo", ["Blue"] = "Azul", ["Green"] = "Verde", ["Purple"] = "Morado", ["Orange"] = "Naranja", ["Gold"] = "Oro", ["Black"] = "Negro", ["Nothing"] = "Nada", ["Every hand"] = "Todas las manos",
      ["Arcana"] = "Arcano", ["Celestial"] = "Celestial", ["Standard"] = "Estándar", ["Buffoon"] = "Bufón", ["Forge creations"] = "Creaciones de la Forja",
      ["Common"] = "Común", ["Uncommon"] = "Poco común", ["Rare"] = "Raro", ["Legendary"] = "Legendario", ["Foil"] = "Laminada", ["Holographic"] = "Holográfica", ["Polychrome"] = "Polícroma", ["Negative"] = "Negativa",
      ["Red Seal"] = "Sello rojo", ["Blue Seal"] = "Sello azul", ["Gold Seal"] = "Sello de oro", ["Purple Seal"] = "Sello morado",
    },
  }
end

register()

return Cat
