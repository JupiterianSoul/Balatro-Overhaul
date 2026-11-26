local Hooks = require("overhaul.hooks")

local Loc = {merged = setmetatable({}, {__mode = "k"})}

local function is_leaf(v)
    return type(v) ~= "table" or v[1] ~= nil or next(v) == nil
end

function Loc.merge(dst, src)
    for k, v in pairs(src) do
        if is_leaf(v) or type(dst[k]) ~= "table" or is_leaf(dst[k]) then
            dst[k] = v
        else
            Loc.merge(dst[k], v)
        end
    end
    return dst
end

function Loc.language()
    local lang = G.SETTINGS and G.SETTINGS.language or "en-us"
    if G.F_ENGLISH_ONLY or not love.filesystem.getInfo("localization/" .. lang .. ".lua") then lang = "en-us" end
    if not love.filesystem.getInfo("overhaul/localization/" .. lang .. ".lua") then lang = "en-us" end
    return lang
end

local function blue_entry(t)
    local d = type(t) == "table" and t.descriptions and t.descriptions.Stake
    return d and d.stake_blue
end

local function copy_lines(lines)
    local out = {}
    for i, v in ipairs(type(lines) == "table" and lines or {}) do out[i] = v end
    return out
end

function Loc.apply(t)
    if type(t) ~= "table" or Loc.merged[t] then return end
    Loc.merged[t] = true
    local vb = blue_entry(t)
    Loc.vanilla_blue = vb and copy_lines(vb.text) or Loc.vanilla_blue
    local chunk = love.filesystem.load("overhaul/localization/" .. Loc.language() .. ".lua")
    local ok, ours = pcall(chunk)
    if ok and type(ours) == "table" then Loc.merge(t, ours) end
    local rb = blue_entry(t)
    Loc.rework_blue = rb and copy_lines(rb.text) or Loc.rework_blue
end

function Loc.reworks()
    local e = blue_entry(G and G.localization)
    if not (e and Loc.vanilla_blue and Loc.rework_blue) then return end
    local off = G.SETTINGS and G.SETTINGS.rework_blue_stake == false
    local g = G.GAME
    if G.STAGE == G.STAGES.RUN and g and (g.stake or 0) >= 5 and g.modifiers then off = not g.modifiers.ante_shop_tax end
    e.text = copy_lines(off and Loc.vanilla_blue or Loc.rework_blue)
    local parse = rawget(_G, "loc_parse_string")
    if e.text_parsed and parse then
        e.text_parsed = {}
        for _, line in ipairs(e.text) do e.text_parsed[#e.text_parsed + 1] = parse(line) end
    end
end

local function reworks_after(...)
    pcall(Loc.reworks)
    return ...
end

Hooks.wrap(_G, "init_localization", function(orig) return function(...)
    Loc.apply(G.localization)
    return reworks_after(orig(...))
end end, {id = "overhaul.localization"})

Hooks.wrap("Game", "start_run", function(orig) return function(...)
    return reworks_after(orig(...))
end end, {id = "overhaul.localization.start_run"})

Hooks.wrap("Game", "main_menu", function(orig) return function(...)
    return reworks_after(orig(...))
end end, {id = "overhaul.localization.main_menu"})

OverhaulLoc = Loc

return Loc
