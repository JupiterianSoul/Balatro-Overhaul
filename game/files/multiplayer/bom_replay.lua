local RP = {}

local function L(s) return mod_loc and mod_loc(s) or s end

RP.V = 5
RP.EXACT_V = 4
RP.ge = 0
RP.evs = 0
RP.FLUSH_S = 1
RP.MIN_GAP_S = 0.25
RP.MAX_IN_BYTES = 3000
RP.MAX_BOOT_BYTES = 16000
RP.MAX_RS_BYTES = 400000
RP.PRE_MAX = 80
RP.RECENT_MAX = 8
RP.BATCH_MAX = 400
RP.SEQ_FILE = "mp_replay_seq.json"

RP.IN_TYPES = {
    match_state_update = true, pvp_resolved = true, ascension_resolved = true, opponent_blind_finished = true,
    blind_finished = true, pvp_result = true, round_end = true, boss_sync = true, start_blind = true,
    ready_blind_rejected = true, ready_blind_kept = true, opponent_ready_blind = true, opponent_unready_blind = true, sabotage = true,
    enemy_info = true, end_pvp = true, set_location = true, ante_timer = true, pvp_timer_paused = true,
    pvp_timer_resumed = true, opponent_deck = true, state_sync = true, party_state = true, party_notice = true,
    party_location = true,
}

RP.ACTION_KINDS = {
    bs = true, sk = true, rb = true, pl = true, di = true, by = true, se = true, rr = true,
    us = true, pk = true, sp = true, co = true, ns = true,
}

function RP.ranks(ids)
    local idx = {}
    for i = 1, #ids do idx[i] = i end
    table.sort(idx, function(a, b)
        if ids[a] == ids[b] then return a < b end
        return ids[a] < ids[b]
    end)
    local out = {}
    for r, i in ipairs(idx) do out[i] = r end
    return out
end

function RP.order_code(ids)
    if type(ids) ~= "table" or #ids < 2 then return nil end
    local r = RP.ranks(ids)
    for i = 1, #r do
        if r[i] ~= i then return r end
    end
    return nil
end

function RP.apply_ranks(items, ranks, id_of)
    if type(ranks) ~= "table" or #ranks ~= #items then return nil end
    local ids = {}
    for i, it in ipairs(items) do ids[i] = id_of(it) end
    local cur = RP.ranks(ids)
    local by_rank = {}
    for i, r in ipairs(cur) do by_rank[r] = items[i] end
    local out, seen = {}, {}
    for i, r in ipairs(ranks) do
        local it = by_rank[r]
        if not it or seen[r] then return nil end
        seen[r] = true
        out[i] = it
    end
    return out
end

function RP.hash(str)
    local h = 2166136261
    for i = 1, #str do
        h = (h * 31 + str:byte(i)) % 4294967296
    end
    return h
end

function RP.hand_hash(hands)
    if type(hands) ~= "table" then return 0 end
    local keys = {}
    for k, v in pairs(hands) do
        if type(v) == "table" and type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts + 1] = k .. ":" .. tostring(tonumber(hands[k].level) or 0)
    end
    return RP.hash(table.concat(parts, ";"))
end

function RP.score_str(v)
    if type(v) == "number" then
        if v ~= v then return "nan" end
        if v == math.huge then return "inf" end
        if math.abs(v) < 1e15 then return string.format("%.0f", v) end
        return string.format("%.6g", v)
    end
    if v == nil then return "0" end
    return tostring(v)
end

function RP.card_sig(c)
    if type(c) ~= "table" then return "" end
    local base = type(c.base) == "table" and c.base or {}
    local center = c.config and c.config.center
    local ed = type(c.edition) == "table" and c.edition.type or ""
    return tostring(base.suit or "") .. "," .. tostring(base.value or "") .. "," .. tostring(type(center) == "table" and center.key or "") .. "," .. tostring(c.seal or "") .. "," .. tostring(ed)
end

function RP.cards_hash(cards)
    if type(cards) ~= "table" then return nil end
    local parts = {}
    for _, c in ipairs(cards) do parts[#parts + 1] = RP.card_sig(c) end
    table.sort(parts)
    return tostring(#parts) .. "." .. tostring(RP.hash(table.concat(parts, ";")))
end

function RP.checksum(st)
    st = st or {}
    return {
        k = "ck",
        a = tonumber(st.ante) or 0,
        r = tonumber(st.round) or 0,
        m = math.floor((tonumber(st.dollars) or 0) + 0.5),
        s = RP.score_str(st.chips),
        h = RP.hand_hash(st.hands),
        j = RP.cards_hash(st.jokers),
        d = RP.cards_hash(st.deck),
    }
end

function RP.compare(rec, cur)
    if type(rec) ~= "table" or type(cur) ~= "table" then return nil end
    for _, f in ipairs({ "a", "r", "m", "s", "h", "j", "d" }) do
        if rec[f] ~= nil and cur[f] ~= nil and tostring(rec[f]) ~= tostring(cur[f]) then return f end
    end
    return nil
end

function RP.ante_of(entries, upto)
    local ante = 1
    for i = 1, math.min(upto or #entries, #entries) do
        local e = entries[i]
        if type(e) == "table" and (e.k == "bs" or e.k == "sk" or e.k == "ck") and tonumber(e.a) then ante = tonumber(e.a) end
    end
    return ante
end

function RP.index_of_ante(entries, ante)
    for i, e in ipairs(entries) do
        if type(e) == "table" and (e.k == "bs" or e.k == "sk") and (tonumber(e.a) or 0) >= ante then return i end
    end
    return nil
end

function RP.max_ante(entries)
    local m = 1
    for _, e in ipairs(entries) do
        if type(e) == "table" and tonumber(e.a) and tonumber(e.a) > m then m = tonumber(e.a) end
    end
    return m
end

function RP.clean(stream)
    local out = {}
    if type(stream) ~= "table" then return out end
    for _, e in ipairs(stream) do
        if type(e) == "table" and type(e.k) == "string" then out[#out + 1] = e end
    end
    return out
end

function RP.playable(stream)
    for _, e in ipairs(RP.clean(stream)) do
        if e.k == "start" then return true end
    end
    return false
end

function RP.pids(streams)
    local out = {}
    if type(streams) ~= "table" then return out end
    for k, s in pairs(streams) do
        local pid = tonumber(k)
        if pid and RP.playable(s) then out[#out + 1] = pid end
    end
    table.sort(out)
    return out
end

function RP.pick_pid(header, streams, my_name, want)
    local pids = RP.pids(streams)
    if #pids == 0 then return nil end
    local has = {}
    for _, p in ipairs(pids) do has[p] = true end
    if want and has[want] then return want end
    local players = type(header) == "table" and header.players or {}
    if my_name then
        for _, p in ipairs(players) do
            if p.name == my_name and has[tonumber(p.pid)] then return tonumber(p.pid) end
        end
    end
    for _, p in ipairs(players) do
        if not p.is_bot and has[tonumber(p.pid)] then return tonumber(p.pid) end
    end
    return pids[1]
end

function RP.new_batcher(seq)
    local b = { seq = seq or 0, buf = {}, last = 0, force = false }
    function b.push(e) b.buf[#b.buf + 1] = e end
    function b.due(now, urgent)
        if #b.buf == 0 then return false end
        if urgent or #b.buf >= RP.BATCH_MAX then return true end
        if b.force then return (now - b.last) >= RP.MIN_GAP_S end
        return (now - b.last) >= RP.FLUSH_S
    end
    function b.take(now)
        if #b.buf == 0 then return nil end
        b.seq = b.seq + 1
        local a, rest = {}, {}
        for i, e in ipairs(b.buf) do
            if i <= RP.BATCH_MAX then a[i] = e else rest[#rest + 1] = e end
        end
        local out = { type = "act", seq = b.seq, a = a }
        b.buf, b.last, b.force = rest, now, #rest > 0
        return out
    end
    return b
end

function RP.merge_live(state, seq, entries)
    state.seq = state.seq or 0
    state.pending = state.pending or {}
    if type(seq) ~= "number" or seq <= state.seq or type(entries) ~= "table" then return 0 end
    state.pending[seq] = entries
    local added = 0
    while state.pending[state.seq + 1] do
        local batch = state.pending[state.seq + 1]
        state.pending[state.seq + 1] = nil
        state.seq = state.seq + 1
        for _, e in ipairs(batch) do
            if type(e) == "table" and type(e.k) == "string" then
                state.entries[#state.entries + 1] = e
                added = added + 1
            end
        end
    end
    return added
end

local REC = { on = false, batch = nil, t0 = 0, match_id = nil, started = false, depth = 0, pre = {}, recent = {}, ge0 = 0, ev0 = 0, eval_depth = 0 }
RP._rec = REC

local function game_events() return RP.ge - (REC.ge0 or 0) end
local function evals() return RP.evs - (REC.ev0 or 0) end

local function clock()
    return (love and love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
end

local function pb()
    local P = rawget(_G, "bom_playback")
    return type(P) == "table" and P or nil
end

local function playing_back()
    local P = pb()
    return P and P.active and P.active() or false
end

local function json()
    return bom_core and bom_core.json
end

local function read_seq(id)
    local ok, out = pcall(function()
        if not (love and love.filesystem and love.filesystem.getInfo(RP.SEQ_FILE)) then return 0 end
        local d = json().decode(love.filesystem.read(RP.SEQ_FILE))
        if type(d) == "table" and d.id == id then return tonumber(d.seq) or 0 end
        return 0
    end)
    return ok and out or 0
end

local function write_seq(id, seq)
    pcall(function()
        require("functions/fast_fs").write(RP.SEQ_FILE, json().encode({ id = id, seq = seq }))
    end)
end

local function ids_of(area)
    local out = {}
    if area and area.cards then
        for i, c in ipairs(area.cards) do out[i] = tonumber(c.sort_id) or i end
    end
    return out
end

local function index_in(area, card)
    if not (area and area.cards) then return nil end
    for i, c in ipairs(area.cards) do
        if c == card then return i end
    end
    return nil
end

local function highlighted(area)
    local out = {}
    if not (area and area.highlighted) then return out end
    for _, c in ipairs(area.highlighted) do
        local i = index_in(area, c)
        if i then out[#out + 1] = i end
    end
    table.sort(out)
    return out
end

function RP.screen_order(area, idxs)
    if not (area and area.cards) or type(idxs) ~= "table" or #idxs < 2 then return nil end
    local xs = {}
    for _, i in ipairs(idxs) do
        local c = area.cards[i]
        if not (c and c.T and tonumber(c.T.x)) then return nil end
        xs[i] = c.T.x
    end
    local out = {}
    for k, i in ipairs(idxs) do out[k] = i end
    table.sort(out, function(a, b)
        if xs[a] ~= xs[b] then return xs[a] < xs[b] end
        return a < b
    end)
    for k = 1, #out do
        if out[k] ~= idxs[k] then return out end
    end
    return nil
end

function RP.area_code(area)
    if not G then return nil end
    if area == G.hand then return "h" end
    if area == G.jokers then return "j" end
    if area == G.consumeables then return "c" end
    if area == G.shop_jokers then return "sj" end
    if area == G.shop_vouchers then return "sv" end
    if area == G.shop_booster then return "sb" end
    if area == G.pack_cards then return "p" end
    return nil
end

function RP.area_of(code)
    if not G then return nil end
    local map = { h = G.hand, j = G.jokers, c = G.consumeables, sj = G.shop_jokers, sv = G.shop_vouchers, sb = G.shop_booster, p = G.pack_cards }
    return map[code]
end

local function with_orders(e, hand)
    if hand and G.hand then e.o = RP.order_code(ids_of(G.hand)) end
    if G.jokers then e.jo = RP.order_code(ids_of(G.jokers)) end
    if G.consumeables then e.ca = RP.order_code(ids_of(G.consumeables)) end
    return e
end

function RP.mods_fp()
    local parts = {}
    pcall(function()
        for _, m in ipairs(bom_core.mod_list() or {}) do parts[#parts + 1] = tostring(m.id) .. "@" .. tostring(m.version or "") end
    end)
    table.sort(parts)
    local s = table.concat(parts, "|")
    if #s > 512 then s = "#" .. tostring(RP.hash(s)) end
    return s
end

local function canon(v, depth)
    if type(v) ~= "table" then return tostring(v) end
    if depth > 8 then return "?" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. canon(v[k], depth + 1) end
    return "{" .. table.concat(out, ",") .. "}"
end

function RP.forge_fp()
    local JF = rawget(_G, "JokerForge")
    local St = JF and JF.store
    local parts = {}
    local ok = pcall(function()
        for _, c in ipairs(G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Joker or {}) do
            if type(c) == "table" and c.forge and not c.forge_lost then
                local made = St and St.get and c.forge_id and St.get(c.forge_id) or nil
                parts[#parts + 1] = tostring(c.key) .. ":" .. (made and canon({ made.rarity, made.cost, made.rules, made.vars }, 0) or "")
            end
        end
    end)
    if not ok then return nil end
    if #parts == 0 then return "0" end
    table.sort(parts)
    return tostring(RP.hash(table.concat(parts, "|")))
end

function RP.tag_needs()
    local out, seen = {}, {}
    local P = G and G.P_CENTERS or {}
    for _, list in ipairs({ G and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Tag or {}, G and G.P_TAGS or {} }) do
        for _, t in pairs(list) do
            local r = type(t) == "table" and t.requires or nil
            if type(r) == "string" and not seen[r] and P[r] then
                seen[r] = true
                if not P[r].discovered then out[#out + 1] = r end
            end
        end
    end
    table.sort(out)
    return out
end

function RP.snapshot()
    if not (G and G.GAME) then return RP.checksum({}) end
    local g = G.GAME
    return RP.checksum({
        ante = g.round_resets and g.round_resets.ante,
        round = g.round,
        dollars = g.dollars,
        chips = g.chips,
        hands = g.hands,
        jokers = G.jokers and G.jokers.cards,
        deck = G.playing_cards,
    })
end

local function plain_ab(v, depth)
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return nil end
        return v
    end
    if t == "string" or t == "boolean" then return v end
    if t ~= "table" or depth > 3 or getmetatable(v) ~= nil then return nil end
    local out, any = {}, false
    for k, x in pairs(v) do
        if type(k) == "string" then
            local p = plain_ab(x, depth + 1)
            if p ~= nil then out[k], any = p, true end
        end
    end
    return any and out or nil
end

function RP.plain_ability(c)
    if type(c) ~= "table" or type(c.ability) ~= "table" then return nil end
    return plain_ab(c.ability, 0)
end

function RP.canon(v) return canon(v, 0) end

function RP.by_sort(cards)
    local list = {}
    for i, c in ipairs(cards or {}) do list[i] = c end
    table.sort(list, function(a, b) return (tonumber(a.sort_id) or 0) < (tonumber(b.sort_id) or 0) end)
    return list
end

function RP.sigs(cards)
    local out = {}
    for i, c in ipairs(RP.by_sort(cards)) do out[i] = RP.card_sig(c) end
    return out
end

function RP.joker_ids(cards)
    local out, n = {}, {}
    for i, c in ipairs(RP.by_sort(cards)) do
        local key = c.config and type(c.config.center) == "table" and c.config.center.key or "?"
        n[key] = (n[key] or 0) + 1
        out[i] = { c = c, id = key .. "#" .. n[key] }
    end
    return out
end

function RP.hand_levels(hands)
    local out = {}
    for k, v in pairs(type(hands) == "table" and hands or {}) do
        if type(k) == "string" and type(v) == "table" and type(v.level) == "number" and type(v.chips) == "number" and type(v.mult) == "number" then
            out[k] = { v.level, v.chips, v.mult, tonumber(v.played) or 0 }
        end
    end
    return out
end

function RP.deck_order(cards)
    if type(cards) ~= "table" or #cards == 0 then return nil end
    local parts = {}
    for i, c in ipairs(cards) do parts[i] = RP.card_sig(c) end
    return RP.hash(table.concat(parts, ";"))
end

function RP.hand_check()
    if not (G and G.GAME and G.hand and G.jokers) then return nil end
    local g = G.GAME
    local last = REC.hk or { hl = {}, ja = {}, rg = {} }
    REC.hk = last
    local e = {
        k = "hk", m = math.floor((tonumber(g.dollars) or 0) + 0.5), s = RP.score_str(g.chips), h = RP.hand_hash(g.hands),
        hd = RP.sigs(G.hand.cards), j = RP.sigs(G.jokers.cards), cs = RP.sigs(G.consumeables and G.consumeables.cards), dk = G.deck and #G.deck.cards or nil,
    }
    local hl = {}
    for k, v in pairs(RP.hand_levels(g.hands)) do
        local c = canon(v, 0)
        if last.hl[k] ~= c then hl[k], last.hl[k] = v, c end
    end
    if next(hl) then e.hl = hl end
    local ja = {}
    for _, x in ipairs(RP.joker_ids(G.jokers.cards)) do
        local ab = RP.plain_ability(x.c)
        local c = ab and canon(ab, 0) or ""
        if ab and last.ja[x.id] ~= c then ja[x.id], last.ja[x.id] = ab, c end
    end
    if next(ja) then e.ja = ja end
    local rg = {}
    for k, v in pairs(type(g.pseudorandom) == "table" and g.pseudorandom or {}) do
        if type(k) == "string" and type(v) == "number" and v == v then
            local c = tostring(v)
            if last.rg[k] ~= c then rg[k], last.rg[k] = v, c end
        end
    end
    if next(rg) then e.rg = rg end
    local rx = {}
    for k in pairs(last.rg) do
        local v = type(g.pseudorandom) == "table" and g.pseudorandom[k]
        if type(v) ~= "number" or v ~= v then rx[#rx + 1] = k end
    end
    table.sort(rx)
    for _, k in ipairs(rx) do last.rg[k] = nil end
    if #rx > 0 then e.rx = rx end
    e.do_ = RP.deck_order(G.deck and G.deck.cards)
    local b = g.blind
    if type(b) == "table" then
        e.b = b.config and type(b.config.blind) == "table" and b.config.blind.key or nil
        e.bc = RP.score_str(b.chips)
    end
    return e
end

local function assign(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            assign(dst[k], v)
        else
            dst[k] = v
        end
    end
end

local function split_sig(s)
    local parts = {}
    for p in (tostring(s) .. ","):gmatch("([^,]*),") do parts[#parts + 1] = p end
    return parts
end

local function sig_diff(want, cards)
    local have = {}
    for _, c in ipairs(cards) do
        local s = RP.card_sig(c)
        have[s] = have[s] or {}
        table.insert(have[s], c)
    end
    local missing = {}
    for _, s in ipairs(want) do
        if have[s] and #have[s] > 0 then table.remove(have[s], 1) else missing[#missing + 1] = s end
    end
    local extra = {}
    for _, c in ipairs(cards) do
        local list = have[RP.card_sig(c)]
        for _, x in ipairs(list or {}) do
            if x == c then extra[#extra + 1] = c break end
        end
    end
    return missing, extra
end

local function match_order(cards, want)
    local list = RP.by_sort(cards)
    if #list ~= #want then return false end
    local ids, used, order = {}, {}, {}
    for i, c in ipairs(list) do ids[i] = c.sort_id end
    for _, s in ipairs(want) do
        for _, c in ipairs(list) do
            if not used[c] and RP.card_sig(c) == s then
                used[c] = true
                order[#order + 1] = c
                break
            end
        end
    end
    if #order ~= #list then return false end
    local moved = false
    for i, c in ipairs(order) do
        if c.sort_id ~= ids[i] then c.sort_id, moved = ids[i], true end
    end
    return true, moved
end

local function make_card(area, s)
    local p = split_sig(s)
    local center = G.P_CENTERS and G.P_CENTERS[p[3] or ""]
    if not (center and center.set and create_card) then return false end
    local card = create_card(center.set, area, nil, nil, true, nil, center.key)
    if not card then return false end
    if card.set_edition then card:set_edition((p[5] or "") ~= "" and { [p[5]] = true } or nil, true, true) end
    card:add_to_deck()
    area:emplace(card)
    return true
end

local function fix_owned(area, want, tag, out)
    if not (area and area.cards and type(want) == "table") then return end
    local missing, extra = sig_diff(want, area.cards)
    if #missing > 0 or #extra > 0 then
        for _, c in ipairs(extra) do pcall(function() c:remove() end) end
        local ok = true
        for _, s in ipairs(missing) do
            local done, made = pcall(make_card, area, s)
            if not (done and made) then ok = false end
        end
        out[#out + 1] = ok and tag or (tag .. "!")
    end
    local same, moved = match_order(area.cards, want)
    if same and moved and #missing == 0 and #extra == 0 then out[#out + 1] = tag .. "o" end
    if area.set_ranks then pcall(area.set_ranks, area) end
end

local function fix_hand(want, out)
    if not (G.hand and G.deck and type(want) == "table") then return end
    local missing, extra = sig_diff(want, G.hand.cards)
    if #missing > 0 or #extra > 0 then
        local ok = #missing == #extra
        pcall(function() G.hand:unhighlight_all() end)
        for i, s in ipairs(missing) do
            local hc = extra[i]
            local j
            for k = #G.deck.cards, 1, -1 do
                if RP.card_sig(G.deck.cards[k]) == s then j = k break end
            end
            local hi
            for k, c in ipairs(G.hand.cards) do if c == hc then hi = k end end
            if not (hc and j and hi) then
                ok = false
            else
                local dc = G.deck.cards[j]
                G.deck.cards[j], G.hand.cards[hi] = hc, dc
                hc.area, dc.area = G.deck, G.hand
                dc.facing, dc.sprite_facing = hc.facing or "front", hc.sprite_facing or "front"
                hc.facing, hc.sprite_facing = "back", "back"
                pcall(function() if G.GAME.blind and G.GAME.blind.debuff_card then G.GAME.blind:debuff_card(dc) end end)
            end
        end
        for _, area in ipairs({ G.hand, G.deck }) do
            pcall(area.set_ranks, area)
            pcall(area.align_cards, area)
        end
        out[#out + 1] = ok and "hd" or "hd!"
    end
    local same, moved = match_order(G.hand.cards, want)
    if same and moved and #missing == 0 and #extra == 0 then out[#out + 1] = "hdo" end
end

function RP.resync(e, exp)
    local out = {}
    if not (G and G.GAME and type(e) == "table") then return out end
    local g = G.GAME
    if tonumber(e.m) and math.floor((tonumber(g.dollars) or 0) + 0.5) ~= tonumber(e.m) then
        g.dollars = tonumber(e.m)
        out[#out + 1] = "m"
    end
    if e.s ~= nil and type(g.chips) == "number" and RP.score_str(g.chips) ~= e.s and tonumber(e.s) then
        g.chips = tonumber(e.s)
        out[#out + 1] = "s"
    end
    local hl_bad = false
    for k, v in pairs(type(exp) == "table" and exp.hl or {}) do
        local h = type(g.hands) == "table" and g.hands[k]
        if type(h) == "table" and type(v) == "table" and canon({ h.level, h.chips, h.mult, tonumber(h.played) or 0 }, 0) ~= canon(v, 0) then
            h.level, h.chips, h.mult, h.played = v[1], v[2], v[3], v[4]
            hl_bad = true
        end
    end
    if hl_bad then out[#out + 1] = "hl" end
    if e.h ~= nil and RP.hand_hash(g.hands) ~= e.h then out[#out + 1] = "h!" end
    fix_owned(G.jokers, e.j, "j", out)
    fix_owned(G.consumeables, e.cs, "c", out)
    local ab_bad = false
    for _, x in ipairs(RP.joker_ids(G.jokers and G.jokers.cards)) do
        local want = type(exp) == "table" and exp.ja and exp.ja[x.id]
        if type(want) == "table" then
            local cur = RP.plain_ability(x.c)
            if not cur or canon(cur, 0) ~= canon(want, 0) then
                assign(x.c.ability, want)
                ab_bad = true
            end
        end
    end
    if ab_bad then out[#out + 1] = "ja" end
    local rg = type(exp) == "table" and exp.rg
    if type(rg) == "table" and next(rg) and type(g.pseudorandom) == "table" then
        local set, drop, first = 0, 0, nil
        for k, v in pairs(rg) do
            if tostring(g.pseudorandom[k]) ~= tostring(v) then
                g.pseudorandom[k], set = v, set + 1
                if not first or k < first then first = k end
            end
        end
        for k, v in pairs(g.pseudorandom) do
            if type(k) == "string" and type(v) == "number" and rg[k] == nil then
                g.pseudorandom[k], drop = nil, drop + 1
                if not first or k < first then first = k end
            end
        end
        if set + drop > 0 then out[#out + 1] = string.format("rng+%d-%d:%s", set, drop, tostring(first)) end
    end
    fix_hand(e.hd, out)
    local b = g.blind
    if type(b) == "table" then
        local key = b.config and type(b.config.blind) == "table" and b.config.blind.key or nil
        if e.b ~= nil and key ~= e.b then out[#out + 1] = "b!" end
        if e.bc ~= nil and type(b.chips) == "number" and RP.score_str(b.chips) ~= e.bc and tonumber(e.bc) then
            b.chips = tonumber(e.bc)
            pcall(function() b.chip_text = number_format(b.chips) end)
            out[#out + 1] = "bc"
        end
    end
    if tonumber(e.dk) and G.deck and #G.deck.cards ~= tonumber(e.dk) then out[#out + 1] = "dk!"
    elseif e.do_ ~= nil and G.deck and RP.deck_order(G.deck.cards) ~= e.do_ then out[#out + 1] = "do!" end
    return out
end

RP.MAKERS = {
    select_blind = function(e)
        local b = e and e.config and e.config.ref_table
        local key = type(b) == "table" and b.key or nil
        return with_orders({ k = "bs", b = key, a = G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante }, false)
    end,
    skip_blind = function()
        return with_orders({ k = "sk", a = G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante }, false)
    end,
    reroll_boss = function()
        if G.from_boss_tag then return nil end
        return with_orders({ k = "rb" }, false)
    end,
    play_cards_from_highlighted = function()
        local hk = RP.hand_check()
        if hk then RP.push(hk) end
        REC.click = { jo = ids_of(G.jokers), h = ids_of(G.hand) }
        local c = highlighted(G.hand)
        return with_orders({ k = "pl", c = c, x = RP.screen_order(G.hand, c) }, true)
    end,
    discard_cards_from_highlighted = function(_, hook)
        if hook then return nil end
        local hk = RP.hand_check()
        if hk then RP.push(hk) end
        local c = highlighted(G.hand)
        return with_orders({ k = "di", c = c, x = RP.screen_order(G.hand, c) }, true)
    end,
    buy_from_shop = function(e)
        local card = e and e.config and e.config.ref_table
        if type(card) ~= "table" then return nil end
        local code = RP.area_code(card.area)
        local i = index_in(card.area, card)
        if not code or not i then return nil end
        return with_orders({ k = "by", w = code, i = i, u = (e.config.id == "buy_and_use") or nil }, false)
    end,
    sell_card = function(e)
        local card = e and e.config and e.config.ref_table
        if type(card) ~= "table" then return nil end
        local code = RP.area_code(card.area)
        local i = index_in(card.area, card)
        if not code or not i then return nil end
        return with_orders({ k = "se", w = code, i = i }, false)
    end,
    reroll_shop = function() return with_orders({ k = "rr" }, false) end,
    use_card = function(e)
        local card = e and e.config and e.config.ref_table
        if type(card) ~= "table" then return nil end
        local code = RP.area_code(card.area)
        if code == "sb" or code == "sv" then
            local i = index_in(card.area, card)
            if not i then return nil end
            return with_orders({ k = "by", w = code, i = i }, false)
        end
        if code ~= "c" and code ~= "p" then return nil end
        local i = index_in(card.area, card)
        if not i then return nil end
        local out = with_orders({ k = code == "p" and "pk" or "us", i = i, ht = highlighted(G.hand) }, true)
        if G.jokers and G.jokers.highlighted and #G.jokers.highlighted > 0 then out.tj = highlighted(G.jokers) end
        out.x = RP.screen_order(G.hand, out.ht)
        if #out.ht == 0 then out.ht = nil end
        return out
    end,
    skip_booster = function() return with_orders({ k = "sp" }, false) end,
    cash_out = function()
        local ck = RP.snapshot()
        RP.push(ck)
        return with_orders({ k = "co" }, false)
    end,
    bom_lose_life_button = function()
        RP.push(RP.snapshot())
        return with_orders({ k = "co", l = 1 }, false)
    end,
    toggle_shop = function()
        if not G.shop then return nil end
        return with_orders({ k = "ns" }, false)
    end,
}

RP.HOOKED = {}

function RP.push(e)
    if not (REC.on and REC.batch) then return end
    if REC.rolls and #REC.rolls > 0 and type(e) == "table" and e.k ~= "rn" then
        local r = REC.rolls
        REC.rolls = nil
        RP.push({ k = "rn", r = r })
    end
    e.t = math.floor((clock() - REC.t0) * 1000)
    REC.batch.push(e)
    if RP.ACTION_KINDS[e.k] or e.k == "ck" or e.k == "end" or e.k == "rs" or e.k == "rl" then REC.batch.force = true end
end

local function wrap(name)
    local cur = G and G.FUNCS and G.FUNCS[name]
    if type(cur) ~= "function" or RP.HOOKED[cur] then return end
    local maker = RP.MAKERS[name]
    local function w(...)
        if REC.on and REC.depth == 0 and maker then
            local ok, e = pcall(maker, ...)
            if ok and type(e) == "table" then RP.push(e) end
        end
        REC.depth = REC.depth + 1
        local res = { xpcall(cur, debug.traceback, ...) }
        REC.depth = REC.depth - 1
        if not res[1] then error(res[2], 0) end
        return unpack(res, 2)
    end
    RP.HOOKED[w] = true
    G.FUNCS[name] = w
end

function RP.follows(before, now)
    local pos = {}
    for i, id in ipairs(before or {}) do pos[id] = i end
    local last = 0
    for _, id in ipairs(now or {}) do
        local p = pos[id]
        if not p or p < last then return false end
        last = p
    end
    return true
end

function RP.before_eval()
    if G and G.GAME and G.GAME.multiplayer then RP.evs = RP.evs + 1 end
    local P = pb()
    if P and P.active and P.active() then
        if P.before_eval then P.before_eval() end
        return
    end
    local click = REC.click
    REC.click = nil
    if not (REC.on and click and G) then return end
    local jo, h = ids_of(G.jokers), ids_of(G.hand)
    if RP.follows(click.jo, jo) and RP.follows(click.h, h) then return end
    RP.push({ k = "eo", jo = RP.order_code(jo), o = RP.order_code(h) })
end

local function wrap_eval()
    local cur = G and G.FUNCS and G.FUNCS.evaluate_play
    if type(cur) ~= "function" or RP.HOOKED[cur] then return end
    local function w(...)
        if REC.eval_depth == 0 then pcall(RP.before_eval) end
        REC.eval_depth = REC.eval_depth + 1
        local res = { xpcall(cur, debug.traceback, ...) }
        REC.eval_depth = REC.eval_depth - 1
        if not res[1] then error(res[2], 0) end
        return unpack(res, 2)
    end
    RP.HOOKED[w] = true
    G.FUNCS.evaluate_play = w
end

RP.ROLLS_MAX = 400

function RP.pick_ident(v, k)
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return "v" .. tostring(v) end
    if t == "table" then
        if type(v.key) == "string" then return "c" .. v.key end
        if v.sort_id ~= nil and v.config and type(v.config.center) == "table" then return "s" .. RP.card_sig(v) end
    end
    return "k" .. tostring(k)
end

function RP.wrap_pick()
    local orig = rawget(_G, "pseudorandom_element")
    if RP._pick_wrapped or type(orig) ~= "function" then return end
    RP._pick_wrapped = true
    pseudorandom_element = function(t, seed, ...)
        local v, k = orig(t, seed, ...)
        if type(seed) ~= "number" or type(t) ~= "table" or v == nil then return v, k end
        local P = pb()
        if P and P.active and P.active() then
            local want = P.recorded_pick and P.recorded_pick(tostring(seed))
            if want and RP.pick_ident(v, k) ~= want then
                for k2, v2 in pairs(t) do
                    if RP.pick_ident(v2, k2) == want then
                        if P.note_pick then pcall(P.note_pick, want) end
                        return v2, k2
                    end
                end
            end
            return v, k
        end
        if REC.on and REC.batch and G and G.GAME then
            REC.rolls = REC.rolls or {}
            if #REC.rolls < RP.ROLLS_MAX then REC.rolls[#REC.rolls + 1] = { tostring(seed), RP.pick_ident(v, k) } end
        end
        return v, k
    end
end

function RP.install_hooks()
    if not (G and G.FUNCS) then return end
    for name in pairs(RP.MAKERS) do wrap(name) end
    wrap_eval()
end

local function bmatch() return rawget(_G, "bom_match") end

local function my_pid()
    local m = bmatch()
    local st = m and m.get_state and m.get_state() or {}
    local P = rawget(_G, "bom_party")
    if P and P.active and P.active() and P.my_pid then
        local ok, v = pcall(P.my_pid)
        if ok and v then return v end
    end
    return tonumber(st.server_player_id) or (m and m.my_seat and select(2, pcall(m.my_seat))) or nil
end

function RP.current_match_id()
    local m = bmatch()
    local st = m and m.get_state and m.get_state() or {}
    return REC.match_id or st.match_id
end

local function in_live_match()
    if playing_back() then return false end
    if not (G and G.GAME and G.GAME.multiplayer) then return false end
    local m = bmatch()
    if not (m and m.get_phase and m.PHASE) then return false end
    local ph = m.get_phase()
    return ph ~= m.PHASE.NONE and ph ~= m.PHASE.LOBBY and ph ~= m.PHASE.MATCH_END
end

function RP.begin(match_id, rejoin, server_seq)
    if not match_id then return end
    if not rejoin and REC.match_id == match_id and REC.batch and not REC.local_only then return end
    local seq = 0
    if rejoin or REC.match_id == match_id then seq = math.max(read_seq(match_id), REC.batch and REC.batch.seq or 0, tonumber(server_seq) or 0) end
    local same = REC.match_id == match_id and REC.batch ~= nil
    if not same then
        REC.started = false
        REC.recent = {}
        REC.last_sync = nil
        REC.hk = nil
        REC.rolls = nil
    end
    local keep = same and REC.batch.buf or {}
    REC.match_id = match_id
    REC.batch = RP.new_batcher(seq)
    for _, e in ipairs(keep) do REC.batch.buf[#REC.batch.buf + 1] = e end
    if not same then REC.t0, REC.ge0, REC.ev0 = clock(), RP.ge, RP.evs end
    REC.on = false
    REC.armed = true
    REC.pre = {}
    REC.rejoin = rejoin and true or nil
    REC.restore_until = nil
end

local function json_copy(v, max)
    local ok, s = pcall(function() return json().encode(v) end)
    if not ok or type(s) ~= "string" or #s > (max or RP.MAX_IN_BYTES) then return nil end
    local ok2, t = pcall(function() return json().decode(s) end)
    return ok2 and t or nil
end

function RP.capture_boot()
    local m = bmatch()
    if not (m and m.get_settings) then return nil end
    local st = m.get_state and m.get_state() or {}
    local b = { set = json_copy(m.get_settings() or {}, RP.MAX_BOOT_BYTES), host = st.is_host and true or false, mode = st.mode }
    pcall(function() b.deck = m.get_my_deck() end)
    local P = rawget(_G, "bom_party")
    if P and P.S and P.active and P.active() then
        b.party = { me = P.S.me, room = json_copy(P.S.room, RP.MAX_BOOT_BYTES) }
    end
    return b
end

local function start_entry()
    local g = G.GAME
    local back = g.selected_back
    local deck = back and back.effect and back.effect.center and back.effect.center.key or nil
    local e = {
        k = "start", v = RP.V, seed = g.pseudorandom and g.pseudorandom.seed, deck = deck,
        deck_name = back and back.name, stake = g.stake, mp_stake = g.mp_stake or g.stake_key,
        pid = my_pid(), mf = RP.mods_fp(), gv = rawget(_G, "OVERHAUL_VERSION"), gn = rawget(_G, "OVERHAUL_NAME"),
    }
    if REC.boot then e.boot, REC.boot = REC.boot, nil end
    pcall(function()
        local nm = bmatch().get_state().my_name
        if type(nm) == "string" and nm ~= "" then e.nm = nm end
    end)
    if g.mp_open_pool then
        e.op = 1
    else
        local nd = RP.tag_needs()
        if #nd > 0 then e.nd = nd end
    end
    return e
end

local function push_pre()
    local pre = REC.pre or {}
    REC.pre = {}
    for _, e in ipairs(pre) do
        if REC.batch then REC.batch.push(e) end
    end
end

function RP.finish(reason)
    if not REC.on then REC.armed = false return end
    RP.push({ k = "end", r = reason })
    RP.flush(true)
    REC.on, REC.armed, REC.restore_until = false, false, nil
end

local function connected()
    if not (bom_core and bom_core.is_connected) then return true end
    local ok, v = pcall(bom_core.is_connected)
    return ok and v and true or false
end

function RP.flush(force)
    if REC.local_only then return end
    if not (REC.batch and bom_core and bom_core.send) then return end
    if force then REC.batch.force = true end
    if not connected() then return end
    local now = clock()
    if not REC.batch.due(now, force) then return end
    local msg = REC.batch.take(now)
    if msg then
        msg.id = REC.match_id
        if bom_core.send(msg) == false then
            REC.batch.seq = msg.seq - 1
            local buf = msg.a
            for _, e in ipairs(REC.batch.buf) do buf[#buf + 1] = e end
            REC.batch.buf = buf
            return
        end
        REC.recent[#REC.recent + 1] = msg
        if #REC.recent > RP.RECENT_MAX then table.remove(REC.recent, 1) end
        write_seq(REC.match_id, msg.seq)
    end
end

function RP.resend_recent()
    if not (bom_core and bom_core.send) or not connected() then return end
    for _, msg in ipairs(REC.recent or {}) do pcall(bom_core.send, msg) end
end

function RP.update()
    pcall(RP.install_hooks)
    if REC.armed and not REC.on and in_live_match() and G.STATE == G.STATES.BLIND_SELECT and G.blind_select then
        REC.on = true
        if REC.started or REC.rejoin then
            RP.push({ k = "rj", ck = RP.snapshot(), g = game_events(), ev = evals() })
        else
            REC.started = true
            REC.ge0, REC.ev0 = RP.ge, RP.evs
            RP.push(start_entry())
        end
        push_pre()
    end
    if REC.restore_until and (in_live_match() or clock() > REC.restore_until) then REC.restore_until = nil end
    if REC.on and not REC.local_only and not in_live_match() then
        local m = bmatch()
        local over = m and m.get_phase and m.get_phase() == m.PHASE.MATCH_END
        if over or (not REC.restore_until and not (G and G.GAME and G.GAME.multiplayer)) then
            RP.finish("over")
            return
        end
    end
    if REC.on then RP.flush(false) end
end

RP._test = {}

function RP.test_record()
    REC.batch = RP.new_batcher(0)
    REC.t0, REC.ge0, REC.ev0 = clock(), RP.ge, RP.evs
    REC.on, REC.armed, REC.local_only, REC.match_id = true, false, true, "local"
end

function RP._test.begin_entry()
    if REC.local_only and REC.on then RP.push(start_entry()) end
end

function RP.test_entries()
    local out = {}
    if REC.batch then for i, e in ipairs(REC.batch.buf) do out[i] = e end end
    REC.on, REC.local_only = false, nil
    return out
end

local function copy_msg(d)
    local ok, s = pcall(function() return json().encode(d) end)
    if not ok or type(s) ~= "string" or #s > RP.MAX_IN_BYTES then return nil end
    local ok2, t = pcall(function() return json().decode(s) end)
    return ok2 and t or nil
end

function RP.note_in(d)
    if type(d) ~= "table" or not RP.IN_TYPES[d.type] then return end
    local pre = REC.armed and not REC.on and REC.batch ~= nil and not REC.local_only
    if not (REC.on or pre) then return end
    local ok, s = pcall(function() return json().encode(d) end)
    if not ok or type(s) ~= "string" or #s > RP.MAX_IN_BYTES then return end
    if d.type == "boss_sync" then
        if s == REC.last_sync then return end
        REC.last_sync = s
    end
    local m = copy_msg(d)
    if not m then return end
    if pre then
        if #REC.pre < RP.PRE_MAX then REC.pre[#REC.pre + 1] = { k = "in", m = m, t = math.floor((clock() - REC.t0) * 1000) } end
        return
    end
    local e = { k = "in", m = m, g = game_events(), ev = evals() }
    if G and G.GAME then
        e.s = G.STATE
        e.sc = RP.score_str(G.GAME.chips)
        e.dl = math.floor((tonumber(G.GAME.dollars) or 0) + 0.5)
    end
    RP.push(e)
end

local function on_start(d)
    if type(d) ~= "table" or not d.match_id or playing_back() then return end
    RP.begin(d.match_id, false)
end

function RP.rejoin_live(d)
    local m = bmatch()
    if not (m and G and G.STAGES and G.STAGE == G.STAGES.RUN and G.GAME and G.GAME.multiplayer) then return false end
    local ok, inm = pcall(function() return m.is_in_match() and not m.is_match_over() end)
    if not (ok and inm) then return false end
    local st = m.get_state and m.get_state() or {}
    return st.room_code == d.code
end

local function without_snapshot(d, keep_snapshot)
    local t = {}
    for k, v in pairs(d) do
        if k ~= "token" and (keep_snapshot or k ~= "snapshot") then t[k] = v end
    end
    return t
end

local function on_rejoin(d)
    if type(d) ~= "table" or not d.match_id or playing_back() then return end
    if RP.rejoin_live(d) and REC.match_id == d.match_id and REC.batch and REC.on then
        local seq = tonumber(d.act_seq)
        if seq and seq > REC.batch.seq then REC.batch.seq = seq end
        local m = json_copy(without_snapshot(d), RP.MAX_BOOT_BYTES)
        if m then RP.push({ k = "rl", m = m, g = game_events(), ev = evals() }) end
        RP.resend_recent()
        REC.batch.force = true
        return
    end
    RP.begin(d.match_id, true, d.act_seq)
    if REC.batch and #REC.batch.buf > 0 then RP.flush(true) end
    local m = json_copy(without_snapshot(d, true), RP.MAX_RS_BYTES)
    if not m then
        m = json_copy(without_snapshot(d), RP.MAX_BOOT_BYTES) or {}
        m.big = true
    end
    REC.started = true
    REC.on, REC.armed = true, false
    REC.restore_until = clock() + 60
    RP.push({ k = "rs", m = m, g = game_events(), ev = evals(), mf = RP.mods_fp() })
    REC.batch.force = true
end

local function on_end()
    if REC.on then RP.finish("over") end
end

RP.pending = nil
RP.status = nil

local function menu() return rawget(_G, "mpm_menu") or (MP and MP.menu) end

local function popup(text)
    pcall(function()
        if attention_text and G and G.ROOM then
            attention_text({ text = text, scale = 0.6, hold = 3, align = "cm", offset = { x = 0, y = -2 }, major = G.ROOM_ATTACH, colour = G.C.RED })
        end
    end)
end
RP.popup = popup

local function busy_in_room()
    if G and G.GAME and G.GAME.multiplayer and not playing_back() then return true end
    local m = bmatch()
    if m and m.get_phase and m.PHASE then
        local ph = m.get_phase()
        if ph ~= m.PHASE.NONE then return true end
    end
    return false
end

function RP.request(id)
    RP.pending = { id = id, at = clock(), stage = G and G.STAGE }
    local function go()
        bom_core.send({ type = "replay_get", id = id, pkey = bom_core.player_key and bom_core.player_key() or nil })
    end
    local m = menu()
    if m and m.with_connection then
        m.with_connection(go, function() RP.pending = nil; popup(L("Could not reach the server.")) end)
    elseif bom_core and bom_core.is_connected and bom_core.is_connected() then
        go()
    else
        RP.pending = nil
        popup(L("Could not reach the server."))
    end
end

function RP.watch(match_id)
    if type(match_id) ~= "string" or match_id == "" then return end
    if playing_back() then return end
    if busy_in_room() then
        RP.after_leave = match_id
        if G.FUNCS.mp_leave_lobby then G.FUNCS.mp_leave_lobby({ config = {} }) end
        return
    end
    RP.request(match_id)
end

function RP.on_replay_data(d)
    if not (RP.pending and d.id == RP.pending.id) then return end
    local asked = RP.pending.stage
    RP.pending = nil
    local P = pb()
    if not P then return end
    if busy_in_room() or (G.STAGES and G.STAGE == G.STAGES.RUN and asked ~= G.STAGES.RUN) then return end
    local streams = type(d.streams) == "table" and d.streams or {}
    local my_name = nil
    pcall(function() my_name = G.PROFILES[G.SETTINGS.profile].name end)
    pcall(function() if bom_match and bom_match.get_state then my_name = bom_match.get_state().my_name or my_name end end)
    local pid = RP.pick_pid(d.header, streams, my_name, tonumber(d.you))
    if not pid then popup(L("No replay for this match")) return end
    pcall(RP.own_name, d.header, tonumber(d.you))
    P.start({ mode = "replay", id = d.id, header = d.header or {}, streams = streams, pid = pid })
end

function RP.own_name(header, you)
    if not (you and type(header) == "table" and type(header.players) == "table") then return end
    local p = G.PROFILES and G.SETTINGS and G.PROFILES[G.SETTINGS.profile]
    local n = p and type(p.name) == "string" and p.name:match("^%s*(.-)%s*$") or ""
    if n == "" or n == "Player" then return end
    for _, pl in ipairs(header.players) do
        if type(pl) == "table" and tonumber(pl.pid) == you and not pl.is_bot then
            pl.rec = pl.rec or pl.name
            pl.name = n
        end
    end
end

RP.ERRORS = {
    live = "This match is still being played.",
    not_found = "No replay for this match",
    private = "This match is private.",
    unavailable = "Replays are not available right now.",
}

function RP.on_replay_error(d)
    if RP.pending and d.id and d.id ~= RP.pending.id then return end
    RP.pending = nil
    popup(L(RP.ERRORS[d.reason] or RP.ERRORS.unavailable))
end

function RP.tick_after_leave()
    if not RP.after_leave then return end
    if busy_in_room() then return end
    if not (G and G.STATE == G.STATES.MENU) then return end
    local id = RP.after_leave
    RP.after_leave = nil
    RP.request(id)
end

function RP.results_button_node(w)
    local id = RP.current_match_id()
    if not id then return nil end
    RP._results_id = id
    return UIBox_button({ id = "mp_watch_replay_btn", button = "mp_watch_replay", label = { L("Watch replay") }, colour = G.C.BLUE,
        minw = w or 3.4, maxw = w or 3.4, minh = (_G._IS_DESKTOP == false) and 0.85 or 0.7, scale = 0.4, focus_args = { nav = "wide" } })
end

function RP.init()
    pcall(RP.install_hooks)
    pcall(RP.wrap_pick)
    local m = bmatch()
    if m and m.set_starting_mp_run and not RP._boot_wrapped then
        RP._boot_wrapped = true
        local orig = m.set_starting_mp_run
        m.set_starting_mp_run = function(...)
            if not playing_back() then
                local ok, b = pcall(RP.capture_boot)
                if ok and b then REC.boot = b end
            end
            return orig(...)
        end
    end
    G.FUNCS.mp_watch_replay = function()
        local id = RP._results_id or RP.current_match_id()
        if id then RP.watch(id) end
    end
    if bom_events and bom_events.register then
        bom_events.register("match_start", on_start)
        bom_events.register("match_session", on_start)
        bom_events.register("rejoin_ok", on_rejoin)
        bom_events.register("match_ended", on_end)
        bom_events.register("match_end", on_end)
        bom_events.register("replay_data", function(d) RP.on_replay_data(d) return true end)
        bom_events.register("replay_error", function(d) RP.on_replay_error(d) return true end)
    end
    if bom_events and bom_events.on_game_event and not RP._ge_wrapped then
        RP._ge_wrapped = true
        local on_game_event = bom_events.on_game_event
        bom_events.on_game_event = function(...)
            if G and G.GAME and G.GAME.multiplayer then RP.ge = RP.ge + 1 end
            return on_game_event(...)
        end
    end
    if bom_events and bom_events.dispatch and not RP._dispatch_wrapped then
        RP._dispatch_wrapped = true
        local orig = bom_events.dispatch
        bom_events.dispatch = function(data)
            local P = pb()
            if P and P.filter_in and P.filter_in(data) then return end
            if type(data) == "table" and (REC.on or REC.armed) then pcall(RP.note_in, data) end
            return orig(data)
        end
    end
end

local function register_strings_1()
    mod_loc_register{
        fr = {
            ["Watch replay"] = "Voir le replay",
            ["No replay for this match"] = "Pas de replay pour ce match",
            ["This match is still being played."] = "Ce match est encore en cours.",
            ["This match is private."] = "Ce match est privé.",
            ["Replays are not available right now."] = "Les replays ne sont pas disponibles pour le moment.",
            ["Could not reach the server."] = "Impossible de joindre le serveur.",
        },
        es = {
            ["Watch replay"] = "Ver repetición",
            ["No replay for this match"] = "No hay repetición de esta partida",
            ["This match is still being played."] = "Esta partida sigue en juego.",
            ["This match is private."] = "Esta partida es privada.",
            ["Replays are not available right now."] = "Las repeticiones no están disponibles ahora.",
            ["Could not reach the server."] = "No se pudo conectar con el servidor.",
        },
    }
end

function RP.register_strings()
    if not mod_loc_register then return end
    register_strings_1()
end

return RP
