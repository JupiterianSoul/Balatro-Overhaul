local bom_daily = {}

local function L(s) return mod_loc and mod_loc(s) or s end

bom_daily.cache = {}
bom_daily.waiters = {}
bom_daily.pending = nil

local function kind_of(k) return k == "weekly" and "weekly" or "daily" end

local function now_ms() return os.time() * 1000 end

local function rulesets() return rawget(_G, "bom_rulesets") end
local function layers() return rawget(_G, "bom_layers") end

local function fresh(info)
    return type(info) == "table" and type(info.ends_at) == "number" and now_ms() < info.ends_at
end

function bom_daily.info(kind)
    local c = bom_daily.cache[kind_of(kind)]
    if not fresh(c) then return nil end
    local rs = c.ruleset or {}
    local R = rulesets()
    local name, desc = rs.name, rs.desc
    if R and type(rs.base) == "string" and R.BY_ID[rs.base] then
        name, desc = R.BY_ID[rs.base].name, R.BY_ID[rs.base].desc
    end
    local ly = layers()
    return {
        kind = c.kind, key = c.key, seed = c.seed, ends_at = c.ends_at, ruleset = rs,
        name = L(name or ""), desc = desc and L(desc) or nil,
        mode = R and R.mode_name(rs.mode or "nemesis") or tostring(rs.mode),
        layers = ly and ly.names and ly.names(rs.layers) or {},
        deck = rs.settings and rs.settings.deck or nil,
        seconds_left = math.max(0, math.floor((c.ends_at - now_ms()) / 1000)),
        completed = bom_daily.is_completed(c.kind, c.key),
    }
end

function bom_daily.time_left_text(kind)
    local i = bom_daily.info(kind)
    if not i then return nil end
    local s = i.seconds_left
    local d, h, m = math.floor(s / 86400), math.floor(s % 86400 / 3600), math.floor(s % 3600 / 60)
    if d > 0 then return L("Ends in") .. " " .. d .. L("d") .. " " .. h .. L("h") end
    if h > 0 then return L("Ends in") .. " " .. h .. L("h") .. " " .. m .. L("min") end
    return L("Ends in") .. " " .. math.max(1, m) .. L("min")
end

function bom_daily.request(kind, cb)
    kind = kind_of(kind)
    local c = bom_daily.cache[kind]
    if fresh(c) then
        if cb then pcall(cb, bom_daily.info(kind)) end
        return true
    end
    if cb then
        bom_daily.waiters[kind] = bom_daily.waiters[kind] or {}
        table.insert(bom_daily.waiters[kind], cb)
    end
    local core = rawget(_G, "bom_core")
    if not (core and core.connect and core.send) then return false end
    pcall(core.connect, function() core.send({type = "daily_get", kind = kind}) end)
    return false
end

function bom_daily.on_ruleset(d)
    if type(d) ~= "table" or type(d.ruleset) ~= "table" then return true end
    local kind = kind_of(d.kind)
    bom_daily.cache[kind] = d
    local R = rulesets()
    if R and type(d.ruleset.id) == "string" then R.server[d.ruleset.id] = R.deep_copy(d.ruleset) end
    local list = bom_daily.waiters[kind] or {}
    bom_daily.waiters[kind] = nil
    local info = bom_daily.info(kind)
    for _, cb in ipairs(list) do pcall(cb, info) end
    return true
end

function bom_daily.play(kind)
    kind = kind_of(kind)
    bom_daily.request(kind, function(info)
        if not info then return end
        bom_daily.pending = {kind = kind, ruleset = info.ruleset, key = info.key}
        local room = rawget(_G, "bom_room")
        if room and room.create then room.create("private") end
    end)
end

function bom_daily.start(kind)
    pcall(function() if G.OVERLAY_MENU then G.FUNCS.exit_overlay_menu() end end)
    bom_daily.play(kind)
end

local function on_room_created()
    local p = bom_daily.pending
    if not p then return end
    bom_daily.pending = nil
    local R = rulesets()
    if not (R and R.later and R.apply_server) then return end
    R.later(function()
        R.apply_server(p.ruleset, p.kind)
        local m = rawget(_G, "bom_match")
        local st = m and m.get_state and m.get_state()
        if type(st) == "table" then st.bom_daily = {kind = p.kind, key = p.key} end
    end)
end

local function profile()
    local ok, p = pcall(function() return G.PROFILES[G.SETTINGS.profile] end)
    return ok and p or nil
end

function bom_daily.is_completed(kind, key)
    local p = profile()
    local done = p and p.progression and p.progression.mp_daily_done
    return type(done) == "table" and done[kind_of(kind)] == key
end

function bom_daily.fetch() end

function bom_daily.apply_modifier() end

function bom_daily.try_complete()
    if not (G and G.GAME) then return end
    local rec = G.GAME.bom_daily
    if type(rec) ~= "table" or type(rec.key) ~= "string" then return end
    local kind = kind_of(rec.kind)
    if bom_daily.is_completed(kind, rec.key) then return end
    local p = profile()
    if not (p and p.progression) then return end
    p.progression.mp_daily_done = type(p.progression.mp_daily_done) == "table" and p.progression.mp_daily_done or {}
    p.progression.mp_daily_done[kind] = rec.key
    pcall(function() if award_xp then award_xp(kind == "weekly" and 150 or 80, "bom_" .. kind .. "_challenge") end end)
    if kind == "daily" then
        pcall(function()
            if QuestManager and QuestManager.get_active_quests then
                for _, q in ipairs(QuestManager.get_active_quests() or {}) do
                    if q and q.id == "bom_daily_completed" then QuestManager.update_quest_progress(q, 1) end
                end
            end
        end)
        local yesterday = os.date("!%Y-%m-%d", os.time() - 86400)
        if p.progression.mp_last_daily == yesterday then
            p.progression.bom_daily_streak = (p.progression.bom_daily_streak or 0) + 1
        elseif p.progression.mp_last_daily ~= rec.key then
            p.progression.bom_daily_streak = 1
        end
        p.progression.mp_last_daily = rec.key
        G.GAME.bom_daily_streak = p.progression.bom_daily_streak
        G.GAME.mp_last_daily = rec.key
    end
    pcall(function() if AchievementManager and AchievementManager.check_all then AchievementManager.check_all() end end)
    pcall(function() if G.save_progress then G:save_progress() end end)
end

function bom_daily.get_info()
    local i = bom_daily.info("daily")
    local p = profile()
    return {
        date = i and i.key or os.date("!%Y-%m-%d"),
        active = i ~= nil,
        completed = i and i.completed or false,
        modifier = i and {name = i.name, desc = i.desc} or nil,
        streak = p and p.progression and p.progression.bom_daily_streak or 0,
        info = i,
    }
end

bom_daily.FR = {["Ends in"] = "Fin dans", ["d"] = " j", ["h"] = " h", ["min"] = " min"}
bom_daily.ES = {["Ends in"] = "Termina en", ["d"] = " d", ["h"] = " h", ["min"] = " min"}

function bom_daily.load()
    if mod_loc_register then mod_loc_register({fr = bom_daily.FR, es = bom_daily.ES}) end
    local ev = rawget(_G, "bom_events")
    if ev and ev.register and not bom_daily._registered then
        bom_daily._registered = true
        ev.register("daily_ruleset", bom_daily.on_ruleset)
        ev.register("room_created", on_room_created)
    end
end

return bom_daily
