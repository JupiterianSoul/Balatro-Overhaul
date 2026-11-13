local ok, ffi = pcall(require, "ffi")
if not ok or ffi.os ~= "Windows" then return false end
pcall(ffi.cdef, [[
int MultiByteToWideChar(unsigned int cp, unsigned long flags, const char *src, int srclen, wchar_t *dst, int dstlen);
int SetCurrentDirectoryW(const wchar_t *path);
]])
local lib_ok, k32 = pcall(ffi.load, "kernel32")
if not lib_ok then return false end
local function chdir(path)
    if type(path) ~= "string" or path == "" then return false end
    local done = false
    pcall(function()
        local n = k32.MultiByteToWideChar(65001, 0, path, -1, nil, 0)
        if n <= 0 then return end
        local buf = ffi.new("wchar_t[?]", n)
        if k32.MultiByteToWideChar(65001, 0, path, -1, buf, n) <= 0 then return end
        done = k32.SetCurrentDirectoryW(buf) ~= 0
    end)
    return done
end
local dir
pcall(function() dir = love.filesystem.getSourceBaseDirectory() end)
local moved = chdir(dir)
if not moved then
    pcall(function() moved = chdir(love.filesystem.getSaveDirectory()) end)
end
WIN_CWD_MOVED = moved
return moved
