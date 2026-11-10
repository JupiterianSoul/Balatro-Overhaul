local toml = {}

local function utf8_char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40) end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40, 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

function toml.parse(src)
    src = src:gsub("\r\n", "\n")
    if src:sub(1, 3) == "\239\187\191" then src = src:sub(4) end
    local pos, len = 1, #src
    local root = {}
    local current = root

    local function err(msg)
        local line = 1
        for _ in src:sub(1, pos):gmatch("\n") do line = line + 1 end
        error("toml line " .. line .. ": " .. msg, 0)
    end

    local function peek(n) return src:sub(pos, pos + (n or 1) - 1) end

    local function skip_ws()
        while pos <= len do
            local c = src:sub(pos, pos)
            if c == " " or c == "\t" then pos = pos + 1 else break end
        end
    end

    local function skip_ws_nl_comments()
        while pos <= len do
            local c = src:sub(pos, pos)
            if c == " " or c == "\t" or c == "\n" then
                pos = pos + 1
            elseif c == "#" then
                local e = src:find("\n", pos, true)
                pos = e and e or len + 1
            else
                break
            end
        end
    end

    local function read_escape()
        local c = src:sub(pos, pos)
        pos = pos + 1
        if c == "n" then return "\n" elseif c == "t" then return "\t" elseif c == "r" then return "\r"
        elseif c == "\\" then return "\\" elseif c == '"' then return '"' elseif c == "b" then return "\b"
        elseif c == "f" then return "\f" elseif c == "e" then return "\27"
        elseif c == "u" then
            local h = src:sub(pos, pos + 3); pos = pos + 4
            return utf8_char(tonumber(h, 16))
        elseif c == "U" then
            local h = src:sub(pos, pos + 7); pos = pos + 8
            return utf8_char(tonumber(h, 16))
        end
        err("bad escape \\" .. c)
    end

    local function parse_string()
        if peek(3) == '"""' then
            pos = pos + 3
            if src:sub(pos, pos) == "\n" then pos = pos + 1 end
            local buf = {}
            while true do
                if pos > len then err("unterminated string") end
                if peek(3) == '"""' then
                    local extra = 0
                    while src:sub(pos + 3 + extra, pos + 3 + extra) == '"' and extra < 2 do extra = extra + 1 end
                    buf[#buf + 1] = string.rep('"', extra)
                    pos = pos + 3 + extra
                    return table.concat(buf)
                end
                local c = src:sub(pos, pos)
                if c == "\\" then
                    pos = pos + 1
                    local save = pos
                    while src:sub(pos, pos):match("[ \t]") do pos = pos + 1 end
                    if src:sub(pos, pos) == "\n" then
                        while src:sub(pos, pos):match("[ \t\n]") do pos = pos + 1 end
                    else
                        pos = save
                        buf[#buf + 1] = read_escape()
                    end
                else
                    buf[#buf + 1] = c
                    pos = pos + 1
                end
            end
        elseif peek(3) == "'''" then
            pos = pos + 3
            if src:sub(pos, pos) == "\n" then pos = pos + 1 end
            local e = src:find("'''", pos, true)
            if not e then err("unterminated literal string") end
            local extra = 0
            while src:sub(e + 3 + extra, e + 3 + extra) == "'" and extra < 2 do extra = extra + 1 end
            local s = src:sub(pos, e - 1 + extra)
            pos = e + 3 + extra
            return s
        elseif peek() == '"' then
            pos = pos + 1
            local buf = {}
            while true do
                local c = src:sub(pos, pos)
                if c == "" or c == "\n" then err("unterminated string") end
                if c == '"' then pos = pos + 1; return table.concat(buf) end
                if c == "\\" then
                    pos = pos + 1
                    buf[#buf + 1] = read_escape()
                else
                    buf[#buf + 1] = c
                    pos = pos + 1
                end
            end
        elseif peek() == "'" then
            local e = src:find("'", pos + 1, true)
            if not e then err("unterminated literal string") end
            local s = src:sub(pos + 1, e - 1)
            pos = e + 1
            return s
        end
        err("expected string")
    end

    local parse_value

    local function parse_array()
        pos = pos + 1
        local arr = {}
        while true do
            skip_ws_nl_comments()
            if peek() == "]" then pos = pos + 1; return arr end
            arr[#arr + 1] = parse_value()
            skip_ws_nl_comments()
            if peek() == "," then pos = pos + 1
            elseif peek() == "]" then pos = pos + 1; return arr
            else err("expected , or ] in array") end
        end
    end

    local parse_key

    local function parse_inline_table()
        pos = pos + 1
        local t = {}
        skip_ws()
        if peek() == "}" then pos = pos + 1; return t end
        while true do
            skip_ws()
            local keys = parse_key()
            skip_ws()
            if peek() ~= "=" then err("expected =") end
            pos = pos + 1
            skip_ws()
            local tgt = t
            for i = 1, #keys - 1 do
                tgt[keys[i]] = tgt[keys[i]] or {}
                tgt = tgt[keys[i]]
            end
            tgt[keys[#keys]] = parse_value()
            skip_ws()
            if peek() == "," then pos = pos + 1
            elseif peek() == "}" then pos = pos + 1; return t
            else err("expected , or } in inline table") end
        end
    end

    parse_value = function()
        local c = peek()
        if c == '"' or c == "'" then return parse_string() end
        if c == "[" then return parse_array() end
        if c == "{" then return parse_inline_table() end
        if src:sub(pos, pos + 3) == "true" then pos = pos + 4; return true end
        if src:sub(pos, pos + 4) == "false" then pos = pos + 5; return false end
        local num = src:match("^[%+%-]?[%d_]+%.?[%d_]*[eE]?[%+%-]?%d*", pos)
        if num and num ~= "" then
            pos = pos + #num
            local n = tonumber((num:gsub("_", "")))
            if n == nil then err("bad number " .. num) end
            return n
        end
        local special = src:match("^[%+%-]?inf", pos) or src:match("^[%+%-]?nan", pos)
        if special then
            pos = pos + #special
            if special:find("nan") then return 0 / 0 end
            return special:sub(1, 1) == "-" and -math.huge or math.huge
        end
        err("unexpected value")
    end

    parse_key = function()
        local keys = {}
        while true do
            skip_ws()
            local c = peek()
            local k
            if c == '"' or c == "'" then
                k = parse_string()
            else
                k = src:match("^[%w_%-]+", pos)
                if not k then err("expected key") end
                pos = pos + #k
            end
            keys[#keys + 1] = k
            skip_ws()
            if peek() == "." then pos = pos + 1 else break end
        end
        return keys
    end

    while true do
        skip_ws_nl_comments()
        if pos > len then break end
        if peek(2) == "[[" then
            pos = pos + 2
            local keys = parse_key()
            skip_ws()
            if peek(2) ~= "]]" then err("expected ]]") end
            pos = pos + 2
            local t = root
            for i = 1, #keys - 1 do
                local v = t[keys[i]]
                if v == nil then v = {}; t[keys[i]] = v end
                if v[1] ~= nil and type(v[1]) == "table" and v.__array then v = v[#v] end
                t = v
            end
            local last = keys[#keys]
            if t[last] == nil then t[last] = {__array = true} end
            local arr = t[last]
            local entry = {}
            arr[#arr + 1] = entry
            current = entry
        elseif peek() == "[" then
            pos = pos + 1
            local keys = parse_key()
            skip_ws()
            if peek() ~= "]" then err("expected ]") end
            pos = pos + 1
            local t = root
            for i = 1, #keys do
                local v = t[keys[i]]
                if v == nil then v = {}; t[keys[i]] = v end
                if v.__array then v = v[#v] end
                t = v
            end
            current = t
        else
            local keys = parse_key()
            skip_ws()
            if peek() ~= "=" then err("expected =") end
            pos = pos + 1
            skip_ws()
            local t = current
            for i = 1, #keys - 1 do
                t[keys[i]] = t[keys[i]] or {}
                t = t[keys[i]]
            end
            t[keys[#keys]] = parse_value()
            skip_ws()
            if peek() == "#" then
                local e = src:find("\n", pos, true)
                pos = e and e or len + 1
            elseif pos <= len and peek() ~= "\n" then
                err("unexpected text after value")
            end
        end
    end

    local function strip(t)
        if type(t) ~= "table" then return t end
        t.__array = nil
        for _, v in pairs(t) do strip(v) end
        return t
    end
    return strip(root)
end

return toml
