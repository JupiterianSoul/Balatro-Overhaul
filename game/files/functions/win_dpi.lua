local ok, ffi = pcall(require, "ffi")
if not ok or ffi.os ~= "Windows" then return false end
pcall(ffi.cdef, "int SetProcessDpiAwarenessContext(void *value); int SetProcessDPIAware(void);")
local lib_ok, user32 = pcall(ffi.load, "user32")
if not lib_ok then return false end
local done = false
pcall(function()
    done = user32.SetProcessDpiAwarenessContext(ffi.cast("void *", ffi.cast("intptr_t", -4))) ~= 0
end)
if not done then
    pcall(function() done = user32.SetProcessDPIAware() ~= 0 end)
end
WIN_DPI_AWARE = done
return done
