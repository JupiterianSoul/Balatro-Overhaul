BOT = BOT or {}
BOT.brains = BOT.brains or {}
BOT.WAIT = BOT.WAIT or {}

local M = {}
BOT.sim = M

local json_ok, json = pcall(require, "bot.sim.json")

local function L(s)
    if mod_loc then return mod_loc(s) end
    return s
end

M.KINDS = {w14 = "w16", seer = "Seer"}
M.BUDGETS = {"fast", "normal", "deep"}
M.LIMITS = {fast = 8, normal = 25, deep = 90}
M.SAFETY = 600
M.VANILLA_DECKS = {b_red = true, b_blue = true, b_yellow = true, b_green = true, b_black = true, b_magic = true, b_nebula = true,
    b_ghost = true, b_abandoned = true, b_checkered = true, b_zodiac = true, b_painted = true, b_anaglyph = true, b_plasma = true, b_erratic = true}
M.MAPPED = {select = true, skip = true, reroll_boss = true, play = true, discard = true, use = true, sell = true, reorder_jokers = true,
    buy = true, buy_and_use = true, redeem = true, open = true, pick = true, reroll = true, leave = true, cash_out = true}

M.next_id = 0
M.run = nil
M.launch = nil

local function budget()
    local b = BOT.config and BOT.config.get and BOT.config.get("sim_budget") or "normal"
    if not M.LIMITS[b] then b = "normal" end
    return b
end

local function ensure_thread()
    if M.thread and M.thread:isRunning() then return true end
    if M.thread then
        local err = M.thread:getError()
        M.thread = nil
        if err then return false, err end
    end
    local ok, th = pcall(love.thread.newThread, "functions/bot_sim_thread.lua")
    if not ok or not th then return false, tostring(th) end
    love.thread.getChannel("bot_sim_req"):clear()
    love.thread.getChannel("bot_sim_res"):clear()
    M.thread = th
    th:start()
    return true
end

local function send(msg)
    M.next_id = M.next_id + 1
    msg.id = M.next_id
    love.thread.getChannel("bot_sim_req"):push(json.encode(msg))
    return msg.id
end

function M.mark_launch()
    M.launch = {old = G.GAME, at = love.timer.getTime()}
    M.run = nil
end

local function is_modded(c)
    return type(c) == "table" and (c.mod ~= nil or c.original_mod ~= nil)
end

function M.vanilla_check()
    local g = G.GAME
    if not g then return false, "no run" end
    if g.modded_run then return false, "modded run" end
    if g.challenge then return false, "challenge run" end
    if g.run_rules and next(g.run_rules) then return false, "custom run rules" end
    for _, set in ipairs({"Joker", "Back", "Voucher", "Tarot", "Planet", "Spectral", "Booster"}) do
        for _, c in ipairs((G.P_CENTER_POOLS and G.P_CENTER_POOLS[set]) or {}) do
            if is_modded(c) then return false, "mods are loaded" end
            if (set == "Joker" or set == "Voucher") and c.unlocked == false then return false, "needs every joker and voucher unlocked" end
        end
    end
    local key = g.selected_back and g.selected_back.effect and g.selected_back.effect.center and g.selected_back.effect.center.key
    if not M.VANILLA_DECKS[key] then return false, "not a vanilla deck" end
    local stake = tonumber(g.stake) or 1
    if stake < 1 or stake > 8 then return false, "not a vanilla stake" end
    local seed = g.pseudorandom and g.pseudorandom.seed
    if type(seed) ~= "string" or seed == "" then return false, "no seed" end
    if (g.round_resets and g.round_resets.ante or 1) ~= 1 or (g.round or 0) ~= 0 then return false, "run already started" end
    return true, {seed = seed, deck = key, stake = stake}
end

local function note(text)
    BOT.note("sim", text)
end

local function fail(R, why)
    if R.failed then return end
    R.failed = why
    M.failed_reason = why
    if BOT.ui and BOT.ui.set_reasoning then
        BOT.ui.set_reasoning(L("w16 cannot play this run:") .. " " .. tostring(why) .. "\n" .. L("The simple brain plays instead, it is much weaker."))
    end
    BOT.thinking_since = nil
    note(string.format("%s: %s, %s", M.KINDS[R.kind] or R.kind, why, L("the offline brain plays the rest of the run")))
    print("[Bot-latro sim] " .. tostring(R.kind) .. " fallback: " .. tostring(why))
end

local function start(kind)
    M.failed_reason = nil
    local R = {kind = kind, game = G.GAME, budget = budget()}
    M.run = R
    local ok, info = M.vanilla_check()
    if not ok then
        R.failed = info
        note(string.format("%s: %s (%s), %s", M.KINDS[kind], L("needs a fresh vanilla run it started itself"), L(info), L("the offline brain plays instead")))
        return R
    end
    if not json_ok then
        fail(R, "cannot load the sim: " .. tostring(json))
        return R
    end
    local tok, terr = ensure_thread()
    if not tok then
        fail(R, "thread error: " .. tostring(terr))
        return R
    end
    local os_name = love.system and love.system.getOS and love.system.getOS() or ""
    R.setup = info
    R.wait = send({cmd = "new", kind = kind, setup = info, budget = R.budget, noffi = os_name == "Android" or os_name == "iOS"})
    R.since = love.timer.getTime()
    BOT.thinking_since = R.since
    note(string.format("%s: %s %s, %s, %s %d", M.KINDS[kind], L("mirrors seed"), info.seed, info.deck, L("stake"), info.stake))
    return R
end

local function poll(R)
    local ch = love.thread.getChannel("bot_sim_res")
    while true do
        local raw = ch:pop()
        if not raw then break end
        local okd, r = pcall(json.decode, raw)
        if okd and type(r) == "table" and R and r.id then
            if r.id == R.wait then
                R.wait = nil
                if not r.ok then
                    fail(R, tostring(r.err or "sim error"))
                elseif r.snap then
                    R.snap = r.snap
                    R.check = true
                end
                if r.cmd == "new" and r.ok then
                    BOT.thinking_since = nil
                    if r.weights then note("Fair: " .. L("weights") .. " " .. tostring(r.weights)) end
                end
            elseif r.id == R.deciding then
                R.deciding = nil
                BOT.thinking_since = nil
                if r.ok and type(r.action) == "table" then
                    R.decision = {action = r.action, step = R.snap and R.snap.step, why = r.why, secs = r.secs, think = r.think}
                else
                    R.no_decision = r.err or r.why or "no action"
                end
            end
        end
    end
    if R and not R.failed and M.thread and not M.thread:isRunning() and (R.wait or R.deciding) then
        fail(R, "thread stopped: " .. tostring(M.thread:getError()))
    end
end

local RANKS = {[10] = "T", [11] = "J", [12] = "Q", [13] = "K", [14] = "A"}
local SUITS = {Spades = "S", Hearts = "H", Diamonds = "D", Clubs = "C"}

local function edition_key(card)
    local e = card.edition
    if type(e) ~= "table" then return nil end
    if type(e.key) == "string" then return e.key end
    if type(e.type) == "string" then return "e_" .. e.type end
    for _, k in ipairs({"foil", "holo", "polychrome", "negative"}) do
        if e[k] then return "e_" .. k end
    end
    return nil
end

local function is_playing_card(card)
    local set = card.ability and card.ability.set
    return (set == "Default" or set == "Enhanced") and card.base and card.base.id
end

local function center_key(card)
    return card.config and card.config.center and card.config.center.key or "?"
end

local function card_str(card)
    if not is_playing_card(card) then
        local ed = edition_key(card)
        local key = center_key(card)
        return ed and (key .. ":" .. ed) or key
    end
    local s = (RANKS[card.base.id] or tostring(card.base.id)) .. (SUITS[card.base.suit] or "?")
    local center = card.config and card.config.center
    if center and center.key and center.key ~= "c_base" then s = s .. ":" .. center.key end
    local ed = edition_key(card)
    if ed then s = s .. ":" .. ed end
    if card.seal then s = s .. ":s_" .. string.lower(card.seal) end
    local pb = card.ability and card.ability.perma_bonus
    if type(pb) == "number" and pb ~= 0 then s = s .. ":+" .. tostring(pb) end
    return s
end

local function real_snap(phase)
    local g = G.GAME
    local out = {phase = phase, ante = g.round_resets and g.round_resets.ante, money = g.dollars, hand = {}, jokers = {}, consumables = {}}
    for i, c in ipairs(G.hand and G.hand.cards or {}) do out.hand[i] = card_str(c) end
    for i, c in ipairs(G.jokers and G.jokers.cards or {}) do out.jokers[i] = center_key(c) end
    for i, c in ipairs(G.consumeables and G.consumeables.cards or {}) do out.consumables[i] = card_str(c) end
    if G.shop and G.shop_jokers and G.shop_jokers.cards then
        out.shop = {}
        for i, c in ipairs(G.shop_jokers.cards) do out.shop[i] = is_playing_card(c) and card_str(c) or center_key(c) end
    end
    if phase == "pack" and G.pack_cards then
        out.pack = {}
        for i, c in ipairs(G.pack_cards.cards or {}) do out.pack[i] = card_str(c) end
    end
    return out
end

local function list_diff(name, a, b)
    a, b = a or {}, b or {}
    if #a ~= #b then return string.format("%s count %d vs %d", name, #b, #a) end
    for i = 1, #a do
        if tostring(a[i]) ~= tostring(b[i]) then return string.format("%s %d: %s vs %s", name, i, tostring(b[i]), tostring(a[i])) end
    end
    return nil
end

local function compare(sim, real)
    if sim.phase ~= real.phase then return "phase " .. tostring(real.phase) .. " vs " .. tostring(sim.phase) end
    if sim.ante ~= real.ante then return "ante " .. tostring(real.ante) .. " vs " .. tostring(sim.ante) end
    if sim.money ~= real.money then return "money " .. tostring(real.money) .. " vs " .. tostring(sim.money) end
    local d = list_diff("hand", sim.hand, real.hand) or list_diff("jokers", sim.jokers, real.jokers) or list_diff("consumables", sim.consumables, real.consumables)
    if d then return d end
    if sim.shop and real.shop then d = list_diff("shop", sim.shop, real.shop) if d then return d end end
    if sim.pack and real.pack then d = list_diff("pack", sim.pack, real.pack) if d then return d end end
    return nil
end
M.compare = compare
M.real_snap = real_snap

local function pos_of(area, id)
    for i, c in ipairs(area and area.cards or {}) do
        if c.sort_id == id then return i end
    end
    return nil
end

local function id_at(area, pos)
    local c = area and area.cards and area.cards[pos]
    return c and c.sort_id
end

local function map_list(list, f)
    if type(list) ~= "table" then return nil end
    local out = {}
    for i, v in ipairs(list) do
        local r = f(v)
        if r == nil then return nil end
        out[i] = r
    end
    return out
end

local AREA = {buy = "shop_jokers", buy_and_use = "shop_jokers", redeem = "shop_vouchers", open = "shop_booster", pick = "pack_cards", use = "consumeables"}

function M.to_positions(a)
    if not M.MAPPED[a.type] then return nil, "action " .. tostring(a.type) .. " has no sim form" end
    local p = {type = a.type}
    local hp = function(id) return pos_of(G.hand, id) end
    if a.cards then
        p.cards = map_list(a.cards, hp)
        if not p.cards then return nil, "card not in hand" end
    end
    if a.targets and #a.targets > 0 then
        p.targets = map_list(a.targets, hp)
        if not p.targets then return nil, "target not in hand" end
    end
    if a.type == "sell" then
        local i = pos_of(G.jokers, a.card)
        if i then p.area, p.card = "jokers", i else
            i = pos_of(G.consumeables, a.card)
            if not i then return nil, "sell card not found" end
            p.area, p.card = "consumables", i
        end
    elseif AREA[a.type] then
        p.card = pos_of(G[AREA[a.type]], a.card)
        if not p.card then return nil, a.type .. " card not found" end
    end
    if a.type == "reorder_jokers" then
        p.order = map_list(a.order, function(id) return pos_of(G.jokers, id) end)
        if not p.order then return nil, "joker not found" end
    end
    return p
end

function M.to_ids(p)
    local a = {type = p.type}
    local hid = function(pos) return id_at(G.hand, pos) end
    if p.cards then
        a.cards = map_list(p.cards, hid)
        if not a.cards then return nil, "hand position out of range" end
    end
    if p.targets then
        a.targets = map_list(p.targets, hid)
        if not a.targets then return nil, "target position out of range" end
    end
    if p.type == "sell" then
        a.card = id_at(p.area == "consumables" and G.consumeables or G.jokers, p.card)
        if not a.card then return nil, "sell position out of range" end
    elseif AREA[p.type] then
        a.card = id_at(G[AREA[p.type]], p.card)
        if not a.card then return nil, p.type .. " position out of range" end
    end
    if p.type == "reorder_jokers" then
        a.order = map_list(p.order, function(pos) return id_at(G.jokers, pos) end)
        if not a.order then return nil, "joker position out of range" end
    end
    return a
end

local VERB = {buy = "Buy", open = "Open", pick = "Take", use = "Use", sell = "Sell", skip = "Skip blind", select = "Play blind",
    reroll = "Reroll", leave = "Leave shop", reroll_boss = "Reroll boss", reorder_jokers = "Reorder jokers", skip_pack = "Skip pack",
    buy_and_use = "Buy and use", play = "Play", discard = "Discard"}

local function card_by_id(id)
    for _, area in ipairs({G.hand, G.jokers, G.consumeables, G.shop_jokers, G.shop_vouchers, G.shop_booster, G.pack_cards}) do
        for _, c in ipairs(area and area.cards or {}) do
            if c.sort_id == id then return c end
        end
    end
    return nil
end

local function card_label(c)
    if not c then return "" end
    local set = c.ability and c.ability.set
    if set and set ~= "Default" and set ~= "Enhanced" and c.ability.name then return tostring(c.ability.name) end
    if c.base and c.base.value then return tostring(c.base.value) .. " " .. tostring(c.base.suit or "") end
    return ""
end

local function describe_move(p)
    local verb = L(VERB[p.type] or tostring(p.type))
    local a = M.to_ids(p)
    if not a then return verb end
    if a.cards and (p.type == "play" or p.type == "discard") then
        local cards = {}
        for _, id in ipairs(a.cards) do
            local c = card_by_id(id)
            if c then cards[#cards + 1] = c end
        end
        if p.type == "play" and #cards > 0 then
            local ok, text, disp = pcall(G.FUNCS.get_poker_hand_info, cards)
            if ok and (disp or text) then return verb .. " " .. tostring(disp or text) end
        end
        return verb .. " " .. #cards
    end
    if a.card then
        local name = card_label(card_by_id(a.card))
        if name ~= "" then return verb .. " " .. name end
    end
    return verb
end

function M.thinking_text(think)
    if type(think) ~= "table" or type(think.items) ~= "table" or #think.items < 2 then return nil end
    local out = {}
    if think.kind == "solver" then
        out[1] = string.format(L("Odds to clear, %d draws each:"), think.n or 0)
        for i, it in ipairs(think.items) do
            out[#out + 1] = string.format("%s%d%% %s", i == 1 and "> " or "", math.floor((it.w or 0) * 100 + 0.5), describe_move(it.a))
        end
    else
        out[1] = string.format(L("Avg ante over %d futures:"), think.n or 0)
        for i, it in ipairs(think.items) do
            out[#out + 1] = string.format("%s%.1f %s", i == 1 and "> " or "", it.v or 0, describe_move(it.a))
        end
    end
    return table.concat(out, "\n")
end

local function current_run(kind)
    local R = M.run
    if R and R.game == G.GAME and R.kind == kind then return R end
    local L0 = M.launch
    if L0 and G.GAME and G.GAME ~= L0.old then
        M.launch = nil
        return start(kind)
    end
    if R and R.game == G.GAME then return R end
    R = {kind = kind, game = G.GAME, failed = "not started by Bot-latro"}
    M.run = R
    note(string.format("%s: %s, %s", M.KINDS[kind], L("needs a fresh vanilla run it started itself"), L("the offline brain plays instead")))
    return R
end

local function rules(state, ctx, R)
    local f = BOT.brains.rules
    if not f then return nil end
    local a, reason = f(state, ctx)
    if R and R.failed then reason = "[" .. L("offline brain") .. "] " .. tostring(reason or "") end
    return a, reason
end

local function brain(kind)
    return function(state, ctx)
        local R = current_run(kind)
        poll(R)
        if R.failed then return rules(state, ctx, R) end
        if R.wait then
            if love.timer.getTime() - (R.since or 0) > 30 then fail(R, "sim did not answer") return rules(state, ctx, R) end
            return BOT.WAIT
        end
        local phase = BOT_BRIDGE.phase()
        if R.check and R.snap then
            R.check = false
            local d = compare(R.snap, real_snap(phase))
            if d then
                fail(R, L("lost sync with the game") .. " (" .. d .. ")")
                return rules(state, ctx, R)
            end
        end
        if R.decision then
            local dec = R.decision
            R.decision = nil
            if R.snap and dec.step == R.snap.step then
                local a, err = M.to_ids(dec.action)
                if a then
                    R.decided_by = kind
                    local th = M.thinking_text(dec.think)
                    if th then return a, string.format("%s, %.1fs", M.KINDS[kind], dec.secs or 0) .. "\n" .. th end
                    return a, string.format("%s (%.1fs): %s", M.KINDS[kind], dec.secs or 0, tostring(dec.why or ""))
                end
                fail(R, tostring(err))
                return rules(state, ctx, R)
            end
        end
        if R.no_decision then
            R.no_decision = nil
            return rules(state, ctx, R)
        end
        if not R.deciding then
            R.budget = budget()
            R.deciding = send({cmd = "decide", budget = R.budget})
            R.slow_noted = nil
            R.decide_at = love.timer.getTime()
            BOT.thinking_since = R.decide_at
            return BOT.WAIT
        end
        local waited = love.timer.getTime() - (R.decide_at or 0)
        if waited > M.SAFETY then
            R.deciding = nil
            BOT.thinking_since = nil
            note(string.format("%s: %s", M.KINDS[kind], L("over the time budget, the offline brain plays this move")))
            return rules(state, ctx, R)
        end
        if waited > (M.LIMITS[R.budget] or 25) and not R.slow_noted then
            R.slow_noted = true
            if BOT.ui and BOT.ui.set_reasoning then BOT.ui.set_reasoning(L("Taking longer than usual on this machine, still thinking.")) end
        end
        return BOT.WAIT
    end
end

for kind in pairs(M.KINDS) do BOT.brains[kind] = brain(kind) end

function M.after_apply(a)
    local R = M.run
    if not R or R.failed or R.game ~= G.GAME or not R.pending_step then return end
    local p = R.pending_step
    R.pending_step = nil
    R.decision = nil
    R.wait = send({cmd = "step", action = p})
    R.since = love.timer.getTime()
end

local base_apply = BOT.apply
BOT.apply = function(a, reason)
    local R = M.run
    local live = R and not R.failed and R.game == G.GAME and G.GAME and BOT.brains[BOT.settings and BOT.settings.brain] == BOT.brains[R.kind]
    if live then
        if a.type == "endless" or a.type == "new_run" or a.type == "menu" then
            R.failed = "run over"
            live = false
        else
            local p, err = M.to_positions(a)
            if not p then
                fail(R, tostring(err))
                live = false
            else
                R.pending_step = p
            end
        end
    end
    local done = base_apply(a, reason)
    if live then
        if done then M.after_apply(a) else R.pending_step = nil end
    end
    return done
end

local base_start = BOT.start
BOT.start = function(opts)
    M.run = nil
    return base_start(opts)
end

function M.stop()
    M.run = nil
    M.launch = nil
end

if mod_loc_register then
    mod_loc_register({
        fr = {
            ["Seer (early)"] = "Seer (version alpha)",
            ["Fair (early)"] = "Fair (version alpha)",
            ["Fair Seer (early)"] = "Fair Seer (version alpha)",
            ["the offline brain plays the rest of the run"] = "le cerveau hors ligne joue la suite de la partie",
            ["needs a fresh vanilla run it started itself"] = "il faut une nouvelle partie vanilla lancée par Bot-latro",
            ["the offline brain plays instead"] = "le cerveau hors ligne joue à sa place",
            ["lost sync with the game"] = "désynchronisé avec la partie",
            ["over the time budget, the offline brain plays this move"] = "temps dépassé, le cerveau hors ligne joue ce coup",
            ["w16 cannot play this run:"] = "w16 ne peut pas jouer cette partie :",
            ["The simple brain plays instead, it is much weaker."] = "Le cerveau simple joue à sa place, il est bien plus faible.",
            ["Taking longer than usual on this machine, still thinking."] = "Plus long que d'habitude sur cette machine, il réfléchit encore.",
            ["Odds to clear, %d draws each:"] = "Chance de passer, %d tirages :",
            ["Avg ante over %d futures:"] = "Mise moyenne sur %d futurs :",
            ["Buy"] = "Acheter",
            ["Open"] = "Ouvrir",
            ["Take"] = "Prendre",
            ["Use"] = "Utiliser",
            ["Sell"] = "Vendre",
            ["Skip blind"] = "Passer la blinde",
            ["Play blind"] = "Jouer la blinde",
            ["Reroll"] = "Relancer",
            ["Leave shop"] = "Quitter la boutique",
            ["Reroll boss"] = "Relancer le boss",
            ["Reorder jokers"] = "Réordonner les jokers",
            ["Skip pack"] = "Passer le paquet",
            ["Buy and use"] = "Acheter et utiliser",
            ["Play"] = "Jouer",
            ["Discard"] = "Défausser",
            ["mirrors seed"] = "simule la seed",
            ["weights"] = "poids",
            ["offline brain"] = "cerveau hors ligne",
            ["modded run"] = "partie moddée",
            ["challenge run"] = "partie défi",
            ["custom run rules"] = "règles personnalisées",
            ["mods are loaded"] = "des mods sont chargés",
            ["needs every joker and voucher unlocked"] = "il faut tous les jokers et coupons débloqués",
            ["not a vanilla deck"] = "jeu non vanilla",
            ["not a vanilla stake"] = "mise non vanilla",
            ["no seed"] = "pas de seed",
            ["run already started"] = "partie déjà commencée",
            ["Thinking time"] = "Temps de réflexion",
            ["fast"] = "rapide",
            ["normal"] = "normal",
            ["deep"] = "profond",
            ["Early version. Reads the seed: knows every future draw and shop."] = "Version alpha. Lit la seed : connaît chaque tirage et chaque boutique à venir.",
            ["Early version. Neural net and tree search, sees only what a player sees."] = "Version alpha. Réseau de neurones et recherche, ne voit que ce que voit un joueur.",
            ["Early version. Plans over sampled worlds, sees only what a player sees."] = "Version alpha. Planifie sur des mondes tirés au hasard, ne voit que ce que voit un joueur.",
            ["Starts its own vanilla run (no mods, no challenge). Thinks in the background."] = "Lance sa propre partie vanilla (sans mods ni défi). Réfléchit en arrière-plan.",
        },
        es = {
            ["Seer (early)"] = "Seer (versión alfa)",
            ["Fair (early)"] = "Fair (versión alfa)",
            ["Fair Seer (early)"] = "Fair Seer (versión alfa)",
            ["the offline brain plays the rest of the run"] = "el cerebro sin conexión juega el resto de la partida",
            ["needs a fresh vanilla run it started itself"] = "necesita una partida vanilla nueva iniciada por Bot-latro",
            ["the offline brain plays instead"] = "el cerebro sin conexión juega en su lugar",
            ["lost sync with the game"] = "perdió la sincronía con la partida",
            ["over the time budget, the offline brain plays this move"] = "tiempo agotado, el cerebro sin conexión juega esta jugada",
            ["w16 cannot play this run:"] = "w16 no puede jugar esta partida:",
            ["The simple brain plays instead, it is much weaker."] = "El cerebro simple juega en su lugar, es mucho más débil.",
            ["Taking longer than usual on this machine, still thinking."] = "Tarda más de lo normal en esta máquina, sigue pensando.",
            ["Odds to clear, %d draws each:"] = "Prob. de superar, %d robos:",
            ["Avg ante over %d futures:"] = "Apuesta media en %d futuros:",
            ["Buy"] = "Comprar",
            ["Open"] = "Abrir",
            ["Take"] = "Tomar",
            ["Use"] = "Usar",
            ["Sell"] = "Vender",
            ["Skip blind"] = "Saltar la ciega",
            ["Play blind"] = "Jugar la ciega",
            ["Reroll"] = "Volver a tirar",
            ["Leave shop"] = "Salir de la tienda",
            ["Reroll boss"] = "Cambiar el jefe",
            ["Reorder jokers"] = "Reordenar comodines",
            ["Skip pack"] = "Saltar el sobre",
            ["Buy and use"] = "Comprar y usar",
            ["Play"] = "Jugar",
            ["Discard"] = "Descartar",
            ["mirrors seed"] = "simula el código",
            ["weights"] = "pesos",
            ["offline brain"] = "cerebro sin conexión",
            ["modded run"] = "partida con mods",
            ["challenge run"] = "partida de desafío",
            ["custom run rules"] = "reglas personalizadas",
            ["mods are loaded"] = "hay mods cargados",
            ["needs every joker and voucher unlocked"] = "necesita todos los comodines y vales desbloqueados",
            ["not a vanilla deck"] = "baraja no vanilla",
            ["not a vanilla stake"] = "pozo no vanilla",
            ["no seed"] = "sin código",
            ["run already started"] = "partida ya empezada",
            ["Thinking time"] = "Tiempo para pensar",
            ["fast"] = "rápido",
            ["normal"] = "normal",
            ["deep"] = "profundo",
            ["Early version. Reads the seed: knows every future draw and shop."] = "Versión alfa. Lee el código: conoce cada robo y cada tienda futuros.",
            ["Early version. Neural net and tree search, sees only what a player sees."] = "Versión alfa. Red neuronal y búsqueda, solo ve lo que ve un jugador.",
            ["Early version. Plans over sampled worlds, sees only what a player sees."] = "Versión alfa. Planifica sobre mundos de muestra, solo ve lo que ve un jugador.",
            ["Starts its own vanilla run (no mods, no challenge). Thinks in the background."] = "Inicia su propia partida vanilla (sin mods ni desafío). Piensa en segundo plano.",
        },
    })
end

return M
