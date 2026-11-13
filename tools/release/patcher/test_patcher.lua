package.path = "tools/release/?.lua;" .. package.path
local F = require("patcher.find")
local A = require("patcher.apply")
local Z = require("patcher.zipread")

local p = F.library_paths([["libraryfolders" { "0" { "path"		"C:\\Program Files (x86)\\Steam" } "1" { "path" "D:\\SteamLibrary" } }]])
assert(p[1] == "C:\\Program Files (x86)\\Steam" and p[2] == "D:\\SteamLibrary", "vdf paths")

local win_env = function(k)
    return ({["ProgramFiles(x86)"] = "C:\\Program Files (x86)"})[k]
end
assert(F.steam_roots("Windows", win_env)[1] == "C:\\Program Files (x86)/Steam", "windows root")
local files = {["D:/SteamLibrary/steamapps/common/Balatro/Balatro.exe"] = 56000000}
local found = F.scan("Windows", win_env, function(path)
    if path:find("x86", 1, true) and path:find("steamapps/libraryfolders.vdf", 1, true) then
        return [["path" "D:\\SteamLibrary"]]
    end
end, function(path)
    return files[(path:gsub("\\", "/"))]
end)
assert(#found == 1 and found[1].path:find("SteamLibrary", 1, true), "windows library scan")

local mac_game = "/Users/x/Library/Application Support/Steam/steamapps/common/Balatro/Balatro.app/Contents/Resources/Balatro.love"
local mac = F.scan("OS X", function(k)
    return k == "HOME" and "/Users/x" or nil
end, function() end, function(path)
    return path == mac_game and 5e7 or nil
end)
assert(#mac == 1, "mac scan")

local lin = F.scan("Linux", function(k)
    return k == "HOME" and "/home/x" or nil
end, function() end, function(path)
    if path:find("/home/x/.local/share/Steam/", 1, true) or path:find("/home/x/.steam/steam/", 1, true) then
        if path:find("Balatro.exe", 1, true) then
            return 5e7
        end
    end
end)
assert(#lin == 1, "linux symlinked roots are one copy")

local function utf16(str)
    return (str:gsub(".", "%0\0")) .. "\0\0"
end
local groot = "RGBX\1\0\0\0" .. utf16("Games\\Xbox")
assert(F.gaming_root(groot)[1] == "Games\\Xbox", "gaming root parse")
assert(#F.gaming_root("nope") == 0, "gaming root junk")
local xb = F.scan("Windows", win_env, function(path)
    if path == "E:/.GamingRoot" then
        return groot
    end
end, function(path)
    return ({["D:/XboxGames/Balatro/Content/Balatro.exe"] = 5e7 + 1})[path]
end, nil, {"C", "D", "E"})
assert(#xb == 1 and xb[1].where == "xbox" and xb[1].path == "D:/XboxGames/Balatro/Content/Balatro.exe", "xbox default folder")
local xl = F.scan("Windows", win_env, function(path)
    if path == "E:/.GamingRoot" then
        return groot
    end
end, function(path)
    return ({["E:/Games/Xbox/Balatro Game Pass/Content/main.lua"] = 900, ["E:/Games/Xbox/Balatro Game Pass/Content/version.jkr"] = 20})[path]
end, function(pat)
    if pat == "E:/Games/Xbox/*" then
        return {"Forza", "Balatro Game Pass"}
    end
end, {"C", "E"})
assert(#xl == 1 and xl[1].loose and xl[1].path == "E:/Games/Xbox/Balatro Game Pass/Content", "xbox custom root, loose files")
local xp = F.scan("Windows", function(k)
    return k == "LOCALAPPDATA" and "C:\\Users\\x\\AppData\\Local" or win_env(k)
end, function() end, function() end, function(pat)
    if pat:find("Packages", 1, true) then
        return {"Microsoft.Photos_8wekyb3d8bbwe", "PlaystackLtd.Balatro_abc123"}
    end
end, {"C"})
assert(#xp == 1 and xp[1].protected and xp[1].package == "PlaystackLtd.Balatro_abc123", "store copy is protected")

local function win_tree(files, dirs, regs, env)
    local fs, ls = {}, {}
    local function norm(path)
        return (path:gsub("\\", "/"):gsub("/+", "/"):lower())
    end
    for k, v in pairs(files) do
        fs[norm(k)] = v
    end
    for k, v in pairs(dirs or {}) do
        ls[norm(k)] = v
    end
    local e = {["ProgramFiles(x86)"] = "C:\\Program Files (x86)", ProgramFiles = "C:\\Program Files",
        ProgramW6432 = "C:\\Program Files", LOCALAPPDATA = "C:\\Users\\g\\AppData\\Local"}
    for k, v in pairs(env or {}) do
        e[k] = v
    end
    local probes = 0
    return function(k)
        return e[k]
    end, function(path)
        local v = fs[norm(path)]
        return type(v) == "string" and v or nil
    end, function(path)
        probes = probes + 1
        local v = fs[norm(path)]
        return type(v) == "number" and v or (type(v) == "string" and #v or nil)
    end, function(pat)
        return ls[norm(pat)]
    end, function(hive, key, value)
        return (regs or {})[hive .. "\\" .. key .. "\\" .. value]
    end, function()
        return probes
    end
end
local function win_scan(files, dirs, regs, drives, env)
    local g, r, s, d, reg = win_tree(files, dirs, regs, env)
    return F.scan("Windows", g, r, s, d, drives or {"C", "D"}, reg)
end
local STORE = {["C:/Program Files/WindowsApps/*"] = {"PlaystackLtd.Balatro_1.0.1.0_x64__abc"},
    ["C:/Users/g/AppData/Local/Packages/*"] = {"Microsoft.Photos_8wekyb3d8bbwe", "PlaystackLtd.Balatro_abc"}}
local EXE = 56000000

local w = win_scan({["D:/Steam/steamapps/common/Balatro/Balatro.exe"] = EXE}, STORE,
    {["HKCU\\Software\\Valve\\Steam\\SteamPath"] = "d:/steam"})
assert(#w == 2 and w[1].where == "steam" and w[1].path:lower():find("d:/steam", 1, true) and w[2].protected, "steam on D: from HKCU SteamPath, store copy last")
w = win_scan({["E:/Program Files (x86)/Steam/steamapps/common/Balatro/Balatro.exe"] = EXE}, nil,
    {["HKLM\\SOFTWARE\\WOW6432Node\\Valve\\Steam\\InstallPath"] = "E:\\Program Files (x86)\\Steam\\"}, {"C"})
assert(#w == 1 and w[1].path:find("^E:"), "steam root from HKLM WOW6432Node, drive not in the list")
w = win_scan({["X:/Valve/steamapps/common/Balatro/Balatro.exe"] = EXE}, nil,
    {["HKLM\\SOFTWARE\\Valve\\Steam\\InstallPath"] = "X:\\Valve"}, {"C"})
assert(#w == 1 and w[1].path:find("^X:"), "steam root from HKLM 64 bit key")
w = win_scan({["C:/Program Files (x86)/Steam/steamapps/libraryfolders.vdf"] = '"libraryfolders"\n{\n\t"0"\n\t{\n\t\t"path"\t\t"C:\\\\Program Files (x86)\\\\Steam"\n\t}\n\t"1"\n\t{\n\t\t"path"\t\t"F:\\\\SteamLibrary"\n\t}\n}',
    ["F:/SteamLibrary/steamapps/common/Balatro/Balatro.exe"] = EXE}, STORE, nil, {"C"})
assert(#w == 2 and w[1].path:find("^F:\\SteamLibrary") and w[2].protected, "microSD library from libraryfolders.vdf")
w = win_scan({["G:/SteamLibrary/steamapps/common/Balatro/Balatro.exe"] = EXE}, STORE, nil, {"C", "G"})
assert(#w == 2 and w[1].path:find("^G:/SteamLibrary"), "library found on a drive with no registry and no vdf")
w = win_scan({["Q:/Games/Steam/steamapps/libraryfolders.vdf"] = '"path" "S:\\\\Lib"', ["S:/Lib/steamapps/common/Balatro/Balatro.exe"] = EXE},
    nil, {["HKCU\\Software\\Valve\\Steam\\SteamPath"] = "q:/games/steam"}, {"C"})
assert(#w == 1 and w[1].path:find("^S:\\Lib"), "libraries listed by a registry root are followed")
w = win_scan({["H:/Odd/Place/Balatro.exe"] = EXE}, nil,
    {["HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Steam App 2379780\\InstallLocation"] = "H:\\Odd\\Place"}, {"C"})
assert(#w == 1 and w[1].where == "steam" and w[1].path:gsub("\\", "/"):find("^H:/Odd/Place/Balatro.exe"), "Balatro's own uninstall key")
w = win_scan({["D:/SteamLibrary/steamapps/appmanifest_2379780.acf"] = '"AppState" { "appid" "2379780" "installdir" "Balatro Game" }',
    ["D:/SteamLibrary/steamapps/common/Balatro Game/Balatro.exe"] = EXE}, nil, nil, {"D"})
assert(#w == 1 and w[1].path:find("Balatro Game", 1, true), "installdir from the app manifest")
w = win_scan({["C:/Program Files (x86)/Steam/steamapps/common/Balatro/Balatro.exe"] = EXE}, nil,
    {["HKCU\\Software\\Valve\\Steam\\SteamPath"] = "c:/program files (x86)/steam",
     ["HKLM\\SOFTWARE\\WOW6432Node\\Valve\\Steam\\InstallPath"] = "C:\\Program Files (x86)\\Steam"})
assert(#w == 1, "one Steam copy when the registry and Program Files name the same folder")
w = win_scan({["C:/XboxGames/Balatro/Content/Balatro.exe"] = EXE + 7, ["D:/Steam/steamapps/common/Balatro/Balatro.exe"] = EXE},
    STORE, {["HKCU\\Software\\Valve\\Steam\\SteamPath"] = "D:/Steam"})
assert(#w == 2 and w[1].where == "steam" and w[2].where == "xbox" and not w[2].protected, "Steam and an XboxGames copy, both usable")
w = win_scan({}, STORE)
assert(#w == 1 and w[1].protected and w[1].package == "PlaystackLtd.Balatro_1.0.1.0_x64__abc", "only the protected store copy")
w = win_scan({}, {["C:/Users/g/AppData/Local/Packages/*"] = STORE["C:/Users/g/AppData/Local/Packages/*"]})
assert(#w == 1 and w[1].protected, "WindowsApps cannot be listed, the Packages folder still tells")
assert(F.clean_dir(' "D:\\Steam\\" ') == "D:\\Steam" and F.clean_dir("E:\\") == "E:/" and F.clean_dir("") == nil, "clean registry dirs")
local probes
local g0, r0, s0, d0, reg0
g0, r0, s0, d0, reg0, probes = win_tree({})
F.scan("Windows", g0, r0, s0, d0, {"C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z"}, reg0)
assert(probes() < 4000, "drive search stays small: " .. probes())

local l, crlf, final = A.split_lines("a\r\nb\r\n")
assert(crlf and final and #l == 2, "crlf split")
l, crlf, final = A.split_lines("a\nb")
assert(not crlf and not final and #l == 2, "lf split")
l = A.split_lines("")
assert(#l == 0, "empty split")

local base = {"keep", "  drop this vanilla line here", "x"}
local out = A.apply_bop("BOP 1\neol lf\nfinal 1\nbase 1\nc 1\ns 1\nl 1\nnew line\nr 1 2 %09 -\nend\n", function()
    return base
end)
assert(out == "keep\nnew line\n\tdrop this vanilla line here\n", "bop apply")
assert(A.apply_bop("BOP 1\neol crlf\nfinal 0\nbase 0\nl 2\na\nb\nend\n", function() end) == "a\r\nb", "bop crlf")
assert(A.apply_bop("BOP 3\n", function() end) == nil, "bad header")
assert(A.apply_bop("BOP 1\neol lf\nfinal 1\nbase 1\ne 1 2 - - =4\nend\n", function() return base end) == nil, "edit needs format 2")
out = A.apply_bop("BOP 2\neol lf\nfinal 1\nbase 1\ne 1 2 %20%20 - =5,-4,+%6B%65%65%70,=18\nend\n", function() return base end)
assert(out == "  drop keep vanilla line here\n", "bop edit")
assert(A.apply_bop("BOP 2\neol lf\nfinal 1\nbase 1\ne 1 2 - - =5\nend\n", function() return base end) == nil, "edit must use the whole line")
assert(A.apply_bop("BOP 2\neol lf\nfinal 1\nbase 1\ne 1 2 - - =99\nend\n", function() return base end) == nil, "edit past end")
assert(A.load_manifest("return {format = 2, files = {}}") ~= nil, "manifest format 2")
assert(A.load_manifest("return {format = 3, files = {}}") == nil, "manifest format 3")
assert(A.apply_bop("BOP 1\neol lf\nfinal 1\nbase 1\nc 9\nend\n", function() return base end) == nil, "copy past end")
assert(A.load_manifest("os.exit(1)") == nil, "manifest sandbox")
assert(A.load_manifest("return {format = 1, files = {}}") ~= nil, "manifest ok")
assert(Z.open("not a zip at all, just text padding padding", function() end) == nil, "not zip")

local van = {"alpha = 1", "beta = 2", "gamma = 3", "delta = 4"}
local van_hashes = {}
for i, l in ipairs(van) do van_hashes[i] = string.format("%06x", A.line_hash(l)) end
local mixed = A.drift_lines("alpha = 1\r\nbeta = 2\nextra = 9\r\ngamma = 3\r\ndelta = 4\r\n", table.concat(van_hashes))
assert(mixed[1] == "alpha = 1" and mixed[2] == "beta = 2" and mixed[3] == "gamma = 3" and mixed[4] == "delta = 4", "drift with mixed line endings")
out = A.apply_bop("BOP 1\neol lf\nfinal 1\nbase 1\nc 4\nl 1\nours\nend\n", function() return mixed end)
assert(out == "alpha = 1\nbeta = 2\nextra = 9\ngamma = 3\ndelta = 4\nours\n", "mixed line endings keep the player's extra line")

local gap = A.align({1, 2, 9, 3, 9, 4}, {1, 2, 9, 7, 3, 9, 4})
assert(gap[3] == 3 and gap[4] == 5 and gap[5] == 6, "drift maps lines inside a gap that grew")
local gap2 = A.align({1, 2, 9, 8, 6, 3}, {1, 2, 9, 5, 3})
assert(gap2[3] == 3 and gap2[4] == nil and gap2[5] == nil, "drift maps the kept line of a gap that shrank")
local holes = setmetatable({}, {__index = function(_, i) return ({[1] = "one", [3] = "three"})[i] end})
local bop = "BOP 2\neol lf\nfinal 1\nbase 0\nr 1 1 %20%20 -\nr 1 2 %20%20 -\ne 1 3 - - =5,+!\nend\n"
assert(A.apply_bop(bop, function() return holes end) == nil, "a missing line still stops a strict build")
assert(A.apply_bop(bop, function() return holes end, true) == "  one\n\nthree!\n", "lenient build leaves a missing line blank")

print("patcher tests ok")
