local N = {}

N.DISCORD = "https://discord.gg/uu4pu8NySP"
N.GITHUB = "https://github.com/JupiterianSoul/Balatro-Overhaul"
N.FILE = "files/CHANGELOG.md"

function N.safe_url(url)
    return type(url) == "string" and url:match("^https://[%w%-%.]+%.%a+/[^%s]*$") ~= nil
end

function N.open(url)
    if not N.safe_url(url) then
        return false
    end
    local ok, res = pcall(love.system.openURL, url)
    return ok and res ~= false
end

function N.vnum(s)
    s = tostring(s or "")
    return s:match("^%s*(%d+[%d%.]*%d)") or s:match("^%s*(%d+)") or s
end

function N.parse(text, fallback_title)
    local out = {groups = {}}
    local by, last = {}, nil
    local function add(title, line)
        title = title or fallback_title or ""
        local g = by[title]
        if not g then
            g = {title = title, lines = {}}
            by[title] = g
            out.groups[#out.groups + 1] = g
        end
        g.lines[#g.lines + 1] = line
        last = {g = g, i = #g.lines}
    end
    for raw in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
        local l = raw:gsub("\r$", "")
        local head = l:match("^#%s+(.+)$")
        local item = l:match("^%s*[%+%-]%s+(.+)$")
        if head then
            out.title = head
            last = nil
        elseif item then
            item = item:gsub("^{[%w_]+}%s*", "")
            local name, body = item:match("^%[(.-)%]%s*(.+)$")
            add(name, body or item)
        elseif l:match("%S") then
            local more = l:gsub("^%s+", "")
            if last and l:match("^%s") then
                last.g.lines[last.i] = last.g.lines[last.i] .. " " .. more
            else
                add(nil, more)
            end
        end
    end
    return out
end

function N.md_block(md, version, lang)
    local want = N.vnum(version)
    local cur, block, title, en_block, en_title
    local in_ver = false
    for raw in (tostring(md or "") .. "\n"):gmatch("([^\n]*)\n") do
        local l = raw:gsub("\r$", "")
        local head = l:match("^##%s+([^#].*)$")
        local sub, t = l:match("^###%s+(%a%a)%s*(.-)%s*$")
        if head then
            if in_ver then
                break
            end
            in_ver = N.vnum(head:match("^(.-)%s*|") or head) == want
            cur = nil
        elseif in_ver and sub then
            cur = sub:lower()
            if cur == lang then
                block, title = {}, t
            elseif cur == "en" then
                en_block, en_title = {}, t
            end
        elseif in_ver and cur then
            local target = (cur == lang and block) or (cur == "en" and en_block) or nil
            if target and l:match("%S") then
                target[#target + 1] = l
            end
        end
    end
    local b, t = block, title
    if not b or #b == 0 then
        b, t = en_block, en_title
    end
    if not b or #b == 0 then
        return nil
    end
    return ((t and t ~= "") and ("# " .. t .. "\n") or "") .. table.concat(b, "\n")
end

function N.from_feed(P, entry, lang)
    local text = entry and P.changelog(entry, lang)
    if not text then
        return nil
    end
    local d = N.parse(text)
    if #d.groups == 0 then
        return nil
    end
    d.version = N.vnum(entry.name or entry.version)
    return d
end

function N.from_patch(C, version, lang)
    local ok, md = pcall(love.filesystem.read, C.root .. "/" .. N.FILE)
    if not ok or type(md) ~= "string" then
        return nil
    end
    local text = N.md_block(md, version, lang)
    if not text then
        return nil
    end
    local d = N.parse(text)
    if #d.groups == 0 then
        return nil
    end
    d.version = N.vnum(version)
    return d
end

function N.after_due(seen, installed)
    if not installed or installed == "" or installed == "?" then
        return false
    end
    return N.vnum(seen) ~= N.vnum(installed)
end

return N
