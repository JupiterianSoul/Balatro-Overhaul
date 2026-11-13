local SIO = require("save_io")
local C = require("core")
local V = require("saves")

local FIX = os.getenv("SAVES_FIX")
local STEAM = FIX .. "/steam/Balatro"
local REAL = FIX .. "/real"
local fails, passes = 0, 0

local function check(name, ok, extra)
    if ok then
        passes = passes + 1
        print("PASS " .. name .. (extra and ("  " .. extra) or ""))
    else
        fails = fails + 1
        print("FAIL " .. name .. (extra and ("  " .. extra) or ""))
    end
end

local function readf(p)
    local f = io.open(p, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
end

local function writef(p, d)
    local f = assert(io.open(p, "wb"))
    f:write(d)
    f:close()
end

local function ohl(name)
    return V.with_overhaul(function(fs)
        return fs.getInfo(name) and fs.read(name) or nil
    end)
end

local function own(name)
    return V.with_overhaul(function(fs)
        return fs.getInfo(name) and fs.getRealDirectory(name) == fs.getSaveDirectory() or false
    end)
end

local function ohl_write(name, data)
    return V.with_overhaul(function(fs)
        if data == nil then return fs.remove(name) end
        return fs.write(name, data)
    end)
end

local function backups()
    local out = {}
    for _, n in ipairs(love.filesystem.getDirectoryItems(V.BACKUPS)) do
        if n:match("%.zip$") then out[#out + 1] = n end
    end
    table.sort(out)
    return out
end

local function unzip_file(p)
    return SIO.unzip(love.filesystem.read(p) or "")
end

local function tree_hash(dir)
    local h = io.popen("cd '" .. dir .. "' && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum")
    local s = h:read("*a")
    h:close()
    return s
end

local orig = {}
for _, f in ipairs({"1/profile.jkr", "1/meta.jkr"}) do orig[f] = readf(REAL .. "/" .. f) end
check("fixture has a real Steam profile", orig["1/profile.jkr"] and orig["1/meta.jkr"] and #orig["1/meta.jkr"] > 1000,
    "profile " .. #(orig["1/profile.jkr"] or "") .. " B, meta " .. #(orig["1/meta.jkr"] or "") .. " B")

local found = V.find({})
local steam
for _, s in ipairs(found) do if s.where == "steam" then steam = s end end
check("Steam save found", steam ~= nil)

local n, err = V.load(steam.files, "balatro")
check("Steam save loaded into the Overhaul", n ~= nil, tostring(n or err))
for f, d in pairs(orig) do
    check("in: " .. f .. " byte-equal", ohl(f) == d)
end

local played = "return {[\"overhaul_played\"]=true}"
local mine = SIO.zip(SIO.entries({["1/profile.jkr"] = played, ["1/meta.jkr"] = orig["1/meta.jkr"]}))
local tmpzip = FIX .. "/played.zip"
writef(tmpzip, mine)
local pf = V.read_import(tmpzip)
V.load(pf, "file")
check("Overhaul progress changed", ohl("1/profile.jkr") == played)
local steam_save_before = readf(STEAM .. "/1/save.jkr")
local before = #backups()
local out_n, out_err = V.export_to(steam)
check("first EXPORT HERE press writes", out_n == 2, tostring(out_n or out_err))
check("out: profile in Steam = Overhaul bytes", readf(STEAM .. "/1/profile.jkr") == played)
check("out: meta in Steam = Overhaul bytes", readf(STEAM .. "/1/meta.jkr") == orig["1/meta.jkr"])
check("out: Steam run save untouched", readf(STEAM .. "/1/save.jkr") == steam_save_before)
local bl = backups()
check("out: Steam save zipped first", #bl == before + 1)
local sb
for _, b in ipairs(bl) do if b:match("^steam%-before%-export") then sb = b end end
local sback = sb and unzip_file(V.BACKUPS .. "/" .. sb)
check("out: backup holds the old Steam profile", sback and sback["1/profile.jkr"] == orig["1/profile.jkr"] and sback["1/save.jkr"] == steam_save_before)
check("no leftover temp file in Steam folder", readf(STEAM .. "/1/profile.jkr.overhaul-new") == nil)

writef(STEAM .. "/1/profile.jkr", orig["1/profile.jkr"])
local back_files = V.read_folder(STEAM)
V.load(back_files, "balatro")
for f, d in pairs(orig) do
    check("back in: " .. f .. " byte-equal to the real Steam save", ohl(f) == d)
end
V.export_to(steam)
for f, d in pairs(orig) do
    check("out again: Steam " .. f .. " byte-equal to the real save", readf(STEAM .. "/" .. f) == d)
end

local xb
for _, s in ipairs(V.find({})) do if s.where == "xbox" then xb = s end end
check("Xbox save found", xb ~= nil, xb and xb.path)
if xb then
    check("Xbox slot 1 profile byte-equal", xb.files["1/profile.jkr"] == orig["1/profile.jkr"])
    check("Xbox slot 1 meta byte-equal", xb.files["1/meta.jkr"] == orig["1/meta.jkr"])
    local x2 = readf(FIX .. "/xsrc/2/profile.jkr")
    check("Xbox slot 2 from a container named 2/profile.jkr", x2 ~= nil and xb.files["2/profile.jkr"] == x2)
    check("Xbox settings container ignored", xb.files["settings.jkr"] == nil)
    local info = SIO.describe(xb.files)
    check("Xbox profiles described", #info == 2, #info .. " profiles")
    local names = {}
    for _, p in ipairs(info) do names[#names + 1] = tostring(p.slot) .. "=" .. tostring(p.name) end
    check("Xbox row shows each profile once with its own name", #info == 2 and info[1].slot ~= info[2].slot and info[2].name == "Gab", table.concat(names, " "))
    local xhash = tree_hash(xb.path)
    check("EXPORT HERE refused for Xbox", select(2, V.export_to(xb)) == "read_only")
    local xn = V.load(xb.files, "xbox")
    check("Xbox save loads into the Overhaul", xn ~= nil and ohl("2/profile.jkr") == x2)
    check("Xbox folder unchanged after read, load and refused export", tree_hash(xb.path) == xhash)
    local idx = readf(xb.path .. "/containers.index")
    check("truncated index refused", V.xbox_index(idx:sub(1, 40)) == nil)
    check("absurd count refused", V.xbox_index(idx:sub(1, 4) .. "\255\255\255\127" .. idx:sub(9)) == nil)
    check("empty index refused", V.xbox_index("") == nil)
    check("container with absurd count refused", V.xbox_container("\4\0\0\0\255\255\0\0") == nil)
    local junk = {}
    for i = 1, 200 do
        local s = {}
        for k = 1, (i * 7) % 300 do s[k] = string.char((i * k * 31) % 256) end
        s = table.concat(s)
        local ok1 = pcall(V.xbox_index, s)
        local ok2 = pcall(V.xbox_container, s)
        local ok3 = pcall(V.xbox_index, idx:sub(1, (i * 13) % #idx))
        if not (ok1 and ok2 and ok3) then junk[#junk + 1] = i end
    end
    check("200 random or cut index files never crash", #junk == 0)
end

ohl_write(SIO.LOCK, SIO.lock_text(0, os.time()))
local cur = ohl("1/profile.jkr")
local rn, rerr = V.load(steam.files, "balatro")
check("load refused while the game runs", rn == nil and rerr == "running")
pf = V.read_import(tmpzip)
rn, rerr = V.load(pf, "file")
check("import refused while the game runs", rn == nil and rerr == "running")
check("save untouched while refused", ohl("1/profile.jkr") == cur)
ohl_write(SIO.LOCK, SIO.lock_text(0, os.time() - 120))
rn = V.load(steam.files, "balatro")
check("stale lock after a crash does not lock the player out", rn ~= nil)
ohl_write(SIO.LOCK, SIO.lock_text(999999, os.time()))
rn = V.load(steam.files, "balatro")
check("fresh lock of a dead process is ignored (Linux)", rn ~= nil)
ohl_write(SIO.LOCK, nil)

local start = backups()
local seen = {}
for _, b in ipairs(start) do seen[b] = true end
local made = 0
for i = 1, 30 do
    local files = V.read_import(i % 2 == 0 and tmpzip or STEAM)
    local k = V.load(files, "file")
    if k then made = made + 1 end
end
local after = backups()
local all_there = true
for b in pairs(seen) do
    if not love.filesystem.getInfo(V.BACKUPS .. "/" .. b) then all_there = false end
end
local good = 0
for _, b in ipairs(after) do
    local t = unzip_file(V.BACKUPS .. "/" .. b)
    if t and next(t) then good = good + 1 end
end
check("30 imports in a row all loaded", made == 30, made .. "/30")
check("30 imports made 30 new backups", #after == #start + 30, #start .. " -> " .. #after)
check("every older backup still there", all_there)
check("every backup zip reads back", good == #after, good .. "/" .. #after)

local evil = SIO.zip(SIO.entries({
    ["Balatro/1/profile.jkr"] = orig["1/profile.jkr"],
    ["Balatro/../../evil.jkr"] = "return {}",
    ["Balatro/main.lua"] = "os.exit(3)",
    ["Balatro/functions/button_callbacks.lua"] = "os.exit(3)",
    ["Balatro/card.lua"] = "os.exit(3)",
    ["Balatro/x.dll"] = "MZ",
    ["Balatro/1/../../escape.jkr"] = "return {}",
    ["Balatro/run_history.lua"] = "return {}",
}))
writef(FIX .. "/evil.zip", evil)
local ef = V.read_import(FIX .. "/evil.zip")
local en = ef and V.load(ef, "file")
check("zip with traversal and code loads only save data", en == 3, tostring(en))
check("modded twin of the imported profile written", ohl("modded/profile.jkr") == orig["1/profile.jkr"])
check("no main.lua planted", not own("main.lua") and not own("functions/button_callbacks.lua") and not own("card.lua") and not own("x.dll"))
check("nothing escaped the save folder", readf(os.getenv("XDG_DATA_HOME") .. "/evil.jkr") == nil and readf(os.getenv("XDG_DATA_HOME") .. "/love/evil.jkr") == nil)
check("data .lua kept", ohl("run_history.lua") == "return {}")
for _, bad in ipairs({"../a.jkr", "/etc/x", "C:/x", "a\\b", "1/./profile.jkr", "1//profile.jkr", "engine/x.lua", "conf.lua", "a.so"}) do
    check("unsafe name refused: " .. bad, SIO.unsafe(bad))
end
for _, ok in ipairs({"1/profile.jkr", "achievement_data_1.jkr", "jimbo_jam/a.lua", "forge_cards/x.png", "minigames.lua"}) do
    check("save name allowed: " .. ok, not SIO.unsafe(ok))
end
local cap = SIO.MAX_TOTAL
SIO.MAX_TOTAL = 4000
writef(FIX .. "/withmods.zip", SIO.zip(SIO.entries({["Balatro/1/profile.jkr"] = orig["1/profile.jkr"], ["Balatro/Mods/big.bin"] = string.rep("x", 5000)})))
writef(FIX .. "/bigsave.zip", SIO.zip(SIO.entries({["Balatro/1/profile.jkr"] = orig["1/profile.jkr"], ["Balatro/big.bin"] = string.rep("x", 5000)})))
check("Balatro folder zipped with its Mods folder still imports", SIO.unzip(readf(FIX .. "/withmods.zip"), nil, SIO.save_entry) ~= nil)
check("save over the size cap refused", select(2, SIO.unzip(readf(FIX .. "/bigsave.zip"), nil, SIO.save_entry)) == "too_big")
check("Overhaul folder zipped whole still imports", SIO.normalize(SIO.unzip(SIO.zip(SIO.entries({["Overhaul/modded/profile.jkr"] = orig["1/profile.jkr"]})), nil, SIO.save_entry))["modded/profile.jkr"] ~= nil)
SIO.MAX_TOTAL = cap
os.execute("truncate -s 200M '" .. FIX .. "/huge.zip'")
local hf, herr = V.read_import(FIX .. "/huge.zip")
check("200 MB file refused before reading", hf == nil and herr == "too_big")

ohl_write("1/profile.jkr", orig["1/profile.jkr"])
local bk = V.with_overhaul(function(fs) return SIO.with_touched(fs, steam.files, {}) end)
ohl_write("1/profile.jkr", "return {[\"changed\"]=1}")
local an, aerr = V.with_overhaul(function(fs) return SIO.apply(fs, steam.files, bk) end)
check("apply refuses a file that is not in the backup", an == nil and aerr == "changed")
check("refused apply removed nothing", ohl("1/profile.jkr") == "return {[\"changed\"]=1}")

local names = {}
for i = 1, 5 do names[i] = SIO.backup(love.filesystem, "same_second", "t", {["1/profile.jkr"] = "x" .. i}) end
local distinct = {}
for _, nm in ipairs(names) do if nm then distinct[nm] = true end end
local cnt = 0
for _ in pairs(distinct) do cnt = cnt + 1 end
check("five backups in the same second get five names", cnt == 5)

check("lock: fresh is alive", SIO.lock_alive(SIO.lock_text(1, 1000), 1010))
check("lock: 31 s old is stale", not SIO.lock_alive(SIO.lock_text(1, 1000), 1031))
check("lock: clock far ahead is stale", not SIO.lock_alive(SIO.lock_text(1, 2000), 1000))
check("lock: garbage is stale", not SIO.lock_alive("hello", 1000))

local bin = FIX .. "/bin"
local title = "Pick a 'save' \"now\" $(touch " .. FIX .. "/pwned) `id`"
local picked = FIX .. "/it's a save $x.zip"
writef(picked, mine)
local function wait(job)
    for _ = 1, 500 do
        local st, p = V.pick_poll(job)
        if st then return st, p end
        love.timer.sleep(0.01)
    end
end
local function run_pick(path, osn)
    local cmd = V.pick_command(osn, title)
    local h = io.popen("PATH='" .. path .. "' ; export PATH ; " .. cmd)
    local out = h:read("*a")
    h:close()
    return out
end
local zout = run_pick(bin .. "/z", "Linux")
check("zenity: picked path comes back as is", zout:gsub("\n$", "") == picked)
check("zenity: title passed as one argument", readf(FIX .. "/zenity_args.txt") == "--file-selection\n--title=" .. title .. "\n--file-filter=*.zip *.jkr\n")
local kout = run_pick(bin .. "/k", "Linux")
check("kdialog fallback works", kout:gsub("\n$", "") == picked)
local nout = run_pick(bin .. "/none", "Linux")
check("no dialog program: falls back", nout:match("rc:none") ~= nil)
local mout = run_pick(bin .. "/mac", "OS X")
check("osascript: picked path comes back", mout:gsub("\n$", "") == picked)
check("osascript: AppleScript string escaped", readf(FIX .. "/osascript_args.txt") ==
    "-e\nPOSIX path of (choose file with prompt \"Pick a 'save' \\\"now\\\" $(touch " .. FIX .. "/pwned) `id`\")\n")
check("no command ran from the title", readf(FIX .. "/pwned") == nil)
local wcmd = V.pick_command("Windows", title)
writef(FIX .. "/ps.txt", wcmd)
check("PowerShell command is fixed text without the title", not wcmd:find("EncodedCommand", 1, true)
    and not wcmd:find("touch", 1, true) and select(2, wcmd:gsub('"', "")) == 2)
local job = V.pick_start(title)
check("thread picker started", job ~= nil)
local st, p = wait(job)
check("thread picker returns the path (fake zenity in PATH)", st == "ok" and p == picked, tostring(st) .. " " .. tostring(p))
local imp = V.read_import(p)
check("picked file imports", imp ~= nil)

local function comp(str)
    return love.data.compress("string", "deflate", str, 1)
end
local van_meta = 'return {["unlocked"]={["j_joker"]=true,["j_greedy_joker"]=true,},["discovered"]={["j_joker"]=true,["j_greedy_joker"]=true,["j_lusty_joker"]=true,["c_mercury"]=true,},["alerted"]={},}'
local van_prof = 'return {["name"]="Steamy",["career_stats"]={["c_wins"]=7,["c_rounds"]=212,},}'
local van_run = 'return {["GAME"]={["round"]=9,["round_resets"]={["ante"]=3,},},}'
local van = {["1/profile.jkr"] = comp(van_prof), ["1/meta.jkr"] = comp(van_meta), ["1/save.jkr"] = comp(van_run)}
local pv = SIO.preview(van)
check("preview: profile name and wins", pv[1] and pv[1].name == "Steamy" and pv[1].wins == 7 and pv[1].rounds == 212)
check("preview: discovered and unlocked counted", pv[1] and pv[1].discovered == 4 and pv[1].unlocked == 2, pv[1] and (pv[1].discovered .. "/" .. pv[1].unlocked))
check("preview: run in progress", pv[1] and pv[1].run and pv[1].run.ante == 3 and pv[1].run.round == 9)
local mir = SIO.mirror_modded(van)
check("issue 19: vanilla import gets a modded twin", mir["modded/meta.jkr"] == van["1/meta.jkr"] and mir["modded/profile.jkr"] == van["1/profile.jkr"] and mir["modded/save.jkr"] == nil)
check("issue 19: preview hides the modded twin", #SIO.preview(mir) == 1)
local own_mod = SIO.mirror_modded({["1/profile.jkr"] = van["1/profile.jkr"], ["modded/profile.jkr"] = comp('return {["name"]="M"}')})
check("issue 19: an export with its own modded profile keeps it", SIO.read_jkr(own_mod["modded/profile.jkr"]).name == "M")
local vdir = FIX .. "/vanilla_steam/Balatro"
os.execute("mkdir -p '" .. vdir .. "/1'")
writef(vdir .. "/1/profile.jkr", van["1/profile.jkr"])
writef(vdir .. "/1/meta.jkr", van["1/meta.jkr"])
ohl_write("modded/profile.jkr", comp('return {["name"]="fresh"}'))
ohl_write("modded/meta.jkr", comp('return {["discovered"]={},["unlocked"]={},}'))
local vf = V.read_folder(vdir)
local vn = vf and V.load(vf, "balatro")
check("issue 19: Steam import reaches the modded profile too", vn and ohl("modded/meta.jkr") == van["1/meta.jkr"] and ohl("1/meta.jkr") == van["1/meta.jkr"])
local mm = SIO.read_jkr(ohl("modded/meta.jkr") or "") or {}
check("issue 19: collection discovered count survives the import", mm.discovered and mm.discovered.j_lusty_joker and mm.discovered.c_mercury)
local jf, jerr = V.read_import(vdir .. "/1/meta.jkr")
check("a .jkr picked inside a Steam slot folder reads the whole save", jf and jf["1/profile.jkr"] == van["1/profile.jkr"], tostring(jerr))
os.execute("mkdir -p '" .. FIX .. "/lone'")
writef(FIX .. "/lone/profile.jkr", van["1/profile.jkr"])
local lf = V.read_import(FIX .. "/lone/profile.jkr")
check("a lone profile.jkr imports as profile 1", lf and lf["1/profile.jkr"] == van["1/profile.jkr"])
writef(FIX .. "/lone/notes.txt", "hello")
check("a text file is refused as not a save", select(2, V.read_import(FIX .. "/lone/notes.txt")) == "not_zip")
local hostile = {
    {"code in profile.jkr", {["Balatro/1/profile.jkr"] = 'return os.execute("touch ' .. FIX .. '/pwned2")'}, "damaged"},
    {"endless loop in meta.jkr", {["Balatro/1/meta.jkr"] = "return (function() while true do end end)()"}, "damaged"},
    {"bytecode profile", {["Balatro/1/profile.jkr"] = string.dump(function() return {} end)}, "damaged"},
    {"compressed code in profile", {["Balatro/1/profile.jkr"] = comp('return {["x"]=io.open("/etc/passwd")}')}, "damaged"},
}
for _, h in ipairs(hostile) do
    local f, e = SIO.read_any(SIO.zip(SIO.entries(h[2])), "x.zip")
    check("hostile zip refused: " .. h[1], f == nil and e == h[3], tostring(e))
end
check("no hostile code ran", readf(FIX .. "/pwned2") == nil)
local mixed, merr, mmeta = SIO.read_any(SIO.zip(SIO.entries({["Balatro/1/profile.jkr"] = van["1/profile.jkr"], ["Balatro/1/save.jkr"] = 'if x then return {} end return {}',
    ["Balatro/run_history.lua"] = 'return {os.exit(3)}', ["Balatro/jimbo_jam/a.lua"] = 'return {["ok"]=true}'})), "m.zip")
check("non plain run and history left out, data kept", mixed and mixed["1/save.jkr"] == nil and mixed["run_history.lua"] == nil and mixed["jimbo_jam/a.lua"] ~= nil
    and mmeta and #mmeta.dropped == 2, tostring(merr))
local good = SIO.zip(SIO.entries({["Balatro/1/profile.jkr"] = van["1/profile.jkr"], ["Balatro/1/meta.jkr"] = van["1/meta.jkr"]}))
for _, cut in ipairs({10, 40, #good - 30, #good - 1}) do
    check("truncated zip refused at " .. cut .. " bytes", SIO.read_any(good:sub(1, cut), "t.zip") == nil)
end
local gf, _, gmeta = SIO.read_any(good, "g.zip")
check("good zip reads with a date", gf ~= nil and gmeta.when ~= nil and math.abs(gmeta.when - os.time()) < 3 * 86400)
check("export name is dated", SIO.export_name(os.time{year = 2026, month = 11, day = 11, hour = 12}) == "Balatro Overhaul save 2026-11-11.zip")
local scmd = V.save_command("Windows", title, "Balatro Overhaul save 2026-11-11.zip")
check("PowerShell save command is plain fixed text", not scmd:find("EncodedCommand", 1, true) and not scmd:find("touch", 1, true) and scmd:find("SaveFileDialog", 1, true) ~= nil)
check("save name cannot break out of the command", not V.save_command("Linux", "t", "a'; touch x; '.zip"):find("'; touch", 1, true))
local ex = V.export()
local sjob = ex and V.save_start(title, ex:match("[^/]+$"))
local sst, sp
if sjob then sst, sp = wait(sjob) end
check("save dialog returns the chosen path (fake zenity --save)", sst == "ok" and sp == os.getenv("SAVE_TO"), tostring(sst) .. " " .. tostring(sp))
check("export copied to the chosen place, byte-equal", sp and V.copy_out(ex, sp) and readf(sp) == readf(ex) and readf(sp .. ".part") == nil)
local before_run = ohl("1/profile.jkr")
writef(os.getenv("XDG_DATA_HOME") .. "/love/" .. C.GAME_FOLDER .. "/overhaul_running.lock", "1 " .. os.time() .. "\n")
local rf = V.read_import(FIX .. "/played.zip")
check("game still open: import refused", select(2, V.load(rf, "file")) == "running" and ohl("1/profile.jkr") == before_run)
os.remove(os.getenv("XDG_DATA_HOME") .. "/love/" .. C.GAME_FOLDER .. "/overhaul_running.lock")
love.filesystem.write(V.APP_RESULT, "ok\n+app_import.zip\n#0123456789abcdef0123456789abcdef\n@my save.zip\n")
local ar = V.app_result()
check("app result parsed", ar and ar.status == "ok" and ar.file == "app_import.zip" and ar.token == "0123456789abcdef0123456789abcdef" and ar.name == "my save.zip")
love.filesystem.write(V.APP_RESULT, "old\n")
check("old app answer parsed", V.app_result().status == "old")
love.filesystem.write(V.APP_RESULT, "ok\n>huge.zip\n")
check("too big pick parsed", V.app_result().status == "big")
check("no app bridge on PC", V.app_supported() == false and V.app_start("export") == false)
print(string.format("RESULT %d passed, %d failed", passes, fails))
love.event.quit(fails == 0 and 0 or 1)
