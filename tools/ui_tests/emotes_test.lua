local base = (arg and arg[0] and arg[0]:match("^(.*)/tools/ui_tests/") or ".")
local root = base .. "/assets/"
local E = dofile(root .. "multiplayer/bom_emotes.lua")
local fails = 0
local function check(name, cond, detail) if not cond then fails = fails + 1 print("FAIL " .. name .. " " .. tostring(detail or "")) else print("ok   " .. name) end end

check("8 to 12 emotes", #E.LIST >= 8 and #E.LIST <= 12, #E.LIST)
local seen, all_posed = {}, true
for _, def in ipairs(E.LIST) do
    check("unique id " .. def.id, not seen[def.id])
    seen[def.id] = true
    if not E.POSES[def.id] then all_posed = false end
    check("label FR and ES " .. def.id, E.LOC.fr[def.label] ~= nil and E.LOC.es[def.label] ~= nil, def.label)
    check("sounds for " .. def.id, type(E.SOUNDS[def.id]) == "table" and #E.SOUNDS[def.id] > 0)
end
check("every emote has a pose", all_posed)

check("legacy numbers", E.resolve(1) == "lucky" and E.resolve(2) == "gg" and E.resolve(4) == "oops" and E.resolve(6) == "hurry")
check("legacy texts", E.resolve("Good luck!") == "lucky" and E.resolve("Well played!") == "gg" and E.resolve("Hurry up!") == "hurry" and E.resolve("Thanks!") == "gg")
check("new ids and case", E.resolve("laugh") == "laugh" and E.resolve("GG") == "gg" and E.resolve("3") == "fire")
check("bad values dropped", E.resolve(0) == nil and E.resolve(7) == nil and E.resolve(1.5) == nil and E.resolve(0 / 0) == nil
    and E.resolve("dance") == nil and E.resolve(nil) == nil and E.resolve(true) == nil and E.resolve({}) == nil)
check("tables resolve", E.resolve({id = "nope"}) == "nope" and E.resolve({e = 5}) == "gg" and E.resolve({id = "x", e = 3}) == "fire")
for id, n in pairs(E.TO_LEGACY) do check("to legacy known " .. id, E.BY_ID[id] ~= nil and n >= 1 and n <= 6) end

local f = io.open(base .. "/server/src/social.ts", "r")
local ts = f and f:read("*a") or ""
if f then f:close() end
local function ts_list(name)
    local body = ts:match("export const " .. name .. " = %[(.-)%]")
    local out = {}
    for s in (body or ""):gmatch("'([%w_]+)'") do out[#out + 1] = s end
    return out
end
local ids = ts_list("EMOTE_IDS")
check("server knows the same ids", #ids == #E.LIST, #ids)
for i, def in ipairs(E.LIST) do check("server id " .. i, ids[i] == def.id, tostring(ids[i])) end
local leg = ts_list("EMOTE_FROM_LEGACY")
for i = 1, 6 do check("server legacy " .. i, leg[i] == E.FROM_LEGACY[i], tostring(leg[i])) end
local map = ts:match("EMOTE_TO_LEGACY: Record<string, number> = {(.-)}") or ""
local server_to = {}
for k, v in map:gmatch("([%w_]+): (%d+)") do server_to[k] = tonumber(v) end
for id, n in pairs(E.TO_LEGACY) do check("server to legacy " .. id, server_to[id] == n, tostring(server_to[id])) end
for id, n in pairs(server_to) do check("client to legacy " .. id, E.TO_LEGACY[id] == n) end

local sounds = {}
local p = io.popen('ls "' .. root .. 'resources/sounds" 2>/dev/null')
if p then for line in p:lines() do sounds[line:gsub("%.ogg$", "")] = true end p:close() end
for id, list in pairs(E.SOUNDS) do
    for _, s in ipairs(list) do
        local code = s[2] == "glass" and "glass1" or s[2]
        check("sound exists " .. id .. " " .. s[2], sounds[code] == true)
        check("sound in time " .. id .. " " .. s[2], s[1] >= 0 and s[1] < E.DURATION)
    end
end

local D, step = E.DURATION, 1 / 60
check("envelope closed", E.envelope(0) == 0 and E.envelope(D) == 0 and E.envelope(0.7) == 1)
local prev, env_jump = E.envelope(0), 0
for i = 1, math.floor(D / step) do
    local v = E.envelope(i * step)
    if i > 1 then env_jump = math.max(env_jump, math.abs(v - prev)) end
    prev = v
end
check("envelope smooth at 60 fps", env_jump < 0.3, env_jump)

local LIM = {x = 0.09, y = 0.09, w = 0.24, h = 0.24, r = 0.36}
local function finite(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
for _, def in ipairs(E.LIST) do
    local last, worst, worst_at, bad_num, missing, empty = {}, 0, "", false, nil, false
    for i = 0, math.floor(D / step) do
        local t = i * step
        local parts = E.pose(def.id, t)
        if t > 0.2 and t < 1.2 and #parts == 0 then empty = true end
        local now = {}
        for _, part in ipairs(parts) do
            for _, key in ipairs({"x", "y", "w", "h", "r"}) do
                if part[key] ~= nil and not finite(part[key]) then bad_num = true end
            end
            if part.k == "spr" and not E.SPRITES[part.spr] then missing = part.spr end
            if part.k == "txt" and type(part.text) ~= "string" then missing = "text " .. tostring(part.key) end
            if part.k == "spr" or part.k == "rect" or part.k == "fx" or part.k == "flame" then
                local was = last[part.key]
                if was then
                    for key, lim in pairs(LIM) do
                        if part[key] and was[key] then
                            local d = math.abs(part[key] - was[key]) / lim
                            if d > worst then worst, worst_at = d, string.format("%s.%s at %.3f", part.key, key, t) end
                        end
                    end
                end
                now[part.key] = part
            end
        end
        last = now
    end
    check("pose numbers finite " .. def.id, not bad_num)
    check("pose sprites known " .. def.id, missing == nil, missing)
    check("pose never empty " .. def.id, not empty)
    check("smooth at 60 fps " .. def.id, worst <= 1, string.format("%.2f %s", worst, worst_at))
end

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
