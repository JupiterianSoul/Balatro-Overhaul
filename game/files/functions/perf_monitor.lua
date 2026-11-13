PERF_MON = {
    enabled = false,
    LOG_FILE = "perf_spikes.log",
    FLUSH_SECONDS = 4,
    SPIKE_FACTOR = 1.5,
}
local PM = PERF_MON

local raw_append = love.filesystem.append
local raw_gc = collectgarbage
local clock = love.timer.getTime
local floor = math.floor
local fmt = string.format

local seg, cnt, depth = {}, {}, {}
local UPRE = setmetatable({}, { __index = function(t, k) local v = "u." .. tostring(k) t[k] = v return v end })
local DPRE = setmetatable({}, { __index = function(t, k) local v = "d." .. tostring(k) t[k] = v return v end })
local loop_t, lap_t, loop_seen = nil, nil, false
local upd_t0, drw_t0, cp_upd, cp_drw = nil, nil, nil, nil
local upd_ms, drw_ms, ev_ms, pres_ms, pace_ms, pgc_ms = 0, 0, 0, 0, 0, 0
local kb0 = 0
local last_mp = "-"
local slow_path
local target_ms, refresh_hz, vsync = 1000 / 60, 0, 1
local buf, buf_n = {}, 0
local last_flush, flush_ms = 0, 0
local writer, writer_ch = nil, nil
local state_names = {}

local HBIN, HMAX = 0.25, 400
local function new_stats()
    local s = { hist = {}, frames = 0, spikes = 0, upd = 0, drw = 0, drops = 0, alloc = 0, max = 0, t0 = 0 }
    for i = 0, HMAX do s.hist[i] = 0 end
    return s
end
local win, ses = new_stats(), new_stats()

local WRITER = [[
require("love.filesystem")
local path, chname, full = ...
local ch = love.thread.getChannel(chname)
while true do
    local s = ch:demand()
    if type(s) ~= "string" then break end
    local f = full and io.open(full, "ab")
    if f then
        f:write(s)
        f:close()
    else
        love.filesystem.append(path, s)
    end
end
]]

local WRAPS = {
    { "save_run", "save_run" },
    { "STR_PACK", "str_pack" },
    { "Game.save_progress", "save_progress" },
    { "Game.save_settings", "save_settings" },
    { "love.filesystem.write", "fs.write" },
    { "love.filesystem.append", "fs.append" },
    { "love.filesystem.read", "fs.read" },
    { "json.decode", "json.dec" },
    { "json.encode", "json.enc" },
    { "UIBox.init", "ui.new" },
    { "UIBox.recalculate", "ui.recalc" },
    { "DynaText.init", "text.new" },
    { "Card.init", "card.new" },
    { "love.graphics.newCanvas", "gfx.canvas" },
    { "love.graphics.newShader", "gfx.shader" },
    { "love.graphics.newImage", "gfx.image" },
    { "love.graphics.newFont", "gfx.font" },
    { "AndroidWS.poll", "mp.ws_poll" },
    { "MP.core.update", "mp.core" },
    { "MP.ranked.update", "mp.ranked" },
    { "MP.social.update", "mp.social" },
    { "MP.emotes.update", "mp.emotes" },
    { "MP.rejoin.update", "mp.rejoin" },
    { "MP.sync.update", "mp.sync" },
    { "MP.custom_objects.update", "mp.objects" },
    { "MP.decks.update", "mp.decks" },
    { "MP.pvp_hud.ensure_for_current_blind", "mp.pvp_hud" },
    { "MP.party.update", "mp.party" },
    { "MP.replay.update", "mp.replay" },
    { "MP.playback.update", "mp.playback" },
    { "MP.traps.update", "mp.traps" },
    { "MP.draft.update", "mp.draft" },
    { "MP.race.update", "mp.race" },
}

local function add(label, ms)
    seg[label] = (seg[label] or 0) + ms
end

local function make_wrap(fn, label)
    local keep = label:sub(1, 3) == "fs."
    local function done(t0, arg, ...)
        depth[label] = 0
        local ms = (clock() - t0) * 1000
        seg[label] = (seg[label] or 0) + ms
        cnt[label] = (cnt[label] or 0) + 1
        if keep and ms > 5 then slow_path = tostring(arg):gsub("%s", "_") end
        return ...
    end
    return function(...)
        if not PM.enabled or (depth[label] or 0) > 0 then return fn(...) end
        depth[label] = 1
        local t0 = clock()
        return done(t0, (...), fn(...))
    end
end

local function resolve(path)
    local t = _G
    local key
    for part in path:gmatch("[^%.]+") do
        if key then
            t = t[key]
            if type(t) ~= "table" then return nil end
        end
        key = part
    end
    return t, key
end

local function install_wraps()
    for _, w in ipairs(WRAPS) do
        local ok, t, k = pcall(resolve, w[1])
        if ok and t then
            local fn = rawget(t, k)
            if type(fn) == "function" then t[k] = make_wrap(fn, w[2]) end
        end
    end
    collectgarbage = function(opt, arg)
        if PM.enabled and (opt == nil or opt == "collect") then
            local t0 = clock()
            local r = raw_gc(opt, arg)
            add("gc.full", (clock() - t0) * 1000)
            cnt["gc.full"] = (cnt["gc.full"] or 0) + 1
            return r
        end
        return raw_gc(opt, arg)
    end
end

local function refresh_target()
    local hz, vs = 0, 1
    local ok, _, _, flags = pcall(love.window.getMode)
    if ok and type(flags) == "table" then
        hz = flags.refreshrate or 0
        if flags.vsync ~= nil then vs = flags.vsync end
    end
    if love.window.getVSync then
        local ok2, v = pcall(love.window.getVSync)
        if ok2 and v ~= nil then vs = v end
    end
    refresh_hz, vsync = hz, vs
    if PM.target_override then
        target_ms = PM.target_override
        return
    end
    local fps = hz > 0 and hz or 60
    local cap = G and G.FPS_CAP
    if cap and cap > 0 and cap < 9999 and (cap < fps or vs == 0 or vs == false) then fps = cap end
    target_ms = 1000 / fps
end

local function state_key()
    if not (G and G.STATE and G.STATES) then return "-" end
    local s = state_names[G.STATE]
    if s then return s end
    for k, v in pairs(G.STATES) do
        if v == G.STATE then
            state_names[G.STATE] = k
            return k
        end
    end
    return tostring(G.STATE)
end

local function overlay_name()
    local o = G and G.OVERLAY_MENU
    if not o then return "none" end
    if type(o) == "table" then
        local id = o.config and o.config.id
        if not id and type(o.definition) == "table" and o.definition.config then id = o.definition.config.id end
        if id then return (tostring(id):gsub("%s", "_")) end
    end
    return "open"
end

local function top3()
    local a, av, b, bv, c, cv = nil, 0, nil, 0, nil, 0
    for k, v in pairs(seg) do
        if v > av then
            c, cv, b, bv, a, av = b, bv, a, av, k, v
        elseif v > bv then
            c, cv, b, bv = b, bv, k, v
        elseif v > cv then
            c, cv = k, v
        end
    end
    return a, av, b, bv, c, cv
end

local function fmt_top(k, v)
    if not k then return "-" end
    local n = cnt[k]
    if n and n > 0 then return fmt("%s:%.2f(x%d)", k, v, n) end
    return fmt("%s:%.2f", k, v)
end

local function pct(s, p)
    if s.frames == 0 then return 0 end
    local want, acc = s.frames * p, 0
    for i = 0, HMAX - 1 do
        acc = acc + s.hist[i]
        if acc >= want then return (i + 0.5) * HBIN end
    end
    return s.max
end

local function add_frame(s, interval, alloc, dropped)
    s.frames = s.frames + 1
    s.upd = s.upd + upd_ms
    s.drw = s.drw + drw_ms
    s.alloc = s.alloc + alloc
    if dropped then s.drops = s.drops + 1 end
    if interval > s.max then s.max = interval end
    local bin = floor(interval / HBIN)
    if bin > HMAX then bin = HMAX end
    s.hist[bin] = s.hist[bin] + 1
end

local function push_line(line)
    buf_n = buf_n + 1
    buf[buf_n] = line
end

local function finish_frame(t, interval)
    local kb1 = raw_gc("count")
    local dropped = kb1 < kb0
    local alloc = dropped and 0 or (kb1 - kb0)
    local measure = PM.lua_mode and (ev_ms + upd_ms) or interval
    add_frame(win, measure, alloc, dropped)
    add_frame(ses, measure, alloc, dropped)
    if measure > target_ms * PM.SPIKE_FACTOR then
        win.spikes = win.spikes + 1
        ses.spikes = ses.spikes + 1
        local a, av, b, bv, c, cv = top3()
        local ui_n = (G and G.I and G.I.UIBOX and #G.I.UIBOX) or 0
        local mv_n = (G and G.MOVEABLES and #G.MOVEABLES) or 0
        local lw = love.window
        local foc = lw and lw.hasFocus and lw.hasFocus() and 1 or 0
        local vis = lw and lw.isVisible and lw.isVisible() and not (lw.isMinimized and lw.isMinimized()) and 1 or 0
        push_line(fmt("S t=%.2f ms=%.2f tgt=%.2f ev=%.2f upd=%.2f drw=%.2f pgc=%.2f pace=%.2f pres=%.2f top=%s,%s,%s state=%s ovl=%s ui=%d mv=%d kb0=%.0f kb1=%.0f gc=%d mp=%s foc=%d vis=%d fsw=%s",
            t - ses.t0, interval, target_ms, ev_ms, upd_ms, drw_ms, pgc_ms, pace_ms, pres_ms,
            fmt_top(a, av), fmt_top(b, bv), fmt_top(c, cv),
            state_key(), overlay_name(), ui_n, mv_n, kb0, kb1, dropped and 1 or 0, last_mp,
            foc, vis, slow_path or "-"))
    end
    slow_path = nil
    kb0 = kb1
end

local function stats_line(tag, s, t)
    local secs = math.max(t - s.t0, 0.001)
    local n = math.max(s.frames, 1)
    return fmt("%s t=%.1f secs=%.1f frames=%d spikes=%d p50=%.2f p99=%.2f p999=%.2f max=%.2f upd=%.3f drw=%.3f gcdrops=%d allockbs=%.0f flushms=%.3f tgt=%.2f hz=%d vsync=%s cap=%s state=%s",
        tag, t - ses.t0, secs, s.frames, s.spikes, pct(s, 0.5), pct(s, 0.99), pct(s, 0.999), s.max,
        s.upd / n, s.drw / n, s.drops, s.alloc / secs, flush_ms, target_ms, refresh_hz, tostring(vsync), tostring(G and G.FPS_CAP), state_key())
end

local function reset_stats(s, t)
    s.frames, s.spikes, s.upd, s.drw, s.drops, s.alloc, s.max, s.t0 = 0, 0, 0, 0, 0, 0, 0, t
    local h = s.hist
    for i = 0, HMAX do h[i] = 0 end
end

local function write_out(s, sync)
    if writer then
        local err = writer:getError()
        if err or not writer:isRunning() then
            writer, writer_ch = nil, nil
            pcall(raw_append, PM.LOG_FILE, "writer thread stopped: " .. tostring(err) .. "\n")
        end
    end
    if writer_ch and not sync then
        writer_ch:push(s)
    elseif writer_ch then
        writer_ch:push(s)
        writer_ch:push(false)
        pcall(writer.wait, writer)
        writer, writer_ch = nil, nil
    else
        pcall(raw_append, PM.LOG_FILE, s)
    end
end

function PM.flush(sync)
    if not PM.enabled then return end
    local t0 = clock()
    push_line(stats_line("W", win, t0))
    push_line(stats_line("T", ses, t0))
    local s = table.concat(buf, "\n", 1, buf_n) .. "\n"
    for i = 1, buf_n do buf[i] = nil end
    buf_n = 0
    write_out(s, sync)
    reset_stats(win, t0)
    refresh_target()
    local t1 = clock()
    flush_ms = (t1 - t0) * 1000
    last_flush = t1
end

local function reset_frame()
    for k in pairs(seg) do seg[k] = 0 end
    for k in pairs(cnt) do cnt[k] = 0 end
    for k in pairs(depth) do depth[k] = 0 end
    upd_ms, drw_ms, ev_ms, pres_ms, pace_ms, pgc_ms = 0, 0, 0, 0, 0, 0
end

local function boundary(t)
    if loop_t then finish_frame(t, (t - loop_t) * 1000) end
    loop_t = t
    reset_frame()
    if t - last_flush > PM.FLUSH_SECONDS then
        PM.flush()
        seg["perf.flush"] = flush_ms
    end
    lap_t = clock()
end

local function header()
    local os_name = love.system.getOS and love.system.getOS() or "?"
    local cores = love.system.getProcessorCount and love.system.getProcessorCount() or 0
    local rn, rv, rvd, rdev = "?", "?", "?", "?"
    local ok, a, b, c, d = pcall(love.graphics.getRendererInfo)
    if ok then rn, rv, rvd, rdev = tostring(a), tostring(b), tostring(c), tostring(d) end
    local w, h = love.graphics.getDimensions()
    local pause = raw_gc("setpause", 200)
    raw_gc("setpause", pause)
    local stepmul = raw_gc("setstepmul", 200)
    raw_gc("setstepmul", stepmul)
    local gs = G and G.SETTINGS and G.SETTINGS.GRAPHICS or {}
    return fmt("\n== perf monitor on %s mode=%s version=%s os=%s cores=%d renderer=%s|%s|%s|%s size=%dx%d hz=%d vsync=%s cap=%s jit=%s gcpause=%s gcstepmul=%s perf_mode=%s gc_tuning=%s crt=%s bloom=%s shadows=%s texscale=%s render_scale=%s shader_q=%s\n",
        os.date("%Y-%m-%d %H:%M:%S"), PM.lua_mode and "lua" or "frame", tostring(G and G.VERSION), os_name, cores, rn, rv, rvd, rdev, w, h, refresh_hz, tostring(vsync),
        tostring(G and G.FPS_CAP), tostring(jit and jit.status and jit.status()), tostring(pause), tostring(stepmul),
        tostring(gs.performance_mode), tostring(gs.perf_gc_tuning), tostring(gs.crt), tostring(gs.bloom), tostring(gs.shadows),
        tostring(gs.texture_scaling), tostring(gs.perf_resolution), tostring(gs.perf_shader_quality))
end

local function start_writer()
    if not (love.thread and love.thread.newThread) then return end
    local ok, th = pcall(love.thread.newThread, WRITER)
    if not ok or not th then return end
    local chname = "perf_mon_out"
    local dok, dir = pcall(love.filesystem.getSaveDirectory)
    local full = dok and type(dir) == "string" and dir ~= "" and (dir .. "/" .. PM.LOG_FILE) or nil
    if not pcall(th.start, th, PM.LOG_FILE, chname, full) then return end
    writer, writer_ch = th, love.thread.getChannel(chname)
end

local function hook_focus()
    local prev = love.focus
    love.focus = function(f, ...)
        if prev then prev(f, ...) end
        if not f then PM.flush() end
    end
end

function PM.init()
    if PM._checked then return end
    PM._checked = true
    local on = G and G.SETTINGS and G.SETTINGS.GRAPHICS and G.SETTINGS.GRAPHICS.perf_log
    if not on and os.getenv and os.getenv("PERF_LOG") == "1" then on = true end
    if not on then
        local ok, info = pcall(love.filesystem.getInfo, "perf_log.on")
        on = ok and info ~= nil
    end
    if not on then return end
    if os.getenv then
        PM.lua_mode = os.getenv("PERF_LOG_LUA") == "1"
        PM.target_override = tonumber(os.getenv("PERF_LOG_TARGET_MS") or "")
    end
    clock = rawget(_G, "SOAK_REAL_TIME") or love.timer.getTime
    refresh_target()
    install_wraps()
    hook_focus()
    start_writer()
    local t = clock()
    last_flush, ses.t0, win.t0 = t, t, t
    kb0 = raw_gc("count")
    write_out(header(), false)
    PM.enabled = true
end

function PM.shutdown()
    if not PM.enabled then return end
    PM.flush(true)
    PM.enabled = false
end

function PM.note_mp_message(t)
    last_mp = tostring(t or "-")
end

function PM.add_sub(label, ms)
    if PM.enabled then add(label, ms) end
end

function PM.checkpoint(label, typ, reset)
    if not PM.enabled or reset or not label then return end
    local t = clock()
    if typ == "update" then
        if cp_upd then add(UPRE[label], (t - cp_upd) * 1000) end
        cp_upd = t
    elseif typ == "draw" then
        if cp_drw then add(DPRE[label], (t - cp_drw) * 1000) end
        cp_drw = t
    end
end

function PM.loop_top()
    if not PM.enabled then return end
    loop_seen = true
    boundary(clock())
end

function PM.lap(k)
    if not PM.enabled or not lap_t then return end
    local t = clock()
    local d = (t - lap_t) * 1000
    lap_t = t
    if k == "ev" then ev_ms = ev_ms + d
    elseif k == "pres" then pres_ms = pres_ms + d
    elseif k == "pace" then pace_ms = pace_ms + d
    elseif k == "pgc" then pgc_ms = pgc_ms + d
    end
end

function PM.frame_update_begin()
    if not PM.enabled then return end
    upd_t0 = clock()
    cp_upd = upd_t0
end

function PM.frame_update_end()
    if not PM.enabled or not upd_t0 then return end
    upd_ms = upd_ms + (clock() - upd_t0) * 1000
    upd_t0 = nil
end

function PM.frame_draw_begin()
    if not PM.enabled then return end
    drw_t0 = clock()
    cp_drw = drw_t0
end

function PM.frame_draw_end()
    if not PM.enabled or not drw_t0 then return end
    local t = clock()
    if cp_drw then add("d.tail", (t - cp_drw) * 1000) end
    drw_ms = drw_ms + (t - drw_t0) * 1000
    drw_t0 = nil
    if not loop_seen then boundary(t) end
end
