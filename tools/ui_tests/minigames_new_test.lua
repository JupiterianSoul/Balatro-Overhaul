local root = (arg and arg[1]) or "."
package.path = root .. "/assets/?.lua;" .. package.path

local fails, checks = 0, 0
local function ok(cond, what)
    checks = checks + 1
    if not cond then fails = fails + 1 print("FAIL " .. what) end
end

local defs = {}
local K = {}
function K.card_w() return 2.05 end
function K.card_h() return 2.75 end
function K.pops() return {} end
function K.pop() end
function K.juice() end
function K.sound() end
function K.shake() end
function K.flash() end
function K.press() end
function K.skin_key() return "j_joker" end
function K.skin_shape() return 1, 1, 1, 1 end
local clock = 0
function K.now() return clock end
function K.hit(b, x, y, pad)
    pad = pad or 0
    return b and x >= b.x - pad and x <= b.x + b.w + pad and y >= b.y - pad and y <= b.y + b.h + pad
end
function K.shuffle(rng, t)
    for i = #t, 2, -1 do
        local j = rng:random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end
local SUITS, RANKS = {"H", "C", "D", "S"}, {"2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"}
function K.deck(rng)
    local d = {}
    for _, s in ipairs(SUITS) do
        for r = 1, 13 do d[#d + 1] = {suit = s, rank = r + 1, key = s .. "_" .. RANKS[r]} end
    end
    return K.shuffle(rng, d)
end

Minigames = {kit = K, L = function(s) return s end, register = function(d) defs[d.key] = d end}
UIK = {touch = function() return false end}
G = {C = {BLACK = {0, 0, 0, 1}, RED = {1, 0, 0, 1}, GOLD = {1, 1, 0, 1}, BLUE = {0, 0, 1, 1}, CHIPS = {0, 0, 1, 1}, MULT = {1, 0, 0, 1}, GREEN = {0, 1, 0, 1}, SECONDARY_SET = {}, UI = {}},
    localization = {descriptions = {Blind = {bl_psychic = {name = "The Psychic", text = {"Must play 5 cards"}}, bl_small = {name = "Small Blind", text = {}}, bl_eye = {name = "The Eye", text = {"No repeat hand", "types this round"}}}}}}

local rng = {random = function(_, a, b)
    if not a then return math.random() end
    return math.random(a, b)
end}
math.randomseed(7)

local BB = dofile(root .. "/assets/functions/minigames/beat_blind.lua")
local RN = dofile(root .. "/assets/functions/minigames/runner.lua")
local P = require "functions/minigames/poker"
ok(defs.beat_blind and defs.runner, "both games register")

ok(BB.target_for(1, 1) == 150 and BB.target_for(1, 2) == 230 and BB.target_for(1, 3, "bl_hook") == 300, "ante 1 targets 150, 230, 300")
ok(BB.target_for(2, 1) == 350 and BB.target_for(3, 1) == 790, "targets grow 2.3x per ante")
ok(BB.target_for(1, 3, "bl_wall") == 450 and BB.target_for(1, 3, "bl_needle") == 150, "The Wall is 3x base, The Needle 1x")

local function card(rank, suit) return {rank = rank, suit = suit, key = suit .. "_" .. RANKS[rank - 1]} end

local function new_bb()
    local g = setmetatable({W = 10.6, H = 5.4, rng = rng}, BB)
    g:start()
    return g
end

local function run(g, secs)
    for _ = 1, math.floor(secs * 60) do
        if g.over then return end
        g:update(1 / 60)
    end
end

local function play(g, cards)
    g.hand = {}
    for i, c in ipairs(cards) do
        c.sel, c.hook, c.x, c.lift, c.delay = true, false, 0, 0, 0
        g.hand[i] = c
    end
    for _, c in ipairs({card(2, "S"), card(3, "D"), card(4, "S")}) do
        c.sel, c.hook, c.x, c.lift, c.delay = false, false, 0, 0, 0
        g.hand[#g.hand + 1] = c
    end
    g:do_play()
    run(g, 6)
end

local g = new_bb()
ok(g.state == "select" and #g.hand == 8 and g.hands == 3 and g.discards == 2 and g.target == 150, "first blind: 8 cards, 3 hands, 2 discards, target 150")
play(g, {card(13, "H"), card(13, "S")})
ok(g.score == (10 + 20) * 2 and g.round == 60, "pair of kings scores (10 + 20) x 2 = 60")
ok(g.state == "select" and g.hands == 2 and #g.hand == 8, "back to select with a refilled hand")
play(g, {card(14, "H"), card(13, "H"), card(9, "H"), card(6, "H"), card(3, "H")})
ok(g.score == 60 + (35 + 11 + 10 + 9 + 6 + 3) * 4, "flush scores base 35 x 4 plus every card")
ok(g.state == "pick" and g.beaten == 1 and g.offer and #g.offer == 3, "beating the blind offers three planets")
local fav = false
for _, o in ipairs(g.offer or {}) do if o.hand == "Flush" or o.hand == "Pair" then fav = true end end
ok(fav, "the most played hand's planet is offered")
local pick = g.offer[1].hand
g:choose(1)
ok(g.levels[pick] == 2 and g.state == "chosen", "choosing a planet levels its hand")
run(g, 1)
ok(g.state == "select" and g.kind == 2 and g.target == 230 and g.round == 0, "next is the Big Blind at 230")
local c0, m0 = P.BASE[pick][1], P.BASE[pick][2]
local c1, m1 = g:base(pick)
ok(c1 > c0 and m1 > m0, "levelled hand has more chips and mult")

g = new_bb()
g.kind = 3
g.bag = {"bl_psychic"}
g:new_blind()
ok(g.boss == "bl_psychic" and g.bname == "The Psychic" and g.btext == "Must play 5 cards", "boss name and rule come from the game's text")
local before = g.score
play(g, {card(13, "H"), card(13, "S")})
ok(g.score == before and g.hands == 2, "a pair under The Psychic is not allowed, scores 0 and uses the hand")

g = new_bb()
g.kind, g.bag = 3, {"bl_eye"}
g:new_blind()
play(g, {card(13, "H"), card(13, "S")})
local s1 = g.score
ok(s1 == 60, "The Eye: first pair scores")
play(g, {card(12, "H"), card(12, "S")})
ok(g.score == s1, "The Eye: a second pair scores 0")
play(g, {card(12, "H"), card(12, "S"), card(12, "D")})
ok(g.score > s1 and g.over, "The Eye: a new hand type scores, then out of hands ends the run")
ok(g.summary and g.summary:find("The Eye", 1, true) and g.summary:find("\n", 1, true), "end summary names the boss on two lines")

g = new_bb()
g.kind, g.bag = 3, {"bl_flint"}
g:new_blind()
local fc, fm = g:base("Pair")
ok(fc == 5 and fm == 1, "The Flint halves base chips and mult")
g = new_bb()
g.kind, g.bag = 3, {"bl_water"}
g:new_blind()
ok(g.discards == 0, "The Water: no discards")
g.kind, g.bag = 3, {"bl_needle"}
g:new_blind()
ok(g.hands == 1, "The Needle: one hand")
g.kind, g.bag = 3, {"bl_hook"}
g:new_blind()
play(g, {card(13, "H"), card(13, "S")})
ok(#g.hand == 8 and g.di == 8 + 2 + 2 + 3, "The Hook discards two held cards per hand, the hand refills")

g = new_bb()
g.kind = 3
g.bag = {"bl_mouth"}
g:new_blind()
g.round = g.target
g.state, g.t = "clear", 99
run(g, 2)
ok(g.state == "pick", "boss beaten leads to the planet pick")
g:choose(2)
run(g, 1)
ok(g.ante == 2 and g.kind == 1 and g.target == 350, "after the boss comes ante 2 Small Blind")

local function new_rn()
    local r = setmetatable({W = 10.6, H = 5.4, rng = rng}, RN)
    r:start()
    return r
end

local r = new_rn()
r.gap = 1e9
r:jump()
local top = 0
for _ = 1, 120 do
    r:update(1 / 60)
    top = math.max(top, r.jy)
end
ok(top > 1.75 and top <= RN.JUMP ^ 2 / (2 * RN.GRAV) and not r.air and r.jy == 0, "jump reaches about 1.8 and lands")
ok(r.cstep % 10 == 0 and r.score == r.cstep * r.mult, "chips count in tens, score is chips x mult")

r = new_rn()
r.gap = 1e9
r.obs[1] = {kind = "fly", key = "bl_small", w = 0.53, h = 0.53, y = r.gy - 1.95, size = 0.66, bob = 0, extra = 1, x = r.px + 1}
run(r, 0.5)
ok(r.state == "run", "a floating blind passes over a grounded Jimbo")
r.obs[1] = {kind = "fly", key = "bl_small", w = 0.53, h = 0.53, y = r.gy - 1.95, size = 0.66, bob = 0, extra = 1, x = r.px + 2.2}
r:jump()
run(r, 0.4)
ok(r.state == "dead", "jumping into a floating blind knocks Jimbo out")
run(r, 1.5)
ok(r.over and r.summary:find("Small Blind", 1, true), "the end card names what knocked him out")

r = new_rn()
r.gap = 1e9
r.obs[1] = {kind = "stack", list = {"stake_red", "stake_blue", "stake_gold"}, n = 3, w = 0.45, h = 1.04, y = r.gy - 0.57, extra = 0, x = r.px + 2.6}
r.picks[1] = {x = r.px + 2.6, y = r.gy - 2.3, key = "H_A", spin = 0, j = {}}
local jumped = false
for _ = 1, 120 do
    local o = r.obs[1]
    if not jumped and o and (o.x - o.w / 2) - (r.px + r.pw / 2 - 0.14) <= r.speed * 0.2 then r:jump() jumped = true end
    r:update(1 / 60)
end
ok(r.state == "run" and r.mult == 2 and r.cards == 1, "a timed jump clears a 3-chip stack and grabs the card above it")

r = new_rn()
r.gap = 1e9
r.obs[1] = {kind = "roll", key = "bl_hook", w = 0.56, h = 0.56, y = r.gy - 0.39, size = 0.78, r = 0, extra = 1.5, x = r.px + 2}
run(r, 1)
ok(r.state == "dead" or r.over, "running into a rolling Boss Blind ends the run")

r = new_rn()
for _ = 1, 60 * 60 do r:update(1 / 60) if r.state ~= "run" then break end end
ok(r.speed <= RN.TOP and r.speed >= RN.START, "speed stays between start and top")

g = new_bb()
g.kind, g.bag = 3, {"bl_eye"}
g:new_blind()
ok(#g.blines == 2 and g.blines[1] == "No repeat hand" and g.blines[2] == "types this round", "a boss keeps its effect lines for the blind panel")
g = new_bb()
ok(#g.blines == 0, "the Small Blind has no effect lines")
ok(g.bp.y + g.bp.h <= 2.0, "the blind panel ends above the lifted cards on phone")

local function settle(gg)
    for i, c in ipairs(gg.hand) do c.x, c.lift, c.delay = gg:target_x(i), 0, 0 end
end
local function nsel(gg) return #gg:selected() end
g = new_bb()
settle(g)
local cy = g.hy
g:drag(g.hand[1].x, cy, true)
ok(nsel(g) == 0, "pressing on a card starts a sweep without selecting yet")
g:drag(g.hand[2].x, cy, true)
ok(g.hand[1].sel and g.hand[2].sel and nsel(g) == 2, "sweeping onto the next card selects both")
g:drag(g.hand[2].x + 0.1, cy, true)
ok(nsel(g) == 2, "staying on a card does not toggle it again")
g:drag(g.hand[3].x, cy, true)
g:press(g.hand[3].x, cy)
ok(nsel(g) == 3 and g.hand[3].sel, "the click that ends a sweep is ignored")
g:drag(g.hand[3].x, cy, false)
clock = clock + 1
g:press(g.hand[5].x, cy)
ok(g.hand[5].sel and nsel(g) == 4, "a normal tap still selects")
g:drag(g.hand[3].x, cy, true)
g:drag(g.hand[2].x, cy, true)
ok(not g.hand[3].sel and not g.hand[2].sel and nsel(g) == 2, "sweeping back over selected cards unselects them")
g:drag(g.hand[2].x, cy, false)
clock = clock + 1
for _, c in ipairs(g.hand) do c.sel = false end
g:preview()
g:drag(g.hand[1].x, cy, true)
for i = 2, 8 do g:drag(g.hand[i].x, cy, true) end
g:drag(g.hand[8].x, cy, false)
ok(nsel(g) == 5, "a sweep over the whole hand stops at 5 cards")
clock = clock + 1
for _, c in ipairs(g.hand) do c.sel = false end
g:preview()
g:drag(g.W / 2, 0.5, true)
g:drag(g.hand[1].x, cy, true)
g:drag(g.hand[2].x, cy, true)
ok(nsel(g) == 0, "a press that starts above the hand never sweeps")
g:drag(g.hand[2].x, cy, false)
clock = clock + 1
g.state = "score"
g:drag(g.hand[1].x, cy, true)
g:drag(g.hand[2].x, cy, true)
ok(nsel(g) == 0, "no sweep while a hand scores")
g:drag(g.hand[2].x, cy, false)

local SL = dofile(root .. "/assets/functions/minigames/slots.lua")
ok(defs.slots, "slots registers")
local pool = {}
for i = 1, 150 do pool[i] = "j_t" .. i end
pool[151] = "j_joker"
local s1 = SL.draw_symbols(rng, pool)
local seen, dup = {}, false
for _, k in ipairs(s1) do if seen[k] then dup = true end seen[k] = true end
ok(#s1 == 6 and s1[1] == "j_joker" and not dup, "slots draws 6 different symbols with Jimbo always in")
local differ = false
for _ = 1, 5 do
    local s2 = SL.draw_symbols(rng, pool)
    for i = 2, 6 do if s2[i] ~= s1[i] then differ = true end end
end
ok(differ, "slots draws new symbols each game")
local alike = false
for _ = 1, 30 do
    local pl = {"j_jolly", "j_zany", "j_sly", "j_t1", "j_t2", "j_t3", "j_t4", "j_t5", "j_t6"}
    for _, k in ipairs(SL.draw_symbols(rng, pl)) do if k == "j_jolly" or k == "j_zany" or k == "j_sly" then alike = true end end
end
ok(not alike, "jokers with Jimbo's face stay off the reels so three Jimbo is never in doubt")
local few = SL.draw_symbols(rng, {"j_t1", "j_joker"})
ok(#few == 6 and few[1] == "j_joker", "a small pool is filled with the old symbols")
local sg = setmetatable({W = 10.6, H = 5.4, rng = rng}, SL)
sg:start()
local onreel = {}
for _, k in ipairs(sg.reels[1].strip) do onreel[k] = true end
ok(#sg.reels[1].strip == 6 and onreel.j_joker, "every reel carries the 6 symbols with Jimbo")

function K.jokers()
    local t = {}
    for i = 1, 30 do t[i] = "j_" .. i end
    return t
end
local JM = dofile(root .. "/assets/functions/minigames/joker_memory.lua")
local jm = setmetatable({W = 10.6, H = 5.4, rng = rng}, JM)
jm:start()
local function up_count()
    local n = 0
    for _, c in ipairs(jm.cards) do if c.up then n = n + 1 end end
    return n
end
ok(up_count() == #jm.cards, "memory shows every card face up when the game starts")
jm:press(jm:pos(1))
ok(jm.open1 == nil, "cards cannot be flipped while they are shown")
run(jm, 1.2)
ok(up_count() == #jm.cards and jm.left == 60, "cards stay up for the first second and the timer waits")
run(jm, 0.7)
ok(up_count() == 0 and jm.show_t == nil, "cards flip face down after the preview")
run(jm, 0.3)
ok(jm.left < 60, "the timer starts after the preview")
jm:press(jm:pos(1))
ok(jm.open1 == 1, "a card can be flipped once play begins")

print(string.format("%d checks, %d failed", checks, fails))
print(fails == 0 and "ALL OK" or "FAILED")
os.exit(fails == 0 and 0 or 1)
