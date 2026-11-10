package.path = "assets/functions/?.lua;" .. package.path
love = {data = {decompress = function() error("no zlib here") end}}
local SIO = require("save_io")

local fails = 0
local function check(name, ok)
    if not ok then
        fails = fails + 1
        print("FAIL " .. name)
    end
end

check("crc32", SIO.crc32("123456789") == 0xCBF43926)
check("crc32 empty", SIO.crc32("") == 0)

local prof = 'return {["name"]="Gab",["career_stats"]={["c_wins"]=4,["c_rounds"]=30}}'
local files = {
    ["Balatro/1/profile.jkr"] = prof,
    ["Balatro/1/meta.jkr"] = 'return {["unlocked"]={}}',
    ["Balatro/2/meta.jkr"] = 'return {}',
    ["Balatro/settings.jkr"] = 'return {["mp_player_key"]="x"}',
    ["Balatro/bot/keys.lua"] = "return {}",
    ["Balatro/achievement_data_1.jkr"] = "return {}",
    ["__MACOSX/Balatro/1/._profile.jkr"] = "junk",
}
local data = SIO.zip(SIO.entries(files))
local back, list = SIO.unzip(data)
check("unzip", back ~= nil and #list == 7)
for k, v in pairs(files) do
    check("roundtrip " .. k, back[k] == v)
end
local n = SIO.normalize(back)
check("normalize profile", n["1/profile.jkr"] == prof)
check("normalize keeps extras", n["achievement_data_1.jkr"] ~= nil)
check("normalize drops settings", n["settings.jkr"] == nil)
check("normalize drops keys", n["bot/keys.lua"] == nil)
check("normalize drops macosx", next(n) and n["__MACOSX/Balatro/1/._profile.jkr"] == nil)
local slots = SIO.check(n)
check("check slots", slots and #slots == 2 and slots[1] == "1" and slots[2] == "2")
local info = SIO.describe(n)
check("describe", info[1].name == "Gab" and info[1].wins == 4 and info[1].rounds == 30)
check("bad check", SIO.check({["1/profile.jkr"] = "garbage"}) == nil)
check("no profile", select(2, SIO.normalize({["x.txt"] = "a"})) == "no_profile")
check("not zip", select(2, SIO.unzip("hello")) == "not_zip")
local v = SIO.vanilla_only({["1/profile.jkr"] = "a", ["1/save.jkr"] = "b", ["1/meta.jkr"] = "c"})
check("vanilla only", v["1/save.jkr"] == nil and v["1/profile.jkr"] == "a" and v["1/meta.jkr"] == "c")
check("skip", SIO.skip("settings.jkr") and SIO.skip("backups/a.zip") and SIO.skip("mp_connection.log") and not SIO.skip("1/profile.jkr"))

if fails == 0 then
    print("save_io: all passed")
else
    os.exit(1)
end
