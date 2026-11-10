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
    local node = B.rank(p.rank, o)
    if node then return node end
    if o.by_name ~= false and bom_ranked and bom_ranked.badge_for and type(p.name) == "string" then
        local ok, n = pcall(bom_ranked.badge_for, p.name, o.size or ((kit() and kit().dims().row_h or 0.42) * 0.9))
        if ok then return n end
    end
    return nil
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
