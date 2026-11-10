-- ============================================
-- ARCH: mp_log — Structured logging for all multiplayer modules.
-- Replaces raw print() calls with leveled, tagged output.
-- Levels: ERROR > WARN > INFO > DEBUG
-- Usage:
--   mp_log.info("BOM_CORE", "Connected successfully")
--   mp_log.debug("BOM_CORE", "Received message: %s", msg)
--   mp_log.error("BOM_ROOM", "start_run failed: %s", tostring(err))
-- ============================================

local mp_log = {}

-- Level constants (lower = more severe)
local LEVELS = {
    ERROR = 1,
    WARN  = 2,
    INFO  = 3,
    DEBUG = 4,
}

-- Current threshold — only messages at this level or below are printed
local current_level = LEVELS.INFO

-- ============================================
-- SET LOG LEVEL — Called at init or runtime
-- ============================================
function mp_log.enabled(level_name)
    local lvl = LEVELS[level_name and level_name:upper() or "INFO"]
    return lvl ~= nil and lvl <= current_level
end

function mp_log.set_level(level_name)
    local lvl = LEVELS[level_name and level_name:upper() or "INFO"]
    if lvl then
        current_level = lvl
    end
end

-- ============================================
-- CORE LOG FUNCTION
-- ============================================
local function log_msg(level_num, level_tag, tag, fmt, ...)
    if level_num > current_level then return end
    -- Build message: "[TAG] message" or "[level][TAG] message"
    local msg
    local ok, formatted = pcall(string.format, fmt, ...)
    if ok then
        msg = formatted
    else
        -- Fallback: concatenate raw args if format fails
        local parts = { tostring(fmt) }
        local args = { ... }
        for i = 1, #args do
            parts[#parts + 1] = tostring(args[i])
        end
        msg = table.concat(parts, " ")
    end

    local prefix = "[" .. tag .. "]"
    if level_tag ~= "INFO" then
        prefix = "[" .. level_tag .. "]" .. prefix
    end

    print(prefix .. " " .. msg)
end

-- ============================================
-- PUBLIC API: mp_log.error / warn / info / debug
-- Signature: mp_log.info(tag, fmt, ...)
--   tag: module name, e.g. "BOM_CORE", "BOM_MATCH"
--   fmt: format string (or plain message)
--   ...: optional format args
-- ============================================

function mp_log.error(tag, fmt, ...)
    log_msg(LEVELS.ERROR, "ERROR", tag, fmt, ...)
end

function mp_log.warn(tag, fmt, ...)
    log_msg(LEVELS.WARN, "WARN", tag, fmt, ...)
end

function mp_log.info(tag, fmt, ...)
    log_msg(LEVELS.INFO, "INFO", tag, fmt, ...)
end

function mp_log.debug(tag, fmt, ...)
    log_msg(LEVELS.DEBUG, "DEBUG", tag, fmt, ...)
end

-- ============================================
-- CONVENIENCE: Get current level name
-- ============================================
function mp_log.get_level()
    for name, num in pairs(LEVELS) do
        if num == current_level then return name end
    end
    return "UNKNOWN"
end

return mp_log
