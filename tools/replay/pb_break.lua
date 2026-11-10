local T = ...
local step, wait, sleep, shot, ROLE = T.step, T.wait, T.sleep, T.shot, T.role
local PB, RP = bom_playback, bom_replay
local B = {}

local function st() return PB.state() or {} end

local function playing()
    local s = PB.state()
    return PB.active() and s ~= nil and not s.loading
end

function B.during()
    local pid0 = st().pid
    wait(function() return (st().i or 0) > 12 end, 120)
    local can = PB.can_switch()
    step("replay_break_can_switch_" .. ROLE, can, "pids=" .. tostring(#RP.pids(st().streams or {})))
    if not can then return end
    G.FUNCS.pb_switch()
    local ok = wait(function() return playing() and st().pid ~= pid0 end, 120)
    sleep(3)
    local s = st()
    step("replay_break_switch_" .. ROLE, ok and not s.drifted and PB.active(), string.format("pid %s>%s drifted=%s at=%s", tostring(pid0), tostring(s.pid), tostring(s.drifted), tostring(s.i)))
    shot("replay_break_switched")
    G.FUNCS.pb_switch()
    ok = wait(function() return playing() and st().pid == pid0 end, 120)
    s = st()
    step("replay_break_switch_back_" .. ROLE, ok and not s.drifted, string.format("pid=%s drifted=%s", tostring(s.pid), tostring(s.drifted)))
end

local function history_entry(id)
    local H = rawget(_G, "BO_HISTORY")
    for _, e in ipairs(H and H.load() or {}) do
        if e.replay == id then return H, e end
    end
    return H, nil
end

local function watch(entry)
    G.FUNCS.bo_hist_watch({ config = { ref_table = { id = entry.id } } })
    return wait(playing, 90)
end

local function on_detail()
    return G.OVERLAY_MENU ~= nil and G.OVERLAY_MENU:get_UIE_by_ID("bo_hist_watch") ~= nil
end

function B.after(id)
    local H, entry = history_entry(id)
    step("replay_history_mp_row_" .. ROLE, entry ~= nil and H.can_watch(entry), "id=" .. tostring(id))
    if not entry then return end
    pcall(H.open_detail, entry.id)
    sleep(1)
    local ok = watch(entry)
    step("replay_history_watch_starts_" .. ROLE, ok, "active=" .. tostring(PB.active()))
    if not ok then return end
    G.FUNCS.pb_ff()
    local half = math.floor(#(st().entries or {}) / 2)
    wait(function() return (st().i or 0) >= half end, 300)
    G.FUNCS.pb_leave()
    local back = wait(function() return G.STATE == G.STATES.MENU and not PB.active() and G.OVERLAY_MENU ~= nil end, 60)
    sleep(2)
    step("replay_history_leave_mid_" .. ROLE, back and G.PB_BAR == nil and not (G.GAME and G.GAME.multiplayer) and on_detail(),
        string.format("menu=%s bar=%s mp=%s detail=%s", tostring(G.STATE == G.STATES.MENU), tostring(G.PB_BAR ~= nil), tostring(G.GAME and G.GAME.multiplayer), tostring(on_detail())))
    shot("replay_history_after_leave")
    ok = watch(entry)
    step("replay_history_watch_again_" .. ROLE, ok)
    if not ok then return end
    G.FUNCS.pb_ff()
    ok = wait(function() return st().done end, 900)
    local s = st()
    step("replay_history_plays_clean_" .. ROLE, ok and not s.drifted, string.format("drifted=%s why=%s at=%s/%s", tostring(s.drifted), tostring(s.drift_why), tostring(s.i), tostring(s.entries and #s.entries)))
    PB.leave()
    wait(function() return G.STATE == G.STATES.MENU end, 60)
    sleep(3)
end

return B
