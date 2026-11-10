
local bom_core = {}


bom_core.json = {}

local json = bom_core.json

function bom_core.plain_number(v)
    if type(v) == "number" then return v end
    if v == nil then return 0 end
    if type(v) == "cdata" or type(v) == "table" then
        if to_number then
            local ok, n = pcall(to_number, v)
            if ok and type(n) == "number" then return n end
        end
        if type(v.to_number) == "function" then
            local ok, n = pcall(v.to_number, v)
            if ok and type(n) == "number" then return n end
        end
        if type(v) == "table" and type(v.val) == "number" then return v.val end
    end
    return tonumber(v) or 0
end

local function json_encode_value(val, depth)
    depth = depth or 0
    if depth > 50 then return '"[max depth]"' end
    local t = type(val)
    if val == nil then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val ~= val then return "null" end
        if val == math.huge or val == -math.huge then return "null" end
        return tostring(val)
    elseif t == "cdata" or (t == "table" and is_big and is_big(val)) then
        local n = bom_core.plain_number(val)
        if n ~= n then return "null" end
        if n == math.huge then return '"inf"' end
        if n == -math.huge then return "null" end
        return tostring(n)
    elseif t == "string" then
        local s = val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
        return '"' .. s .. '"'
    elseif t == "table" then
        local is_array = true
        local max_i = 0
        local count = 0
        for k, _ in pairs(val) do
            count = count + 1
            if type(k) == "number" and k == math.floor(k) and k >= 1 then
                if k > max_i then max_i = k end
            else
                is_array = false
                break
            end
        end
        if is_array and max_i == count then
            local parts = {}
            for i = 1, max_i do
                parts[i] = json_encode_value(val[i], depth + 1)
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                if type(k) == "string" then
                    parts[#parts + 1] = json_encode_value(k, depth + 1) .. ":" .. json_encode_value(v, depth + 1)
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

function json.encode(val)
    local ok, result = pcall(json_encode_value, val, 0)
    if ok then return result end
    return "{}"
end

local function skip_ws(s, i)
    while i <= #s do
        local c = s:byte(i)
        if c == 32 or c == 9 or c == 10 or c == 13 then i = i + 1
        else break end
    end
    return i
end

local json_parse_value

local function json_parse_string(s, i)
    i = i + 1
    local parts = {}
    local n = #s
    while i <= n do
        local j = s:find('["\\]', i)
        if not j then
            parts[#parts + 1] = s:sub(i)
            i = n + 1
            break
        end
        if j > i then parts[#parts + 1] = s:sub(i, j - 1) end
        i = j
        local c = s:sub(i, i)
        if c == '"' then
            return table.concat(parts), i + 1
        elseif c == '\\' then
            i = i + 1
            local esc = s:sub(i, i)
            if esc == '"' then parts[#parts + 1] = '"'
            elseif esc == '\\' then parts[#parts + 1] = '\\'
            elseif esc == '/' then parts[#parts + 1] = '/'
            elseif esc == 'n' then parts[#parts + 1] = '\n'
            elseif esc == 'r' then parts[#parts + 1] = '\r'
            elseif esc == 't' then parts[#parts + 1] = '\t'
            else parts[#parts + 1] = esc end
            i = i + 1
        else
            parts[#parts + 1] = c
            i = i + 1
        end
    end
    return table.concat(parts), i
end

local function json_parse_number(s, i)
    local j = i
    if s:sub(j, j) == '-' then j = j + 1 end
    while j <= #s and s:byte(j) >= 48 and s:byte(j) <= 57 do j = j + 1 end
    if j <= #s and s:sub(j, j) == '.' then
        j = j + 1
        while j <= #s and s:byte(j) >= 48 and s:byte(j) <= 57 do j = j + 1 end
    end
    if j <= #s and (s:sub(j, j) == 'e' or s:sub(j, j) == 'E') then
        j = j + 1
        if j <= #s and (s:sub(j, j) == '+' or s:sub(j, j) == '-') then j = j + 1 end
        while j <= #s and s:byte(j) >= 48 and s:byte(j) <= 57 do j = j + 1 end
    end
    return tonumber(s:sub(i, j - 1)), j
end

local function json_parse_object(s, i)
    i = i + 1
    local obj = {}
    i = skip_ws(s, i)
    if s:sub(i, i) == '}' then return obj, i + 1 end
    while i <= #s do
        i = skip_ws(s, i)
        local key
        key, i = json_parse_string(s, i)
        i = skip_ws(s, i)
        i = i + 1
        i = skip_ws(s, i)
        local val
        val, i = json_parse_value(s, i)
        obj[key] = val
        i = skip_ws(s, i)
        local c = s:sub(i, i)
        if c == '}' then return obj, i + 1 end
        i = i + 1
    end
    return obj, i
end

local function json_parse_array(s, i)
    i = i + 1
    local arr = {}
    i = skip_ws(s, i)
    if s:sub(i, i) == ']' then return arr, i + 1 end
    while i <= #s do
        i = skip_ws(s, i)
        local val
        val, i = json_parse_value(s, i)
        arr[#arr + 1] = val
        i = skip_ws(s, i)
        local c = s:sub(i, i)
        if c == ']' then return arr, i + 1 end
        i = i + 1
    end
    return arr, i
end

json_parse_value = function(s, i)
    i = skip_ws(s, i)
    local c = s:sub(i, i)
    if c == '"' then return json_parse_string(s, i)
    elseif c == '{' then return json_parse_object(s, i)
    elseif c == '[' then return json_parse_array(s, i)
    elseif c == 't' then return true, i + 4
    elseif c == 'f' then return false, i + 5
    elseif c == 'n' then return nil, i + 4
    else return json_parse_number(s, i)
    end
end

function json.decode(s)
    if not s or s == "" then return nil end
    local ok, val = pcall(json_parse_value, s, 1)
    if ok then return val end
    return nil
end



local SERVER_URL = mp_config and mp_config.SERVER_URL or "wss://balatro-overhaul-muliplayer.onrender.com/ws"
local reconnect_timer = 0
local RECONNECT_DELAY = mp_config and mp_config.RECONNECT_DELAY or 3
local reconnect_callback = nil
local heartbeat_timer = 0
local HEARTBEAT_INTERVAL = mp_config and mp_config.HEARTBEAT_INTERVAL or 25
local connect_timeout_timer = 0
local CONNECT_TIMEOUT = mp_config and mp_config.CONNECT_TIMEOUT or 15
local REACH_TIMEOUT = mp_config and mp_config.REACH_TIMEOUT or 20
local connect_extended = false
local was_connected = false

local LOC = {
    fr = {
        ["Could not reach the server in %d seconds."] = "Impossible de joindre le serveur en %d secondes.",
        ["The server did not answer in %d seconds."] = "Le serveur n'a pas répondu en %d secondes.",
        ["Last step: %s"] = "Dernière étape : %s",
        ["Connection failed: %s"] = "Échec de la connexion : %s",
        ["The secure connection helper is not running. Start the game from the launcher (it needs python3)."] = "L'assistant de connexion sécurisée ne tourne pas. Lance le jeu depuis le launcher (il faut python3).",
    },
    es = {
        ["Could not reach the server in %d seconds."] = "No se pudo contactar con el servidor en %d segundos.",
        ["The server did not answer in %d seconds."] = "El servidor no respondió en %d segundos.",
        ["Last step: %s"] = "Último paso: %s",
        ["Connection failed: %s"] = "Error de conexión: %s",
        ["The secure connection helper is not running. Start the game from the launcher (it needs python3)."] = "El asistente de conexión segura no está en marcha. Abre el juego desde el launcher (necesita python3).",
    },
}
local loc_done = false

local function loc(s)
    if not loc_done and mod_loc_register then
        loc_done = true
        mod_loc_register(LOC)
    end
    return mod_loc and mod_loc(s) or s
end

local function short(s, n)
    s = tostring(s or "")
    if #s > n then s = s:sub(1, n - 3) .. "..." end
    return s
end

function bom_core.is_connected()
    if AndroidWS then return AndroidWS.isConnected() end
    return false
end

local connect_opts = nil

local function connect_failed(msg)
    local opts = connect_opts
    connect_opts = nil
    if opts and opts.on_fail then pcall(opts.on_fail, msg) end
    if opts and opts.silent then return end
    pcall(function()
        if bom_ui and bom_ui.hide_connecting_screen then bom_ui.hide_connecting_screen() end
        if bom_ui and bom_ui.show_error then bom_ui.show_error(msg) end
    end)
end

function bom_core.connect(on_ready, opts)
    if bom_core.is_connected() then
        if on_ready then on_ready() end
        return
    end

    if reconnect_callback then
        local first, first_opts = reconnect_callback, connect_opts
        reconnect_callback = function()
            if type(first) == "function" then pcall(first) end
            if on_ready then on_ready() end
        end
        connect_opts = {
            silent = (first_opts and first_opts.silent and opts and opts.silent) or false,
            on_fail = function(msg)
                if first_opts and first_opts.on_fail then pcall(first_opts.on_fail, msg) end
                if opts and opts.on_fail then pcall(opts.on_fail, msg) end
            end,
        }
        return
    end

    reconnect_callback = on_ready
    connect_opts = opts
    connect_timeout_timer = REACH_TIMEOUT
    connect_extended = false

    if not AndroidWS then
        mp_log.error("BOM_CORE", "AndroidWS bridge not available!")
        reconnect_callback = nil
        pcall(function()
            if bom_ui and bom_ui.hide_connecting_screen then bom_ui.hide_connecting_screen() end
            if bom_ui and bom_ui.show_error then bom_ui.show_error("WebSocket bridge not available.") end
        end)
        return
    end

    mp_log.info("BOM_CORE", "Connecting via AndroidWS to %s", SERVER_URL)
    AndroidWS.connect(SERVER_URL)
end

function bom_core.player_key()
    if not (G and G.SETTINGS) then return nil end
    local k = G.SETTINGS.mp_player_key
    if type(k) ~= "string" or not k:match("^[A-Za-z0-9]+$") or #k ~= 24 then
        local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        local t = {}
        for i = 1, 24 do
            local r = math.random(1, #chars)
            t[i] = chars:sub(r, r)
        end
        k = table.concat(t)
        G.SETTINGS.mp_player_key = k
        if G.save_settings then pcall(G.save_settings, G) end
    end
    return k
end

function bom_core.send(data, opts)
    if not bom_core.is_connected() then
        if bom_rejoin and bom_rejoin.queue_offline then pcall(bom_rejoin.queue_offline, data) end
        return false
    end
    if not AndroidWS then return false end
    if type(data) == "table" and data.name ~= nil and data.pkey == nil then data.pkey = bom_core.player_key() end
    local encoded = json.encode(data)
    if opts and opts.raw then return AndroidWS.send(encoded) end
    if #encoded > 300 and love and love.data and love.data.compress then
        local ok_c, compressed = pcall(love.data.compress, "string", "deflate", encoded)
        if ok_c and compressed and #compressed < #encoded then
            local ok_b, b64 = pcall(love.data.encode, "string", "base64", compressed)
            if ok_b and b64 then
                encoded = '{"z":1,"d":"' .. b64 .. '"}'
            end
        end
    end
    return AndroidWS.send(encoded)
end

local mod_list_cache = nil

local function clip(v, n)
    local t = tostring(v or ""):gsub("%c", "")
    if #t > n then t = t:sub(1, n) end
    return t
end

function bom_core.mod_list()
    if mod_list_cache then return mod_list_cache end
    local list = {}
    pcall(function()
        local L = rawget(_G, "MODLOADER")
        if not (L and L.active and L.status) then return end
        local st = L.status()
        for _, e in ipairs(st and st.mods or {}) do
            if e.loaded then
                local id = clip(e.id or e.folder, 64)
                if id ~= "" then
                    list[#list + 1] = { id = id, name = clip(e.name or id, 64), version = clip(e.version, 32) }
                end
            end
        end
        if #list == 0 then
            local S = rawget(_G, "SMODS")
            list[1] = { id = "Steamodded", name = "Steamodded", version = clip(S and S.version, 32) }
        end
        for _, m in ipairs(list) do if m.name == "" then m.name = m.id end end
        table.sort(list, function(a, b) return a.id < b.id end)
    end)
    mod_list_cache = list
    return list
end

function bom_core.mods_field()
    local list = bom_core.mod_list()
    if #list == 0 then return nil end
    return list
end

function bom_core.is_modded()
    return #bom_core.mod_list() > 0
end

function bom_core.same_mods(a, b)
    a, b = a or {}, b or {}
    if #a ~= #b then return false end
    local want = {}
    for _, m in ipairs(a) do want[tostring(m.id)] = tostring(m.version or "") end
    for _, m in ipairs(b) do
        if want[tostring(m.id)] ~= tostring(m.version or "") then return false end
    end
    return true
end

bom_core.rtt = nil
local ping_sent_at = nil

local function send_ping()
    ping_sent_at = love.timer.getTime()
    bom_core.send({ type = "ping", rtt = bom_core.rtt })
end

function bom_core.on_pong()
    if not ping_sent_at then return end
    local first = bom_core.rtt == nil
    bom_core.rtt = math.max(0, math.min(60000, math.floor((love.timer.getTime() - ping_sent_at) * 1000 + 0.5)))
    ping_sent_at = nil
    if first then send_ping() end
end

function bom_core.update(dt)
    if not AndroidWS then return end
    if bom_match and bom_match.tick_ante_timer then pcall(bom_match.tick_ante_timer) end

    local max_msgs = mp_config and mp_config.MAX_MSG_PER_FRAME or 50
    local iterations = 0
    while iterations < max_msgs do
        iterations = iterations + 1
        local msg = AndroidWS.receive()
        if not msg then break end

        if msg:sub(1, 6) == '{"z":1' and love and love.data then
            local ok_env, envelope = pcall(json.decode, msg)
            if ok_env and envelope and envelope.z == 1 and type(envelope.d) == "string" then
                local ok_d, decoded = pcall(love.data.decode, "string", "base64", envelope.d)
                if ok_d and decoded then
                    local ok_u, decompressed = pcall(love.data.decompress, "string", "deflate", decoded)
                    if ok_u and decompressed then msg = decompressed end
                end
            end
        end

        if mp_log.enabled("DEBUG") then mp_log.debug("BOM_CORE", "Received message: %s", tostring(msg):sub(1, 200)) end
        local ok, data = pcall(json.decode, msg)
        if ok and data and data.type then
            local ok_disp, err_disp = pcall(function()
                if bom_events and bom_events.dispatch then
                    bom_events.dispatch(data)
                end
            end)
            if not ok_disp then
                mp_log.error("BOM_CORE", "Event dispatch failed (type=%s): %s", tostring(data.type), tostring(err_disp))
            end
        else
            pcall(function()
                require("functions/fast_fs").append("mp_match_debug.txt",
                    "\n[UNDECODED] bytes=" .. tostring(#msg) .. " head=" .. msg:sub(1, 60))
            end)
        end
    end

    local connected_now = AndroidWS.isConnected()
    if was_connected and not connected_now then
        mp_log.warn("BOM_CORE", "Connection lost")
        pcall(function()
            require("functions/fast_fs").append("mp_match_debug.txt", "\n[CONNECTION_LOST] own socket dropped")
        end)
        local ok_lost, err_lost = pcall(function()
            if bom_rejoin and bom_rejoin.on_connection_lost then
                bom_rejoin.on_connection_lost()
            elseif bom_match and bom_match.is_in_match and bom_match.is_in_match()
                and not bom_match.get_state().match_over then
                bom_match.end_match("lose", "connection_lost")
            end
        end)
        if not ok_lost then mp_log.error("BOM_CORE", "connection lost handler failed: %s", tostring(err_lost)) end
    end
    was_connected = connected_now
    if connected_now and reconnect_callback then
        local cb = reconnect_callback
        reconnect_callback = nil
        connect_opts = nil
        reconnect_timer = 0
        heartbeat_timer = 0
        connect_timeout_timer = 0
        mp_log.info("BOM_CORE", "Connected successfully")
        pcall(send_ping)
        if type(cb) == "function" then
            local ok, err = pcall(cb)
            if not ok then
                mp_log.error("BOM_CORE", "Callback error: %s", tostring(err))
            end
        else
            mp_log.error("BOM_CORE", "reconnect_callback was %s, not function", type(cb))
        end
    end

    if not connected_now and reconnect_callback then
        local ws_err = AndroidWS and AndroidWS.lastError()
        if ws_err then
            mp_log.warn("BOM_CORE", "Connection failed: %s", tostring(ws_err))
            reconnect_callback = nil
            connect_timeout_timer = 0
            pcall(function()
                if AndroidWS and AndroidWS.close then AndroidWS.close() end
            end)
            pcall(function()
                require("functions/fast_fs").append("mp_connection.log", os.date("%Y-%m-%d %H:%M:%S") .. " CONNECT_FAILED: " .. tostring(ws_err) .. "\n")
            end)
            if tostring(ws_err):find("tunnel_fail", 1, true) then
                connect_failed(loc("The secure connection helper is not running. Start the game from the launcher (it needs python3)."))
            else
                connect_failed(string.format(loc("Connection failed: %s"), short(ws_err, 80)))
            end
        else
            if not connect_extended and AndroidWS.isWaiting and AndroidWS.isWaiting() then
                connect_extended = true
                connect_timeout_timer = connect_timeout_timer + math.max(0, CONNECT_TIMEOUT - REACH_TIMEOUT)
            end
            connect_timeout_timer = connect_timeout_timer - (dt or 0)
            if connect_timeout_timer <= 0 then
                local step = AndroidWS.lastStatus and AndroidWS.lastStatus() or nil
                local secs = connect_extended and CONNECT_TIMEOUT or REACH_TIMEOUT
                mp_log.warn("BOM_CORE", "Connection timed out after %ds (last step: %s)", secs, tostring(step))
                pcall(function()
                    require("functions/fast_fs").append("mp_connection.log", os.date("%Y-%m-%d %H:%M:%S") .. " CONNECT_TIMEOUT: " .. tostring(secs) .. "s last_step=" .. tostring(step) .. "\n")
                end)
                reconnect_callback = nil
                connect_timeout_timer = 0
                pcall(function()
                    if AndroidWS and AndroidWS.close then AndroidWS.close() end
                end)
                local head = string.format(loc(connect_extended and "The server did not answer in %d seconds." or "Could not reach the server in %d seconds."), secs)
                connect_failed(step and (head .. " " .. string.format(loc("Last step: %s"), short(step, 60))) or head)
            end
        end
    end

    if connected_now then
        heartbeat_timer = heartbeat_timer + (dt or 0)
        if heartbeat_timer >= HEARTBEAT_INTERVAL then
            heartbeat_timer = 0
            mp_log.debug("BOM_CORE", "Sending ping")
            send_ping()
        end
    end
end

function bom_core.disconnect()
    if AndroidWS then
        AndroidWS.close()
    end
    was_connected = false
    reconnect_callback = nil
    connect_opts = nil
    reconnect_timer = 0
    heartbeat_timer = 0
    connect_timeout_timer = 0
end

function bom_core.get_server_url()
    return SERVER_URL
end

mp_log.info("BOM_CORE", "Multiplayer core module loaded")
return bom_core
