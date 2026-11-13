
local bom_insane_int = {}

local function _safe_number_format(n, limit)
    if number_format then
        local ok, formatted = pcall(number_format, n, limit)
        if ok and formatted then return formatted end
    end
    return tostring(n or 0)
end

function bom_insane_int.empty()
    return {
        coeffiocient = 0,
        exponent = 0,
        e_count = 0,
    }
end

function bom_insane_int.create(coeffiocient, exponent, e_count)
    return {
        coeffiocient = tonumber(coeffiocient) or 0,
        exponent = tonumber(exponent) or 0,
        e_count = tonumber(e_count) or 0,
    }
end

function bom_insane_int.from_string(value)
    if type(value) == "table" and value.coeffiocient ~= nil then
        return value
    end
    if value == nil then return bom_insane_int.empty() end

    local str = tostring(value)
    if str == "" then return bom_insane_int.empty() end

    local plain = tonumber(str)
    if plain ~= nil then
        return bom_insane_int.create(plain, 0, 0)
    end

    local e_count = 0
    while #str > 0 and string.lower(string.sub(str, 1, 1)) == "e" do
        e_count = e_count + 1
        str = string.sub(str, 2)
    end

    local coeffiocient, exponent = string.match(str, "^([%+%-]?[%d%.]+)e([%+%-]?%d+)$")
    if coeffiocient then
        return bom_insane_int.create(coeffiocient, exponent, e_count)
    end

    return bom_insane_int.create(tonumber(str) or 0, 0, e_count)
end

function bom_insane_int.to_string(value)
    local insane = bom_insane_int.from_string(value)
    local prefix = string.rep("e", insane.e_count or 0)

    if (insane.exponent or 0) == 0 then
        return prefix .. _safe_number_format(insane.coeffiocient or 0)
    end

    return prefix
        .. _safe_number_format(insane.coeffiocient or 0, 10000)
        .. "e"
        .. _safe_number_format(insane.exponent or 0)
end

function bom_insane_int.greater_than(left, right)
    local a = bom_insane_int.from_string(left)
    local b = bom_insane_int.from_string(right)

    if a.e_count ~= b.e_count then
        return (a.e_count or 0) > (b.e_count or 0)
    end
    if a.exponent ~= b.exponent then
        return (a.exponent or 0) > (b.exponent or 0)
    end
    return (a.coeffiocient or 0) > (b.coeffiocient or 0)
end

function bom_insane_int.to_number_if_safe(value)
    local insane = bom_insane_int.from_string(value)
    if (insane.e_count or 0) == 0 and (insane.exponent or 0) == 0 then
        return insane.coeffiocient or 0
    end
    return nil
end

mp_log.info("BOM_INSANE_INT", "insane int helper loaded")
return bom_insane_int
