local Regex = {}
Regex.__index = Regex

local byte, sub = string.byte, string.sub

local function decode(s, i)
    local c = byte(s, i)
    if not c then return nil, i end
    if c < 0x80 then return c, i + 1 end
    if c >= 0xF0 then
        local c2, c3, c4 = byte(s, i + 1, i + 3)
        if c4 then return (c - 0xF0) * 0x40000 + (c2 - 0x80) * 0x1000 + (c3 - 0x80) * 0x40 + (c4 - 0x80), i + 4 end
    elseif c >= 0xE0 then
        local c2, c3 = byte(s, i + 1, i + 2)
        if c3 then return (c - 0xE0) * 0x1000 + (c2 - 0x80) * 0x40 + (c3 - 0x80), i + 3 end
    elseif c >= 0xC0 then
        local c2 = byte(s, i + 1)
        if c2 then return (c - 0xC0) * 0x40 + (c2 - 0x80), i + 2 end
    end
    return c, i + 1
end

local function is_space(cp)
    return cp == 32 or (cp >= 9 and cp <= 13) or cp == 0x85 or cp == 0xA0 or cp == 0x1680
        or (cp >= 0x2000 and cp <= 0x200A) or cp == 0x2028 or cp == 0x2029 or cp == 0x202F or cp == 0x205F or cp == 0x3000
end
local function is_digit(cp) return cp >= 48 and cp <= 57 end
local function is_word(cp)
    return (cp >= 48 and cp <= 57) or (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122) or cp == 95
        or (cp >= 0xC0 and not is_space(cp))
end
local function is_word_byte(b)
    return b and ((b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95 or b >= 0x80)
end

local posix = {
    alpha = function(c) return (c >= 65 and c <= 90) or (c >= 97 and c <= 122) end,
    digit = is_digit,
    alnum = function(c) return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) end,
    space = function(c) return c == 32 or (c >= 9 and c <= 13) end,
    upper = function(c) return c >= 65 and c <= 90 end,
    lower = function(c) return c >= 97 and c <= 122 end,
    word = function(c) return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95 end,
    punct = function(c) return (c >= 33 and c <= 47) or (c >= 58 and c <= 64) or (c >= 91 and c <= 96) or (c >= 123 and c <= 126) end,
    xdigit = function(c) return (c >= 48 and c <= 57) or (c >= 65 and c <= 70) or (c >= 97 and c <= 102) end,
}

local function parse(pattern, flags)
    local p, n = 1, #pattern
    local ngroups = 0
    local names = {}
    local ignore_ws = flags.ignore_whitespace
    local case_i = flags.case_insensitive

    local function fail(msg) error("regex: " .. msg .. " at " .. p .. " in " .. pattern, 0) end

    local function skip_verbose()
        if not ignore_ws then return end
        while p <= n do
            local c = sub(pattern, p, p)
            if c == " " or c == "\t" or c == "\n" or c == "\r" then
                p = p + 1
            elseif c == "#" then
                local e = pattern:find("\n", p, true)
                p = e and e + 1 or n + 1
            else
                break
            end
        end
    end

    local function parse_escape_cp()
        local c = sub(pattern, p, p)
        p = p + 1
        if c == "n" then return 10 elseif c == "t" then return 9 elseif c == "r" then return 13
        elseif c == "f" then return 12 elseif c == "v" then return 11 elseif c == "a" then return 7 elseif c == "0" then return 0
        elseif c == "x" then
            if sub(pattern, p, p) == "{" then
                local e = pattern:find("}", p, true)
                local v = tonumber(sub(pattern, p + 1, e - 1), 16)
                p = e + 1
                return v
            end
            local v = tonumber(sub(pattern, p, p + 1), 16)
            p = p + 2
            return v
        elseif c == "u" or c == "U" then
            if sub(pattern, p, p) == "{" then
                local e = pattern:find("}", p, true)
                local v = tonumber(sub(pattern, p + 1, e - 1), 16)
                p = e + 1
                return v
            end
            local len = c == "u" and 4 or 8
            local v = tonumber(sub(pattern, p, p + len - 1), 16)
            p = p + len
            return v
        end
        local cp, np = decode(pattern, p - 1)
        p = np
        return cp
    end

    local function class_escape(c)
        if c == "s" then return is_space, false elseif c == "S" then return is_space, true
        elseif c == "d" then return is_digit, false elseif c == "D" then return is_digit, true
        elseif c == "w" then return is_word, false elseif c == "W" then return is_word, true end
    end

    local function parse_class()
        local negate = false
        if sub(pattern, p, p) == "^" then negate = true; p = p + 1 end
        local items = {}
        local first = true
        while true do
            if p > n then fail("unterminated class") end
            local c = sub(pattern, p, p)
            if c == "]" and not first then p = p + 1; break end
            first = false
            if c == "[" and sub(pattern, p, p + 1) == "[:" then
                local e = pattern:find(":]", p + 2, true)
                local name = sub(pattern, p + 2, e - 1)
                local neg = false
                if name:sub(1, 1) == "^" then neg = true; name = name:sub(2) end
                local f = posix[name] or fail("unknown posix class " .. name)
                items[#items + 1] = {fn = f, neg = neg}
                p = e + 2
            elseif c == "[" then
                p = p + 1
                local inner = parse_class()
                items[#items + 1] = {fn = inner, neg = false}
            else
                local lo
                if c == "\\" then
                    p = p + 1
                    local e = sub(pattern, p, p)
                    local f, neg = class_escape(e)
                    if f then
                        p = p + 1
                        items[#items + 1] = {fn = f, neg = neg}
                    else
                        lo = parse_escape_cp()
                    end
                else
                    lo, p = decode(pattern, p)
                end
                if lo then
                    if sub(pattern, p, p) == "-" and sub(pattern, p + 1, p + 1) ~= "]" and p + 1 <= n then
                        p = p + 1
                        local hi
                        if sub(pattern, p, p) == "\\" then p = p + 1; hi = parse_escape_cp() else hi, p = decode(pattern, p) end
                        items[#items + 1] = {lo = lo, hi = hi}
                    else
                        items[#items + 1] = {lo = lo, hi = lo}
                    end
                end
            end
        end
        local function test(cp)
            local hit = false
            for i = 1, #items do
                local it = items[i]
                if it.fn then
                    local r = it.fn(cp)
                    if it.neg then r = not r end
                    if r then hit = true; break end
                else
                    if cp >= it.lo and cp <= it.hi then hit = true; break end
                    if case_i then
                        local alt = (cp >= 65 and cp <= 90) and cp + 32 or ((cp >= 97 and cp <= 122) and cp - 32 or nil)
                        if alt and alt >= it.lo and alt <= it.hi then hit = true; break end
                    end
                end
            end
            if negate then return not hit end
            return hit
        end
        return test
    end

    local parse_alt

    local function parse_atom()
        local c = sub(pattern, p, p)
        if c == "(" then
            p = p + 1
            local node
            if sub(pattern, p, p) == "?" then
                p = p + 1
                local c2 = sub(pattern, p, p)
                if c2 == ":" then
                    p = p + 1
                    node = {type = "group", body = parse_alt()}
                elseif c2 == "<" or c2 == "P" then
                    if c2 == "P" then p = p + 1 end
                    p = p + 1
                    local e = pattern:find(">", p, true) or fail("bad group name")
                    local name = sub(pattern, p, e - 1)
                    p = e + 1
                    ngroups = ngroups + 1
                    local idx = ngroups
                    names[name] = idx
                    node = {type = "group", index = idx, body = parse_alt()}
                else
                    local fl = pattern:match("^[%-imsxU]+", p) or fail("unsupported group")
                    p = p + #fl
                    local on = true
                    for ch in fl:gmatch(".") do
                        if ch == "-" then on = false
                        elseif ch == "x" then ignore_ws = on
                        elseif ch == "i" then case_i = on
                        elseif ch == "s" then flags.dot_nl = on
                        elseif ch == "m" then flags.multi_line = on end
                    end
                    if sub(pattern, p, p) == ")" then
                        p = p + 1
                        return {type = "empty"}
                    elseif sub(pattern, p, p) == ":" then
                        p = p + 1
                        node = {type = "group", body = parse_alt()}
                    else
                        fail("bad flag group")
                    end
                end
            else
                ngroups = ngroups + 1
                local idx = ngroups
                node = {type = "group", index = idx, body = parse_alt()}
            end
            if sub(pattern, p, p) ~= ")" then fail("missing )") end
            p = p + 1
            return node
        elseif c == "[" then
            p = p + 1
            return {type = "set", test = parse_class()}
        elseif c == "." then
            p = p + 1
            return {type = flags.dot_nl and "anynl" or "any"}
        elseif c == "^" then
            p = p + 1
            return {type = flags.multi_line and "bol" or "bot"}
        elseif c == "$" then
            p = p + 1
            return {type = flags.multi_line and "eol" or "eot"}
        elseif c == "\\" then
            p = p + 1
            local e = sub(pattern, p, p)
            local f, neg = class_escape(e)
            if f then
                p = p + 1
                return {type = "set", test = neg and function(cp) return not f(cp) end or f}
            end
            if e == "b" then p = p + 1; return {type = "wordb"} end
            if e == "B" then p = p + 1; return {type = "nwordb"} end
            if e == "A" then p = p + 1; return {type = "bot"} end
            if e == "z" then p = p + 1; return {type = "eot"} end
            local cp = parse_escape_cp()
            return {type = "char", cp = cp}
        end
        local cp
        cp, p = decode(pattern, p)
        return {type = "char", cp = cp}
    end

    local function parse_seq()
        local items = {}
        while true do
            skip_verbose()
            if p > n then break end
            local c = sub(pattern, p, p)
            if c == "|" or c == ")" then break end
            local atom = parse_atom()
            skip_verbose()
            local q = sub(pattern, p, p)
            local mn, mx
            if q == "*" then mn, mx = 0, math.huge; p = p + 1
            elseif q == "+" then mn, mx = 1, math.huge; p = p + 1
            elseif q == "?" then mn, mx = 0, 1; p = p + 1
            elseif q == "{" and pattern:match("^{%s*%d*%s*,?%s*%d*%s*}", p) then
                local body = pattern:match("^{(.-)}", p)
                p = p + #body + 2
                local a, comma, b = body:match("^%s*(%d*)%s*(,?)%s*(%d*)%s*$")
                mn = tonumber(a) or 0
                if comma == "" then mx = mn else mx = tonumber(b) or math.huge end
            end
            if mn then
                local greedy = true
                if sub(pattern, p, p) == "?" then greedy = false; p = p + 1 end
                atom = {type = "rep", body = atom, min = mn, max = mx, greedy = greedy}
            end
            if case_i and atom.type == "char" then atom.ci = true end
            items[#items + 1] = atom
        end
        return {type = "seq", items = items}
    end

    parse_alt = function()
        local branches = {parse_seq()}
        while sub(pattern, p, p) == "|" do
            p = p + 1
            branches[#branches + 1] = parse_seq()
        end
        if #branches == 1 then return branches[1] end
        return {type = "alt", branches = branches}
    end

    local ast = parse_alt()
    if p <= n then fail("unexpected )") end
    return ast, ngroups, names
end

local function single_test(node)
    local t = node.type
    if t == "char" then
        local want = node.cp
        if node.ci then
            local alt = (want >= 65 and want <= 90) and want + 32 or ((want >= 97 and want <= 122) and want - 32 or want)
            return function(cp) return cp == want or cp == alt end
        end
        return function(cp) return cp == want end
    elseif t == "set" then
        return node.test
    elseif t == "any" then
        return function(cp) return cp ~= 10 and cp ~= 13 end
    elseif t == "anynl" then
        return function() return true end
    elseif t == "seq" then
        if #node.items == 1 then return single_test(node.items[1]) end
    elseif t == "group" then
        if not node.index then return single_test(node.body) end
    elseif t == "alt" then
        local tests = {}
        for i, b in ipairs(node.branches) do
            tests[i] = single_test(b)
            if not tests[i] then return nil end
        end
        return function(cp)
            for j = 1, #tests do
                if tests[j](cp) then return true end
            end
            return false
        end
    end
end

local function compile(node, k)
    local t = node.type
    if t == "seq" then
        local m = k
        for i = #node.items, 1, -1 do m = compile(node.items[i], m) end
        return m
    elseif t == "empty" then
        return k
    elseif t == "alt" then
        local ms = {}
        for i, b in ipairs(node.branches) do ms[i] = compile(b, k) end
        return function(s, i, caps)
            for j = 1, #ms do
                local r = ms[j](s, i, caps)
                if r then return r end
            end
            return nil
        end
    elseif t == "group" then
        if not node.index then return compile(node.body, k) end
        local si, ei = node.index * 2 - 1, node.index * 2
        local close = function(s, i, caps)
            local old = caps[ei]
            caps[ei] = i
            local r = k(s, i, caps)
            if not r then caps[ei] = old end
            return r
        end
        local body = compile(node.body, close)
        return function(s, i, caps)
            local olds, olde = caps[si], caps[ei]
            caps[si] = i
            local r = body(s, i, caps)
            if not r then caps[si] = olds; caps[ei] = olde end
            return r
        end
    elseif t == "bol" then
        return function(s, i, caps)
            local pb = byte(s, i - 1)
            if i == 1 or (pb == 10) or (pb == 13 and byte(s, i) ~= 10) then return k(s, i, caps) end
            return nil
        end
    elseif t == "eol" then
        return function(s, i, caps)
            local b = byte(s, i)
            if b == nil or b == 13 or (b == 10 and byte(s, i - 1) ~= 13) then return k(s, i, caps) end
            return nil
        end
    elseif t == "bot" then
        return function(s, i, caps) if i == 1 then return k(s, i, caps) end return nil end
    elseif t == "eot" then
        return function(s, i, caps) if i == #s + 1 then return k(s, i, caps) end return nil end
    elseif t == "wordb" or t == "nwordb" then
        local want = t == "wordb"
        return function(s, i, caps)
            local a = is_word_byte(byte(s, i - 1)) and true or false
            local b = is_word_byte(byte(s, i)) and true or false
            if (a ~= b) == want then return k(s, i, caps) end
            return nil
        end
    elseif t == "rep" then
        local mn, mx, greedy = node.min, node.max, node.greedy
        local test = single_test(node.body)
        if test then
            return function(s, i, caps)
                local positions = {i}
                local pos, count = i, 0
                local limit = greedy and mx or mn
                while count < limit do
                    local cp, np = decode(s, pos)
                    if not cp or not test(cp) then break end
                    pos = np
                    count = count + 1
                    positions[count + 1] = pos
                end
                if count < mn then return nil end
                if greedy then
                    for c = count, mn, -1 do
                        local r = k(s, positions[c + 1], caps)
                        if r then return r end
                    end
                    return nil
                end
                while true do
                    local r = k(s, pos, caps)
                    if r then return r end
                    if count >= mx then return nil end
                    local cp, np = decode(s, pos)
                    if not cp or not test(cp) then return nil end
                    pos = np
                    count = count + 1
                end
            end
        end
        local body_node = node.body
        local function attempt(count, s, i, caps)
            local function after_body(s2, j, caps2)
                if j == i and count + 1 > mn then return nil end
                return attempt(count + 1, s2, j, caps2)
            end
            if greedy then
                if count < mx then
                    local r = compile(body_node, after_body)(s, i, caps)
                    if r then return r end
                end
                if count >= mn then return k(s, i, caps) end
                return nil
            else
                if count >= mn then
                    local r = k(s, i, caps)
                    if r then return r end
                end
                if count < mx then return compile(body_node, after_body)(s, i, caps) end
                return nil
            end
        end
        return function(s, i, caps) return attempt(0, s, i, caps) end
    else
        local test = single_test(node)
        return function(s, i, caps)
            local cp, np = decode(s, i)
            if cp and test(cp) then return k(s, np, caps) end
            return nil
        end
    end
end

local function literal_prefix(ast)
    local node = ast
    while node and node.type == "group" do node = node.body end
    if not node or node.type ~= "seq" then
        if node and node.type == "char" and not node.ci then return node.cp < 128 and string.char(node.cp) or nil end
        return nil
    end
    local buf = {}
    for _, it in ipairs(node.items) do
        if it.type == "char" and not it.ci and it.cp < 128 then buf[#buf + 1] = string.char(it.cp) else break end
    end
    if #buf == 0 then return nil end
    return table.concat(buf)
end

local function first_info(node)
    local t = node.type
    if t == "char" or t == "set" or t == "any" or t == "anynl" then
        return {single_test(node)}, false
    elseif t == "seq" then
        local tests = {}
        for _, it in ipairs(node.items) do
            local ft, nullable = first_info(it)
            if ft == nil then return nil, true end
            for _, f in ipairs(ft) do tests[#tests + 1] = f end
            if not nullable then return tests, false end
        end
        return tests, true
    elseif t == "group" then
        return first_info(node.body)
    elseif t == "alt" then
        local tests, any_null = {}, false
        for _, br in ipairs(node.branches) do
            local ft, nullable = first_info(br)
            if ft == nil then return nil, true end
            for _, f in ipairs(ft) do tests[#tests + 1] = f end
            if nullable then any_null = true end
        end
        return tests, any_null
    elseif t == "rep" then
        local ft, nullable = first_info(node.body)
        if ft == nil then return nil, true end
        return ft, nullable or node.min == 0
    elseif t == "empty" or t == "bol" or t == "eol" or t == "wordb" or t == "nwordb" or t == "bot" or t == "eot" then
        return {}, true
    end
    return nil, true
end

local function required_literal(ast)
    local best = ""
    local function walk(node)
        if node.type == "group" then return walk(node.body) end
        if node.type ~= "seq" then return end
        local run = {}
        local function flush()
            local s = table.concat(run)
            if #s > #best then best = s end
            run = {}
        end
        for _, it in ipairs(node.items) do
            if it.type == "char" and not it.ci and it.cp < 128 then
                run[#run + 1] = string.char(it.cp)
            else
                flush()
                if it.type == "group" then walk(it.body)
                elseif it.type == "rep" and it.min >= 1 then walk(it.body) end
            end
        end
        flush()
    end
    walk(ast)
    return best ~= "" and best or nil
end

local function can_newline(node)
    local t = node.type
    if t == "char" then return node.cp == 10 or node.cp == 13 end
    if t == "set" then return node.test(10) or node.test(13) end
    if t == "any" then return false end
    if t == "anynl" then return true end
    if t == "group" or t == "rep" then return can_newline(node.body) end
    if t == "seq" then
        for _, it in ipairs(node.items) do if can_newline(it) then return true end end
        return false
    end
    if t == "alt" then
        for _, br in ipairs(node.branches) do if can_newline(br) then return true end end
        return false
    end
    return false
end

local function line_literal(ast)
    if ast.type ~= "seq" then return nil end
    local best, best_start = nil, nil
    local i, items = 1, ast.items
    while i <= #items do
        if items[i].type == "char" and not items[i].ci and items[i].cp < 128 and items[i].cp ~= 10 and items[i].cp ~= 13 then
            local j = i
            local buf = {}
            while j <= #items and items[j].type == "char" and not items[j].ci and items[j].cp < 128 and items[j].cp ~= 10 and items[j].cp ~= 13 do
                buf[#buf + 1] = string.char(items[j].cp)
                j = j + 1
            end
            local lit = table.concat(buf)
            if not best or #lit > #best then best, best_start = lit, i end
            i = j
        else
            i = i + 1
        end
    end
    if not best or #best < 3 then return nil end
    for k = 1, best_start - 1 do
        if can_newline(items[k]) then return nil end
    end
    return best
end

function Regex.new(pattern, flags)
    flags = flags or {}
    local f = {multi_line = flags.multi_line, ignore_whitespace = flags.ignore_whitespace, case_insensitive = flags.case_insensitive, dot_nl = flags.dot_nl}
    local ast, ngroups, names = parse(pattern, f)
    local matcher = compile(ast, function(_, i) return i end)
    local ft, nullable = first_info(ast)
    local first = (ft and not nullable and #ft > 0) and ft or nil
    return setmetatable({pattern = pattern, matcher = matcher, ngroups = ngroups, names = names, prefix = literal_prefix(ast), first = first, must = required_literal(ast), line_lit = line_literal(ast)}, Regex)
end

local function build_groups(self, i, e, caps)
    local groups = {[0] = {i, e}}
    for g = 1, self.ngroups do
        local a, b = caps[g * 2 - 1], caps[g * 2]
        if a and b then groups[g] = {a, b} end
    end
    return groups
end

function Regex:match_at(s, start)
    local lit = self.line_lit
    if lit then
        local next_start = start
        local search = start
        while true do
            local L = s:find(lit, search, true)
            if not L then return nil end
            local ls = L
            while ls > 1 do
                local b = byte(s, ls - 1)
                if b == 10 or b == 13 then break end
                ls = ls - 1
            end
            local i = math.max(next_start, ls)
            while i <= L do
                local caps = {}
                local e = self.matcher(s, i, caps)
                if e then return build_groups(self, i, e, caps) end
                local _, np = decode(s, i)
                i = np
            end
            next_start = L + 1
            search = L + 1
        end
    end
    local n = #s
    local i = start
    local prefix = self.prefix
    local first = self.first
    local nfirst = first and #first or 0
    if self.must and not s:find(self.must, i, true) then return nil end
    while i <= n + 1 do
        if prefix then
            local f = s:find(prefix, i, true)
            if not f then return nil end
            i = f
        end
        local try = true
        if first then
            local cp = decode(s, i)
            try = false
            if cp then
                for j = 1, nfirst do
                    if first[j](cp) then try = true; break end
                end
            end
        end
        local caps = {}
        local e = try and self.matcher(s, i, caps)
        if e then
            local groups = {[0] = {i, e}}
            for g = 1, self.ngroups do
                local a, b = caps[g * 2 - 1], caps[g * 2]
                if a and b then groups[g] = {a, b} end
            end
            return groups
        end
        if i > n then break end
        local _, np = decode(s, i)
        i = np
    end
    return nil
end

function Regex:captures_all(s)
    local out = {}
    local pos = 1
    local last_end = nil
    while pos <= #s + 1 do
        local g = self:match_at(s, pos)
        if not g then break end
        local a, b = g[0][1], g[0][2]
        if a == b and last_end == a then
            if a > #s then break end
            local _, np = decode(s, a)
            pos = np
        else
            out[#out + 1] = g
            last_end = b
            if b == a then
                if a > #s then break end
                local _, np = decode(s, a)
                pos = np
            else
                pos = b
            end
        end
    end
    return out
end

function Regex:group_index(name)
    if name:match("^%d+$") then return tonumber(name) end
    return self.names[name]
end

function Regex:interpolate(template, s, groups)
    local out = {}
    local i, n = 1, #template
    while i <= n do
        local d = template:find("$", i, true)
        if not d then out[#out + 1] = template:sub(i); break end
        out[#out + 1] = template:sub(i, d - 1)
        local nx = template:sub(d + 1, d + 1)
        if nx == "$" then
            out[#out + 1] = "$"
            i = d + 2
        else
            local name, after
            if nx == "{" then
                local e = template:find("}", d + 2, true)
                if e then name = template:sub(d + 2, e - 1); after = e + 1 end
            else
                name = template:match("^[%w_]+", d + 1)
                if name then after = d + 1 + #name end
            end
            if not name or name == "" then
                out[#out + 1] = "$"
                i = d + 1
            else
                local idx = self:group_index(name)
                local g = idx and groups[idx]
                if g then out[#out + 1] = s:sub(g[1], g[2] - 1) end
                i = after
            end
        end
    end
    return table.concat(out)
end

return Regex
