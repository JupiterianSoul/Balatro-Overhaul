local function load_native()
    local cpath = package.cpath or ""
    for pattern in cpath:gmatch("[^;]+") do
        local path = pattern:gsub("%?", "https")
        local f = io.open(path, "rb")
        if f then
            f:close()
            local open = package.loadlib(path, "luaopen_https")
            if open then
                local ok, mod = pcall(open)
                if ok and type(mod) == "table" and type(mod.request) == "function" then return mod end
            end
        end
    end
end

local native = load_native()
if native then return native end

local M = {overhaul = true}

local OS = "Linux"
do
    local ok = pcall(require, "love.system")
    if ok and love and love.system and love.system.getOS then OS = love.system.getOS() end
end

local TUNNEL_PORT = tonumber(os.getenv("OVERHAUL_TUNNEL_PORT") or "") or 44380
local MAX_REDIRECTS = 8
local METHODS = {GET = true, HEAD = true, POST = true, PUT = true, DELETE = true, PATCH = true}

local function split_url(url)
    local scheme, host, path = tostring(url):match("^(https?)://([^/%?#]+)(.*)$")
    if not scheme then return nil end
    if path == "" then path = "/" end
    if path:sub(1, 1) == "?" then path = "/" .. path end
    path = path:gsub("#.*$", "")
    local h, port = host:match("^(.-):(%d+)$")
    if h then host = h; port = tonumber(port) else port = scheme == "https" and 443 or 80 end
    return scheme, host, port, path
end

local function resolve(base, loc)
    if loc:match("^https?://") then return loc end
    local scheme, host = base:match("^(https?)://([^/%?#]+)")
    if loc:sub(1, 2) == "//" then return scheme .. ":" .. loc end
    if loc:sub(1, 1) == "/" then return scheme .. "://" .. host .. loc end
    local dir = base:gsub("[%?#].*$", ""):match("^(.*/)") or (base .. "/")
    return dir .. loc
end

local function check_options(url, options)
    if type(url) ~= "string" then error("\"url\" must be a string", 3) end
    options = options or {}
    if type(options) ~= "table" then error("\"options\" must be a table", 3) end
    local method = options.method and tostring(options.method):upper() or (options.data and "POST" or "GET")
    if not METHODS[method] then error("\"options.method\" must be one of GET, HEAD, POST, PUT, DELETE, PATCH", 3) end
    local headers = {}
    for k, v in pairs(options.headers or {}) do headers[tostring(k)] = tostring(v) end
    local data = options.data
    if data ~= nil and type(data) ~= "string" then error("\"options.data\" must be a string", 3) end
    if data == "" then data = nil end
    return method, headers, data
end

local function has_header(headers, name)
    name = name:lower()
    for k in pairs(headers) do if k:lower() == name then return true end end
    return false
end

local function header_lookup(headers, name)
    name = name:lower()
    for k, v in pairs(headers or {}) do if tostring(k):lower() == name then return v end end
end

local function redirect_method(code, method)
    if code == 307 or code == 308 then return method, true end
    if method == "HEAD" then return "HEAD", false end
    return "GET", false
end

local function with_redirects(backend, url, method, headers, data)
    local current = url
    for _ = 1, MAX_REDIRECTS do
        local code, body, rheaders = backend(current, method, headers, data)
        if not code or code == 0 then return 0, body or "request failed", rheaders or {} end
        local loc = header_lookup(rheaders, "location")
        if code >= 300 and code < 400 and code ~= 304 and loc then
            current = resolve(current, loc)
            local keep
            method, keep = redirect_method(code, method)
            if not keep then data = nil end
        else
            return code, body, rheaders
        end
    end
    return 0, "too many redirects", {}
end

local function parse_head(lines)
    local code, headers = nil, {}
    for _, line in ipairs(lines) do
        local c = line:match("^HTTP/[%d%.]+%s+(%d+)")
        if c then
            code, headers = tonumber(c), {}
        else
            local k, v = line:match("^([^:]+):%s*(.-)%s*$")
            if k and code then headers[k] = v end
        end
    end
    return code, headers
end

local socket
local function tunnel_backend(url, method, headers, data)
    if not socket then
        local ok, s = pcall(require, "socket")
        if not ok then return 0, "socket unavailable", {} end
        socket = s
    end
    local scheme, host, port, path = split_url(url)
    if not scheme then return 0, "bad url", {} end
    local tcp = socket.tcp()
    tcp:settimeout(8)
    local ok, err
    if scheme == "https" then
        ok, err = tcp:connect("127.0.0.1", TUNNEL_PORT)
        if not ok then tcp:close(); return 0, "no tls tunnel: " .. tostring(err), {} end
        tcp:send(host .. ":" .. port .. "\n")
        tcp:settimeout(30)
        local line, e2 = tcp:receive("*l")
        if line ~= "OK" then tcp:close(); return 0, "tunnel: " .. tostring(line or e2), {} end
    else
        ok, err = tcp:connect(host, port)
        if not ok then tcp:close(); return 0, "connect: " .. tostring(err), {} end
    end
    tcp:settimeout(60)
    local out = {method .. " " .. path .. " HTTP/1.1", "Host: " .. host}
    for k, v in pairs(headers) do out[#out + 1] = k .. ": " .. v end
    if not has_header(headers, "accept") then out[#out + 1] = "Accept: */*" end
    out[#out + 1] = "Accept-Encoding: identity"
    out[#out + 1] = "Connection: close"
    if data or method == "POST" or method == "PUT" or method == "PATCH" then
        out[#out + 1] = "Content-Length: " .. tostring(data and #data or 0)
    end
    local req = table.concat(out, "\r\n") .. "\r\n\r\n" .. (data or "")
    local sent, e3 = tcp:send(req)
    if not sent then tcp:close(); return 0, "send: " .. tostring(e3), {} end
    local status_line, e4 = tcp:receive("*l")
    if not status_line then tcp:close(); return 0, "recv: " .. tostring(e4), {} end
    local code = tonumber(status_line:match("^HTTP/[%d%.]+%s+(%d+)"))
    if not code then tcp:close(); return 0, "bad status line", {} end
    local rheaders, lower = {}, {}
    while true do
        local h, e5 = tcp:receive("*l")
        if not h then tcp:close(); return 0, "headers: " .. tostring(e5), {} end
        if h == "" then break end
        local k, v = h:match("^([^:]+):%s*(.-)%s*$")
        if k then rheaders[k] = v; lower[k:lower()] = v end
    end
    local parts = {}
    local te = (lower["transfer-encoding"] or ""):lower()
    local total = tonumber(lower["content-length"])
    if method == "HEAD" or code == 204 or code == 304 then
        total = 0
        te = ""
    end
    if te:find("chunked", 1, true) then
        while true do
            local size_line, e6 = tcp:receive("*l")
            if not size_line then tcp:close(); return 0, "chunk: " .. tostring(e6), {} end
            local size = tonumber(size_line:match("^%s*(%x+)"), 16)
            if not size then tcp:close(); return 0, "bad chunk", {} end
            if size == 0 then break end
            local left = size
            while left > 0 do
                local part, e7, partial = tcp:receive(math.min(left, 65536))
                part = part or partial
                if not part or #part == 0 then tcp:close(); return 0, "body: " .. tostring(e7), {} end
                left = left - #part
                parts[#parts + 1] = part
            end
            tcp:receive("*l")
        end
    elseif total then
        local left = total
        while left > 0 do
            local part, e8, partial = tcp:receive(math.min(left, 65536))
            part = part or partial
            if not part or #part == 0 then tcp:close(); return 0, "body: " .. tostring(e8), {} end
            left = left - #part
            parts[#parts + 1] = part
        end
    else
        while true do
            local part, e9, partial = tcp:receive(65536)
            part = part or partial
            if part and #part > 0 then parts[#parts + 1] = part end
            if e9 == "closed" then break end
            if e9 then tcp:close(); return 0, "body: " .. tostring(e9), {} end
        end
    end
    tcp:close()
    return code, table.concat(parts), rheaders
end

local function shell_quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function read_all(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

local function curl_backend(url, method, headers, data)
    local base = os.tmpname()
    local body_f, head_f, data_f = base .. ".body", base .. ".head", base .. ".data"
    local cmd = {"curl", "-sS", "--max-time", "120", "-o", shell_quote(body_f), "-D", shell_quote(head_f), "-w", "'%{http_code}'"}
    method = tostring(method or "GET"):upper()
    if not method:match("^%u+$") then return 0, "bad method", {} end
    if method == "HEAD" then cmd[#cmd + 1] = "-I" else cmd[#cmd + 1] = "-X " .. method end
    for k, v in pairs(headers) do cmd[#cmd + 1] = "-H " .. shell_quote(k .. ": " .. v) end
    if data then
        local f = io.open(data_f, "wb")
        if not f then os.remove(base); return 0, "cannot write request body", {} end
        f:write(data)
        f:close()
        cmd[#cmd + 1] = "--data-binary @" .. shell_quote(data_f)
    end
    cmd[#cmd + 1] = shell_quote(url)
    local p = io.popen(table.concat(cmd, " ") .. " 2>&1")
    local out = p and p:read("*a") or ""
    if p then p:close() end
    local body = method ~= "HEAD" and read_all(body_f) or ""
    local head = read_all(head_f) or ""
    for _, f in ipairs({base, body_f, head_f, data_f}) do os.remove(f) end
    local code = tonumber(out:match("(%d%d%d)%s*$"))
    if not code or code == 0 then
        local msg = out:gsub("%d%d%d%s*$", ""):gsub("%s+$", "")
        return 0, msg ~= "" and msg or "curl failed", {}
    end
    local lines = {}
    for line in head:gmatch("([^\r\n]*)\r?\n") do if line ~= "" then lines[#lines + 1] = line end end
    local _, rheaders = parse_head(lines)
    return code, body, rheaders or {}
end

local winhttp
local function winhttp_setup()
    if winhttp ~= nil then return winhttp end
    winhttp = false
    local ok_ffi, ffi = pcall(require, "ffi")
    if not ok_ffi then return false end
    pcall(ffi.cdef, [[
        void *WinHttpOpen(const uint16_t *agent, uint32_t access, const uint16_t *proxy, const uint16_t *bypass, uint32_t flags);
        void *WinHttpConnect(void *session, const uint16_t *server, uint16_t port, uint32_t reserved);
        void *WinHttpOpenRequest(void *connect, const uint16_t *verb, const uint16_t *object, const uint16_t *version, const uint16_t *referrer, const uint16_t **accept, uint32_t flags);
        int WinHttpSendRequest(void *request, const uint16_t *headers, uint32_t headers_len, void *optional, uint32_t optional_len, uint32_t total_len, uintptr_t context);
        int WinHttpReceiveResponse(void *request, void *reserved);
        int WinHttpQueryHeaders(void *request, uint32_t info, const uint16_t *name, void *buffer, uint32_t *buffer_len, uint32_t *index);
        int WinHttpQueryDataAvailable(void *request, uint32_t *size);
        int WinHttpReadData(void *request, void *buffer, uint32_t to_read, uint32_t *read);
        int WinHttpCloseHandle(void *handle);
        int WinHttpSetTimeouts(void *handle, int resolve, int connect, int send, int receive);
    ]])
    pcall(ffi.cdef, [[int MultiByteToWideChar(unsigned int cp, uint32_t flags, const char *str, int cb, uint16_t *wstr, int cch);]])
    pcall(ffi.cdef, [[int WideCharToMultiByte(unsigned int cp, uint32_t flags, const uint16_t *wstr, int cch, char *str, int cb, const char *def, int *used);]])
    pcall(ffi.cdef, [[uint32_t GetLastError(void);]])
    local ok_lib, lib = pcall(ffi.load, "winhttp")
    if not ok_lib then return false end
    winhttp = {ffi = ffi, lib = lib}
    return winhttp
end

local function wide(ffi, s)
    local n = ffi.C.MultiByteToWideChar(65001, 0, s, -1, nil, 0)
    local buf = ffi.new("uint16_t[?]", math.max(n, 1))
    ffi.C.MultiByteToWideChar(65001, 0, s, -1, buf, n)
    return buf
end

local function narrow(ffi, w, chars)
    local n = ffi.C.WideCharToMultiByte(65001, 0, w, chars, nil, 0, nil, nil)
    if n <= 0 then return "" end
    local buf = ffi.new("char[?]", n)
    ffi.C.WideCharToMultiByte(65001, 0, w, chars, buf, n, nil, nil)
    return ffi.string(buf, n)
end

local function winhttp_backend(url, method, headers, data)
    local W = winhttp_setup()
    if not W then return 0, "winhttp unavailable", {} end
    local ffi, lib = W.ffi, W.lib
    local scheme, host, port, path = split_url(url)
    if not scheme then return 0, "bad url", {} end
    local agent = header_lookup(headers, "user-agent") or "BalatroOverhaul"
    local session = lib.WinHttpOpen(wide(ffi, agent), 4, nil, nil, 0)
    if session == nil then session = lib.WinHttpOpen(wide(ffi, agent), 0, nil, nil, 0) end
    if session == nil then return 0, "WinHttpOpen failed", {} end
    local handles = {session}
    local function done(code, body, h)
        for i = #handles, 1, -1 do lib.WinHttpCloseHandle(handles[i]) end
        return code, body, h
    end
    lib.WinHttpSetTimeouts(session, 15000, 15000, 30000, 60000)
    local conn = lib.WinHttpConnect(session, wide(ffi, host), port, 0)
    if conn == nil then return done(0, "WinHttpConnect failed", {}) end
    handles[#handles + 1] = conn
    local req = lib.WinHttpOpenRequest(conn, wide(ffi, method), wide(ffi, path), nil, nil, nil, scheme == "https" and 0x00800000 or 0)
    if req == nil then return done(0, "WinHttpOpenRequest failed", {}) end
    handles[#handles + 1] = req
    local lines = {}
    for k, v in pairs(headers) do lines[#lines + 1] = k .. ": " .. v end
    local hdr = #lines > 0 and wide(ffi, table.concat(lines, "\r\n")) or nil
    local body_buf = data and ffi.new("char[?]", #data, data) or nil
    local len = data and #data or 0
    if lib.WinHttpSendRequest(req, hdr, hdr and 0xFFFFFFFF or 0, body_buf, len, len, 0) == 0 then
        return done(0, "WinHttpSendRequest failed (" .. tostring(ffi.C.GetLastError()) .. ")", {})
    end
    if lib.WinHttpReceiveResponse(req, nil) == 0 then
        return done(0, "WinHttpReceiveResponse failed (" .. tostring(ffi.C.GetLastError()) .. ")", {})
    end
    local status = ffi.new("uint32_t[1]")
    local slen = ffi.new("uint32_t[1]", 4)
    if lib.WinHttpQueryHeaders(req, 0x20000000 + 19, nil, status, slen, nil) == 0 then
        return done(0, "no status code", {})
    end
    local rheaders = {}
    local hlen = ffi.new("uint32_t[1]", 0)
    lib.WinHttpQueryHeaders(req, 22, nil, nil, hlen, nil)
    if hlen[0] > 0 then
        local hbuf = ffi.new("uint16_t[?]", hlen[0] / 2 + 1)
        if lib.WinHttpQueryHeaders(req, 22, nil, hbuf, hlen, nil) ~= 0 then
            local text = narrow(ffi, hbuf, hlen[0] / 2)
            for line in text:gmatch("([^\r\n]+)") do
                local k, v = line:match("^([^:]+):%s*(.-)%s*$")
                if k then rheaders[k] = v end
            end
        end
    end
    local parts = {}
    local avail = ffi.new("uint32_t[1]")
    local got = ffi.new("uint32_t[1]")
    while true do
        if lib.WinHttpQueryDataAvailable(req, avail) == 0 then return done(0, "read failed", {}) end
        if avail[0] == 0 then break end
        local buf = ffi.new("char[?]", avail[0])
        if lib.WinHttpReadData(req, buf, avail[0], got) == 0 then return done(0, "read failed", {}) end
        if got[0] == 0 then break end
        parts[#parts + 1] = ffi.string(buf, got[0])
    end
    return done(tonumber(status[0]), table.concat(parts), rheaders)
end

local BACKENDS = {tunnel = tunnel_backend, curl = curl_backend, winhttp = winhttp_backend}

local function order()
    local forced = os.getenv("OVERHAUL_HTTPS_BACKEND")
    if forced and BACKENDS[forced] then return {forced} end
    if OS == "Windows" then return {"winhttp", "tunnel"} end
    if OS == "Android" or OS == "iOS" then return {"tunnel"} end
    return {"curl", "tunnel"}
end

M.backend = nil

function M.request(url, options)
    local method, headers, data = check_options(url, options)
    local last
    for _, name in ipairs(M.backend and {M.backend} or order()) do
        local code, body, rheaders = with_redirects(BACKENDS[name], url, method, headers, data)
        if code and code ~= 0 then
            M.backend = name
            return code, body, rheaders
        end
        last = last or body
        if M.backend then break end
    end
    return 0, last or "no backend", {}
end

return M
