local L = require("lang")
local C = require("core")
local P = require("feed")
local V = require("saves")

local maybe_ask, pad_repeat
local S = {tab = "play", games = {}, frame = 0, feed = {state = "off"}, tab_time = 0, page = 1}
local U, X

local function t(key, ...)
    local lang = L[S.lang] or L.en
    local s = (C.PHONE and (lang["phone_" .. key] or L.en["phone_" .. key])) or lang[key] or L.en[key] or key
    if select("#", ...) > 0 then
        return string.format(s, ...)
    end
    return s
end

local function vname(x)
    if type(x) ~= "table" then
        return tostring(x)
    end
    return tostring(x.overhaul_name or x.name or x.overhaul_version or x.version or "?")
end

local function vtext(v)
    return (tostring(v):gsub("%-FULL", ""))
end

local function err_text(err)
    local m = C.manifest() or {}
    if not err then
        return t("err_missing"), t("err_missing_hint")
    end
    local code = err.code
    if err.where == "xbox" and (code == "version" or code == "modded") then
        return t("err_xbox_build", vtext(err.found or "?")), t("err_xbox_build_hint", vtext(m.game_version or "?"))
    elseif code == "protected" then
        return t("err_protected"), t("err_protected_hint")
    elseif code == "read" then
        return t("err_read", tostring(err.file)), nil
    elseif code == "not_game" then
        return t("err_not_game"), t("err_missing_hint")
    elseif code == "version" then
        return t("err_version", vtext(err.found), err.overhaul and tostring(err.overhaul) or vname(m), vtext(err.wanted)),
            t("err_version_hint", vtext(err.wanted))
    elseif code == "modded" then
        return t("err_modded", tostring(err.files[1]), #err.files), t("err_modded_hint")
    elseif code == "write" then
        return t("err_write", tostring(err.file)), nil
    elseif code == "download" then
        return t("dl_failed", tostring(err.detail or "?")), t("dl_hint")
    elseif code == "damaged" then
        return t("dl_damaged"), t("dl_hint")
    elseif code == "bad" then
        return t("dl_bad"), t("dl_hint")
    elseif code == "no_reinstall" then
        return t("no_reinstall"), nil
    end
    return t("err_patch", tostring(err.file or code)), nil
end

local function short_err(err)
    local code = err and err.code
    if err and err.where == "xbox" and (code == "version" or code == "modded") then
        return t("bad_xbox_build")
    elseif code == "protected" then
        return t("bad_protected")
    elseif code == "version" then
        return t("bad_version", vtext(err.found))
    elseif code == "modded" then
        return t("bad_modded")
    elseif code == "not_game" then
        return t("bad_not_game")
    elseif code == "read" then
        return t("bad_read")
    end
    return (err_text(err))
end

local function set_msg(text, hint, kind)
    S.msg, S.hint, S.msg_kind = text, hint, kind or "info"
end

local function run_task(fn, done)
    S.task = coroutine.create(fn)
    S.task_done = done
end

local function step_task(budget)
    if not S.task then
        return
    end
    local t0 = love.timer.getTime()
    repeat
        local ok, a, b = coroutine.resume(S.task)
        if not ok then
            S.task = nil
            S.progress = nil
            set_msg(t("err_patch", tostring(a)), nil, "error")
            print("launcher: task failed: " .. tostring(a))
            return
        end
        if coroutine.status(S.task) == "dead" then
            local done = S.task_done
            S.task, S.task_done = nil, nil
            if done then
                done(a, b)
            end
            return
        end
    until a == "frame" or love.timer.getTime() - t0 > budget
end

local function load_game_font(z)
    if not U or not X or not z then
        return
    end
    X.borrow(z, U)
    X.mute = X.mute or C.settings().sounds == false
end

local function tag_err(g, err)
    if err then
        err.where = g.where
        err.found = err.found or g.version
    end
    return err
end

local function full_check(g)
    g.status = "checking"
    local ok, err, z = C.full_check(g.path, function()
        coroutine.yield()
    end)
    load_game_font(z)
    if ok then
        g.status, g.version, g.err = "ok", ok.version, nil
    else
        g.status, g.err = "error", tag_err(g, err)
        g.version = err and err.found or g.version
    end
    z = nil
    collectgarbage()
end

local function check_games(prefer)
    S.games = C.scan()
    S.sel = nil
    S.checking = true
    run_task(function()
        for _, g in ipairs(S.games) do
            g.status = "checking"
            coroutine.yield()
            local ok, err, z
            if g.protected then
                err = {code = "protected"}
            else
                ok, err, z = C.quick_check(g.path)
                load_game_font(z)
                z = nil
            end
            if ok then
                g.status, g.version = "quick", ok.version
            else
                g.version = err and err.found
                g.status, g.err = "error", tag_err(g, err)
            end
            collectgarbage()
            coroutine.yield()
        end
        local want = prefer or C.settings().game_path
        for _, g in ipairs(S.games) do
            if g.path == want then
                S.sel = g
            end
        end
        if not S.sel or S.sel.status == "error" then
            for _, g in ipairs(S.games) do
                if g.status ~= "error" then
                    S.sel = g
                    break
                end
            end
        end
        S.sel = S.sel or S.games[1]
        if S.sel and S.sel.status == "quick" then
            full_check(S.sel)
        end
        for _, g in ipairs(S.games) do
            if g.status == "quick" then
                g.status = "ok"
            end
        end
    end, function()
        S.checking = false
        maybe_ask()
    end)
end

local function pick(path, label)
    local p = C.resolve_pick(path)
    if not p then
        set_msg(label or t("err_read", tostring(path)), t("drop_hint"), "error")
        return
    end
    C.settings().game_path = p
    C.save_settings()
    set_msg(nil)
    S.tab = "game"
    S.page = 1
    check_games(p)
end

local function stamp_state()
    local m = C.manifest()
    local st = C.stamp()
    if st and not love.filesystem.getInfo(C.GAME_FOLDER .. "/main.lua") then
        st = nil
    end
    return st, m
end

local function game_ready()
    return S.sel and S.sel.status == "ok"
end

local function only_protected()
    for _, g in ipairs(S.games) do
        if not g.protected then
            return false
        end
    end
    return #S.games > 0
end

local function feed_new()
    return S.feed.state == "new" and S.feed.entry
end

local function stamp_key()
    local st = C.stamp()
    return st and (tostring(st.overhaul_version) .. "@" .. tostring(st.time)) or ""
end

local function refresh_installed()
    if S.task or S.handoff or S.shot_mode then
        return
    end
    local now = love.timer.getTime()
    if S.stamp_at and now < S.stamp_at then
        return
    end
    S.stamp_at = now + 1.5
    local key = stamp_key()
    if S.stamp_seen == nil or key == S.stamp_seen then
        S.stamp_seen = key
        return
    end
    S.stamp_seen = key
    C._settings = nil
    if P.restore() and S.feed.entry then
        S.feed.state = P.status(S.feed.entry)
    end
    local st, m = stamp_state()
    print("launcher: install changed to " .. key .. ", update feed " .. tostring(S.feed.state))
    pcall(io.stdout.flush, io.stdout)
    if st and m and st.overhaul_version == m.overhaul_version and S.feed.state ~= "new" then
        set_msg(t("up_to_date", vname(m)), nil, "ok")
    end
end

local function install_done(res, err)
    S.progress = nil
    S.stamp_seen = stamp_key()
    if res then
        set_msg(t("done_install", vname(C.manifest() or {})), nil, "ok")
        local sc_ok, sc = pcall(function() return require("shortcuts").install(C, require("patcher.find")) end)
        if sc_ok and sc then
            local parts = {}
            if sc.linux == "ok" then parts[#parts + 1] = t("sc_menu") elseif sc.lnk then parts[#parts + 1] = t("sc_lnk") end
            if sc.steam == "ok" then parts[#parts + 1] = t("sc_steam") elseif sc.steam == "running" then parts[#parts + 1] = t("sc_steam_running") end
            if #parts > 0 then set_msg(t("done_install", vname(C.manifest() or {})) .. " " .. table.concat(parts, " "), nil, "ok") end
        end
        if S.handoff then
            S.play_after = S.handoff.play
            S.handoff = nil
        end
    else
        local a, b = err_text(err)
        set_msg(a, b, "error")
        S.handoff = nil
    end
end

local function do_install()
    if S.task then
        return
    end
    if not game_ready() then
        if S.sel and S.sel.err then
            set_msg(err_text(S.sel.err))
            S.msg_kind = "error"
        else
            set_msg(t("need_game"), nil, "error")
        end
        return
    end
    local path = S.sel.path
    local entry = feed_new()
    S.progress = {stage = entry and "downloading" or "reading"}
    set_msg(nil)
    local function progress(stage, i, n)
        S.progress = {stage = stage, i = i, n = n}
        coroutine.yield()
    end
    run_task(function()
        if entry then
            local res, err = P.update(entry, path, progress, function()
                coroutine.yield("frame")
            end)
            if res then
                S.feed.state = "latest"
            end
            return res, err
        end
        return C.install(path, progress)
    end, install_done)
end

local function do_play()
    if S.task then
        return
    end
    if not stamp_state() then
        set_msg(t("need_install"), nil, "error")
        return
    end
    local ok, cmd = C.play(S.sel and S.sel.path)
    if ok then
        set_msg(t("starting"), nil, "ok")
    else
        set_msg(t("start_failed", cmd), nil, "error")
    end
end

local function do_apk()
    if S.task then
        return
    end
    local tool = C.apk_tool()
    if not tool then
        set_msg(t("apk_missing"), nil, "error")
        return
    end
    if not game_ready() then
        set_msg(t("need_game"), nil, "error")
        return
    end
    local path = S.sel.path
    S.progress = {stage = "reading"}
    run_task(function()
        return tool.run({
            game_path = path,
            game_dir = C.game_dir(),
            icon = C.apk_icon and C.apk_icon(path) or nil,
            out_dir = love.filesystem.getSaveDirectory(),
            lang = S.lang,
            progress = function(i, n)
                S.progress = {stage = "installing", i = i, n = n}
                coroutine.yield()
            end,
        })
    end, function(res, err)
        S.progress = nil
        if res then
            set_msg(t("apk_done", tostring(res)), nil, "ok")
        elseif type(err) == "table" then
            local a, b = err_text(err)
            set_msg(a, b, "error")
        else
            set_msg(t("apk_failed", tostring(err)), nil, "error")
        end
    end)
end

local APP_MODE = C.PHONE and C.app_info ~= nil and not (rawget(_G, "OVERHAUL_PHONE") or {}).direct

local function refresh_app()
    if not APP_MODE then
        return
    end
    S.app = C.app_info() or false
    if S.app then
        local apk = love.filesystem.getInfo(C.APP_APK)
        if apk and not S.task and (S.app.time or 0) / 1000 >= (apk.modtime or 0) - 5 then
            love.filesystem.remove(C.APP_APK)
        end
        if C.drop_launcher_game and not S.task then
            C.drop_launcher_game()
        end
    end
end

local APP_PENDING = "app_pending"

local function start_app_install()
    if not C.can_install() then
        S.wait_allow = true
        love.filesystem.write(APP_PENDING, "1\n")
        set_msg(t("app_allow"), t("app_allow_hint"), "info")
        return
    end
    S.wait_allow = nil
    love.filesystem.remove(APP_PENDING)
    if C.install_app() then
        S.wait_app = true
        set_msg(t("app_confirm"), nil, "info")
    else
        set_msg(t("app_install_fail"), nil, "error")
    end
end

local function do_make_app()
    if S.task then
        return
    end
    if not game_ready() then
        set_msg(t("need_game"), nil, "error")
        return
    end
    if love.filesystem.getInfo(C.APP_APK) and not S.app then
        start_app_install()
        return
    end
    local carry = V.overhaul_files(true) or {}
    S.progress = {stage = "building", i = 0, n = 1}
    set_msg(nil)
    run_task(function()
        return C.build_app({carry = carry, yield = function(i, n)
            S.progress = i and {stage = "building", i = i, n = n} or {stage = "signing"}
            coroutine.yield()
        end})
    end, function(res, err)
        S.progress = nil
        collectgarbage()
        if res then
            start_app_install()
        elseif type(err) == "table" and err.code ~= "app_build" and err.code ~= "no_maker" then
            local a, b = err_text(err)
            set_msg(a, b, "error")
        else
            set_msg(t("app_build_fail", tostring(type(err) == "table" and (err.file or err.code) or err)), nil, "error")
        end
    end)
end

local function do_open_app()
    if C.open_app() then
        set_msg(t("starting"), nil, "ok")
    else
        refresh_app()
        set_msg(t("app_open_fail"), nil, "error")
    end
end

local function app_focus()
    if not APP_MODE then
        return
    end
    local had = S.app
    refresh_app()
    if S.wait_allow and not S.task and C.can_install() then
        start_app_install()
    elseif S.wait_app and S.app and (not had or (S.app.time or 0) ~= (had.time or 0)) then
        S.wait_app = nil
        if had then
            set_msg(t("app_updated"), nil, "ok")
        else
            set_msg(t("app_done"), next(V.overhaul_files(true) or {}) and t("app_saves_moved") or nil, "ok")
        end
    end
end

local function save_err(err)
    local k = "serr_" .. tostring(err)
    local s = t(k)
    return s ~= k and s or tostring(err)
end

local function prof_lines(info)
    local out = {}
    for _, p in ipairs(info or {}) do
        out[#out + 1] = p.name and p.name ~= "" and t("prof_named", p.name, p.wins, p.rounds) or t("prof_line", p.slot, p.wins, p.rounds)
    end
    return out
end

local function info_text(info, scale, w)
    local full = table.concat(prof_lines(info), "   ")
    if #full == 0 then
        return t("save_empty")
    end
    local f = U.font(scale)
    if f:getWidth(full) <= w then
        return full
    end
    local short = {}
    for _, p in ipairs(info) do
        short[#short + 1] = t("prof_short", (p.name and p.name ~= "") and p.name or ("P" .. p.slot), p.wins)
    end
    for n = #short, 1, -1 do
        local s = table.concat(short, "   ", 1, n) .. (n < #short and ("   +" .. (#short - n)) or "")
        if f:getWidth(s) <= w or n == 1 then
            return s
        end
    end
end

local function refresh_saves()
    if not V.supported() then
        S.saves, S.osave = {}, {}
        return
    end
    S.saves = V.find(S.games)
    S.osave = V.overhaul_info()
end

local function load_save(src, kind, confirmed)
    if S.task then
        return
    end
    if not confirmed and #(S.osave or {}) > 0 and S.confirm ~= src then
        S.confirm = src
        set_msg(t("load_confirm"), nil, "info")
        return
    end
    S.confirm = nil
    local n, err = V.load(src.files, kind)
    if n then
        local set = C.settings()
        set.save_choice = kind
        C.save_settings()
        S.osave = V.overhaul_info()
        set_msg(t("load_ok", n), nil, "ok")
    else
        set_msg(t("load_fail", save_err(err)), nil, "error")
    end
    return n
end

local function choose_new()
    local set = C.settings()
    set.save_choice = "new"
    C.save_settings()
    S.ask = nil
    set_msg(t("choice_new"), nil, "ok")
end

local function import_path(path)
    local files, err = V.read_import(path)
    if not files then
        S.tab = "saves"
        set_msg(t("load_fail", save_err(err)), t("saves_hint"), "error")
        return
    end
    local src = {path = C.clean_path(path), where = "file", files = files, info = require("save_io").describe(files)}
    S.picked_save = src
    S.ask = nil
    S.tab = "saves"
    load_save(src, "file")
end

local function do_export()
    local path, err = V.export()
    if path then
        set_msg(t("export_ok", path), nil, "ok")
        if not S.shot_mode then
            V.open_folder(V.EXPORTS)
        end
    else
        set_msg(err == "empty" and t("export_empty") or t("load_fail", save_err(err)), nil, "error")
    end
end

maybe_ask = function()
    if S.asked or S.checking or not V.supported() then
        return
    end
    S.asked = true
    refresh_saves()
    if C.settings().save_choice == nil and S.saves[1] and not S.shot_mode and not S.handoff and not os.getenv("LAUNCHER_NO_ASK") then
        S.ask = S.saves[1]
        V.backup("balatro", S.ask.files)
    end
end

local function stamp_ok()
    local st, m = stamp_state()
    return st, m or {}
end

local function to_tab(key)
    if S.tab ~= key then
        S.tab = key
        S.tab_time = U.time
        S.page = 1
        set_msg(nil)
    end
end

local TAB_KEYS = C.PHONE and {"play", "game", "saves", "settings", "about"} or {"play", "game", "saves", "android", "settings", "about"}

local function phone_layout(W, H)
    local sx, sy, sw, sh = 0, 0, W, H
    if love.window.getSafeArea then
        sx, sy, sw, sh = love.window.getSafeArea()
    end
    local portrait = sh > sw * 1.05
    local lay = {W = W, H = H, portrait = portrait, touch = true, phone = true}
    lay.pad_u = 0.3
    lay.gap_u = 0.25
    lay.title_u = 0.8
    lay.tab_u = 1.5
    lay.tab_rows = 1
    lay.foot_u = 0
    local margin = math.floor(math.min(sw, sh) * 0.03 + 0.5)
    local fw, fh = sw - 2 * margin, sh - 2 * margin
    local head_u = lay.pad_u + lay.title_u + 0.2 + lay.tab_u + lay.gap_u + 0.2 + lay.pad_u
    if portrait then
        U.u = math.floor(math.min(fw / 11.2, fh / (head_u + 15)) + 0.5)
    else
        U.u = math.floor(math.min(fh / (head_u + 7.2), fw / 16) + 0.5)
    end
    local u = U.u
    U.text_k = 1.08
    lay.u = u
    lay.bw_u = fw / u - 2 * lay.pad_u
    lay.bh_u = fh / u - head_u
    lay.ww, lay.wh = fw, fh
    lay.wx, lay.wy = sx + margin, sy + margin
    lay.cx = lay.wx + lay.ww / 2
    lay.pad = U.px(lay.pad_u)
    lay.ix, lay.iw = lay.wx + lay.pad, lay.ww - 2 * lay.pad
    lay.title_y = lay.wy + lay.pad + U.px(lay.title_u / 2)
    lay.tab_y = lay.wy + lay.pad + U.px(lay.title_u + 0.2)
    lay.tab_h = U.px(lay.tab_u)
    lay.by = lay.tab_y + lay.tab_h + U.px(lay.gap_u + 0.2)
    lay.bx = lay.ix
    lay.BW = lay.iw
    lay.foot_h = 0
    lay.foot_y = lay.wy + lay.wh - lay.pad
    lay.BH = lay.foot_y - lay.by
    lay.btn_h = U.px(1.5)
    lay.gap = U.px(lay.gap_u)
    lay.f_btn = 0.5
    lay.f_text = 0.42
    lay.f_head = 0.48
    return lay
end

local function layout()
    local W, H = love.graphics.getDimensions()
    if C.PHONE then
        return phone_layout(W, H)
    end
    local portrait = H > W * 1.05
    local touch = U.touch_mode
    local lay = {W = W, H = H, portrait = portrait, touch = touch}
    lay.bw_u = portrait and 11.6 or 15
    lay.bh_u = portrait and 15 or 7
    lay.pad_u = 0.3
    lay.gap_u = 0.22
    lay.title_u = 0.8
    lay.tab_u = touch and 0.95 or 0.72
    lay.tab_rows = portrait and 2 or 1
    lay.foot_u = touch and 1.0 or 0.8
    local tabs_block = lay.tab_rows * lay.tab_u + (lay.tab_rows - 1) * 0.15
    local total_h = lay.pad_u + lay.title_u + 0.2 + tabs_block + lay.gap_u + 0.35 + lay.bh_u + lay.foot_u + lay.pad_u
    if not portrait then
        local uh = H * 0.92 / (total_h + 0.2)
        lay.bw_u = math.max(15, math.min(18.5, W * 0.9 / uh - 0.14 - 2 * lay.pad_u))
    end
    local total_w = lay.bw_u + 2 * lay.pad_u
    U.u = math.min(W * 0.9 / (total_w + 0.14), H * 0.92 / (total_h + 0.2))
    if portrait then
        local spare = H * 0.92 / U.u - 0.2 - total_h
        if spare > 0 then
            lay.bh_u = lay.bh_u + math.min(spare, 3)
            total_h = total_h + math.min(spare, 3)
        end
    end
    local u = U.u
    U.text_k = portrait and 1.18 or 1
    lay.u = u
    lay.ww, lay.wh = math.floor(total_w * u + 0.5), math.floor(total_h * u + 0.5)
    lay.wx = math.floor((W - lay.ww) / 2 + 0.5)
    lay.wy = math.floor((H - lay.wh) / 2 - 0.05 * u + 0.5)
    lay.pad = U.px(lay.pad_u)
    lay.ix, lay.iw = lay.wx + lay.pad, lay.ww - 2 * lay.pad
    lay.title_y = lay.wy + lay.pad + U.px(lay.title_u / 2)
    lay.tab_y = lay.wy + lay.pad + U.px(lay.title_u + 0.2)
    lay.tab_h = U.px(lay.tab_u)
    lay.by = lay.tab_y + U.px(tabs_block + lay.gap_u)
    lay.bx = lay.ix
    lay.BW = lay.iw
    lay.foot_h = U.px(lay.foot_u)
    lay.foot_y = lay.wy + lay.wh - lay.pad - lay.foot_h
    lay.BH = lay.foot_y - U.px(0.35) - lay.by
    lay.btn_h = U.px(touch and 1.0 or 0.78)
    lay.gap = U.px(lay.gap_u)
    lay.f_btn = touch and 0.5 or 0.45
    lay.f_text = touch and 0.4 or 0.36
    lay.f_head = touch and 0.46 or 0.42
    lay.cx = W / 2
    return lay
end

local function message_block(x, y, w, h, msg, hint, kind)
    if not msg then
        return
    end
    local color = kind == "error" and U.C.red or (kind == "ok" and U.C.green or U.C.white)
    local size = 0.4
    local hs = 0.34
    local function total()
        return U.paragraph_height(msg, size, w) + (hint and U.paragraph_height(hint, hs, w) + U.px(0.1) or 0)
    end
    while total() > h and size > 0.24 do
        size = size * 0.94
        hs = size * 0.85
    end
    if total() > h and hint then
        hint = nil
    end
    local th = total()
    local yy = y + math.max(0, math.floor((h - th) / 2))
    local used = U.paragraph(msg, x, yy, w, size, color)
    if hint then
        U.paragraph(hint, x, yy + used + U.px(0.1), w, hs, U.C.soft)
    end
end

local function current_message()
    local msg, hint, kind = S.msg, S.hint, S.msg_kind
    if not msg and not S.progress and not S.checking then
        if S.sel and S.sel.status == "error" then
            msg, hint = err_text(S.sel.err)
            kind = "error"
        elseif #S.games == 0 then
            msg, hint, kind = t("err_missing"), t("err_missing_hint"), "error"
        elseif feed_new() then
            msg, hint, kind = t(APP_MODE and "app_news" or "update_news", vname(S.feed.entry)), P.changelog(S.feed.entry, S.lang), "info"
        elseif S.feed.state == "launcher" then
            msg, hint, kind = t("need_launcher", vname(S.feed.entry)), S.feed.entry.page, "error"
        elseif APP_MODE then
            msg, kind = t(S.app and "app_ready_hint" or "app_intro"), "info"
        end
    end
    return msg, hint, kind
end

local function progress_label(p)
    if p.stage == "building" then
        return t("app_building", math.min(p.i or 0, p.n or 0), p.n or 0)
    elseif p.stage == "signing" then
        return t("app_signing")
    end
    return p.stage == "installing" and t("installing", p.i or 0, p.n or 0)
        or (p.stage == "checking" and t("checking"))
        or (p.stage == "downloading" and t("downloading"))
        or (p.stage == "finishing" and t("finishing"))
        or t("reading")
end

local function game_status_text(g)
    if not g then
        return S.checking and t("looking") or t("not_found"), U.C.soft
    end
    if g.status == "checking" or g.status == "quick" then
        return t("checking"), U.C.soft
    end
    if g.status == "ok" then
        return t("game_ok", vtext(g.version)), U.C.white
    end
    return short_err(g.err), U.C.red
end

local function overhaul_status_text()
    if APP_MODE then
        if S.app then
            return t("installed", S.app.name ~= "" and S.app.name or "?"), U.C.white
        end
        return t("app_none"), U.C.soft
    end
    local st, m = stamp_ok()
    local entry = feed_new()
    if entry then
        return st and t("update_out", vname(st), vname(entry)) or t("out_now", vname(entry)), U.C.gold
    elseif not st then
        return t("not_installed"), U.C.soft
    elseif st.overhaul_version == m.overhaul_version then
        return t("installed", vname(st)), U.C.white
    end
    return t("update_ready", vname(st), vname(m)), U.C.gold
end

local function primary_action()
    if APP_MODE then
        if not game_ready() then
            local label = #S.games > 0 and t("choose_game") or t("find_game")
            return "find", label, U.C.red, function()
                to_tab("game")
            end
        elseif S.wait_allow then
            return "allow", t("app_allow_btn"), U.C.orange, function()
                if not C.allow_install() then
                    set_msg(t("app_install_fail"), nil, "error")
                end
            end
        elseif S.app then
            return "open", t("app_open"), U.C.blue, do_open_app
        end
        return "make", t("app_make"), U.C.green, do_make_app
    end
    local st, m = stamp_ok()
    local current = st and st.overhaul_version == m.overhaul_version
    if feed_new() and game_ready() then
        return "update", t("update"), U.C.green, do_install
    elseif current then
        return "play", t("play"), U.C.blue, do_play
    elseif not game_ready() then
        local label = only_protected() and t("how_fix") or (#S.games > 0 and t("choose_game") or t("find_game"))
        return "find", label, U.C.red, function()
            to_tab("game")
        end
    elseif not st then
        return "install", t("install"), U.C.green, do_install
    end
    return "update", t("update"), U.C.green, do_install
end

local function draw_card(cx, cy, h)
    local tilt = 0
    if not U.touch_mode then
        local mx = love.mouse.getPosition()
        tilt = math.max(-1, math.min(1, (mx - cx) / (U.u * 6)))
    end
    local a = U.anim.card
    local j = a and (U.time - a.juice) or 9
    local spin = j < 0.6 and math.sin(j * 22) * math.exp(-j * 7) * 0.25 or 0
    local w = h * 71 / 95
    U.add_hit("card", cx - w / 2, cy - h / 2, w, h, function()
        U.juice("card")
        X.play("card1")
    end)
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(spin)
    love.graphics.translate(-cx, -cy)
    if X.jokers and X.joker_quad then
        U.card(X.jokers, X.joker_quad, cx, cy, h, U.time, tilt)
    else
        U.blank_card(cx, cy, h, U.time, U.C.red)
    end
    love.graphics.pop()
end

local function draw_play(lay)
    local bx, by, BW, BH = lay.bx, lay.by, lay.BW, lay.BH
    local rx, rw, ry
    local sh = U.px(lay.phone and 1.75 or (lay.touch and 1.35 or 1.25))
    local ph = U.px(lay.phone and 1.8 or (lay.touch and 1.5 or 1.35))
    local msg_h = U.px(lay.portrait and 2.6 or (lay.phone and 1.5 or 1.9))
    local stack = lay.phone and lay.portrait
    local cards_h = stack and (2 * sh + U.px(0.2)) or sh
    local block = cards_h + U.px(0.3) + ph + U.px(0.3) + lay.btn_h + U.px(0.25) + msg_h
    if lay.portrait then
        local ch = math.max(U.px(4.6), math.min(U.px(6.4), math.floor((BH - U.px(0.9) - block) * 0.9)))
        local top = by + math.max(U.px(0.15), math.floor((BH - ch - U.px(0.6) - block) / 2))
        draw_card(bx + BW / 2, top + ch / 2, ch)
        rx, rw, ry = bx, BW, top + ch + U.px(0.6)
    else
        local cw = U.px(4.3)
        draw_card(bx + cw / 2, by + BH / 2 - U.px(0.1), math.min(U.px(4.8), BH - U.px(1.2)))
        rx, rw, ry = bx + cw + U.px(0.4), BW - cw - U.px(0.4), by
        ry = ry + math.max(0, math.floor((BH - block) / 2))
    end
    local half = math.floor((rw - lay.gap) / 2)
    local gtext, gcol = game_status_text(S.sel)
    local otext, ocol = overhaul_status_text()
    if stack then
        U.status_card(rx, ry, rw, sh, t("your_game"), gtext, gcol)
        U.status_card(rx, ry + sh + U.px(0.2), rw, sh, t(APP_MODE and "app_label" or "overhaul"), otext, ocol)
    else
        U.status_card(rx, ry, half, sh, t("your_game"), gtext, gcol)
        U.status_card(rx + rw - half, ry, half, sh, t(APP_MODE and "app_label" or "overhaul"), otext, ocol)
    end
    local y = ry + cards_h + U.px(0.3)
    if S.progress or (S.checking and not S.sel) then
        local p = S.progress
        local frac = p and p.i and p.n and p.n > 0 and p.i / p.n or nil
        U.progress(rx, y, rw, ph, frac, p and progress_label(p) or t("looking"))
    else
        local id, label, col, fn = primary_action()
        U.button("main_" .. id, label, rx, y, rw, ph, col, 0.75, function()
            X.play("button")
            fn()
        end, {inactive = S.task ~= nil or S.checking, default = true})
    end
    y = y + ph + U.px(0.3)
    local st, m = stamp_ok()
    local pid = primary_action()
    local busy = S.task ~= nil
    local second
    if APP_MODE then
        if S.app then
            second = {"rebuild", t("app_rebuild"), U.C.green, function()
                love.filesystem.remove(C.APP_APK)
                do_make_app()
            end, busy or not game_ready()}
        end
    elseif pid ~= "play" and st then
        second = {"play2", t("play"), U.C.blue, do_play, busy}
    elseif pid == "play" then
        local ilabel = (st.overhaul_version ~= m.overhaul_version or feed_new()) and t("update") or t("reinstall")
        second = {"install", ilabel, U.C.green, do_install, not game_ready() or busy}
    end
    if second then
        U.button(second[1], second[2], rx, y, C.open_folder and half or rw, lay.btn_h, second[3], lay.f_btn, function()
            X.play("button")
            second[4]()
        end, {inactive = second[5]})
    end
    local fx, fw = rx + rw - half, half
    if not second then
        fx, fw = rx, rw
    end
    if C.open_folder then
        U.button("folder", t("open_folder"), fx, y, fw, lay.btn_h, U.C.grey, lay.f_btn, function()
            X.play("button")
            C.open_folder()
        end)
    end
    y = y + lay.btn_h + U.px(0.25)
    local msg, hint, kind = current_message()
    message_block(rx, y, rw, math.max(msg_h, by + BH - y), msg, hint, kind)
end

local function badge_for(g)
    if g.where == "steam" then
        return t("badge_steam"), U.C.blue
    elseif g.where == "xbox" then
        return t("badge_xbox"), U.C.green
    elseif g.where == "play" then
        return t("badge_play"), U.C.green
    elseif g.where == "bundled" then
        return t("badge_bundled"), U.C.green
    end
    return t("badge_picked"), U.C.orange
end

local function use_copy(g)
    if not S.task and S.sel ~= g then
        X.play("button")
        C.settings().game_path = g.path
        C.save_settings()
        S.sel = g
        set_msg(nil)
        run_task(function()
            full_check(g)
        end)
    end
end

local function draw_ways(x, y, w, h, lay)
    local ways = {{t("way_steam"), t("way_steam_steps")}, {t("way_xbox"), t("way_xbox_steps")}}
    local gap = lay.gap
    local bw = lay.portrait and w or math.floor((w - gap) / 2)
    local pad = U.px(0.3)
    local hs = lay.f_head
    local tw = bw - 2 * pad
    local function steps(text, size)
        local out = {}
        for line in text:gmatch("[^\n]+") do
            local num, rest = line:match("^(%d+%.%s+)(.*)$")
            num, rest = num and num:gsub("%s+$", "") or "", rest or line
            local indent = num ~= "" and U.text_width("0.", size) + U.px(0.15) or 0
            out[#out + 1] = {num = num, indent = indent, lines = U.wrap(rest, size, tw - indent)}
        end
        return out
    end
    local function height(list, size)
        local n = 0
        for _, st in ipairs(list) do
            n = n + #st.lines
        end
        return n * U.line_h(size) + (#list - 1) * U.px(0.1)
    end
    local head_h = U.line_h(hs) + U.px(0.15)
    local size, blocks, needs, total = lay.f_text, nil, nil, 0
    repeat
        blocks = {steps(ways[1][2], size), steps(ways[2][2], size)}
        needs = {height(blocks[1], size) + head_h + 2 * pad, height(blocks[2], size) + head_h + 2 * pad}
        if lay.portrait then
            total = needs[1] + needs[2] + gap
        else
            needs[1] = math.max(needs[1], needs[2])
            needs[2] = needs[1]
            total = needs[1]
        end
        if total > h then
            size = size * 0.94
        end
    until total <= h or size < 0.22
    local lh = U.line_h(size)
    local wy = y + math.max(0, math.floor((h - total) / 2))
    for i, way in ipairs(ways) do
        local wx = lay.portrait and x or x + (i - 1) * (bw + gap)
        U.box(wx, wy, bw, needs[i], U.C.black)
        local yy = wy + pad
        if lay.portrait then
            wy = wy + needs[i] + gap
        end
        U.print_center(U.fit(way[1], hs, tw), wx + bw / 2, yy + U.line_h(hs) / 2, hs, U.C.gold)
        yy = yy + head_h
        for _, st in ipairs(blocks[i]) do
            U.print_left(st.num, wx + pad, yy + lh / 2, size, U.C.gold)
            for _, l in ipairs(st.lines) do
                U.print_left(l, wx + pad + st.indent, yy + lh / 2, size, U.C.white)
                yy = yy + lh
            end
            yy = yy + U.px(0.1)
        end
    end
end

local function draw_game(lay)
    local bx, by, BW, BH = lay.bx, lay.by, lay.BW, lay.BH
    U.print_center(t("copies"), bx + BW / 2, by + U.px(0.25), lay.f_head, U.C.gold)
    local bar_y = by + BH - lay.btn_h
    local half = math.floor((BW - lay.gap) / 2)
    local msg, hint, kind = S.msg, S.hint, S.msg_kind
    if not msg and #S.games > 0 then
        msg, hint, kind = t("drop_hint"), nil, "hint"
    end
    local msg_h = U.px(lay.portrait and 2.2 or (lay.phone and 1.6 or 1.15))
    local top = by + U.px(0.7)
    local rh = U.px(lay.phone and 1.8 or (lay.touch and 1.3 or 1.1))
    local rgap = U.px(0.2)
    local list_h = bar_y - msg_h - U.px(0.2) - top
    local per = math.max(1, math.floor((list_h + rgap) / (rh + rgap)))
    local pages = math.max(1, math.ceil(#S.games / per))
    if pages > 1 then
        per = math.max(1, math.floor((list_h - lay.btn_h - U.px(0.1) + rgap) / (rh + rgap)))
        pages = math.max(1, math.ceil(#S.games / per))
    end
    S.page = math.max(1, math.min(S.page, pages))
    local y = top
    if #S.games == 0 then
        if S.checking then
            U.progress(bx, y, BW, rh, nil, t("looking"))
        else
            U.box(bx, y, BW, rh, U.C.black)
            U.print_center(U.fit(t("err_missing"), 0.42, BW - U.px(0.4)), bx + BW / 2, y + rh / 2, 0.42, U.C.red)
            msg, hint, kind = t("err_missing_hint"), t("drop_hint"), "hint"
        end
    end
    local use_w = U.px(lay.phone and 3.2 or (lay.portrait and 2.5 or 2.85))
    local locked = only_protected()
    if locked and not S.msg then
        msg, hint, kind = t("err_protected"), nil, "error"
    end
    for i = (S.page - 1) * per + 1, math.min(#S.games, S.page * per) do
        local g = S.games[i]
        local inuse = S.sel == g and not g.protected
        U.box(bx, y, BW, rh, g.protected and U.darken(U.C.black, 0.25) or U.C.black)
        if inuse then
            love.graphics.setLineWidth(math.max(2, U.px(0.05)))
            love.graphics.setColor(U.C.gold)
            U.rrect("line", bx, y, BW, rh, U.px(0.12))
        end
        local btext, bcol = badge_for(g)
        local bw = U.badge(btext, bx + U.px(0.25), y + rh / 2, lay.phone and 0.36 or 0.3, g.protected and U.C.grey or bcol)
        local tx = bx + U.px(0.25) + bw + U.px(0.25)
        local tw = BW - (tx - bx) - use_w - U.px(0.45)
        local ts = lay.phone and 0.44 or (lay.touch and 0.36 or 0.32)
        local shown = (g.where == "play" or g.where == "bundled") and t("game_" .. g.where) or (g.path:match("^%a:[/\\]") and g.path:gsub("/", "\\") or g.path)
        local ss = lay.phone and U.fit_scale(shown, ts, tw, ts * 0.75) or ts
        U.print_left(U.fit(shown, ss, tw), tx, y + rh * 0.33, ss, g.protected and U.C.inactive_text or U.C.white)
        local st, sc = game_status_text(g)
        if g.protected and g.status == "error" then
            st, sc = t("bad_protected_row"), U.C.inactive_text
        end
        local sts = lay.phone and U.fit_scale(st, ts, tw, ts * 0.75) or ts
        U.print_left(U.fit(st, sts, tw), tx, y + rh * 0.69, sts, sc == U.C.white and U.C.soft or sc)
        local bh = rh - U.px(0.3)
        local ucol = inuse and (g.status == "error" and U.C.red or U.C.green) or U.C.blue
        U.button("use" .. i, inuse and t("in_use") or t("use_this"), bx + BW - use_w - U.px(0.15), y + U.px(0.15) - U.px(0.03), use_w, bh, ucol, lay.f_btn * 0.9,
            function()
                use_copy(g)
            end, {inactive = (g.status == "error" and not inuse) or S.task ~= nil})
        y = y + rh + rgap
    end
    if locked then
        local list_bottom = bar_y - msg_h - U.px(0.2)
        draw_ways(bx, y, BW, list_bottom - y, lay)
    end
    if pages > 1 then
        local py = bar_y - msg_h - U.px(0.2) - lay.btn_h
        local aw = U.px(0.9)
        local pw = U.px(4)
        local px = bx + (BW - pw) / 2
        U.button("page_prev", "<", px, py, aw, lay.btn_h, U.C.red, 0.5, function()
            S.page = S.page > 1 and S.page - 1 or pages
        end)
        U.button("page_next", ">", px + pw - aw, py, aw, lay.btn_h, U.C.red, 0.5, function()
            S.page = S.page < pages and S.page + 1 or 1
        end)
        U.print_center(t("page", S.page, pages), px + pw / 2, py + lay.btn_h / 2, 0.42, U.C.white)
    end
    local mw = math.min(BW, U.px(12.5))
    message_block(bx + (BW - mw) / 2, bar_y - msg_h - U.px(0.1), mw, msg_h, msg, hint, kind == "hint" and "info" or kind)
    U.button("scan", t("scan"), bx, bar_y, C.PHONE and BW or half, lay.btn_h, U.C.blue, lay.f_btn, function()
        if not S.task then
            X.play("button")
            set_msg(nil)
            S.page = 1
            check_games()
        end
    end, {inactive = S.task ~= nil})
    if C.PHONE then
        return
    end
    U.button("paste", t("paste"), bx + BW - half, bar_y, half, lay.btn_h, U.C.orange, lay.f_btn, function()
        X.play("button")
        local clip = love.system.getClipboardText()
        if not clip or clip:match("^%s*$") then
            set_msg(t("err_paste"), t("drop_hint"), "error")
        else
            pick(clip)
        end
    end, {inactive = S.task ~= nil})
end

local function save_badge(src)
    if src.where == "local" then
        return t("badge_local"), U.C.green
    elseif src.where == "file" then
        return t("badge_file"), U.C.orange
    elseif src.where == "overhaul" then
        return t("badge_overhaul"), U.C.red
    end
    return t("badge_steam"), U.C.blue
end

local function draw_saves(lay)
    local bx, by, BW, BH = lay.bx, lay.by, lay.BW, lay.BH
    U.print_center(t("saves_head"), bx + BW / 2, by + U.px(0.25), lay.f_head, U.C.gold)
    local stacked = lay.portrait
    local nbtn = C.PHONE and 2 or 3
    local bar_y = by + BH - lay.btn_h - (stacked and (nbtn - 1) * (lay.btn_h + lay.gap) or 0)
    local msg, hint, kind = S.msg, S.hint, S.msg_kind
    if not msg then
        local c = C.settings().save_choice
        if c then
            msg, kind = t("choice_now", t(c == "new" and "choice_fresh" or (c == "file" and "choice_file" or "choice_balatro"))), "info"
        else
            msg, kind = t((APP_MODE and S.app) and "app_saves_note" or "saves_hint"), "info"
        end
    end
    local rows = {}
    for _, src in ipairs(S.saves or {}) do
        rows[#rows + 1] = src
    end
    if S.picked_save then
        rows[#rows + 1] = S.picked_save
    end
    rows[#rows + 1] = {where = "overhaul", path = C.game_save_dir(), info = S.osave or {}}
    local msg_h = U.px(lay.portrait and 2.2 or (lay.phone and 1.6 or 1.15))
    local top = by + U.px(0.7)
    local rh = U.px(lay.phone and 1.8 or (lay.touch and 1.3 or 1.1))
    local rgap = U.px(0.2)
    local list_h = bar_y - msg_h - U.px(0.2) - top
    local per = math.max(1, math.floor((list_h + rgap) / (rh + rgap)))
    local pages = math.max(1, math.ceil(#rows / per))
    if pages > 1 then
        per = math.max(1, math.floor((list_h - lay.btn_h - U.px(0.1) + rgap) / (rh + rgap)))
        pages = math.max(1, math.ceil(#rows / per))
    end
    S.page = math.max(1, math.min(S.page, pages))
    local y = top
    local use_w = U.px(lay.phone and 3.2 or (lay.portrait and 2.5 or 2.85))
    local busy = S.task ~= nil
    for i = (S.page - 1) * per + 1, math.min(#rows, S.page * per) do
        local src = rows[i]
        U.box(bx, y, BW, rh, U.C.black)
        local btext, bcol = save_badge(src)
        local bw = U.badge(btext, bx + U.px(0.25), y + rh / 2, lay.phone and 0.36 or 0.3, bcol)
        local tx = bx + U.px(0.25) + bw + U.px(0.25)
        local has_btn = src.where ~= "overhaul"
        local tw = BW - (tx - bx) - (has_btn and use_w + U.px(0.45) or U.px(0.25))
        local ts = lay.phone and 0.44 or (lay.touch and 0.36 or 0.32)
        U.print_left(U.fit(src.path, ts, tw), tx, y + rh * 0.33, ts, U.C.white)
        U.print_left(U.fit(info_text(src.info, ts, tw), ts, tw), tx, y + rh * 0.69, ts, U.C.soft)
        if has_btn then
            local bh = rh - U.px(0.3)
            U.button("load" .. i, t("load"), bx + BW - use_w - U.px(0.15), y + U.px(0.15) - U.px(0.03), use_w, bh,
                S.confirm == src and U.C.orange or U.C.green, lay.f_btn * 0.9, function()
                    X.play("button")
                    load_save(src, src.where == "file" and "file" or "balatro")
                end, {inactive = busy})
        end
        y = y + rh + rgap
    end
    if pages > 1 then
        local py = bar_y - msg_h - U.px(0.2) - lay.btn_h
        local aw = U.px(0.9)
        local pw = U.px(4)
        local px = bx + (BW - pw) / 2
        U.button("spage_prev", "<", px, py, aw, lay.btn_h, U.C.red, 0.5, function()
            S.page = S.page > 1 and S.page - 1 or pages
        end)
        U.button("spage_next", ">", px + pw - aw, py, aw, lay.btn_h, U.C.red, 0.5, function()
            S.page = S.page < pages and S.page + 1 or 1
        end)
        U.print_center(t("page", S.page, pages), px + pw / 2, py + lay.btn_h / 2, 0.42, U.C.white)
    end
    local mw = math.min(BW, U.px(12.5))
    message_block(bx + (BW - mw) / 2, bar_y - msg_h - U.px(0.1), mw, msg_h, msg, hint, kind == "hint" and "info" or kind)
    local third = math.floor((BW - (nbtn - 1) * lay.gap) / nbtn)
    local xs = {bx, nbtn == 2 and bx + BW - third or bx + third + lay.gap, bx + BW - third}
    local ys = {bar_y, bar_y, bar_y}
    if stacked then
        third = BW
        xs = {bx, bx, bx}
        ys = {bar_y, bar_y + lay.btn_h + lay.gap, bar_y + 2 * (lay.btn_h + lay.gap)}
    end
    U.button("import", t("import_file"), xs[1], ys[1], third, lay.btn_h, U.C.blue, lay.f_btn, function()
        X.play("button")
        local clip = love.system.getClipboardText()
        if not clip or clip:match("^%s*$") then
            set_msg(t("err_paste"), t("saves_hint"), "error")
        else
            import_path(clip)
        end
    end, {inactive = busy})
    U.button("export", t("export_save"), xs[2], ys[2], third, lay.btn_h, U.C.green, lay.f_btn, function()
        X.play("button")
        do_export()
    end, {inactive = busy})
    if nbtn == 3 then
        U.button("backups", t("backups"), xs[3], ys[3], third, lay.btn_h, U.C.grey, lay.f_btn, function()
            X.play("button")
            V.open_folder(V.BACKUPS)
        end)
    end
end

local function draw_ask(lay)
    local src = S.ask
    U.hits = {}
    love.graphics.setColor(0, 0, 0, 0.55)
    love.graphics.rectangle("fill", 0, 0, lay.W, lay.H)
    local w = math.min(lay.ww - U.px(0.6), U.px(lay.portrait and 10.6 or 12))
    local cw = w - 2 * lay.pad
    local lines = prof_lines(src.info)
    local fs = lay.f_text
    local text_h = U.paragraph_height(t("ask_text"), fs * 1.1, cw)
    local list_h = #lines * U.px(fs * 1.25)
    local note_h = U.paragraph_height(t("ask_backup"), fs * 0.92, cw)
    local bh = U.px(lay.touch and 1.15 or 1.0)
    local stacked = lay.portrait
    local btn_block = stacked and (2 * bh + lay.gap) or bh
    local h = lay.pad + U.px(0.8) + text_h + U.px(0.3) + list_h + U.px(0.3) + note_h + U.px(0.4) + btn_block + lay.gap + lay.btn_h + lay.pad
    local x = math.floor((lay.W - w) / 2 + 0.5)
    local y = math.floor((lay.H - h) / 2 + 0.5)
    U.window(x, y, w, h)
    local cx = x + lay.pad
    local yy = y + lay.pad
    U.print_center(t("ask_title"), lay.W / 2, yy + U.px(0.3), 0.55, U.C.gold)
    yy = yy + U.px(0.8)
    yy = yy + U.paragraph(t("ask_text"), cx, yy, cw, fs * 1.1, U.C.white) + U.px(0.3)
    for _, line in ipairs(lines) do
        U.print_center(U.fit(line, fs, cw), lay.W / 2, yy + U.px(fs * 1.25) / 2, fs, U.C.gold)
        yy = yy + U.px(fs * 1.25)
    end
    yy = yy + U.px(0.3)
    yy = yy + U.paragraph(t("ask_backup"), cx, yy, cw, fs * 0.92, U.C.soft) + U.px(0.4)
    local function do_load()
        X.play("button")
        S.ask = nil
        S.tab = "play"
        load_save(src, "balatro", true)
    end
    local function do_new()
        X.play("button")
        choose_new()
    end
    if stacked then
        U.button("ask_load", t("ask_load"), cx, yy, cw, bh, U.C.green, lay.f_btn, do_load, {default = true})
        yy = yy + bh + lay.gap
        U.button("ask_new", t("ask_new"), cx, yy, cw, bh, U.C.blue, lay.f_btn, do_new)
        yy = yy + bh + lay.gap
    else
        local half = math.floor((cw - lay.gap) / 2)
        U.button("ask_load", t("ask_load"), cx, yy, half, bh, U.C.green, lay.f_btn, do_load, {default = true})
        U.button("ask_new", t("ask_new"), cx + cw - half, yy, half, bh, U.C.blue, lay.f_btn, do_new)
        yy = yy + bh + lay.gap
    end
    U.button("ask_other", t("ask_other"), cx, yy, cw, lay.btn_h, U.C.grey, lay.f_btn * 0.9, function()
        X.play("button")
        S.ask = nil
        to_tab("saves")
    end)
end

local function draw_android(lay)
    local bx, by, BW, BH = lay.bx, lay.by, lay.BW, lay.BH
    local cw = math.min(BW, U.px(lay.portrait and 11 or 10))
    local cx = bx + (BW - cw) / 2
    local ph = U.px(lay.touch and 1.3 or 1.15)
    local fs = lay.f_text * 1.1
    local text_h = U.paragraph_height(t("android_text"), fs, cw - U.px(0.6))
    local msg_h = U.px(1.6)
    local block = U.px(0.9) + text_h + U.px(0.5) + U.px(0.5) + ph + U.px(0.3) + msg_h
    local y = by + math.max(U.px(0.3), math.floor((BH - block) / 2))
    U.print_center(t("android_head"), bx + BW / 2, y + U.px(0.3), 0.55, U.C.gold)
    y = y + U.px(0.9)
    U.box(cx, y, cw, text_h + U.px(0.5), U.C.black)
    U.paragraph(t("android_text"), cx + U.px(0.3), y + U.px(0.25), cw - U.px(0.6), fs, U.C.white)
    y = y + text_h + U.px(0.5) + U.px(0.5)
    local bw = math.min(cw, U.px(6))
    if S.progress then
        local p = S.progress
        local frac = p.i and p.n and p.n > 0 and p.i / p.n or nil
        U.progress(cx, y, cw, ph, frac, progress_label(p))
    else
        U.button("apk", t("apk_make"), bx + (BW - bw) / 2, y, bw, ph, U.C.green, 0.55, function()
            X.play("button")
            do_apk()
        end, {inactive = S.task ~= nil or not C.apk_tool()})
    end
    y = y + ph + U.px(0.3)
    local msg, hint, kind = S.msg, S.hint, S.msg_kind
    if not msg and not C.apk_tool() then
        msg, kind = t("apk_missing"), "info"
    elseif not msg then
        msg, kind = t("apk_where", love.filesystem.getSaveDirectory()), "info"
    end
    message_block(cx, y, cw, msg_h, msg, hint, kind)
end

local function draw_settings(lay)
    local bx, by, BW, BH = lay.bx, lay.by, lay.BW, lay.BH
    local cw = math.min(BW, U.px(lay.phone and 9.5 or (lay.portrait and 9 or 6.5)))
    local cx = bx + (BW - cw) / 2
    local ch = U.px(lay.phone and 2.4 or (lay.touch and 1.8 or 1.55))
    local th = U.px(lay.phone and 1.5 or (lay.touch and 0.95 or 0.8))
    local g1, g2, g3, mh = U.px(0.35), U.px(0.2), U.px(0.45), U.px(1.4)
    if lay.phone and not lay.portrait then
        g1, g2, g3, mh = U.px(0.2), U.px(0.05), U.px(0.2), U.px(1.1)
    end
    local block = ch + g1 + 2 * th + g2 + g3 + mh
    local y = by + math.max(U.px(0.25), math.floor((BH - block) / 2))
    local idx = 1
    for i, code in ipairs(L.order) do
        if code == S.lang then
            idx = i
        end
    end
    local function set_lang(d)
        X.play("button")
        S.lang = L.order[(idx - 1 + d) % #L.order + 1]
        C.settings().lang = S.lang
        C.save_settings()
    end
    U.cycle("lang", t("language"), cx, y, cw, ch, L.names[S.lang], idx, #L.order, function()
        set_lang(-1)
    end, function()
        set_lang(1)
    end)
    y = y + ch + g1
    local set = C.settings()
    U.toggle("snd", t("set_sounds"), cx, y, cw, th, set.sounds ~= false, function()
        set.sounds = set.sounds == false
        C.save_settings()
        X.mute = set.sounds == false or os.getenv("LAUNCHER_MUTE") == "1"
        U.juice("snd")
        X.play("button")
    end)
    y = y + th + g2
    U.toggle("crt", t("set_crt"), cx, y, cw, th, set.crt ~= false, function()
        set.crt = set.crt == false
        C.save_settings()
        X.crt_on = set.crt ~= false
        U.juice("crt")
        X.play("button")
    end)
    y = y + th + g3
    message_block(cx, y, cw, mh, t("set_hint"), nil, "hint")
end

local function draw_about(lay)
    local m = C.manifest() or {}
    local bx, by, BW, BH = lay.bx, lay.by, lay.BW, lay.BH
    local cw = math.min(BW, U.px(lay.phone and (lay.portrait and 12 or 18) or (lay.portrait and 11 or 13)))
    local cx = bx + (BW - cw) / 2
    local paras = {
        {t("about_1", vname(m), vtext(m.game_version)), U.C.gold},
        {t(APP_MODE and "app_about_2" or "about_2"), U.C.white},
        {t("about_3"), U.C.soft},
        {t("about_4", C.game_save_dir()), U.C.soft},
        {t("lic_head"), U.C.gold, true},
        {t("lic_love"), U.C.soft},
        {t("lic_game"), U.C.soft},
    }
    if APP_MODE then
        table.remove(paras, 4)
    end
    local size = lay.f_text
    local pg = U.px(0.18)
    local function total()
        local h = 0
        for _, p in ipairs(paras) do
            h = h + U.paragraph_height(p[1], p[3] and size * 1.15 or size, cw) + pg
        end
        return h - pg
    end
    while total() > BH - U.px(0.2) and size > 0.22 do
        size = size * 0.95
    end
    local y = by + math.max(U.px(0.1), math.floor((BH - total()) / 2))
    for _, p in ipairs(paras) do
        y = y + U.paragraph(p[1], cx, y, cw, p[3] and size * 1.15 or size, p[2]) + pg
    end
end

local TABS = {
    play = {"tab_play", draw_play},
    game = {"tab_game", draw_game},
    saves = {"tab_saves", draw_saves},
    android = {"tab_android", draw_android},
    settings = {"tab_settings", draw_settings},
    about = {"tab_about", draw_about},
}

local function tab_step(d)
    local idx = 1
    for i, k in ipairs(TAB_KEYS) do
        if k == S.tab then
            idx = i
        end
    end
    X.play("paper1")
    to_tab(TAB_KEYS[(idx - 1 + d) % #TAB_KEYS + 1])
end

local function draw_tabs(lay)
    local n = #TAB_KEYS
    local per_row = lay.tab_rows == 1 and n or math.ceil(n / lay.tab_rows)
    local tgap = U.px(0.18)
    local tw = math.min(U.px(lay.touch and 2.8 or 2.6), math.floor((lay.iw - (per_row - 1) * tgap) / per_row))
    local fs = lay.touch and 0.46 or 0.4
    if lay.phone then
        tw = math.floor((lay.iw - (per_row - 1) * tgap) / per_row)
        fs = 0.5
        for _, key in ipairs(TAB_KEYS) do
            fs = math.min(fs, U.fit_scale(t(TABS[key][1]), 0.5, tw - U.px(0.3), 0.3))
        end
    end
    for i, key in ipairs(TAB_KEYS) do
        local row = math.floor((i - 1) / per_row)
        local col = (i - 1) % per_row
        local in_row = math.min(per_row, n - row * per_row)
        local x0 = math.floor(lay.cx - (in_row * tw + (in_row - 1) * tgap) / 2)
        local x = x0 + col * (tw + tgap)
        local y = lay.tab_y + row * (lay.tab_h + U.px(0.15))
        if S.tab == key then
            U.pointer(x + tw / 2, y - U.px(0.24), U.px(0.15), U.C.red)
        end
        U.button("tab_" .. key, t(TABS[key][1]), x, y, tw, lay.tab_h, U.C.red, fs, function()
            if S.tab ~= key then
                X.play("paper1")
            end
            to_tab(key)
        end)
    end
end

local function draw_scene()
    local lay = layout()
    U.begin_frame()
    X.background(lay.W, lay.H)
    love.graphics.setColor(U.C.grey[1], U.C.grey[2], U.C.grey[3], 0.3)
    love.graphics.rectangle("fill", 0, 0, lay.W, lay.H)
    U.window(lay.wx, lay.wy, lay.ww, lay.wh)
    U.print_center(t("title"), lay.cx, lay.title_y, 0.6, U.C.gold)
    draw_tabs(lay)
    local k = math.min(1, (U.time - (S.tab_time or 0)) / 0.18)
    local e = 1 - (1 - k) * (1 - k)
    love.graphics.push()
    love.graphics.translate(0, math.floor((1 - e) * U.px(0.25)))
    TABS[S.tab][2](lay)
    love.graphics.pop()
    if not lay.phone then
        U.button("quit", t("quit"), lay.ix, lay.foot_y, lay.iw, lay.foot_h, U.C.orange, lay.f_btn, function()
            X.play("cancel")
            love.event.quit()
        end)
    end
    if S.ask then
        draw_ask(lay)
    end
end
local shots

local function has_arg(name)
    for _, a in ipairs(arg or {}) do
        if a == name then
            return true
        end
    end
    return false
end

local function cli()
    local mode, game = nil, nil
    for i, a in ipairs(arg) do
        if a == "--cli" then
            mode = arg[i + 1]
        elseif a == "--balatro" then
            game = arg[i + 1]
        end
    end
    local function out(s)
        io.stdout:write(s .. "\n")
        io.stdout:flush()
    end
    local m = C.manifest()
    if not m then
        out("FAIL no patch set in this launcher")
        return 2
    end
    out(string.format("launcher: Overhaul %s for Balatro %s", tostring(m.overhaul_version), tostring(m.game_version)))
    local entry
    if mode == "update" then
        local st = C.stamp()
        local e, ferr
        if P.enabled() then
            e, ferr = P.result(require("net").fetch(P.url()))
        else
            ferr = "off"
        end
        local status = P.status(e)
        out("feed " .. status .. " " .. (e and e.version or tostring(ferr)))
        if status == "launcher" then
            out("FAIL " .. t("need_launcher", e.version))
            return 8
        elseif status == "new" then
            entry = e
        elseif st and st.overhaul_version == m.overhaul_version and love.filesystem.getInfo(C.GAME_FOLDER .. "/main.lua") then
            out("OK " .. (status == "latest" and t("up_to_date", tostring(m.overhaul_version)) or t("feed_offline")))
            return 0
        end
    end
    local path = game and C.resolve_pick(game)
    if game and not path then
        out("FAIL " .. t("err_read", game))
        return 3
    end
    if not path then
        local list = C.scan()
        for _, g in ipairs(list) do
            out("found " .. g.where .. (g.protected and " protected " or " ") .. g.path)
        end
        for _, g in ipairs(list) do
            if not g.protected then
                path = g.path
                break
            end
        end
        if not path and list[1] then
            out("FAIL " .. t("err_protected"))
            return 4
        end
    end
    if not path then
        out("FAIL " .. t("err_missing"))
        return 4
    end
    out("game " .. path)
    local co = coroutine.create(function()
        if entry then
            out("update " .. entry.version .. " " .. entry.url)
            return P.update(entry, path, function() coroutine.yield() end)
        end
        if mode == "install" or mode == "update" then
            return C.install(path, function() coroutine.yield() end)
        end
        if mode == "apk" then
            local tool = C.apk_tool()
            if not tool then
                return nil, {code = "apk_missing"}
            end
            local file, aerr = tool.run({game_path = path, out_dir = os.getenv("LAUNCHER_APK_DIR") or love.filesystem.getSaveDirectory(),
                icon = C.apk_icon and C.apk_icon(path) or nil, progress = function() coroutine.yield() end})
            if not file then
                return nil, {code = "apk", detail = aerr}
            end
            return {apk = file}
        end
        return C.full_check(path, function() coroutine.yield() end)
    end)
    local ok, res, err
    repeat
        ok, res, err = coroutine.resume(co)
    until coroutine.status(co) == "dead"
    if not ok then
        out("FAIL crash " .. tostring(res))
        return 5
    end
    if not res then
        if err and err.code == "apk" then
            out("FAIL apk " .. tostring(err.detail))
            return 6
        end
        local a, b = err_text(err)
        out("FAIL " .. a .. (b and (" | " .. b) or ""))
        return 6
    end
    if mode == "apk" then
        out("OK apk " .. tostring(res.apk))
    elseif mode == "install" or mode == "update" then
        out("OK installed " .. tostring((C.manifest() or {}).overhaul_version) .. ", " .. tostring(res.files) .. " files into " .. C.game_dir())
        out("play: " .. C.play_command())
        if has_arg("--play") then
            local pok, cmd = C.play(path)
            out((pok and "started " or "FAIL start ") .. cmd)
        end
    else
        out("OK Balatro " .. tostring(res.version) .. " checked")
    end
    return 0
end


function love.load(args)
    S.lang = C.settings().lang or L.detect(os.getenv)
    P.restore()
    C.write_link(P.url())
    if LAUNCHER_PLAY then
        if C.manifest() then C.play() end
        love.event.quit(0)
        return
    end
    if LAUNCHER_CLI then
        local code = cli()
        love.event.quit(code)
        return
    end
    U = require("ui")
    X = require("gfx")
    pcall(function()
        local AI = require("app_icon")
        local gd = C.game_dir()
        local canvas = AI.compose("launcher", love.filesystem.getInfo(C.GAME_FOLDER .. "/main.lua") and AI.read_from(gd) or nil)
        love.window.setIcon(canvas:newImageData())
    end)
    local mobile = love.system.getOS() == "Android" or love.system.getOS() == "iOS"
    local touch_screen = not mobile and C.touchscreen()
    U.touch_mode = mobile or touch_screen
    U.phone = C.PHONE == true
    local size = os.getenv("LAUNCHER_SIZE")
    if size then
        local w, h = size:match("^(%d+)x(%d+)$")
        if w then
            love.window.setMode(tonumber(w), tonumber(h), {resizable = true, minwidth = 400, minheight = 400})
        end
    elseif touch_screen then
        love.window.maximize()
    end
    X.init()
    X.crt_on = C.settings().crt ~= false
    X.mute = C.settings().sounds == false or os.getenv("LAUNCHER_MUTE") == "1"
    love.keyboard.setKeyRepeat(true)
    local dir = os.getenv("LAUNCHER_SHOT_DIR")
    if dir and dir ~= "" then
        shots = {dir = dir, list = {}, wait = 0}
        for name in (os.getenv("LAUNCHER_SHOTS") or "play,game,android,settings,about"):gmatch("[^,]+") do
            shots.list[#shots.list + 1] = name
        end
        X.mute = true
        S.shot_mode = true
    end
    if os.getenv("LAUNCHER_LANG") then
        S.lang = os.getenv("LAUNCHER_LANG")
    end
    if has_arg("--update") then
        S.handoff = {play = has_arg("--play")}
    end
    local phone = rawget(_G, "OVERHAUL_PHONE")
    if type(phone) == "table" and phone.handoff then
        S.handoff = {play = true}
    end
    if P.enabled() then
        S.feed = {state = "checking", job = P.start and P.start() or require("net").start(P.url())}
    end
    local fake = os.getenv("LAUNCHER_FAKE_FEED")
    if shots and fake and fake ~= "" then
        S.feed = {state = "new", entry = {version = fake, url = "http://127.0.0.1:9/none.zip", size = 1, sha256 = "0",
            changelog = {en = "New jokers and fixes.", fr = "Nouveaux jokers et corrections.", es = "Nuevos jokers y arreglos."}}}
    end
    check_games()
    refresh_app()
    if APP_MODE and love.filesystem.getInfo(APP_PENDING) then
        if S.app or not love.filesystem.getInfo(C.APP_APK) then
            love.filesystem.remove(APP_PENDING)
        else
            start_app_install()
        end
    end
end

function love.focus(f)
    if f then
        app_focus()
    end
end

local function handoff_step()
    local st, m = stamp_state()
    if feed_new() or not st or (m and st.overhaul_version ~= m.overhaul_version) then
        S.tab = "play"
        do_install()
        if not S.task then
            S.handoff = nil
        end
        return
    end
    S.handoff = nil
    if S.feed.state == "latest" then
        set_msg(t("up_to_date", vname(m or {})), nil, "ok")
    else
        set_msg(t("feed_offline"), nil, "info")
    end
end

local function feed_update()
    if S.feed.job then
        local r = require("net").poll(S.feed.job)
        if r then
            local e, err = P.result(r)
            S.feed = {state = P.status(e), entry = e, err = err}
            if err then
                print("launcher: update feed: " .. tostring(err))
            end
        end
    end
    if S.handoff and not S.task and not S.checking and (S.feed.state ~= "checking" or C.PHONE) then
        handoff_step()
    end
    if S.play_after and not S.task then
        S.play_after = nil
        do_play()
        if S.msg_kind == "ok" then
            S.quit_at = love.timer.getTime() + 1.5
        end
    end
    if S.quit_at and love.timer.getTime() > S.quit_at then
        S.quit_at = nil
        love.event.quit(0)
    end
end


local function shot_update()
    shots.wait = shots.wait + 1
    if shots.pending then
        if shots.after and shots.wait >= 4 then
            shots.after()
            shots.after = nil
        end
        if shots.wait >= 12 and (shots.force or not S.task) then
            local name = shots.pending
            shots.pending, shots.force, shots.wait = nil, nil, 0
            love.graphics.captureScreenshot(function(img)
                local f = io.open(shots.dir .. "/" .. name:gsub("[^%w_]", "_") .. ".png", "wb")
                if f then
                    f:write(img:encode("png"):getString())
                    f:close()
                end
            end)
        end
        return
    end
    if S.task or S.checking or shots.wait < 8 or S.feed.state == "checking" then
        return
    end
    local name = table.remove(shots.list, 1)
    if not name then
        love.event.quit(0)
        return
    end
    local tab, extra = name:match("^(%a+)%+?(.*)$")
    to_tab(tab)
    S.tab_time = -1
    U.pointer_hidden = true
    S.ask = nil
    if extra == "install" then
        do_install()
    elseif extra == "progress" then
        do_install()
        shots.force = true
    elseif extra == "play" then
        do_play()
    elseif extra == "apk" then
        do_apk()
    elseif extra == "app" then
        do_make_app()
    elseif extra == "focus_back" then
        app_focus()
    elseif extra == "ask" then
        S.ask = S.saves and S.saves[1]
    elseif extra == "confirm" then
        local src = S.saves and S.saves[1]
        if src then
            load_save(src, "balatro")
        end
    elseif extra == "load" then
        local src = S.saves and S.saves[1]
        if src then
            load_save(src, "balatro", true)
        end
    elseif extra == "export" then
        do_export()
    elseif extra == "focus" then
        U.show_focus = true
        U.move_focus(0, 1)
    elseif extra == "swipe" then
        shots.after = function()
            local cx, cy = love.graphics.getWidth() / 2, love.graphics.getHeight() / 2
            love.mousepressed(cx, cy, 1, true)
            love.mousemoved(cx, cy - U.px(2), 0, -U.px(2), true)
            love.mousereleased(cx, cy - U.px(2), 1, true)
            print("launcher: swipe page " .. S.page)
        end
    elseif extra == "stick" then
        shots.after = function()
            love.gamepadaxis(nil, "lefty", 1)
            love.gamepadaxis(nil, "lefty", 0)
            love.gamepadaxis(nil, "lefty", 1)
            love.gamepadaxis(nil, "lefty", 0)
            print("launcher: stick focus " .. tostring(U.focus))
        end
    end
    shots.pending, shots.wait = name, 0
end

function love.update(dt)
    U.time = U.time + dt
    X.update(dt)
    step_task(0.012)
    feed_update()
    refresh_installed()
    U.step_anims(dt)
    pad_repeat()
    S.frame = S.frame + 1
    if shots then
        shot_update()
    end
end

function love.draw()
    local w, h = love.graphics.getDimensions()
    X.frame(w, h, draw_scene)
end

local function page_step(d)
    if not S.ask and (S.tab == "game" or S.tab == "saves") then
        S.page = math.max(1, S.page + d)
    end
end

function love.mousemoved(x, y, _, _, istouch)
    if istouch then
        U.touch_mode = true
    end
    U.show_focus = false
    U.pointer_hidden = false
    if S.drag and not S.drag.moved and math.max(math.abs(x - S.drag.x), math.abs(y - S.drag.y)) > U.px(0.5) then
        S.drag.moved = true
        U.pressed = nil
    end
end

function love.mousepressed(x, y, b, istouch)
    if b ~= 1 then
        return
    end
    if istouch then
        U.touch_mode = true
    end
    S.drag = {x = x, y = y}
    local h = U.hit_at(x, y)
    U.pressed = h and h.action and h.id or nil
end

function love.wheelmoved(_, dy)
    if dy ~= 0 then
        page_step(dy > 0 and -1 or 1)
    end
end

function love.mousereleased(x, y, b)
    if b ~= 1 then
        return
    end
    local drag = S.drag
    S.drag = nil
    if drag and drag.moved then
        local dx, dy = x - drag.x, y - drag.y
        if math.abs(dy) > math.abs(dx) and math.abs(dy) > U.px(1.2) then
            page_step(dy < 0 and 1 or -1)
        end
        U.pressed = nil
        return
    end
    local h = U.hit_at(x, y)
    if h and h.id == U.pressed and h.action then
        U.focus = nil
        U.juice(h.id)
        h.action()
    end
    U.pressed = nil
end

local function nav(dx, dy)
    U.show_focus = true
    U.pointer_hidden = true
    U.move_focus(dx, dy)
end

love.keypressed = function(key)
    if "escape" == key then
        if S.ask then
            X.play("cancel")
            S.ask = nil
            return
        end
        love.event.quit()
    elseif key == "down" then
        nav(0, 1)
    elseif key == "up" then
        nav(0, -1)
    elseif key == "right" then
        nav(1, 0)
    elseif key == "left" then
        nav(-1, 0)
    elseif key == "tab" then
        U.show_focus = true
        U.pointer_hidden = true
        U.focus_cycle(love.keyboard.isDown("lshift", "rshift") and -1 or 1)
    elseif key == "pageup" or key == "q" then
        tab_step(-1)
    elseif key == "pagedown" or key == "e" then
        tab_step(1)
    elseif key == "return" or key == "kpenter" or key == "space" then
        U.activate_focus()
    elseif key == "v" and (love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")) then
        pick(love.system.getClipboardText())
    end
end

local PAD_DIRS = {dpdown = {0, 1}, dpup = {0, -1}, dpright = {1, 0}, dpleft = {-1, 0}}

local function pad_hold(key, dir)
    S.pad_hold = dir and {key = key, dir = dir, at = love.timer.getTime() + 0.4} or nil
end

pad_repeat = function()
    local h = S.pad_hold
    if h and love.timer.getTime() >= h.at then
        h.at = h.at + 0.12
        nav(h.dir[1], h.dir[2])
    end
end

function love.gamepadreleased(_, b)
    if S.pad_hold and S.pad_hold.key == b then
        pad_hold(nil)
    end
end

function love.gamepadaxis(_, axis, v)
    if axis ~= "leftx" and axis ~= "lefty" then
        return
    end
    local key = "stick_" .. axis
    if math.abs(v) < 0.35 then
        if S.pad_hold and S.pad_hold.key == key then
            pad_hold(nil)
        end
        return
    end
    if math.abs(v) < 0.6 or (S.pad_hold and S.pad_hold.key == key) then
        return
    end
    local s = v > 0 and 1 or -1
    local dir = axis == "leftx" and {s, 0} or {0, s}
    nav(dir[1], dir[2])
    pad_hold(key, dir)
end

function love.gamepadpressed(_, b)
    if PAD_DIRS[b] then
        pad_hold(b, PAD_DIRS[b])
    end
    if b == "dpdown" then
        nav(0, 1)
    elseif b == "dpup" then
        nav(0, -1)
    elseif b == "dpright" then
        nav(1, 0)
    elseif b == "dpleft" then
        nav(-1, 0)
    elseif b == "leftshoulder" then
        tab_step(-1)
    elseif b == "rightshoulder" then
        tab_step(1)
    elseif b == "a" then
        U.show_focus = true
        if not U.activate_focus() then
            nav(0, 1)
        end
    elseif b == "b" or b == "back" then
        if S.ask then
            X.play("cancel")
            S.ask = nil
        elseif S.tab ~= "play" then
            X.play("cancel")
            to_tab("play")
        end
    end
end

function love.filedropped(file)
    local name = file:getFilename()
    if V.supported() and V.is_save_path(name) then
        import_path(name)
    else
        pick(name)
    end
end

function love.directorydropped(path)
    if V.supported() and V.is_save_path(path) then
        import_path(path)
    else
        pick(path)
    end
end
