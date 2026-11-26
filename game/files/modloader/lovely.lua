local toml = require("modloader.toml")
local Regex = require("modloader.regex")

local Engine = {
    version = "0.10.0",
    repo = "https://github.com/ethangreen-dev/lovely-injector",
    patches = {},
    targets = {},
    vars = {},
    warnings = {},
    applied = {},
    aliases = {},
    late_misses = {},
    skip_late = {},
}

local LATE_MISS = "overhaul late patch "

local function late_miss(id, target, why)
    if Engine.late_global then Engine.late_global[id] = "miss" end
    for _, m in ipairs(Engine.late_misses) do
        if m.id == id and m.target == target then return end
    end
    Engine.late_misses[#Engine.late_misses + 1] = {id = id, target = target, why = why}
end

local quiet_no_match = false

local function warn(msg, patch, target, found)
    if quiet_no_match and patch and found == 0 then return end
    Engine.warnings[#Engine.warnings + 1] = msg
    if patch and Engine.misses then
        Engine.misses[#Engine.misses + 1] = {target = target, source = patch.source, kind = patch.kind,
            found = found or 0, wanted = patch.times, pattern = patch.pattern}
    end
    print("[lovely] WARN " .. msg)
    if Engine.on_warn then pcall(Engine.on_warn, msg) end
end

local function lower_cmp(a, b) return a:lower() < b:lower() end

local function as_list(t)
    if type(t) == "string" then return {t} end
    return t or {}
end

local function trim(s)
    local a = s:find("%S")
    if not a then return "" end
    local b = #s
    local c = s:byte(b)
    while c == 32 or (c >= 9 and c <= 13) do b = b - 1; c = s:byte(b) end
    return s:sub(a, b)
end

local function wildmatch(pat, s)
    local pi, si, np, ns = 1, 1, #pat, #s
    local star_p, star_s
    while si <= ns do
        local pc = pat:sub(pi, pi)
        if pi <= np and pc == "?" then
            local b = s:byte(si)
            local w = b >= 0xF0 and 4 or (b >= 0xE0 and 3 or (b >= 0xC0 and 2 or 1))
            pi = pi + 1
            si = si + w
        elseif pi <= np and pc == "*" then
            star_p = pi
            star_s = si
            pi = pi + 1
        elseif pi <= np and pc == s:sub(si, si) then
            pi = pi + 1
            si = si + 1
        elseif star_p then
            pi = star_p + 1
            star_s = star_s + 1
            si = star_s
        else
            return false
        end
    end
    while pi <= np and pat:sub(pi, pi) == "*" do pi = pi + 1 end
    return pi > np
end

local function split_raw_lines(text)
    local lines = {}
    local pos, n = 1, #text
    while pos <= n do
        local e = text:find("\n", pos, true)
        if not e then
            lines[#lines + 1] = text:sub(pos)
            break
        end
        lines[#lines + 1] = text:sub(pos, e)
        pos = e + 1
    end
    return lines
end

local function split_inclusive(s)
    local out = {}
    local pos, n = 1, #s
    while pos <= n do
        local e = s:find("\n", pos, true)
        if not e then out[#out + 1] = s:sub(pos); break end
        out[#out + 1] = s:sub(pos, e)
        pos = e + 1
    end
    return out
end

local function apply_pattern(patch, lines, target, trimmed)
    local pat_lines = {}
    for line in (patch.pattern .. "\n"):gmatch("(.-)\r?\n") do pat_lines[#pat_lines + 1] = trim(line) end
    if patch.pattern:sub(-1) == "\n" then pat_lines[#pat_lines] = nil end
    local m = #pat_lines
    if m == 0 then
        warn("pattern on " .. target .. " from " .. patch.source .. " has no lines")
        return lines, false, trimmed
    end
    local matches = {}
    local first = pat_lines[1]
    local first_plain = not first:find("[%*%?]")
    local idx, n = 1, #lines
    while idx + m - 1 <= n do
        local ok = true
        local t1 = trimmed[idx]
        if not t1 then t1 = trim(lines[idx]); trimmed[idx] = t1 end
        if first_plain then ok = (t1 == first) else ok = wildmatch(first, t1) end
        if ok then
            for j = 2, m do
                local t = trimmed[idx + j - 1]
                if not t then t = trim(lines[idx + j - 1]); trimmed[idx + j - 1] = t end
                if not wildmatch(pat_lines[j], t) then ok = false; break end
            end
        end
        if ok then
            local indent = patch.match_indent and lines[idx]:match("^[ \t]*") or ""
            matches[#matches + 1] = {idx, indent}
            idx = idx + m
        else
            idx = idx + 1
        end
    end
    if #matches == 0 then
        warn("pattern '" .. patch.pattern .. "' on " .. target .. " from " .. patch.source .. " resulted in no matches", patch, target, 0)
        return lines, false, trimmed
    end
    if patch.times then
        if #matches ~= patch.times then
            warn("pattern '" .. patch.pattern .. "' on " .. target .. " from " .. patch.source .. " resulted in " .. #matches .. " matches, wanted " .. patch.times, patch, target, #matches)
        end
        while #matches > patch.times do matches[#matches] = nil end
    end
    local payload_src = patch.payload or ""
    local out, out_trim = {}, {}
    local cursor = 1
    local merged = false
    for _, mt in ipairs(matches) do
        local li, indent = mt[1], mt[2]
        local pieces = split_inclusive(payload_src)
        local payload = {}
        for i, piece in ipairs(pieces) do payload[i] = indent .. piece end
        if payload_src:sub(-1) ~= "\n" then
            if #payload == 0 then payload[1] = "\n" else payload[#payload] = payload[#payload] .. "\n" end
        end
        local pos = patch.position
        local insert_at = pos == "after" and li + m or li
        for i = cursor, insert_at - 1 do out[#out + 1] = lines[i]; out_trim[#out] = trimmed[i] end
        if #out > 0 and out[#out]:sub(-1) ~= "\n" then merged = true end
        for _, pl in ipairs(payload) do out[#out + 1] = pl end
        if pos == "at" then
            cursor = li + m
        else
            cursor = insert_at
        end
    end
    for i = cursor, #lines do out[#out + 1] = lines[i]; out_trim[#out] = trimmed[i] end
    if merged then return split_raw_lines(table.concat(out)), true, {} end
    return out, true, out_trim
end

local function is_word_byte(b)
    return b and ((b >= 48 and b <= 57) or (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 95)
end

local function apply_regex(patch, text, target)
    local ok, re = pcall(Regex.new, patch.pattern, {multi_line = true, ignore_whitespace = patch.verbose})
    if not ok then
        warn("regex failed to compile for " .. target .. " from " .. patch.source .. ": " .. tostring(re))
        return text, false
    end
    local cok, caps = pcall(re.captures_all, re, text)
    if not cok then
        warn("regex '" .. patch.pattern .. "' on " .. target .. " from " .. patch.source .. " could not be matched: " .. tostring(caps), patch, target, 0)
        return text, false
    end
    if #caps == 0 then
        warn("regex '" .. patch.pattern .. "' on " .. target .. " from " .. patch.source .. " resulted in no matches", patch, target, 0)
        return text, false
    end
    if patch.times then
        if #caps ~= patch.times then
            warn("regex '" .. patch.pattern .. "' on " .. target .. " from " .. patch.source .. " resulted in " .. #caps .. " matches, wanted " .. patch.times, patch, target, #caps)
        end
        while #caps > patch.times do caps[#caps] = nil end
    end
    local root = (patch.root_capture or "0"):gsub("%$", "")
    local out = {}
    local last_byte
    local function emit(s)
        if s ~= "" then out[#out + 1] = s; last_byte = s:byte(-1) end
    end
    local cursor = 1
    for _, groups in ipairs(caps) do
        local prepend = re:interpolate(patch.line_prepend or "", text, groups)
        local idx = re:group_index(root)
        local tg = idx and groups[idx]
        if not tg then
            warn("regex capture '" .. root .. "' not found for " .. target .. " from " .. patch.source)
            emit(text:sub(cursor))
            return table.concat(out), false
        end
        local ts, te = tg[1], tg[2]
        local pieces = split_inclusive(patch.payload or "")
        for i, piece in ipairs(pieces) do pieces[i] = prepend .. piece end
        local payload = re:interpolate(table.concat(pieces), text, groups)
        local pos = patch.position
        local copy_to = pos == "after" and te or ts
        emit(text:sub(cursor, copy_to - 1))
        local first = payload:byte(1)
        if first and is_word_byte(first) then
            local left = (copy_to > 1) and last_byte or nil
            if left and is_word_byte(left) then payload = " " .. payload end
        end
        local lastb = payload:byte(-1)
        if lastb and is_word_byte(lastb) then
            local post = pos == "before" and ts or te
            local right = text:byte(post)
            if right and is_word_byte(right) then payload = payload .. " " end
        end
        emit(payload)
        if pos == "at" then cursor = te else cursor = copy_to end
    end
    emit(text:sub(cursor))
    return table.concat(out), true
end

local function apply_copy(patch, text)
    local contents = {}
    for _, c in ipairs(patch.contents or {}) do contents[#contents + 1] = c end
    if patch.payload then contents[#contents + 1] = patch.payload end
    for _, c in ipairs(contents) do
        if patch.position == "prepend" then
            text = c .. "\n" .. text
        else
            text = text .. "\n" .. c
        end
    end
    return text
end

local function stable_by_priority(list)
    for i, p in ipairs(list) do p._order = i end
    table.sort(list, function(a, b)
        if a.priority ~= b.priority then return a.priority < b.priority end
        return a._order < b._order
    end)
    return list
end

local function read_file(path)
    local s = love.filesystem.read(path)
    if Engine._inputs then Engine._inputs[#Engine._inputs + 1] = path .. "\0" .. (s or "\1") end
    return s
end

local function fnv_hex(s)
    local bit = require("bit")
    local h1, h2 = 0x811c9dc5, 0x01000193
    local bxor, tobit = bit.bxor, bit.tobit
    for i = 1, #s do
        local b = s:byte(i)
        h1 = tobit(bxor(h1, b) * 16777619)
        h2 = tobit(bxor(h2, b) * 2246822519)
    end
    return bit.tohex(h1) .. bit.tohex(h2)
end

function Engine.hash(s)
    if love.data and love.data.hash then
        return love.data.encode("string", "hex", love.data.hash("md5", s))
    end
    return fnv_hex(s)
end

local function remove_tree(path)
    if love.filesystem.getInfo(path, "directory") then
        for _, item in ipairs(love.filesystem.getDirectoryItems(path)) do remove_tree(path .. "/" .. item) end
    end
    love.filesystem.remove(path)
end

function Engine.layer_of(path)
    local fs = love.filesystem
    if not fs.getRealDirectory then return nil end
    local ok, dir = pcall(fs.getRealDirectory, path)
    return ok and type(dir) == "string" and dir or nil
end

function Engine.home_only(dir, paths)
    local home = Engine.layer_of("modloader/lovely.lua")
    if not home then return paths, {} end
    local fs = love.filesystem
    local save = fs.getSaveDirectory and fs.getSaveDirectory() or nil
    local kept, stale = {}, {}
    for _, path in ipairs(paths) do
        local here = Engine.layer_of(path)
        if here and here ~= home and here ~= save then stale[#stale + 1] = path else kept[#kept + 1] = path end
    end
    for _, path in ipairs(stale) do print("[lovely] ignored " .. path .. ": left over from an older install") end
    return kept, stale
end

function Engine.load(mods_dir, opts)
    opts = opts or {}
    Engine.mods_dir = mods_dir
    Engine.patches, Engine.targets, Engine.vars, Engine.warnings = {}, {}, {}, {}
    Engine.cache_dir, Engine.fingerprint, Engine.cache_key = nil, nil, nil
    Engine._inputs = {}
    Engine.opts = opts
    Engine.late_misses, Engine.skip_late = {}, {}
    Engine.late_global, Engine.late_target = {}, {}
    Engine.has_fork = next(opts.extra or {}) ~= nil
    Engine.dump_dir = nil
    if opts.dump then
        Engine.dump_dir = mods_dir .. "/lovely/dump"
        remove_tree(Engine.dump_dir)
    end
    local blacklist = {}
    local bl = not opts.enabled and read_file(mods_dir .. "/lovely/blacklist.txt")
    if bl then
        for line in bl:gmatch("[^\r\n]+") do
            line = trim(line)
            if line ~= "" and line:sub(1, 1) ~= "#" then blacklist[line] = true end
        end
    end
    local dirs, where = {}, {}
    for _, name in ipairs(love.filesystem.getDirectoryItems(mods_dir)) do
        local info = love.filesystem.getInfo(mods_dir .. "/" .. name)
        if info and info.type == "directory" and not blacklist[name]
            and (opts.enabled and opts.enabled[name] or (not opts.enabled
            and not love.filesystem.getInfo(mods_dir .. "/" .. name .. "/.lovelyignore"))) then
            dirs[#dirs + 1] = name
            where[name] = mods_dir .. "/" .. name
        end
    end
    for name, dir in pairs(opts.extra or {}) do
        if not where[name] then dirs[#dirs + 1] = name end
        where[name] = dir
    end
    table.sort(dirs, lower_cmp)
    Engine.mod_dirs = {}
    for _, name in ipairs(dirs) do
        local mod_dir = where[name]
        Engine.mod_dirs[#Engine.mod_dirs + 1] = mod_dir
        local files = {}
        if love.filesystem.getInfo(mod_dir .. "/lovely.toml", "file") then files[#files + 1] = mod_dir .. "/lovely.toml" end
        if love.filesystem.getInfo(mod_dir .. "/lovely", "directory") then
            local tomls = {}
            local function walk(rel)
                local base = mod_dir .. "/lovely" .. (rel == "" and "" or "/" .. rel)
                for _, f in ipairs(love.filesystem.getDirectoryItems(base)) do
                    local sub = rel == "" and f or (rel .. "/" .. f)
                    local info = love.filesystem.getInfo(base .. "/" .. f)
                    if info and info.type == "directory" then
                        walk(sub)
                    elseif info and info.type == "file" and f:sub(-5) == ".toml" then
                        tomls[#tomls + 1] = sub
                    end
                end
            end
            walk("")
            table.sort(tomls, lower_cmp)
            for _, f in ipairs(tomls) do files[#files + 1] = mod_dir .. "/lovely/" .. f end
        end
        if opts.extra and opts.extra[name] == mod_dir then files = Engine.home_only(mod_dir, files) end
        for _, file in ipairs(files) do
            Engine.load_patch_file(file, mod_dir, read_file(file) or "")
        end
    end
    for _, file in ipairs(opts.late or {}) do
        Engine.load_patch_file(file, nil, read_file(file) or "", true)
    end
    local inputs = Engine._inputs
    Engine._inputs = nil
    table.insert(inputs, 1, table.concat({"lovely-lua", Engine.version, Engine.cache_format,
        tostring(opts.build or ""), mods_dir}, "\0"))
    Engine.fingerprint = Engine.hash(table.concat(inputs, "\0\0"))
    Engine.cache_key = Engine.hash(Engine.fingerprint .. "\0" .. love.filesystem.getSaveDirectory())
    return Engine
end

Engine.cache_format = "1"

function Engine.use_cache(root)
    if not Engine.cache_key then return nil end
    local dir = root .. "/" .. Engine.cache_key
    if love.filesystem.getInfo(root, "directory") then
        for _, item in ipairs(love.filesystem.getDirectoryItems(root)) do
            if item ~= Engine.cache_key then remove_tree(root .. "/" .. item) end
        end
    end
    if not love.filesystem.getInfo(dir, "directory") and not love.filesystem.createDirectory(dir) then return nil end
    Engine.cache_dir = dir
    Engine.cache_hits, Engine.cache_misses = 0, 0
    return dir
end

local function vars_key()
    local keys = {}
    for k in pairs(Engine.vars) do keys[#keys + 1] = k end
    if #keys == 0 then return "" end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do parts[i] = k .. "=" .. tostring(Engine.vars[k]) end
    return Engine.hash(table.concat(parts, "\0"))
end

local function cross_key(target)
    local parts = {}
    for _, p in ipairs(Engine.patches) do
        if p.late and p.requires and p.target == target then
            for _, entry in ipairs(as_list(p.requires)) do
                for id in tostring(entry):gmatch("[^|]+") do
                    local other = Engine.late_target[id]
                    if other and other ~= target and Engine.late_global[id] == "miss" then parts[#parts + 1] = id end
                end
            end
        end
    end
    if #parts == 0 then return "" end
    table.sort(parts)
    return "x" .. Engine.hash(table.concat(parts, "\0"))
end

local WSEP = "\0\n"

function Engine.dump_name(name)
    local a, b, c = name:match('=%[([%w_]+) (%S+) "([^"]+)"%]')
    if not a then
        a, c = name:match('=%[([%w_]+) "([^"]+)"%]')
        b = ""
    end
    if a then return a .. "/" .. (b == "" and "" or b:gsub("%.", "/") .. "/") .. c end
    return (name:gsub("@", ""))
end

function Engine.dump(name, out)
    local root = Engine.dump_dir
    if not root or type(out) ~= "string" then return end
    local rel = Engine.dump_name(name)
    if select(2, rel:gsub("[^\128-\191]", "")) > 100 then return end
    local path = root .. "/" .. rel
    if love.filesystem.getInfo(path) then return end
    local parent = path:match("^(.*)/[^/]*$")
    if parent then love.filesystem.createDirectory(parent) end
    love.filesystem.write(path, out)
end

local function patch_uncached(name, buffer)
    local out = Engine.apply_patches(name, buffer)
    Engine.dump(name, out)
    return out
end

function Engine.patch_cached(name, buffer)
    local target = name:sub(1, 1) == "@" and name:sub(2) or name
    if not Engine.targets[target] or type(buffer) ~= "string" then return buffer end
    if LOADING_SCREEN then pcall(LOADING_SCREEN.draw) end
    local dir = Engine.cache_dir
    if not dir then return patch_uncached(name, buffer) end
    local base = dir .. "/" .. Engine.hash(target)
    local key = Engine.hash(buffer) .. vars_key() .. cross_key(target)
    local meta = love.filesystem.read(base .. ".meta")
    if meta then
        local mkey, count, warns = meta:match("^([^\n]*)\n(%d+)\n(.*)$")
        if mkey == key then
            local out = love.filesystem.read(base .. ".patched")
            if out then
                Engine.cache_hits = Engine.cache_hits + 1
                Engine.applied[target] = tonumber(count)
                local pos = 1
                while true do
                    local a, b = warns:find(WSEP, pos, true)
                    if not a then break end
                    local w = warns:sub(pos, a - 1)
                    Engine.warnings[#Engine.warnings + 1] = w
                    local id, t = w:match("^" .. LATE_MISS .. "(.-) missed on (.*)$")
                    if id then
                        local t2, need = t:match("^(.-) %(needs (.-)%)$")
                        late_miss(id, t2 or t, need and ("needs " .. need) or "no match")
                    end
                    if Engine.on_warn then pcall(Engine.on_warn, w) end
                    pos = b + 1
                end
                Engine.dump(name, out)
                return out
            end
        end
    end
    local first = #Engine.warnings + 1
    local out = patch_uncached(name, buffer)
    Engine.cache_misses = Engine.cache_misses + 1
    local warns = {}
    for i = first, #Engine.warnings do warns[#warns + 1] = Engine.warnings[i] .. WSEP end
    if love.filesystem.write(base .. ".patched", out) then
        love.filesystem.write(base .. ".meta", key .. "\n" .. tostring(Engine.applied[target] or 0) .. "\n" .. table.concat(warns))
    end
    return out
end

function Engine.load_patch_file(file, mod_dir, content, late)
    if mod_dir then
        local abs_dir = (love.filesystem.getSaveDirectory() .. "/" .. mod_dir):gsub("\\", "\\\\")
        content = content:gsub("{{lovely_hack:patch_dir}}", function() return abs_dir end)
    end
    local ok, doc = pcall(toml.parse, content)
    if not ok then
        warn("could not parse " .. file .. ": " .. tostring(doc))
        return
    end
    local priority = (doc.manifest and tonumber(doc.manifest.priority)) or 0
    for k, v in pairs(doc.vars or {}) do Engine.vars[k] = tostring(v) end
    for i, entry in ipairs(doc.patches or {}) do
        for kind, def in pairs(entry) do
            local p = {kind = kind, priority = priority, source = file, mod_dir = mod_dir}
            for k, v in pairs(def) do p[k] = v end
            local valid = true
            if late then
                p.late = true
                p.id = p.id or (file .. "#" .. i)
                if type(p.target) == "string" then Engine.late_target[p.id] = p.target end
                if kind ~= "pattern" and kind ~= "regex" then
                    warn("late patch " .. p.id .. " in " .. file .. " is a " .. kind .. " patch, only pattern and regex are allowed")
                    valid = false
                end
            elseif kind == "module" then
                p.content = read_file(mod_dir .. "/" .. tostring(def.source))
                if not p.content then
                    warn("module source " .. tostring(def.source) .. " not found for " .. file)
                    valid = false
                end
                if p.load_now and not p.before then
                    warn("module " .. tostring(p.name) .. " has load_now without before in " .. file)
                    valid = false
                end
                if valid then Engine.targets[p.before or ""] = true end
            elseif kind == "copy" then
                p.contents = {}
                for _, src in ipairs(def.sources or {}) do
                    local c = read_file(mod_dir .. "/" .. src)
                    if not c then
                        warn("copy source " .. src .. " not found for " .. file)
                        valid = false
                    else
                        p.contents[#p.contents + 1] = c
                    end
                end
            elseif kind ~= "pattern" and kind ~= "regex" then
                warn("unknown patch kind " .. kind .. " in " .. file)
                valid = false
            end
            if valid then
                if kind ~= "module" then
                    for _, t in ipairs(as_list(p.target)) do Engine.targets[t] = true end
                end
                Engine.patches[#Engine.patches + 1] = p
            end
        end
    end
end

function Engine.missing_requires(p, state, skip)
    if skip and skip[p.id] then return skip[p.id].entry, skip[p.id].quiet end
    local quiet, first, pending = true, nil, nil
    for _, entry in ipairs(as_list(p.requires)) do
        local good, open, loud = false, false, false
        for id in tostring(entry):gmatch("[^|]+") do
            local st = state[id]
            local other = Engine.late_target and Engine.late_target[id]
            if st == nil and other and other ~= p.target then
                st = Engine.late_global[id] == "miss" and "miss" or "ok"
            end
            if st == "ok" then good = true elseif st == nil then open = true elseif st ~= "absent" then loud = true end
        end
        if not good then
            if open then
                pending = pending or {}
                pending[#pending + 1] = tostring(entry)
            else
                first = first or tostring(entry)
                if loud then quiet = false end
            end
        end
    end
    if first then return first, quiet end
    return nil, nil, pending
end

local function can_apply(p, target)
    for _, t in ipairs(as_list(p.target)) do
        if t == target then return true end
    end
    return false
end

function Engine.needs_patching(name)
    if type(name) ~= "string" then return false end
    if name:sub(1, 1) == "@" then name = name:sub(2) end
    return Engine.targets[name] == true
end

function Engine.apply_patches(name, buffer, skip)
    if LOADING_SCREEN then pcall(LOADING_SCREEN.draw, "Patching game files") end
    local target = name:sub(1, 1) == "@" and name:sub(2) or name
    if not Engine.targets[target] then return buffer end
    local count = 0
    local copies, textual = {}, {}
    for _, p in ipairs(Engine.patches) do
        if p.kind == "copy" and can_apply(p, target) then copies[#copies + 1] = p end
    end
    local late = {}
    for _, p in ipairs(Engine.patches) do
        if p.kind == "pattern" and can_apply(p, target) then
            if not p.late then textual[#textual + 1] = p elseif not Engine.skip_late[target] then late[#late + 1] = p end
        end
    end
    for _, p in ipairs(Engine.patches) do
        if p.kind == "regex" and can_apply(p, target) then
            if not p.late then textual[#textual + 1] = p elseif not Engine.skip_late[target] then late[#late + 1] = p end
        end
    end
    stable_by_priority(copies)
    stable_by_priority(textual)
    stable_by_priority(late)
    for _, p in ipairs(late) do textual[#textual + 1] = p end
    local text = buffer
    if text:find("\r\n", 1, true) then text = text:gsub("\r\n", "\n") end
    for _, p in ipairs(copies) do
        text = apply_copy(p, text)
        count = count + 1
    end
    local lines, trimmed
    local late_state, assumed, retry = {}, {}, {}
    local has_late = #late > 0
    local nwarn0, nmiss0, nrec0 = #Engine.warnings, #Engine.late_misses, Engine.misses and #Engine.misses
    for _, p in ipairs(textual) do
        local ok, absent, needs
        if LOADING_SCREEN then pcall(LOADING_SCREEN.draw) end
        local nwarn = #Engine.warnings
        local pending
        if p.late then needs, absent, pending = Engine.missing_requires(p, late_state, skip) end
        if needs then
            ok = false
        else
            quiet_no_match = p.late and p.optional == true
            if p.kind == "pattern" then
                if not lines then lines = split_raw_lines(text); trimmed = {} end
                lines, ok, trimmed = apply_pattern(p, lines, target, trimmed)
                text = nil
            else
                if lines then text = table.concat(lines); lines = nil; trimmed = nil end
                text, ok = apply_regex(p, text, target)
            end
            absent = quiet_no_match and not ok and #Engine.warnings == nwarn
            quiet_no_match = false
        end
        if ok then count = count + 1 end
        if not ok and not p.late and has_late and #Engine.warnings == nwarn + 1 and Engine.warnings[#Engine.warnings]:find("resulted in no matches", 1, true) then
            retry[#retry + 1] = {p = p, warning = #Engine.warnings, miss = Engine.misses and #Engine.misses}
        end
        if ok and pending then assumed[#assumed + 1] = {id = p.id, entries = pending} end
        if p.late then late_state[p.id] = ok and "ok" or absent and "absent" or "miss" end
        if p.late and not absent and (not ok or #Engine.warnings > nwarn) then
            late_miss(p.id, target, needs and ("needs " .. needs) or "no match")
            warn(LATE_MISS .. p.id .. " missed on " .. target .. (needs and (" (needs " .. needs .. ")") or ""), needs and p or nil, target, 0)
        end
    end
    local drop_warn, drop_miss = {}, {}
    for _, r in ipairs(retry) do
        local p, ok = r.p, false
        quiet_no_match = true
        if p.kind == "pattern" then
            if not lines then lines = split_raw_lines(text); trimmed = {} end
            lines, ok, trimmed = apply_pattern(p, lines, target, trimmed)
            text = nil
        else
            if lines then text = table.concat(lines); lines = nil; trimmed = nil end
            text, ok = apply_regex(p, text, target)
        end
        quiet_no_match = false
        if ok then
            count = count + 1
            drop_warn[r.warning] = true
            if r.miss then drop_miss[r.miss] = true end
        end
    end
    for i = #Engine.warnings, 1, -1 do if drop_warn[i] then table.remove(Engine.warnings, i) end end
    if Engine.misses then
        for i = #Engine.misses, 1, -1 do if drop_miss[i] then table.remove(Engine.misses, i) end end
    end
    if lines then text = table.concat(lines) end
    local redo
    for _, a in ipairs(assumed) do
        for _, entry in ipairs(a.entries) do
            local good, quiet = false, true
            for id in entry:gmatch("[^|]+") do
                if late_state[id] == "ok" then good = true elseif late_state[id] ~= "absent" then quiet = false end
            end
            if not good then
                redo = redo or {}
                for k, v in pairs(skip or {}) do redo[k] = v end
                redo[a.id] = {entry = entry, quiet = quiet}
                break
            end
        end
    end
    if redo then
        for i = #Engine.warnings, nwarn0 + 1, -1 do Engine.warnings[i] = nil end
        for i = #Engine.late_misses, nmiss0 + 1, -1 do Engine.late_misses[i] = nil end
        if nrec0 and Engine.misses then for i = #Engine.misses, nrec0 + 1, -1 do Engine.misses[i] = nil end end
        return Engine.apply_patches(name, buffer, redo)
    end
    local groups = {}
    for _, p in ipairs(late) do
        if type(p.needed) == "string" and (p.needed_when ~= "fork" or Engine.has_fork) then
            if groups[p.needed] == nil then groups[#groups + 1] = p.needed; groups[p.needed] = false end
            if late_state[p.id] == "ok" then groups[p.needed] = true end
        end
    end
    for _, group in ipairs(groups) do
        if not groups[group] then
            late_miss(group, target, "no variant applied")
            warn(LATE_MISS .. group .. " missed on " .. target)
        end
    end
    local out = {}
    for _, line in ipairs(split_inclusive(text)) do
        out[#out + 1] = line:gsub("{{lovely:([%w_]+)}}", function(var)
            local v = Engine.vars[var]
            if v == nil then error("lovely: unregistered variable '" .. var .. "' in " .. target, 0) end
            return v
        end)
    end
    Engine.applied[target] = count
    return table.concat(out)
end

local function lovely_module()
    return {
        repo = Engine.repo,
        version = Engine.version,
        mod_dir = Engine.mod_dir_abs,
        apply_patches = function(name, buffer) return Engine.patch_cached(name, buffer) end,
        reload_patches = function() Engine.load(Engine.mods_dir, Engine.opts); return true end,
        set_var = function(k, v) Engine.vars[k] = v end,
        get_var = function(k) return Engine.vars[k] end,
        remove_var = function(k) Engine.vars[k] = nil end,
        log_path = Engine.mod_dir_abs and (Engine.mod_dir_abs .. "/lovely/log") or "",
    }
end

local raw_load = load
local raw_loadstring = loadstring

local function patch_chunk(code, chunkname)
    if type(code) == "string" and Engine.needs_patching(chunkname) then
        Engine.run_load_now_modules(chunkname)
        return Engine.patch_cached(chunkname, code)
    end
    return code
end

local function quote_lua(str)
    return '"' .. str:gsub('[%c"\\]', function(c) return string.format("\\%03d", c:byte()) end) .. '"'
end

function Engine.thread_requires(code)
    local pre, seen = {}, {}
    if type(code) ~= "string" then return "" end
    for name in code:gmatch("require%s*%(?%s*[\"']([%w_%./%-]+)[\"']") do
        if not seen[name] and not name:find("^love%.") then
            seen[name] = true
            local path = name:gsub("%.lua$", ""):gsub("%.", "/") .. ".lua"
            local tname = Engine.aliases[path] or path
            if Engine.needs_patching(tname) and love.filesystem.getInfo(path, "file") then
                local src = love.filesystem.read(path)
                if src then
                    local at = quote_lua("@" .. path)
                    pre[#pre + 1] = "package.preload[" .. quote_lua(name) .. "]=function(...) local f=loadstring("
                        .. quote_lua(Engine.patch_cached(tname, src)) .. "," .. at .. ") if f then local r={pcall(f,...)} if r[1] then return r[2] end end return assert(loadstring("
                        .. quote_lua(src) .. "," .. at .. "))(...) end;"
                end
            end
        end
    end
    return table.concat(pre)
end

function Engine.thread_modules(chunkname)
    local pre = {}
    for _, p in ipairs(Engine.patches or {}) do
        if p.kind == "module" and p.before == chunkname and p.name and type(p.content) == "string" then
            local name = '=[lovely ' .. p.name .. ' "' .. tostring(p.source) .. '"]'
            pre[#pre + 1] = "package.preload[" .. quote_lua(p.name) .. "]=function(...) return assert(loadstring("
                .. quote_lua(Engine.patch_cached(name, p.content)) .. "," .. quote_lua(name) .. "))(...) end;"
        end
    end
    return table.concat(pre)
end

local function compile_module(p)
    local name = '=[lovely ' .. p.name .. ' "' .. tostring(p.source) .. '"]'
    local code = Engine.patch_cached(name, p.content)
    return raw_loadstring(code, name)
end

function Engine.run_load_now_modules(chunkname)
    local target = chunkname:sub(1, 1) == "@" and chunkname:sub(2) or chunkname
    if target ~= "conf.lua" then Engine.run_load_now_modules("conf.lua") end
    local list = {}
    for _, p in ipairs(Engine.patches) do
        if p.kind == "module" and p.load_now and p.before == target and not p._done then list[#list + 1] = p end
    end
    stable_by_priority(list)
    for _, p in ipairs(list) do
        p._done = true
        local fn, err = compile_module(p)
        if not fn then error("lovely: load_now module " .. p.name .. " failed to load: " .. tostring(err), 0) end
        local ok, res = pcall(fn)
        if not ok then error("lovely: load_now module " .. p.name .. " failed: " .. tostring(res), 0) end
        package.preload[p.name] = function() return res end
    end
end

function Engine.find_breaker(target, code)
    local dirs, seen = {}, {}
    for _, p in ipairs(Engine.patches) do
        if (p.kind == "pattern" or p.kind == "regex" or p.kind == "copy") and p.mod_dir and not seen[p.mod_dir] and can_apply(p, target) then
            seen[p.mod_dir] = true
            dirs[#dirs + 1] = p.mod_dir
        end
    end
    local all, applied = Engine.patches, Engine.applied[target]
    local misses = Engine.misses or {}
    local nwarn, nmiss = #Engine.warnings, #misses
    local found, count, order = {}, {}, {}
    for i, dir in ipairs(dirs) do
        local list, n = {}, 0
        for _, p in ipairs(all) do
            if p.mod_dir ~= dir then
                list[#list + 1] = p
            elseif can_apply(p, target) then
                n = n + 1
            end
        end
        Engine.patches = list
        local ok, out = pcall(Engine.apply_patches, target, code)
        Engine.patches = all
        if ok and type(out) == "string" and raw_loadstring(out, "@" .. target) then
            found[#found + 1] = dir
            count[dir], order[dir] = n, i
        end
    end
    table.sort(found, function(a, b)
        if count[a] ~= count[b] then return count[a] < count[b] end
        return order[a] < order[b]
    end)
    Engine.patches = all
    Engine.applied[target] = applied
    for i = #Engine.warnings, nwarn + 1, -1 do Engine.warnings[i] = nil end
    for i = #misses, nmiss + 1, -1 do misses[i] = nil end
    return found[1], found
end

function Engine.late_for(target)
    local list = {}
    for _, p in ipairs(Engine.patches) do
        if p.late and can_apply(p, target) then list[#list + 1] = p end
    end
    return list
end

function Engine.salvage_late(target, code, chunkname)
    local order = {}
    for _, p in ipairs(Engine.late_for(target)) do if p.id then order[#order + 1] = p end end
    stable_by_priority(order)
    local n = #order
    if n == 0 then return nil end
    local dropped = {}
    local nw, nl, nm = #Engine.warnings, #Engine.late_misses, Engine.misses and #Engine.misses
    local function rewind()
        for i = #Engine.warnings, nw + 1, -1 do Engine.warnings[i] = nil end
        for i = #Engine.late_misses, nl + 1, -1 do Engine.late_misses[i] = nil end
        if nm and Engine.misses then for i = #Engine.misses, nm + 1, -1 do Engine.misses[i] = nil end end
    end
    local function try(upto)
        local skip = {}
        for id in pairs(dropped) do skip[id] = {entry = "a working " .. target, quiet = true} end
        for i = upto + 1, n do skip[order[i].id] = {entry = "later patches", quiet = true} end
        local ok, out = pcall(Engine.apply_patches, target, code, skip)
        rewind()
        if ok and type(out) == "string" and raw_loadstring(out, chunkname) then return out end
    end
    if not try(0) then return nil end
    local lo, guard = 0, 0
    while guard < 2 * n + 2 do
        guard = guard + 1
        if try(n) then break end
        local a, b = lo, n
        while b - a > 1 do
            local m = math.floor((a + b) / 2)
            if try(m) then a = m else b = m end
        end
        local found
        for j = b + 1, math.min(n, b + 8) do
            if try(j) then found = j break end
        end
        if found then
            lo = found
        else
            dropped[order[b].id] = true
            lo = a
        end
    end
    local skip = {}
    for id in pairs(dropped) do skip[id] = {entry = "a working " .. target, quiet = true} end
    local ok, out = pcall(Engine.apply_patches, target, code, skip)
    local fn = ok and type(out) == "string" and raw_loadstring(out, chunkname)
    if not fn then rewind() return nil end
    local list = {}
    for _, p in ipairs(order) do
        if dropped[p.id] then
            list[#list + 1] = p.id
            late_miss(p.id, target, "broke the file")
        end
    end
    return fn, list
end

function Engine.compile_patched(target, code, chunkname)
    local fn, err = raw_loadstring(Engine.patch_cached(target, code), chunkname)
    if fn then return fn end
    local late = Engine.late_for(target)
    if #late > 0 and not Engine.skip_late[target] then
        local ok_s, fn_s, list = pcall(Engine.salvage_late, target, code, chunkname)
        if ok_s and fn_s then
            warn("overhaul late patches broke " .. target .. ", loaded it without " .. table.concat(list, ", ") .. ": " .. tostring(err))
            return fn_s
        end
        Engine.skip_late[target] = true
        local ok, out = pcall(Engine.apply_patches, target, code)
        local fn2 = ok and type(out) == "string" and raw_loadstring(out, chunkname)
        if fn2 then
            for _, p in ipairs(late) do late_miss(p.id, target, "broke the file") end
            warn("overhaul late patches broke " .. target .. ", loaded it without them: " .. tostring(err))
            return fn2
        end
        Engine.skip_late[target] = nil
    end
    local ok, dir, all = pcall(Engine.find_breaker, target, code)
    if ok and dir and all and #all > 1 then
        local names = {}
        for i, d in ipairs(all) do names[i] = d:match("([^/]+)$") or d end
        local list = table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
        err = "The patches of " .. list .. " clash in " .. target .. " (" .. dir .. "/lovely). Turning off any one of them fixes it, or update them. " .. tostring(err)
    elseif ok and dir then
        local name = dir:match("([^/]+)$") or dir
        err = "The mod " .. name .. " broke " .. target .. " with one of its patches (" .. dir .. "/lovely). Turn it off or update it. " .. tostring(err)
    else
        err = "Mod patches broke " .. target .. ". " .. tostring(err)
    end
    return nil, err
end

function Engine.install()
    Engine.mod_dir_abs = (love.filesystem.getSaveDirectory() .. "/" .. Engine.mods_dir):gsub("\\", "/")
    package.preload.lovely = lovely_module
    local mods = {}
    for _, p in ipairs(Engine.patches) do
        if p.kind == "module" and not p.load_now then mods[#mods + 1] = p end
    end
    stable_by_priority(mods)
    for _, p in ipairs(mods) do
        local fn, err = compile_module(p)
        if fn then package.preload[p.name] = fn else
            local msg = tostring(err)
            package.preload[p.name] = function() error(msg, 0) end
            warn("module " .. p.name .. " failed to load: " .. msg)
        end
    end
    loadstring = function(code, ...)
        return raw_loadstring(patch_chunk(code, (...)), ...)
    end
    load = function(chunk, ...)
        return raw_load(patch_chunk(chunk, (...)), ...)
    end
    local searcher = function(modname)
        local base = modname:gsub("%.", "/")
        for _, path in ipairs({base .. ".lua", base .. "/init.lua"}) do
            local tname = Engine.aliases[path] or path
            if Engine.needs_patching(tname) and love.filesystem.getInfo(path, "file") then
                local code = love.filesystem.read(path)
                if type(code) == "string" then
                    Engine.run_load_now_modules(tname)
                    local fn, err = Engine.compile_patched(tname, code, "@" .. path)
                    if not fn then error(err, 0) end
                    return fn
                end
            end
        end
        return nil
    end
    local loaders = package.loaders or package.searchers
    table.insert(loaders, 2, searcher)
    local raw_fs_load = love.filesystem.load
    love.filesystem.load = function(path, ...)
        if Engine.needs_patching(path) then
            local code = love.filesystem.read(path)
            if not code then return raw_fs_load(path, ...) end
            Engine.run_load_now_modules(path)
            return Engine.compile_patched(path, code, "@" .. path)
        end
        return raw_fs_load(path, ...)
    end
    if love.thread and love.thread.newThread then
        local raw_new_thread = love.thread.newThread
        love.thread.newThread = function(src, ...)
            if type(src) == "string" and not src:find("\n") then
                local code = love.filesystem.read(src)
                local pre = Engine.thread_modules(src) .. Engine.thread_requires(code)
                if code and (pre ~= "" or Engine.needs_patching(src)) then
                    return raw_new_thread(love.filesystem.newFileData(pre .. Engine.patch_cached(src, code), src), ...)
                end
            elseif type(src) == "userdata" and src.getFilename and src.getString then
                local name = src:getFilename()
                if type(name) == "string" and name ~= "" then
                    local pre = Engine.thread_modules(name) .. Engine.thread_requires(src:getString())
                    if pre ~= "" or Engine.needs_patching(name) then
                        return raw_new_thread(love.filesystem.newFileData(pre .. Engine.patch_cached(name, src:getString()), name), ...)
                    end
                end
            end
            return raw_new_thread(src, ...)
        end
    end
    Engine.installed = true
    return Engine
end

return Engine
