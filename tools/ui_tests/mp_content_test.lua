local root = (arg and arg[0] and arg[0]:match("^(.*)/tools/ui_tests/") or ".") .. "/assets/"

local function center(t) t.config = t.config or {} return t end
G = {
    SETTINGS = { language = 'en-us' },
    C = { RED = {}, BLUE = {}, MULT = {}, MONEY = {}, FILTER = {}, PURPLE = {}, DARK_EDITION = {}, SECONDARY_SET = { Spectral = {}, Planet = {} }, UI = { BACKGROUND_INACTIVE = {} } },
    FUNCS = { toggle_shop = function() end, can_sell_card = function() end },
    handlist = { 'Flush Five', 'Flush House', 'Five of a Kind', 'Straight Flush', 'Four of a Kind', 'Full House', 'Flush', 'Straight', 'Three of a Kind', 'Two Pair', 'Pair', 'High Card' },
    P_CENTERS = {
        j_hanging_chad = center({ key = 'j_hanging_chad', order = 115, name = 'Hanging Chad', set = 'Joker', rarity = 1, cost = 4, config = { extra = 2 } }),
        j_ticket = center({ key = 'j_ticket', order = 106, name = 'Golden Ticket', set = 'Joker', rarity = 1, cost = 5, config = { extra = 4 }, enhancement_gate = 'm_gold' }),
        j_idol = center({ key = 'j_idol', order = 127, name = 'The Idol', set = 'Joker', rarity = 2, cost = 6, config = { extra = 2 } }),
        j_baron = center({ key = 'j_baron', order = 72, name = 'Baron', set = 'Joker', rarity = 3, cost = 8, config = { extra = 1.5 } }),
        j_mime = center({ key = 'j_mime', order = 19, name = 'Mime', set = 'Joker', rarity = 2, cost = 5, config = { extra = 1 } }),
        j_selzer = center({ key = 'j_selzer', order = 102, name = 'Seltzer', set = 'Joker', rarity = 2, cost = 6, config = { extra = 10 } }),
        j_turtle_bean = center({ key = 'j_turtle_bean', order = 80, name = 'Turtle Bean', set = 'Joker', rarity = 2, cost = 6, config = { extra = { h_size = 5, h_mod = 1 } } }),
        j_todo_list = center({ key = 'j_todo_list', order = 60, name = 'To Do List', set = 'Joker', rarity = 1, cost = 4, config = { extra = { dollars = 4, poker_hand = 'High Card' } } }),
        j_bloodstone = center({ key = 'j_bloodstone', order = 117, name = 'Bloodstone', set = 'Joker', rarity = 2, cost = 7, config = { extra = { odds = 2, Xmult = 1.5 } } }),
        j_joker = center({ key = 'j_joker', order = 1, name = 'Joker', set = 'Joker', rarity = 1, cost = 2, config = { mult = 4 } }),
        m_glass = center({ key = 'm_glass', name = 'Glass Card', set = 'Enhanced', config = { Xmult = 2, extra = 4 } }),
        c_magician = center({ key = 'c_magician', name = 'The Magician', set = 'Tarot', config = { mod_conv = 'm_lucky', max_highlighted = 2 } }),
        c_ouija = center({ key = 'c_ouija', name = 'Ouija', set = 'Spectral' }),
        c_wraith = center({ key = 'c_wraith', name = 'Wraith', set = 'Spectral' }),
        b_red = center({ key = 'b_red', name = 'Red Deck', set = 'Back' }),
    },
    P_TAGS = {
        tag_uncommon = center({ key = 'tag_uncommon', name = 'Uncommon Tag', config = { type = 'store_joker_create' } }),
        tag_rare = center({ key = 'tag_rare', name = 'Rare Tag', config = { type = 'store_joker_create' } }),
        tag_foil = center({ key = 'tag_foil', config = { type = 'store_joker_modify' } }),
        tag_holo = center({ key = 'tag_holo', config = { type = 'store_joker_modify' } }),
        tag_polychrome = center({ key = 'tag_polychrome', config = { type = 'store_joker_modify' } }),
        tag_negative = center({ key = 'tag_negative', config = { type = 'store_joker_modify' } }),
        tag_investment = center({ key = 'tag_investment', config = { type = 'eval', dollars = 25 } }),
    },
    P_SEALS = { Blue = { order = 3, set = 'Seal' } },
    localization = { descriptions = {
        Joker = { j_hanging_chad = { name = 'Hanging Chad', text = { 'vanilla chad' } } },
        Tarot = { c_magician = { name = 'The Magician', text = { 'vanilla magician' } } },
        Spectral = { c_ouija = { name = 'Ouija', text = { 'vanilla ouija' } }, c_wraith = { name = 'Wraith', text = { 'vanilla wraith' } } },
        Tag = { tag_uncommon = { name = 'Uncommon Tag', text = { 'free' } } },
        Other = { blue_seal = { name = 'Blue Seal', text = { 'vanilla blue' } } },
        Enhanced = {}, Back = {}, Stake = {}, Edition = {},
    } },
}
G.P_JOKER_RARITY_POOLS = { {}, {}, {}, {} }
G.P_CENTER_POOLS = { Joker = {} }
for _, c in pairs(G.P_CENTERS) do
    c.key = c.key
    if c.set == 'Joker' then
        table.insert(G.P_JOKER_RARITY_POOLS[c.rarity], c)
        table.insert(G.P_CENTER_POOLS.Joker, c)
    end
end
for _, p in pairs(G.P_JOKER_RARITY_POOLS) do table.sort(p, function(a, b) return a.order < b.order end) end
table.sort(G.P_CENTER_POOLS.Joker, function(a, b) return a.order < b.order end)
local vanilla_joker_pool = #G.P_CENTER_POOLS.Joker

mp_log = { info = function() end, warn = function() end }
mod_loc = function(s) return s end
mod_loc_register = function() end
loc_parse_string = function(s) return { s } end
localize = function(a) if type(a) == 'table' then return 'loc' end return a end
pseudorandom = function() return 0.1 end
pseudoseed = function(s) return s end
pseudorandom_element = function(t) return t[1] end
generate_card_ui = function(c, full) if full then full.extra = (full.extra or 0) + 1 return full end return { main = { c.key } } end
Event = function(t) return t end
ease_dollars = function() end
get_current_pool = function() return {} end
get_blind_amount = function(ante) return 1000 * ante end

Card = {}
function Card.load(self, t) self.loaded_center = t.save_fields.center; self.ability = t.ability end
function Card.update() end
function Card.calculate_joker(self) if self.config and self.config.center and self.config.center.mp_joker then return nil end return "orig" end
function Card.calculate_dollar_bonus() return nil end
function Card.generate_UIBox_ability_table() return { main = {} } end
function Card.set_cost(self) self.cost = self.base_cost or 10 end
function Card.sell_card() end
function Card.set_ability(self, c) self.ability = { name = c.name } end
function Card.get_end_of_round_effect() return {} end
function Card.use_consumeable() return 'orig_use' end
function Card.can_use_consumeable() return true end
function Card.open() G.GAME.pack_choices = 1 end
Back = { apply_to_run = function() end }
Tag = { apply_to_run = function() return nil end }
Game = {
    start_run = function(self, args)
        G.GAME = args.savetext and args.savetext.GAME or { modifiers = {}, starting_params = { discards = 3 }, round_resets = { ante = 1 } }
        G.GAME.stake = args.stake or 1
        G.last_back = { effect = { center = G.P_CENTERS[args.back or 'b_red'] } }
        Back.apply_to_run(G.last_back)
    end,
    main_menu = function() end,
    set_language = function() end,
}

local settings = { multiplayer_jokers = true }
bom_match = { get_state = function() return { settings = settings } end, get_settings = function() return settings end }
bom_party = { active = function() return false end }
local pvp = false
bom_nemesis = { is_pvp_boss = function() return pvp end }
bom_events = { handlers = {}, register = function(t, fn) bom_events.handlers[t] = fn end }

local fails = 0
local function check(name, cond, detail) if not cond then fails = fails + 1 print("FAIL " .. name .. " " .. tostring(detail)) else print("ok   " .. name) end end
local function in_pool(pool, key) for _, c in ipairs(pool) do if c.key == key then return true end end return false end

G.GAME = { modifiers = {}, pool_flags = {}, round_resets = { ante = 1 } }
local O = dofile(root .. "multiplayer/bom_custom_objects.lua")
bom_custom_objects = O
O.init()
local R = dofile(root .. "multiplayer/bom_reworks.lua")
bom_reworks = R
R.init()
local D = dofile(root .. "multiplayer/bom_decks.lua")
bom_decks = D
D.init()
local S = dofile(root .. "multiplayer/bom_stakes.lua")
bom_stakes = S
S.init()

check("10 MP jokers", #O.list() == 10, #O.list())
check("jokers omitted from SP", G.P_CENTERS.j_mp_truce.omit == true)
check("old keys alias", G.P_CENTERS.j_mp_pacifist == G.P_CENTERS.j_mp_truce and G.P_CENTERS.j_mp_heckler.key == 'j_mp_envy')
check("remap", O.remap('j_mp_lightning_rod') == 'j_mp_bulwark' and O.remap('j_joker') == 'j_joker')
check("SP pools untouched", #G.P_CENTER_POOLS.Joker == vanilla_joker_pool and not in_pool(G.P_JOKER_RARITY_POOLS[1], 'j_mp_truce'))
check("loc injected", G.localization.descriptions.Joker.j_mp_truce.name == 'Truce')

G.GAME.multiplayer = true
O.update(0)
check("MP pools on", in_pool(G.P_JOKER_RARITY_POOLS[1], 'j_mp_truce') and in_pool(G.P_JOKER_RARITY_POOLS[2], 'j_mp_grudge') and G.GAME.pool_flags.mp_duel_jokers == true)
local last = G.P_JOKER_RARITY_POOLS[1][#G.P_JOKER_RARITY_POOLS[1]]
check("pool sorted by order", last.order >= 1101, last.key)
G.GAME.multiplayer = nil
O.update(0)
check("MP pools off again", not in_pool(G.P_JOKER_RARITY_POOLS[1], 'j_mp_truce') and #G.P_CENTER_POOLS.Joker == vanilla_joker_pool and G.GAME.pool_flags.mp_custom_objects == nil)

local c = setmetatable({}, { __index = Card })
Card.load(c, { save_fields = { center = 'j_mp_pacifist' }, ability = { name = 'Pacifist', extra = { x_mult = 10 }, eternal = true } })
check("old save remapped", c.loaded_center == 'j_mp_truce' and c.ability.name == 'Truce' and c.ability.extra.x_mult == 8 and c.ability.eternal == true)

G.GAME.multiplayer = true
local truce = setmetatable({ config = { center = G.P_CENTERS.j_mp_truce }, ability = { name = 'Truce', extra = { x_mult = 8, mult = 8 } } }, { __index = Card })
G.jokers = { cards = {} }
local r1 = Card.calculate_joker(truce, { cardarea = G.jokers, joker_main = true })
pvp = true
local r2 = Card.calculate_joker(truce, { cardarea = G.jokers, joker_main = true })
pvp = false
check("truce outside PvP", r1 and r1.Xmult_mod == 8)
check("truce in PvP", r2 and r2.mult_mod == 8 and not r2.Xmult_mod)
check("vanilla joker untouched", Card.calculate_joker(setmetatable({ config = { center = G.P_CENTERS.j_joker }, ability = { name = 'Joker' } }, { __index = Card }), {}) == 'orig')

local consumed = bom_events.handlers.sabotage({ sabotage_id = 'mpj_stats', skips = 2, sells_total = 3, dollars = 41 })
check("stats consumed", consumed == true and G.GAME.mp_opp_stats.dollars == 41 and G.GAME.mp_opp_stats.skips == 2)
check("other sabotage passes", bom_events.handlers.sabotage({ sabotage_id = 'sab_fog' }) == nil)
local envy = setmetatable({ config = { center = G.P_CENTERS.j_mp_envy }, ability = { name = 'Envy', extra = { per = 8, max = 5 } } }, { __index = Card })
check("envy pays", Card.calculate_dollar_bonus(envy) == 5, Card.calculate_dollar_bonus(envy))
local tariff = setmetatable({ config = { center = G.P_CENTERS.j_mp_tariff }, ability = { name = 'Tariff', extra = { gain = 3, self_gain = 1, mult = 0 } } }, { __index = Card })
Card.calculate_joker(tariff, { cardarea = G.jokers, setting_blind = true, blind = { key = 'bl_mp_nemesis' } })
Card.calculate_joker(tariff, { cardarea = G.jokers, setting_blind = true, blind = { key = 'bl_mp_nemesis' } })
check("tariff collects once", tariff.ability.extra.mult == 9, tariff.ability.extra.mult)
G.GAME.skips = 0
G.GAME.mp_lives, G.GAME.mp_opponent_lives = 2, 4
local bulwark = setmetatable({ config = { center = G.P_CENTERS.j_mp_bulwark }, ability = { name = 'Bulwark', extra = { chips = 100, high = 60 } } }, { __index = Card })
pvp = true
local rb = Card.calculate_joker(bulwark, { cardarea = G.jokers, joker_main = true })
pvp = false
check("bulwark doubled in PvP", rb and rb.chip_mod == 400, rb and rb.chip_mod)
check("rework list", #R.available() == 21, #R.available())
R.apply({ 'j_hanging_chad', 'j_ticket', 'c_magician', 'Blue', 'tag_investment', 'nope' })
check("chad config", G.P_CENTERS.j_hanging_chad.config.extra == 1)
check("ticket moved", G.P_CENTERS.j_ticket.rarity == 2 and in_pool(G.P_JOKER_RARITY_POOLS[2], 'j_ticket') and not in_pool(G.P_JOKER_RARITY_POOLS[1], 'j_ticket') and G.P_CENTERS.j_ticket.enhancement_gate == nil)
check("investment", G.P_TAGS.tag_investment.config.dollars == 15)
check("magician text swapped", G.localization.descriptions.Tarot.c_magician.text[2] == 'card into a' and G.localization.descriptions.Tarot.c_magician.name == 'The Magician')
check("blue seal text swapped", G.localization.descriptions.Other.blue_seal.text[1]:find('random') ~= nil)
check("game list", G.GAME.mp_reworks and #G.GAME.mp_reworks == 5, G.GAME.mp_reworks and #G.GAME.mp_reworks)
local chad = setmetatable({ config = { center = G.P_CENTERS.j_hanging_chad }, ability = { name = 'Hanging Chad', extra = 1 } }, { __index = Card })
G.play = {}
local a, b = {}, {}
local rr = Card.calculate_joker(chad, { repetition = true, cardarea = G.play, other_card = b, scoring_hand = { a, b } })
check("chad second card", rr and rr.repetitions == 1)
local info = R.info('c_magician')
check("info", info and info.name == 'The Magician' and #info.note == 2 and info.text[1]:find('Enhances') ~= nil)
local ui = Card.generate_UIBox_ability_table(chad)
check("rework note in tooltip", ui.extra == 1)
local magician_ref = G.localization.descriptions.Tarot.c_magician
R.clear()
R.clear()
check("chad restored", G.P_CENTERS.j_hanging_chad.config.extra == 2)
check("ticket restored", G.P_CENTERS.j_ticket.rarity == 1 and in_pool(G.P_JOKER_RARITY_POOLS[1], 'j_ticket') and not in_pool(G.P_JOKER_RARITY_POOLS[2], 'j_ticket') and G.P_CENTERS.j_ticket.enhancement_gate == 'm_gold')
check("texts restored", G.localization.descriptions.Tarot.c_magician.text[1] == 'vanilla magician' and G.localization.descriptions.Other.blue_seal.text[1] == 'vanilla blue' and magician_ref ~= G.localization.descriptions.Tarot.c_magician)
check("investment restored", G.P_TAGS.tag_investment.config.dollars == 25)
check("nothing active", #R.active() == 0)

Game.start_run(G, { savetext = { GAME = { mp_reworks = { 'm_glass' }, modifiers = {}, starting_params = { discards = 3 }, round_resets = { ante = 1 } } }, mp_start = true })
check("rejoin restores reworks", R.is_active('m_glass') and G.P_CENTERS.m_glass.config.Xmult == 1.5)
Game.start_run(G, {})
check("SP run clears reworks", not R.is_active('m_glass') and G.P_CENTERS.m_glass.config.Xmult == 2)
R.apply(R.PRESETS.balanced.reworks)
Game.main_menu(G)
check("main menu clears", #R.active() == 0)

settings.mp_stake = 'stake_mp_spectral'
local args = { mp_start = true, stake = 1 }
Game.start_run(G, args)
check("MP stake base", args.stake == 8 and G.GAME.stake == 8)
check("MP stake overlay", G.GAME.mp_stake == 'stake_mp_spectral' and G.GAME.starting_params.discards == 4 and G.GAME.modifiers.scaling == 4 and G.GAME.modifiers.enable_rentals_in_shop == true)
check("scaling 4 blind table", get_blind_amount(2) == 1100 and get_blind_amount(1) == 300, get_blind_amount(2))
settings.mp_stake = nil
Game.start_run(G, { mp_start = true, stake = 3 })
check("no MP stake", G.GAME.mp_stake == nil and G.GAME.stake == 3 and get_blind_amount(2) == 2000)
check("stake options", #S.options() == 4 and S.options()[1].value == '' and S.name('stake_mp_planet') == 'Nova Stake')

check("deck options", #D.options() == 6 and D.options()[1].value == 'Lilac Deck')
Game.start_run(G, { back = 'b_mp_lilac' })
check("deck modifier", G.GAME.modifiers.mp_lilac == true and G.GAME.mp_deck == 'b_mp_lilac')
local v = setmetatable({ ability = { set = 'Voucher' }, base_cost = 10 }, { __index = Card })
Card.set_cost(v)
check("lilac ante 1 voucher", v.cost == 5, v.cost)
G.GAME.round_resets.ante = 4
Card.set_cost(v)
check("lilac ante 4 full price", v.cost == 10, v.cost)
G.GAME.round_resets.ante = 2
Card.set_cost(v)
check("lilac ante 2 voucher", v.cost == 7, v.cost)
G.GAME.round_resets.ante = 3
Card.set_cost(v)
check("lilac ante 3 voucher", v.cost == 9, v.cost)

for _, k in ipairs(D.KEYS) do
    local d = D.DEFS[k]
    check("deck art " .. k, d.atlas == D.ART_ATLAS and D.ART_ORDER[d.pos.x + 1] == k:gsub('^b_mp_', '') and G.P_CENTERS[k].pos.x == d.pos.x, d.atlas)
    check("deck text " .. k, d.loc.en and d.loc.fr and d.loc.es and #d.loc.fr.text > 0 and #d.loc.es.text > 0)
end

Game.start_run(G, { back = 'b_mp_seer' })
local seer = G.P_CENTERS.b_mp_seer.config
check("seer start items", seer.voucher == 'v_clearance_sale' and seer.consumables[1] == 'c_medium' and G.GAME.modifiers.mp_money_cap == 40)
G.GAME.dollars, G.GAME.interest_cap = 100, 25
D.update()
check("seer money cap", G.GAME.dollars == 65, G.GAME.dollars)
G.GAME.dollars = 30
D.update()
check("seer under the cap", G.GAME.dollars == 30, G.GAME.dollars)

Game.start_run(G, { back = 'b_mp_tangerine' })
local tang = G.P_CENTERS.b_mp_tangerine.config
check("tangerine start items", #tang.consumables == 2 and tang.consumables[2] == 'c_hanged_man' and tang.consumable_slot == 1 and G.GAME.mp_deck == 'b_mp_tangerine')

Game.start_run(G, { back = 'b_mp_cobalt' })
local pack = setmetatable({ ability = { set = 'Booster' }, base_cost = 4 }, { __index = Card })
Card.set_cost(pack)
check("cobalt pack cost", pack.cost == 6, pack.cost)
Card.open(pack)
check("cobalt pack choice", G.GAME.pack_choices == 2, G.GAME.pack_choices)
local vch = setmetatable({ ability = { set = 'Voucher' }, base_cost = 10 }, { __index = Card })
Card.set_cost(vch)
check("cobalt leaves vouchers", vch.cost == 10 and not G.GAME.modifiers.mp_lilac, vch.cost)

Game.start_run(G, { back = 'b_mp_gemini' })
local events, made = {}, {}
G.E_MANAGER = { add_event = function(_, e) events[#events + 1] = e end }
G.CONTROLLER = { locks = {} }
copy_card = function(src) local c = { src = src, set_edition = function(self, e) self.edition = e end, add_to_deck = function() end } made[#made + 1] = c return c end
card_eval_status_text = function() end
G.consumeables = { cards = { { ability = { set = 'Spectral' } }, { ability = { set = 'Tarot' }, key = 'c_fool' } }, emplace = function(self, c) self.cards[#self.cards + 1] = c end }
G.FUNCS.toggle_shop({})
for _, e in ipairs(events) do e.func() end
check("gemini negative copy", #made == 1 and made[1].src.key == 'c_fool' and made[1].edition.negative == true and #G.consumeables.cards == 3, #made)
events, made = {}, {}
G.consumeables.cards = { { ability = { set = 'Spectral' } } }
G.FUNCS.toggle_shop({})
check("gemini needs a tarot or planet", #events == 0 and #made == 0)
Game.start_run(G, { back = 'b_red' })
G.consumeables.cards = { { ability = { set = 'Planet' } } }
G.FUNCS.toggle_shop({})
check("gemini off on other decks", #events == 0)

Game.start_run(G, { back = 'b_mp_random' })
check("random deck modifier", G.GAME.modifiers.mp_random == true and G.GAME.mp_deck == 'b_mp_random')

local looks, cols = {}, {}
for _, k in ipairs(S.KEYS) do
    local d, a = S.DEFS[k], S.ART[k]
    local look = a.src[1] .. ',' .. a.src[2]
    check("stake look unique " .. k, not looks[look] and not cols[d.colour] and S.colour(k) ~= nil, look)
    looks[look], cols[d.colour] = true, true
    check("stake art cell " .. k, S.list()[d.order].atlas == S.ART_ATLAS and S.list()[d.order].pos.x == d.order - 1)
end
check("no stake colour for none", S.colour('') == nil and S.colour(nil) == nil)
local MC = dofile(root .. "multiplayer/mpm_collection.lua")
local FINALS = { [25] = true, [26] = true, [27] = true, [28] = true, [29] = true }
local seen_look = {}
for i, r in ipairs(MC.BLIND_ART.rows) do
    local look = r[1] .. (r[4] or '')
    check("mp blind " .. i .. " uses a final boss chip", FINALS[r[1]] == true, r[1])
    check("mp blind " .. i .. " looks unique", not seen_look[look] and not seen_look[r[2]], look)
    seen_look[look], seen_look[r[2]] = true, true
end
check("rival red heart", MC.BLIND_ART.nemesis[1] == 25 and MC.BLIND_ART.nemesis[2] == MC.BLIND_ART.rows[1][2])

local saved_blinds, saved_anim = G.P_BLINDS, G.ANIMATION_ATLAS
G.P_BLINDS = { bl_big = { pos = { x = 0, y = 1 } }, bl_tooth = { pos = { x = 0, y = 2 } } }
G.ANIMATION_ATLAS = { mp_nemesis_chip = {}, blind_chips = {} }
local okn, NM = pcall(dofile, root .. "multiplayer/bom_nemesis.lua")
NM = okn and (NM or bom_nemesis) or nil
if NM and NM.ensure_registered then
    pcall(NM.ensure_registered)
    local nb = G.P_BLINDS.bl_mp_nemesis
    check("rival blind uses its heart chip", nb and nb.atlas == 'mp_nemesis_chip' and nb.pos.x == 0 and nb.pos.y == 0, nb and nb.atlas)
    check("pvp blind shows the rival, not a regular boss", NM.get_nemesis_key() == 'bl_mp_nemesis', NM.get_nemesis_key())
else
    check("bom_nemesis loads", false, NM)
end
G.P_BLINDS, G.ANIMATION_ATLAS = saved_blinds, saved_anim

G.SETTINGS.language = 'fr'
Game.set_language(G)
check("french after language change", G.localization.descriptions.Joker.j_mp_truce.name == 'Trêve' and G.localization.descriptions.Back.b_mp_cobalt.name == 'Jeu cobalt')

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
