local K = {}

local function L(s) return mod_loc and mod_loc(s) or s end
local function touch() return rawget(_G, "UIK") and UIK.touch and UIK.touch() or false end
K.touch = touch

local DESK = {
    row_h = 0.42, gap = 0.1, scale = 0.32, small = 0.28, min_scale = 0.22,
    lives_w = 1.25, name_w = 3.0, badge_w = 0.95, skips_w = 1.25, host_w = 0.95, kick_w = 0.5, status_w = 4.6,
    place_w = 0.5, score_w = 2.2, stat_w = 0.62, chip = 0.34, icon = 0.34,
}
local PHONE = {
    row_h = 0.52, gap = 0.1, scale = 0.38, small = 0.33, min_scale = 0.26,
    lives_w = 1.4, name_w = 3.2, badge_w = 1.05, skips_w = 1.4, host_w = 1.05, kick_w = 0.6, status_w = 4.8,
    place_w = 0.56, score_w = 2.4, stat_w = 0.7, chip = 0.4, icon = 0.42,
}

function K.dims()
    return touch() and PHONE or DESK
end

function K.colour(name, fallback)
    local C = G and G.C
    if not C then return fallback or {1, 1, 1, 1} end
    local all = {
        lives = C.RED, hands = C.BLUE, discards = C.RED, skips = C.PURPLE, host = C.GOLD, gold = C.GOLD,
        name = C.RED, name_host = C.GOLD, name_light = {0.88, 0.89, 0.91, 1},
        status = {0.16, 0.19, 0.22, 1}, score = C.BLACK, row = {0, 0, 0, 0.22}, row_mine = {1, 0.85, 0.3, 0.14},
        dark_text = C.UI and C.UI.TEXT_DARK or {0.2, 0.2, 0.2, 1}, light_text = C.UI and C.UI.TEXT_LIGHT or {1, 1, 1, 1},
        muted = {0.75, 0.79, 0.83, 1}, out = C.UI and C.UI.BACKGROUND_INACTIVE or {0.4, 0.4, 0.4, 1},
        kick = C.RED, mine_outline = C.GOLD,
    }
    return all[name] or fallback or C.WHITE
end

local function text_w(str, scale)
    if rawget(_G, "UIK") and UIK.text_w then return UIK.text_w(str, scale) end
    return #tostring(str or "") * (scale or 0.3) * 0.3
end
K.text_w = text_w

local function chars(s)
    local out = {}
    for ch in tostring(s or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do out[#out + 1] = ch end
    return out
end

function K.fit(str, maxw, scale, min_scale)
    str = tostring(str or "")
    scale = scale or K.dims().scale
    min_scale = math.min(scale, min_scale or K.dims().min_scale)
    if not maxw or maxw <= 0 then return str, scale end
    local w = text_w(str, scale)
    if w <= maxw then return str, scale end
    local s2 = math.max(min_scale, scale * maxw / w)
    if text_w(str, s2) <= maxw + 0.001 then return str, s2 end
    local list = chars(str)
    while #list > 1 do
        list[#list] = nil
        local cut = table.concat(list):gsub("%s+$", "") .. "..."
        if text_w(cut, min_scale) <= maxw then return cut, min_scale end
    end
    return (list[1] or "") .. "...", min_scale
end

function K.text(str, o)
    o = o or {}
    local cfg = {scale = o.scale or K.dims().scale, colour = o.colour or K.colour("light_text"), shadow = o.shadow ~= false, id = o.id}
    if o.ref_table then
        cfg.ref_table, cfg.ref_value = o.ref_table, o.ref_value
    else
        cfg.text = tostring(str or "")
    end
    return {n = G.UIT.T, config = cfg}
end

function K.cell(nodes, o)
    o = o or {}
    local w = o.w or 1
    local h = o.h or K.dims().row_h
    return {n = o.row and G.UIT.R or G.UIT.C, config = {
        align = o.align or "cm", minw = w, maxw = o.no_maxw and nil or w, minh = h, padding = o.padding or 0,
        r = o.r, colour = o.colour or G.C.CLEAR, emboss = o.emboss, outline = o.outline, outline_colour = o.outline_colour,
        id = o.id, button = o.button, hover = o.button ~= nil or o.hover, shadow = o.shadow, func = o.func,
        ref_table = o.ref_table, tooltip = o.tooltip, detailed_tooltip = o.detailed_tooltip, one_press = o.one_press,
    }, nodes = nodes or {}}
end

function K.spacer(w, h)
    return {n = G.UIT.C, config = {minw = w or K.dims().gap, minh = h or 0.01}, nodes = {}}
end

function K.pill(text, o)
    o = o or {}
    local d = K.dims()
    local w, h = o.w or 1.2, o.h or d.row_h
    local scale = o.scale or d.scale
    local inner = w - (o.inset or 0.12)
    local node
    if o.ref_table then
        node = K.text(nil, {ref_table = o.ref_table, ref_value = o.ref_value, scale = scale, colour = o.text_colour, shadow = o.shadow})
    else
        local s, sc = K.fit(text, inner, scale, o.min_scale)
        node = K.text(s, {scale = sc, colour = o.text_colour, shadow = o.shadow})
    end
    local nodes = {node}
    if o.left then table.insert(nodes, 1, o.left) end
    if o.right then nodes[#nodes + 1] = o.right end
    return K.cell(nodes, {w = w, h = h, r = o.r or math.min(0.1, h * 0.3), colour = o.colour or K.colour("status"), emboss = o.emboss or 0.03,
        id = o.id, outline = o.outline, outline_colour = o.outline_colour, tooltip = o.tooltip, func = o.func})
end

local function count_text(n, one, many)
    n = tonumber(n) or 0
    return tostring(n) .. " " .. L(n == 1 and one or many)
end

function K.lives_pill(n, o)
    o = o or {}
    local text = o.short and tostring(tonumber(n) or 0) or count_text(n, "Life", "Lives")
    local out = (tonumber(n) or 0) <= 0 and o.dim_out ~= false
    return K.pill(text, {w = o.w or K.dims().lives_w, h = o.h, scale = o.scale, colour = out and K.colour("out") or K.colour("lives"), id = o.id, emboss = o.emboss})
end

function K.skips_pill(n, o)
    o = o or {}
    return K.pill(count_text(n, "Skip", "Skips"), {w = o.w or K.dims().skips_w, h = o.h, scale = o.scale, colour = K.colour("skips"), id = o.id})
end

function K.host_tag(on, o)
    o = o or {}
    local w = o.w or K.dims().host_w
    if not on then return K.cell({}, {w = w, h = o.h}) end
    return K.pill(L("HOST"), {w = w, h = o.h, scale = o.scale, colour = K.colour("host"), text_colour = K.colour("dark_text"), shadow = false})
end

K.BLIND_ART = {
    bl_mp_nemesis = {atlas = "mp_nemesis_chip", pos = {x = 0, y = 0}},
    bl_mp_clash = {atlas = "mp_blind_chips", pos = {x = 0, y = 1}, colour = "d85f23"},
    bl_mp_raid = {atlas = "mp_blind_chips", pos = {x = 0, y = 3}, colour = "8a41b7"},
    bl_mp_royale = {atlas = "mp_blind_chips", pos = {x = 0, y = 4}, colour = "e29f29"},
    bl_mp_race = {atlas = "mp_blind_chips", pos = {x = 0, y = 5}, colour = "3f9e4f"},
}

function K.blind_icon(key, size)
    local b = key and G and G.P_BLINDS and G.P_BLINDS[key]
    if not (b and b.pos and G.ANIMATION_ATLAS) then return nil end
    local art = K.BLIND_ART[key]
    local own = art and G.ANIMATION_ATLAS[art.atlas]
    local atlas = own or G.ANIMATION_ATLAS[b.atlas or "blind_chips"] or G.ANIMATION_ATLAS.blind_chips
    if not atlas then return nil end
    local ok, spr = pcall(AnimatedSprite, 0, 0, size, size, atlas, own and art.pos or b.pos)
    if not ok or not spr then return nil end
    spr.states.drag.can = false
    spr.states.collide.can = false
    return {n = G.UIT.O, config = {object = spr, can_collide = false}}
end

function K.chip_icon(size)
    if not get_stake_sprite then return nil end
    local ok, spr = pcall(get_stake_sprite, (G and G.GAME and G.GAME.stake) or 1, size)
    if not ok or not spr then return nil end
    return {n = G.UIT.O, config = {w = size, h = size, object = spr, can_collide = false}}
end

function K.status_pill(st, o)
    o = o or {}
    st = st or {}
    local d = K.dims()
    local w, h = o.w or d.status_w, o.h or d.row_h
    local icon = st.blind and K.blind_icon(st.blind, math.min(d.icon, h * 0.86)) or nil
    local room = w - 0.16 - (icon and (d.icon + 0.08) or 0)
    local s, sc = K.fit(st.text or "", room, o.scale or d.scale)
    local nodes = {K.text(s, {scale = sc, colour = st.text_colour})}
    if icon then
        nodes[#nodes + 1] = K.spacer(0.08)
        nodes[#nodes + 1] = icon
    end
    return K.cell(nodes, {w = w, h = h, r = math.min(0.1, h * 0.3), colour = st.colour or K.colour("status"), emboss = o.emboss or 0.03, id = o.id})
end

function K.name_bar(name, o)
    o = o or {}
    local d = K.dims()
    local w, h = o.w or d.name_w, o.h or d.row_h
    local s, sc = K.fit(name or "?", w - 0.16, o.scale or d.scale, o.min_scale)
    local tc = o.text_colour or K.colour("light_text")
    return K.cell({K.text(s, {scale = sc, colour = tc, shadow = o.shadow})}, {w = w, h = h, r = math.min(0.1, h * 0.3),
        colour = o.colour or K.colour("name"), emboss = o.emboss or 0.03, id = o.id, outline = o.outline, outline_colour = o.outline_colour})
end

function K.place_tag(n, o)
    o = o or {}
    local d = K.dims()
    return K.cell({K.text("#" .. tostring(n or "?"), {scale = o.scale or d.scale, colour = o.colour or K.colour("gold")})}, {w = o.w or d.place_w, h = o.h})
end

function K.stat_box(o)
    o = o or {}
    local d = K.dims()
    local w, h = o.w or d.stat_w, o.h or d.row_h
    local node
    if o.ref_table then
        node = K.text(nil, {ref_table = o.ref_table, ref_value = o.ref_value, scale = o.scale or d.scale, colour = o.text_colour})
    else
        node = K.text(tostring(o.value or "-"), {scale = o.scale or d.scale, colour = o.text_colour})
    end
    return K.cell({node}, {w = w, h = h, r = math.min(0.1, h * 0.3), colour = o.colour or K.colour("score"), emboss = o.emboss or 0.03, id = o.id})
end

function K.score_pill(o)
    o = o or {}
    local d = K.dims()
    local w, h = o.w or d.score_w, o.h or d.row_h
    local chip_size = math.min(o.chip or d.chip, h * 0.82)
    local chip = o.no_chip ~= true and K.chip_icon(chip_size) or nil
    local text_room = w - 0.16 - (chip and (chip_size + 0.06) or 0)
    local text_node
    if o.ref_table then
        text_node = {n = G.UIT.C, config = {align = "cm", maxw = text_room}, nodes = {
            K.text(nil, {ref_table = o.ref_table, ref_value = o.ref_value, scale = o.scale or d.scale, colour = o.text_colour})}}
    else
        local s, sc = K.fit(o.text or "0", text_room, o.scale or d.scale)
        text_node = K.text(s, {scale = sc, colour = o.text_colour})
    end
    local nodes = {}
    if chip then
        nodes[#nodes + 1] = chip
        nodes[#nodes + 1] = K.spacer(0.06)
    end
    nodes[#nodes + 1] = text_node
    return K.cell(nodes, {w = w, h = h, r = math.min(0.1, h * 0.3), colour = o.colour or K.colour("score"), emboss = o.emboss or 0.03, id = o.id})
end

function K.icon_button(o)
    o = o or {}
    local d = K.dims()
    local w, h = o.w or d.kick_w, o.h or d.row_h
    return {n = G.UIT.C, config = {align = "cm", minw = w, maxw = w, minh = h, r = math.min(0.1, h * 0.3), colour = o.colour or K.colour("kick"),
        button = o.button, ref_table = o.ref_table, hover = true, shadow = true, emboss = 0.03, id = o.id, one_press = o.one_press}, nodes = {
        K.text(o.label or "K", {scale = o.scale or d.scale, colour = o.text_colour}),
    }}
end

function K.badge_slot(node, o)
    o = o or {}
    local d = K.dims()
    return K.cell(node and {node} or {}, {w = o.w or d.badge_w, h = o.h, no_maxw = true})
end

function K.row(cells, o)
    o = o or {}
    local d = K.dims()
    local gap = o.gap or d.gap
    local nodes = {}
    for _, c in ipairs(cells) do
        if c then
            if c.n == G.UIT.R then c.n = G.UIT.C end
            if #nodes > 0 and gap > 0 then nodes[#nodes + 1] = K.spacer(gap) end
            nodes[#nodes + 1] = c
        end
    end
    local mine = o.mine
    return {n = G.UIT.R, config = {align = o.align or "cm", minw = o.w, minh = o.h, padding = o.padding or 0.04, r = 0.1,
        colour = o.colour or (mine and K.colour("row_mine")) or (o.plain and G.C.CLEAR or K.colour("row")),
        outline = mine and 1 or nil, outline_colour = mine and K.colour("mine_outline") or nil, id = o.id}, nodes = nodes}
end

function K.ranked_row(o)
    o = o or {}
    local d = K.dims()
    local w = o.w or 10
    local rk = type(o.rank) == "table" and o.rank or nil
    local badge = nil
    if rawget(_G, "bom_badges") and bom_badges.rank then badge = bom_badges.rank(rk, {size = d.row_h * 0.9}) end
    local rank_text = rk and (rk.name or (bom_ranked and bom_ranked.rank_name and bom_ranked.rank_name(rk.rank, rk.tier))) or "-"
    local rp_w = d.lives_w
    local rt, rs = K.fit(rank_text, 2.1, d.small)
    local rank_w = 2.2
    local name_w = math.max(1.4, w - d.place_w - d.badge_w - rank_w - rp_w - 4 * d.gap - 0.1)
    return K.row({
        K.place_tag(o.place, {h = o.h}),
        K.badge_slot(badge, {h = o.h}),
        K.name_bar(o.name, {w = name_w, h = o.h, colour = o.mine and K.colour("name_host") or K.colour("name_light"), text_colour = K.colour("dark_text"), shadow = false}),
        K.cell({K.text(rt, {scale = rs, colour = rk and bom_ranked and bom_ranked.rank_colour and bom_ranked.rank_colour(rk.rank) or K.colour("muted")})}, {w = rank_w, h = o.h}),
        K.pill(o.rp ~= nil and (tostring(o.rp) .. " " .. L("RP")) or "-", {w = rp_w, h = o.h, colour = K.colour("status")}),
    }, {w = w, h = o.h, mine = o.mine})
end

local STRINGS_FR = {
    ["Life"] = "Vie", ["Lives"] = "Vies", ["Skip"] = "Saut", ["Skips"] = "Sauts", ["HOST"] = "HÔTE", ["RP"] = "RP",
}
local STRINGS_ES = {
    ["Life"] = "Vida", ["Lives"] = "Vidas", ["Skip"] = "Salto", ["Skips"] = "Saltos", ["HOST"] = "ANFITRIÓN", ["RP"] = "RP",
}

function K.init()
    if mod_loc_register then mod_loc_register({fr = STRINGS_FR, es = STRINGS_ES}) end
end

return K
