local root = arg and arg[1] or "."
package.path = root .. "/assets/?.lua;" .. package.path

local REG = {fr = {}, es = {}}
function mod_loc(s) return s end
function mod_loc_register(t)
    for lang, entries in pairs(t or {}) do
        for k, v in pairs(entries) do REG[lang][k] = v end
    end
end
G = {FUNCS = {}, SETTINGS = {}, C = {}}
Game = {set_render_settings = function() end}
dofile(root .. "/assets/functions/art/suit_palettes.lua")

local pass, fail = 0, 0
local function check(name, ok, detail)
    if ok then pass = pass + 1 else fail = fail + 1; print("FAIL " .. name .. (detail and (" " .. tostring(detail)) or "")) end
end

local keys, hexes = {}, {}
for _, c in ipairs(SUIT_COLOURS) do
    check("colour_hex_" .. c.key, type(c.hex) == "string" and c.hex:match("^%x%x%x%x%x%x$") ~= nil, c.hex)
    check("colour_key_unique_" .. c.key, not keys[c.key])
    check("colour_hex_unique_" .. c.key, not hexes[c.hex])
    keys[c.key], hexes[c.hex] = true, true
    check("fr_colour_" .. c.name, REG.fr[c.name] ~= nil)
    check("es_colour_" .. c.name, REG.es[c.name] ~= nil)
end
check("colour_count", #SUIT_COLOURS == 36, #SUIT_COLOURS)
for _, k in ipairs({"red", "crimson", "coral", "orange", "amber", "gold", "green", "teal", "cyan", "blue", "navy", "indigo", "purple", "pink", "brown", "black", "grey"}) do
    check("old_colour_kept_" .. k, keys[k] == true)
end

local pkeys = {}
for _, p in ipairs(SUIT_PALETTES) do
    pkeys[p.key] = true
    check("fr_palette_" .. p.name, REG.fr[p.name] ~= nil)
    check("es_palette_" .. p.name, REG.es[p.name] ~= nil)
    for _, s in ipairs({"Hearts", "Diamonds", "Clubs", "Spades"}) do
        if p.colours then check("palette_colour_" .. p.key .. "_" .. s, type(p.colours[s]) == "string" and p.colours[s]:match("^%x%x%x%x%x%x$") ~= nil) end
    end
end
local function lab(h)
    local function lin(c) c = c / 255 return c <= 0.04045 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4 end
    local r, g, b = lin(tonumber(h:sub(1, 2), 16)), lin(tonumber(h:sub(3, 4), 16)), lin(tonumber(h:sub(5, 6), 16))
    local x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    local y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    local z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    local function f(v) return v > 0.008856 and v ^ (1 / 3) or 7.787 * v + 16 / 116 end
    return 116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))
end
local function de(a, b)
    local l1, a1, b1 = lab(a)
    local l2, a2, b2 = lab(b)
    return math.sqrt((l1 - l2) ^ 2 + (a1 - a2) ^ 2 + (b1 - b2) ^ 2)
end
local BASE = {Hearts = "f03464", Diamonds = "f06b3f", Clubs = "235955", Spades = "3c4368"}
local SUITS4 = {"Hearts", "Diamonds", "Clubs", "Spades"}
for _, p in ipairs(SUIT_PALETTES) do
    if p.colours and p.key ~= "four" then
        local low = math.huge
        for _, s in ipairs(SUITS4) do low = math.min(low, de(p.colours[s], BASE[s])) end
        check("preset_changes_every_suit_" .. p.key, low >= 25, string.format("%.1f", low))
    end
    if p.colours then
        local low = math.huge
        for i = 1, 4 do for j = i + 1, 4 do low = math.min(low, de(p.colours[SUITS4[i]], p.colours[SUITS4[j]])) end end
        check("preset_suits_apart_" .. p.key, low >= 28, string.format("%.1f", low))
    end
end
for i, p in ipairs(SUIT_PALETTES) do
    for j = i + 1, #SUIT_PALETTES do
        local q = SUIT_PALETTES[j]
        if p.colours and q.colours then
            local far = 0
            for _, s in ipairs(SUITS4) do far = math.max(far, de(p.colours[s], q.colours[s])) end
            check("presets_differ_" .. p.key .. "_" .. q.key, far >= 35, string.format("%.1f", far))
        end
    end
end
check("no_colourblind", not pkeys.colourblind)
check("has_default_hc_custom", pkeys.normal and pkeys.hc and pkeys.custom)
check("first_is_default", SUIT_PALETTES[1].key == "normal" and SUIT_PALETTES[1].name == "Default")
check("palette_count", #SUIT_PALETTES >= 14, #SUIT_PALETTES)

G.SETTINGS = {suit_palette = "colourblind"}
check("old_colourblind_save_falls_back", suit_palette_key() == "normal", suit_palette_key())
G.SETTINGS = {suit_palette = "colourblind", colourblind_option = true}
check("old_colourblind_with_hc", suit_palette_key() == "hc")

G.SETTINGS = {}
local applied = 0
suit_palette_apply = function() applied = applied + 1 end
for i, p in ipairs(SUIT_PALETTES) do if p.key == "custom" then suit_palette_set(i) end end
check("custom_seeded", G.SETTINGS.suit_palette == "custom" and G.SETTINGS.suit_palette_custom and G.SETTINGS.suit_palette_custom.Hearts == "red")
local c = suit_palette_colours("custom")
check("custom_colours_hex", c.Spades == "2b2b33" and c.Diamonds == "f07a1e", c.Spades)
G.SETTINGS.suit_palette_custom.Clubs = "nope"
check("custom_bad_key_falls_back", suit_palette_colours("custom").Clubs == "2c9a4b")
check("deck_row_hook", type(suit_palette_deck_row) == "function" and type(G.FUNCS.suit_custom_colours) == "function" and type(G.FUNCS.suit_colour_pick) == "function")
for _, k in ipairs({"Custom Colours", "CUSTOM COLOURS", "Suit Colours"}) do
    check("fr_" .. k, REG.fr[k] ~= nil)
    check("es_" .. k, REG.es[k] ~= nil)
end

print(string.format("suit palettes: %d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
