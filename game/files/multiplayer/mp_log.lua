
local mp_log = {}

local LEVELS = {
    ERROR = 1,
    WARN  = 2,
    INFO  = 3,
    DEBUG = 4,
}

local current_level = LEVELS.INFO

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

local function log_msg(level_num, level_tag, tag, fmt, ...)
    if level_num > current_level then return end
    local msg
    local ok, formatted = pcall(string.format, fmt, ...)
    if ok then
        msg = formatted
    else
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

function mp_log.get_level()
    for name, num in pairs(LEVELS) do
        if num == current_level then return name end
    end
    return "UNKNOWN"
end

return mp_log
