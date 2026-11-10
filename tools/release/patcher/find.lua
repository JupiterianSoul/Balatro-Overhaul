local F = {}

local GAME_FILES = {
    "steamapps/common/Balatro/Balatro.exe",
    "steamapps/common/Balatro/Balatro.app/Contents/Resources/Balatro.love",
    "steamapps/common/Balatro/Balatro.app/Contents/Resources/Game.love",
    "steamapps/common/Balatro/Balatro.love",
}

local DIR_FILES = {
    "Balatro.exe",
    "Balatro.love",
    "Game.love",
    "Balatro.app/Contents/Resources/Balatro.love",
    "Balatro.app/Contents/Resources/Game.love",
    "Contents/Resources/Balatro.love",
    "Contents/Resources/Game.love",
}

local function join(a, b)
    if a:sub(-1) == "/" or a:sub(-1) == "\\" then
        return a .. b
    end
    return a .. "/" .. b
end

F.STEAM_APP = "2379780"

F.STEAM_REG = {
    {"HKLM", "SOFTWARE\\WOW6432Node\\Valve\\Steam", "InstallPath"},
    {"HKLM", "SOFTWARE\\Valve\\Steam", "InstallPath"},
    {"HKCU", "Software\\Valve\\Steam", "SteamPath"},
    {"HKCU", "Software\\Valve\\Steam", "InstallPath"},
}

F.GAME_REG = {
    {"HKLM", "SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Steam App " .. F.STEAM_APP, "InstallLocation"},
    {"HKLM", "SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Steam App " .. F.STEAM_APP, "InstallLocation"},
    {"HKCU", "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Steam App " .. F.STEAM_APP, "InstallLocation"},
}

F.DRIVE_LIBS = {"SteamLibrary", "Steam", "Program Files (x86)/Steam", "Program Files/Steam", "Games/Steam",
    "Games/SteamLibrary", "SteamGames", "Steam Library", "Games"}

F.DEFAULT_DRIVES = {"C", "D", "E", "F", "G", "H"}

function F.clean_dir(p)
    if type(p) ~= "string" then
        return nil
    end
    p = p:gsub("%z.*$", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub('^"(.*)"$', "%1"):gsub("[/\\]+$", "")
    if p == "" then
        return nil
    end
    if p:match("^%a:$") then
        p = p .. "/"
    end
    return (p:gsub("^%a:", string.upper))
end

function F.reg_values(list, reg)
    local out = {}
    if not reg then
        return out
    end
    for _, q in ipairs(list) do
        local ok, v = pcall(reg, q[1], q[2], q[3])
        v = ok and F.clean_dir(v) or nil
        if v then
            out[#out + 1] = v
        end
    end
    return out
end

function F.steam_roots(os_name, getenv, reg)
    local home = getenv("HOME") or getenv("USERPROFILE") or ""
    local roots = {}
    if os_name == "Windows" then
        for _, p in ipairs(F.reg_values(F.STEAM_REG, reg)) do
            roots[#roots + 1] = p
        end
        for _, var in ipairs({"ProgramFiles(x86)", "ProgramFiles", "ProgramW6432"}) do
            local p = getenv(var)
            if p then
                roots[#roots + 1] = join(p, "Steam")
            end
        end
        roots[#roots + 1] = "C:/Program Files (x86)/Steam"
        roots[#roots + 1] = "C:/Program Files/Steam"
    elseif os_name == "OS X" then
        roots[#roots + 1] = join(home, "Library/Application Support/Steam")
    else
        local data = getenv("XDG_DATA_HOME")
        if data and data ~= "" then
            roots[#roots + 1] = join(data, "Steam")
        end
        roots[#roots + 1] = join(home, ".local/share/Steam")
        roots[#roots + 1] = join(home, ".steam/steam")
        roots[#roots + 1] = join(home, ".steam/root")
        roots[#roots + 1] = join(home, ".steam/debian-installation")
        roots[#roots + 1] = join(home, ".var/app/com.valvesoftware.Steam/.local/share/Steam")
        roots[#roots + 1] = join(home, "snap/steam/common/.local/share/Steam")
    end
    return roots
end

function F.library_paths(vdf)
    local out = {}
    for p in vdf:gmatch('"path"%s+"(.-)"') do
        out[#out + 1] = (p:gsub("\\\\", "\\"))
    end
    return out
end

function F.install_dir(acf)
    local d = acf and acf:match('"installdir"%s+"(.-)"')
    return d and d ~= "" and (d:gsub("\\\\", "\\")) or nil
end

function F.is_loose(dir, exists)
    return exists(join(dir, "main.lua")) and exists(join(dir, "version.jkr")) and true or false
end

function F.in_folder(dir, exists)
    for _, rel in ipairs(DIR_FILES) do
        local p = join(dir, rel)
        if exists(p) then
            return p
        end
    end
    for _, sub in ipairs({"", "Content"}) do
        local d = sub == "" and dir or join(dir, sub)
        if F.is_loose(d, exists) then
            return d, true
        end
    end
end

F.XBOX_NAMES = {"Balatro", "Balatro (PC)", "Balatro - PC", "Playstack.Balatro", "PlaystackLtd.Balatro"}

function F.gaming_root(data)
    if not data or #data < 10 or data:sub(1, 4) ~= "RGBX" then
        return {}
    end
    local out, cur = {}, {}
    for i = 9, #data - 1, 2 do
        local lo, hi = data:byte(i), data:byte(i + 1)
        if lo == 0 and hi == 0 then
            if #cur > 0 then
                out[#out + 1] = table.concat(cur)
                cur = {}
            end
        elseif hi == 0 and lo >= 32 and lo < 127 then
            cur[#cur + 1] = string.char(lo)
        else
            cur = {}
        end
    end
    if #cur > 0 then
        out[#out + 1] = table.concat(cur)
    end
    return out
end

function F.xbox_folders(drives, read_file)
    local out, seen = {}, {}
    for _, d in ipairs(drives) do
        local root = d:sub(1, 1):upper() .. ":/"
        local names = F.gaming_root(read_file(root .. ".GamingRoot"))
        names[#names + 1] = "XboxGames"
        for _, n in ipairs(names) do
            n = n:gsub("\\", "/"):gsub("^/+", ""):gsub("^%a:/", "")
            local p = root .. n
            if not seen[p:lower()] then
                seen[p:lower()] = true
                out[#out + 1] = p
            end
        end
    end
    return out
end

function F.scan_xbox(getenv, read_file, file_size, list_dir, drives)
    local found = {}
    local exists = function(p)
        return file_size(p) ~= nil
    end
    local dirs = {}
    for _, folder in ipairs(F.xbox_folders(drives or F.DEFAULT_DRIVES, read_file)) do
        local names = list_dir and list_dir(folder .. "/*") or nil
        if names then
            for _, n in ipairs(names) do
                if n:lower():find("balatro", 1, true) then
                    dirs[#dirs + 1] = join(folder, n)
                end
            end
        else
            for _, n in ipairs(F.XBOX_NAMES) do
                dirs[#dirs + 1] = join(folder, n)
            end
        end
    end
    for _, d in ipairs(dirs) do
        local p, loose = F.in_folder(join(d, "Content"), exists)
        if not p then
            p, loose = F.in_folder(d, exists)
        end
        if p then
            found[#found + 1] = {path = p, where = "xbox", loose = loose or nil}
        end
    end
    if #found == 0 and list_dir then
        local apps = join(getenv("ProgramW6432") or getenv("ProgramFiles") or "C:/Program Files", "WindowsApps")
        for _, n in ipairs(list_dir(apps .. "/*") or {}) do
            if n:lower():find("balatro", 1, true) then
                local p, loose = F.in_folder(join(apps, n), exists)
                found[#found + 1] = p and {path = p, where = "xbox", loose = loose or nil}
                    or {path = join(apps, n), where = "xbox", protected = true, package = n}
            end
        end
    end
    if #found == 0 and list_dir then
        local local_app = getenv("LOCALAPPDATA")
        local pkgs = local_app and list_dir(join(local_app, "Packages") .. "/*") or nil
        for _, n in ipairs(pkgs or {}) do
            if n:lower():find("balatro", 1, true) then
                found[#found + 1] = {path = join(join(local_app, "Packages"), n), where = "xbox", protected = true, package = n}
                break
            end
        end
    end
    return found
end

function F.scan(os_name, getenv, read_file, file_size, list_dir, drives, reg)
    local win = os_name == "Windows"
    local found, seen_path, seen_size = {}, {}, {}
    local function norm(p)
        local key = p:gsub("\\", "/"):gsub("/+", "/"):gsub("/$", "")
        return win and key:lower() or key
    end
    local function add(p, where)
        local key = norm(p)
        if seen_path[key] then
            return
        end
        seen_path[key] = true
        local size = file_size(p)
        if not size or size < 1024 then
            return
        end
        if seen_size[size] then
            return
        end
        seen_size[size] = true
        found[#found + 1] = {path = p, where = where, size = size}
    end
    local function add_entry(g)
        local key = norm(g.path)
        if not seen_path[key] then
            seen_path[key] = true
            found[#found + 1] = g
        end
    end
    local exists = function(p)
        return file_size(p) ~= nil
    end
    local function add_dir(dir, where)
        local p, loose = F.in_folder(dir, exists)
        if p and loose then
            add_entry({path = p, where = where, loose = true})
        elseif p then
            add(p, where)
        end
    end
    local libs, seen_lib = {}, {}
    local function add_lib(p)
        p = F.clean_dir(p)
        if not p then
            return
        end
        local key = norm(p)
        if not seen_lib[key] then
            seen_lib[key] = true
            libs[#libs + 1] = p
        end
    end
    for _, root in ipairs(F.steam_roots(os_name, getenv, reg)) do
        add_lib(root)
    end
    if win then
        for _, d in ipairs(drives or F.DEFAULT_DRIVES) do
            local letter = d:sub(1, 1):upper()
            for _, rel in ipairs(F.DRIVE_LIBS) do
                add_lib(letter .. ":/" .. rel)
            end
        end
    end
    local i = 1
    while i <= #libs do
        local lib = libs[i]
        for _, rel in ipairs({"steamapps/libraryfolders.vdf", "config/libraryfolders.vdf"}) do
            local vdf = read_file(join(lib, rel))
            if vdf then
                for _, p in ipairs(F.library_paths(vdf)) do
                    add_lib(p)
                end
            end
        end
        i = i + 1
    end
    if win then
        for _, dir in ipairs(F.reg_values(F.GAME_REG, reg)) do
            add_dir(dir, "steam")
        end
    end
    for _, lib in ipairs(libs) do
        for _, rel in ipairs(GAME_FILES) do
            add(join(lib, rel), "steam")
        end
        local sub = F.install_dir(read_file(join(lib, "steamapps/appmanifest_" .. F.STEAM_APP .. ".acf")))
        if sub then
            add_dir(join(lib, "steamapps/common/" .. sub), "steam")
        end
    end
    if win then
        for _, g in ipairs(F.scan_xbox(getenv, read_file, file_size, list_dir, drives)) do
            if g.loose or g.protected then
                add_entry(g)
            else
                add(g.path, "xbox")
            end
        end
    end
    local out = {}
    for _, g in ipairs(found) do
        if not g.protected then
            out[#out + 1] = g
        end
    end
    for _, g in ipairs(found) do
        if g.protected then
            out[#out + 1] = g
        end
    end
    return out
end

return F
