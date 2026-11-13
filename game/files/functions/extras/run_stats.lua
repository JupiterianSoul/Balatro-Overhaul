local X = Extras
local KEY = "run_stats"
local M = X.feature(KEY, {})
local L = function(s) return mod_loc(s) end

M.FILE = "run_splits.lua"
M.OLD_FILE = "night_splits.lua"
M.MAX_HANDS = 20
M.PER_COL = 10
M.MAX_ANTES = 11


local function fmt(t)
    t = math.max(0, tonumber(t) or 0)
    local h = math.floor(t / 3600)
    local m = math.floor((t % 3600) / 60)
    local s = t % 60
    if h > 0 then return string.format("%d:%02d:%04.1f", h, m, s) end
    return string.format("%d:%04.1f", m, s)
end
M.fmt = fmt

local function delta(d)
    if d == nil then return "" end
    if math.abs(d) < 0.05 then return "0.0" end
    return (d < 0 and "-" or "+") .. fmt(math.abs(d))
end
M.delta = delta

local function num(v)
    if v == nil then return "0" end
    local ok, s = pcall(number_format, v)
    if ok and s then return tostring(s) end
    return tostring(v)
end

local function load_best()
    if M.best then return M.best end
    M.best = {}
    local ok, data = pcall(love.filesystem.read, M.FILE)
    if not (ok and type(data) == "string") then ok, data = pcall(love.filesystem.read, M.OLD_FILE) end
    if ok and type(data) == "string" then
        local fn = loadstring(data)
        if fn then
            setfenv(fn, {})
            local ok2, t = pcall(fn)
            if ok2 and type(t) == "table" then M.best = t end
        end
    end
    return M.best
end
M.load_best = load_best

local function save_best()
    local keys = {}
    for k in pairs(M.best or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        local parts = {}
        for a, v in pairs(M.best[k]) do
            if type(a) == "number" and type(v) == "number" then parts[#parts + 1] = string.format("[%d] = %.2f", a, v) end
        end
        table.sort(parts)
        out[#out + 1] = string.format("[%q] = {%s}", k, table.concat(parts, ", "))
    end
    pcall(function() require("functions/fast_fs").write(M.FILE, "return {\n  " .. table.concat(out, ",\n  ") .. "\n}\n") end)
end

function M.run_key()
    local g = G.GAME
    local back = g and g.selected_back and g.selected_back.effect and g.selected_back.effect.center
    return tostring(back and back.key or "?") .. "|" .. tostring(g and g.stake or 1)
end

function M.counts()
    local g = G.GAME
    return g and not g.seeded and not g.challenge and not g.multiplayer
end

function M.split(t, ante)
    if t.splits[ante] then return end
    t.splits[ante] = t.t
    local seg = t.t - (t.splits[ante - 1] or 0)
    t.segs = t.segs or {}
    t.segs[ante] = seg
    if not M.counts() then return end
    local best = load_best()
    local k = M.run_key()
    best[k] = best[k] or {}
    local prev = best[k][ante]
    t.deltas = t.deltas or {}
    t.prev_best = t.prev_best or {}
    t.prev_best[ante] = prev
    if prev then t.deltas[ante] = seg - prev end
    if not prev or seg < prev then
        best[k][ante] = seg
        save_best()
    end
end

function M.tick(dt)
    local g = G.GAME
    if G.STAGE ~= G.STAGES.RUN or not (g and g.round_resets) or G.SETTINGS.paused or G.STATE == G.STATES.GAME_OVER then return end
    local t = g.run_timer
    if not t then
        t = {t = 0, splits = {}, ante = g.round_resets.ante}
        g.run_timer = t
    end
    t.t = t.t + dt
    local a = g.round_resets.ante
    if a ~= t.ante then
        if type(a) == "number" and type(t.ante) == "number" and a > t.ante then M.split(t, t.ante) end
        t.ante = a
    end
end

function M.record()
    if not (G and G.GAME) then return end
    local chips, m = rawget(_G, "hand_chips"), rawget(_G, "mult")
    if chips == nil or m == nil then return end
    local ok, score = pcall(function() return chips * m end)
    if not ok then return end
    local log = G.GAME.run_hand_log or {}
    G.GAME.run_hand_log = log
    table.insert(log, 1, {
        hand = G.GAME.last_hand_played or "",
        chips = num(chips),
        mult = num(m),
        score = num(type(score) == "number" and math.floor(score) or score),
        ante = G.GAME.round_resets and G.GAME.round_resets.ante or 0,
    })
    while #log > M.MAX_HANDS do table.remove(log) end
end

function M.on_toggle(v)
    M.live = v
end

function M.init()
    M.live = X.on(KEY)
    if not M._timer and Game and Game.update then
        M._timer = true
        local orig = Game.update
        Game.update = function(self, dt)
            orig(self, dt)
            if M.live then M.tick(dt) end
        end
    end
    if not M._hands and type(G.FUNCS.evaluate_play) == "function" then
        M._hands = true
        local orig = G.FUNCS.evaluate_play
        G.FUNCS.evaluate_play = function(...)
            local r = {orig(...)}
            if X.on(KEY) then pcall(M.record) end
            return unpack(r)
        end
    end
end

local TS = 0.32
local ROW = 0.36
local GAP = 0.12

local function text(str, colour)
    return {n = G.UIT.T, config = {text = tostring(str), scale = TS, colour = colour or G.C.UI.TEXT_LIGHT, shadow = true}}
end

local function cell(nodes, w, align)
    if nodes.n then nodes = {nodes} end
    return {n = G.UIT.C, config = {align = align or "cr", minw = w, maxw = w, minh = ROW}, nodes = nodes}
end

local function gap(w)
    return {n = G.UIT.C, config = {minw = w or GAP, minh = ROW}, nodes = {}}
end

local function tw(str)
    return UIK.text_w(str, TS)
end

local function name_of(set, key)
    local ok, s = pcall(localize, {type = "name_text", set = set, key = key})
    if ok and type(s) == "string" and s ~= "ERROR" then return s end
    return tostring(key)
end

local function hand_name(key)
    if not key or key == "" then return "?" end
    local s = localize(key, "poker_hands")
    if s == "ERROR" then return key end
    return s
end

local function widths()
    local w = {n = math.max(tw("20"), tw("#")) + 0.1, cm = 2.5, score = 2.0}
    local hand = tw(L("Hand"))
    for _, k in ipairs(G.handlist or {}) do hand = math.max(hand, tw(hand_name(k))) end
    w.hand = math.min(math.max(hand + 0.15, 2.2), 3.4)
    w.sub = w.n + GAP + w.hand + GAP + w.cm + GAP + w.score
    w.mid = 0.4
    w.inner = 2 * w.sub + w.mid
    return w
end

local function card(header, body, w)
    local nodes = {UIK.header(header, {w = w})}
    for _, r in ipairs(body) do nodes[#nodes + 1] = r end
    return {n = G.UIT.R, config = {align = "cm", padding = 0.08, r = 0.12, colour = UIK.C.section}, nodes = {
        {n = G.UIT.C, config = {align = "tm", minw = w}, nodes = nodes},
    }}
end

local function note_row(str, w)
    return {n = G.UIT.R, config = {align = "cm", minw = w, minh = ROW}, nodes = {text(str, UIK.C.muted)}}
end

local function antes_rows(w)
    local g = G.GAME or {}
    local t = g.run_timer or {t = 0, splits = {}}
    local best = load_best()[M.run_key()] or {}
    local cur = tonumber(t.ante) or (g.round_resets and g.round_resets.ante) or 1
    local labels = {L("Ante"), L("Time"), L("Best"), L("Difference")}
    local lw = 0
    for _, s in ipairs(labels) do lw = math.max(lw, tw(s)) end
    lw = lw + 0.2
    local max_cols = math.max(1, math.min(M.MAX_ANTES, math.floor((w - lw) / 1.15)))
    local cw = (w - lw) / max_cols
    local antes = {}
    for a in pairs(t.splits or {}) do if type(a) == "number" and a < cur then antes[#antes + 1] = a end end
    table.sort(antes)
    local first = math.max(1, #antes - max_cols + 2)
    local cols = {}
    local function column(cells, colour)
        local rows = {}
        for i, c in ipairs(cells) do rows[i] = {n = G.UIT.R, config = {align = "cr", minh = ROW}, nodes = {cell(c, cw - 0.1)}} end
        return {n = G.UIT.C, config = {align = "tm", minw = cw, padding = 0, r = 0.08, colour = colour or G.C.CLEAR}, nodes = {
            {n = G.UIT.R, config = {align = "cr", padding = 0}, nodes = {{n = G.UIT.C, config = {align = "tm"}, nodes = rows}}},
        }}
    end
    local label_rows = {}
    for i, s in ipairs(labels) do label_rows[i] = {n = G.UIT.R, config = {align = "cl", minh = ROW}, nodes = {cell(text(s, UIK.C.muted), lw, "cl")}} end
    cols[1] = {n = G.UIT.C, config = {align = "tm", minw = lw}, nodes = label_rows}
    for i = first, #antes do
        local a = antes[i]
        local seg = t.segs and t.segs[a]
        local d = t.deltas and t.deltas[a]
        local shown_best = (t.prev_best and t.prev_best[a]) or best[a]
        local dtext, dcol
        if d then dtext, dcol = delta(d), d <= 0 and G.C.GREEN or G.C.RED
        elseif M.counts() then dtext, dcol = L("New best"), G.C.GOLD
        else dtext, dcol = "-", UIK.C.muted end
        cols[#cols + 1] = column({text(a), text(seg and fmt(seg) or "-"), text(shown_best and fmt(shown_best) or "-", UIK.C.muted), text(dtext, dcol)})
    end
    local now_seg = t.t - (t.splits and t.splits[cur - 1] or 0)
    local tint = {G.C.GOLD[1], G.C.GOLD[2], G.C.GOLD[3], 0.16}
    cols[#cols + 1] = column({text(cur, G.C.GOLD), text(fmt(now_seg), G.C.GOLD), text(best[cur] and fmt(best[cur]) or "-", UIK.C.muted), text(L("Now"), G.C.GOLD)}, tint)
    local used = lw + (#cols - 1) * cw
    if used < w then cols[#cols + 1] = {n = G.UIT.C, config = {minw = w - used, minh = ROW}, nodes = {}} end
    local back = g.selected_back and g.selected_back.effect and g.selected_back.effect.center
    local stake = G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake and G.P_CENTER_POOLS.Stake[g.stake or 1]
    local info = (back and name_of("Back", back.key) or "?") .. ", " .. (stake and name_of("Stake", stake.key) or "?")
    local foot = M.counts() and L("Best times are kept per deck and stake.") or L("Seeded, challenge and MP runs do not change best times.")
    return card(L("Run time") .. " " .. fmt(t.t), {
        {n = G.UIT.R, config = {align = "cl", minw = w}, nodes = cols},
        note_row(info .. ". " .. foot, w),
    }, w)
end

local function hand_row(i, e, w)
    local cm = {text(e.chips, G.C.CHIPS), text(" x ", G.C.UI.TEXT_LIGHT), text(e.mult, G.C.MULT)}
    return {n = G.UIT.R, config = {align = "cm", minh = ROW, r = 0.06, colour = i % 2 == 0 and {0, 0, 0, 0.12} or G.C.CLEAR}, nodes = {
        cell(text(i, UIK.C.muted), w.n), gap(),
        cell(text(hand_name(e.hand)), w.hand, "cl"), gap(),
        cell(cm, w.cm), gap(),
        cell(text(e.score), w.score),
    }}
end

local function hand_head(w)
    return {n = G.UIT.R, config = {align = "cm", minh = ROW}, nodes = {
        cell(text("#", UIK.C.muted), w.n), gap(),
        cell(text(L("Hand"), UIK.C.muted), w.hand, "cl"), gap(),
        cell(text(L("Chips x Mult"), UIK.C.muted), w.cm), gap(),
        cell(text(L("Score"), UIK.C.muted), w.score),
    }}
end

local function hands_rows(w)
    local log = G.GAME and G.GAME.run_hand_log or {}
    local body
    if #log == 0 then
        body = {n = G.UIT.R, config = {align = "cm", minw = w.inner, minh = ROW * (M.PER_COL + 1)}, nodes = {text(L("No hands played yet this run."), UIK.C.muted)}}
    else
        local function sub(from)
            local rows = {hand_head(w)}
            for i = from, from + M.PER_COL - 1 do
                rows[#rows + 1] = log[i] and hand_row(i, log[i], w) or {n = G.UIT.R, config = {minw = w.sub, minh = ROW}, nodes = {}}
            end
            return {n = G.UIT.C, config = {align = "tm", minw = w.sub}, nodes = rows}
        end
        local right = #log > M.PER_COL and sub(M.PER_COL + 1) or {n = G.UIT.C, config = {minw = w.sub}, nodes = {}}
        body = {n = G.UIT.R, config = {align = "tm", minw = w.inner}, nodes = {sub(1), {n = G.UIT.C, config = {minw = w.mid}, nodes = {}}, right}}
    end
    return card(L("Hand log, newest first"), {body}, w.inner)
end

function M.tab_def()
    local t = UIK and UIK.touch and UIK.touch()
    TS = t and 0.42 or 0.32
    ROW = t and 0.48 or 0.36
    local w = widths()
    return {n = G.UIT.ROOT, config = {align = "cm", padding = 0.05, colour = G.C.CLEAR}, nodes = {
        antes_rows(w.inner),
        {n = G.UIT.R, config = {minh = 0.12}, nodes = {}},
        hands_rows(w),
    }}
end

function M.run_info_tab()
    return {label = L("Stats"), tab_definition_function = M.tab_def}
end

mod_loc_register{
    fr = {["Stats"] = "Statistiques", ["Run time"] = "Temps de partie", ["Ante"] = "Mise", ["Time"] = "Temps", ["Best"] = "Meilleur", ["Difference"] = "Écart",
        ["Now"] = "En cours", ["New best"] = "Record", ["Hand log, newest first"] = "Mains jouées, la plus récente en haut",
        ["Hand"] = "Main", ["Chips x Mult"] = "Jetons x Multi", ["Score"] = "Score", ["No hands played yet this run."] = "Aucune main jouée dans cette partie.",
        ["Best times are kept per deck and stake."] = "Les records sont gardés par jeu et par mise.",
        ["Seeded, challenge and MP runs do not change best times."] = "Les parties avec seed, défi ou MP ne changent pas les records."},
    es = {["Stats"] = "Estadísticas", ["Run time"] = "Tiempo de partida", ["Ante"] = "Apuesta", ["Time"] = "Tiempo", ["Best"] = "Mejor", ["Difference"] = "Diferencia",
        ["Now"] = "Ahora", ["New best"] = "Récord", ["Hand log, newest first"] = "Manos jugadas, la más reciente arriba",
        ["Hand"] = "Mano", ["Chips x Mult"] = "Fichas x multi", ["Score"] = "Puntos", ["No hands played yet this run."] = "Todavía no hay manos jugadas en esta partida.",
        ["Best times are kept per deck and stake."] = "Los récords se guardan por baraja y pozo.",
        ["Seeded, challenge and MP runs do not change best times."] = "Las partidas con código, desafío o MP no cambian los récords."},
}

return M
