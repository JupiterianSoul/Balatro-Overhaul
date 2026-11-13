local lib_mode, lib_root = ...
local LIB = lib_mode == "--lib"
local root = LIB and lib_root or (arg and arg[1]) or "."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local json = require("bot.sim.json")
local C = require("bot.ingame.core")
local PL = require("bot.seer.play")
local D = require("bot.sim.data")
local E = require("bot.sim.engine")
local ST = require("bot.sim.state")
local SW = require("bot.mp.swap")

local function wall_clock()
    local okf, ffi = pcall(require, "ffi")
    if not okf then return os.clock end
    pcall(ffi.cdef, "typedef struct { long tv_sec; long tv_nsec; } bot_mp_ts;")
    pcall(ffi.cdef, "int clock_gettime(int clk, bot_mp_ts *tp);")
    local okt, ts = pcall(ffi.new, "bot_mp_ts")
    if not okt then return os.clock end
    local lib = ffi.C
    local okc, rc = pcall(function() return lib.clock_gettime(1, ts) end)
    if not okc or rc ~= 0 then return os.clock end
    return function()
        lib.clock_gettime(1, ts)
        return tonumber(ts.tv_sec) + tonumber(ts.tv_nsec) * 1e-9
    end
end

local now = wall_clock()
PL.now = now

local wfile = io.open(root .. "/" .. C.WEIGHTS, "rb")
if wfile then
    wfile:close()
    C.WEIGHTS = root .. "/" .. C.WEIGHTS
end

local SCALE = tonumber(os.getenv("BOT_TIME_SCALE") or "") or 1
local LEVELS = {
    easy = {budget = "normal", slip = 0, soft = 0.25, hand = 0.4, pick = 0.3, shop = 2.5, spend = {keep = 0.4, slack = 8, max = 4}},
    medium = {budget = "deep", slip = 0, soft = 1.2, hand = 2, pick = 1.2, shop = 8, spend = {keep = 1, slack = 8, max = 4}},
    hard = {kind = "w14", budget = os.getenv("BOT_HARD_BUDGET") or "fast", slip = 0, soft = 2.5, hand = 3.5, pick = 3, shop = 18, spend = {keep = 1, slack = 5, max = 5}},
}
local SPEND_TYPES = {buy = true, buy_and_use = true, redeem = true, open = true, reroll = true}
local SAVERS = {j_bull = true, j_bootstraps = true}
local BLIND = {"S", "B", "L"}
local RESERVE = 0.02
local LOAD_MAX = 20
local MAX_STEPS = 600
local STOPS = {shop = true, pack = true, blind_select = true}
local MP_BANS = {"j_mr_bones", "j_luchador", "j_matador", "j_chicot", "v_hieroglyph", "v_petroglyph", "v_directors_cut", "v_retcon", "tag_boss", "bl_wall", "bl_final_vessel"}

local bots = {}
local describe

local function spend_keep(sp, s)
    if not sp or s.phase ~= "shop" then return nil end
    for k = 1, s.n_jok do
        local j = D.JOKERS[s.j_id[k]]
        if j and SAVERS[j.key] then return nil end
    end
    local keep = s.no_interest == 1 and 0 or math.floor(s.interest_cap * sp.keep)
    if s.money <= keep + sp.slack then return nil end
    return keep
end

local function spend_cost(s, a)
    local c = ST.clone(s)
    if not E.step(c, C.copy_action(a)) then return nil end
    return s.money - c.money
end

local function spend(b, s, why)
    local sp = b.spend
    if not sp or (b.spends or 0) >= sp.max then return nil end
    local keep = spend_keep(sp, s)
    if not keep then return nil end
    local cands = {}
    local mc = b.core.mc
    if mc and (why == "rollouts" or why == "net") then
        local ef, ec = mc:root_edges()
        local order = {}
        for i = 0, ec - 1 do order[i + 1] = ef + i end
        table.sort(order, function(x, y)
            if mc.e_N[x] ~= mc.e_N[y] then return mc.e_N[x] > mc.e_N[y] end
            if mc.e_prior[x] ~= mc.e_prior[y] then return mc.e_prior[x] > mc.e_prior[y] end
            return x < y
        end)
        for _, e in ipairs(order) do
            local a = C.clean(mc:edge_action(e, {type = "play", cards = {}}, s))
            if SPEND_TYPES[a.type] then cands[#cands + 1] = a end
        end
    end
    for p = 1, s.n_sj do cands[#cands + 1] = {type = "buy", card = p} end
    for p = 1, s.n_sv do cands[#cands + 1] = {type = "redeem", card = p} end
    for p = 1, s.n_sb do cands[#cands + 1] = {type = "open", card = p} end
    cands[#cands + 1] = {type = "reroll"}
    local full = s.n_jok >= s.joker_limit
    for _, a in ipairs(cands) do
        local bd = a.type == "open" and D.BOOST[s.sb_id[a.card]]
        local cost = not (full and bd and bd.kind == "Buffoon") and spend_cost(s, a)
        if cost and cost > 0 and s.money - cost >= keep then
            b.spends = (b.spends or 0) + 1
            return a
        end
    end
    return nil
end

local function act(b, stop_at, per, soft)
    local s = b.core.s
    if b.econ_slip and (s.phase == "shop" or s.phase == "pack") and math.random() < b.econ_slip then
        local a = {type = s.phase == "shop" and "leave" or "skip"}
        if b.core:legal(a) then return a end
    end
    if s.phase == "play" and b.slip > 0 and math.random() < b.slip then
        local ok, a = pcall(PL.fast_action, s, true)
        if ok and a and b.core:legal(a) then return C.clean(a) end
    end
    local t, c0 = now(), os.clock()
    local k = b.load or 1
    local hard = math.min(t + (per or math.huge) / k, stop_at or math.huge)
    PL.deadline, PL.hard = math.min(t + (soft or b.soft) / k, hard), hard - RESERVE
    local a, why
    if t >= PL.hard and s.phase == "play" then
        a, why = C.fallback(s), "out of time"
        if not (a and b.core:legal(a)) then a, why = b.core:decide() else a = C.clean(a) end
    else
        a, why = b.core:decide()
    end
    PL.deadline, PL.hard = math.huge, math.huge
    local w, c = now() - t, os.clock() - c0
    if w > 0.005 then
        local r = math.min(LOAD_MAX, math.max(1, w / math.max(c, 0.001)))
        b.load = (b.load or 1) * 0.7 + r * 0.3
    end
    if s.phase ~= "shop" and s.phase ~= "pack" then b.spends = 0 end
    if a and a.type == "leave" and s.phase == "shop" then
        local ok, sa = pcall(spend, b, s, why)
        if ok and sa then return sa, "spend" end
    end
    return a, why
end

local NNF = require("bot.nn.features")
local SHOP_MOVES_MAX = 2

local function step(b, stop_at, per, soft)
    local s = b.core.s
    local ph = s.phase
    if ph == "blind_select" then b.next_blind = s.blind_on_deck end
    if ph == "blind_select" or ph == "play" then b.shop_moves = 0 end
    NNF.SHOP_MOVES = (b.shop_moves or 0) < SHOP_MOVES_MAX
    local a, why = act(b, stop_at, per, soft)
    NNF.SHOP_MOVES = true
    if not a then return false end
    if ph == "shop" and a.type == "reorder_jokers" then b.shop_moves = (b.shop_moves or 0) + 1 end
    if ph == "blind_select" and a.type == "select" then b.blind = BLIND[b.next_blind] or "L" end
    if a.type == "play" and b.capture then
        local played = {}
        for i, p in ipairs(a.cards or {}) do if s.hand[p] then played[i] = b.capture(s, s.hand[p]) end end
        b.played = played
    end
    local note = ph ~= "play" and describe(s, a) or nil
    local ok = b.core:step(a)
    if note then
        if why == "spend" then note.spend = true end
        note.cost = note.money - s.money
        note.money = s.money
        note.jokers = s.n_jok
        note.phase = s.phase
        if a.type == "leave" then
            note.held = {}
            for k = 1, s.n_jok do note.held[k] = D.JOKERS[s.j_id[k]].key end
        end
    end
    return ok, a, note
end

local function next_key(s)
    local d = s.blind_on_deck or 1
    if d == 1 then return "bl_small" end
    if d == 2 then return "bl_big" end
    local bd = s.boss_choice and D.BLINDS[s.boss_choice]
    return bd and bd.key or nil
end

local H = {}

function H.new(m)
    local lv = LEVELS[m.level] or LEVELS.medium
    local core = C.new(lv.kind or "hybrid", {seed = m.seed, deck = m.deck, stake = m.stake}, lv.budget, nil, "GAME" .. tostring(m.bot))
    core.s.mp = 1
    local ban = {}
    for _, k in ipairs(MP_BANS) do ban[k] = true end
    core.s.ban = ban
    if ban[D.VOUCHERS[core.s.voucher].key] then core.s.voucher = E.get_next_voucher(core.s) end
    if tonumber(m.win_ante) then core.s.win_ante = tonumber(m.win_ante) end
    local added = {}
    for _, key in ipairs(type(m.jokers) == "table" and m.jokers or {}) do
        if type(key) == "string" and D.JOKER_ID[key] and core.s.n_jok < core.s.joker_limit then
            E.add_joker(core.s, key)
            added[#added + 1] = key
        end
    end
    for _ = 1, math.min(5, math.max(0, math.floor(tonumber(m.random_jokers) or 0))) do
        if core.s.n_jok >= core.s.joker_limit then break end
        E.I.create_into(core.s, 1, nil, nil, nil, "rr_jok")
        added[#added + 1] = D.JOKERS[core.s.j_id[core.s.n_jok]].key
    end
    local h = 0
    for i = 1, #tostring(m.bot) do h = (h * 31 + tostring(m.bot):byte(i)) % 1000003 end
    math.randomseed(os.time() + h)
    local function sec(v) return (v or math.huge) * SCALE end
    bots[m.bot] = {core = core, deck = m.deck, slip = lv.slip or 0, econ_slip = lv.econ_slip, soft = sec(lv.soft), hand = sec(lv.hand),
        pick = sec(lv.pick), shop = sec(lv.shop), spend = lv.spend, blind = "S", capture = function(st, cid) return H.pcard(st, cid) end}
    return {ok = true, jokers = added}
end

function H.warm()
    if not C.shared_w then C.shared_w = require("bot.nn.weights").load(C.WEIGHTS) end
    return {ok = true}
end

function H.advance(m)
    local b = bots[m.bot]
    if not b then return {ok = false, err = "no bot"} end
    local s = b.core.s
    local fair = b.core.fair
    local worlds = fair and fair.o.worlds
    b.spent = b.spent or 0
    local r
    local acts, log = 0, {}
    if s.phase ~= "play" then s.mp_pvp = 0 end
    for _ = 1, MAX_STEPS do
        local ph = s.phase
        if ph == "game_over" or ph == "win" then r = {ok = true, done = true} break end
        if ph == "play" then
            s.mp_pvp = m.pvp and 1 or 0
            r = {ok = true, ante = s.ante, blind = b.blind, blind_key = s.blind > 0 and D.BLINDS[s.blind].key or nil,
                hands = s.hands_left, discards = s.discards_left, target = s.blind_chips, money = s.money}
            b.seen, b.spent = nil, 0
            break
        end
        if m.one and acts > 0 then r = {ok = true, more = true, ante = s.ante} break end
        if m.stops and STOPS[ph] and b.seen ~= ph then
            b.seen = ph
            r = {ok = true, stop = ph, ante = s.ante, blind = BLIND[s.blind_on_deck] or "L", blind_key = next_key(s)}
            break
        end
        if STOPS[ph] then b.seen = ph end
        local left = b.shop - b.spent
        if left <= 0 then
            if fair then fair.o.worlds = 1 end
            b.core.ro_off = true
            b.core.cheap = true
        end
        local t0 = now()
        local ok, _, note = step(b, t0 + math.max(left, 0) / (b.load or 1), b.pick, b.pick)
        b.spent = b.spent + now() - t0
        if not ok then r = {ok = false, err = "stuck in " .. tostring(s.phase)} break end
        acts = acts + 1
        log[acts] = note
    end
    if fair then fair.o.worlds = worlds end
    b.core.ro_off = false
    b.core.cheap = false
    r = r or {ok = false, err = "too many steps"}
    r.acts = acts
    if m.one then r.act = log[1] else r.log = log end
    return r
end

function H.pvp(m)
    local b = bots[m.bot]
    if not b then return {ok = false, err = "no bot"} end
    b.core.s.mp_pvp = m.on and 1 or 0
    return {ok = true}
end

local function hand_steps(m, b, s, fair)
    local stop_at = now() + b.hand
    local discards = 0
    for _ = 1, 40 do
        if fair and now() > stop_at then fair.o.worlds = 1 end
        local ok, a = step(b, stop_at, b.hand)
        if not ok then return {ok = false, err = "no action"} end
        if a and a.type == "discard" then discards = discards + 1 end
        if s.phase ~= "play" or (a and a.type == "play") then
            local over = s.phase ~= "play"
            local lost = s.mp_lost == 1
            if over then s.mp_lost = 0 s.mp_pvp = 0 end
            local bd = H.board({bot = m.bot, where = "blind"}).board
            if bd then
                bd.played = b.played or {}
                local lh = s.last_hand
                bd.hand_name = type(lh) == "number" and D.HAND_NAMES[lh] or lh
                bd.hand_level = lh and s.h_level[lh] or nil
                bd.hand_chips = s.last_chips
                bd.hand_mult = s.last_mult
                bd.chips = s.chips
            end
            return {ok = true, chips = s.chips, hands_left = over and 0 or s.hands_left, discards_left = over and 0 or s.discards_left, over = over, lost = lost, board = bd, discards = discards}
        end
    end
    return {ok = false, err = "no hand played"}
end

function H.hand(m)
    local b = bots[m.bot]
    if not b then return {ok = false, err = "no bot"} end
    local s = b.core.s
    if s.phase ~= "play" then return {ok = false, err = "not playing"} end
    local fair = b.core.fair
    local worlds = fair and fair.o.worlds
    local r = hand_steps(m, b, s, fair)
    if fair then fair.o.worlds = worlds end
    return r
end

local SEAL = {"Gold", "Red", "Blue", "Purple"}

local function pcard(s, cid)
    local r = D.RANK_CHARS[s.c_rank[cid]]
    return {
        i = cid,
        k = D.SUIT_CHARS[s.c_suit[cid]] .. "_" .. r,
        e = s.c_enh[cid] > 0 and D.ENH_KEYS[s.c_enh[cid]] or nil,
        d = s.c_ed[cid] > 0 and D.ED_KEYS[s.c_ed[cid]] or nil,
        s = s.c_seal[cid] > 0 and SEAL[s.c_seal[cid]] or nil,
    }
end

local function item(s, kind, id, cid, ed)
    if kind == E.K_CARD then return pcard(s, cid) end
    local key = kind == E.K_JOKER and D.JOKERS[id].key or D.CONS[id].key
    return {c = key, d = ed and ed > 0 and D.ED_KEYS[ed] or nil}
end

function H.board(m)
    local b = bots[m.bot]
    if not b then return {ok = false, err = "no bot"} end
    local s = b.core.s
    if m.where == "shop" and s.phase == "round_eval" then step(b) end
    local out = {where = s.phase == "shop" and "shop" or "blind", ante = s.ante, chips = s.chips, target = s.blind_chips,
        hands = s.hands_left, discards = s.discards_left, money = s.money, deck = s.n_deck,
        blind = s.blind > 0 and D.BLINDS[s.blind].key or nil, jokers = {}, cons = {}, hand = {}}
    for k = 1, s.n_jok do out.jokers[k] = {c = D.JOKERS[s.j_id[k]].key, d = s.j_ed[k] > 0 and D.ED_KEYS[s.j_ed[k]] or nil} end
    for i = 1, s.n_cons do out.cons[i] = {c = s.cons[i]} end
    if out.where == "blind" then
        for i = 1, s.n_hand do out.hand[i] = pcard(s, s.hand[i]) end
    else
        out.shop = {}
        for i = 1, s.n_sj do out.shop[#out.shop + 1] = item(s, s.sj_kind[i], s.sj_id[i], s.sj_cid[i], s.sj_ed[i]) end
        for i = 1, s.n_sv do out.shop[#out.shop + 1] = {c = D.VOUCHERS[s.sv_id[i]].key} end
        for i = 1, s.n_sb do out.shop[#out.shop + 1] = {c = D.BOOST[s.sb_id[i]].key} end
    end
    return {ok = true, board = out}
end

describe = function(s, a)
    local t, p = a.type, a.card
    local note = {type = t, money = s.money, ante = s.ante, from = s.phase}
    local ok, key = pcall(function()
        if (t == "buy" or t == "buy_and_use") and s.sj_kind[p] then
            local it = item(s, s.sj_kind[p], s.sj_id[p], s.sj_cid[p], s.sj_ed[p])
            return it.c or it.k
        elseif t == "redeem" and s.sv_id[p] then return D.VOUCHERS[s.sv_id[p]].key
        elseif t == "open" and s.sb_id[p] then return D.BOOST[s.sb_id[p]].key
        elseif t == "sell" and a.area == "consumables" then return s.cons[p]
        elseif t == "sell" and s.j_id[p] then return D.JOKERS[s.j_id[p]].key
        elseif t == "use" then return s.cons[p]
        elseif t == "pick" and s.pk_kind[p] then
            local it = item(s, s.pk_kind[p], s.pk_id[p], s.pk_cid[p], s.pk_ed[p])
            return it.c or it.k
        end
    end)
    note.key = ok and key or nil
    return note
end

local function ed_type(ed) return ed and ed > 0 and D.ED_KEYS[ed]:sub(3) or nil end

function H.end_data(m)
    local b = bots[m.bot]
    if not b then return {ok = false, err = "no bot"} end
    local s = b.core.s
    local jokers, cards = {}, {}
    for k = 1, s.n_jok do jokers[k] = {k = D.JOKERS[s.j_id[k]].key, ed = ed_type(s.j_ed[k])} end
    for c = 1, s.n_cards do
        if s.c_alive[c] == 1 then
            local p = pcard(s, c)
            cards[#cards + 1] = {f = p.k, e = p.e, ed = ed_type(s.c_ed[c]), s = p.s}
        end
    end
    return {ok = true, jokers = jokers, deck = {back = b.deck, cards = cards}}
end

function H.swap(m)
    local b = bots[m.bot]
    if not b then return {ok = false, err = "no bot"} end
    local s = b.core.s
    if s.phase == "round_eval" then step(b) end
    if s.phase ~= "shop" and s.phase ~= "blind_select" then return {ok = false, err = "not at a swap point: " .. tostring(s.phase)} end
    b.sw_owner = b.sw_owner or (type(m.name) == "string" and m.name or nil)
    local mine = SW.export(b)
    if type(m.run) == "table" then SW.import(b, m.run) end
    return {ok = true, run = mine, facts = SW.facts(mine), phase = s.phase}
end

function H.swap_facts(m)
    local b = bots[m.bot]
    if not b then return {ok = false, err = "no bot"} end
    if b.core.s.phase == "round_eval" then step(b) end
    b.sw_owner = b.sw_owner or (type(m.name) == "string" and m.name or nil)
    local r = SW.export(b)
    return {ok = true, run = r, facts = SW.facts(r)}
end

function H.save(m)
    local b = bots[m.bot]
    if not b then return {ok = false, err = "no bot"} end
    return {ok = true, run = SW.export(b)}
end

function H.resume(m)
    local made = H.new(m)
    local b = bots[m.bot]
    local s = b.core.s
    if type(m.run) == "table" then SW.import(b, m.run) end
    local ante = math.max(1, math.floor(tonumber(m.ante) or 1))
    local n = math.max(1, math.min(3, math.floor(tonumber(m.blind_n) or 1)))
    if s.phase == "blind_select" and (ante > 1 or n > 1) then
        s.ante, s.blind_ante = ante, ante
        s.round = (ante - 1) * 3 + n - 1
        s.blind_on_deck = n
        s.state_small = n == 1 and 1 or 3
        s.state_big = n == 2 and 1 or (n == 3 and 3 or 0)
        s.state_boss = n == 3 and 1 or 0
        s.boss_choice = E.get_new_boss(s)
    end
    made.ante, made.blind_n, made.phase = s.ante, s.blind_on_deck, s.phase
    return made
end

H.pcard = pcard

function H.drop(m)
    bots[m.bot] = nil
    return {ok = true}
end

H.spend_keep = spend_keep
H.MP_BANS = MP_BANS
H.LEVELS = LEVELS
H.now = now
H.bots = bots

if LIB then return H end

io.stdout:setvbuf("line")
for line in io.stdin:lines() do
    local okd, m = pcall(json.decode, line)
    local r
    local t0, w0 = os.clock(), now()
    if okd and type(m) == "table" and H[m.cmd] then
        local ok, res = pcall(H[m.cmd], m)
        r = ok and res or {ok = false, err = tostring(res)}
    else
        r = {ok = false, err = "bad message"}
    end
    r.id = okd and type(m) == "table" and m.id or nil
    r.cpu_ms = math.floor((os.clock() - t0) * 1000 + 0.5)
    r.wall_ms = math.floor((now() - w0) * 1000 + 0.5)
    io.stdout:write(json.encode(r), "\n")
end
