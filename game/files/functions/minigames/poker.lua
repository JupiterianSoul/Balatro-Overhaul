local P = {}

P.NAMES = {"High Card", "Pair", "Two Pair", "Three of a Kind", "Straight", "Flush", "Full House", "Four of a Kind", "Straight Flush"}
P.BASE = {
    ["High Card"] = {5, 1}, ["Pair"] = {10, 2}, ["Two Pair"] = {20, 2}, ["Three of a Kind"] = {30, 3}, ["Straight"] = {30, 4},
    ["Flush"] = {35, 4}, ["Full House"] = {40, 4}, ["Four of a Kind"] = {60, 7}, ["Straight Flush"] = {100, 8},
}
P.SUITS = {"H", "C", "D", "S"}
P.RANKS = {"2", "3", "4", "5", "6", "7", "8", "9", "T", "J", "Q", "K", "A"}

local cnt = {}
P.scoring = {}

function P.chips(rank)
    if rank == 14 then return 11 end
    if rank >= 10 then return 10 end
    return rank
end

function P.key(rank, suit)
    return suit .. "_" .. P.RANKS[rank - 1]
end

function P.eval(cards, n)
    local sc = P.scoring
    for r = 2, 14 do cnt[r] = 0 end
    for i = 1, 5 do sc[i] = false end
    for i = 1, n do cnt[cards[i].rank] = cnt[cards[i].rank] + 1 end
    local flush, straight = false, false
    if n == 5 then
        flush = true
        for i = 2, 5 do if cards[i].suit ~= cards[1].suit then flush = false end end
        local lo, hi, distinct = 99, 0, true
        for i = 1, 5 do
            local r = cards[i].rank
            if cnt[r] > 1 then distinct = false end
            if r < lo then lo = r end
            if r > hi then hi = r end
        end
        if distinct then
            if hi - lo == 4 then straight = true
            elseif hi == 14 and cnt[2] == 1 and cnt[3] == 1 and cnt[4] == 1 and cnt[5] == 1 then straight = true end
        end
    end
    local four, three, pairs, top = nil, nil, 0, 0
    for r = 14, 2, -1 do
        local c = cnt[r]
        if c == 4 then four = r elseif c == 3 then three = r elseif c == 2 then pairs = pairs + 1 end
        if c > 0 and top == 0 then top = r end
    end
    local name
    if straight and flush then name = "Straight Flush"
    elseif four then name = "Four of a Kind"
    elseif three and pairs > 0 then name = "Full House"
    elseif flush then name = "Flush"
    elseif straight then name = "Straight"
    elseif three then name = "Three of a Kind"
    elseif pairs >= 2 then name = "Two Pair"
    elseif pairs == 1 then name = "Pair"
    else name = "High Card" end
    local high_done = false
    for i = 1, n do
        local c = cnt[cards[i].rank]
        if name == "Straight Flush" or name == "Flush" or name == "Straight" or name == "Full House" then sc[i] = true
        elseif name == "High Card" then
            if cards[i].rank == top and not high_done then sc[i] = true high_done = true end
        elseif name == "Four of a Kind" then sc[i] = c == 4
        elseif name == "Three of a Kind" then sc[i] = c == 3
        else sc[i] = c == 2 end
    end
    return name
end

function P.score(cards, n)
    local name = P.eval(cards, n)
    local base = P.BASE[name]
    local chips = base[1]
    for i = 1, n do
        if P.scoring[i] then chips = chips + P.chips(cards[i].rank) end
    end
    return name, chips, base[2], chips * base[2]
end

local used = {}

local function distinct_ranks(rng, out, from, to, avoid1, avoid2)
    for r = 2, 14 do used[r] = false end
    if avoid1 then used[avoid1] = true end
    if avoid2 then used[avoid2] = true end
    for i = from, to do
        local r = rng:random(2, 14)
        while used[r] do r = rng:random(2, 14) end
        used[r] = true
        out[i].rank = r
        out[i].suit = P.SUITS[rng:random(1, 4)]
    end
end

local function same_rank(rng, out, from, count, rank)
    local o = rng:random(0, 3)
    for i = 0, count - 1 do
        out[from + i].rank = rank
        out[from + i].suit = P.SUITS[(o + i) % 4 + 1]
    end
end

local function other(rng, a, b)
    local r = rng:random(2, 14)
    while r == a or r == b do r = rng:random(2, 14) end
    return r
end

function P.make(name, rng, out)
    for _ = 1, 300 do
        if name == "Straight Flush" or name == "Straight" then
            local lo = rng:random(1, 10)
            local s = P.SUITS[rng:random(1, 4)]
            for i = 1, 5 do
                local r = lo + i - 1
                out[i].rank = r == 1 and 14 or r
                out[i].suit = name == "Straight Flush" and s or P.SUITS[rng:random(1, 4)]
            end
        elseif name == "Four of a Kind" then
            local r = rng:random(2, 14)
            same_rank(rng, out, 1, 4, r)
            out[5].rank = other(rng, r)
            out[5].suit = P.SUITS[rng:random(1, 4)]
        elseif name == "Full House" then
            local a = rng:random(2, 14)
            local b = other(rng, a)
            same_rank(rng, out, 1, 3, a)
            same_rank(rng, out, 4, 2, b)
        elseif name == "Flush" then
            distinct_ranks(rng, out, 1, 5)
            local s = P.SUITS[rng:random(1, 4)]
            for i = 1, 5 do out[i].suit = s end
        elseif name == "Three of a Kind" then
            local a = rng:random(2, 14)
            same_rank(rng, out, 1, 3, a)
            distinct_ranks(rng, out, 4, 5, a)
        elseif name == "Two Pair" then
            local a = rng:random(2, 14)
            local b = other(rng, a)
            same_rank(rng, out, 1, 2, a)
            same_rank(rng, out, 3, 2, b)
            out[5].rank = other(rng, a, b)
            out[5].suit = P.SUITS[rng:random(1, 4)]
        elseif name == "Pair" then
            local a = rng:random(2, 14)
            same_rank(rng, out, 1, 2, a)
            distinct_ranks(rng, out, 3, 5, a)
        else
            distinct_ranks(rng, out, 1, 5)
        end
        if P.eval(out, 5) == name then
            for i = 5, 2, -1 do
                local j = rng:random(1, i)
                out[i].rank, out[j].rank = out[j].rank, out[i].rank
                out[i].suit, out[j].suit = out[j].suit, out[i].suit
            end
            for i = 1, 5 do out[i].key = P.key(out[i].rank, out[i].suit) end
            return true
        end
    end
    return false
end

function P.hand_name(name)
    if localize then
        local ok, s = pcall(localize, name, "poker_hands")
        if ok and type(s) == "string" and s ~= "ERROR" then return s end
    end
    return name
end

return P
