package.path = "tools/release/launcher/?.lua;" .. package.path
local MF = require("modfiles")

local files, dirs = {}, {}
local fs = {}
function fs.getInfo(p)
    if dirs[p] then return {type = "directory"} end
    if files[p] then return {type = "file"} end
end
function fs.read(p) return files[p] end
function fs.write(p, d) files[p] = d return true end
function fs.remove(p) files[p] = nil dirs[p] = nil return true end
function fs.createDirectory(p) dirs[p] = true end
function fs.getDirectoryItems(p)
    local out, seen = {}, {}
    local prefix = p .. "/"
    for k in pairs(files) do
        if k:sub(1, #prefix) == prefix then
            local n = k:sub(#prefix + 1):match("^[^/]+")
            if not seen[n] then seen[n] = true out[#out + 1] = n end
        end
    end
    for k in pairs(dirs) do
        if k:sub(1, #prefix) == prefix then
            local n = k:sub(#prefix + 1):match("^[^/]+")
            if not seen[n] then seen[n] = true out[#out + 1] = n end
        end
    end
    return out
end

local fails = 0
local function check(name, ok)
    if not ok then fails = fails + 1 print("FAIL " .. name) end
end

dirs["mods"] = true
dirs["mods/Cryptid"] = true
files["mods/Cryptid/Cryptid.json"] = '{"id": "Cryptid", "name": "Cryptid Mod"}'
files["mods/Cryptid/main.lua"] = "x"
dirs["mods/Plain"] = true
files["mods/Plain/main.lua"] = "x"
dirs["mods/.cache"] = true
dirs["mods/lovely"] = true
dirs["mods/Steamodded"] = true
files["mods/Steamodded/src/preflight/loader.lua"] = "x"
files["mods/enabled.txt"] = "Cryptid\n"

local list = MF.list(fs)
check("list count", #list == 2)
check("list name", list[1].name == "Cryptid Mod" and list[1].enabled)
check("list fallback", list[2].name == "Plain" and not list[2].enabled)

check("disable", MF.set_enabled(fs, "Cryptid", false))
check("disabled list", not MF.list(fs)[1].enabled and files["mods/Cryptid/.lovelyignore"] == "")
check("enable", MF.set_enabled(fs, "Plain", true))
check("enabled file", files["mods/enabled.txt"] == "Plain\n")
check("enable clears ignore", (MF.set_enabled(fs, "Cryptid", true)) and files["mods/Cryptid/.lovelyignore"] == nil)
check("bad names", not MF.set_enabled(fs, "../x", true) and not MF.remove(fs, "..") and not MF.remove(fs, "lovely") and not MF.remove(fs, ".cache"))

check("remove", MF.remove(fs, "Cryptid"))
check("removed gone", fs.getInfo("mods/Cryptid") == nil and files["mods/Cryptid/main.lua"] == nil)
check("removed from enabled", not (files["mods/enabled.txt"] or ""):find("Cryptid"))
check("list after remove", #MF.list(fs) == 1)

check("modded false", not MF.modded(fs))
files["mods/session.txt"] = "modded\n"
check("modded true", MF.modded(fs))

check("no trouble", not MF.trouble(fs))
files["mods/.running.txt"] = "2026 mods A\n"
check("trouble running", MF.trouble(fs))
files["mods/.running.txt"] = "2026 mods A\ntitle\n"
check("no trouble after title", not MF.trouble(fs))
files["mods/.boot_crashes.txt"] = "1"
check("trouble crashes", MF.trouble(fs))

check("safe pending none", not MF.safe_pending(fs))
check("safe start", MF.safe_start(fs) and MF.safe_pending(fs))

if fails == 0 then print("modfiles: all checks passed") end
os.exit(fails == 0 and 0 or 1)
