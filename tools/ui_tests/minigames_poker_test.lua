local base = (arg and arg[0] and arg[0]:match("^(.*)/tools/ui_tests/") or ".")
local P = dofile(base .. "/assets/functions/minigames/poker.lua")
local fails = 0
local function check(name, cond, detail) if not cond then fails = fails + 1 print("FAIL " .. name .. " " .. tostring(detail or "")) else print("ok   " .. name) end end

local rng = {random = function(_, a, b) return math.random(a, b) end}
math.randomseed(1104)

local function hand(spec)
    local t = {}
    for c in spec:gmatch("%S+") do
        local r, s = c:sub(1, 1), c:sub(2, 2)
        local rank = ({T = 10, J = 11, Q = 12, K = 13, A = 14})[r] or tonumber(r)
        t[#t + 1] = {rank = rank, suit = s}
    end
    return t, #t
end

local cases = {
    {"AS KS QS JS TS", "Straight Flush"}, {"AH 2C 3D 4S 5H", "Straight"}, {"9H TC JD QS KH", "Straight"},
    {"QH KC AD 2S 3H", "High Card"}, {"7H 7C 7D 7S 2H", "Four of a Kind"}, {"7H 7C 7D 2S 2H", "Full House"},
    {"2H 5H 9H JH KH", "Flush"}, {"7H 7C 7D 2S 4H", "Three of a Kind"}, {"7H 7C 2D 2S 4H", "Two Pair"},
    {"7H 7C 3D 2S 4H", "Pair"}, {"KH", "High Card"}, {"KH KC", "Pair"}, {"KH KC KD", "Three of a Kind"},
    {"2H 3H 4H 5H", "High Card"}, {"KH KC 4D 4S", "Two Pair"},
}
for _, c in ipairs(cases) do
    local cards, n = hand(c[1])
    check("eval " .. c[1], P.eval(cards, n) == c[2], P.eval(cards, n))
end

local cards, n = hand("7H 7C 3D 2S 4H")
local name, chips, mult, total = P.score(cards, n)
check("pair scores the pair only", name == "Pair" and chips == 10 + 14 and mult == 2 and total == 48, chips .. "x" .. mult)
cards, n = hand("AS 3D 2S")
name, chips, mult, total = P.score(cards, n)
check("high card scores the top card", name == "High Card" and chips == 5 + 11 and mult == 1 and total == 16, chips .. "x" .. mult)
cards, n = hand("AS KS QS JS TS")
name, chips, mult, total = P.score(cards, n)
check("royal scores all five", name == "Straight Flush" and chips == 100 + 11 + 10 + 10 + 10 + 10 and mult == 8, chips .. "x" .. mult)
cards, n = hand("7H 7C 7D 7S 2H")
P.eval(cards, n)
check("four of a kind kicker does not score", P.scoring[1] and P.scoring[4] and not P.scoring[5])

local out = {}
for i = 1, 5 do out[i] = {} end
for _, nm in ipairs(P.NAMES) do
    local good, dupes = true, false
    for _ = 1, 400 do
        if not P.make(nm, rng, out) or P.eval(out, 5) ~= nm then good = false break end
        local seen = {}
        for i = 1, 5 do
            if seen[out[i].key] then dupes = true end
            seen[out[i].key] = true
            if out[i].key ~= P.key(out[i].rank, out[i].suit) then good = false end
        end
    end
    check("make " .. nm .. " x400", good)
    check("make " .. nm .. " no duplicate cards", not dupes)
end
check("card key format", P.key(14, "S") == "S_A" and P.key(10, "H") == "H_T" and P.key(2, "C") == "C_2")
check("hand name falls back to English", P.hand_name("Two Pair") == "Two Pair")

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
