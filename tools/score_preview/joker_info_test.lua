local root = arg[1] or "."
local fails, checks = 0, 0
local function ok(cond, msg)
    checks = checks + 1
    if not cond then fails = fails + 1; print("FAIL " .. msg) end
end

local protos = {}
for line in io.lines(root .. "/assets/game.lua") do
    local key, body = line:match("^%s*(j_[%w_]+)=%s*({.*}),?%s*$")
    if key then
        local fn = loadstring("return " .. body)
        local okp, t = pcall(fn)
        if okp and type(t) == 'table' then t.key = key; protos[#protos + 1] = t end
    end
end
ok(#protos == 150, "150 vanilla jokers parsed (" .. #protos .. ")")

local function colour() return {1, 1, 1, 1} end
G = {C = setmetatable({UI = {TEXT_LIGHT = colour(), TEXT_INACTIVE = colour()}, SECONDARY_SET = {Tarot = colour(), Planet = colour(), Spectral = colour()}},
    {__index = function() return colour() end}), FUNCS = {}, SETTINGS = {language = 'en-us'}, ASSET_ATLAS = {}}
G.GAME = {probabilities = {normal = 1}, dollars = 12, hands_played = 3, skips = 2, starting_deck_size = 52,
    consumeable_usage_total = {tarot = 3}, consumeable_usage = {c_mars = {set = 'Planet', count = 1}, c_fool = {set = 'Tarot', count = 2}},
    current_round = {hands_left = 1, discards_left = 2, discards_used = 0, hands_played = 0,
        mail_card = {rank = 'King'}, castle_card = {suit = 'Hearts'}, ancient_card = {suit = 'Clubs'}, idol_card = {rank = 'Queen', suit = 'Spades'}},
    hands = {Pair = {played = 2, played_this_round = 1}}}
G.deck = {cards = {1, 2, 3}}
G.playing_cards = {}
for i = 1, 48 do G.playing_cards[i] = i end
local Card = {}
Card.__index = Card
function Card:is_suit(s) return self.base.suit == s end
function Card:get_id() return self.base.id end
local function pc(id, suit, hl)
    return setmetatable({base = {id = id, suit = suit, nominal = math.min(id, 10)}, ability = {effect = ''}, highlighted = hl}, Card)
end
G.hand = {cards = {pc(13, 'Spades'), pc(12, 'Clubs'), pc(4, 'Spades'), pc(2, 'Hearts', true), pc(2, 'Diamonds', true)}}
G.hand.highlighted = {G.hand.cards[4], G.hand.cards[5]}
function localize(a, b)
    if type(a) == 'table' then return (a.key or 'x'):gsub('^%a_', ''):gsub('_', ' '):gsub('^%l', string.upper) end
    if a == 'k_tarot' then return 'Tarot' elseif a == 'k_spectral' then return 'Spectral' elseif a == 'k_joker' then return 'Joker' end
    return a
end
function mod_loc(s) if s == 'jd_mult' then return 'Mult' elseif s == 'jd_chips' then return 'Chips' end return s end
function mod_loc_register() end
function number_format(n) return tostring(n) end
function UIBox() return {remove = function() end} end
CardArea = {remove_card = function() end}
PREVIEW = {fx_for = function() return nil end, hand_info = function() return 'Pair', 'Pair', {Pair = {{1}}}, {} end}

dofile(root .. "/assets/functions/joker_display.lua")

local function ability_for(p)
    local cfg = p.config or {}
    local a = {name = p.name, set = 'Joker', effect = p.effect, mult = cfg.mult or 0, t_mult = cfg.t_mult or 0, t_chips = cfg.t_chips or 0,
        x_mult = cfg.Xmult or 1, h_size = cfg.h_size or 0, d_size = cfg.d_size or 0, type = cfg.type or '', perma_bonus = 0}
    if type(cfg.extra) == 'table' then
        a.extra = {}
        for k, v in pairs(cfg.extra) do a.extra[k] = v end
    else
        a.extra = cfg.extra
    end
    a.invis_rounds, a.caino_xmult, a.hands_played_at_create = 0, 1, 1
    a.steel_tally, a.stone_tally, a.nine_tally, a.driver_tally = 2, 1, 4, 7
    if p.name == 'Yorick' then a.yorick_discards = a.extra.discards end
    if p.name == 'Loyalty Card' then a.loyalty_remaining = a.extra.every end
    if p.name == 'To Do List' then a.to_do_poker_hand = 'Flush' end
    return a
end

local jokers = {}
for i, p in ipairs(protos) do
    jokers[i] = {config = {center = p}, ability = ability_for(p), sell_cost = 3, children = {}}
end
G.jokers = {cards = {jokers[1], jokers[2], jokers[3]}, config = {card_limit = 5}}

local seen = 0
for i, p in ipairs(protos) do
    local id = p.key:sub(3)
    local def = JD.DEFS[id]
    ok(def ~= nil, "definition for " .. p.key)
    if def then
        local c = jokers[i]
        if id == 'blueprint' or id == 'brainstorm' then
            G.jokers.cards = {c, jokers[1]}
            if id == 'brainstorm' then G.jokers.cards = {jokers[1], c} end
        end
        local good, r = pcall(def, c)
        ok(good and type(r) == 'table', p.key .. " runs: " .. tostring(r))
        if good and type(r) == 'table' then
            r = JD.clean_info(r)
            seen = seen + 1
            ok(type(r.m) == 'string' and r.m ~= '', p.key .. " has a main value")
            for _, field in ipairs({'m', 's', 'e'}) do
                local s = r[field]
                if s then
                    ok(not s:find('_'), p.key .. " " .. field .. " has an underscore: " .. s)
                    ok(not s:find('\226\128\148') and not s:find('\226\128\147') and not s:find(' %- '), p.key .. " " .. field .. " has a dash: " .. s)
                    ok(not s:find('^%(?%l'), p.key .. " " .. field .. " starts lowercase: " .. s)
                    ok(not s:find('nil') and not s:find('nan') and not s:find('{%d}'), p.key .. " " .. field .. " has a hole: " .. s)
                end
            end
            if os.getenv("JI_MD") == "1" then
                local live = ({mult = "Mult it adds", chips = "Chips it adds", chips_mult = "Chips and Mult it adds", xmult = "X Mult it applies",
                    money = "$ it pays during scoring", reps = "Retriggers it gives"})[r.unit or ''] or "Same as without a selection"
                print(string.format("| %d | %s | `%s` | %s | %s | %s | %s | ji_%02d |", i, p.name, p.key, r.m, r.s or '', r.e or '', live, math.floor((i - 1) / 5) + 1))
            else
                print(string.format("%-22s | %-26s | %-34s | %s", p.key, r.m, r.s or '', r.e or ''))
            end
        end
        G.jokers.cards = {jokers[1], jokers[2], jokers[3]}
    end
end
local lo = {mult = 9, chips = 0, xmult = 1, dollars = 0, reps = 0}
local hi = {mult = 23, chips = 0, xmult = 1, dollars = 0, reps = 0}
local segs = JD.fx_segs(lo, hi, 'mult')
ok(segs[1] and segs[1].t == '+9 to 23 Mult', "range text from sandbox fx: " .. tostring(segs[1] and segs[1].t))
segs = JD.fx_segs(nil, nil, 'xmult')
ok(segs[1] and segs[1].t == 'X1' and segs[1].pill, "inactive xmult shows X1")
ok(JD.clean("hello_world - test") == "Hello world test", "clean text: " .. JD.clean("hello_world - test"))
print(string.format("joker_info_test: %d definitions ran, %d checks, %d failed", seen, checks, fails))
os.exit(fails == 0 and 0 or 1)
