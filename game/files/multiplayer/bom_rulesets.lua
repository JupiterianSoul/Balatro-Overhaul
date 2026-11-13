local R = {}

local function L(s) return mod_loc and mod_loc(s) or s end

local function layers()
    return rawget(_G, "bom_layers") or package.loaded["multiplayer.bom_layers"]
end

local function bmatch()
    return rawget(_G, "bom_match") or package.loaded["multiplayer.bom_match"]
end

local function deep_copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deep_copy(x) end
    return t
end
R.deep_copy = deep_copy

local function state()
    local m = bmatch()
    local st = m and m.get_state and m.get_state()
    return type(st) == "table" and st or {}
end

local function settings()
    local m = bmatch()
    return (m and m.get_settings and m.get_settings()) or {}
end

local function party_on()
    local p = rawget(_G, "bom_party")
    if not (p and p.active) then return false end
    local ok, on = pcall(p.active)
    return ok and on == true
end

local CATS = {"jokers", "consumables", "vouchers", "blinds", "tags"}
local NEMESIS_BLIND = "bl_mp_nemesis"

R.NEW_SETTINGS = {hide_opp_score = false, layers = {}, ruleset_id = "", pool_seed = "", mp_stake = ""}

function R.install_settings()
    local m = bmatch()
    local d = m and m.DEFAULT_SETTINGS
    if type(d) ~= "table" then return false end
    for k, v in pairs(R.NEW_SETTINGS) do
        if d[k] == nil then d[k] = deep_copy(v) end
    end
    local st = m.get_state and m.get_state()
    if type(st) == "table" and type(st.settings) == "table" then
        for k, v in pairs(R.NEW_SETTINGS) do
            if st.settings[k] == nil then st.settings[k] = deep_copy(v) end
        end
    end
    return true
end

R.MODES = {
    {key = "nemesis", name = "Rivals"},
    {key = "faceoff", name = "FaceOff"},
    {key = "ascension", name = "Ascension"},
    {key = "br", name = "Battle Royale", party = true},
    {key = "teams", name = "Teams", party = true},
    {key = "raid", name = "Co-op Raid", party = true},
}
R.MODE_BY_KEY = {}
for _, m in ipairs(R.MODES) do R.MODE_BY_KEY[m.key] = m end

R.LIST, R.BY_ID, R.BY_MODE = {}, {}, {}
R.server = {}

function R.add_mode(def)
    if type(def) ~= "table" or type(def.key) ~= "string" then return nil end
    if not R.MODE_BY_KEY[def.key] then R.MODES[#R.MODES + 1] = def end
    R.MODE_BY_KEY[def.key] = def
    R.BY_MODE[def.key] = R.BY_MODE[def.key] or {}
    return def
end

local function norm_bans(b)
    local out = {}
    for _, c in ipairs(CATS) do
        out[c] = {}
        for _, k in ipairs((type(b) == "table" and b[c]) or {}) do
            if type(k) == "string" and k ~= NEMESIS_BLIND then out[c][#out[c] + 1] = k end
        end
    end
    return out
end
R.norm_bans = norm_bans

function R.register(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or type(def.mode) ~= "string" then return nil end
    def.family = def.family or def.id
    def.settings = def.settings or {}
    def.bans = norm_bans(def.bans)
    def.reworks = def.reworks or {}
    def.layers = def.layers or {}
    if not R.BY_ID[def.id] then R.LIST[#R.LIST + 1] = def end
    R.BY_ID[def.id] = def
    if not def.hidden then
        if not R.MODE_BY_KEY[def.mode] then R.add_mode({key = def.mode, name = def.mode}) end
        local list = R.BY_MODE[def.mode] or {}
        R.BY_MODE[def.mode] = list
        local found = false
        for i, x in ipairs(list) do if x.id == def.id then list[i] = def found = true end end
        if not found then list[#list + 1] = def end
    end
    return def
end

local BALANCED = {"j_hanging_chad", "j_bloodstone", "m_glass"}
local EXPANDED = {"j_hanging_chad", "j_bloodstone", "m_glass", "j_ticket", "j_selzer", "j_turtle_bean", "c_ouija"}
local NO_JUSTICE = {consumables = {"c_justice"}}
R.BALANCED_REWORKS, R.EXPANDED_REWORKS = BALANCED, EXPANDED

local D_CLASSIC = "Our standard MP rules, no reworks"
local D_BALANCED = "MP balance reworks, Justice banned"
local D_SMALL = "Only a quarter of the cards exist, duplicates allowed"

local function family(mode, fam, extra)
    local base = {
        classic = {name = "Classic", desc = D_CLASSIC},
        balanced = {name = "Balanced", desc = D_BALANCED, reworks = BALANCED, bans = NO_JUSTICE, settings = {the_order = true}},
        small_world = {name = "Scarcity", desc = D_SMALL, reworks = EXPANDED, bans = NO_JUSTICE, layers = {"small_world"}},
    }
    local d = deep_copy(base[fam] or {})
    for k, v in pairs(extra or {}) do d[k] = deep_copy(v) end
    d.id, d.mode, d.family = mode .. "_" .. fam, mode, fam
    return R.register(d)
end

family("nemesis", "classic")
family("nemesis", "balanced")
R.register{id = "nemesis_vanilla", mode = "nemesis", family = "vanilla", name = "Vanilla", desc = "Plain Balatro cards, no MP jokers or reworks",
    settings = {multiplayer_jokers = false, the_order = false}}
R.register{id = "nemesis_traditional", mode = "nemesis", family = "traditional", name = "Slow burn", desc = "Balanced plus more reworks, no timer",
    reworks = EXPANDED, bans = NO_JUSTICE, settings = {timer = false, the_order = true}}
R.register{id = "nemesis_major", mode = "nemesis", family = "major", name = "Tournament", desc = "Tournament rules: 180 s timer, no helpers",
    reworks = {"j_bloodstone"}, settings = {timer = true, timer_base_seconds = 180, timer_increment_seconds = 0, timer_forgiveness = 0,
    the_order = false, multiplayer_jokers = false, allow_advisor = false, allow_hand_optimizer = false, allow_score_preview = false}}
family("nemesis", "small_world")
R.register{id = "nemesis_speed", mode = "nemesis", family = "speed", name = "Sprint", desc = "Rapid clock, PvP from ante 1, ends at ante 6",
    reworks = BALANCED, bans = NO_JUSTICE, layers = {"clock_blitz"}, settings = {pvp_start_round = 1, win_ante = 6}}
R.register{id = "nemesis_chaos", mode = "nemesis", family = "chaos", name = "Chaos", desc = "Scarcity, unstable score, mystery prices, life steal",
    layers = {"small_world", "score_wobble", "shop_mystery"}, settings = {life_steal = true, pvp_win_money = 3}}

family("faceoff", "classic")
family("faceoff", "balanced")
R.register{id = "faceoff_duel", mode = "faceoff", family = "duel", name = "Quick duel", desc = "Two lives, ends at ante 4, a head start",
    settings = {starting_lives = 2, win_ante = 4, rules = {hand_level = 2, dollars = 8}}}
R.register{id = "faceoff_blitz", mode = "faceoff", family = "speed", name = "Rapid fire", desc = "Three lives and the Rapid clock",
    reworks = BALANCED, bans = NO_JUSTICE, layers = {"clock_blitz"}, settings = {starting_lives = 3}}
family("faceoff", "small_world")

family("ascension", "classic")
family("ascension", "balanced")
R.register{id = "ascension_marathon", mode = "ascension", family = "marathon", name = "Marathon", desc = "Three lives and a long road to ante 12",
    settings = {starting_lives = 3, win_ante = 12, rules = {interest_cap = 50}}}
R.register{id = "ascension_glass", mode = "ascension", family = "glass", name = "Glass cannon", desc = "Fragile glass and steeper blinds",
    layers = {"glass_fragile"}, settings = {rules = {blind_growth = 2}}}
family("ascension", "small_world")

family("br", "classic")
family("br", "balanced")
R.register{id = "br_sudden", mode = "br", family = "sudden", name = "Sudden death", desc = "Two lives, the final two drop to one",
    settings = {starting_lives = 2, br_sudden_death = true}}
R.register{id = "br_bloodbath", mode = "br", family = "bloodbath", name = "Bloodbath", desc = "Two lowest scores lose a life, every blind counts",
    settings = {br_losers = 2, party_every_blind = true}}
family("br", "small_world")

family("teams", "classic")
family("teams", "balanced")
R.register{id = "teams_carry", mode = "teams", family = "carry", name = "No carry", desc = "Teammates count for half, everyone must score",
    settings = {team_share = 50}}
family("teams", "small_world")

family("raid", "classic")
family("raid", "balanced")
R.register{id = "raid_heroic", mode = "raid", family = "heroic", name = "Heroic", desc = "A tougher boss and two shared lives",
    settings = {raid_per_player = 160, raid_lives = 2}}
family("raid", "small_world")

R.RANKED = R.register{id = "ranked", mode = "nemesis", family = "ranked", hidden = true, locked = true,
    name = "Ranked", desc = "The same fixed rules for every ranked match.", reworks = BALANCED, bans = NO_JUSTICE,
    settings = {mode = "nemesis", starting_lives = 4, pvp_start_round = 2, showdown_starting_antes = 1, win_ante = false, stake = 1, deck = "Red Deck",
        different_decks = false, different_seeds = false, custom_seed = "random", gold_on_life_loss = true, no_gold_on_round_loss = false,
        death_on_round_loss = true, pvp_win_money = 0, life_steal = false, timer = true, timer_base_seconds = 150, timer_increment_seconds = 0,
        timer_forgiveness = 1, pvp_countdown_seconds = 3, the_order = true, balance_enabled = true, multiplayer_jokers = true, normal_bosses = false,
        allow_advisor = false, allow_hand_optimizer = false, allow_score_preview = false, joker_picks = 0, my_starting_jokers = {}, rules = {},
        allow_fast_speed = false, allow_score_speed = false, allow_skip_score = false, show_seed = false,
        spectate = true, spectate_jokers = false, hide_opp_score = true, layers = {}, ruleset_id = "ranked"}}

function R.modes(party)
    local out = {}
    for _, m in ipairs(R.MODES) do
        if party == nil or (m.party == true) == (party == true) then out[#out + 1] = m end
    end
    return out
end

function R.mode_name(key)
    local m = R.MODE_BY_KEY[key]
    return L(m and m.name or tostring(key))
end

function R.for_mode(mode)
    return R.BY_MODE[mode] or {}
end

function R.mode_of(s)
    s = s or settings()
    if party_on() then return s.party_kind or "br" end
    local m = s.mode or "nemesis"
    if m == "attrition" then m = "nemesis" elseif m == "showdown" then m = "faceoff" end
    return m
end

function R.find(mode, fam)
    for _, d in ipairs(R.for_mode(mode)) do if d.family == fam then return d end end
    return nil
end

function R.default_id(mode)
    local list = R.for_mode(mode)
    return list[1] and list[1].id or nil
end

function R.current_id(s)
    s = s or settings()
    local mode = R.mode_of(s)
    local id = s.ruleset_id
    if R.server[id] then return id end
    local d = R.BY_ID[id]
    if d and not d.hidden and d.mode == mode then return id end
    local pm = d and R.MODE_BY_KEY[d.mode]
    if d and not d.hidden and pm and pm.party and d.mode == s.party_kind and (mode == "nemesis" or mode == "faceoff") then return id end
    if d and d.family then
        local f = R.find(mode, d.family)
        if f then return f.id end
    end
    return R.default_id(mode)
end

function R.name(id)
    local d = R.server[id] or R.BY_ID[id]
    return d and L(d.name or id) or nil
end

function R.desc(id)
    local d = R.server[id] or R.BY_ID[id]
    return d and d.desc and L(d.desc) or nil
end

local function valid_layers(list)
    local ly = layers()
    if ly and ly.valid then return ly.valid(list) end
    return type(list) == "table" and deep_copy(list) or {}
end

local function build(d, s)
    local lay = d.layers
    if s and type(s.layers) == "table" then lay = s.layers end
    local st = deep_copy(d.settings or {})
    st.ruleset_id = d.id
    st.layers = valid_layers(lay)
    return {
        id = d.id, name = d.name, desc = d.desc, mode = d.mode, settings = st,
        bans = norm_bans(d.bans), reworks = deep_copy(d.reworks or {}), layers = valid_layers(lay), locked = d.locked == true,
    }
end

function R.get(id)
    if type(id) ~= "string" then return nil end
    if R.server[id] then return deep_copy(R.server[id]) end
    local d = R.BY_ID[id]
    if not d then return nil end
    local s = settings()
    if s.ruleset_id == id or R.current_id(s) == id then return build(d, s) end
    return build(d, nil)
end

function R.lock_kind()
    local st = state()
    if st.bom_lock then return st.bom_lock end
    if st.ranked == true then return "ranked" end
    if type(st.ruleset) == "table" and st.ruleset.locked == true then return "ranked" end
    return nil
end

function R.locked() return R.lock_kind() ~= nil end

function R.effective(s)
    s = s or settings()
    local st = state()
    local srv = st.bom_server_rs
    if type(srv) ~= "table" and type(st.ruleset) == "table" and st.ruleset.locked == true then srv = st.ruleset end
    if type(srv) == "table" then
        local rs = deep_copy(srv)
        rs.bans = norm_bans(rs.bans)
        rs.reworks = type(rs.reworks) == "table" and rs.reworks or {}
        rs.layers = valid_layers(rs.layers or (rs.settings and rs.settings.layers))
        return rs
    end
    local id = R.current_id(s)
    local d = R.BY_ID[id]
    if not d then
        return {id = "", name = "", desc = "", mode = R.mode_of(s), settings = {}, bans = norm_bans(nil), reworks = {}, layers = valid_layers(s.layers), locked = false}
    end
    return build(d, s)
end

function R.describe(rs)
    rs = rs or R.effective()
    local out = {}
    if type(rs) ~= "table" then return out end
    out[#out + 1] = {L("Ruleset"), L(rs.name or "")}
    local ly = layers()
    local names = ly and ly.names and ly.names(rs.layers) or {}
    out[#out + 1] = {L("Modifiers"), #names > 0 and table.concat(names, ", ") or L("None")}
    local n = 0
    for _, c in ipairs(CATS) do n = n + #((rs.bans or {})[c] or {}) end
    out[#out + 1] = {L("Bans"), tostring(n)}
    out[#out + 1] = {L("Reworks"), tostring(#(rs.reworks or {}))}
    return out
end

local function random_seed()
    local m = bmatch()
    if m and m.random_seed then
        local ok, v = pcall(m.random_seed)
        if ok and v then return tostring(v) end
    end
    return tostring(math.random(10000000, 99999999))
end

local KEEP = {mode = true, deck = true, my_starting_jokers = true, custom_seed = true, different_seeds = true, different_decks = true, stake = true}

function R.settings_for(id, current)
    local d = R.BY_ID[id]
    local m = bmatch()
    if not (d and m and m.defaults) then return nil end
    current = current or settings()
    local fresh = m.defaults()
    for k in pairs(KEEP) do if current[k] ~= nil then fresh[k] = deep_copy(current[k]) end end
    for k in pairs(m.PARTY_KEYS or {}) do if current[k] ~= nil then fresh[k] = deep_copy(current[k]) end end
    for k, v in pairs(d.settings or {}) do
        if k ~= "mode" and k ~= "party_kind" then fresh[k] = deep_copy(v) end
    end
    local ly = layers()
    local lay = valid_layers(d.layers)
    if ly and ly.settings_for then
        for k, v in pairs(ly.settings_for(lay)) do fresh[k] = deep_copy(v) end
    end
    fresh.layers = lay
    fresh.ruleset_id = d.id
    if ly and ly.has and ly.has(lay, "small_world") then fresh.pool_seed = random_seed() end
    return fresh
end

function R.layer_change(s, ids)
    local d = R.BY_ID[R.current_id(s)]
    local m = bmatch()
    local defaults = m and m.DEFAULT_SETTINGS or {}
    local ly = layers()
    local out = {layers = valid_layers(ids)}
    local before = ly and ly.settings_for and ly.settings_for(s.layers) or {}
    local after = ly and ly.settings_for and ly.settings_for(out.layers) or {}
    for k in pairs(before) do
        if after[k] == nil then
            local v = d and d.settings and d.settings[k]
            if v == nil then v = defaults[k] end
            out[k] = deep_copy(v)
        end
    end
    for k, v in pairs(after) do out[k] = deep_copy(v) end
    if ly and ly.has and ly.has(out.layers, "small_world") and not ly.has(s.layers, "small_world") then out.pool_seed = random_seed() end
    return out
end

function R.apply_server(rs, kind)
    if type(rs) ~= "table" then return end
    local m = bmatch()
    if not m then return end
    rs = deep_copy(rs)
    rs.bans = norm_bans(rs.bans)
    rs.layers = valid_layers(rs.layers or (rs.settings and rs.settings.layers))
    rs.reworks = type(rs.reworks) == "table" and rs.reworks or {}
    if type(rs.id) == "string" then R.server[rs.id] = rs end
    local st = state()
    st.bom_lock = kind or "ranked"
    local base = type(rs.base) == "string" and R.BY_ID[rs.base] and not R.BY_ID[rs.base].hidden and rs.base or nil
    if st.bom_lock == "ranked" or not base then st.bom_server_rs = rs end
    if st.bom_lock == "ranked" then
        st.ranked = true
        st.ruleset = rs
    end
    local fresh = m.defaults and m.defaults() or {}
    for k in pairs(m.PARTY_KEYS or {}) do if st.settings and st.settings[k] ~= nil then fresh[k] = deep_copy(st.settings[k]) end end
    for k, v in pairs(rs.settings or {}) do fresh[k] = deep_copy(v) end
    local ly = layers()
    if ly and ly.settings_for then
        for k, v in pairs(ly.settings_for(rs.layers)) do fresh[k] = deep_copy(v) end
    end
    fresh.layers = deep_copy(rs.layers)
    fresh.ruleset_id = base or rs.id or ""
    if base and ly and ly.has and ly.has(rs.layers, "small_world") and (fresh.pool_seed == nil or fresh.pool_seed == "") then
        fresh.pool_seed = tostring(rs.settings and rs.settings.custom_seed or rs.id or "")
    end
    if m.get_phase and m.PHASE and m.get_phase() ~= m.PHASE.LOBBY then return end
    m.update_settings(fresh)
    if st.bom_lock ~= "ranked" and m.is_host_player and m.is_host_player() and m.sync_settings then m.sync_settings() end
    pcall(function()
        local ls = rawget(_G, "bom_lobby_settings")
        if ls and ls.is_open and ls.is_open() and UIK then UIK.refresh() end
    end)
end

function R.pool_seed(seed, s)
    s = s or settings()
    local m = bmatch()
    local diff = m and m.different_seeds and m.different_seeds(s)
    if not diff then return tostring(seed or s.custom_seed or "") end
    if type(s.pool_seed) == "string" and s.pool_seed ~= "" then return s.pool_seed end
    local st = state()
    return tostring(st.match_id or st.room_code or seed or "")
end

local function reworks_api()
    local r = rawget(_G, "bom_reworks")
    return type(r) == "table" and r or nil
end

function R.apply_reworks(keys)
    local api = reworks_api()
    if not api then return false end
    if api.clear then pcall(api.clear) end
    if type(keys) ~= "table" or #keys == 0 or not api.apply then return true end
    local list = keys
    if api.available then
        local ok, av = pcall(api.available)
        if ok and type(av) == "table" then
            local set = {}
            for k, v in pairs(av) do
                if type(k) == "number" and type(v) == "string" then set[v] = true elseif v then set[k] = true end
            end
            list = {}
            for _, k in ipairs(keys) do if set[k] then list[#list + 1] = k end end
        end
    end
    if #list > 0 then pcall(api.apply, list) end
    return true
end

function R.clear()
    local api = reworks_api()
    if api and api.clear then pcall(api.clear) end
    local ly = layers()
    if ly and ly.restore_centers then pcall(ly.restore_centers) end
    R._run, R._resumed = nil, nil
end

function R.rules_for_run(rules)
    local rs = R.effective()
    R._run = rs
    R.apply_reworks(rs.reworks)
    local ly = layers()
    if ly and ly.apply_centers then pcall(ly.apply_centers, rs.layers) end
    R._resumed = nil
    if ly and ly.rules_for then return ly.rules_for(rs.layers, rules) end
    return rules
end

local function own_blind(key)
    if key == NEMESIS_BLIND then return true end
    return type(key) == "string" and key:sub(1, 6) == "bl_mp_"
end

function R.after_start(seed)
    if not (G and G.GAME) then return end
    local s = settings()
    local rs = R._run or R.effective(s)
    G.GAME.banned_keys = G.GAME.banned_keys or {}
    for _, c in ipairs(CATS) do
        for _, k in ipairs((rs.bans or {})[c] or {}) do
            if not own_blind(k) then G.GAME.banned_keys[k] = true end
        end
    end
    local ly = layers()
    if ly and ly.start_run then ly.start_run(rs.layers, {pool_seed = R.pool_seed(seed, s)}) end
    local token = random_seed()
    G.GAME.bom_rs = {id = rs.id, layers = deep_copy(rs.layers), reworks = deep_copy(rs.reworks), token = token}
    R._resumed = token
    local st = state()
    local shown = deep_copy(rs)
    if ly and ly.bans_for then
        local extra = ly.bans_for(rs.layers)
        for _, c in ipairs(CATS) do
            shown.bans[c] = shown.bans[c] or {}
            for _, k in ipairs(extra[c] or {}) do shown.bans[c][#shown.bans[c] + 1] = k end
        end
    end
    if type(st.bom_daily) == "table" then G.GAME.bom_daily = deep_copy(st.bom_daily) end
    if st.bom_lock ~= "ranked" then shown.locked = false end
    if st.bom_lock and st.bom_lock ~= "ranked" then shown.kind = st.bom_lock end
    st.ruleset = shown
end

function R.resume()
    local rec = G and G.GAME and G.GAME.bom_rs
    if type(rec) ~= "table" or not G.GAME.multiplayer then return end
    if R._resumed and R._resumed == rec.token then return end
    R._resumed = rec.token or true
    R.apply_reworks(rec.reworks)
    local ly = layers()
    if ly and ly.apply_centers then pcall(ly.apply_centers, rec.layers) end
    local st = state()
    if type(st.ruleset) ~= "table" then
        local rs = R.server[rec.id] and deep_copy(R.server[rec.id]) or (R.BY_ID[rec.id] and build(R.BY_ID[rec.id], {layers = rec.layers}))
        if rs then
            rs.layers = valid_layers(rec.layers)
            rs.reworks = deep_copy(rec.reworks or {})
            if st.bom_lock ~= "ranked" then rs.locked = false end
            st.ruleset = rs
        end
    end
end

local function later(fn)
    if not (G and G.E_MANAGER and Event) then return pcall(fn) end
    G.E_MANAGER:add_event(Event({trigger = "immediate", blocking = false, blockable = false, func = function() pcall(fn) return true end}))
end
R.later = later

local function on_room_ready(d)
    if type(d) ~= "table" or d.ranked ~= true or type(d.ruleset) ~= "table" then return end
    local rs = d.ruleset
    later(function() R.apply_server(rs, "ranked") end)
end

local function on_session(d)
    if type(d) ~= "table" then return end
    local st = state()
    if d.match_id ~= nil then st.match_id = d.match_id end
    if d.ranked == true then
        st.ranked = true
        st.bom_lock = "ranked"
    end
    if type(d.ruleset) == "table" then
        local rs = deep_copy(d.ruleset)
        if type(rs.id) == "string" then R.server[rs.id] = rs end
        if d.ranked == true then
            st.bom_server_rs = rs
            st.ruleset = rs
        end
    end
end

local function on_rejoin(d)
    on_session(d)
    later(function() R._resumed = nil end)
end

local function wrap_reset()
    local m = bmatch()
    if not (m and m.reset) or R._reset_wrapped then return end
    R._reset_wrapped = true
    local orig = m.reset
    m.reset = function(...)
        local r = orig(...)
        local st = state()
        st.bom_server_rs, st.bom_lock, st.bom_daily = nil, nil, nil
        pcall(R.clear)
        return r
    end
end

R.FR = {
    ["Classic"] = "Classique", ["Our standard MP rules, no reworks"] = "Nos règles MP standard, sans refontes",
    ["Balanced"] = "Équilibré", ["MP balance reworks, Justice banned"] = "Refontes d'équilibrage MP, Justice interdite",
    ["Scarcity"] = "Pénurie", ["Only a quarter of the cards exist, duplicates allowed"] = "Seul un quart des cartes existe, doublons permis",
    ["Vanilla"] = "Vanilla", ["Plain Balatro cards, no MP jokers or reworks"] = "Cartes Balatro d'origine, sans jokers MP ni refontes",
    ["Slow burn"] = "Feu doux", ["Balanced plus more reworks, no timer"] = "Équilibré avec plus de refontes, sans minuteur",
    ["Tournament"] = "Tournoi", ["Tournament rules: 180 s timer, no helpers"] = "Règles de tournoi : minuteur de 180 s, sans aides",
    ["Sprint"] = "Sprint", ["Rapid clock, PvP from ante 1, ends at ante 6"] = "Chrono rapide, JcJ dès la mise initiale 1, fin à la 6",
    ["Chaos"] = "Chaos", ["Scarcity, unstable score, mystery prices, life steal"] = "Pénurie, score instable, prix mystère, vol de vie",
    ["Quick duel"] = "Duel rapide", ["Two lives, ends at ante 4, a head start"] = "Deux vies, fin à la mise initiale 4, départ avantagé",
    ["Rapid fire"] = "Tir rapide", ["Three lives and the Rapid clock"] = "Trois vies et le chrono rapide",
    ["Marathon"] = "Marathon", ["Three lives and a long road to ante 12"] = "Trois vies et une longue route jusqu'à la mise initiale 12",
    ["Glass cannon"] = "Canon de verre", ["Fragile glass and steeper blinds"] = "Verre fragile et blindes plus raides",
    ["Sudden death"] = "Mort subite", ["Two lives, the final two drop to one"] = "Deux vies, les deux derniers tombent à une",
    ["Bloodbath"] = "Carnage", ["Two lowest scores lose a life, every blind counts"] = "Les deux pires scores perdent une vie, chaque blinde compte",
    ["No carry"] = "Pas de passager", ["Teammates count for half, everyone must score"] = "Les coéquipiers comptent à moitié, tout le monde doit marquer",
    ["Heroic"] = "Héroïque", ["A tougher boss and two shared lives"] = "Un boss plus coriace et deux vies partagées",
    ["Ranked"] = "Classé", ["The same fixed rules for every ranked match."] = "Les mêmes règles fixes pour chaque match classé.",
    ["Rivals"] = "Rivaux", ["FaceOff"] = "FaceOff", ["Ascension"] = "Ascension", ["Battle Royale"] = "Battle Royale",
    ["Teams"] = "Équipes", ["Co-op Raid"] = "Raid coop",
    ["Ruleset"] = "Règles", ["Modifiers"] = "Modificateurs", ["Bans"] = "Interdits", ["Reworks"] = "Refontes", ["None"] = "Aucun",
}

R.ES = {
    ["Classic"] = "Clásico", ["Our standard MP rules, no reworks"] = "Nuestras reglas MP estándar, sin cambios",
    ["Balanced"] = "Equilibrado", ["MP balance reworks, Justice banned"] = "Cambios de equilibrio MP, Justicia vetada",
    ["Scarcity"] = "Escasez", ["Only a quarter of the cards exist, duplicates allowed"] = "Solo existe un cuarto de las cartas, se permiten repetidas",
    ["Vanilla"] = "Vanilla", ["Plain Balatro cards, no MP jokers or reworks"] = "Cartas de Balatro originales, sin comodines MP ni cambios",
    ["Slow burn"] = "Fuego lento", ["Balanced plus more reworks, no timer"] = "Equilibrado con más cambios, sin temporizador",
    ["Tournament"] = "Torneo", ["Tournament rules: 180 s timer, no helpers"] = "Reglas de torneo: temporizador de 180 s, sin ayudas",
    ["Sprint"] = "Sprint", ["Rapid clock, PvP from ante 1, ends at ante 6"] = "Reloj rápido, JcJ desde la apuesta inicial 1, fin en la 6",
    ["Chaos"] = "Caos", ["Scarcity, unstable score, mystery prices, life steal"] = "Escasez, puntuación inestable, precios misteriosos, robo de vida",
    ["Quick duel"] = "Duelo rápido", ["Two lives, ends at ante 4, a head start"] = "Dos vidas, fin en la apuesta inicial 4, con ventaja inicial",
    ["Rapid fire"] = "Fuego rápido", ["Three lives and the Rapid clock"] = "Tres vidas y el reloj rápido",
    ["Marathon"] = "Maratón", ["Three lives and a long road to ante 12"] = "Tres vidas y un largo camino hasta la apuesta inicial 12",
    ["Glass cannon"] = "Cañón de cristal", ["Fragile glass and steeper blinds"] = "Cristal frágil y ciegas más duras",
    ["Sudden death"] = "Muerte súbita", ["Two lives, the final two drop to one"] = "Dos vidas, los dos últimos bajan a una",
    ["Bloodbath"] = "Masacre", ["Two lowest scores lose a life, every blind counts"] = "Las dos peores puntuaciones pierden una vida, cada ciega cuenta",
    ["No carry"] = "Sin pasajeros", ["Teammates count for half, everyone must score"] = "Los compañeros cuentan la mitad, todos deben puntuar",
    ["Heroic"] = "Heroico", ["A tougher boss and two shared lives"] = "Un jefe más duro y dos vidas compartidas",
    ["Ranked"] = "Clasificatoria", ["The same fixed rules for every ranked match."] = "Las mismas reglas fijas para cada partida clasificatoria.",
    ["Rivals"] = "Rivales", ["FaceOff"] = "FaceOff", ["Ascension"] = "Ascensión", ["Battle Royale"] = "Battle Royale",
    ["Teams"] = "Equipos", ["Co-op Raid"] = "Raid cooperativo",
    ["Ruleset"] = "Reglas", ["Modifiers"] = "Modificadores", ["Bans"] = "Vetos", ["Reworks"] = "Cambios", ["None"] = "Ninguno",
}

function R.init()
    R.install_settings()
    if mod_loc_register then mod_loc_register({fr = R.FR, es = R.ES}) end
    local ly = layers()
    if ly then
        if ly.init then pcall(ly.init) end
        ly.on_frame = R.resume
    end
    wrap_reset()
    local ev = rawget(_G, "bom_events")
    if ev and ev.register then
        ev.register("room_ready", on_room_ready)
        ev.register("match_session", on_session)
        ev.register("match_start", on_session)
        ev.register("rejoin_ok", on_rejoin)
    end
end

R.install_settings()

return R
