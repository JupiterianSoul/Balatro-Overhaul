local U = OverhaulUpdate
if type(U) ~= "table" then return end

local LINK = "overhaul_launcher_link.lua"
local RECHECK_SECS = 1800
local RETRY_SECS = 120

local function read_link()
    local ok_src, src = pcall(love.filesystem.getSource)
    if not ok_src or type(src) ~= "string" or src == "" then return nil end
    local dir = src:gsub("[/\\]+$", ""):match("^(.*)[/\\][^/\\]+$")
    if not dir then return nil end
    local f = io.open(dir .. "/" .. LINK, "rb")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    local chunk = loadstring(body or "", "=" .. LINK)
    if not chunk then return nil end
    setfenv(chunk, {})
    local ok, link = pcall(chunk)
    if not ok or type(link) ~= "table" or link.format ~= 1 or type(link.feed) ~= "string" then return nil end
    if type(link.launcher) ~= "table" or type(link.launcher[1]) ~= "string" then return nil end
    return link
end

local link = read_link()
if not link then
    local check = U.check
    function U.check(...)
        if rawget(_G, "RELEASE_BUILD") and love.system.getOS() ~= "Android" then return end
        return check(...)
    end
    return
end
U.launcher_link = link

local function decode(body)
    local ok, chunk = pcall(love.filesystem.load, "smods/libs/json/json.lua")
    if not ok or not chunk then return nil end
    local ok2, lib = pcall(chunk)
    if not ok2 then return nil end
    local ok3, data = pcall(lib.decode, body or "")
    return ok3 and type(data) == "table" and data or nil
end

local function show(state, label)
    U.state = state
    U.ui.label = label
    if state == "available" then return U.refresh_menu() end
    if G and G.MAIN_MENU_UI and G.STAGE == G.STAGES.MAIN_MENU then pcall(function() G.MAIN_MENU_UI:recalculate() end) end
end

function U.check(force)
    if U.checking or U.state == "failed" then return end
    local now = love.timer.getTime()
    if not force and U.next_check and now < U.next_check then return end
    U.checking = true
    ModWorkshop.request("get", {lane = "update", url = link.feed}, function(res)
        U.checking = false
        local data = res.ok and decode(res.body)
        local latest = data and data.format == 1 and type(data.latest) == "table" and data.latest
        if not latest or type(latest.version) ~= "string" then
            U.next_check = love.timer.getTime() + RETRY_SECS
            return
        end
        U.next_check = love.timer.getTime() + RECHECK_SECS
        if U.newer(latest.version, OVERHAUL_VERSION) then
            U.build = {version = latest.version, name = type(latest.name) == "string" and latest.name or nil, size = tonumber(latest.size), sha256 = latest.sha256}
            if U.state == "none" then show("available", mod_loc("UPDATE AVAILABLE")) end
        end
    end)
end

local function quote(s)
    if love.system.getOS() == "Windows" then return '"' .. tostring(s):gsub('"', '') .. '"' end
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

function U.start()
    local parts = {}
    for _, a in ipairs(link.launcher) do parts[#parts + 1] = quote(a) end
    parts[#parts + 1] = "--update --play"
    local cmd = table.concat(parts, " ")
    if love.system.getOS() == "Windows" then
        cmd = 'start "" ' .. cmd
    else
        cmd = cmd .. " >/dev/null 2>&1 &"
    end
    local r = os.execute(cmd)
    if r == 0 or r == true then
        love.event.quit()
    else
        U.error = mod_loc("Could not start the launcher.")
        show("failed", mod_loc("UPDATE FAILED"))
    end
end

local prompt_definition = U.prompt_definition
function U.prompt_definition(opts)
    local def = prompt_definition(opts)
    local browser = mod_loc("The download opens in your browser.")
    local function swap(node)
        if type(node) ~= "table" then return end
        if node.config and node.config.text == browser then
            node.config.text = mod_loc("The game closes, the launcher installs the update and starts it again.")
            node.config.colour = G.C.UI.TEXT_LIGHT
        end
        for _, child in ipairs(node.nodes or {}) do swap(child) end
    end
    swap(def)
    return def
end

mod_loc_register{
    fr = {
        ["The game closes, the launcher installs the update and starts it again."] = "Le jeu se ferme, le lanceur installe la mise à jour et le relance.",
        ["Could not start the launcher."] = "Impossible de lancer le lanceur.",
    },
    es = {
        ["The game closes, the launcher installs the update and starts it again."] = "El juego se cierra, el lanzador instala la actualización y lo vuelve a abrir.",
        ["Could not start the launcher."] = "No se pudo abrir el lanzador.",
    },
}

return U
