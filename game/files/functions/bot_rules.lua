BOT = BOT or {}
BOT.brains = BOT.brains or {}

local R = {}
BOT.rules = R

R.ECON = {["Golden Joker"] = true, ["Egg"] = true, ["To the Moon"] = true, ["Rocket"] = true, ["Cloud 9"] = true,
    ["Delayed Gratification"] = true, ["Business Card"] = true, ["Reserved Parking"] = true, ["Faceless Joker"] = true,
    ["Mail-In Rebate"] = true, ["Satellite"] = true, ["Bull"] = true, ["Gift Card"] = true, ["Rough Gem"] = true}

local function legal_of(state, t, card)
    for _, l in ipairs(state.legal or {}) do
        if l.type == t and (card == nil or l.card == card) then return l end
    end
    return nil
end

local function ids_of(cards, limit)
    local out = {}
    local inhand = {}
    for _, c in ipairs(G.hand and G.hand.cards or {}) do inhand[c] = true end
    for _, c in ipairs(cards or {}) do
        if inhand[c] and c.sort_id and #out < (limit or 5) then out[#out + 1] = c.sort_id end
    end
    return out
end

local function analyze_hand()
    if not (BOT_ENGINE and BOT_ENGINE.analyze) then return nil end
    BOT_ENGINE._last_hash = nil
    local ok = pcall(BOT_ENGINE.analyze)
    if not ok then return nil end
    return BOT_ENGINE.results
end

local function fallback_play(state, n)
    local cards = {}
    for _, c in ipairs(state.hand or {}) do cards[#cards + 1] = c end
    local by_rank = {}
    for _, c in ipairs(cards) do
        local r = c.rank_id or 0
        by_rank[r] = by_rank[r] or {}
        table.insert(by_rank[r], c.id)
    end
    local groups = {}
    for r, l in pairs(by_rank) do groups[#groups + 1] = {r = r, l = l} end
    table.sort(groups, function(a, b)
        if #a.l ~= #b.l then return #a.l > #b.l end
        return a.r > b.r
    end)
    local out = {}
    for _, g in ipairs(groups) do
        for _, id in ipairs(g.l) do if #out < n then out[#out + 1] = id end end
        if #out >= n or #g.l < 2 then break end
    end
    if #out == 0 and cards[1] then out[1] = cards[1].id end
    return out
end

local function card_obj(id)
    return BOT_BRIDGE.card_anywhere(id)
end

local function plain_name(id)
    local c = card_obj(id)
    return c and c.ability and c.ability.name
end

local function use_free_consumable(state)
    for _, l in ipairs(state.legal or {}) do
        if l.type == "use" and not l.targets_min then
            local c = card_obj(l.card)
            if c and c.ability and c.ability.set == "Planet" then
                return {type = "use", card = l.card}, "level up a hand with " .. tostring(l.name)
            end
        end
    end
    return nil
end

function R.aimed_play(res, aim)
    if type(aim) ~= "table" or #aim == 0 or type(res.plays) ~= "table" then return nil end
    local best = res.best_play
    if not (best and best.score) then return nil end
    local want = {}
    for _, h in ipairs(aim) do want[tostring(h):lower()] = true end
    if want[tostring(best.hand_name):lower()] then return nil end
    local need = math.max(0, (tonumber(res.blind_chips) or 0) - (tonumber(res.current_chips) or 0))
    for _, p in ipairs(res.plays) do
        if p.cards and p.score and want[tostring(p.hand_name):lower()] then
            if (need > 0 and p.score >= need) or (best.score < need and p.score >= best.score * 0.85) then return p end
            return nil
        end
    end
    return nil
end

function R.play(state, ctx, opts)
    opts = opts or {}
    local a, why = use_free_consumable(state)
    if a then return a, why end
    local res = analyze_hand()
    local play_l = legal_of(state, "play")
    local disc_l = legal_of(state, "discard")
    if res then
        local best = res.best_play
        if disc_l and res.verdict == "DISCARD FIRST" and res.best_discard and res.best_discard.discard_cards then
            local ids = ids_of(res.best_discard.discard_cards, disc_l.cards_max)
            if #ids > 0 then
                return {type = "discard", cards = ids}, "discard " .. #ids .. " cards, " .. tostring(res.verdict_reason or "aiming for a better hand")
            end
        end
        local aimed = R.aimed_play(res, opts.aim)
        if aimed then best = aimed end
        if play_l and best and best.cards then
            local ids = ids_of(best.cards, play_l.cards_max)
            if #ids > 0 then
                return {type = "play", cards = ids}, "play " .. tostring(best.hand_name or "best hand") .. (res.verdict_reason and (", " .. res.verdict_reason) or "")
            end
        end
    end
    if play_l then
        return {type = "play", cards = fallback_play(state, play_l.cards_max)}, "play the biggest group of ranks"
    end
    if disc_l then
        return {type = "discard", cards = fallback_play(state, 1)}, "playing is blocked, discard"
    end
    return nil
end

local function shop_reserve(state)
    local ante = state.run and state.run.ante or 1
    if ante <= 1 then return 0 end
    return math.min(25, 5 * ante)
end

function R.shop(state, ctx, opts)
    opts = opts or {}
    local a, why = use_free_consumable(state)
    if a then return a, why end
    local money = (state.run and state.run.money or 0) - (state.run and state.run.bankrupt_at or 0)
    local style = ctx.style or {}
    local reserve = opts.reserve or math.max(0, shop_reserve(state) + (style.reserve_add or 0))
    if style.reserve_max then reserve = math.max(reserve, math.min(style.reserve_max, 5 * (state.run and state.run.ante or 1))) end
    ctx.shop_turns = ctx.shop_turns or 0
    if ctx.shop_turns > (opts.max_shop_actions or 10) then return {type = "leave"}, "done shopping" end
    local ratings = {}
    if BOT_ENGINE and BOT_ENGINE.analyze_shop then
        local ok, res = pcall(BOT_ENGINE.analyze_shop)
        if ok and res then
            for _, j in ipairs(res.joker_ratings or {}) do ratings[j.name] = j.rating end
            for _, v in ipairs(res.voucher_ratings or {}) do ratings[v.name] = v.rating end
        end
    end
    local best, best_r = nil, -1
    for _, l in ipairs(state.legal or {}) do
        if l.type == "buy" or l.type == "redeem" then
            local r = ratings[plain_name(l.card)] or 2
            local cobj = card_obj(l.card)
            if style.edition_bonus and cobj and cobj.edition then r = r + style.edition_bonus end
            if style.econ_bonus and cobj and cobj.ability and R.ECON[cobj.ability.name or ""] then r = r + style.econ_bonus end
            local after = money - (l.cost or 0)
            local ok = r >= 5 or (r >= 3 and after >= reserve) or (after >= reserve + 10)
            local is_joker = cobj and cobj.ability and cobj.ability.set == "Joker"
            local few_jokers = #(state.jokers or {}) < math.min(4, (state.run and state.run.joker_slots) or 5)
            if is_joker and few_jokers and after >= 0 then
                ok = true
                r = r + 2
            end
            if l.type == "redeem" and few_jokers and r < 5 then ok = false end
            if l.type == "buy" and cobj and cobj.ability and not is_joker and cobj.ability.set ~= "Planet" then ok = ok and after >= reserve + 5 end
            if ok and r > best_r then best, best_r = l, r end
        end
    end
    if best then
        return {type = best.type, card = best.card}, (best.type == "buy" and "buy " or "redeem ") .. tostring(best.name) .. " (rating " .. best_r .. ")"
    end
    for _, l in ipairs(state.legal or {}) do
        if l.type == "open" and money - (l.cost or 0) >= reserve + 4 and (ctx.packs_this_shop or 0) < (style.max_packs or 1) then
            ctx.packs_this_shop = (ctx.packs_this_shop or 0) + 1
            return {type = "open", card = l.card}, "open " .. tostring(l.name)
        end
    end
    local rr = legal_of(state, "reroll")
    if rr and money - (rr.cost or 0) >= reserve + (style.reroll_margin or 15) and (ctx.rerolls_this_shop or 0) < (style.max_rerolls or 2) then
        ctx.rerolls_this_shop = (ctx.rerolls_this_shop or 0) + 1
        return {type = "reroll"}, "reroll, money to spare"
    end
    return {type = "leave"}, "nothing worth buying"
end

function R.pack(state, ctx)
    local ratings = {}
    if BOT_ENGINE and BOT_ENGINE.analyze_pack then
        local ok, res = pcall(BOT_ENGINE.analyze_pack)
        if ok and res then
            for _, it in ipairs(res.items or {}) do ratings[it.name] = it.rating end
        end
    end
    local best, best_r = nil, -1
    for _, l in ipairs(state.legal or {}) do
        if l.type == "pick" then
            local r = ratings[plain_name(l.card)] or 2
            if l.targets_min and #(state.hand or {}) < l.targets_min then r = -2 end
            if r > best_r then best, best_r = l, r end
        end
    end
    if best and best_r >= 0 then
        local a = {type = "pick", card = best.card}
        if best.targets_min then
            a.targets = {}
            local hand = state.hand or {}
            for i = 1, math.min(best.targets_max, #hand) do a.targets[i] = hand[i].id end
        end
        return a, "take " .. tostring(best.name) .. " (rating " .. best_r .. ")"
    end
    return {type = "skip"}, "nothing useful in the pack"
end

BOT.brains.rules = function(state, ctx)
    local phase = state.phase
    if phase ~= "shop" then ctx.packs_this_shop = 0 ctx.rerolls_this_shop = 0 end
    if phase == "blind_select" then
        local can_skip = false
        for _, l in ipairs(state.legal or {}) do
            if l.type == "ready" then return {type = "ready"}, "ready for the PvP blind" end
            if l.type == "skip" then can_skip = true end
        end
        local style = ctx.style or {}
        if can_skip and style.skip_blinds and (state.run and state.run.ante or 1) <= (style.skip_until_ante or 8) and state.blind_on_deck ~= "Boss" then
            ctx.skips = (ctx.skips or 0) + 1
            if ctx.skips % 2 == 1 then return {type = "skip"}, "skip for the tag" end
        end
        return {type = "select"}, "play the blind"
    elseif phase == "play" then
        return R.play(state, ctx)
    elseif phase == "shop" then
        return R.shop(state, ctx)
    elseif phase == "pack" then
        return R.pack(state, ctx)
    elseif phase == "round_eval" then
        return {type = "cash_out"}, "cash out"
    elseif phase == "win" then
        return {type = "endless"}, "keep going in endless"
    elseif phase == "game_over" then
        return {type = "new_run"}, "try again"
    end
    return nil
end
