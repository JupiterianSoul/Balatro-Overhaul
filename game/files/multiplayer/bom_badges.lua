local B = {}

local function L(s) return mod_loc and mod_loc(s) or s end

B.LEVELS = {
    easy = {letter = "E", colour = "GREEN", name = "Easy"},
    medium = {letter = "M", colour = "BLUE", name = "Medium"},
    hard = {letter = "H", colour = "RED", name = "Hard"},
}
B.LEVEL_BY_NUMBER = {"easy", "medium", "hard"}

function B.level_of(p)
    if type(p) ~= "table" then return "medium" end
    local lv = p.bot_level or p.level or p.botLevel
    if type(lv) == "number" then lv = B.LEVEL_BY_NUMBER[lv] end
    if type(lv) == "string" then
        lv = lv:lower()
        if lv == "e" then lv = "easy" elseif lv == "m" then lv = "medium" elseif lv == "h" then lv = "hard" end
    end
    return B.LEVELS[lv] and lv or "medium"
end

function B.is_bot(p)
    if type(p) ~= "table" then return false end
    if p.is_bot ~= nil then return p.is_bot == true end
    return p.bot == true or p.isBot == true
end

local function kit() return rawget(_G, "bom_kit") end

function B.bot(level, o)
    o = o or {}
    local k = kit()
    local d = k and k.dims() or {row_h = 0.42, small = 0.28}
    local h = o.h or d.row_h
    local info = B.LEVELS[level] or B.LEVELS.medium
    local sq = h * 0.86
    local scale = o.scale or math.min(d.small, h * 0.62)
    local col = (G.C and G.C[info.colour]) or G.C.BLUE
    local word = {n = G.UIT.C, config = {align = "cm", minh = sq, padding = 0.04, r = math.min(0.08, sq * 0.3), colour = {0.16, 0.19, 0.22, 1}, emboss = 0.02}, nodes = {
        {n = G.UIT.T, config = {text = L("BOT"), scale = scale, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
    }}
    local letter = {n = G.UIT.C, config = {align = "cm", minw = sq, maxw = sq, minh = sq, r = math.min(0.08, sq * 0.3), colour = col, emboss = 0.02,
        tooltip = {text = {L(info.name)}}}, nodes = {
        {n = G.UIT.T, config = {text = info.letter, scale = scale, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
    }}
    return {n = G.UIT.C, config = {align = "cm", padding = 0}, nodes = {word, {n = G.UIT.C, config = {minw = 0.04}}, letter}}
end

B.DEV_COLOUR = {0.53, 0.40, 0.65, 1}

function B.is_dev(p)
    return type(p) == "table" and p.dev == true
end

function B.dev(o)
    o = o or {}
    local k = kit()
    local d = k and k.dims() or {row_h = 0.42, small = 0.28}
    local h = o.h or d.row_h
    local sq = h * 0.86
    local scale = o.scale or math.min(d.small, h * 0.62)
    G.FUNCS.bom_dev_poly = G.FUNCS.bom_dev_poly or B.poly_install
    return {n = G.UIT.C, config = {align = "cm", minw = B.dev_w(o), minh = sq, padding = 0.02, r = math.min(0.08, sq * 0.3), colour = G.C.CLEAR, func = "bom_dev_poly"}, nodes = {
        {n = G.UIT.T, config = {text = "DEV", scale = scale, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
    }}
end

local POLY = {}
local POLY_PH = 40

local function poly_atlas(w, h, r)
    local pw = math.max(8, math.floor(POLY_PH * w / math.max(h, 0.01) + 0.5))
    local pr = math.max(1, r / math.max(h, 0.01) * POLY_PH)
    local key = pw .. ":" .. math.floor(pr * 10 + 0.5)
    if POLY[key] then return POLY[key] end
    local c = B.DEV_COLOUR
    local lip = math.max(2, math.floor(POLY_PH * 0.08 + 0.5))
    local data = love.image.newImageData(pw, POLY_PH)
    data:mapPixel(function(x, y)
        local px, py = x + 0.5, y + 0.5
        local cx = math.min(math.max(px, pr), pw - pr)
        local cy = math.min(math.max(py, pr), POLY_PH - pr)
        local dx, dy = px - cx, py - cy
        if dx * dx + dy * dy > pr * pr then return 0, 0, 0, 0 end
        if y >= POLY_PH - lip then return c[1] * 0.72, c[2] * 0.72, c[3] * 0.72, 1 end
        return c[1], c[2], c[3], 1
    end)
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    local atlas = {name = "bom_dev_poly_" .. key, image = img, px = pw, py = POLY_PH, type = "asset_atli"}
    G.ASSET_ATLAS[atlas.name] = atlas
    POLY[key] = atlas
    return atlas
end

local function poly_draw(e)
    local spr = e.bom_poly
    if spr and e.states.visible then
        spr:hard_set_T(e.VT.x, e.VT.y, e.VT.w, e.VT.h)
        local t = G.TIMERS.REAL
        spr.ARGS.send_to_shader = spr.ARGS.send_to_shader or {0, 0}
        spr.ARGS.send_to_shader[1] = t / 28 + spr.seed
        spr.ARGS.send_to_shader[2] = t
        spr:draw_shader("dissolve")
        spr:draw_shader("polychrome", nil, spr.ARGS.send_to_shader)
    end
    return e.bom_poly_base(e)
end

local function poly_install(e)
    if e.bom_poly or not (e.T and e.T.w > 0 and e.T.h > 0) then return end
    local ok, spr = pcall(Sprite, e.T.x, e.T.y, e.T.w, e.T.h, poly_atlas(e.T.w, e.T.h, e.config.r or 0.08), {x = 0, y = 0})
    if not ok or not spr then e.bom_poly = false return end
    spr.states.drag.can = false
    spr.states.collide.can = false
    spr.states.hover.can = false
    spr.seed = math.random()
    e.bom_poly = spr
    e.bom_poly_base = e.draw_self
    e.draw_self = poly_draw
    local remove = e.remove
    e.remove = function(self, ...)
        if self.bom_poly then self.bom_poly:remove() self.bom_poly = nil end
        return remove(self, ...)
    end
end

B.poly_install = poly_install

function B.dev_w(o)
    o = o or {}
    local k = kit()
    local d = k and k.dims() or {row_h = 0.42, small = 0.28}
    local h = o.h or d.row_h
    local scale = o.scale or math.min(d.small, h * 0.62)
    local tw = k and k.text_w and k.text_w("DEV", scale) or 3 * scale * 0.3
    return tw + scale * 0.7
end

function B.any_dev(list)
    if type(list) ~= "table" then return false end
    for _, p in pairs(list) do
        if type(p) == "table" and (p.dev == true or (bom_ranked and bom_ranked.is_dev_name and bom_ranked.is_dev_name(p.name))) then return true end
    end
    return false
end

function B.dev_space(o)
    o = o or {}
    local k = kit()
    local h = o.h or (k and k.dims().row_h or 0.42)
    return {n = G.UIT.C, config = {minw = B.dev_w(o) + 0.04, minh = h * 0.86}}
end

function B.dev_col_w(o)
    return B.dev_w(o) + 0.08 + B.dev_rank_opts(o or {}).size
end

function B.with_space(node, o)
    local gap = B.dev_space(o)
    if not node then return gap end
    return {n = G.UIT.C, config = {align = "cm", padding = 0}, nodes = {gap, {n = G.UIT.C, config = {minw = 0.04}}, node}}
end

function B.name_badge(p, size, dev_col)
    if type(p) ~= "table" or type(p.name) ~= "string" or not bom_ranked then return nil end
    local dev = B.is_dev(p) or (bom_ranked.is_dev_name and bom_ranked.is_dev_name(p.name))
    local node = bom_ranked.badge_for(p.name, (dev or dev_col) and size * 0.86 or size, {no_dev = true})
    if dev then return B.with_dev(node, {h = size / 0.9}) end
    if dev_col then return B.with_space(node, {h = size / 0.9}) end
    return node
end

function B.with_dev(node, o)
    local tag = B.dev(o)
    if not node then return tag end
    return {n = G.UIT.C, config = {align = "cm", padding = 0}, nodes = {tag, {n = G.UIT.C, config = {minw = 0.04}}, node}}
end

function B.rank(rank, o)
    o = o or {}
    if type(rank) ~= "table" or rank.rank == nil then return nil end
    if not (bom_ranked and bom_ranked.badge_node) then return nil end
    local size = o.size or ((kit() and kit().dims().row_h or 0.42) * 0.9)
    local ok, node = pcall(bom_ranked.badge_node, tonumber(rank.rank) or 0, tonumber(rank.tier) or 3, size, {})
    if ok then return node end
    return nil
end

function B.for_player(p, o)
    o = o or {}
    if type(p) ~= "table" then return nil end
    if B.is_bot(p) then return B.bot(B.level_of(p), o) end
    local wide = B.is_dev(p) or o.dev_col
    local node = B.rank(p.rank, wide and B.dev_rank_opts(o) or o)
    if not node and o.by_name ~= false and bom_ranked and bom_ranked.badge_for and type(p.name) == "string" then
        local size = o.size or ((kit() and kit().dims().row_h or 0.42) * 0.9)
        if wide then size = size * 0.86 end
        local ok, n = pcall(bom_ranked.badge_for, p.name, size, {no_dev = true})
        if ok then node = n end
    end
    if B.is_dev(p) then return B.with_dev(node, o) end
    if o.dev_col then return B.with_space(node, o) end
    return node
end

function B.dev_rank_opts(o)
    local k = kit()
    local size = o.size or ((k and k.dims().row_h or 0.42) * 0.9)
    local out = {}
    for key, v in pairs(o) do out[key] = v end
    out.size = size * 0.86
    return out
end

function B.slot(p, o)
    o = o or {}
    local k = kit()
    local node = B.for_player(p, o)
    if k then return k.badge_slot(node, {w = o.w, h = o.h}) end
    local d = {n = G.UIT.C, config = {align = "cm", minw = o.w or 0.95, minh = o.h or 0.42}, nodes = node and {node} or {}}
    return d
end

local FR = {["BOT"] = "BOT", ["Easy"] = "Facile", ["Medium"] = "Moyen", ["Hard"] = "Difficile"}
local ES = {["BOT"] = "BOT", ["Easy"] = "Fácil", ["Medium"] = "Medio", ["Hard"] = "Difícil"}

function B.init()
    if mod_loc_register then mod_loc_register({fr = FR, es = ES}) end
end

return B
