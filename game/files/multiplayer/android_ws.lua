
local AndroidWS = {}

local _connected = false
local _last_error = nil
local _incoming = {}
local _thread = nil
local _cmd_channel = nil
local _msg_channel = nil
local _status_channel = nil
local _socket_available = nil
local _initialized = false
local _debug_url = nil
local _debug_host = nil
local _debug_path = nil
local _last_status = nil
local _waiting = false

local WORKER_CODE = [[
local bit = require("bit")

local cmd_ch = love.thread.getChannel("aws_cmd")
local msg_ch = love.thread.getChannel("aws_msg")
local status_ch = love.thread.getChannel("aws_status")

local socket_ok, socket = pcall(require, "socket")
if not socket_ok then
    status_ch:push("ERROR:socket_missing:" .. tostring(socket))
    while true do
        local cmd = cmd_ch:demand(1)
        if cmd then
            if cmd == "QUIT" then return end
            if cmd == "PROBE" then
                status_ch:push("PROBE:false:luasocket not available: " .. tostring(socket))
            end
        end
    end
end

status_ch:push("PROBE:true:luasocket loaded OK")


local mime_b64
pcall(function() mime_b64 = require("mime").b64 end)

local function base64_encode(data)
    if mime_b64 then return mime_b64(data) end
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x)
        local r, b_str = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b_str % 2 ^ i - b_str % 2 ^ (i - 1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
        return b:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local function generate_ws_key()
    math.randomseed(os.time() + os.clock() * 1000)
    local bytes = {}
    for i = 1, 16 do bytes[i] = string.char(math.random(0, 255)) end
    return base64_encode(table.concat(bytes))
end

local function generate_mask()
    local m = {}
    for i = 1, 4 do m[i] = math.random(0, 255) end
    return m
end


local function ws_encode_frame(data)
    local payload = tostring(data)
    local len = #payload
    local header = {}

    header[1] = string.char(0x81)
    local mask = generate_mask()
    if len < 126 then
        header[2] = string.char(bit.bor(0x80, len))
    elseif len < 65536 then
        header[2] = string.char(bit.bor(0x80, 126))
        header[3] = string.char(bit.rshift(len, 8))
        header[4] = string.char(bit.band(len, 0xFF))
    else
        header[2] = string.char(bit.bor(0x80, 127))
        for i = 7, 0, -1 do
            header[#header + 1] = string.char(i >= 4 and 0 or bit.band(bit.rshift(len, i * 8), 0xFF))
        end
    end
    for i = 1, 4 do header[#header + 1] = string.char(mask[i]) end
    local masked = {}
    local CHUNK = 2048
    for s = 1, len, CHUNK do
        local e = s + CHUNK - 1
        if e > len then e = len end
        local bytes = { payload:byte(s, e) }
        for k = 1, #bytes do
            bytes[k] = bit.bxor(bytes[k], mask[(s + k - 2) % 4 + 1])
        end
        masked[#masked + 1] = string.char(unpack(bytes))
    end
    return table.concat(header) .. table.concat(masked)
end

local function ws_encode_pong(data)
    local len = data and #data or 0
    local frame = string.char(0x8A)
    local mask = generate_mask()
    frame = frame .. string.char(bit.bor(0x80, len))
    for i = 1, 4 do frame = frame .. string.char(mask[i]) end
    local masked = {}
    for i = 1, len do
        masked[i] = string.char(bit.bxor(data:byte(i), mask[(i - 1) % 4 + 1]))
    end
    return frame .. table.concat(masked)
end

local function ws_encode_close()
    local mask = generate_mask()
    local frame = string.char(0x88, 0x80)
    for i = 1, 4 do frame = frame .. string.char(mask[i]) end
    return frame
end


local tcp = nil
local connected = false
local buffer = ""
local frag_parts = nil
local url = nil

local TUNNEL_PORT = tonumber(os.getenv("OVERHAUL_TUNNEL_PORT") or "") or 44380

local using_winhttp = false
local wh_ses, wh_con, wh_req, wh_ws_h = nil, nil, nil, nil

local ffi_ok, ffi_lib = pcall(require, "ffi")
local on_windows = false
if jit and jit.os == "Windows" then
    on_windows = true
elseif ffi_ok and ffi_lib and ffi_lib.os == "Windows" then
    on_windows = true
end

if ffi_ok and on_windows then
    pcall(function()
        ffi_lib.cdef[=[
            void* WinHttpOpen(const wchar_t* a, unsigned long b, const wchar_t* c, const wchar_t* d, unsigned long e);
            void* WinHttpConnect(void* a, const wchar_t* b, unsigned short c, unsigned long d);
            void* WinHttpOpenRequest(void* a, const wchar_t* b, const wchar_t* c, const wchar_t* d, const wchar_t* e, void** f, unsigned long g);
            int WinHttpSendRequest(void* a, const wchar_t* b, unsigned long c, void* d, unsigned long e, unsigned long f, uintptr_t g);
            int WinHttpReceiveResponse(void* a, void* b);
            void* WinHttpWebSocketCompleteUpgrade(void* a, uintptr_t b);
            unsigned long WinHttpWebSocketSend(void* a, int b, void* c, unsigned long d);
            unsigned long WinHttpWebSocketReceive(void* a, void* b, unsigned long c, unsigned long* d, int* e);
            unsigned long WinHttpWebSocketClose(void* a, unsigned short b, void* c, unsigned long d);
            int WinHttpSetOption(void* a, unsigned long b, void* c, unsigned long d);
            int WinHttpCloseHandle(void* a);
        ]=]
    end)
end

local winhttp = nil
local kernel32 = nil
if ffi_ok and on_windows then
    pcall(function() winhttp = ffi_lib.load("winhttp") end)
    pcall(function()
        ffi_lib.cdef[=[ unsigned long GetLastError(); ]=]
        kernel32 = ffi_lib.load("kernel32")
    end)
end

local function last_err()
    return (kernel32 and kernel32.GetLastError() or 0)
end

local WH_REASONS = {
    [12002] = "timed out",
    [12007] = "server name not found",
    [12029] = "cannot connect",
    [12030] = "connection dropped",
    [12152] = "bad answer",
    [12157] = "TLS failed",
    [12175] = "TLS certificate refused",
}

local function wh_reason(step, code)
    code = tonumber(code) or 0
    return step .. " " .. tostring(code) .. (WH_REASONS[code] and (" (" .. WH_REASONS[code] .. ")") or "")
end

status_ch:push("STATUS:winhttp_init:ffi=" .. tostring(ffi_ok) .. " win=" .. tostring(on_windows) .. " winhttp=" .. tostring(winhttp ~= nil) .. " kernel32=" .. tostring(kernel32 ~= nil))

pcall(function()
    require("love.filesystem")
    local msg = os.date("%Y-%m-%d %H:%M:%S") .. " WORKER_INIT: ffi=" .. tostring(ffi_ok) .. " jit.os=" .. tostring(jit and jit.os) .. " ffi.os=" .. tostring(ffi_ok and ffi_lib and ffi_lib.os) .. " on_windows=" .. tostring(on_windows) .. " winhttp=" .. tostring(winhttp ~= nil) .. " kernel32=" .. tostring(kernel32 ~= nil) .. "\n"
    love.filesystem.append("winhttp_debug.log", msg)
end)

local function wcs(s)
    if not ffi_lib then return nil end
    local ws = ffi_lib.new("wchar_t[?]", #s + 1)
    for i = 0, #s - 1 do ws[i] = s:byte(i + 1) end
    ws[#s] = 0
    return ws
end

local function winhttp_close_all()
    if wh_ws_h and winhttp then
        pcall(function() winhttp.WinHttpWebSocketClose(wh_ws_h, 1000, ffi_lib.cast("void*", 0), 0) end)
        pcall(function() winhttp.WinHttpCloseHandle(wh_ws_h) end)
        wh_ws_h = nil
    end
    if wh_req and winhttp then pcall(function() winhttp.WinHttpCloseHandle(wh_req) end); wh_req = nil end
    if wh_con and winhttp then pcall(function() winhttp.WinHttpCloseHandle(wh_con) end); wh_con = nil end
    if wh_ses and winhttp then pcall(function() winhttp.WinHttpCloseHandle(wh_ses) end); wh_ses = nil end
end

local function winhttp_do_connect(h, p, ph)
    if not winhttp or not ffi_lib then return false, "no winhttp" end
    winhttp_close_all()
    local NULL  = ffi_lib.cast("void*", 0)
    local WNULL = ffi_lib.cast("wchar_t*", 0)
    local connect_ms   = ffi_lib.new("unsigned long[1]", 20000)
    local resolve_ms   = ffi_lib.new("unsigned long[1]", 15000)
    local response_ms  = ffi_lib.new("unsigned long[1]", 90000)
    local recv_ms      = ffi_lib.new("unsigned long[1]", 10)
    local ses = winhttp.WinHttpOpen(wcs("BalatroOverhaul/1.0"), 4, WNULL, WNULL, 0)
    if ses == nil then ses = winhttp.WinHttpOpen(wcs("BalatroOverhaul/1.0"), 0, WNULL, WNULL, 0) end
    if ses == nil then return false, wh_reason("WinHttpOpen", last_err()) end
    winhttp.WinHttpSetOption(ses, 2, resolve_ms, 4)
    winhttp.WinHttpSetOption(ses, 3, connect_ms, 4)
    local con = winhttp.WinHttpConnect(ses, wcs(h), p, 0)
    if con == nil then
        winhttp.WinHttpCloseHandle(ses)
        return false, wh_reason("WinHttpConnect", last_err())
    end
    local req = winhttp.WinHttpOpenRequest(con, wcs("GET"), wcs(ph), WNULL, WNULL, NULL, 0x00800000)
    if req == nil then
        winhttp.WinHttpCloseHandle(con); winhttp.WinHttpCloseHandle(ses)
        return false, wh_reason("WinHttpOpenRequest", last_err())
    end
    winhttp.WinHttpSetOption(req, 114, NULL, 0)
    winhttp.WinHttpSetOption(req, 6, response_ms, 4)
    if winhttp.WinHttpSendRequest(req, WNULL, 0, NULL, 0, 0, 0) == 0 then
        local e = last_err()
        winhttp.WinHttpCloseHandle(req); winhttp.WinHttpCloseHandle(con); winhttp.WinHttpCloseHandle(ses)
        return false, wh_reason("WinHttpSendRequest", e)
    end
    status_ch:push("STATUS:waiting:server reached, waiting for its answer")
    if winhttp.WinHttpReceiveResponse(req, NULL) == 0 then
        local e = last_err()
        winhttp.WinHttpCloseHandle(req); winhttp.WinHttpCloseHandle(con); winhttp.WinHttpCloseHandle(ses)
        return false, wh_reason("WinHttpReceiveResponse", e)
    end
    local ws = winhttp.WinHttpWebSocketCompleteUpgrade(req, 0)
    if ws == nil then
        winhttp.WinHttpCloseHandle(req); winhttp.WinHttpCloseHandle(con); winhttp.WinHttpCloseHandle(ses)
        return false, wh_reason("WinHttpWebSocketCompleteUpgrade", last_err())
    end
    wh_ses = ses; wh_con = con; wh_req = req; wh_ws_h = ws
    return true
end

local function winhttp_ws_send(text)
    if not wh_ws_h or not winhttp or not ffi_lib then return false end
    local buf = ffi_lib.new("uint8_t[?]", #text + 1)
    ffi_lib.copy(buf, text, #text)
    return winhttp.WinHttpWebSocketSend(wh_ws_h, 0, buf, #text) == 0
end

local wh_frag = nil
local function winhttp_ws_receive()
    if not wh_ws_h or not winhttp or not ffi_lib then return nil end
    local buf = ffi_lib.new("uint8_t[?]", 65536)
    local nr  = ffi_lib.new("unsigned long[1]", 0)
    local bt  = ffi_lib.new("int[1]", 0)
    local r   = winhttp.WinHttpWebSocketReceive(wh_ws_h, buf, 65536, nr, bt)
    if r == 0 then
        if bt[0] == 4 then wh_frag = nil return nil, "close" end
        local chunk = nr[0] > 0 and ffi_lib.string(buf, nr[0]) or ""
        if bt[0] == 1 or bt[0] == 3 then
            wh_frag = (wh_frag or "") .. chunk
            return nil
        end
        if wh_frag then
            chunk = wh_frag .. chunk
            wh_frag = nil
        end
        if #chunk > 0 then return chunk end
        return nil
    end
    if r ~= 12002 then
        return nil, "error:" .. r
    end
    return nil
end


local wrecv_ch = love.thread.getChannel("aws_wrecv")
local wrecv_gen = 0
local wrecv_thread = nil
local WRECV_CODE = [==[
local handle_num, gen = ...
local ffi = require("ffi")
require("love.thread")
local msg_out = love.thread.getChannel("aws_msg")
local err_out = love.thread.getChannel("aws_wrecv")
pcall(ffi.cdef, [=[
    unsigned long WinHttpWebSocketReceive(void* a, void* b, unsigned long c, unsigned long* d, int* e);
]=])
local ok_load, lib = pcall(ffi.load, "winhttp")
if not ok_load then
    err_out:push(gen .. ":winhttp load failed")
    return
end
local h = ffi.cast("void*", handle_num)
local buf = ffi.new("uint8_t[?]", 65536)
local nr = ffi.new("unsigned long[1]", 0)
local bt = ffi.new("int[1]", 0)
local frag = nil
while true do
    local r = lib.WinHttpWebSocketReceive(h, buf, 65536, nr, bt)
    if r ~= 0 then
        if r ~= 12002 then
            err_out:push(gen .. ":error:" .. tostring(r))
            return
        end
    else
        local t = bt[0]
        if t == 4 then
            err_out:push(gen .. ":close")
            return
        end
        local chunk = nr[0] > 0 and ffi.string(buf, nr[0]) or ""
        if t == 1 or t == 3 then
            frag = (frag or "") .. chunk
        else
            if frag then
                chunk = frag .. chunk
                frag = nil
            end
            if #chunk > 0 then msg_out:push(chunk) end
        end
    end
end
]==]

local function winhttp_start_receiver()
    wrecv_gen = wrecv_gen + 1
    wrecv_ch:clear()
    local hn = tonumber(ffi_lib.cast("uintptr_t", wh_ws_h))
    local th_ok, th = pcall(love.thread.newThread, WRECV_CODE)
    if not th_ok or not th then
        return false, "receiver thread: " .. tostring(th)
    end
    wrecv_thread = th
    th:start(hn, wrecv_gen)
    return true
end

local function do_connect(target_url)
    url = target_url
    local proto, host, port, path = url:match("^(wss?)://([^/:]+):?(%d*)(/?.*)")
    if not host then
        status_ch:push("ERROR:bad_url:Invalid URL: " .. tostring(url))
        return false
    end
    port = tonumber(port) or (proto == "wss" and 443 or 80)
    if path == "" then path = "/" end

    status_ch:push("STATUS:connecting:" .. host .. ":" .. port)
    status_ch:push("DEBUG_URL:" .. tostring(url) .. "|" .. tostring(host) .. "|" .. tostring(path) .. "|" .. tostring(proto) .. "|" .. tostring(port))

    pcall(function()
        require("love.filesystem")
        love.filesystem.append("winhttp_debug.log", os.date("%Y-%m-%d %H:%M:%S") .. " CONNECT: proto=" .. tostring(proto) .. " host=" .. tostring(host) .. " port=" .. tostring(port) .. " path=" .. tostring(path) .. " winhttp=" .. tostring(winhttp ~= nil) .. "\n")
    end)

    if proto == "wss" and winhttp ~= nil then
        status_ch:push("STATUS:winhttp:Connecting via WinHTTP WSS to " .. host .. ":" .. port)
        local pcall_ok, ok_or_err, err_msg = pcall(winhttp_do_connect, host, port, path)
        pcall(function()
            require("love.filesystem")
            love.filesystem.append("winhttp_debug.log", os.date("%Y-%m-%d %H:%M:%S") .. " WINHTTP_RESULT: pcall_ok=" .. tostring(pcall_ok) .. " ok=" .. tostring(ok_or_err) .. " err=" .. tostring(err_msg) .. "\n")
        end)
        if not pcall_ok then
            status_ch:push("ERROR:winhttp_crash:WinHTTP FFI error: " .. tostring(ok_or_err))
            return false
        end
        if not ok_or_err then
            status_ch:push("ERROR:winhttp_fail:WinHTTP WSS failed: " .. tostring(err_msg))
            return false
        end
        local rs_ok, rs_err = winhttp_start_receiver()
        if not rs_ok then
            winhttp_close_all()
            status_ch:push("ERROR:winhttp_fail:WinHTTP WSS failed: " .. tostring(rs_err))
            return false
        end
        connected = true
        using_winhttp = true
        status_ch:push("CONNECTED:ok:WebSocket connected via WinHTTP to " .. host .. ":" .. port)
        return true
    end

    local t = socket.tcp()
    t:settimeout(10)

    if proto == "wss" then
        status_ch:push("STATUS:tunnel:Connecting via TLS tunnel 127.0.0.1:" .. TUNNEL_PORT)
        pcall(function()
            require("love.filesystem")
            love.filesystem.append("mp_connection.log", os.date("%Y-%m-%d %H:%M:%S") .. " TUNNEL_CONNECT: host=" .. tostring(host) .. " port=" .. tostring(port) .. " tunnel_port=" .. tostring(TUNNEL_PORT) .. "\n")
        end)

        local res, conn_err = t:connect("127.0.0.1", TUNNEL_PORT)
        if not res then
            status_ch:push("ERROR:tunnel_fail:TLS tunnel not running on 127.0.0.1:" .. TUNNEL_PORT .. " (" .. tostring(conn_err) .. ")")
            pcall(function()
                require("love.filesystem")
                love.filesystem.append("mp_connection.log", os.date("%Y-%m-%d %H:%M:%S") .. " TUNNEL_FAIL: " .. tostring(conn_err) .. "\n")
            end)
            pcall(function() t:close() end)
            return false
        end

        local send_ok, send_err = t:send(host .. ":" .. port .. "\n")
        if not send_ok then
            status_ch:push("ERROR:tunnel_send:Failed to send target to tunnel: " .. tostring(send_err))
            pcall(function() t:close() end)
            return false
        end

        t:settimeout(15)
        local response, recv_err = t:receive("*l")
        if not response then
            status_ch:push("ERROR:tunnel_timeout:No response from TLS tunnel: " .. tostring(recv_err))
            pcall(function() t:close() end)
            return false
        end

        if response ~= "OK" then
            status_ch:push("ERROR:tunnel_tls:" .. tostring(response))
            pcall(function() t:close() end)
            return false
        end

        status_ch:push("STATUS:tunnel_ok:TLS established via tunnel to " .. host .. ":" .. port)
        status_ch:push("STATUS:waiting:server reached, waiting for its answer")
        pcall(function()
            require("love.filesystem")
            love.filesystem.append("mp_connection.log", os.date("%Y-%m-%d %H:%M:%S") .. " TUNNEL_OK: TLS to " .. tostring(host) .. ":" .. tostring(port) .. "\n")
        end)
    else
        local res, conn_err = t:connect(host, port)
        if not res then
            status_ch:push("ERROR:tcp_fail:TCP connect failed: " .. tostring(conn_err))
            pcall(function() t:close() end)
            return false
        end
        status_ch:push("STATUS:waiting:server reached, waiting for its answer")
    end

    local key = generate_ws_key()
    local handshake = "GET " .. path .. " HTTP/1.1\r\n" ..
        "Host: " .. host .. (port ~= 80 and port ~= 443 and (":" .. port) or "") .. "\r\n" ..
        "Upgrade: websocket\r\n" ..
        "Connection: Upgrade\r\n" ..
        "Sec-WebSocket-Key: " .. key .. "\r\n" ..
        "Sec-WebSocket-Version: 13\r\n" ..
        "\r\n"

    local send_ok, send_err = t:send(handshake)
    if not send_ok then
        status_ch:push("ERROR:handshake_send:Failed to send handshake: " .. tostring(send_err))
        pcall(function() t:close() end)
        return false
    end

    t:settimeout(10)
    local response_line, recv_err = t:receive("*l")
    if not response_line then
        status_ch:push("ERROR:handshake_recv:No handshake response: " .. tostring(recv_err))
        pcall(function() t:close() end)
        return false
    end
    if not response_line:match("101") then
        status_ch:push("ERROR:handshake_fail:Handshake rejected: " .. tostring(response_line))
        pcall(function() t:close() end)
        return false
    end
    while true do
        local line = t:receive("*l")
        if not line or line == "" then break end
    end

    t:settimeout(0)
    tcp = t
    connected = true
    buffer = ""
    frag_parts = nil
    status_ch:push("CONNECTED:ok:WebSocket connected to " .. host .. ":" .. port)
    pcall(function()
        require("love.filesystem")
        love.filesystem.append("mp_connection.log", os.date("%Y-%m-%d %H:%M:%S") .. " CONNECTED: WebSocket to " .. tostring(host) .. ":" .. tostring(port) .. " (TCP/tunnel)\n")
    end)
    return true
end

local function do_disconnect()
    if using_winhttp then
        wrecv_gen = wrecv_gen + 1
        winhttp_close_all()
        using_winhttp = false
        connected = false
        buffer = ""
        frag_parts = nil
        status_ch:push("DISCONNECTED:ok:Closed")
        return
    end
    if tcp then
        pcall(function() tcp:send(ws_encode_close()) end)
        pcall(function() tcp:close() end)
    end
    tcp = nil
    connected = false
    buffer = ""
    frag_parts = nil
    status_ch:push("DISCONNECTED:ok:Closed")
end

local function do_send(text)
    if using_winhttp then
        if not winhttp_ws_send(text) then
            status_ch:push("ERROR:send_fail:WinHTTP send error")
            do_disconnect()
        end
        return
    end
    if not connected or not tcp then
        status_ch:push("ERROR:send_fail:Not connected")
        return
    end
    local ok, err = pcall(function()
        local frame = ws_encode_frame(text)
        local total = #frame
        local i = 1
        local deadline = socket.gettime() + 30
        while i <= total do
            local last, serr, partial = tcp:send(frame, i)
            if last then
                i = last + 1
            elseif serr == "timeout" or serr == "wantwrite" then
                if partial and partial >= i then i = partial + 1 end
                if socket.gettime() > deadline then error("send timed out") end
                socket.sleep(0.002)
            else
                error(tostring(serr))
            end
        end
    end)
    if not ok then
        status_ch:push("ERROR:send_fail:" .. tostring(err))
        do_disconnect()
    end
end

local function process_frames()
    if using_winhttp then
        local recv_err = nil
        local e = wrecv_ch:pop()
        while e do
            local g, rest = tostring(e):match("^(%d+):(.*)$")
            if tonumber(g) == wrecv_gen then recv_err = rest end
            e = wrecv_ch:pop()
        end
        if not recv_err and wrecv_thread and wrecv_thread:getError() then
            recv_err = "receiver crashed: " .. tostring(wrecv_thread:getError())
        end
        if recv_err then
            status_ch:push("DISCONNECTED:winhttp:" .. tostring(recv_err))
            wrecv_gen = wrecv_gen + 1
            winhttp_close_all()
            using_winhttp = false
            connected = false
        end
        return
    end
    if not connected or not tcp then return end

    local ok, err = pcall(function()
        local parts = {}
        for _ = 1, 64 do
            local data, read_err, partial = tcp:receive(65536)
            local chunk = data or partial
            if chunk and #chunk > 0 then
                parts[#parts + 1] = chunk
            end
            if read_err and read_err ~= "timeout" and read_err ~= "wantread" then
                if #parts > 0 then buffer = buffer .. table.concat(parts) end
                error("read error: " .. tostring(read_err))
            end
            if not data then break end
        end
        if #parts > 0 then buffer = buffer .. table.concat(parts) end

        local iterations = 0
        while #buffer >= 2 and iterations < 100 do
            iterations = iterations + 1
            local b1 = buffer:byte(1)
            local b2 = buffer:byte(2)
            local opcode = bit.band(b1, 0x0F)
            local is_fin = bit.band(b1, 0x80) ~= 0
            local is_masked = bit.band(b2, 0x80) ~= 0
            local payload_len = bit.band(b2, 0x7F)
            local header_size = 2

            if payload_len == 126 then
                if #buffer < 4 then break end
                payload_len = buffer:byte(3) * 256 + buffer:byte(4)
                header_size = 4
            elseif payload_len == 127 then
                if #buffer < 10 then break end
                payload_len = 0
                for i = 3, 10 do payload_len = payload_len * 256 + buffer:byte(i) end
                header_size = 10
            end

            if is_masked then header_size = header_size + 4 end
            if #buffer < header_size + payload_len then break end

            local payload
            if is_masked then
                local ms = header_size - 3
                local mk = { buffer:byte(ms), buffer:byte(ms+1), buffer:byte(ms+2), buffer:byte(ms+3) }
                local bytes = {}
                for i = 1, payload_len do
                    bytes[i] = string.char(bit.bxor(buffer:byte(header_size + i), mk[(i-1) % 4 + 1]))
                end
                payload = table.concat(bytes)
            else
                payload = buffer:sub(header_size + 1, header_size + payload_len)
            end

            buffer = buffer:sub(header_size + payload_len + 1)

            if opcode == 0x00 then
                if frag_parts then
                    frag_parts[#frag_parts + 1] = payload
                    if is_fin then
                        msg_ch:push(table.concat(frag_parts))
                        frag_parts = nil
                    end
                end
            elseif opcode == 0x01 then
                if is_fin then
                    msg_ch:push(payload)
                else
                    frag_parts = { payload }
                end
            elseif opcode == 0x08 then
                do_disconnect()
                return
            elseif opcode == 0x09 then
                pcall(function() tcp:send(ws_encode_pong(payload)) end)
            end
        end
    end)

    if not ok then
        status_ch:push("ERROR:frame_error:" .. tostring(err))
        do_disconnect()
    end
end

while true do
    local cmd
    if connected then
        cmd = cmd_ch:pop()
    else
        cmd = cmd_ch:demand(0.1)
    end

    local handled = 0
    while cmd do
        handled = handled + 1
        if cmd == "QUIT" then
            do_disconnect()
            return
        elseif cmd:sub(1, 8) == "CONNECT:" then
            local target = cmd:sub(9)
            local dc_ok, dc_err = pcall(do_connect, target)
            if not dc_ok then
                status_ch:push("ERROR:connect_crash:" .. tostring(dc_err))
            end
        elseif cmd == "CLOSE" then
            local cl_ok, cl_err = pcall(do_disconnect)
            if not cl_ok then
                connected = false
                using_winhttp = false
                status_ch:push("DISCONNECTED:error:" .. tostring(cl_err))
            end
        elseif cmd:sub(1, 5) == "SEND:" then
            do_send(cmd:sub(6))
        elseif cmd == "PROBE" then
            status_ch:push("PROBE:true:luasocket available")
        end
        cmd = (connected and handled < 64) and cmd_ch:pop() or nil
    end

    if connected then
        process_frames()
    end

    if not connected then
        socket.sleep(0.05)
    else
        socket.sleep(0.01)
    end
end
]]

function AndroidWS.init()
    if _initialized then return end
    _initialized = true

    _cmd_channel = love.thread.getChannel("aws_cmd")
    _msg_channel = love.thread.getChannel("aws_msg")
    _status_channel = love.thread.getChannel("aws_status")

    _cmd_channel:clear()
    _msg_channel:clear()
    _status_channel:clear()

    local nt_ok, nt_err
    nt_ok, _thread = pcall(love.thread.newThread, WORKER_CODE)
    if not nt_ok then
        _last_error = "Thread creation failed: " .. tostring(_thread)
        _thread = nil
        _socket_available = false
        if mp_log then mp_log.error("AndroidWS", "newThread failed: %s", tostring(_last_error)) end
        return
    end
    local ok, err = pcall(function() _thread:start() end)
    if not ok then
        _last_error = "Thread start failed: " .. tostring(err)
        _socket_available = false
        return
    end

    _cmd_channel:push("PROBE")
end

function AndroidWS.poll()
    if not _status_channel then return end

    if _thread and not _thread:isRunning() then
        local thread_err = _thread:getError()
        if thread_err then
            _last_error = "Worker thread crashed: " .. tostring(thread_err)
            _connected = false
            mp_log.error("AndroidWS", "Worker thread error: %s", tostring(thread_err))
            _thread = nil
            _initialized = false
        end
    end

    local iterations = 0
    while iterations < 50 do
        iterations = iterations + 1
        local status = _status_channel:pop()
        if not status then break end

        local kind, code, detail = status:match("^(%w+):([^:]*):?(.*)")
        if kind == "PROBE" then
            _socket_available = (code == "true")
            if not _socket_available then
                _last_error = detail or "luasocket not available"
            end
            mp_log.info("AndroidWS", "Probe result: socket=%s %s", tostring(_socket_available), tostring(detail))
        elseif kind == "CONNECTED" then
            _connected = true
            _last_error = nil
            mp_log.info("AndroidWS", "Connected: %s", tostring(detail))
        elseif kind == "DISCONNECTED" then
            _connected = false
            mp_log.info("AndroidWS", "Disconnected: %s", tostring(detail))
        elseif kind == "ERROR" then
            _last_error = (code or "") .. ": " .. (detail or "")
            mp_log.error("AndroidWS", "Error: %s", tostring(_last_error))
        elseif kind == "DEBUG_URL" then
            local rest = status:sub(#"DEBUG_URL:" + 1)
            local parts = {}
            for part in rest:gmatch("[^|]+") do
                parts[#parts + 1] = part
            end
            _debug_url = parts[1] or "?"
            _debug_host = parts[2] or "?"
            _debug_path = parts[3] or "?"
            mp_log.debug("AndroidWS", "DEBUG_URL: %s host=%s path=%s", tostring(_debug_url), tostring(_debug_host), tostring(_debug_path))
        elseif kind == "STATUS" then
            _last_status = (detail and detail ~= "") and detail or code
            if code == "waiting" then _waiting = true end
            mp_log.debug("AndroidWS", "Status: %s %s", tostring(code), tostring(detail))
        end
    end
end


function AndroidWS.connect(url)
    if not _initialized then AndroidWS.init() end
    if not _cmd_channel then
        _last_error = "Bridge not initialized"
        return
    end
    if _thread and not _thread:isRunning() then
        local thread_err = _thread:getError()
        if thread_err then
            mp_log.warn("AndroidWS", "Worker thread died: %s - respawning", tostring(thread_err))
        else
            mp_log.warn("AndroidWS", "Worker thread stopped - respawning")
        end
        _initialized = false
        _thread = nil
        AndroidWS.init()
        if not _cmd_channel then
            _last_error = "Bridge respawn failed"
            return
        end
    end
    _last_error = nil
    _last_status = nil
    _waiting = false
    _connected = false
    if _status_channel then _status_channel:clear() end
    if _msg_channel then _msg_channel:clear() end
    _cmd_channel:push("CONNECT:" .. tostring(url))
end

function AndroidWS.send(text)
    if not _connected or not _cmd_channel then return false end
    _cmd_channel:push("SEND:" .. tostring(text))
    return true
end

function AndroidWS.receive()
    if not _msg_channel then return nil end
    return _msg_channel:pop()
end

function AndroidWS.close()
    if not _cmd_channel then return end
    _cmd_channel:push("CLOSE")
    _connected = false
end

function AndroidWS.isConnected()
    return _connected
end

function AndroidWS.lastStatus()
    return _last_status
end

function AndroidWS.isWaiting()
    return _waiting
end

function AndroidWS.lastError()
    return _last_error
end

function AndroidWS.socketAvailable()
    return _socket_available
end

function AndroidWS.debugURL()
    return _debug_url
end

function AndroidWS.debugHost()
    return _debug_host
end

function AndroidWS.debugPath()
    return _debug_path
end

function AndroidWS.shutdown()
    if _cmd_channel then
        _cmd_channel:push("QUIT")
    end
    _connected = false
    _initialized = false
end

mp_log.info("ANDROID_WS", "AndroidWS bridge module loaded")
return AndroidWS
