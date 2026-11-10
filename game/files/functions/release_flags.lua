ReleaseFlags = ReleaseFlags or {}
local R = ReleaseFlags

R.DEV_MARKER = "dev_build.txt"
R.RELEASE_MARKER = "release_build.txt"

R.TEST_ENV = {
    "SOAK_OUT", "SOAK_PREVIEW_CHECK", "SOAK_SEED", "LOADING_SHOT_DIR", "NO_NAME_PROMPT",
    "BOT_VERSUS_WINDOW", "BOT_VERSUS_STAY", "BOT_VERSUS_CODE", "BOT_TIME_SCALE", "BOT_CONFIG_DIR",
    "OVERHAUL_CRASH_URL",
    "PERF_LOG", "PERF_LOG_LUA", "PERF_LOG_TARGET_MS", "BOM_RELEASE_ART", "OVERHAUL_MINIGAMES",
}

R.OFF = {
    debug_menu = true, debug_peer = true, dev_tools = true, ai_art = true, bundled_songs = true, test_hooks = true,
}

R.AI_ATLAS = {mp_jokers = true, mp_mode_jokers = true, mp_decks = true}

function R.ai_hidden(c)
    if not R.off("ai_art") then return false end
    if c == nil then return true end
    if type(c) == "string" then c = G and G.P_CENTERS and G.P_CENTERS[c] end
    if type(c) ~= "table" then return false end
    if c.ai_art ~= nil then return c.ai_art == true end
    return c.atlas ~= nil and R.AI_ATLAS[c.atlas] == true
end

local function in_source(fs, path)
    if not fs.getInfo(path) then return false end
    if not fs.getRealDirectory or not fs.getSaveDirectory then return true end
    local real = fs.getRealDirectory(path)
    return real ~= nil and real ~= fs.getSaveDirectory()
end

function R.detect()
    local env = os.getenv and os.getenv("OVERHAUL_RELEASE")
    if env == "1" then return true end
    if env == "0" then return false end
    local fs = love and love.filesystem
    if not (fs and fs.getInfo) then return false end
    if in_source(fs, R.RELEASE_MARKER) then return true end
    return not in_source(fs, R.DEV_MARKER)
end

RELEASE_BUILD = R.detect() == true

function R.on()
    return RELEASE_BUILD == true
end

function R.off(what)
    return RELEASE_BUILD == true and R.OFF[what] == true
end

if RELEASE_BUILD then
    BOM_DEBUG_BUILD = nil
    local blocked = {}
    for _, k in ipairs(R.TEST_ENV) do blocked[k] = true end
    local getenv = os.getenv
    os.getenv = function(k)
        if blocked[k] then return nil end
        return getenv(k)
    end
end

local function noop() end

function R.apply()
    if not RELEASE_BUILD or R.applied then return end
    R.applied = true
    BOM_DEBUG_BUILD = nil
    if DebugManager then
        DebugManager.unlocked = false
        DebugManager.verify_pin = function() return false end
        DebugManager.is_enabled = function() return false end
    end
    if G and G.FUNCS then
        for _, k in ipairs({"open_debug_pin", "open_debug_menu", "open_debug_menu_overlay", "debug_try_unlock", "debug_pin_digit",
            "debug_pin_clear", "debug_pin_submit", "debug_unlock_all", "debug_add_balacoin", "debug_add_xp", "debug_ranked_max"}) do
            if G.FUNCS[k] then G.FUNCS[k] = noop end
        end
    end
    unlock_all_debug = noop
    if G and G.FUNCS then
        for k, v in pairs(G.FUNCS) do
            if type(k) == "string" and k:sub(1, 6) == "debug_" and type(v) == "function" then G.FUNCS[k] = noop end
        end
    end
    local bots = rawget(_G, "BOT") and BOT.config and BOT.config.PROVIDERS
    if type(bots) == "table" then
        for i = #bots, 1, -1 do
            if bots[i].key == "mock" then table.remove(bots, i) end
        end
    end
    create_UIBox_debug_pin = nil
    if Game and Game.start_up and not R.start_up_wrapped then
        R.start_up_wrapped = true
        local start_up = Game.start_up
        function Game:start_up(...)
            BOM_DEBUG_BUILD = nil
            local r = start_up(self, ...)
            local St = G and G.SETTINGS
            if St and not St.release_defaults then
                St.release_defaults = 1
                if G.save_settings then pcall(function() G:save_settings() end) end
            end
            return r
        end
    end
end

return R
