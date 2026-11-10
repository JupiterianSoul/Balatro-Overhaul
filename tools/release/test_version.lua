local repo = (arg and arg[0] or ""):match("^(.*)/tools/release/") or "."

local fails = 0
local function check(ok, msg)
    if not ok then
        fails = fails + 1
        print("FAIL " .. msg)
    end
end

local function read(path)
    local f = assert(io.open(repo .. "/" .. path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function grab(path, header)
    local src = read(path)
    local start = src:find(header, 1, true)
    assert(start, header .. " not in " .. path)
    local stop = src:find("\nend\n", start, true)
    local chunk = assert(loadstring("local U, P = {}, {}\n" .. src:sub(start, stop + 4) .. "\nreturn U, P"))
    local U, P = chunk()
    return U.newer or P.newer
end

local env = {}
setfenv(assert(loadstring(read("assets/globals.lua"):match("^(.-\n.-\n.-\n)"))), env)()
check(type(env.OVERHAUL_VERSION) == "string" and env.OVERHAUL_VERSION:match("^%d+$") ~= nil, "OVERHAUL_VERSION is a plain build number: " .. tostring(env.OVERHAUL_VERSION))
check(env.OVERHAUL_NAME == "2.0 (pre-release)", "OVERHAUL_NAME is the shown name: " .. tostring(env.OVERHAUL_NAME))
check(env.VERSION == "V 2.0 (pre-release) - Overhaul", "VERSION shows the name: " .. tostring(env.VERSION))
local build = env.OVERHAUL_VERSION

local game_newer = grab("assets/functions/overhaul_update.lua", "function U.newer(a, b)")
local launcher_newer = grab("tools/release/launcher/feed.lua", "function P.newer(a, b)")
for name, newer in pairs({game = game_newer, launcher = launcher_newer}) do
    for _, old in ipairs({"2.4", "2.5", "2.6", "2.7", "2.99"}) do
        check(newer(build, old), name .. ": build " .. build .. " is newer than " .. old)
        check(not newer(old, build), name .. ": " .. old .. " is not newer than build " .. build)
    end
    check(newer(tostring(tonumber(build) + 1), build), name .. ": the next build is newer")
    check(not newer(build, build), name .. ": the same build is not newer")
end

check(tonumber(build) > 27, "the build number stays above every 2.x digit run")

local apk = read("tools/release/android/make_apk.py"):match("def version_code_for%(name%):(.-)\n\n")
check(apk ~= nil and apk:find("parts[0] * 10000", 1, true) ~= nil, "Android version code still grows with the first number")

_G.OVERHAUL_VERSION, _G.OVERHAUL_NAME = build, env.OVERHAUL_NAME
_G.mod_loc = function(s) return s end
local room_src = read("assets/multiplayer/bom_room.lua")
local vt_start = room_src:find("local build_loc = false", 1, true)
local vt_stop = room_src:find("\nend\n", vt_start, true)
local vt = assert(loadstring("local bom_room = {}\n" .. room_src:sub(vt_start, vt_stop + 4) .. "\nreturn bom_room.version_text"))()
check(vt(build) == "V 2.0 (pre-release)", "MP: own build shows its name, got " .. tostring(vt(build)))
check(vt("2.7") == "V 2.7", "MP: an old 2.x client shows its version")
check(vt("31") == "build 31", "MP: another build shows its number")

if fails == 0 then
    print("version: build " .. build .. " shown as " .. env.OVERHAUL_NAME .. ", all checks passed")
else
    os.exit(1)
end
