local here = (arg and arg[0] or ""):match("^(.*)/test/") or "."
local repo = here .. "/../../.."
package.path = here .. "/?.lua;" .. package.path
local opened = {}
love = {system = {openURL = function(u) opened[#opened + 1] = u return true end}}
local N = require("news")

local fails = 0
local function check(ok, msg)
    if not ok then
        fails = fails + 1
        print("FAIL " .. msg)
    end
end

local f = assert(io.open(repo .. "/assets/CHANGELOG.md", "rb"))
local md = f:read("*a")
f:close()

for _, lang in ipairs({"en", "fr", "es"}) do
    local text = N.md_block(md, "2.0.4", lang)
    check(text ~= nil, "2.0.4 block " .. lang)
    local d = N.parse(text)
    check(d.title and d.title:find("2.0.4", 1, true), "title " .. lang)
    check(#d.groups >= 5, "groups " .. lang .. " " .. #d.groups)
    local n = 0
    for _, g in ipairs(d.groups) do n = n + #g.lines end
    check(n == 14, "14 lines " .. lang .. " got " .. n)
    check(not text:find("\226\128\148", 1, true), "no em dash " .. lang)
end
check(N.parse(N.md_block(md, "2.0.4", "en")).groups[1].title == "Security", "Security first")
check(N.md_block(md, "2.0.4", "de") == N.md_block(md, "2.0.4", "en"), "unknown language falls back to English")
check(N.md_block(md, "9.9.9", "en") == nil, "unknown version has no notes")
check(N.md_block(md, "2.0.3 (pre-release)", "en"):find("ONLINE", 1, true) ~= nil, "version names with a suffix match")

local old = N.from_feed({changelog = function(e, l) return e.changelog[l] end}, {version = "57", changelog = {en = "New jokers and fixes."}}, "en")
check(old and #old.groups == 1 and old.groups[1].lines[1] == "New jokers and fixes.", "plain text feeds still show")

check(N.after_due(nil, "2.0.4") == true, "first start of the new launcher shows the notes")
check(N.after_due("2.0.4", "2.0.4") == false, "second start does not")
check(N.after_due("2.0.3", "2.0.4 (pre-release)") == true, "an update shows the notes")
check(N.after_due(nil, nil) == false, "nothing installed shows nothing")

check(N.open(N.DISCORD) and opened[1] == "https://discord.gg/uu4pu8NySP", "Discord link")
check(N.open(N.GITHUB) and opened[2] == "https://github.com/JupiterianSoul/Balatro-Overhaul", "GitHub link")
check(not N.open("http://discord.gg/x") and not N.open("file:///etc/passwd") and not N.open("https://x.y/a b") and #opened == 2, "only https links open")

print(string.format("news: %d failures", fails))
os.exit(fails == 0 and 0 or 1)
