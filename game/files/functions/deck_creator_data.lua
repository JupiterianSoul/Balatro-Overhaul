DeckCreatorData = {}

local CustomDeck = {name = "", slug = "", config = {}, spritePos = {x=0,y=0}, loc_txt = {}, unlocked = true, discovered = true}
DeckCreatorData.CustomDeck = CustomDeck

DeckCreatorData.VERSION = 2

DeckCreatorData.ENHANCEMENTS = {"Random", "Bonus", "Mult", "Wild", "Glass", "Steel", "Stone", "Gold", "Lucky"}
DeckCreatorData.EDITIONS = {"Random", "Foil", "Holographic", "Polychrome", "Negative"}
DeckCreatorData.SEALS = {"Random", "Gold", "Red", "Blue", "Purple"}
DeckCreatorData.BACKS = {"b_red", "b_blue", "b_yellow", "b_green", "b_black", "b_magic", "b_nebula", "b_ghost",
    "b_abandoned", "b_checkered", "b_zodiac", "b_painted", "b_anaglyph", "b_plasma", "b_erratic", "b_challenge"}

local function pct(v) return tostring(v) .. "%" end
local function money(v) return "$" .. tostring(v) end
local function times(v) return "x" .. tostring(v) end
local function off_or(f) return function(v) if v == 0 then return mod_loc("Off") end return f(v) end end
local function one_in(v) if v == 0 then return mod_loc("Off") end return "1/" .. tostring(v) end

DeckCreatorData.FMT = {pct = pct, money = money, times = times, one_in = one_in, off_pct = off_or(pct), off_money = off_or(money)}

DeckCreatorData.SCHEMA = {
    {tab = "rules", header = "Start"},
    {key = "hands", tab = "rules", default = 4, min = 1, max = 12, label = "Hands", info = "Hands you can play each round"},
    {key = "discards", tab = "rules", default = 3, min = 0, max = 12, label = "Discards", info = "Discards each round"},
    {key = "hand_size", tab = "rules", default = 8, min = 3, max = 15, label = "Hand size", info = "Cards held in hand"},
    {key = "dollars", tab = "rules", default = 4, min = 0, max = 200, big = 10, fmt = "money", label = "Starting money"},
    {key = "joker_slot", tab = "rules", default = 5, min = 0, max = 12, label = "Joker slots"},
    {key = "consumable_slot", tab = "rules", default = 2, min = 0, max = 8, label = "Consumable slots"},
    {tab = "rules", header = "Run"},
    {key = "win_ante", tab = "rules", default = 8, min = 2, max = 20, label = "Winning ante", info = "Beat this ante's boss to win"},
    {key = "blind_size", tab = "rules", default = 100, min = 25, max = 400, step = 25, big = 100, fmt = "pct", label = "Blind size", info = "Score needed, % of normal"},
    {key = "hand_level", tab = "rules", default = 1, min = 1, max = 10, label = "Starting hand level", info = "Every poker hand starts at this level"},
    {key = "probability", tab = "rules", default = 1, min = 1, max = 4, fmt = "times", label = "Luck", info = "Multiplies listed chances, like Oops! All 6s"},

    {tab = "money", header = "Interest"},
    {key = "interest_amount", tab = "money", default = 1, min = 0, max = 5, fmt = "money", label = "Interest per $5"},
    {key = "interest_max", tab = "money", default = 5, min = 0, max = 50, big = 5, fmt = "money", label = "Interest cap", info = "Most interest paid per round"},
    {key = "no_interest", tab = "money", default = false, label = "No interest"},
    {tab = "money", header = "Rewards"},
    {key = "money_per_hand", tab = "money", default = 1, min = 0, max = 5, fmt = "money", label = "Per hand left", info = "Paid at the end of each round"},
    {key = "money_per_discard", tab = "money", default = 0, min = 0, max = 5, fmt = "money", label = "Per discard left", info = "Paid at the end of each round"},
    {key = "enhanced_dollars_per_round", tab = "money", default = 0, min = 0, max = 3, fmt = "money", label = "Per enhanced card", info = "Each round, for every enhanced card in the deck"},
    {key = "skip_dollars", tab = "money", default = 0, min = 0, max = 25, step = 5, fmt = "money", label = "Skip bonus", info = "Money each time you skip a blind"},
    {key = "frugal_dollars", tab = "money", default = 0, min = 0, max = 20, step = 5, fmt = "money", label = "Frugal bonus", info = "Leave a shop without buying anything"},
    {tab = "money", header = "Costs"},
    {key = "reroll_cost", tab = "money", default = 5, min = 0, max = 20, fmt = "money", label = "Reroll cost", info = "Starting price of a shop reroll"},
    {key = "discount_percent", tab = "money", default = 0, min = 0, max = 90, step = 10, fmt = "pct", label = "Shop discount"},
    {key = "inflation", tab = "money", default = false, label = "Inflation", info = "Prices rise by $1 after each purchase"},
    {key = "discard_cost", tab = "money", default = 0, min = 0, max = 5, fmt = "off_money", label = "Discard fee", info = "Every discard costs money"},
    {key = "negative_joker_money", tab = "money", default = 0, min = 0, max = 5, fmt = "off_money", label = "Negative upkeep", info = "Each Negative Joker costs this per round"},

    {tab = "shop", header = "Shop"},
    {key = "shop_slots", tab = "shop", default = 2, min = 1, max = 6, label = "Shop card slots"},
    {key = "joker_rate", tab = "shop", default = 20, min = 0, max = 40, big = 5, label = "Joker weight", info = "How often shop cards are Jokers"},
    {key = "tarot_rate", tab = "shop", default = 4, min = 0, max = 20, label = "Tarot weight"},
    {key = "planet_rate", tab = "shop", default = 4, min = 0, max = 20, label = "Planet weight"},
    {key = "spectral_rate", tab = "shop", default = 0, min = 0, max = 10, label = "Spectral weight"},
    {key = "playing_card_rate", tab = "shop", default = 0, min = 0, max = 10, label = "Playing card weight"},
    {key = "edition_rate", tab = "shop", default = 1, min = 1, max = 10, fmt = "times", label = "Edition chance", info = "Foil, Holo, Polychrome and Negative odds"},
    {key = "booster_ante_scaling", tab = "shop", default = false, label = "Pack prices scale", info = "Packs cost $1 more each ante"},
    {tab = "shop", header = "Stickers and pools"},
    {key = "enable_eternals_in_shop", tab = "shop", default = false, label = "Eternal stickers", info = "Shop Jokers can be Eternal"},
    {key = "enable_perishables_in_shop", tab = "shop", default = false, label = "Perishable stickers", info = "Shop Jokers can be Perishable"},
    {key = "enable_rentals_in_shop", tab = "shop", default = false, label = "Rental stickers", info = "Shop Jokers can be Rental"},
    {key = "all_eternal", tab = "shop", default = false, label = "All Jokers Eternal", info = "Every Joker you find is Eternal"},
    {key = "allow_duplicate_jokers", tab = "shop", default = false, label = "Duplicate Jokers", info = "Jokers you own can show up again"},
    {key = "allow_legendary_jokers_everywhere", tab = "shop", default = false, label = "Legendaries anywhere", info = "Legendary Jokers can appear in the shop"},
    {key = "allow_black_hole", tab = "shop", default = false, label = "Black Hole in packs", info = "Black Hole joins the Planet and Spectral pools"},
    {key = "allow_soul", tab = "shop", default = false, label = "The Soul in packs", info = "The Soul joins the Spectral pool"},

    {tab = "cards", header = "Suits"},
    {key = "suit_S", tab = "cards", default = true, label = "Spades"},
    {key = "suit_H", tab = "cards", default = true, label = "Hearts"},
    {key = "suit_C", tab = "cards", default = true, label = "Clubs"},
    {key = "suit_D", tab = "cards", default = true, label = "Diamonds"},
    {tab = "cards", header = "Ranks"},
    {key = "ranks_numbered", tab = "cards", default = true, label = "Number cards", info = "2 to 10"},
    {key = "ranks_faces", tab = "cards", default = true, label = "Face cards", info = "Jack, Queen, King"},
    {key = "ranks_aces", tab = "cards", default = true, label = "Aces"},
    {key = "copies", tab = "cards", default = 1, min = 1, max = 4, fmt = "times", label = "Copies of each card"},
    {key = "random_ranks", tab = "cards", default = false, label = "Random ranks", info = "Every card gets a random rank"},
    {key = "random_suits", tab = "cards", default = false, label = "Random suits", info = "Every card gets a random suit"},
    {tab = "cards", header = "Card mix"},
    {key = "enh_type", tab = "cards", default = 1, options = "ENHANCEMENTS", label = "Enhancement"},
    {key = "enh_pct", tab = "cards", default = 0, min = 0, max = 100, step = 10, fmt = "pct", label = "Enhanced cards", info = "Share of the deck with it"},
    {key = "edition_type", tab = "cards", default = 1, options = "EDITIONS", label = "Edition"},
    {key = "edition_pct", tab = "cards", default = 0, min = 0, max = 100, step = 10, fmt = "pct", label = "Cards with edition"},
    {key = "seal_type", tab = "cards", default = 1, options = "SEALS", label = "Seal"},
    {key = "seal_pct", tab = "cards", default = 0, min = 0, max = 100, step = 10, fmt = "pct", label = "Sealed cards"},

    {tab = "items", header = "Random extras"},
    {key = "random_starting_jokers", tab = "items", default = 0, min = 0, max = 5, label = "Random Jokers", info = "Extra random Jokers at the start"},
    {key = "random_consumables", tab = "items", default = 0, min = 0, max = 4, label = "Random consumables", info = "Tarot or Planet cards at the start"},
    {key = "random_voucher", tab = "items", default = false, label = "Random voucher", info = "One random voucher redeemed at the start"},

    {tab = "twists", header = "Scoring"},
    {key = "number_randomizer", tab = "twists", default = false, label = "Number randomizer", info = "Prices, Joker values and hands get rolled"},
    {key = "chip_reduction_percent", tab = "twists", default = 0, min = 0, max = 90, step = 10, fmt = "off_pct", label = "Chips penalty", info = "Each hand scores fewer chips"},
    {key = "mult_reduction_percent", tab = "twists", default = 0, min = 0, max = 90, step = 10, fmt = "off_pct", label = "Mult penalty", info = "Each hand scores less mult"},
    {key = "chips_dollar_cap", tab = "twists", default = false, label = "Chips capped by money", info = "A hand's chips cannot exceed your money"},
    {key = "debuff_played_cards", tab = "twists", default = false, label = "Played cards wear out", info = "Cards you play are debuffed for good"},
    {tab = "twists", header = "Cards"},
    {key = "flipped_cards", tab = "twists", default = 0, min = 0, max = 8, fmt = "one_in", label = "Face down draws", info = "Chance a drawn card is face down"},
    {key = "chance_to_increase_drawn_cards_rank", tab = "twists", default = 0, min = 0, max = 100, step = 10, fmt = "off_pct", label = "Rank up on draw", info = "Drawn cards can go up one rank"},
    {key = "chance_to_increase_discard_cards_rank", tab = "twists", default = 0, min = 0, max = 100, step = 10, fmt = "off_pct", label = "Rank up on discard", info = "Discarded cards can go up one rank"},
    {key = "minus_hand_size_per_X_dollar", tab = "twists", default = 0, min = 0, max = 25, step = 5, fmt = "off_money", label = "Greed tax", info = "-1 hand size for every $X you hold"},
    {tab = "twists", header = "Risk"},
    {key = "destroy_random_joker_after_ante_four", tab = "twists", default = 0, min = 0, max = 100, step = 10, fmt = "off_pct", label = "Joker decay", info = "From ante 4, chance per round to lose a Joker"},
    {key = "neg_joker_on_skip", tab = "twists", default = 0, min = 0, max = 100, step = 10, fmt = "off_pct", label = "Skip for a Negative", info = "Chance of a Negative Joker when skipping"},
}

DeckCreatorData.LISTS = {
    {key = "customJokerList", kind = "Joker", ban = false},
    {key = "customTarotList", kind = "Tarot", ban = false},
    {key = "customPlanetList", kind = "Planet", ban = false},
    {key = "customSpectralList", kind = "Spectral", ban = false},
    {key = "customVoucherList", kind = "Voucher", ban = false},
    {key = "customTagList", kind = "Tag", ban = false},
    {key = "bannedJokerList", kind = "Joker", ban = true},
    {key = "bannedTarotList", kind = "Tarot", ban = true},
    {key = "bannedPlanetList", kind = "Planet", ban = true},
    {key = "bannedSpectralList", kind = "Spectral", ban = true},
    {key = "bannedVoucherList", kind = "Voucher", ban = true},
    {key = "bannedTagList", kind = "Tag", ban = true},
    {key = "bannedBlindList", kind = "Blind", ban = true},
    {key = "bannedBoosterList", kind = "Booster", ban = true},
}

DeckCreatorData.BY_KEY = {}
for _, o in ipairs(DeckCreatorData.SCHEMA) do
    if o.key then DeckCreatorData.BY_KEY[o.key] = o end
end

function DeckCreatorData.options_of(o)
    if type(o.options) == "string" then return DeckCreatorData[o.options] end
    return o.options
end

function DeckCreatorData.format(o, v)
    if type(v) == "boolean" then return v and mod_loc("On") or mod_loc("Off") end
    if o.options then
        local opts = DeckCreatorData.options_of(o)
        return mod_loc(opts[v] or opts[1])
    end
    local f = o.fmt and DeckCreatorData.FMT[o.fmt]
    return f and f(v) or tostring(v)
end

function DeckCreatorData.clamp(o, v)
    if type(o.default) == "boolean" then return v == true end
    if o.options then
        local n = #DeckCreatorData.options_of(o)
        v = math.floor(tonumber(v) or o.default)
        if v < 1 or v > n then return o.default end
        return v
    end
    v = tonumber(v)
    if not v then return o.default end
    local step = o.step or 1
    v = math.floor((v - o.min) / step + 0.5) * step + o.min
    return math.max(o.min, math.min(o.max, v))
end

function DeckCreatorData.defaults()
    local c = {}
    for _, o in ipairs(DeckCreatorData.SCHEMA) do
        if o.key then c[o.key] = o.default end
    end
    for _, l in ipairs(DeckCreatorData.LISTS) do c[l.key] = {} end
    c.customDeck = true
    c.v = DeckCreatorData.VERSION
    c.deck_back = "b_red"
    return c
end

local function legacy_pct(count)
    count = tonumber(count) or 0
    if count <= 0 then return 0 end
    return math.max(10, math.min(100, math.floor(count / 52 * 10 + 0.5) * 10))
end

local function index_of(list, v)
    for i, x in ipairs(list) do if x == v then return i end end
end

function DeckCreatorData.migrate(old)
    old = type(old) == "table" and old or {}
    if old.v == DeckCreatorData.VERSION then
        local c = DeckCreatorData.defaults()
        for k, v in pairs(old) do c[k] = v end
        for _, o in ipairs(DeckCreatorData.SCHEMA) do
            if o.key then c[o.key] = DeckCreatorData.clamp(o, c[o.key]) end
        end
        for _, l in ipairs(DeckCreatorData.LISTS) do
            if type(c[l.key]) ~= "table" then c[l.key] = {} end
        end
        return c
    end
    local c = DeckCreatorData.defaults()
    local direct = {"hands", "discards", "hand_size", "dollars", "joker_slot", "consumable_slot", "win_ante",
        "interest_amount", "reroll_cost", "discount_percent", "shop_slots", "joker_rate", "tarot_rate", "planet_rate",
        "spectral_rate", "playing_card_rate", "edition_rate", "inflation", "no_interest", "discard_cost",
        "negative_joker_money", "enhanced_dollars_per_round", "enable_eternals_in_shop", "enable_perishables_in_shop",
        "enable_rentals_in_shop", "all_eternal", "allow_duplicate_jokers", "allow_legendary_jokers_everywhere",
        "allow_black_hole", "allow_soul", "number_randomizer", "chip_reduction_percent", "mult_reduction_percent",
        "chips_dollar_cap", "debuff_played_cards", "chance_to_increase_drawn_cards_rank",
        "chance_to_increase_discard_cards_rank", "destroy_random_joker_after_ante_four", "random_starting_jokers"}
    for _, k in ipairs(direct) do
        if old[k] ~= nil then c[k] = old[k] end
    end
    if old.booster_ante_scaling ~= nil then c.booster_ante_scaling = (old.booster_ante_scaling == true) or ((tonumber(old.booster_ante_scaling) or 0) > 0) end
    if old.interest_cap ~= nil then c.interest_max = old.interest_cap end
    if old.extra_hand_bonus ~= nil then c.money_per_hand = old.extra_hand_bonus end
    if old.extra_discard_bonus ~= nil then c.money_per_discard = old.extra_discard_bonus end
    if tonumber(old.ante_scaling) then c.blind_size = tonumber(old.ante_scaling) * 100 end
    if tonumber(old.multiply_probabilities) then c.probability = tonumber(old.multiply_probabilities) end
    if old.remove_faces or old.no_faces then c.ranks_faces = false end
    if old.no_aces then c.ranks_aces = false end
    if old.no_numbered_cards then c.ranks_numbered = false end
    if old.randomize_ranks or old.randomize_rank_suit then c.random_ranks = true end
    if old.randomize_suits or old.randomize_rank_suit then c.random_suits = true end
    local enh = {all_bonus = "Bonus", all_mult = "Mult", all_wild = "Wild", all_glass = "Glass", all_steel = "Steel",
        all_stone = "Stone", all_gold = "Gold", all_lucky = "Lucky"}
    for k, name in pairs(enh) do
        if old[k] then c.enh_type = index_of(DeckCreatorData.ENHANCEMENTS, name); c.enh_pct = 100 end
    end
    local eds = {all_foil = "Foil", all_holo = "Holographic", all_polychrome = "Polychrome"}
    for k, name in pairs(eds) do
        if old[k] then c.edition_type = index_of(DeckCreatorData.EDITIONS, name); c.edition_pct = 100 end
    end
    if c.enh_pct == 0 then
        local best, best_n = nil, 0
        local renh = {random_bonus_cards = "Bonus", random_mult_cards = "Mult", random_wild_cards = "Wild", random_glass_cards = "Glass",
            random_steel_cards = "Steel", random_stone_cards = "Stone", random_gold_cards = "Gold", random_lucky_cards = "Lucky",
            random_enhancement_cards = "Random"}
        for k, name in pairs(renh) do
            local n = tonumber(old[k]) or 0
            if n > best_n then best, best_n = name, n end
        end
        if best then c.enh_type = index_of(DeckCreatorData.ENHANCEMENTS, best); c.enh_pct = legacy_pct(best_n) end
    end
    if c.edition_pct == 0 then
        local best, best_n = nil, 0
        local red = {random_foil_cards = "Foil", random_holographic_cards = "Holographic", random_polychrome_cards = "Polychrome", random_edition_cards = "Random"}
        for k, name in pairs(red) do
            local n = tonumber(old[k]) or 0
            if n > best_n then best, best_n = name, n end
        end
        if best then c.edition_type = index_of(DeckCreatorData.EDITIONS, best); c.edition_pct = legacy_pct(best_n) end
    end
    if old.random_starting_items then c.random_consumables = 2 end
    if old.one_random_voucher then c.random_voucher = true end
    if old.flipped_cards == true then c.flipped_cards = 4 elseif tonumber(old.flipped_cards) then c.flipped_cards = tonumber(old.flipped_cards) end
    if old.minus_hand_size_per_X_dollar == true then c.minus_hand_size_per_X_dollar = 5 elseif tonumber(old.minus_hand_size_per_X_dollar) then c.minus_hand_size_per_X_dollar = tonumber(old.minus_hand_size_per_X_dollar) end
    c.frugal_dollars = (tonumber(old.chance_for_twenty_dollars_on_shop_skip) or 0) * 20 / 100
    c.skip_dollars = (tonumber(old.chance_for_five_dollars_on_skip_disable) or 0) * 5 / 100 + (tonumber(old.chance_for_fifteen_dollars_on_skip_disable) or 0) * 15 / 100
    c.neg_joker_on_skip = tonumber(old.chance_for_negative_joker_on_skip_disable) or 0
    local idx = tonumber(old.deck_back_index)
    if idx and DeckCreatorData.BACKS[idx] then c.deck_back = DeckCreatorData.BACKS[idx] end
    for _, l in ipairs(DeckCreatorData.LISTS) do
        if type(old[l.key]) == "table" then c[l.key] = old[l.key] end
    end
    if old.custom_cards_set and type(old.customCardList) == "table" and #old.customCardList > 0 then
        c.customCardList = old.customCardList
        c.custom_cards_set = true
    end
    c.uuid = old.uuid
    for _, o in ipairs(DeckCreatorData.SCHEMA) do
        if o.key then c[o.key] = DeckCreatorData.clamp(o, c[o.key]) end
    end
    return c
end

function DeckCreatorData.is_default(o, v)
    return v == o.default
end

function DeckCreatorData.changed_options(config)
    local out = {}
    for _, o in ipairs(DeckCreatorData.SCHEMA) do
        if o.key and config[o.key] ~= nil and not DeckCreatorData.is_default(o, config[o.key]) then
            out[#out + 1] = o
        end
    end
    return out
end

function DeckCreatorData.composition(config)
    local suits = {}
    for _, s in ipairs({"S", "H", "C", "D"}) do
        if config["suit_" .. s] then suits[#suits + 1] = s end
    end
    local ranks = {}
    if config.ranks_numbered then for _, r in ipairs({"2", "3", "4", "5", "6", "7", "8", "9", "T"}) do ranks[#ranks + 1] = r end end
    if config.ranks_faces then for _, r in ipairs({"J", "Q", "K"}) do ranks[#ranks + 1] = r end end
    if config.ranks_aces then ranks[#ranks + 1] = "A" end
    local copies = tonumber(config.copies) or 1
    local per_suit = {}
    for _, s in ipairs(suits) do per_suit[s] = #ranks * copies end
    local total = #suits * #ranks * copies
    local faces = config.ranks_faces and (#suits * 3 * copies) or 0
    return {suits = suits, ranks = ranks, copies = copies, per_suit = per_suit, total = total, faces = faces}
end

function CustomDeck:blankDeck()
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.name = ""
    o.loc_txt = {name = "", text = {}}
    o.config = DeckCreatorData.defaults()
    o.config.uuid = DeckCreatorUtils and DeckCreatorUtils.uuid() or tostring(math.random(100000, 999999))
    o.slug = "b_dc_" .. o.config.uuid
    o.spritePos = {x = 0, y = 0}
    return o
end

function CustomDeck:new(name, slug, config, spritePos, loc_txt)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.config = config or DeckCreatorData.defaults()
    if slug == nil or slug == "" then
        o.slug = "b_dc_" .. tostring(o.config.uuid or math.random(100000, 999999))
    else
        o.slug = slug
    end
    o.loc_txt = loc_txt or {name = name, text = {}}
    o.name = name
    o.spritePos = spritePos or {x = 0, y = 0}
    o.unlocked = true
    o.discovered = true
    return o
end

function CustomDeck.createCustomDeck(name, slug, cardConfig, spritePos, loc_txt)
    return CustomDeck:new(name, slug, cardConfig, spritePos, loc_txt)
end

function CustomDeck.parseRawDescription(rawDescription)
    local descTable = {}
    for part in string.gmatch(rawDescription .. "<n", "(.-)<n") do
        local modifiedPart = string.gsub(part, "<:([^<]+)<", function(key)
            return "{C:" .. key .. "}"
        end)
        modifiedPart = string.gsub(modifiedPart, "<", "{}")
        table.insert(descTable, modifiedPart)
    end
    return descTable
end
