local ST = {}

local function L(s) return mod_loc and mod_loc(s) or s end
local function kit() return rawget(_G, "bom_kit") end

local GAP = 0.05
local GROUP_GAP = 0.07
local EMB = 0.02
ST.hdr = {}

local function num(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then return tonumber((v:gsub("[,%s]", ""))) end
    if type(v) == "table" and bom_insane_int and bom_insane_int.to_number_if_safe then
        local ok, n = pcall(bom_insane_int.to_number_if_safe, v)
        if ok then return n end
    end
    return nil
end

local function fmt(v)
    if v == nil then return "-" end
    if bom_ui and bom_ui.score_text then return bom_ui.score_text(v) end
    return tostring(v)
end

local function vanilla(key, fallback)
    local ok, s = pcall(localize, key)
    if ok and type(s) == "string" and s ~= "" and s ~= "ERROR" then return s end
    return L(fallback)
end

local function ps_now()
    if bom_ui and bom_ui.in_party_run and bom_ui.in_party_run() then return bom_party.S.ps end
    return nil
end

function ST.kind()
    local ps = ps_now()
    if ps then return ps.kind or (bom_party.kind and bom_party.kind()) or "br", true end
    return (bom_match and bom_match.get_mode and bom_match.get_mode()) or "nemesis", false
end

local function team_name(t)
    if bom_party and bom_party.team_name then return bom_party.team_name(t) end
    return "Team " .. tostring(t)
end

local function team_colour(t)
    if bom_party and bom_party.team_colour then return bom_party.team_colour(t) end
    return G.C.RED
end

function ST.team_groups(list, ps)
    ps = ps or ps_now()
    local groups, by = {}, {}
    for _, t in ipairs((ps and ps.teams) or {}) do
        local id = tonumber(t.team) or 0
        local g = {team = id, lives = tonumber(t.lives) or 0, alive = t.alive ~= false, total = t.score, members = {}}
        by[id] = g
        groups[#groups + 1] = g
    end
    for i, p in ipairs(list) do
        local id = tonumber(p.team) or 0
        local g = by[id]
        if not g then
            g = {team = id, lives = tonumber(p.lives) or 0, alive = p.alive ~= false, members = {}}
            by[id] = g
            groups[#groups + 1] = g
        end
        g.members[#g.members + 1] = i
        if p.mine then g.mine = true end
    end
    local out = {}
    for _, g in ipairs(groups) do
        if #g.members > 0 then
            if g.total == nil then
                local sum = 0
                for _, i in ipairs(g.members) do sum = sum + (num(list[i].score) or 0) end
                g.total = sum
            end
            out[#out + 1] = g
        end
    end
    table.sort(out, function(a, b)
        if a.alive ~= b.alive then return a.alive end
        local ta, tb = num(a.total) or 0, num(b.total) or 0
        if ta ~= tb then return ta > tb end
        return a.team < b.team
    end)
    return out
end

function ST.raid_info(list, ps)
    ps = ps or ps_now()
    local r = (ps and ps.raid) or {}
    local v = (bom_party_run and bom_party_run.view and bom_party_run.view()) or {}
    local target = num(r.target) or num(v.target) or 0
    local sum = 0
    for _, p in ipairs(list) do sum = sum + (num(p.score) or 0) end
    local total = math.max(num(r.total) or 0, num(v.total) or 0, sum)
    local lives = tonumber(r.lives)
    if lives == nil and list[1] then lives = tonumber(list[1].lives) end
    return {target = target, total = total, lives = lives or 0, frac = target > 0 and math.min(1, total / target) or 0}
end

local function bar(w, h, frac, colour)
    frac = math.max(0, math.min(1, tonumber(frac) or 0))
    local r = math.min(0.08, h * 0.4)
    local nodes = {}
    if frac > 0.004 then
        local fw = math.max(0.04, w * frac)
        nodes[1] = {n = G.UIT.C, config = {minw = fw, maxw = fw, minh = h, r = r, colour = colour}, nodes = {}}
    end
    return {n = G.UIT.C, config = {align = "cl", minw = w, maxw = w, minh = h, r = r, colour = {0, 0, 0, 0.35}}, nodes = nodes}
end
ST.bar = bar

local function raid_colour(frac)
    return (frac or 0) >= 1 and G.C.GREEN or G.C.ORANGE
end

local function emote_id(p)
    return p.pid ~= nil and ("bom_emote_pid_" .. tostring(p.pid)) or nil
end

local function name_colours(k, p, team_col)
    if p.alive == false then return k.colour("out"), k.colour("light_text") end
    if p.mine then return k.colour("gold"), k.colour("dark_text") end
    return team_col or k.colour("name"), k.colour("light_text")
end

local function fit_rh(h, lines, extra)
    EMB = lines > 4 and 0 or 0.02
    local rh = (h - (lines - 1) * GAP - (extra or 0) - lines * 4 * EMB) / math.max(1, lines)
    return math.max(0.16, math.min(0.36, rh))
end

local function scale_for(rh)
    return math.min(0.32, rh * 0.8)
end

local function as_col(node)
    if node.n == G.UIT.R then node.n = G.UIT.C end
    return node
end

local function gap_row(h)
    return {n = G.UIT.R, config = {minh = h or GAP}, nodes = {}}
end

local NAME_SC, NAME_MIN

local function name_fit(k, name, w, sc)
    if NAME_SC then return NAME_SC, NAME_SC end
    local cap = {}
    for ch in tostring(name or "?"):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if #cap == 10 then break end
        cap[#cap + 1] = ch
    end
    local _, fs = k.fit(table.concat(cap), w - 0.16, sc, math.min(sc, 0.18))
    NAME_MIN = math.min(NAME_MIN or fs, fs)
    return sc, math.min(sc, 0.18)
end

local function member_row(k, p, m, w, rh, sc, o)
    o = o or {}
    local stat_w = math.max(0.34, rh * 1.25)
    local score_w = o.score_w or math.max(1.0, w * 0.3)
    local badge_w = o.badge == false and 0 or math.max(0.5, rh * 2.1)
    local place_w = o.place and math.max(0.3, rh * 1.1) or 0
    local tag_w = o.tag and math.max(0.8, w * 0.22) or 0
    local stats = (o.lives and 1 or 0) + (o.hands == false and 0 or 1)
    local count = (o.place and 1 or 0) + (o.tag and 1 or 0) + (o.badge == false and 0 or 1) + 1 + stats + 1
    local name_w = w - place_w - tag_w - badge_w - stats * stat_w - score_w - (count - 1) * GAP
    local out = p.alive == false
    local bar_col, text_col = name_colours(k, p, o.team_col)
    local cells = {}
    if o.place then cells[#cells + 1] = k.place_tag(o.place, {w = place_w, h = rh, scale = sc}) end
    if o.tag then cells[#cells + 1] = k.pill(o.tag, {w = tag_w, h = rh, scale = sc, colour = o.tag_colour, text_colour = o.tag_text, emboss = EMB}) end
    if o.badge ~= false then cells[#cells + 1] = k.badge_slot(bom_badges and bom_badges.for_player(p, {h = rh, size = rh}) or nil, {w = badge_w, h = rh}) end
    local nsc, nmin = name_fit(k, p.name, name_w, sc)
    cells[#cells + 1] = k.name_bar(p.name, {w = name_w, h = rh, scale = nsc, min_scale = nmin, colour = bar_col, text_colour = text_col, shadow = not p.mine, emboss = EMB})
    if o.lives then cells[#cells + 1] = k.stat_box({ref_table = m, ref_value = "lives", w = stat_w, h = rh, scale = sc, colour = out and k.colour("out") or k.colour("lives"), emboss = EMB}) end
    if o.hands ~= false then cells[#cells + 1] = k.stat_box({ref_table = m, ref_value = "hands", w = stat_w, h = rh, scale = sc, colour = out and k.colour("out") or k.colour("hands"), emboss = EMB}) end
    cells[#cells + 1] = k.score_pill({ref_table = m, ref_value = "score", w = score_w, h = rh, scale = sc, chip = rh * 0.8, emboss = EMB})
    return k.row(cells, {w = w, h = rh, gap = GAP, mine = p.mine, padding = 0, plain = not p.mine, id = emote_id(p)})
end

local function half_cell(k, p, m, w, rh, sc, o)
    o = o or {}
    local score_w = math.max(0.66, w * 0.38)
    local place_w = o.place and math.max(0.28, rh) or 0
    local name_w = w - score_w - place_w - (o.place and 2 or 1) * GAP
    local bar_col, text_col = name_colours(k, p, o.team_col)
    local cells = {}
    if o.place then cells[#cells + 1] = k.place_tag(o.place, {w = place_w, h = rh, scale = sc}) end
    local nsc, nmin = name_fit(k, p.name, name_w, sc)
    cells[#cells + 1] = k.name_bar(p.name, {w = name_w, h = rh, scale = nsc, min_scale = nmin, colour = bar_col, text_colour = text_col, shadow = not p.mine, emboss = EMB})
    cells[#cells + 1] = k.score_pill({ref_table = m, ref_value = "score", w = score_w, h = rh, scale = sc, no_chip = true, emboss = EMB})
    return as_col(k.row(cells, {w = w, h = rh, gap = GAP, mine = p.mine, padding = 0, plain = not p.mine, id = emote_id(p)}))
end

local function pairs_rows(k, list, models, idx, w, rh, sc, o)
    local rows = {}
    local half = (w - GAP) / 2
    for j = 1, #idx, 2 do
        local a, b = idx[j], idx[j + 1]
        if #rows > 0 then rows[#rows + 1] = gap_row() end
        local oa = o and o(a, j) or nil
        local ob = b and o and o(b, j + 1) or nil
        rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", minw = w}, nodes = {
            half_cell(k, list[a], models[a], half, rh, sc, oa),
            k.spacer(GAP),
            b and half_cell(k, list[b], models[b], half, rh, sc, ob) or k.cell({}, {w = half, h = rh}),
        }}
    end
    return rows
end

local function append(dst, src)
    for _, r in ipairs(src) do dst[#dst + 1] = r end
end

local function header_row(k, label, colour, text_colour, hm, w, rh, sc, o)
    o = o or {}
    local stat_w = math.max(0.34, rh * 1.25)
    local total_w = o.total_w or math.max(1.1, w * 0.36)
    local mid_w = o.mid and math.max(0.5, w * 0.16) or 0
    local name_w = w - stat_w - total_w - mid_w - (o.mid and 3 or 2) * GAP
    local cells = {
        k.name_bar(label, {w = name_w, h = rh, scale = sc, min_scale = math.min(sc, 0.18), colour = colour, text_colour = text_colour or k.colour("light_text"), emboss = EMB}),
        k.stat_box({ref_table = hm, ref_value = "lives", w = stat_w, h = rh, scale = sc, colour = o.out and k.colour("out") or k.colour("lives"), emboss = EMB}),
    }
    if o.mid then cells[#cells + 1] = k.cell({k.text(o.mid, {scale = sc * 0.9, colour = k.colour("muted"), shadow = false})}, {w = mid_w, h = rh}) end
    cells[#cells + 1] = k.score_pill({ref_table = hm, ref_value = "total", w = total_w, h = rh, scale = sc, chip = rh * 0.8, emboss = EMB})
    return k.row(cells, {w = w, h = rh, gap = GAP, mine = o.mine, padding = 0, plain = not o.mine})
end

local function teams_board(k, list, models, w, h)
    local groups = ST.team_groups(list)
    local nt = #groups
    local one, two = nt, nt
    for _, g in ipairs(groups) do
        one = one + #g.members
        two = two + math.ceil(#g.members / 2)
    end
    local cols = one <= 8 and 1 or 2
    local lines = cols == 1 and one or two
    local rh = fit_rh(h, lines, (nt - 1) * GROUP_GAP)
    local sc = scale_for(rh)
    local hidden = bom_ui.opp_score_hidden and bom_ui.opp_score_hidden()
    ST.hdr = {}
    local rows = {}
    for gi, g in ipairs(groups) do
        local hm = {lives = tostring(g.lives), total = (hidden and not g.mine) and "???" or fmt(g.total)}
        ST.hdr[gi] = hm
        if gi > 1 then rows[#rows + 1] = gap_row(GAP + GROUP_GAP) end
        local col = g.alive and team_colour(g.team) or k.colour("out")
        local label = team_name(g.team) .. (g.mine and (" (" .. L("you") .. ")") or "")
        rows[#rows + 1] = header_row(k, label, col, G.C.WHITE, hm, w, rh, sc, {mine = g.mine, out = not g.alive})
        if cols == 1 then
            for _, i in ipairs(g.members) do
                rows[#rows + 1] = gap_row()
                rows[#rows + 1] = member_row(k, list[i], models[i], w, rh, sc, {team_col = col})
            end
        else
            rows[#rows + 1] = gap_row()
            append(rows, pairs_rows(k, list, models, g.members, w, rh, sc, function() return {team_col = col} end))
        end
    end
    return rows
end

local function raid_board(k, list, models, w, h)
    local R = ST.raid_info(list)
    local n = #list
    local cols = n > 4 and 2 or 1
    local lines = 2 + (cols == 2 and math.ceil(n / 2) or n)
    local rh = fit_rh(h, lines, GROUP_GAP)
    local sc = scale_for(rh)
    local hm = {lives = tostring(R.lives), target = fmt(R.target), total = fmt(R.total)}
    ST.hdr = {hm}
    local stat_w = math.max(0.34, rh * 1.25)
    local target_w = math.max(1.4, w * 0.46)
    local label_w = w - stat_w - target_w - 2 * GAP
    local ls, lsc = k.fit(L("Raid target"), label_w - 0.08, sc * 0.95)
    local total_w = math.max(1.2, w * 0.36)
    local bar_w = w - total_w - GAP
    local rows = {
        k.row({
            k.stat_box({ref_table = hm, ref_value = "lives", w = stat_w, h = rh, scale = sc, colour = k.colour("lives"), emboss = EMB}),
            k.cell({k.text(ls, {scale = lsc, colour = k.colour("light_text")})}, {w = label_w, h = rh}),
            k.score_pill({ref_table = hm, ref_value = "target", w = target_w, h = rh, scale = sc, chip = rh * 0.8, text_colour = G.C.RED, emboss = EMB}),
        }, {w = w, h = rh, gap = GAP, plain = true, padding = 0}),
        gap_row(),
        k.row({
            k.cell({bar(bar_w - 0.08, rh * 0.55, R.frac, raid_colour(R.frac))}, {w = bar_w, h = rh}),
            k.score_pill({ref_table = hm, ref_value = "total", w = total_w, h = rh, scale = sc, chip = rh * 0.8, emboss = EMB}),
        }, {w = w, h = rh, gap = GAP, plain = true, padding = 0}),
        gap_row(GAP + GROUP_GAP),
    }
    local idx = {}
    for i = 1, n do idx[i] = i end
    if cols == 1 then
        for _, i in ipairs(idx) do
            if i > 1 then rows[#rows + 1] = gap_row() end
            rows[#rows + 1] = member_row(k, list[i], models[i], w, rh, sc, {place = i, hands = true})
        end
    else
        append(rows, pairs_rows(k, list, models, idx, w, rh, sc, function(i) return {place = i} end))
    end
    return rows
end

local function br_board(k, list, models, w, h)
    local n = math.min(#list, 8)
    local rh = fit_rh(h, n, 0)
    local sc = scale_for(rh)
    ST.hdr = {}
    local rows = {}
    for i = 1, n do
        if i > 1 then rows[#rows + 1] = gap_row() end
        rows[#rows + 1] = member_row(k, list[i], models[i], w, rh, sc, {place = i, lives = true})
    end
    return rows
end

local BOARDS = {teams = teams_board, raid = raid_board, br = br_board}

function ST.board_kind()
    local kind, party = ST.kind()
    if not (party and BOARDS[kind]) then return nil end
    if kind == "br" then
        local ps = ps_now()
        if #((ps and ps.players) or {}) <= 2 then return nil end
    end
    return kind
end

function ST.board_rows(kind, list, models, w, h)
    local k = kit()
    local fn = BOARDS[kind]
    if not (k and fn) then return nil end
    NAME_SC, NAME_MIN = nil, nil
    fn(k, list, models, w, h)
    NAME_SC = NAME_MIN
    local rows = fn(k, list, models, w, h)
    NAME_SC, NAME_MIN = nil, nil
    return rows
end

function ST.board_sig(kind, list)
    if kind == "teams" then
        local parts = {}
        for _, g in ipairs(ST.team_groups(list)) do parts[#parts + 1] = tostring(g.team) .. ":" .. tostring(g.alive) .. ":" .. #g.members end
        return "t" .. table.concat(parts, ",")
    elseif kind == "raid" then
        return "r" .. tostring(math.floor(ST.raid_info(list).frac * 60))
    end
    return ""
end

function ST.board_fill(kind, list)
    if kind == "teams" then
        local hidden = bom_ui.opp_score_hidden and bom_ui.opp_score_hidden()
        for gi, g in ipairs(ST.team_groups(list)) do
            local hm = ST.hdr[gi]
            if hm then
                hm.lives = tostring(g.lives)
                hm.total = (hidden and not g.mine) and "???" or fmt(g.total)
            end
        end
    elseif kind == "raid" then
        local R = ST.raid_info(list)
        local hm = ST.hdr[1]
        if hm then hm.lives, hm.target, hm.total = tostring(R.lives), fmt(R.target), fmt(R.total) end
    end
end

local function stat_text(v)
    if v == nil then return "-" end
    return tostring(v)
end

local function place_order(kind, list)
    local idx = {}
    for i, p in ipairs(list) do idx[p] = i end
    local out = {}
    for _, p in ipairs(list) do out[#out + 1] = p end
    table.sort(out, function(a, b)
        if (a.alive ~= false) ~= (b.alive ~= false) then return a.alive ~= false end
        if a.alive == false and b.alive == false and a.placement ~= nil and b.placement ~= nil and a.placement ~= b.placement then
            return (tonumber(a.placement) or 99) < (tonumber(b.placement) or 99)
        end
        if kind ~= "raid" then
            local la, lb = tonumber(a.lives) or 0, tonumber(b.lives) or 0
            if la ~= lb then return la > lb end
        end
        local sa, sb = num(a.score), num(b.score)
        if (sa or -1) ~= (sb or -1) then return (sa or -1) > (sb or -1) end
        return idx[a] < idx[b]
    end)
    return out
end

local function tab_dims(lines, extra)
    local k = kit()
    local d = k.dims()
    local touch = k.touch()
    local budget = UIK.H - (UIK.TOP or 0.12) - 0.3 - (extra or 0)
    local emb = 0.03
    local rh = d.row_h
    lines = math.max(1, lines or 1)
    if UIK.portrait and UIK.portrait() then lines = lines * 2 end
    local function solve() return (budget - lines * (0.16 + 6 * emb)) / lines end
    if solve() < rh then
        emb = 0.012
        rh = math.max(0.3, math.min(rh, solve()))
    end
    return {
        k = k, d = d, rh = rh, gap = d.gap, w = UIK.W - (touch and 0.6 or 0.8), emb = emb,
        place = d.place_w, badge = d.badge_w, lives = d.lives_w, status = touch and 3.5 or 3.6,
        stat = touch and 1.1 or 1.0, score = d.score_w, scale = math.min(d.scale, rh * 0.76), small = math.min(d.small, rh * 0.68),
    }
end

local TOP_KEYS = {place = true, badge = true, name = true, lives = true}

local function columns(T, o)
    local cols = {{key = "place", w = T.place}, {key = "badge", w = T.badge}, {key = "name"}}
    if o.lives ~= false then cols[#cols + 1] = {key = "lives", w = T.lives} end
    if o.race then
        cols[#cols + 1] = {key = "race", w = T.status + T.stat + T.gap}
        cols[#cols + 1] = {key = "where", w = T.stat + T.score + T.gap}
    else
        if o.status ~= false then cols[#cols + 1] = {key = "status", w = T.status} end
        cols[#cols + 1] = {key = "hands", w = T.stat}
        cols[#cols + 1] = {key = "discards", w = T.stat}
        cols[#cols + 1] = {key = "score", w = o.score_w or T.score}
    end
    local width = o.w or T.w
    if not o.w and not o.race and UIK.portrait and UIK.portrait() then
        local top, f1, f2, n2 = 0, 0, 0, 0
        for _, c in ipairs(cols) do
            if TOP_KEYS[c.key] then top = top + 1; f1 = f1 + (c.w or 0)
            elseif c.key ~= "status" then n2 = n2 + 1; f2 = f2 + (c.w or 0) end
        end
        for _, c in ipairs(cols) do
            c.line = TOP_KEYS[c.key] and 1 or 2
            if c.key == "name" then c.w = math.max(1.2, width - f1 - (top - 1) * T.gap - 0.12) end
            if c.key == "status" then c.w = math.max(1.2, width - f2 - n2 * T.gap - 0.12) end
        end
        cols.split = true
        return cols
    end
    local fixed = 0
    for _, c in ipairs(cols) do fixed = fixed + (c.w or 0) end
    for _, c in ipairs(cols) do if c.key == "name" then c.w = math.max(1.2, width - fixed - (#cols - 1) * T.gap - 0.12) end end
    return cols
end

local function split_row(T, cols, cells, o)
    if not cols.split then return T.k.row(cells, o) end
    local a, b = {}, {}
    for i, c in ipairs(cols) do
        if cells[i] then
            if c.line == 1 then a[#a + 1] = cells[i] else b[#b + 1] = cells[i] end
        end
    end
    local inner = {n = G.UIT.C, config = {align = "cm", padding = 0}, nodes = {
        T.k.row(a, {plain = true, padding = 0.02}),
        T.k.row(b, {plain = true, padding = 0.02}),
    }}
    return T.k.row({inner}, o)
end

local function head_row(T, cols, labels)
    local k = T.k
    local cells = {}
    for _, c in ipairs(cols) do
        local text = labels[c.key]
        if text then
            local s, sc = k.fit(text, c.w - 0.08, T.small)
            cells[#cells + 1] = k.cell({k.text(s, {scale = sc, colour = k.colour("muted"), shadow = false})}, {w = c.w, h = T.rh * 0.7, align = c.key == "name" and "cl" or "cm"})
        else
            cells[#cells + 1] = k.cell({}, {w = c.w, h = T.rh * 0.7})
        end
    end
    return split_row(T, cols, cells, {plain = true, padding = 0.02})
end

local function race_data()
    local d = bom_race and bom_race.S and bom_race.S.data or nil
    if type(d) ~= "table" then return nil end
    local by = {}
    for _, p in ipairs(d.players or {}) do if p.pid ~= nil then by[p.pid] = p end end
    return d, by
end

local function standing_row(T, cols, p, place, o)
    local k = T.k
    local rh = T.rh
    local out = p.alive == false
    local cells = {}
    for _, c in ipairs(cols) do
        local key = c.key
        local sc, E = T.scale, T.emb
        if key == "place" then
            cells[#cells + 1] = k.place_tag(place, {w = c.w, h = rh, scale = sc})
        elseif key == "badge" then
            cells[#cells + 1] = bom_badges.slot(p, {w = c.w, h = rh})
        elseif key == "name" then
            local bar_col, text_col
            if out then bar_col, text_col = k.colour("out"), k.colour("light_text")
            elseif p.mine then bar_col, text_col = k.colour("gold"), k.colour("dark_text")
            elseif o.team_col then bar_col, text_col = o.team_col, k.colour("light_text")
            else bar_col, text_col = k.colour("name_light"), k.colour("dark_text") end
            cells[#cells + 1] = k.name_bar(p.name, {w = c.w, h = rh, scale = sc, colour = bar_col, text_colour = text_col, shadow = false, emboss = E})
        elseif key == "lives" then
            if o.no_lives then cells[#cells + 1] = k.cell({}, {w = c.w, h = rh})
            else cells[#cells + 1] = k.lives_pill(p.lives, {w = c.w, h = rh, scale = sc, emboss = E}) end
        elseif key == "status" then
            cells[#cells + 1] = k.status_pill(bom_ui.player_status(p), {w = c.w, h = rh, scale = sc, emboss = E})
        elseif key == "hands" then
            cells[#cells + 1] = k.stat_box({value = stat_text(p.hands), w = c.w, h = rh, scale = sc, colour = out and k.colour("out") or k.colour("hands"), emboss = E})
        elseif key == "discards" then
            cells[#cells + 1] = k.stat_box({value = stat_text(p.discards), w = c.w, h = rh, scale = sc, colour = out and k.colour("out") or G.C.RED, emboss = E})
        elseif key == "score" then
            local s = p.score
            if s == nil then s = p.live_score end
            cells[#cells + 1] = k.score_pill({text = s ~= nil and fmt(s) or "-", w = c.w, h = rh, scale = sc, chip = rh * 0.8, emboss = E})
        elseif key == "race" then
            local r = o.race or {}
            local goal = math.max(1, tonumber(o.goal) or 1)
            local frac = (tonumber(r.cleared) or 0) / goal
            cells[#cells + 1] = k.cell({bar(c.w - 0.16, rh * 0.5, frac, p.mine and G.C.GOLD or G.C.BLUE)}, {w = c.w, h = rh, r = 0.1, colour = k.colour("status")})
        elseif key == "where" then
            local r = o.race or {}
            local text
            if out then text = L("Out")
            elseif (tonumber(r.cleared) or 0) >= (tonumber(o.goal) or 1e9) then text = L("Done")
            elseif r.ante then text = string.format(L("A%d %s"), tonumber(r.ante) or 1, L(({S = "Small", B = "Big", L = "Boss"})[r.blind or "S"] or "Small"))
            else text = bom_ui.player_status(p).text end
            cells[#cells + 1] = k.pill(text, {w = c.w, h = rh, scale = sc, emboss = E})
        end
    end
    return split_row(T, cols, cells, {mine = p.mine, padding = 0.05, id = emote_id(p)})
end

local function span_w(T, cols, a, b)
    local w, n, on = 0, 0, false
    for _, c in ipairs(cols) do
        if c.key == a then on = true end
        if on then w, n = w + c.w, n + 1 end
        if on and c.key == b then break end
    end
    return w + math.max(0, n - 1) * T.gap
end

local function has_col(cols, key)
    for _, c in ipairs(cols) do if c.key == key then return true end end
    return false
end

local function group_head(T, cols, label, colour, text_colour, lives, total, o)
    o = o or {}
    local k = T.k
    local rh = T.rh
    local lives_a, lives_b = "lives", "lives"
    if not has_col(cols, "lives") then lives_a, lives_b = "hands", "discards" end
    local sc, E = T.scale, T.emb
    local cells = {k.name_bar(label, {w = span_w(T, cols, "place", "name"), h = rh, scale = sc, colour = colour, text_colour = text_colour or k.colour("light_text"), shadow = true, emboss = E})}
    cells[#cells + 1] = lives ~= nil and k.lives_pill(lives, {w = span_w(T, cols, lives_a, lives_b), h = rh, scale = sc, emboss = E}) or k.cell({}, {w = span_w(T, cols, lives_a, lives_b), h = rh})
    if has_col(cols, "status") then
        local mw = span_w(T, cols, "status", "discards")
        if o.mid then
            local ms, msc = k.fit(o.mid, mw - 0.1, T.small)
            cells[#cells + 1] = k.cell({k.text(ms, {scale = msc, colour = k.colour("muted"), shadow = false})}, {w = mw, h = rh})
        else
            cells[#cells + 1] = k.cell({}, {w = mw, h = rh})
        end
    end
    local sw = span_w(T, cols, "score", "score")
    cells[#cells + 1] = total ~= nil and k.score_pill({text = fmt(total), w = sw, h = rh, scale = sc, chip = rh * 0.8, emboss = E}) or k.cell({}, {w = sw, h = rh})
    return k.row(cells, {mine = o.mine, padding = 0.05, plain = not o.mine})
end

local function raid_head(T, list)
    local k = T.k
    local R = ST.raid_info(list)
    local rh = T.rh
    local lw = T.lives + 0.6
    local tw = T.score
    local label_w = 2.4
    local total_w = T.score
    local bar_w = T.w - label_w - tw - total_w - lw - 4 * T.gap - 0.12
    local ls, lsc = k.fit(L("Raid target"), label_w - 0.1, T.scale)
    local lives_text = L("Raid lives") .. ": " .. tostring(R.lives)
    local sc, E = T.scale, T.emb
    return k.row({
        k.cell({k.text(ls, {scale = lsc, colour = k.colour("light_text")})}, {w = label_w, h = rh}),
        k.score_pill({text = fmt(R.target), w = tw, h = rh, scale = sc, chip = rh * 0.8, text_colour = G.C.RED, emboss = E}),
        k.cell({bar(bar_w - 0.16, rh * 0.5, R.frac, raid_colour(R.frac))}, {w = bar_w, h = rh, r = 0.1, colour = k.colour("status")}),
        k.score_pill({text = fmt(R.total), w = total_w, h = rh, scale = sc, chip = rh * 0.8, emboss = E}),
        k.pill(lives_text, {w = lw, h = rh, scale = sc, colour = k.colour("lives"), emboss = E}),
    }, {padding = 0.05})
end

local function spacer_row(h)
    return {n = G.UIT.R, config = {minh = h, minw = 0.1}, nodes = {}}
end

local function labels()
    return {name = L("Player"), lives = L("Lives"), status = L("Status"), hands = vanilla("k_hud_hands", "Hands"),
        discards = vanilla("k_hud_discards", "Discards"), score = L("Score"), race = L("Progress"), where = L("Status")}
end

local function teams_body(T, list)
    local k = T.k
    local groups = ST.team_groups(list)
    local bw = (T.w - 0.3) / 2
    local cols = columns(T, {w = bw, lives = false, status = false, score_w = T.score - 0.4})
    local blocks = {}
    for _, g in ipairs(groups) do
        local col = g.alive and team_colour(g.team) or k.colour("out")
        local label = team_name(g.team) .. (g.mine and (" (" .. L("you") .. ")") or "")
        local nodes = {head_row(T, cols, labels())}
        nodes[#nodes + 1] = group_head(T, cols, label, col, G.C.WHITE, g.lives, g.total, {mine = g.mine})
        local members = {}
        for _, i in ipairs(g.members) do members[#members + 1] = list[i] end
        for pi, p in ipairs(place_order("teams", members)) do
            nodes[#nodes + 1] = spacer_row(0.06)
            nodes[#nodes + 1] = standing_row(T, cols, p, pi, {team_col = col})
        end
        blocks[#blocks + 1] = {n = G.UIT.C, config = {align = "tm", minw = bw, padding = 0.06, r = 0.12, colour = {0, 0, 0, 0.12}}, nodes = nodes}
    end
    local rows = {}
    for i = 1, #blocks, 2 do
        if #rows > 0 then rows[#rows + 1] = spacer_row(0.14) end
        local right = blocks[i + 1] or {n = G.UIT.C, config = {minw = bw + 0.12}, nodes = {}}
        rows[#rows + 1] = {n = G.UIT.R, config = {align = "tm"}, nodes = {blocks[i], {n = G.UIT.C, config = {minw = 0.16}, nodes = {}}, right}}
    end
    return rows
end

local function plain_body(T, kind, list)
    local rows = {}
    local race_d, race_by = nil, nil
    if kind == "race" then race_d, race_by = race_data() end
    local raid = kind == "raid"
    local cols = columns(T, {race = race_d ~= nil, lives = not raid})
    if raid then
        rows[#rows + 1] = raid_head(T, list)
        rows[#rows + 1] = spacer_row(0.12)
    elseif race_d then
        local k = T.k
        rows[#rows + 1] = {n = G.UIT.R, config = {align = "cm", padding = 0.04}, nodes = {
            k.text(string.format(L("Race to ante %d"), tonumber(race_d.target) or 4), {scale = T.scale + 0.06, colour = G.C.GOLD})}}
    end
    rows[#rows + 1] = head_row(T, cols, labels())
    local goal = race_d and (tonumber(race_d.goal) or ((tonumber(race_d.target) or 4) * 3)) or nil
    local ordered = place_order(kind, list)
    if race_d then
        table.sort(ordered, function(a, b)
            local ra, rb = race_by[a.pid] or {}, race_by[b.pid] or {}
            local ca, cb = tonumber(ra.cleared) or 0, tonumber(rb.cleared) or 0
            if ca ~= cb then return ca > cb end
            return (tonumber(ra.at) or 0) < (tonumber(rb.at) or 0)
        end)
    end
    for i, p in ipairs(ordered) do
        rows[#rows + 1] = spacer_row(0.06)
        rows[#rows + 1] = standing_row(T, cols, p, i, {race = race_by and race_by[p.pid] or nil, goal = goal})
    end
    return rows
end

function ST.tab_sig()
    local list = bom_ui.roster()
    local parts = {}
    for _, p in ipairs(list) do
        local st = bom_ui.player_status(p)
        parts[#parts + 1] = table.concat({tostring(p.pid), tostring(p.name), tostring(p.lives), tostring(p.alive), tostring(p.connected), tostring(st.text), tostring(st.blind),
            tostring(p.hands), tostring(p.discards), tostring(p.score), tostring(p.live_score), tostring(p.team)}, ":")
    end
    local kind = ST.kind()
    if kind == "teams" then
        for _, g in ipairs(ST.team_groups(list)) do parts[#parts + 1] = tostring(g.team) .. "=" .. tostring(g.lives) .. "/" .. tostring(g.total) end
    elseif kind == "raid" then
        local R = ST.raid_info(list)
        parts[#parts + 1] = tostring(R.target) .. "/" .. tostring(R.total) .. "/" .. tostring(R.lives)
    elseif kind == "race" then
        local d = race_data()
        for _, p in ipairs((d and d.players) or {}) do parts[#parts + 1] = tostring(p.pid) .. "@" .. tostring(p.cleared) .. tostring(p.ante) .. tostring(p.blind) end
    end
    return table.concat(parts, "|")
end

local TICK = {sig = nil, t = 0}

local function st_open()
    local win = UIK and UIK._win
    if not (win and G.OVERLAY_MENU) then return nil end
    if (win.id == "mp_li" and win._cur == "standings") or (win.id == "party_st" and win._cur == "s") then return win end
    return nil
end

local function st_tick()
    local win = st_open()
    if not win then return end
    local now = G.TIMERS and G.TIMERS.REAL or 0
    if now - TICK.t < 0.25 then return end
    TICK.t = now
    local ok, sig = pcall(ST.tab_sig)
    if not ok then return end
    if TICK.sig ~= nil and sig ~= TICK.sig then
        TICK.sig = sig
        G.E_MANAGER:add_event(Event({trigger = "immediate", blocking = false, blockable = false, func = function()
            if UIK._win == win and st_open() == win then pcall(UIK.refresh) end
            return true
        end}))
        return
    end
    TICK.sig = sig
end

local function line_count(kind, list)
    if kind == "teams" then
        local groups = ST.team_groups(list)
        local total = 0
        for i = 1, #groups, 2 do
            local a, b = #groups[i].members, groups[i + 1] and #groups[i + 1].members or 0
            total = total + 1 + math.max(a, b)
        end
        return total, math.ceil(#groups / 2) * 0.5
    end
    local lines = #list
    if kind == "raid" or kind == "race" then lines = lines + 1 end
    return lines, 0.5
end

function ST.tab()
    local kind = ST.kind()
    local list = bom_ui.roster()
    local T = tab_dims(line_count(kind, list))
    local rows = kind == "teams" and teams_body(T, list) or plain_body(T, kind, list)
    local ok, sig = pcall(ST.tab_sig)
    TICK.sig = ok and sig or nil
    return {n = G.UIT.R, config = {align = "tm", minw = UIK.W, padding = 0.08, func = "bom_st_tick"}, nodes = {
        {n = G.UIT.C, config = {align = "tm"}, nodes = rows},
    }}
end

local FR = {["Best"] = "Meilleur", ["Progress"] = "Progression"}
local ES = {["Best"] = "Mejor", ["Progress"] = "Progreso"}

function ST.init()
    if G and G.FUNCS then G.FUNCS.bom_st_tick = st_tick end
    if mod_loc_register then pcall(mod_loc_register, {fr = FR, es = ES}) end
end

return ST
