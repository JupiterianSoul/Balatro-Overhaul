local M = {}

local function L(s) return mod_loc and mod_loc(s) or s end

local ensure

local function settings()
    return bom_match and bom_match.get_settings and bom_match.get_settings() or {}
end

local function is_host()
    return bom_match and bom_match.is_host_player and bom_match.is_host_player() or false
end

local function rulesets() return rawget(_G, "bom_rulesets") end
local function layers() return rawget(_G, "bom_layers") end

local function lock_kind()
    local R = rulesets()
    return R and R.lock_kind and R.lock_kind() or nil
end

local function can_edit() return is_host() and lock_kind() == nil end
M.can_edit = can_edit

local function fmt_money(v) return "$" .. tostring(v) end
local function fmt_secs(v) return tostring(v) .. "s" end
local function on_off(v) return v and L("On") or L("Off") end

local function mode_options()
    local out = {}
    local list = bom_gamemodes and bom_gamemodes.get_display_list and bom_gamemodes.get_display_list() or {}
    for _, m in ipairs(list) do out[#out + 1] = {value = m.key, label = m.name} end
    if #out == 0 then out[1] = {value = "nemesis", label = "Rivals"} end
    return out
end

local function stake_options()
    local out = {}
    for i, v in ipairs((G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake) or {}) do
        local name = v.name or ("Stake " .. i)
        pcall(function()
            local n = localize{type = 'name_text', set = 'Stake', key = v.key}
            if n and n ~= "ERROR" then name = n end
        end)
        out[#out + 1] = {value = i, label = name, raw = true}
    end
    if #out == 0 then out[1] = {value = 1, label = "White Stake", raw = true} end
    out[#out + 1] = {value = "random", label = "Random (stake)"}
    return out
end

local function deck_options()
    local out = {{value = bom_match and bom_match.RANDOM_DECK or "random_pick", label = "Random pick"}}
    for _, v in ipairs((G.P_CENTER_POOLS and G.P_CENTER_POOLS.Back) or {}) do
        if not v.omit and v.name then out[#out + 1] = {value = v.name, label = v.name, raw = true} end
    end
    local bd = rawget(_G, "bom_decks")
    if bd and bd.options then
        local ok, extra = pcall(bd.options)
        if ok and type(extra) == "table" then
            for _, o in ipairs(extra) do out[#out + 1] = o end
        end
    end
    if #out == 1 then out[2] = {value = "Red Deck", label = "Red Deck", raw = true} end
    return out
end
M.deck_options = deck_options

local function mp_stake_options()
    local bs = rawget(_G, "bom_stakes")
    if bs and bs.options then
        local ok, o = pcall(bs.options)
        if ok and type(o) == "table" and #o > 0 then return o end
    end
    return {{value = "", label = "None", raw = true}}
end

local function final_ante_options()
    local s = settings()
    local auto = bom_match and bom_match.final_ante_for and bom_match.final_ante_for({stake = s.stake}) or 8
    local out = {{value = false, label = L("Auto") .. " (" .. tostring(auto) .. ")", raw = true}}
    for i = 3, 16 do out[#out + 1] = {value = i, label = tostring(i), raw = true} end
    return out
end

local function secs_options(list)
    return function()
        local out = {}
        for _, v in ipairs(list) do out[#out + 1] = {value = v, label = v == 0 and L("Off") or fmt_secs(v), raw = v ~= 0, secs = true} end
        return out
    end
end

local MODE_INFO = {
    nemesis = "Boss blinds are PvP from the chosen ante",
    faceoff = "Every blind is PvP from the chosen ante",
    ascension = "No PvP, lives only go on failed blinds",
    race = "No PvP: first to clear the target ante wins",
}

local function mode_is(m) return function(s) return (s.mode or "nemesis") == m end end
local function party_on() return bom_party ~= nil and bom_party.active() end
local function kind_is(k) return function(s) return (s.party_kind or "br") == k end end
local function not_raid(s) return not party_on() or (s.party_kind or "br") ~= "raid" end
local function has_pvp(s) return (s.party_kind or "br") ~= "race" end
local function losers_info(s)
    local n = tonumber(s.br_losers) or 1
    if n <= 1 then return L("Lowest score loses 1 life") end
    return string.format(L("Lowest %d scores lose 1 life each"), n)
end
local function fmt_pct(v) return tostring(v) .. "%" end

local function party_kind_options()
    local out = {}
    for _, k in ipairs((bom_party and bom_party.KINDS) or {"br", "teams", "raid"}) do
        out[#out + 1] = {value = k, label = bom_party and bom_party.kind_name(k) or k, raw = true}
    end
    return out
end
local function timer_on(s) return s.timer == true end

local function deck_info(s)
    local own = bom_match and bom_match.different_decks and bom_match.different_decks(s)
    if s.deck_draft == true and own then return "Draft bans, then everyone picks from 3" end
    if s.deck_draft == true then return "Decided by the deck draft" end
    if own then return "Everyone picks a deck at match start" end
    if s.deck == (bom_match and bom_match.RANDOM_DECK) then return "A deck is rolled every match" end
    return "Everyone starts with this deck"
end

local function joker_picks_info(s)
    local n = bom_match and bom_match.joker_picks and bom_match.joker_picks(s) or 0
    local raw = math.floor(tonumber(s.joker_picks) or 0)
    if raw > 0 and n < raw then return L("Only %d: starting jokers fill the slots"):format(n) end
    if n <= 0 then return "Everyone picks jokers at match start" end
    return L("Pick %d Common or Uncommon at match start"):format(n)
end

local function fmt(pattern, ...)
    local ok, r = pcall(string.format, pattern, ...)
    return ok and r or pattern
end

local function mode_ban_counts(s)
    local gm = bom_gamemodes and bom_gamemodes.registry and bom_gamemodes.registry[s.mode or "nemesis"]
    if not gm then return nil end
    local j = #(gm.banned_jokers or {}) + #(gm.banned_consumables or {})
    local v = #(gm.banned_vouchers or {})
    local t = #(gm.banned_tags or {})
    if j + v + t == 0 then return nil end
    return j, v, t
end

M.DEFS = {
    {key = "party_kind", tab = "party", kind = "cycle", label = "Party mode", options = party_kind_options, refresh = true, party = true,
        info_fn = function(s) return bom_party and bom_party.KIND_INFO[s.party_kind or "br"] end},
    {key = "party_every_blind", tab = "party", kind = "toggle", label = "Every blind is PvP", info = "Small and Big blinds too, not only Boss", party = true, show = has_pvp},
    {key = "party_blind_seconds", tab = "party", kind = "cycle", label = "AFK limit", info = "PvP goes on without anyone idle this long", party = true, show = has_pvp,
        options = secs_options({60, 90, 120, 180, 240, 300, 420, 600})},
    {header = "Battle Royale", tab = "party", party = true, show = kind_is("br")},
    {key = "br_losers", tab = "party", kind = "stepper", label = "Players hit per blind", info_fn = losers_info, refresh = true, min = 1, max = 3, party = true, show = kind_is("br")},
    {key = "br_ties", tab = "party", kind = "cycle", label = "Ties for lowest", info = "Scores tied at the losing spot", party = true, show = kind_is("br"),
        options = {{value = "all", label = "Everyone tied loses"}, {value = "spare", label = "Ties are spared"}}},
    {key = "br_sudden_death", tab = "party", kind = "toggle", label = "Final two sudden death", info = "When a knockout leaves 2, both go to 1 life", party = true, show = kind_is("br")},
    {key = "party_swap", tab = "party", kind = "toggle", label = "Switcheroo", info = "Runs pass to the next player after each boss", party = true, show = kind_is("br")},
    {header = "Teams", tab = "party", party = true, show = kind_is("teams")},
    {key = "team_size", tab = "party", kind = "stepper", label = "Team size", info = "Players per team, at least 2 teams", min = 2, max = 4, party = true, show = kind_is("teams")},
    {key = "team_share", tab = "party", kind = "stepper", label = "Teammate share", info = "Best teammate counts 100%, others this %", min = 0, max = 100, big_step = 10,
        format = fmt_pct, party = true, show = kind_is("teams")},
    {key = "team_auto", tab = "party", kind = "toggle", label = "Auto-balance teams", info = "Off: players pick their own team", party = true, show = kind_is("teams")},
    {header = "Spectating", tab = "party", party = true},
    {key = "spectate", tab = "party", kind = "toggle", label = "Allow spectating", info = "Off: only knocked-out players can watch", party = true},
    {key = "spectate_jokers", tab = "party", kind = "toggle", label = "Spectators see jokers", info = "Off: only knocked-out players see them", party = true},
    {key = "spectate_wait", tab = "party", kind = "toggle", label = "Spectate while waiting", info = "Watch once your hands are played", party = true, show = has_pvp},
    {header = "Co-op Raid", tab = "party", party = true, show = kind_is("raid")},
    {key = "raid_lives", tab = "party", kind = "stepper", label = "Raid lives", info = "Shared: a failed raid costs 1", min = 1, max = 20, party = true, show = kind_is("raid")},
    {key = "raid_per_player", tab = "party", kind = "stepper", label = "Target per player", info = "Boss blind x players x this, x3 at ante 1", min = 50, max = 800, big_step = 50, format = fmt_pct, party = true, show = kind_is("raid")},
    {key = "raid_scaling", tab = "party", kind = "stepper", label = "Extra target per ante", info = "Target grows this much each ante after 1", min = 0, max = 100, big_step = 10, format = fmt_pct, party = true, show = kind_is("raid")},
    {key = "raid_mvp_bonus", tab = "party", kind = "stepper", label = "Top damage bonus", info = "Money for the best score each raid", min = 0, max = 10, format = fmt_money, party = true, show = kind_is("raid")},

    {key = "mode", tab = "match", kind = "cycle", label = "Mode", options = mode_options, refresh = true, no_party = true,
        info_fn = function(s) return MODE_INFO[s.mode or "nemesis"] end},
    {key = "starting_lives", tab = "match", kind = "stepper", label = "Lives", min = 1, max = 20, show = not_raid,
        info_fn = function(s) return fmt(L("Everyone starts with %d"), s.starting_lives or 4) end},
    {key = "pvp_start_round", tab = "match", kind = "stepper", label = "PvP from ante", min = 1, max = 8, show = mode_is("nemesis"),
        info_fn = function(s)
            local n = tonumber(s.pvp_start_round) or 2
            if n <= 1 then return "Every boss blind is PvP" end
            return fmt(L("Normal bosses before ante %d"), n)
        end},
    {key = "showdown_starting_antes", tab = "match", kind = "stepper", label = "PvP from ante", min = 1, max = 8, show = mode_is("faceoff"), no_party = true,
        info_fn = function(s)
            local n = tonumber(s.showdown_starting_antes) or 1
            if n <= 1 then return "Every blind is PvP from the start" end
            return fmt(L("Normal blinds before ante %d"), n)
        end},
    {key = "win_ante", tab = "match", kind = "cycle", label = "Final ante", options = final_ante_options,
        info_fn = function(s)
            local n = bom_match.final_ante_for and bom_match.final_ante_for(s) or 8
            if (s.mode or "nemesis") == "ascension" then return fmt(L("Clear ante %d to win"), n) end
            return fmt(L("Ends at ante %d, then sudden death"), n)
        end},
    {key = "stake", tab = "match", kind = "cycle", label = "Stake", options = stake_options, refresh = true,
        info_fn = function(s)
            local bs = rawget(_G, "bom_stakes")
            if bs and bs.valid and bs.valid(s.mp_stake) then return "Replaced by the Multiplayer stake" end
            if s.stake == "random" then return "White to Gold, rolled at each start" end
            return nil
        end},
    {key = "mp_stake", tab = "match", kind = "cycle", label = "Multiplayer stake", options = mp_stake_options, refresh = true,
        info_fn = function(s)
            local bs = rawget(_G, "bom_stakes")
            local key = bs and bs.valid and bs.valid(s.mp_stake) and s.mp_stake or nil
            if key == "stake_mp_planet" then return "Orange rules without the Blue shop tax" end
            if key == "stake_mp_spectral" then return "Nova + Rental jokers, score grows faster" end
            if key == "stake_mp_spectral_plus" then return "Eclipse, score grows even faster" end
            return "None: the Stake above is used"
        end,
        colour_fn = function(s) local bs = rawget(_G, "bom_stakes") return bs and bs.colour and bs.colour(s.mp_stake) or nil end},
    {key = "pvp_boss_effect", tab = "match", kind = "toggle", label = "Boss effect on PvP", info = "PvP boss blind adds a random boss effect",
        no_party = true, show = function(s) local m = s.mode or "nemesis" return m == "nemesis" or m == "faceoff" end},
    {header = "Lives and money", tab = "match"},
    {key = "death_on_round_loss", tab = "match", kind = "toggle", label = "Failed blind costs a life", info = "Off: you just keep playing",
        show = function(s) return (s.mode or "nemesis") ~= "ascension" end},
    {key = "gold_on_life_loss", tab = "match", kind = "toggle", label = "Money for a lost life", info = "+$3 per life lost ($2 at Purple Stake+)"},
    {key = "no_gold_on_round_loss", tab = "match", kind = "toggle", label = "No blind reward on a loss", info = "A lost blind or PvP pays $0 reward"},
    {key = "pvp_win_money", tab = "match", kind = "stepper", label = "PvP win bonus", min = 0, max = 10, big_step = 5, format = fmt_money,
        info_fn = function(s)
            local n = tonumber(s.pvp_win_money) or 0
            if n <= 0 then return "Off: no extra money for a PvP win" end
            return fmt(L("+$%d each time you win a PvP blind"), n)
        end},
    {key = "life_steal", tab = "match", kind = "toggle", label = "Life steal", info = "PvP win: +1 life, up to your starting lives"},
    {key = "hide_opp_score", tab = "match", kind = "toggle", label = "Hide enemy score", info = "Hidden until you play your first PvP hand",
        show = function(s) return (s.mode or "nemesis") ~= "ascension" end},
    {header = "Content", tab = "match"},
    {key = "multiplayer_jokers", tab = "match", kind = "toggle", label = "Multiplayer jokers", info = "PvP-only jokers can show up in shops"},
    {key = "balance_enabled", tab = "match", kind = "toggle", label = "Mode bans", show = function(s) return mode_ban_counts(s) ~= nil end,
        info_fn = function(s)
            local j, v, t = mode_ban_counts(s)
            if not j then return nil end
            return fmt(L("Bans %d jokers, %d vouchers, %d tag"), j, v, t)
        end},
    {key = "the_order", tab = "match", kind = "toggle", label = "Same card order", info = "Both players get cards in the same order",
        show = function(s) return not s.different_seeds end},

    {header = "Seeds and decks", tab = "players"},
    {key = "different_seeds", tab = "players", kind = "toggle", label = "Different seeds", info = "Each player gets their own seed", refresh = true},
    {key = "custom_seed", tab = "players", kind = "seed", label = "Seed", info = "Blank: a new seed each match", show = function(s) return not s.different_seeds end},
    {key = "deck", tab = "players", kind = "cycle", label = "Deck", options = deck_options, refresh = true, info_fn = deck_info},
    {key = "different_decks", tab = "players", kind = "toggle", label = "Each player picks a deck", info = "Everyone picks theirs at match start", refresh = true, no_party = true},
    {key = "joker_picks", tab = "players", kind = "stepper", label = "Starting joker picks", min = 0, max = 5, refresh = true, no_party = true,
        format = function(v) return (tonumber(v) or 0) <= 0 and L("Off") or tostring(v) end, info_fn = joker_picks_info},
    {header = "Timers", tab = "players"},
    {key = "timer", tab = "players", kind = "toggle", label = "Ready timer", info = "Clock for the last player to ready up", refresh = true},
    {key = "timer_base_seconds", tab = "players", kind = "cycle", label = "Timer length", info = "Time to ready up before a timeout", options = secs_options({30, 60, 90, 120, 150, 180, 240, 300}), show = timer_on},
    {key = "timer_increment_seconds", tab = "players", kind = "cycle", label = "Extra time per ante", info = "Added to the timer every ante", options = secs_options({0, 15, 30, 60, 90, 120}), show = timer_on},
    {key = "timer_forgiveness", tab = "players", kind = "stepper", label = "Free timeouts", info = "Then each timeout costs a life", min = 0, max = 5, show = timer_on},
    {key = "pvp_countdown_seconds", tab = "players", kind = "cycle", label = "PvP countdown", info = "Countdown before each PvP blind", options = secs_options({0, 3, 5, 10})},
    {header = "Speed", tab = "fair"},
    {key = "allow_fast_speed", tab = "fair", kind = "toggle", label = "Game speed over 4x", info = "Off: game speed is capped at 4x"},
    {key = "allow_score_speed", tab = "fair", kind = "toggle", label = "Score speed", info = "Players can speed up the scoring count"},
    {key = "allow_skip_score", tab = "fair", kind = "toggle", label = "Skip score animation", info = "Players can jump to the final score"},
    {header = "Seed", tab = "fair"},
    {key = "show_seed", tab = "fair", kind = "toggle", label = "Show the seed", info = "Off: hidden until the match ends"},
    {header = "Helpers allowed", tab = "fair"},
    {key = "allow_hand_optimizer", tab = "fair", kind = "toggle", label = "Hand Optimizer", info = "Players can use the Hand Optimizer"},
    {key = "allow_score_preview", tab = "fair", kind = "toggle", label = "Score preview", info = "Shows the score before you play"},
    {header = "Spectating", tab = "fair", no_party = true},
    {key = "spectate_wait", tab = "fair", kind = "toggle", label = "Spectate while waiting", info = "Watch once your hands are played", no_party = true},
}

M.BY_KEY = {}
for _, d in ipairs(M.DEFS) do if d.key then M.BY_KEY[d.key] = d end end

local function opts_of(d, v)
    local o = d.options
    if type(o) == "function" then o = o() end
    o = o or {}
    if type(v) ~= "number" then return o end
    local at = #o + 1
    for i, x in ipairs(o) do
        if x.value == v then return o end
        if type(x.value) ~= "number" then return o end
        if at > #o and x.value > v then at = i end
    end
    local c = {}
    for i, x in ipairs(o) do c[i] = x end
    local secs = o[#o] and o[#o].secs
    table.insert(c, at, {value = v, label = secs and fmt_secs(v) or tostring(v), raw = true, secs = secs})
    return c
end

function M.value_label(key, v)
    local d = M.BY_KEY[key]
    if not d then return tostring(v) end
    if d.kind == "toggle" then return on_off(v) end
    if d.kind == "seed" then return (bom_match.clean_seed(v) or L("Random (seed)")) end
    if d.kind == "cycle" then
        for _, o in ipairs(opts_of(d, v)) do
            if o.value == v then return o.raw and o.label or L(o.label) end
        end
        return tostring(v)
    end
    return d.format and d.format(v) or tostring(v)
end

local function shown(d, s)
    if d.party and not party_on() then return false end
    if d.no_party and party_on() then return false end
    return not d.show or d.show(s)
end

function M.describe(s)
    ensure()
    s = s or settings()
    local defaults = bom_match.DEFAULT_SETTINGS or {}
    local lines = {}
    for _, d in ipairs(M.DEFS) do
        if d.key and shown(d, s) then
            local v, def = s[d.key], defaults[d.key]
            local changed = v ~= nil and v ~= def
            if d.kind == "seed" then changed = bom_match.clean_seed(v) ~= nil end
            if changed then lines[#lines + 1] = L(d.label) .. L(": ") .. M.value_label(d.key, v) end
        end
    end
    if RunRules then
        for _, line in ipairs(RunRules.describe(RunRules.normalize(s.rules or {}))) do lines[#lines + 1] = line end
    end
    return lines
end

local function commit(key, value)
    if not can_edit() then return end
    if bom_room and bom_room.update_setting then bom_room.update_setting(key, value) end
end

local function follow_mode()
    local R = rulesets()
    if not (R and R.current_id and can_edit()) then return end
    local s = settings()
    local id = R.current_id(s)
    if id and id ~= s.ruleset_id then commit("ruleset_id", id) end
end

local W = {seed = {seed = ""}}

local function commit_seed()
    if not W.seed_live then return end
    W.seed_live = false
    if not can_edit() then return end
    local s = settings()
    local want = bom_match.clean_seed(W.seed.seed) or "random"
    if want ~= (bom_match.clean_seed(s.custom_seed) or "random") then commit("custom_seed", want) end
end

local function mp_row(d, s, disabled)
    local info = d.info_fn and d.info_fn(s) or d.info
    local base = {label = L(d.label), info = info and L(info) or nil, disabled = disabled, id = "mpls_" .. d.key, colour = d.colour_fn and d.colour_fn(s) or nil}
    local function changed(v)
        commit(d.key, v)
        if d.key == "mode" or d.key == "party_kind" then follow_mode() end
        if d.refresh then UIK.refresh() end
    end
    if d.kind == "toggle" then
        base.ref_table, base.ref_value = s, d.key
        base.callback = changed
        return UIK.toggle(base)
    elseif d.kind == "stepper" then
        base.ref_table, base.ref_value = s, d.key
        base.min, base.max, base.step, base.big_step, base.format = d.min, d.max, 1, d.big_step, d.format
        base.callback = changed
        return UIK.stepper(base)
    elseif d.kind == "cycle" then
        local o = opts_of(d, s[d.key])
        local labels, cur = {}, 1
        for i, x in ipairs(o) do
            labels[i] = x.raw and x.label or L(x.label)
            if x.value == s[d.key] then cur = i end
        end
        base.options, base.current = labels, cur
        base.callback = function(i) if o[i] then changed(o[i].value) end end
        return UIK.cycle(base)
    elseif d.kind == "seed" then
        if disabled then
            base.value = M.value_label(d.key, s[d.key])
            return UIK.value(base)
        end
        W.seed.seed = bom_match.clean_seed(s.custom_seed) or ""
        W.seed_live = true
        base.ref_table, base.ref_value = W.seed, "seed"
        base.max_length, base.all_caps, base.prompt = 8, true, L("Random (seed)")
        return UIK.input(base)
    end
end

local function mp_tab(tab)
    return function()
        commit_seed()
        local s = settings()
        local ro = not can_edit()
        local items = {}
        for _, d in ipairs(M.DEFS) do
            if d.tab == tab and shown(d, s) then
                if d.header then
                    items[#items + 1] = UIK.header(L(d.header))
                else
                    items[#items + 1] = mp_row(d, s, ro)
                end
            end
        end
        return UIK.flow{id = "mpls_" .. tab, items = items}
    end
end

local RULE_TABS = {
    {key = "run", label = "Run (rules tab)", cats = {"basics", "blinds"}},
    {key = "economy", label = "Economy", cats = {"economy"}},
    {key = "shop", label = "Shop", cats = {"shop"}},
    {key = "deck", label = "Deck", cats = {"deck", "items"}},
    {key = "fun", label = "Fun", cats = {"fun", "bans"}},
}

local CAT_LABEL = {}

local function rules_values()
    W.rules = RunRules.normalize(settings().rules or {})
    return W.rules
end

local function sync_rules()
    if not (can_edit() and W.rules) then return end
    commit("rules", bom_match.clean_rules(W.rules))
end

local function open_list(key)
    if not (RunRules and RunRules.open_picker) then return end
    commit_seed()
    W.picker_from = UIK._win and UIK._win._cur
    W.rules = W.rules or rules_values()
    RunRules.open_picker(key, W.rules, "mpls_back_from_picker", not can_edit())
end

local FUNCS = {}

FUNCS.mpls_back_from_picker = function()
    if G.CUSTOM_RUN then G.CUSTOM_RUN.target = nil; G.CUSTOM_RUN.readonly = false end
    if W.guest_jokers then
        local list = W.guest_jokers.starting_jokers or {}
        W.guest_jokers = nil
        if bom_room and bom_room.update_setting then bom_room.update_setting("my_starting_jokers", list) end
        if bom_ui and bom_ui.show_lobby then bom_ui.show_lobby() end
        return
    end
    sync_rules()
    M.show(W.picker_from)
end

local function rule_tab(t)
    return function()
        commit_seed()
        local values = rules_values()
        local ro = not can_edit()
        local items = {}
        for _, cat in ipairs(t.cats) do
            if #t.cats > 1 then items[#items + 1] = UIK.header(L(CAT_LABEL[cat] or cat)) end
            for _, d in ipairs(RunRules.list(cat)) do
                if d.kind == "list" and not bom_match.MP_EXCLUDED_RULES[d.key] then
                    local n = #(values[d.key] or {})
                    items[#items + 1] = UIK.action{
                        label = L(d.label),
                        info = n > 0 and (n .. " " .. L("chosen")) or L("None"),
                        button_label = ro and L("View") or L("Choose"),
                        button = "mpls_pick_" .. d.key,
                        button_id = "mpls_pick_" .. d.key,
                        colour = d.ban and UIK.C.danger or UIK.C.accent,
                    }
                end
            end
            for _, r in ipairs(RunRules.rows(values, cat, {disabled = ro, skip = bom_match.MP_EXCLUDED_RULES,
                on_change = function(k, v) if W.rules and k ~= nil then W.rules[k] = v end sync_rules() end})) do
                items[#items + 1] = r
            end
        end
        return UIK.flow{id = "mpls_" .. t.key, items = items}
    end
end

local KEEP_ON_PRESET = {mode = true, deck = true, my_starting_jokers = true, deck_pool = true, rolled_deck = true}
for k in pairs((package.loaded["multiplayer.bom_match"] or {}).PARTY_KEYS or {}) do KEEP_ON_PRESET[k] = true end

local function apply_values(values)
    if not can_edit() then return end
    W.seed_live = false
    local s = settings()
    local fresh = bom_match.defaults()
    for k in pairs(KEEP_ON_PRESET) do fresh[k] = s[k] end
    for k, v in pairs(values or {}) do
        if fresh[k] ~= nil or k == "rules" then fresh[k] = bom_match.deep_copy(v) end
    end
    bom_match.update_settings(fresh)
    bom_match.sync_settings()
    play_sound('card1')
    UIK.refresh()
end

local function current_values()
    local s = settings()
    local out = {}
    for _, k in ipairs(bom_match.non_default_keys(s)) do
        if not KEEP_ON_PRESET[k] then out[k] = s[k] end
    end
    out.rules = bom_match.deep_copy(s.rules or {})
    out.layers = bom_match.deep_copy(type(s.layers) == "table" and s.layers or {})
    return out
end

local function select_ruleset(id)
    if not can_edit() then return end
    local R = rulesets()
    local fresh = R and R.settings_for and R.settings_for(id, settings())
    if not fresh then return end
    W.seed_live = false
    bom_match.update_settings(fresh)
    bom_match.sync_settings()
    play_sound('card1')
    UIK.refresh()
end

local function set_layer(id, on)
    if not can_edit() then return end
    local R, ly = rulesets(), layers()
    if not (R and ly) then return end
    local s = settings()
    bom_match.update_settings(R.layer_change(s, ly.toggle(s.layers, id, on)))
    bom_match.sync_settings()
    UIK.refresh()
end

local function user_presets()
    if type(G.SETTINGS.mp_lobby_presets) ~= "table" then G.SETTINGS.mp_lobby_presets = {} end
    local up = G.SETTINGS.mp_lobby_presets
    for slot = 1, 3 do
        if up[slot] ~= nil and type(up[slot]) ~= "table" then up[slot] = nil end
    end
    return up
end

M.NAME_W = 6.4

local function name_body()
    local n = W.naming or {}
    local inner = M.NAME_W - 2 * UIK.PAD
    return UIK.stack({
        UIK.input{w = inner, iw = inner - 0.4, label = L("Preset name"), ref_table = n, ref_value = "name", max_length = 16,
            prompt = L("Slot") .. " " .. tostring(n.slot or 1), extended_corpus = true, id = "mpls_name_input", callback = function() G.FUNCS.mpls_name_ok() end},
    }, {w = inner})
end

local function close_name()
    if G.CONTROLLER then G.CONTROLLER.text_input_hook = nil end
    W.naming = nil
    M.show("overview")
end

FUNCS.mpls_name_ok = function()
    local n = W.naming
    if not n then return end
    if can_edit() then
        local values = current_values()
        local name = tostring(n.name or ""):match("^%s*(.-)%s*$")
        if name ~= "" then values._name = name end
        user_presets()[n.slot] = values
        G:save_settings()
        play_sound('card1')
    end
    close_name()
end

FUNCS.mpls_name_back = function() close_name() end

function M.show_name(slot)
    if not (ensure() and can_edit()) then return end
    commit_seed()
    local saved = user_presets()[slot]
    W.naming = {slot = slot, name = saved and type(saved._name) == "string" and saved._name or ""}
    G.FUNCS.overlay_menu{definition = UIK.window{zoom = false,
        id = "mpls_name",
        compact = true,
        w = M.NAME_W,
        keep_w = true,
        title = L("SAVE PRESET"),
        tabs = {{key = "name", label = L("Save"), build = name_body}},
        back_func = "mpls_name_back",
        footer = {UIK.button{label = L("Save"), button = "mpls_name_ok", colour = UIK.C.ok, id = "mpls_name_ok", w = 3.2}},
    }}
end

for slot = 1, 3 do
    FUNCS["mpls_save_" .. slot] = function()
        if not can_edit() then return end
        M.show_name(slot)
    end
    FUNCS["mpls_load_" .. slot] = function()
        local saved = user_presets()[slot]
        if not saved then play_sound('cancel'); return end
        apply_values(saved)
    end
end

FUNCS.mpls_reset = function()
    local R = rulesets()
    local id = R and R.default_id and R.default_id(R.mode_of(settings()))
    if id then select_ruleset(id) else apply_values({}) end
end

FUNCS.mpls_noop = function() end

local function ruleset_func(id)
    local key = "mpls_rs_" .. id
    if G.FUNCS[key] == nil then G.FUNCS[key] = function() select_ruleset(id) end end
    return key
end

local LOCK_TEXT = {ranked = "Ranked rules", daily = "Daily rules", weekly = "Weekly rules"}
local LOCK_TITLE = {ranked = "RANKED RULES", daily = "DAILY RULES", weekly = "WEEKLY RULES"}

function M.ruleset_lines(s)
    s = s or settings()
    local R, ly = rulesets(), layers()
    local lines = {}
    if not R then return lines end
    local rs = R.effective(s)
    if rs.name and rs.name ~= "" then lines[#lines + 1] = L("Ruleset") .. L(": ") .. L(rs.name) end
    if rs.desc and rs.desc ~= "" then lines[#lines + 1] = L(rs.desc) end
    local names = ly and ly.names and ly.names(rs.layers) or {}
    lines[#lines + 1] = L("Modifiers") .. L(": ") .. (#names > 0 and table.concat(names, ", ") or L("None"))
    return lines
end

local function preset_count(values)
    local n = 0
    for k, v in pairs(values or {}) do
        if k == "layers" then n = n + (type(v) == "table" and #v or 0)
        elseif k ~= "rules" and k ~= "_name" then n = n + 1 end
    end
    if RunRules then n = n + #RunRules.describe(RunRules.normalize(values and values.rules or {})) end
    return n
end

local function build_overview()
    commit_seed()
    local s = settings()
    local host = is_host()
    local edit = can_edit()
    local lock = lock_kind()
    local R = rulesets()
    local presets, slots = {}, nil
    local mode = R and R.mode_of(s) or (s.mode or "nemesis")
    if lock and R then
        local rs = R.effective(s)
        presets[1] = {label = L(rs.name or LOCK_TEXT[lock] or ""), button = "mpls_noop", colour = UIK.C.ok, disabled = true, id = "mpls_rs_locked"}
    elseif R then
        local cur = R.current_id(s)
        for _, d in ipairs(R.for_mode(mode)) do
            presets[#presets + 1] = {label = L(d.name), button = ruleset_func(d.id), colour = d.id == cur and UIK.C.ok or UIK.C.accent,
                disabled = not edit, id = "mpls_rs_" .. d.id}
        end
    end
    if edit then
        slots = {}
        local up = user_presets()
        for slot = 1, 3 do
            local saved = up[slot]
            local named = saved and type(saved._name) == "string" and saved._name ~= "" and saved._name
            slots[slot] = {label = named or (L("Slot") .. " " .. slot .. (saved and (" (" .. preset_count(saved) .. ")") or "")), muted = not saved,
                load = {label = L("Load"), button = "mpls_load_" .. slot, disabled = not saved, id = "mpls_load_" .. slot},
                save = {label = L("Save"), button = "mpls_save_" .. slot, id = "mpls_save_" .. slot}}
        end
    end
    local note = nil
    if lock then
        note = {L(LOCK_TEXT[lock] or "Ranked rules"), L("These rules are fixed for this match.")}
    elseif not host then
        note = {L("Only the host can change settings.")}
    end
    local lines = M.ruleset_lines(s)
    for _, l in ipairs(M.describe(s)) do lines[#lines + 1] = l end
    local title = L("Rulesets")
    if R then title = title .. L(": ") .. R.mode_name(mode) end
    return UIK.overview{
        presets_title = title, presets = presets, per_row = 4,
        slots_title = lock and L(LOCK_TEXT[lock] or "Ranked rules") or (edit and L("Your presets") or L("Host")), slots = slots,
        slots_note = note,
        changes_title = L("This match"), lines = lines,
        empty_text = L("Default multiplayer rules"), more_text = L("and") .. " %d " .. L("more"),
    }
end

W.mods = {}

local function build_modifiers()
    commit_seed()
    local s = settings()
    local ro = not can_edit()
    local ly = layers()
    local items = {}
    if not ly then return UIK.flow{id = "mpls_mods", items = items} end
    W.mods = {}
    for _, id in ipairs(ly.valid(s.layers)) do W.mods[id] = true end
    for _, c in ipairs(ly.CAT_ORDER) do
        local list = ly.by_cat(c.key)
        if #list > 0 then
            items[#items + 1] = UIK.header(L(c.label))
            for _, d in ipairs(list) do
                if W.mods[d.id] == nil then W.mods[d.id] = false end
                local id = d.id
                items[#items + 1] = UIK.toggle{label = L(d.name), info = L(d.desc), ref_table = W.mods, ref_value = id, disabled = ro,
                    id = "mpls_mod_" .. id, callback = function(v) set_layer(id, v == true) end}
            end
        end
    end
    return UIK.flow{id = "mpls_mods", items = items}
end

local function tabs()
    local t = {{key = "overview", label = L("Overview"), build = build_overview}}
    if party_on() then t[#t + 1] = {key = "party", label = L("Party"), build = mp_tab("party")} end
    t[#t + 1] = {key = "match", label = L("Match"), build = mp_tab("match")}
    t[#t + 1] = {key = "players", label = L("Players"), build = mp_tab("players")}
    t[#t + 1] = {key = "fair", label = L("Fair play"), build = mp_tab("fair")}
    if layers() then t[#t + 1] = {key = "mods", label = L("Modifiers"), build = build_modifiers} end
    if RunRules then
        for _, r in ipairs(RULE_TABS) do t[#t + 1] = {key = r.key, label = L(r.label), build = rule_tab(r)} end
    end
    return t
end

FUNCS.bom_back_to_lobby = function()
    commit_seed()
    W.rules = nil
    if G.CUSTOM_RUN then G.CUSTOM_RUN.target = nil; G.CUSTOM_RUN.readonly = false end
    if party_on() then return bom_party.show_lobby() end
    if bom_ui and bom_ui.show_lobby then bom_ui.show_lobby() end
end

function M.is_open()
    return UIK._win ~= nil and UIK._win.id == "mpls" and G.OVERLAY_MENU ~= nil and G.OVERLAY_MENU == M._box
end

function M.show(tab)
    if not ensure() then return end
    local host = can_edit()
    local lock = lock_kind()
    local title = party_on() and (host and L("PARTY SETTINGS") or L("PARTY SETTINGS (VIEW ONLY)")) or (host and L("MATCH SETTINGS") or L("MATCH SETTINGS (VIEW ONLY)"))
    if lock then title = L(LOCK_TITLE[lock] or "RANKED RULES") end
    G.FUNCS.overlay_menu{definition = UIK.window{zoom = false,
        id = "mpls",
        title = title,
        tabs = tabs(),
        tab = tab,
        back_func = "bom_back_to_lobby",
        back_inline = true,
        footer = host and {UIK.button{label = L("Reset"), button = "mpls_reset", colour = UIK.C.danger, id = "mpls_reset"}} or nil,
    }}
    M._box = G.OVERLAY_MENU
end

function M.on_settings_changed()
    if M.is_open() and not is_host() then UIK.refresh() end
end

function M.show_guest_jokers()
    if not (ensure() and RunRules.open_picker) then return end
    local s = settings()
    local n = bom_match.joker_picks(s)
    if n <= 0 then return end
    local rules = RunRules.normalize(s.rules or {})
    local mine = {}
    for _, k in ipairs(bom_match.my_joker_picks(s)) do mine[#mine + 1] = k end
    W.guest_jokers = {starting_jokers = mine, joker_slots = rules.joker_slots, pick_limit = n,
        pick_filter = function(c) return bom_match.joker_pick_ok(c.key, s) end}
    RunRules.open_picker("starting_jokers", W.guest_jokers, "mpls_back_from_picker", false)
end

function M.sync_sliders() commit_seed() end

local function register_strings()
    mod_loc_register{
    fr = {
        ["Spectate while waiting"] = "Regarder en attendant", ["Watch once your hands are played"] = "Regarder une fois vos mains jouées",
        ["Mode"] = "Mode", ["Lives"] = "Vies", ["PvP from ante"] = "JcJ dès la mise initiale", ["Final ante"] = "Dernière mise initiale",
        ["Auto"] = "Auto",
        ["Boss blinds are PvP from the chosen ante"] = "Les boss sont en JcJ dès la mise initiale choisie",
        ["Every blind is PvP from the chosen ante"] = "Chaque blinde est en JcJ dès la mise initiale choisie",
        ["No PvP, lives only go on failed blinds"] = "Pas de JcJ, vies perdues sur blinde ratée",
        ["Lives and money"] = "Vies et argent", ["Failed blind costs a life"] = "Blinde ratée coûte une vie",
        ["PvP win bonus"] = "Bonus de victoire JcJ",
        ["Life steal"] = "Vol de vie",
        ["Content"] = "Contenu", ["Multiplayer jokers"] = "Jokers multijoueur",
        ["Mode bans"] = "Interdits du mode",
        ["Shared queue"] = "File commune",
        ["Seeds and decks"] = "Seeds et jeux", ["Different seeds"] = "Seeds différentes", ["Seed"] = "Seed", ["Random"] = "Aléatoire",
        ["Each player picks a deck"] = "Chaque joueur choisit son jeu",
        ["Timers"] = "Minuteurs", ["Ready timer"] = "Minuteur de prêt",
        ["Timer length"] = "Durée du minuteur", ["Extra time per ante"] = "Temps en plus par mise initiale", ["Free timeouts"] = "Retards pardonnés",
        ["PvP countdown"] = "Décompte JcJ",
        ["Helpers allowed"] = "Aides autorisées", ["Hand Optimizer"] = "Optimiseur de main", ["Score preview"] = "Aperçu du score",
        ["Run"] = "Partie", ["View"] = "Voir", ["Choose"] = "Choisir", ["chosen"] = "choisis", ["None"] = "Aucun",
        ["Your presets"] = "Vos préréglages", ["Slot"] = "Emplacement", ["Load"] = "Charger", ["Save"] = "Sauver",
        ["Rulesets"] = "Règles", ["This match"] = "Ce match", ["Ruleset"] = "Règles", ["Modifiers"] = "Modificateurs",
        ["Hide enemy score"] = "Cacher le score adverse",
        ["Ranked rules"] = "Règles classées", ["Daily rules"] = "Règles du jour", ["Weekly rules"] = "Règles de la semaine",
        ["RANKED RULES"] = "RÈGLES CLASSÉES", ["DAILY RULES"] = "RÈGLES DU JOUR", ["WEEKLY RULES"] = "RÈGLES DE LA SEMAINE",
        ["These rules are fixed for this match."] = "Ces règles sont fixes pour ce match.",
        ["Only the host can change settings."] = "Seul l'hôte peut changer les réglages.", ["Host"] = "Hôte",
        ["Default multiplayer rules"] = "Règles multijoueur par défaut", ["Changes from default"] = "Changements",
        ["and"] = "et", ["more"] = "de plus", ["Overview"] = "Aperçu", ["Match"] = "Match", ["Players"] = "Joueurs",
        ["MATCH SETTINGS"] = "RÉGLAGES DU MATCH", ["MATCH SETTINGS (VIEW ONLY)"] = "RÉGLAGES DU MATCH (LECTURE)", ["Reset"] = "Réinitialiser",
        ["Multiplayer stake"] = "Mise multijoueur", ["Settings"] = "Paramètres", ["View settings"] = "Voir les réglages", ["Choose jokers"] = "Choisir des jokers",
    },
    es = {
        ["Spectate while waiting"] = "Mirar mientras esperas", ["Watch once your hands are played"] = "Mirar al terminar tus manos",
        ["Mode"] = "Modo", ["Lives"] = "Vidas", ["PvP from ante"] = "JcJ desde la apuesta inicial", ["Final ante"] = "Última apuesta inicial",
        ["Auto"] = "Auto",
        ["Boss blinds are PvP from the chosen ante"] = "Los jefes son JcJ desde la apuesta inicial elegida",
        ["Every blind is PvP from the chosen ante"] = "Cada ciega es JcJ desde la apuesta inicial elegida",
        ["No PvP, lives only go on failed blinds"] = "Sin JcJ, vidas solo al fallar una ciega",
        ["Lives and money"] = "Vidas y dinero", ["Failed blind costs a life"] = "Fallar una ciega cuesta una vida",
        ["PvP win bonus"] = "Bonus por victoria JcJ",
        ["Life steal"] = "Robo de vida",
        ["Content"] = "Contenido", ["Multiplayer jokers"] = "Comodines multijugador",
        ["Mode bans"] = "Vetos del modo",
        ["Shared queue"] = "Cola común",
        ["Seeds and decks"] = "Códigos y barajas", ["Different seeds"] = "Códigos distintos", ["Seed"] = "Código", ["Random"] = "Aleatoria",
        ["Each player picks a deck"] = "Cada jugador elige baraja",
        ["Timers"] = "Temporizadores", ["Ready timer"] = "Temporizador de listo",
        ["Timer length"] = "Duración", ["Extra time per ante"] = "Tiempo extra por apuesta inicial", ["Free timeouts"] = "Retrasos perdonados",
        ["PvP countdown"] = "Cuenta atrás JcJ",
        ["Helpers allowed"] = "Ayudas permitidas", ["Hand Optimizer"] = "Optimizador de mano", ["Score preview"] = "Vista previa de puntos",
        ["Run"] = "Partida", ["View"] = "Ver", ["Choose"] = "Elegir", ["chosen"] = "elegidos", ["None"] = "Ninguno",
        ["Your presets"] = "Tus ajustes", ["Slot"] = "Espacio", ["Load"] = "Cargar", ["Save"] = "Guardar",
        ["Rulesets"] = "Reglas", ["This match"] = "Esta partida", ["Ruleset"] = "Reglas", ["Modifiers"] = "Modificadores",
        ["Hide enemy score"] = "Ocultar puntuación rival",
        ["Ranked rules"] = "Reglas clasificatorias", ["Daily rules"] = "Reglas del día", ["Weekly rules"] = "Reglas de la semana",
        ["RANKED RULES"] = "REGLAS CLASIFICATORIAS", ["DAILY RULES"] = "REGLAS DEL DÍA", ["WEEKLY RULES"] = "REGLAS DE LA SEMANA",
        ["These rules are fixed for this match."] = "Estas reglas son fijas para esta partida.",
        ["Only the host can change settings."] = "Solo el anfitrión puede cambiar los ajustes.", ["Host"] = "Anfitrión",
        ["Default multiplayer rules"] = "Reglas multijugador por defecto", ["Changes from default"] = "Cambios sobre lo predeterminado",
        ["and"] = "y", ["more"] = "más", ["Overview"] = "Resumen", ["Match"] = "Partida", ["Players"] = "Jugadores",
        ["MATCH SETTINGS"] = "AJUSTES DE PARTIDA", ["MATCH SETTINGS (VIEW ONLY)"] = "AJUSTES DE PARTIDA (SOLO LECTURA)", ["Reset"] = "Restablecer",
        ["Multiplayer stake"] = "Pozo multijugador", ["Settings"] = "Ajustes", ["View settings"] = "Ver ajustes", ["Choose jokers"] = "Elegir comodines",
    },
    }
end

local function register_preset_strings()
    mod_loc_register{
        ["en-us"] = {["Run (rules tab)"] = "Run", ["Random (seed)"] = "Random"},
        fr = {["SAVE PRESET"] = "SAUVER LE PRÉRÉGLAGE", ["Preset name"] = "Nom du préréglage", ["Run (rules tab)"] = "Partie", ["Random (seed)"] = "Aléatoire", [": "] = " : "},
        es = {["SAVE PRESET"] = "GUARDAR AJUSTE", ["Preset name"] = "Nombre del ajuste", ["Run (rules tab)"] = "Básico", ["Random (seed)"] = "Aleatorio", [": "] = ": "},
    }
end

local function register_player_strings()
    mod_loc_register{
    fr = {
        ["Random pick"] = "Tirage au sort", ["Each player gets their own seed"] = "Chaque joueur a sa propre seed",
        ["Blank: a new seed each match"] = "Vide : nouvelle seed à chaque match",
        ["A deck is rolled every match"] = "Un jeu tiré au sort à chaque match",
        ["Everyone picks a deck at match start"] = "Chacun choisit son jeu au lancement",
        ["Draft bans, then everyone picks from 3"] = "Draft de bans, puis chacun choisit parmi 3",
        ["Decided by the deck draft"] = "Décidé par le draft de jeux",
        ["Only %d: starting jokers fill the slots"] = "Seulement %d : les jokers de départ prennent les places",
        ["Everyone starts with this deck"] = "Tout le monde part avec ce jeu",
        ["Everyone picks theirs at match start"] = "Chacun choisit le sien au lancement",
        ["Starting joker picks"] = "Jokers de départ choisis",
        ["Everyone picks jokers at match start"] = "Chacun choisit ses jokers au lancement",
        ["Pick %d Common or Uncommon at match start"] = "%d communs ou peu communs, au lancement",
        ["Clock for the last player to ready up"] = "Chrono pour le dernier à être prêt",
        ["Time to ready up before a timeout"] = "Temps pour être prêt avant le retard",
        ["Added to the timer every ante"] = "Ajouté au chrono à chaque mise",
        ["Then each timeout costs a life"] = "Ensuite chaque retard coûte une vie",
        ["Countdown before each PvP blind"] = "Décompte avant chaque blinde JcJ",
        ["Off: game speed is capped at 4x"] = "Désactivé : vitesse limitée à 4x",
        ["Off: hidden until the match ends"] = "Désactivé : cachée jusqu'à la fin",
        ["Players can use the Hand Optimizer"] = "Les joueurs peuvent utiliser l'optimiseur",
        ["Shows the score before you play"] = "Montre le score avant de jouer",
    },
    es = {
        ["Random pick"] = "Sorteo", ["Each player gets their own seed"] = "Cada jugador tiene su propia semilla",
        ["Blank: a new seed each match"] = "Vacío: semilla nueva en cada partida",
        ["A deck is rolled every match"] = "Se sortea una baraja en cada partida",
        ["Everyone picks a deck at match start"] = "Cada uno elige baraja al empezar",
        ["Draft bans, then everyone picks from 3"] = "Vetos, luego cada uno elige entre 3",
        ["Decided by the deck draft"] = "Lo decide el veto de barajas",
        ["Only %d: starting jokers fill the slots"] = "Solo %d: los comodines iniciales llenan los huecos",
        ["Everyone starts with this deck"] = "Todos empiezan con esta baraja",
        ["Everyone picks theirs at match start"] = "Cada uno elige la suya al empezar",
        ["Starting joker picks"] = "Comodines iniciales a elegir",
        ["Everyone picks jokers at match start"] = "Cada uno elige comodines al empezar",
        ["Pick %d Common or Uncommon at match start"] = "%d comunes o poco comunes, al empezar",
        ["Clock for the last player to ready up"] = "Reloj para el último en estar listo",
        ["Time to ready up before a timeout"] = "Tiempo para estar listo",
        ["Added to the timer every ante"] = "Se suma en cada apuesta inicial",
        ["Then each timeout costs a life"] = "Luego cada retraso cuesta una vida",
        ["Countdown before each PvP blind"] = "Cuenta atrás antes de cada ciega JcJ",
        ["Off: game speed is capped at 4x"] = "Desactivado: velocidad máxima 4x",
        ["Off: hidden until the match ends"] = "Desactivado: oculta hasta el final",
        ["Players can use the Hand Optimizer"] = "Se puede usar el optimizador de manos",
        ["Shows the score before you play"] = "Muestra la puntuación antes de jugar",
    },
    }
end
if mod_loc_register then pcall(register_player_strings) end

local match_strings_done = false
function M.register_match_strings()
    if match_strings_done or not mod_loc_register then return end
    match_strings_done = true
    mod_loc_register{
        ["en-us"] = {["Random (stake)"] = "Random"},
        fr = {
            ["Everyone starts with %d"] = "Chacun commence avec %d",
            ["Every boss blind is PvP"] = "Chaque boss est en JcJ",
            ["Normal bosses before ante %d"] = "Boss normaux avant la mise %d",
            ["Every blind is PvP from the start"] = "Chaque blinde est en JcJ dès le début",
            ["Normal blinds before ante %d"] = "Blindes normales avant la mise %d",
            ["Clear ante %d to win"] = "Passez la mise %d pour gagner",
            ["Ends at ante %d, then sudden death"] = "Fin à la mise %d, puis mort subite",
            ["Replaced by the Multiplayer stake"] = "Remplacée par la mise multijoueur",
            ["White to Gold, rolled at each start"] = "De blanche à or, tirée à chaque match",
            ["Orange rules without the Blue shop tax"] = "Règles orange sans la taxe bleue",
            ["Nova + Rental jokers, score grows faster"] = "Nova + jokers en location, score plus rapide",
            ["Eclipse, score grows even faster"] = "Éclipse, score encore plus rapide",
            ["None: the Stake above is used"] = "Aucune : la mise ci-dessus compte",
            ["Boss effect on PvP"] = "Effet de boss en JcJ",
            ["PvP boss blind adds a random boss effect"] = "Le boss JcJ ajoute un effet de boss au hasard",
            ["Off: you just keep playing"] = "Désactivé : vous continuez à jouer",
            ["Money for a lost life"] = "Argent par vie perdue",
            ["+$3 per life lost ($2 at Purple Stake+)"] = "+3 $ par vie perdue (2 $ dès la mise violette)",
            ["No blind reward on a loss"] = "Pas de gain de blinde si perdue",
            ["A lost blind or PvP pays $0 reward"] = "Blinde ou JcJ perdu : 0 $ de gain",
            ["Off: no extra money for a PvP win"] = "Désactivé : pas d'argent en plus",
            ["+$%d each time you win a PvP blind"] = "+%d $ par blinde JcJ gagnée",
            ["PvP win: +1 life, up to your starting lives"] = "Victoire JcJ : +1 vie, jusqu'au total de départ",
            ["Hidden until you play your first PvP hand"] = "Caché jusqu'à votre première main JcJ",
            ["PvP-only jokers can show up in shops"] = "Les jokers JcJ peuvent sortir en boutique",
            ["Bans %d jokers, %d vouchers, %d tag"] = "Interdit %d jokers, %d bons, %d badge",
            ["Same card order"] = "Même ordre de cartes",
            ["Both players get cards in the same order"] = "Les deux joueurs ont les cartes dans le même ordre",
            ["Random stake: "] = "Mise aléatoire : ",
            ["Random (stake)"] = "Aléatoire",
        },
        es = {
            ["Everyone starts with %d"] = "Todos empiezan con %d",
            ["Every boss blind is PvP"] = "Cada jefe es JcJ",
            ["Normal bosses before ante %d"] = "Jefes normales antes de la apuesta %d",
            ["Every blind is PvP from the start"] = "Cada ciega es JcJ desde el inicio",
            ["Normal blinds before ante %d"] = "Ciegas normales antes de la apuesta %d",
            ["Clear ante %d to win"] = "Supera la apuesta %d para ganar",
            ["Ends at ante %d, then sudden death"] = "Acaba en la apuesta %d, luego muerte súbita",
            ["Replaced by the Multiplayer stake"] = "Sustituido por el pozo multijugador",
            ["White to Gold, rolled at each start"] = "De blanco a oro, sorteado en cada partida",
            ["Orange rules without the Blue shop tax"] = "Reglas naranja sin el impuesto azul",
            ["Nova + Rental jokers, score grows faster"] = "Nova + comodines de alquiler, puntos más rápidos",
            ["Eclipse, score grows even faster"] = "Eclipse, puntos aún más rápidos",
            ["None: the Stake above is used"] = "Ninguno: se usa el pozo de arriba",
            ["Boss effect on PvP"] = "Efecto de jefe en JcJ",
            ["PvP boss blind adds a random boss effect"] = "El jefe JcJ suma un efecto de jefe al azar",
            ["Off: you just keep playing"] = "Desactivado: sigues jugando",
            ["Money for a lost life"] = "Dinero por vida perdida",
            ["+$3 per life lost ($2 at Purple Stake+)"] = "+$3 por vida perdida ($2 desde pozo morado)",
            ["No blind reward on a loss"] = "Sin premio de ciega al perder",
            ["A lost blind or PvP pays $0 reward"] = "Ciega o JcJ perdido: premio de $0",
            ["Off: no extra money for a PvP win"] = "Desactivado: sin dinero extra",
            ["+$%d each time you win a PvP blind"] = "+$%d por cada ciega JcJ ganada",
            ["PvP win: +1 life, up to your starting lives"] = "Victoria JcJ: +1 vida, hasta las iniciales",
            ["Hidden until you play your first PvP hand"] = "Oculta hasta tu primera mano JcJ",
            ["PvP-only jokers can show up in shops"] = "Los comodines JcJ pueden salir en tienda",
            ["Bans %d jokers, %d vouchers, %d tag"] = "Veta %d comodines, %d vales, %d etiqueta",
            ["Same card order"] = "Mismo orden de cartas",
            ["Both players get cards in the same order"] = "Ambos reciben las cartas en el mismo orden",
            ["Random stake: "] = "Pozo aleatorio: ",
            ["Random (stake)"] = "Aleatorio",
        },
    }
end

local function register_party_strings()
    mod_loc_register{
        fr = {
            ["Every blind is PvP"] = "Chaque blinde en JcJ", ["Small and Big blinds too, not only Boss"] = "Petite et grosse blindes aussi, pas que le boss",
            ["AFK limit"] = "Limite d'inactivité", ["PvP goes on without anyone idle this long"] = "Le JcJ continue sans qui reste inactif ce temps",
            ["Players hit per blind"] = "Joueurs touchés par blinde", ["Lowest score loses 1 life"] = "Le plus bas score perd 1 vie",
            ["Lowest %d scores lose 1 life each"] = "Les %d plus bas scores perdent 1 vie chacun",
            ["Ties for lowest"] = "Égalité en bas", ["Scores tied at the losing spot"] = "Scores égaux à la place perdante",
            ["When a knockout leaves 2, both go to 1 life"] = "Quand il en reste 2, les deux passent à 1 vie",
            ["Players per team, at least 2 teams"] = "Joueurs par équipe, au moins 2 équipes",
            ["Best teammate counts 100%, others this %"] = "Le meilleur compte à 100 %, les autres à ce %",
            ["Off: players pick their own team"] = "Désactivé : chacun choisit son équipe",
            ["Off: only knocked-out players can watch"] = "Désactivé : seuls les éliminés regardent",
            ["Off: only knocked-out players see them"] = "Désactivé : seuls les éliminés les voient",
            ["Shared: a failed raid costs 1"] = "Partagées : un raid raté en coûte 1",
            ["Boss blind x players x this, x3 at ante 1"] = "Boss x joueurs x ceci, x3 à la mise initiale 1", ["Early antes: x3 at ante 1, down to x1 at ante 7"] = "Début de partie : x3 à la mise initiale 1, x1 dès la 7",
            ["Target grows this much each ante after 1"] = "L'objectif monte d'autant par mise initiale après 1",
        },
        es = {
            ["Every blind is PvP"] = "Cada ciega es JcJ", ["Small and Big blinds too, not only Boss"] = "Ciega pequeña y grande también, no solo el jefe",
            ["AFK limit"] = "Límite de inactividad", ["PvP goes on without anyone idle this long"] = "El JcJ sigue sin quien esté inactivo tanto",
            ["Players hit per blind"] = "Jugadores castigados por ciega", ["Lowest score loses 1 life"] = "La puntuación más baja pierde 1 vida",
            ["Lowest %d scores lose 1 life each"] = "Las %d puntuaciones más bajas pierden 1 vida",
            ["Ties for lowest"] = "Empates abajo", ["Scores tied at the losing spot"] = "Puntuaciones empatadas en el puesto perdedor",
            ["When a knockout leaves 2, both go to 1 life"] = "Si quedan 2 tras una eliminación, ambos a 1 vida",
            ["Players per team, at least 2 teams"] = "Jugadores por equipo, al menos 2 equipos",
            ["Best teammate counts 100%, others this %"] = "El mejor cuenta al 100 %, los demás a este %",
            ["Off: players pick their own team"] = "Desactivado: cada uno elige equipo",
            ["Off: only knocked-out players can watch"] = "Desactivado: solo miran los eliminados",
            ["Off: only knocked-out players see them"] = "Desactivado: solo los ven los eliminados",
            ["Shared: a failed raid costs 1"] = "Compartidas: un raid fallido cuesta 1",
            ["Boss blind x players x this, x3 at ante 1"] = "Jefe x jugadores x esto, x3 en la apuesta inicial 1", ["Early antes: x3 at ante 1, down to x1 at ante 7"] = "Al principio: x3 en la apuesta inicial 1, x1 desde la 7",
            ["Target grows this much each ante after 1"] = "El objetivo sube esto por apuesta inicial tras la 1",
        },
    }
end

local ready = false
ensure = function()
    if ready or not (G and G.FUNCS and RunRules and UIK) then return ready end
    ready = true
    if mod_loc_register then register_strings(); register_preset_strings(); register_player_strings(); M.register_match_strings(); register_party_strings() end
    for _, c in ipairs(RunRules.CATEGORIES) do CAT_LABEL[c.key] = c.label end
    for _, d in ipairs(RunRules.list()) do
        if d.kind == "list" and not bom_match.MP_EXCLUDED_RULES[d.key] then
            G.FUNCS["mpls_pick_" .. d.key] = function() open_list(d.key) end
        end
    end
    for k, f in pairs(FUNCS) do G.FUNCS[k] = f end
    return true
end

return M
