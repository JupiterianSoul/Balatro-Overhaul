-- ============================================
-- MULTIPLAYER GAMEMODES - Ported from BalatroMultiplayer v0.3.3
-- Defines gameplay rules for nemesis, faceoff, ascension.
-- Each gamemode specifies: PvP blind logic, banned items, lives, info.
-- No SMODS dependency - plain Lua tables.
-- ============================================

local bom_gamemodes = {}

-- ============================================
-- GAMEMODE REGISTRY
-- ============================================

bom_gamemodes.registry = {}

function bom_gamemodes.register(def)
    if not def or not def.key then
        mp_log.error("BOM_GAMEMODES", "register: missing key")
        return
    end
    bom_gamemodes.registry[def.key] = def
    mp_log.info("BOM_GAMEMODES", "registered gamemode: %s", def.key)
end

function bom_gamemodes.get(key)
    return bom_gamemodes.registry[key]
end

function bom_gamemodes.get_all_keys()
    local keys = {}
    for k, _ in pairs(bom_gamemodes.registry) do
        keys[#keys + 1] = k
    end
    table.sort(keys)
    return keys
end

-- FEATURE: Display list for lobby UI - returns { {key=..., name=...}, ... }
function bom_gamemodes.get_display_list()
    local list = {}
    for k, gm in pairs(bom_gamemodes.registry) do
        list[#list + 1] = { key = k, name = gm.display_name or k }
    end
    table.sort(list, function(a, b)
        local oa = (bom_gamemodes.registry[a.key] or {}).order or 99
        local ob = (bom_gamemodes.registry[b.key] or {}).order or 99
        if oa ~= ob then return oa < ob end
        return a.key < b.key
    end)
    return list
end

function bom_gamemodes.rule_text(key)
    local gm = bom_gamemodes.registry[key]
    return gm and gm.rule or nil
end

-- ============================================
-- GAMEMODE: NEMESIS
-- Standard competitive mode. Ante 1 is solo; Ante 2+ boss blinds are PvP.
-- 4 lives, last player standing wins.
-- (Formerly "Attrition")
-- ============================================

bom_gamemodes.register({
    key = "nemesis",
    display_name = "Rivals",
    description = "Play alongside your opponent. Starting at Ante 2, boss blinds become Rival (PvP) blinds: beat your opponent's score or lose a life!",
    rule = "Boss blinds are PvP from the chosen ante",
    order = 1,
    default_lives = 4,

    is_blind_pvp = function(self, ante, blind, settings)
        local pvp_start = (settings and settings.pvp_start_round) or 2
        if blind ~= "L" then return false end
        return ante >= pvp_start
    end,

    get_blinds_by_ante = function(self, ante, settings)
        local pvp_start = (settings and settings.pvp_start_round) or 2
        if ante >= pvp_start then
            if not (settings and settings.normal_bosses) then
                return nil, nil, "bl_mp_nemesis"
            end
        end
        return nil, nil, nil
    end,

    banned_jokers = {
        "j_mr_bones",
        "j_luchador",
        "j_matador",
        "j_chicot",
    },
    banned_consumables = {},
    banned_vouchers = {
        "v_hieroglyph",
        "v_petroglyph",
        "v_directors_cut",
        "v_retcon",
    },
    banned_enhancements = {},
    banned_tags = {
        "tag_boss",
    },
    banned_blinds = {
        "bl_wall",
        "bl_final_vessel",
    },
})

-- ============================================
-- GAMEMODE: FACEOFF
-- ALL blinds become PvP after a configurable ante threshold.
-- Higher pressure, every blind is Nemesis past the threshold.
-- (Formerly "Showdown")
-- ============================================

bom_gamemodes.register({
    key = "faceoff",
    display_name = "FaceOff",
    description = "ALL blinds become Rival (PvP) blinds from the start. Pure head-to-head every single round!",
    rule = "Every blind is PvP from the chosen ante",
    order = 2,
    default_lives = 4,

    is_blind_pvp = function(self, ante, blind, settings)
        local start_ante = (settings and settings.showdown_starting_antes) or 1
        return ante >= start_ante
    end,

    get_blinds_by_ante = function(self, ante, settings)
        local start_ante = (settings and settings.showdown_starting_antes) or 1
        if ante >= start_ante then
            return "bl_mp_nemesis", "bl_mp_nemesis", "bl_mp_nemesis"
        end
        return nil, nil, nil
    end,

    banned_jokers = {
        "j_mr_bones",
        "j_luchador",
        "j_matador",
        "j_chicot",
    },
    banned_consumables = {},
    banned_vouchers = {
        "v_hieroglyph",
        "v_petroglyph",
        "v_directors_cut",
        "v_retcon",
    },
    banned_enhancements = {},
    banned_tags = {
        "tag_boss",
    },
    banned_blinds = {
        "bl_wall",
        "bl_final_vessel",
    },
})

-- ============================================
-- GAMEMODE: ASCENSION
-- No PvP blinds. Both players play independently.
-- The player who reaches the farthest round wins.
-- If tied on round, the player with the highest score on their
-- latest blind wins. No win screen after beating a boss - the match
-- continues until one player loses.
-- ============================================

bom_gamemodes.register({
    key = "ascension",
    display_name = "Ascension",
    description = "No Rival blinds. Play independently: the player who reaches the farthest round wins! If both fail on the same round, highest score wins.",
    rule = "No PvP, lives only go on failed blinds",
    order = 3,
    default_lives = 1,

    is_blind_pvp = function(self, ante, blind, settings)
        return false  -- No PvP in Ascension
    end,

    get_blinds_by_ante = function(self, ante, settings)
        return nil, nil, nil  -- All vanilla blinds
    end,

    banned_jokers = {},
    banned_consumables = {},
    banned_vouchers = {},
    banned_enhancements = {},
    banned_tags = {},
    banned_blinds = {},
})

-- ============================================
-- HELPERS
-- ============================================

-- Get the active gamemode object for the current match
function bom_gamemodes.get_active()
    if not bom_match then return nil end
    local mode = bom_match.get_mode()
    return bom_gamemodes.registry[mode]
end

-- Check if the current blind is PvP using the active gamemode
function bom_gamemodes.is_blind_pvp(ante, blind, settings)
    local gm = bom_gamemodes.get_active()
    if not gm or not gm.is_blind_pvp then return false end
    return gm:is_blind_pvp(ante, blind, settings)
end

-- Get blind overrides for the current gamemode
function bom_gamemodes.get_blinds_by_ante(ante, settings)
    local gm = bom_gamemodes.get_active()
    if not gm or not gm.get_blinds_by_ante then return nil, nil, nil end
    return gm:get_blinds_by_ante(ante, settings)
end

-- Apply gamemode-specific banned items to G.GAME.banned_keys
function bom_gamemodes.apply_bans()
    local gm = bom_gamemodes.get_active()
    if not gm then return end
    if not G or not G.GAME or not G.GAME.banned_keys then return end

    local ban_tables = {
        "banned_jokers",
        "banned_consumables",
        "banned_vouchers",
        "banned_enhancements",
        "banned_tags",
        "banned_blinds",
    }

    for _, tbl_name in ipairs(ban_tables) do
        local bans = gm[tbl_name]
        if bans then
            for _, key in ipairs(bans) do
                G.GAME.banned_keys[key] = true
            end
        end
    end

    mp_log.info("BOM_GAMEMODES", "applied bans for gamemode: %s", gm.key)
end

-- Get default lives for the active gamemode
function bom_gamemodes.get_default_lives()
    local gm = bom_gamemodes.get_active()
    if gm and gm.default_lives then return gm.default_lives end
    return 4  -- fallback
end

return bom_gamemodes
