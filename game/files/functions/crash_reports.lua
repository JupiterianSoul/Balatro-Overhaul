CrashReports = CrashReports or {}

local PENDING = "crash_reports/pending.txt"
local ATTEMPTS = "crash_reports/attempts.txt"
local MAX_ATTEMPTS = 5
local DEFAULT_URL = "wss://balatro-overhaul-muliplayer.onrender.com/ws"
local INSTALL_ID = "crash_reports/install_id.txt"
local MAX_ACTIONS = 25
local MAX_LOG = 40
CrashReports.actions = CrashReports.actions or {}
CrashReports.log = CrashReports.log or {}

local THREAD_CODE = [[
require("love.filesystem")
local url, body, pending, attempts, channel = ...
local code = 0
if url:match("^https://") then
    local ok, https = pcall(require, "https")
    if ok and https and https.request then
        local ok2, c = pcall(https.request, url, {method = "POST", headers = {["Content-Type"] = "application/json"}, data = body})
        code = ok2 and tonumber(c) or 0
    end
else
    local ok, http = pcall(require, "socket.http")
    local ok2, ltn12 = pcall(require, "ltn12")
    if ok and ok2 and http and ltn12 then
        http.TIMEOUT = 15
        local ok3, _, c = pcall(http.request, {url = url, method = "POST", source = ltn12.source.string(body), sink = ltn12.sink.null(),
            headers = {["Content-Type"] = "application/json", ["Content-Length"] = tostring(#body)}})
        code = ok3 and tonumber(c) or 0
    end
end
if code >= 200 and code < 300 or (code >= 400 and code < 500 and code ~= 429) then
    love.filesystem.remove(pending)
    love.filesystem.remove(attempts)
end
love.thread.getChannel(channel):push(code)
]]

local function json_string(s)
    s = tostring(s or "")
    s = s:gsub('[%c"\\]', function(c)
        if c == '"' then return '\\"' end
        if c == "\\" then return "\\\\" end
        if c == "\n" then return "\\n" end
        if c == "\r" then return "\\r" end
        if c == "\t" then return "\\t" end
        return string.format("\\u%04x", c:byte())
    end)
    s = s:gsub("[\128-\255]", "?")
    return '"' .. s .. '"'
end

CrashReports.TEST_RUN_ENV = {"SHOT_STEPS", "SHOT_OUT", "SOAK_OUT", "LOADING_SHOT_DIR", "LAUNCHER_SHOT_DIR", "BOT_VERSUS_WINDOW"}

function CrashReports.test_run()
    for _, k in ipairs(CrashReports.TEST_RUN_ENV) do
        local v = os.getenv(k)
        if v and v ~= "" then return true end
    end
    return false
end

function CrashReports.url()
    local env = os.getenv("OVERHAUL_CRASH_URL")
    if env and env ~= "" then return env end
    if CrashReports.test_run() then return "http://127.0.0.1:9/crash" end
    local cfg = rawget(_G, "mp_config")
    local ws = (type(cfg) == "table" and cfg.SERVER_URL) or DEFAULT_URL
    return (tostring(ws):gsub("^wss://", "https://"):gsub("^ws://", "http://"):gsub("/ws/?$", "")) .. "/crash"
end

function CrashReports.migrate()
    local St = G and G.SETTINGS
    if not St or St.crashreports_choice ~= nil then return end
    St.crashreports = true
    St.crashreports_choice = 'default'
    if G.save_settings then pcall(function() G:save_settings() end) end
end

function CrashReports.chose()
    if G and G.SETTINGS then G.SETTINGS.crashreports_choice = 'player' end
end

function CrashReports.enabled()
    return not (G and G.SETTINGS and G.SETTINGS.crashreports == false)
end

local function push(list, max, line)
    list[#list + 1] = line
    if #list > max then table.remove(list, 1) end
end

function CrashReports.note(what)
    local t = love.timer and love.timer.getTime() or 0
    push(CrashReports.actions, MAX_ACTIONS, string.format("%8.1f %s", t, tostring(what):sub(1, 160)))
end

function CrashReports.install_id()
    if CrashReports.id then return CrashReports.id end
    local id = love.filesystem.read(INSTALL_ID)
    if not id or not id:match("^%x+$") or #id ~= 16 then
        local parts = {}
        for i = 1, 4 do parts[i] = string.format("%04x", love.math.random(0, 65535)) end
        id = table.concat(parts)
        love.filesystem.createDirectory("crash_reports")
        love.filesystem.write(INSTALL_ID, id)
    end
    CrashReports.id = id
    return id
end

local function os_name()
    local base = love.system and love.system.getOS() or "?"
    if base == "Linux" then
        local f = io.open("/etc/os-release", "r")
        if f then
            local txt = f:read("*a") or ""
            f:close()
            local pretty = txt:match('PRETTY_NAME="([^"]+)"')
            if pretty then return base .. " (" .. pretty .. ")" end
        end
    end
    return base
end

local function state_name(v, tbl)
    for k, n in pairs(tbl or {}) do if n == v then return k end end
    return tostring(v)
end

function CrashReports.context()
    local out = {}
    local function add(k, f)
        local ok, v = pcall(f)
        out[#out + 1] = k .. ": " .. (ok and tostring(v) or "?")
    end
    out[#out + 1] = "Report id: " .. string.format("%04x%04x%04x", love.math.random(0, 65535), love.math.random(0, 65535), love.math.random(0, 65535))
    add("Build", function() return tostring(rawget(_G, "OVERHAUL_VERSION") or "?") .. " (version " .. tostring(rawget(_G, "OVERHAUL_NAME") or "?") .. ")" end)
    add("OS", function()
        local cores = love.system.getProcessorCount and love.system.getProcessorCount() or "?"
        local r = {love.graphics.getRendererInfo()}
        return os_name() .. ", " .. tostring(cores) .. " cores, " .. tostring(r[4] or "?") .. " " .. tostring(r[2] or "")
    end)
    add("Mode", function()
        local m = {state_name(G.STAGE, G.STAGES), state_name(G.STATE, G.STATES)}
        local mp = rawget(_G, "bom_match")
        if mp and mp.is_active and mp.is_active() then
            local st = mp.get_state()
            m[#m + 1] = "multiplayer " .. tostring(st.mode) .. " " .. tostring(st.phase)
        end
        local run = G.GAME and G.STAGE == G.STAGES.RUN
        if run and G.GAME.selected_back and G.GAME.selected_back.name then m[#m + 1] = "deck " .. tostring(G.GAME.selected_back.name) end
        if run and G.GAME.stake then m[#m + 1] = "stake " .. tostring(G.GAME.stake) end
        if run and G.GAME.round_resets and G.GAME.round_resets.ante then m[#m + 1] = "ante " .. tostring(G.GAME.round_resets.ante) end
        if run and G.GAME.challenge then m[#m + 1] = "challenge " .. tostring(G.GAME.challenge) end
        if run and G.GAME.seeded then m[#m + 1] = "seeded" end
        if G.OVERLAY_MENU then m[#m + 1] = "menu open" end
        local L = rawget(_G, "MODLOADER")
        m[#m + 1] = (L and L.modded) and "modded" or "normal"
        return table.concat(m, ", ")
    end)
    add("Screen", function()
        local w, h = love.graphics.getDimensions()
        local kind = _G._IS_DESKTOP == false and "phone" or "desktop"
        local P = rawget(_G, "PORTRAIT")
        if P and P.on and P.on() then kind = kind .. " portrait" end
        return string.format("%dx%d %s, UI size %d%%, picture %s", w, h, kind, math.floor((G.UI_SIZE or 1) * 100 + 0.5), tostring(G.SETTINGS and G.SETTINGS.GRAPHICS and G.SETTINGS.GRAPHICS.perf_resolution or 1))
    end)
    out[#out + 1] = ""
    out[#out + 1] = "Last actions:"
    for _, l in ipairs(CrashReports.actions) do out[#out + 1] = "  " .. l end
    if #CrashReports.actions == 0 then out[#out + 1] = "  (none)" end
    out[#out + 1] = ""
    out[#out + 1] = "Log tail:"
    for _, l in ipairs(CrashReports.log) do out[#out + 1] = "  " .. l end
    if #CrashReports.log == 0 then out[#out + 1] = "  (none)" end
    return table.concat(out, "\n")
end

function CrashReports.hook()
    if CrashReports.hooked then return end
    CrashReports.hooked = true
    local raw_print = print
    local function record(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        local line = table.concat(parts, " "):gsub("[\r\n]+", " "):gsub("^%s+", ""):sub(1, 200)
        if line == "" then return end
        local key = line:gsub("[%d%.%-]+", "#")
        local log = CrashReports.log
        if key == CrashReports.log_key and #log > 0 then
            CrashReports.log_rep = CrashReports.log_rep + 1
            log[#log] = line .. " (x" .. CrashReports.log_rep .. ")"
        else
            CrashReports.log_key, CrashReports.log_rep = key, 1
            push(log, MAX_LOG, line)
        end
    end
    rawset(_G, "print", function(...)
        pcall(record, ...)
        return raw_print(...)
    end)
    if UIElement and UIElement.click then
        local raw_click = UIElement.click
        UIElement.click = function(self, ...)
            if self.config and self.config.button and not self.disable_button then CrashReports.note("button " .. tostring(self.config.button)) end
            return raw_click(self, ...)
        end
    end
    if Game and Game.update then
        local raw_update = Game.update
        local last_stage, last_state, last_menu
        Game.update = function(self, dt)
            if self.STATE ~= last_state or self.STAGE ~= last_stage then
                last_state, last_stage = self.STATE, self.STAGE
                CrashReports.note("state " .. state_name(self.STAGE, self.STAGES) .. " " .. state_name(self.STATE, self.STATES))
            end
            local menu = self.OVERLAY_MENU and true or false
            if menu ~= last_menu then
                last_menu = menu
                CrashReports.note(menu and "menu opened" or "menu closed")
            end
            return raw_update(self, dt)
        end
    end
    local L = rawget(_G, "MODLOADER")
    if L and L.crash_report and not L.crash_report_ctx then
        L.crash_report_ctx = true
        local raw_report = L.crash_report
        L.crash_report = function(...)
            local text = raw_report(...)
            local ok, ctx = pcall(CrashReports.context)
            if ok and ctx then text = tostring(text) .. "\n\n" .. ctx end
            return text
        end
    end
    if L and L.save_pending_report and not L.save_pending_ctx then
        L.save_pending_ctx = true
        local raw_save = L.save_pending_report
        L.save_pending_report = function(...)
            local r = raw_save(...)
            pcall(CrashReports.send_now)
            return r
        end
    end
end

local function plain(s)
    return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

function CrashReports.scrub(text)
    local s = tostring(text or "")
    local names = {}
    local home = os.getenv("HOME") or os.getenv("USERPROFILE")
    if home and #home > 3 then names[#names + 1] = {home, "~"} end
    local ok, ud = pcall(function() return love.filesystem.getUserDirectory() end)
    if ok and type(ud) == "string" and #ud > 3 then names[#names + 1] = {(ud:gsub("[/\\]+$", "")), "~"} end
    for _, pr in pairs(G and G.PROFILES or {}) do
        local n = type(pr) == "table" and pr.name
        if type(n) == "string" and #n >= 3 then names[#names + 1] = {n, "<player>"} end
    end
    for _, p in ipairs(names) do s = s:gsub(plain(p[1]), (p[2]:gsub("%%", "%%%%"))) end
    s = s:gsub("/home/[^/%s:]+", "/home/~"):gsub("/Users/[^/%s:]+", "/Users/~"):gsub("([Uu]sers[/\\])[^/\\%s:]+", "%1~")
    return s
end

function CrashReports.body(report)
    local L = rawget(_G, "MODLOADER")
    local fields = {
        '"v":1',
        '"version":' .. json_string(rawget(_G, "OVERHAUL_NAME") or rawget(_G, "OVERHAUL_VERSION") or "?"),
        '"platform":' .. json_string(love.system and love.system.getOS() or "?"),
        '"modded":' .. ((L and L.modded) and "true" or "false"),
        '"build":' .. json_string(rawget(_G, "OVERHAUL_VERSION") or ""),
        '"player":' .. json_string(CrashReports.install_id()),
        '"report":' .. json_string(CrashReports.scrub(report)),
    }
    return "{" .. table.concat(fields, ",") .. "}"
end

function CrashReports.send_now()
    if CrashReports.crash_sent then return false end
    CrashReports.crash_sent = true
    CrashReports.migrate()
    if not CrashReports.enabled() then return false end
    return CrashReports.start_send()
end

function CrashReports.send_pending()
    if CrashReports.sent_this_launch then return false end
    CrashReports.sent_this_launch = true
    CrashReports.migrate()
    if not CrashReports.enabled() then return false end
    return CrashReports.start_send()
end

function CrashReports.start_send()
    local report = love.filesystem.read(PENDING)
    if not report or report == "" then return false end
    local tries = (tonumber(love.filesystem.read(ATTEMPTS) or "") or 0) + 1
    if tries > MAX_ATTEMPTS then
        love.filesystem.remove(PENDING)
        love.filesystem.remove(ATTEMPTS)
        return false
    end
    love.filesystem.write(ATTEMPTS, tostring(tries))
    CrashReports.channel = "crash_report_result"
    local ok = pcall(function()
        local t = love.thread.newThread(THREAD_CODE)
        t:start(CrashReports.url(), CrashReports.body(report), PENDING, ATTEMPTS, CrashReports.channel)
        CrashReports.thread = t
    end)
    return ok
end

function CrashReports.result()
    if not CrashReports.channel then return nil end
    local code = love.thread.getChannel(CrashReports.channel):pop()
    if code then CrashReports.last_code = code end
    return CrashReports.last_code
end

CrashReports.SCREEN_ON = "A crash report is being sent to the Overhaul team so this can be fixed.\nIt holds the error and game info, nothing that identifies you.\nYou can turn this off in Options > Account."
CrashReports.SCREEN_OFF = "Crash reports are off. To help fix crashes like this one,\nturn on 'Send crash reports' in Options > Account."

function CrashReports.screen_text(on)
    local en = on and CrashReports.SCREEN_ON or CrashReports.SCREEN_OFF
    local ok, txt = pcall(mod_loc, en)
    return ok and type(txt) == "string" and txt or en
end

if mod_loc_register then
    mod_loc_register{
        fr = {
            [CrashReports.SCREEN_ON] = "Un rapport de plantage est envoyé à l'équipe Overhaul pour corriger ce problème.\nIl contient l'erreur et des infos sur le jeu, rien qui permette de vous identifier.\nVous pouvez le désactiver dans Options > Compte.",
            [CrashReports.SCREEN_OFF] = "Les rapports de plantage sont désactivés. Pour aider à corriger ce genre de plantage,\nactivez « Envoyer les rapports de plantage » dans Options > Compte.",
            ["Sends the error and game info to the Overhaul team"] = "Envoie l'erreur et des infos du jeu à l'équipe Overhaul",
        },
        es = {
            [CrashReports.SCREEN_ON] = "Se está enviando un informe de error al equipo de Overhaul para poder arreglarlo.\nIncluye el error y datos del juego, nada que te identifique.\nPuedes desactivarlo en Opciones > Cuenta.",
            [CrashReports.SCREEN_OFF] = "Los informes de errores están desactivados. Para ayudar a arreglar cierres como este,\nactiva «Enviar informes de errores» en Opciones > Cuenta.",
            ["Sends the error and game info to the Overhaul team"] = "Envía el error y datos del juego al equipo de Overhaul",
        },
    }
end

CrashReports.hook()

return CrashReports
