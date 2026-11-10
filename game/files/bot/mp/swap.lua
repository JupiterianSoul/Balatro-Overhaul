local D = require("bot.sim.data")
local E = require("bot.sim.engine")
local ST = require("bot.sim.state")

local X = {}

local SEALS = {"Gold", "Red", "Blue", "Purple"}
local NUMS = {
    {"hand_size", "hand_size"}, {"joker_slots", "joker_limit"}, {"cons_slots", "cons_limit"},
    {"hands", "resets_hands"}, {"discards", "resets_discards"}, {"interest_cap", "interest_cap"},
    {"discount", "discount"}, {"joker_max", "joker_max"}, {"tarot_rate", "tarot_rate"},
    {"planet_rate", "planet_rate"}, {"edition_rate", "edition_rate"}, {"playing_card_rate", "playing_card_rate"},
    {"base_reroll_cost", "base_reroll_cost"},
}
X.NUMS = NUMS

local function ed_key(ed) return ed and ed > 0 and D.ED_KEYS[ed] or nil end

local function num(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    if lo and v < lo then v = lo end
    if hi and v > hi then v = hi end
    return v
end

local function list(t)
    return type(t) == "table" and t or {}
end

function X.export(b)
    local s = b.core.s
    local out = {v = 1, owner = b.sw_owner, dollars = s.money, ante = s.ante,
        jokers = {}, cons = {}, cards = {}, vouchers = {}, levels = {}, tags = {}}
    for _, p in ipairs(NUMS) do out[p[1]] = s[p[2]] end
    local ab = b.sw_ab or {}
    for k = 1, s.n_jok do
        out.jokers[#out.jokers + 1] = {
            k = D.JOKERS[s.j_id[k]].key, ed = ed_key(s.j_ed[k]),
            et = s.j_eternal[k] == 1 or nil, pe = s.j_perish[k] >= 0 and s.j_perish[k] or nil, re = s.j_rental[k] == 1 or nil,
            m = s.j_mult[k], x = s.j_x[k], ex = s.j_ex[k], ev = s.j_ev[k], ab = ab[s.j_uid[k]],
        }
    end
    for _, it in ipairs(b.sw_keep_j or {}) do out.jokers[#out.jokers + 1] = it end
    for i = 1, s.n_cons do out.cons[#out.cons + 1] = {k = s.cons[i], ed = ed_key(s.cons_ed[i])} end
    for _, it in ipairs(b.sw_keep_c or {}) do out.cons[#out.cons + 1] = it end
    for c = 1, s.n_cards do
        if s.c_alive[c] == 1 then
            out.cards[#out.cards + 1] = {
                f = D.SUIT_CHARS[s.c_suit[c]] .. "_" .. D.RANK_CHARS[s.c_rank[c]],
                e = s.c_enh[c] > 0 and D.ENH_KEYS[s.c_enh[c]] or nil, ed = ed_key(s.c_ed[c]),
                s = s.c_seal[c] > 0 and SEALS[s.c_seal[c]] or nil, b = s.c_bonus[c] > 0 and s.c_bonus[c] or nil,
            }
        end
    end
    for vid = 1, #D.VOUCHERS do
        if s.used_v[vid] == 1 then out.vouchers[#out.vouchers + 1] = D.VOUCHERS[vid].key end
    end
    for _, k in ipairs(b.sw_keep_v or {}) do out.vouchers[#out.vouchers + 1] = k end
    for h = 1, D.NUM_HANDS do
        out.levels[D.HAND_NAMES[h]] = {l = s.h_level[h], p = s.h_played[h]}
    end
    for i = 1, s.n_tags do
        if s.tag_trig[i] == 0 then out.tags[#out.tags + 1] = D.TAGS[s.tags[i]].key end
    end
    for _, k in ipairs(b.sw_keep_t or {}) do out.tags[#out.tags + 1] = k end
    return out
end

function X.facts(r)
    local lv = 0
    for _, h in pairs(r.levels or {}) do lv = lv + math.max(0, (tonumber(h.l) or 1) - 1) end
    return {owner = r.owner, ante = r.ante, dollars = r.dollars, deck = #r.cards, jokers = #r.jokers,
        cons = #r.cons, vouchers = #r.vouchers, levels = lv, tags = #r.tags}
end

local function card_ids(e)
    if type(e) ~= "table" or type(e.f) ~= "string" then return nil end
    local sc, rc = e.f:match("^(%a)_(%w)$")
    local suit, rank = sc and D.SUIT_ID[sc], rc and D.RANK_ID[rc]
    if not (suit and rank) then return nil end
    return suit, rank, e.e and D.ENH_ID[e.e] or 0, e.ed and D.ED_ID[e.ed] or 0, e.s and D.SEAL_NAME_ID[e.s] or 0
end

function X.import(b, r)
    local s = b.core.s
    for k = s.n_jok, 1, -1 do E.remove_joker_slot(s, k) end
    b.sw_ab, b.sw_keep_j, b.sw_keep_c, b.sw_keep_v, b.sw_keep_t = {}, {}, {}, {}, {}
    for _, j in ipairs(list(r.jokers)) do
        local key = type(j) == "table" and type(j.k) == "string" and j.k or ""
        local id = D.JOKER_ID[key]
        if id and D.JOKERS[id] then
            local k = E.add_joker(s, id, j.ed and D.ED_ID[j.ed] or 0, {eternal = j.et == true, rental = j.re == true, perish = num(j.pe, 0, 99)})
            s.j_mult[k] = num(j.m) or s.j_mult[k]
            s.j_x[k] = num(j.x, 0) or s.j_x[k]
            s.j_ex[k] = num(j.ex) or s.j_ex[k]
            s.j_ev[k] = num(j.ev, 0) or s.j_ev[k]
            if type(j.ab) == "table" then b.sw_ab[s.j_uid[k]] = j.ab end
        elseif type(j) == "table" then
            b.sw_keep_j[#b.sw_keep_j + 1] = j
        end
    end
    for i = s.n_cons, 1, -1 do s.cons[i], s.cons_ed[i], s.cons_ev[i], s.cons_uid[i] = nil, nil, nil, nil end
    s.n_cons = 0
    for _, c in ipairs(list(r.cons)) do
        local cid = type(c) == "table" and D.CONS_ID and D.CONS_ID[c.k]
        if cid then E.I.add_cons(s, cid, c.ed and D.ED_ID[c.ed] or 0)
        elseif type(c) == "table" then b.sw_keep_c[#b.sw_keep_c + 1] = c end
    end
    local cards = {}
    for _, c in ipairs(list(r.cards)) do
        local suit, rank, enh, ed, seal = card_ids(c)
        if suit then cards[#cards + 1] = {suit, rank, enh or 0, ed or 0, seal or 0, num(c.b, 0) or 0} end
    end
    if #cards > 0 then
        for _, f in ipairs(ST.CARD_ARRAYS) do s[f] = {} end
        s.deck, s.hand, s.disc = {}, {}, {}
        s.n_cards, s.n_deck, s.n_hand, s.n_disc = 0, 0, 0, 0
        for _, c in ipairs(cards) do
            local cid = E.new_card(s, c[2], c[1], c[3], c[4], c[5])
            s.c_bonus[cid] = c[6]
            s.n_deck = s.n_deck + 1
            s.deck[s.n_deck] = cid
        end
    end
    for vid = 1, #D.VOUCHERS do s.used_v[vid] = 0 end
    for _, k in ipairs(list(r.vouchers)) do
        local vid = D.VOUCHER_ID[k]
        if vid then s.used_v[vid] = 1 elseif type(k) == "string" then b.sw_keep_v[#b.sw_keep_v + 1] = k end
    end
    if type(r.levels) == "table" then
        for name, h in pairs(r.levels) do
            local id = D.HAND_ID[name]
            if id and type(h) == "table" then
                local lv = num(h.l, 0, 100000) or s.h_level[id]
                E.level_up(s, id, lv - s.h_level[id])
                s.h_played[id] = num(h.p, 0) or s.h_played[id]
            end
        end
    end
    for i = s.n_tags, 1, -1 do s.tags[i], s.tag_hand[i], s.tag_trig[i] = nil, nil, nil end
    s.n_tags = 0
    for _, k in ipairs(list(r.tags)) do
        local t = D.TAG_ID[k]
        if t then
            s.n_tags = s.n_tags + 1
            s.tags[s.n_tags], s.tag_hand[s.n_tags], s.tag_trig[s.n_tags] = t, 0, 0
        elseif type(k) == "string" then b.sw_keep_t[#b.sw_keep_t + 1] = k end
    end
    s.money = num(r.dollars, -1000, 1e9) or s.money
    for _, p in ipairs(NUMS) do
        local v = num(r[p[1]])
        if v then s[p[2]] = v end
    end
    s.hands_left, s.discards_left = s.resets_hands, s.resets_discards
    b.sw_owner = type(r.owner) == "string" and r.owner:sub(1, 40) or nil
    return true
end

return X
