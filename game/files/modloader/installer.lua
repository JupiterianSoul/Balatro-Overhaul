ModInstaller = ModInstaller or {}

local MODS_DIR = "mods"
local INSTALLED_LIST = MODS_DIR .. "/.installed_zips"
local MAX_SCAN_DEPTH = 2
local MAX_MANIFEST_BYTES = 256 * 1024
local MAX_LUA_PROBE_BYTES = 4 * 1024 * 1024
local MAX_ENTRY_BYTES = 256 * 1024 * 1024
local MAX_TOTAL_BYTES = 1024 * 1024 * 1024

local ffi_ok, ffi = pcall(require, "ffi")
local bit = bit or require("bit")

local log_lines = {}
local function log(msg)
    log_lines[#log_lines + 1] = msg
    print("[ModInstaller] " .. msg)
end

local function os_name()
    return (love and love.system and love.system.getOS and love.system.getOS()) or "Linux"
end

local function u16(s, i)
    local a, b = s:byte(i, i + 1)
    return a + b * 256
end

local function u32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

local posix_ready, win_ready = false, false

local function setup_posix()
    if posix_ready or not ffi_ok then return posix_ready end
    if pcall(ffi.typeof, "struct mi_dirent") then posix_ready = true; return true end
    posix_ready = pcall(ffi.cdef, [[
        typedef struct mi_DIR mi_DIR;
        struct mi_dirent { uint64_t d_ino; int64_t d_off; unsigned short d_reclen; unsigned char d_type; char d_name[256]; };
        mi_DIR *opendir(const char *name);
        struct mi_dirent *readdir(mi_DIR *dirp);
        int closedir(mi_DIR *dirp);
    ]])
    return posix_ready
end

local function setup_win()
    if win_ready or not ffi_ok then return win_ready end
    if pcall(ffi.typeof, "mi_GUID") then win_ready = true; return true end
    win_ready = pcall(ffi.cdef, [[
        typedef struct { uint32_t dwLowDateTime; uint32_t dwHighDateTime; } mi_FILETIME;
        typedef struct {
            uint32_t dwFileAttributes; mi_FILETIME ftCreationTime; mi_FILETIME ftLastAccessTime; mi_FILETIME ftLastWriteTime;
            uint32_t nFileSizeHigh; uint32_t nFileSizeLow; uint32_t dwReserved0; uint32_t dwReserved1;
            uint16_t cFileName[260]; uint16_t cAlternateFileName[14];
        } mi_WIN32_FIND_DATAW;
        typedef struct { uint32_t Data1; uint16_t Data2; uint16_t Data3; uint8_t Data4[8]; } mi_GUID;
        void *FindFirstFileW(const uint16_t *lpFileName, mi_WIN32_FIND_DATAW *lpFindFileData);
        int FindNextFileW(void *hFindFile, mi_WIN32_FIND_DATAW *lpFindFileData);
        int FindClose(void *hFindFile);
        int MultiByteToWideChar(unsigned int cp, uint32_t flags, const char *str, int cb, uint16_t *wstr, int cch);
        int WideCharToMultiByte(unsigned int cp, uint32_t flags, const uint16_t *wstr, int cch, char *str, int cb, const char *def, int *used);
        long SHGetKnownFolderPath(const mi_GUID *rfid, uint32_t dwFlags, void *hToken, uint16_t **ppszPath);
        void CoTaskMemFree(void *pv);
    ]])
    return win_ready
end

local function to_wide(s)
    local n = ffi.C.MultiByteToWideChar(65001, 0, s, -1, nil, 0)
    local buf = ffi.new("uint16_t[?]", n)
    ffi.C.MultiByteToWideChar(65001, 0, s, -1, buf, n)
    return buf
end

local function from_wide(w)
    local n = ffi.C.WideCharToMultiByte(65001, 0, w, -1, nil, 0, nil, nil)
    if n <= 0 then return nil end
    local buf = ffi.new("char[?]", n)
    ffi.C.WideCharToMultiByte(65001, 0, w, -1, buf, n, nil, nil)
    return ffi.string(buf)
end

local function list_files(dir)
    local out = {}
    if os_name() == "Windows" and setup_win() then
        local data = ffi.new("mi_WIN32_FIND_DATAW")
        local h = ffi.C.FindFirstFileW(to_wide(dir .. "\\*"), data)
        if h == nil or ffi.cast("intptr_t", h) == -1 then return nil end
        repeat
            if bit.band(data.dwFileAttributes, 0x10) == 0 then
                local name = from_wide(data.cFileName)
                if name then out[#out + 1] = name end
            end
        until ffi.C.FindNextFileW(h, data) == 0
        ffi.C.FindClose(h)
        return out
    end
    if os_name() ~= "OS X" and os_name() ~= "iOS" and setup_posix() then
        local d = ffi.C.opendir(dir)
        if d ~= nil then
            while true do
                local e = ffi.C.readdir(d)
                if e == nil then break end
                local name = ffi.string(e.d_name)
                if name ~= "." and name ~= ".." then out[#out + 1] = name end
            end
            ffi.C.closedir(d)
            return out
        end
        return nil
    end
    if os_name() ~= "OS X" then return nil end
    local ok, h = pcall(io.popen, "ls -1 '" .. dir:gsub("'", "'\\''") .. "' 2>/dev/null")
    if not ok or not h then return nil end
    for line in h:lines() do out[#out + 1] = line end
    h:close()
    return out
end

local function windows_downloads()
    if not setup_win() then return nil end
    local ok, shell32 = pcall(ffi.load, "shell32")
    local ok2, ole32 = pcall(ffi.load, "ole32")
    if not ok or not ok2 then return nil end
    local guid = ffi.new("mi_GUID", {0x374DE290, 0x123F, 0x4565, {0x91, 0x64, 0x39, 0xC4, 0x92, 0x5E, 0x46, 0x7B}})
    local out = ffi.new("uint16_t*[1]")
    if shell32.SHGetKnownFolderPath(guid, 0, nil, out) ~= 0 then return nil end
    local path = from_wide(out[0])
    ole32.CoTaskMemFree(out[0])
    return path
end

local function xdg_downloads()
    local home = os.getenv("HOME")
    if not home then return nil end
    local cfg = (os.getenv("XDG_CONFIG_HOME") or (home .. "/.config")) .. "/user-dirs.dirs"
    local f = io.open(cfg, "r")
    if f then
        for line in f:lines() do
            local v = line:match('^%s*XDG_DOWNLOAD_DIR%s*=%s*"(.-)"')
            if v then
                f:close()
                return (v:gsub("%$HOME", home))
            end
        end
        f:close()
    end
    return home .. "/Downloads"
end

local PICK_DIR = "overhaul_picked"

function ModInstaller.uses_picker()
    if os_name() == "Android" then return true end
    local fake = os.getenv("OVERHAUL_PICKER_FAKE")
    return fake ~= nil and fake ~= ""
end

function ModInstaller.pick_dir(clear)
    love.filesystem.createDirectory(PICK_DIR)
    if clear then
        for _, name in ipairs(love.filesystem.getDirectoryItems(PICK_DIR)) do
            love.filesystem.remove(PICK_DIR .. "/" .. name)
        end
    end
    return love.filesystem.getSaveDirectory() .. "/" .. PICK_DIR
end

function ModInstaller.download_dirs()
    if ModInstaller.uses_picker() then return {ModInstaller.pick_dir()} end
    local env = os.getenv("MODLOADER_DOWNLOADS")
    if env ~= nil then
        local list = {}
        for d in env:gmatch("[^;]+") do list[#list + 1] = d end
        return list
    end
    local dirs, seen = {}, {}
    local function add(p)
        if p and p ~= "" and not seen[p] then seen[p] = true; dirs[#dirs + 1] = p end
    end
    local sys = os_name()
    if sys == "Windows" then
        add(windows_downloads())
        local up = os.getenv("USERPROFILE")
        if up then add(up .. "\\Downloads") end
    else
        add(xdg_downloads())
    end
    return dirs
end

local function join(dir, name)
    local sep = (os_name() == "Windows") and "\\" or "/"
    if dir:sub(-1) == "/" or dir:sub(-1) == "\\" then return dir .. name end
    return dir .. sep .. name
end

local Zip = {}
Zip.__index = Zip

function Zip.open(path)
    local f = io.open(path, "rb")
    if not f then return nil, "cannot open" end
    local size = f:seek("end")
    if not size or size < 22 then f:close(); return nil, "too small" end
    local tail_len = math.min(size, 65557)
    f:seek("set", size - tail_len)
    local tail = f:read(tail_len) or ""
    local eocd
    local pos = 1
    while true do
        local p = tail:find("PK\5\6", pos, true)
        if not p then break end
        eocd = p
        pos = p + 1
    end
    if not eocd or eocd + 21 > #tail then f:close(); return nil, "not a zip" end
    local count = u16(tail, eocd + 10)
    local cd_size = u32(tail, eocd + 12)
    local cd_off = u32(tail, eocd + 16)
    if count == 0xFFFF or cd_off == 0xFFFFFFFF or cd_size == 0xFFFFFFFF then f:close(); return nil, "zip64 not supported" end
    if cd_off + cd_size > size then f:close(); return nil, "bad central directory" end
    f:seek("set", cd_off)
    local cd = f:read(cd_size) or ""
    local entries = {}
    local i = 1
    for _ = 1, count do
        if cd:sub(i, i + 3) ~= "PK\1\2" then break end
        local flags = u16(cd, i + 8)
        local method = u16(cd, i + 10)
        local csize = u32(cd, i + 20)
        local usize = u32(cd, i + 24)
        local nlen = u16(cd, i + 28)
        local xlen = u16(cd, i + 30)
        local clen = u16(cd, i + 32)
        local loff = u32(cd, i + 42)
        local name = cd:sub(i + 46, i + 45 + nlen):gsub("\\", "/")
        entries[#entries + 1] = {
            name = name, method = method, csize = csize, usize = usize, offset = loff,
            encrypted = bit.band(flags, 1) ~= 0, dir = name:sub(-1) == "/",
        }
        i = i + 46 + nlen + xlen + clen
    end
    return setmetatable({f = f, size = size, entries = entries, path = path}, Zip)
end

function Zip:read(e)
    if e.encrypted then return nil, "encrypted" end
    self.f:seek("set", e.offset)
    local h = self.f:read(30)
    if not h or #h < 30 or h:sub(1, 4) ~= "PK\3\4" then return nil, "bad local header" end
    self.f:seek("set", e.offset + 30 + u16(h, 27) + u16(h, 29))
    local raw = e.csize > 0 and self.f:read(e.csize) or ""
    if not raw or #raw ~= e.csize then return nil, "truncated" end
    local data
    if e.method == 0 then
        data = raw
    elseif e.method == 8 then
        if e.usize == 0 then return "" end
        local ok, out = pcall(love.data.decompress, "string", "deflate", raw .. "\0\0\0\0\0\0\0\0")
        if not ok then return nil, "inflate failed" end
        data = out
    else
        return nil, "unsupported method " .. tostring(e.method)
    end
    if #data ~= e.usize then return nil, "size mismatch" end
    return data
end

function Zip:close()
    if self.f then self.f:close(); self.f = nil end
end

local function dir_of(name)
    return name:match("^(.*)/[^/]*$") or ""
end

local function depth_of(dir)
    if dir == "" then return 0 end
    local _, n = dir:gsub("/", "")
    return n + 1
end

local function is_manifest_json(s)
    return s:find('"id"%s*:') ~= nil and s:find('"main_file"%s*:') ~= nil
end

local function is_smods_header(s)
    return s:sub(1, 200):find("^%s*%-%-%-%s*STEAMODDED HEADER") ~= nil
end

local function json_deps(s)
    local block = s:match('"dependencies"%s*:%s*(%b[])')
    if not block then return nil end
    local out = {}
    for d in block:gmatch('"(.-)"') do out[#out + 1] = d end
    return out
end

local function header_deps(s)
    local line = s:match("%-%-%-%s*DEPENDENCIES:%s*([^\r\n]+)")
    if not line then return nil end
    line = line:gsub("^%s*%[", ""):gsub("%]%s*$", "")
    local out = {}
    for d in line:gmatch("[^,]+") do
        d = d:gsub("^%s+", ""):gsub("%s+$", "")
        if d ~= "" then out[#out + 1] = d end
    end
    return out
end

function ModInstaller.find_mod_roots(zip)
    local found = {}
    local function mark(root, kind, meta)
        if not found[root] or (kind == "json" and found[root].kind ~= "json") then found[root] = {root = root, kind = kind, meta = meta} end
    end
    for _, e in ipairs(zip.entries) do
        if not e.dir then
            local d = dir_of(e.name)
            if depth_of(d) <= MAX_SCAN_DEPTH and not e.name:find("__MACOSX", 1, true) then
                local base = e.name:match("[^/]+$")
                local lower = base:lower()
                if lower:sub(-5) == ".json" and e.usize <= MAX_MANIFEST_BYTES then
                    local s = zip:read(e)
                    if s and is_manifest_json(s) then
                        mark(d, "json", {id = s:match('"id"%s*:%s*"(.-)"'), name = s:match('"name"%s*:%s*"(.-)"'), version = s:match('"version"%s*:%s*"(.-)"'), dependencies = json_deps(s)})
                    end
                elseif lower == "lovely.toml" then
                    mark(d, "lovely")
                elseif lower:sub(-4) == ".lua" and e.usize <= MAX_LUA_PROBE_BYTES and not found[d] then
                    local s = zip:read(e)
                    if s and is_smods_header(s) then
                        mark(d, "header", {id = s:match("%-%-%-%s*MOD_ID:%s*([^\r\n]+)"), name = s:match("%-%-%-%s*MOD_NAME:%s*([^\r\n]+)"), version = s:match("%-%-%-%s*VERSION:%s*([^\r\n]+)"), dependencies = header_deps(s)})
                    end
                end
            end
            local parent = dir_of(d)
            if d ~= "" and d:match("[^/]+$") == "lovely" and depth_of(parent) <= MAX_SCAN_DEPTH and e.name:lower():sub(-5) == ".toml" then
                mark(parent, "lovely")
            end
        end
    end
    local roots = {}
    for _, r in pairs(found) do roots[#roots + 1] = r end
    table.sort(roots, function(a, b) return #a.root < #b.root end)
    local kept = {}
    for _, r in ipairs(roots) do
        local nested = false
        for _, k in ipairs(kept) do
            if k.root == "" or r.root:sub(1, #k.root + 1) == k.root .. "/" then nested = true; break end
        end
        if not nested then kept[#kept + 1] = r end
    end
    for _, r in ipairs(kept) do
        local probe = (r.root == "" and "" or (r.root .. "/")) .. "src/preflight/loader.lua"
        local id = r.meta and r.meta.id and tostring(r.meta.id):lower() or ""
        if id == "steamodded" then r.builtin = true end
        for _, e in ipairs(zip.entries) do
            if e.name == probe then r.builtin = true; break end
        end
    end
    return kept
end

local function sanitize(s)
    s = tostring(s or ""):gsub("[^%w%._%-]", "_"):gsub("^[%._]+", "")
    if s == "" then s = "mod" end
    return s:sub(1, 64)
end

local function folder_name_for(r, zip_name)
    if r.meta and r.meta.id and r.meta.id ~= "" then return sanitize(r.meta.id) end
    if r.root ~= "" then
        local last = r.root:match("[^/]+$")
        return sanitize((last:gsub("%-main$", ""):gsub("%-master$", "")))
    end
    return sanitize((zip_name:gsub("%.[zZ][iI][pP]$", "")))
end

local function remove_tree(path)
    local info = love.filesystem.getInfo(path)
    if not info then return end
    if info.type == "directory" then
        for _, item in ipairs(love.filesystem.getDirectoryItems(path)) do
            remove_tree(path .. "/" .. item)
        end
    end
    love.filesystem.remove(path)
end

local function extract_root(zip, r, target)
    local prefix = r.root == "" and "" or (r.root .. "/")
    local staging = MODS_DIR .. "/.staging_" .. target
    remove_tree(staging)
    love.filesystem.createDirectory(staging)
    local files, total = 0, 0
    for _, e in ipairs(zip.entries) do
        if e.name:sub(1, #prefix) == prefix and not e.name:find("__MACOSX", 1, true) then
            local rel = e.name:sub(#prefix + 1):gsub("\\", "/")
            if rel ~= "" and not rel:find("%.%.") and rel:sub(1, 1) ~= "/" and not rel:find("[%z:]") then
                total = total + (e.usize or 0)
                if (e.usize or 0) > MAX_ENTRY_BYTES or total > MAX_TOTAL_BYTES then
                    remove_tree(staging)
                    return nil, rel .. ": too big"
                end
                if e.dir then
                    love.filesystem.createDirectory(staging .. "/" .. rel:sub(1, -2))
                else
                    local data, err = zip:read(e)
                    if not data then
                        remove_tree(staging)
                        return nil, rel .. ": " .. tostring(err)
                    end
                    local d = dir_of(rel)
                    if d ~= "" then love.filesystem.createDirectory(staging .. "/" .. d) end
                    if not love.filesystem.write(staging .. "/" .. rel, data) then
                        remove_tree(staging)
                        return nil, rel .. ": write failed"
                    end
                    files = files + 1
                end
            end
        end
    end
    local final = MODS_DIR .. "/" .. target
    remove_tree(final)
    local save = love.filesystem.getSaveDirectory()
    local ok = os.rename(save .. "/" .. staging, save .. "/" .. final)
    if not ok then
        remove_tree(staging)
        return nil, "rename failed"
    end
    return files
end

local function read_installed()
    local set = {}
    local data = love.filesystem.read(INSTALLED_LIST)
    if data then
        for line in data:gmatch("[^\n]+") do set[line] = true end
    end
    return set
end

local function write_installed(set)
    local lines = {}
    for k in pairs(set) do lines[#lines + 1] = k end
    table.sort(lines)
    love.filesystem.write(INSTALLED_LIST, table.concat(lines, "\n"))
end

function ModInstaller.zip_roots(path)
    local zip, err = Zip.open(path)
    if not zip then return nil, err end
    local ok, roots = pcall(ModInstaller.find_mod_roots, zip)
    zip:close()
    if not ok then return nil, roots end
    return roots
end

function ModInstaller.install_zip(path, zip_name, opts)
    opts = opts or {}
    local zip, err = Zip.open(path)
    if not zip then return nil, err end
    local roots = ModInstaller.find_mod_roots(zip)
    if #roots == 0 then
        zip:close()
        return nil, "not a mod"
    end
    local installed = {}
    for _, r in ipairs(roots) do
        if r.builtin then
            log("skipped the Steamodded copy inside " .. zip_name .. " (the game has its own)")
        else
            local target = folder_name_for(r, zip_name)
            local files, e2 = extract_root(zip, r, target)
            if not files then
                zip:close()
                return nil, e2, installed
            end
            installed[#installed + 1] = {folder = target, files = files, kind = r.kind, meta = r.meta}
            log("installed " .. zip_name .. " -> " .. MODS_DIR .. "/" .. target .. " (" .. files .. " files, " .. r.kind .. ")")
        end
    end
    zip:close()
    if #installed == 0 then return nil, "built in" end
    return installed
end

local function stamp_of(path, name)
    local f = io.open(path, "rb")
    if not f then return nil end
    local size = f:seek("end") or 0
    f:close()
    return name .. "|" .. tostring(size), size
end

function ModInstaller.find_zips(opts)
    opts = opts or {}
    love.filesystem.createDirectory(MODS_DIR)
    local done = read_installed()
    local found = {}
    local info = {dirs = {}, readable = false}
    local function consider(path, name, where)
        local stamp, size = stamp_of(path, name)
        if not stamp or (done[stamp] and where ~= "picked") then return end
        local roots = ModInstaller.zip_roots(path)
        if type(roots) ~= "table" or #roots == 0 then return end
        local mods, builtin = {}, 0
        for _, r in ipairs(roots) do
            if r.builtin then
                builtin = builtin + 1
            else
                local folder = folder_name_for(r, name)
                mods[#mods + 1] = {
                    folder = folder, kind = r.kind,
                    id = r.meta and r.meta.id, name = (r.meta and r.meta.name) or folder, version = r.meta and r.meta.version,
                    exists = love.filesystem.getInfo(MODS_DIR .. "/" .. folder, "directory") ~= nil,
                }
            end
        end
        found[#found + 1] = {path = path, name = name, size = size, stamp = stamp, where = where, mods = mods, builtin = builtin > 0 and #mods == 0}
    end
    local where = ModInstaller.uses_picker() and "picked" or "downloads"
    for _, dir in ipairs(opts.dirs or ModInstaller.download_dirs()) do
        local names = list_files(dir)
        info.dirs[#info.dirs + 1] = dir
        if names then
            info.readable = true
            table.sort(names)
            for _, name in ipairs(names) do
                if name:lower():sub(-4) == ".zip" then pcall(consider, join(dir, name), name, where) end
            end
        end
    end
    local save = love.filesystem.getSaveDirectory()
    for _, name in ipairs(love.filesystem.getDirectoryItems(MODS_DIR)) do
        if name:lower():sub(-4) == ".zip" then pcall(consider, save .. "/" .. MODS_DIR .. "/" .. name, name, "mods") end
    end
    return found, info
end

function ModInstaller.install_choice(choice)
    if type(choice) ~= "table" or type(choice.path) ~= "string" or type(choice.name) ~= "string" then return nil, "bad choice" end
    log_lines = {}
    local stamp = stamp_of(choice.path, choice.name)
    if not stamp then return nil, "cannot open" end
    local mods, err = ModInstaller.install_zip(choice.path, choice.name)
    if mods then
        local done = read_installed()
        done[stamp] = true
        write_installed(done)
        if choice.where == "picked" then os.remove(choice.path) end
    else
        log("failed " .. choice.name .. ": " .. tostring(err))
    end
    love.filesystem.write(MODS_DIR .. "/.install_log.txt", table.concat(log_lines, "\n"))
    return mods, err
end

function ModInstaller.installed_mods()
    local out = {}
    for _, name in ipairs(love.filesystem.getDirectoryItems(MODS_DIR)) do
        local info = love.filesystem.getInfo(MODS_DIR .. "/" .. name)
        if info and info.type == "directory" and name:sub(1, 1) ~= "." then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

ModInstaller.Zip = Zip

return ModInstaller
