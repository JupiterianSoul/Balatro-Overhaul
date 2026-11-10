package.path = "tools/release/launcher/?.lua;" .. package.path
local S = require("shortcuts")

local fails = 0
local function check(name, ok)
    if not ok then
        fails = fails + 1
        print("FAIL " .. name)
    end
end

local function parse(data)
    local pos = 1
    local function cstr()
        local e = data:find("\0", pos, true)
        local s = data:sub(pos, e - 1)
        pos = e + 1
        return s
    end
    local function map()
        local t = {}
        while true do
            local ty = data:byte(pos)
            pos = pos + 1
            if ty == 8 then return t end
            local k = cstr()
            if ty == 0 then t[k] = map()
            elseif ty == 1 then t[k] = cstr()
            elseif ty == 2 then
                local b1, b2, b3, b4 = data:byte(pos, pos + 3)
                pos = pos + 4
                t[k] = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
            else error("bad type " .. tostring(ty) .. " at " .. pos) end
        end
    end
    check("root starts with a map", data:byte(1) == 0)
    pos = 2
    local name = cstr()
    local t = map()
    check("ends with the root end", data:byte(pos) == 8 and pos == #data)
    return name, t
end

local exe = "C:\\Users\\me\\AppData\\Local\\Balatro Overhaul\\Balatro Overhaul Launcher.exe"
local dir = "C:\\Users\\me\\AppData\\Local\\Balatro Overhaul"

local fresh = S.add_to_vdf(nil, exe, dir)
local name, t = parse(fresh)
check("root is shortcuts", name == "shortcuts")
local e = t["0"]
check("first entry is 0", e ~= nil)
check("app name", e and e.AppName == S.NAME)
check("exe quoted", e and e.Exe == '"' .. exe .. '"')
check("start dir quoted", e and e.StartDir == '"' .. dir .. '"')
check("launch options", e and e.LaunchOptions == "--play")
check("appid high bit", e and e.appid >= 0x80000000)
check("tags map", e and type(e.tags) == "table")
check("has entry", S.has_entry(fresh))
check("no second copy", S.add_to_vdf(fresh, exe, dir) == nil)

local empty = "\0shortcuts\0\8\8"
local _, t2 = parse(S.add_to_vdf(empty, exe, dir))
check("empty list gets entry 0", t2["0"] and t2["0"].AppName == S.NAME)

local other = S.vdf_entry(0, "C:\\Games\\Other.exe", "C:\\Games"):gsub(S.NAME, "Other Game")
local one = "\0shortcuts\0" .. other .. "\8\8"
local _, t3 = parse(S.add_to_vdf(one, exe, dir))
check("existing entry kept", t3["0"] and t3["0"].AppName == "Other Game")
check("new entry is 1", t3["1"] and t3["1"].AppName == S.NAME)

check("broken file left alone", S.add_to_vdf("garbage", exe, dir) == nil)
check("empty file starts a list", S.add_to_vdf("", exe, dir) ~= nil)

if fails == 0 then print("shortcuts: all passed") else print("shortcuts: " .. fails .. " failed") os.exit(1) end
