local F = {}

F.PREFIX = "forge:"
F.WAIT = 30
F.room = nil
F.waits = {}

local function Mods() return package.loaded["functions/forge/forge_mods"] end
local function L(s) return mod_loc and mod_loc(s) or s end
local function now() return love and love.timer and love.timer.getTime() or os.clock() end

function F.is_forge(m)
    return type(m) == "table" and type(m.id) == "string" and m.id:sub(1, #F.PREFIX) == F.PREFIX
end

function F.mod_id(m)
    return F.is_forge(m) and m.id:sub(#F.PREFIX + 1) or nil
end

function F.entries()
    local M = Mods()
    local out = {}
    for _, m in ipairs(M and M.list or {}) do
        if m.on and m.hash then
            local name = (m.name ~= "" and m.name or m.id):sub(1, 64)
            out[#out + 1] = { id = F.PREFIX .. m.id, name = name, version = m.hash, author = (m.author or ""):sub(1, 24), size = m.size or 0 }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function F.list(info)
    local out = {}
    for _, m in ipairs(info and info.hostMods or {}) do
        local id = F.mod_id(m)
        if id and type(m.version) == "string" then
            out[#out + 1] = { id = id, name = tostring(m.name or id), hash = m.version, author = tostring(m.author or ""), size = tonumber(m.size) or 0 }
        end
    end
    return out
end

function F.local_hash(id)
    local M = Mods()
    local mod = M and M.get(id)
    return mod and mod.hash or nil
end

function F.state(e)
    local M = Mods()
    if M and (e.size or 0) > M.SHARE_MAX then return "too_big" end
    local h = F.local_hash(e.id)
    if h == e.hash then return "installed" end
    if h then return "update" end
    return "missing"
end

function F.missing(list)
    local out = {}
    for _, e in ipairs(list or {}) do
        if F.state(e) ~= "installed" then out[#out + 1] = e end
    end
    return out
end

function F.blocked(list)
    for _, e in ipairs(list or {}) do
        if F.state(e) == "too_big" then return true end
    end
    return false
end

function F.enable_exact(list)
    local M = Mods()
    if not (M and M.set_exact) then return end
    local want = {}
    for _, e in ipairs(list or {}) do want[e.id] = true end
    M.set_exact(want)
end

F.REASONS = {
    room_gone = "The room is gone",
    host_gone = "The host left",
    timeout = "The host did not answer",
    hash_mismatch = "The host's copy changed",
    too_big = "Too big to share",
    bad_mod = "Not a valid Forge mod",
    busy = "Too many downloads at once",
    not_in_room = "Not in this room",
    host_refused = "The host could not send it",
}

function F.reason_text(why)
    return L(F.REASONS[why] or F.REASONS.host_refused)
end

function F.accept_raw(e, raw)
    local M = Mods()
    if not M then return false, F.reason_text("bad_mod") end
    if type(raw) ~= "string" or #raw > M.SHARE_MAX then return false, F.reason_text("too_big") end
    if M.hash(raw) ~= e.hash then return false, F.reason_text("hash_mismatch") end
    local mod = M.parse(raw)
    if not mod or mod.id ~= e.id then return false, F.reason_text("bad_mod") end
    local inst = M.install(raw)
    if not inst then return false, F.reason_text("bad_mod") end
    if mp_log then mp_log.info("BOM_FORGE", "installed room Forge mod %s %s", tostring(e.id), tostring(e.hash)) end
    return true
end

local function finish(id, ok, err)
    local w = F.waits[id]
    if not w then return end
    F.waits[id] = nil
    pcall(w.cb, ok, err)
end

local function arm(id)
    if not (G and G.E_MANAGER and Event) then return end
    local w = F.waits[id]
    local at = w and w.at
    G.E_MANAGER:add_event(Event({ trigger = "after", delay = F.WAIT, timer = "REAL", blocking = false, blockable = false, no_delete = true,
        func = function()
            local cur = F.waits[id]
            if cur and cur.at == at then finish(id, false, F.reason_text(cur.reason or "timeout")) end
            return true
        end }))
end

local function ask_online(w)
    w.online = true
    w.at = now()
    arm(w.e.id)
    if not bom_core.send({ type = "forge_get", id = w.e.id }) then finish(w.e.id, false, F.reason_text(w.reason)) end
end

function F.get_one(info, e, cb)
    F.register()
    F.waits[e.id] = { e = e, cb = cb, at = now(), online = false }
    arm(e.id)
    local sent = bom_core.send({ type = "forge_room_get", room = info.id, code = info.code, id = e.id, hash = e.hash })
    if not sent then finish(e.id, false, F.reason_text("room_gone")) end
end

function F.fetch(info, list, done)
    local i = 0
    local function nxt()
        i = i + 1
        local e = list[i]
        if not e then return done(true) end
        F.get_one(info, e, function(ok, err)
            if ok then return nxt() end
            done(false, err)
        end)
    end
    nxt()
end


function F.on_mod(d)
    if type(d) ~= "table" or type(d.id) ~= "string" then return true end
    local w = F.waits[d.id]
    if not w or w.online then return true end
    if d.ok and type(d.mod) == "string" then
        local ok, err = F.accept_raw(w.e, d.mod)
        finish(d.id, ok, err)
        return true
    end
    w.reason = d.reason
    ask_online(w)
    return true
end

function F.claim_online(d)
    if type(d) ~= "table" or type(d.id) ~= "string" then return false end
    local w = F.waits[d.id]
    if not (w and w.online) then return false end
    if d.ok and type(d.mod) == "string" then
        local ok, err = F.accept_raw(w.e, d.mod)
        finish(d.id, ok, err)
    else
        finish(d.id, false, F.reason_text(w.reason))
    end
    return true
end

function F.on_req(d)
    if type(d) ~= "table" or type(d.rid) ~= "string" then return true end
    local M = Mods()
    local reply = { type = "forge_room_put", rid = d.rid }
    if M and type(d.id) == "string" and F.room and F.room[d.id] == d.hash then
        local raw = M.raw_of(d.id)
        if raw and #raw <= M.SHARE_MAX and M.hash(raw) == d.hash then reply.mod = raw end
    end
    bom_core.send(reply)
    if mp_log then mp_log.info("BOM_FORGE", "room Forge mod %s asked, %s", tostring(d.id), reply.mod and "sent" or "refused") end
    return true
end

function F.on_room(d)
    if type(d) ~= "table" then return end
    local set, n = {}, 0
    for _, m in ipairs(type(d.forge) == "table" and d.forge or {}) do
        local id = F.mod_id(m)
        if id and type(m.version) == "string" then
            set[id] = m.version
            n = n + 1
        end
    end
    F.room = n > 0 and set or nil
    F.install_hooks()
    F.refresh()
    if mp_log then mp_log.info("BOM_FORGE", "room Forge mods: %d", n) end
end

function F.active()
    if not F.room then return false end
    local BM = rawget(_G, "bom_match")
    local ok, ph = pcall(function() return BM and BM.get_phase and BM.get_phase() end)
    if not ok or ph == nil or ph == "none" then return false end
    local R = rawget(_G, "ForgeRoom")
    local okr, ranked = pcall(function() return R and R.ranked and R.ranked() end)
    if okr and ranked then return false end
    return true
end

function F.live(which)
    local M = Mods()
    local Store = package.loaded["functions/forge/forge_store"]
    local out = {}
    if Store and Store.room then
        for _, c in ipairs(Store.room[which] or {}) do out[#out + 1] = c end
    end
    for _, c in ipairs(M and M[which] or {}) do
        if c.mod_id and F.room and F.room[c.mod_id] then out[#out + 1] = c end
    end
    return out
end

function F.install_hooks()
    if F.hooked then return true end
    local Store = package.loaded["functions/forge/forge_store"]
    local R = rawget(_G, "ForgeRoom")
    local M = Mods()
    if not (Store and R and M and Store.live_jokers and Store.live_items and R.active and R.pack) then return false end
    F.hooked = true
    local active0, jokers0, items0, pack0 = R.active, Store.live_jokers, Store.live_items, R.pack
    R.active = function(...) return active0(...) or F.active() end
    Store.live_jokers = function(...)
        if not F.active() then return jokers0(...) end
        return F.live("jokers")
    end
    Store.live_items = function(...)
        if not F.active() then return items0(...) end
        local out = F.live("items")
        for _, c in ipairs(Store.items()) do
            if c.kind == "collab" then out[#out + 1] = c end
        end
        return out
    end
    R.pack = function(...)
        if not F.room then return pack0(...) end
        local j, i = M.jokers, M.items
        M.jokers, M.items = {}, {}
        local ok, a, b = pcall(pack0, ...)
        M.jokers, M.items = j, i
        if not ok then error(a) end
        return a, b
    end
    return true
end

function F.refresh()
    local M = Mods()
    if M and M.refresh_game then pcall(M.refresh_game) end
end

F.BOT_REASONS = {
    mods = "Bots can't play with mods. Use a room without mods to add a bot.",
    forge = "Bots can't play with Forge creations. Turn them off to add a bot.",
}

function F.on_bot_error(d)
    if type(d) ~= "table" or not F.BOT_REASONS[d.reason] then return end
    pcall(function() bom_ui.show_error(L(F.BOT_REASONS[d.reason])) end)
end

local function xdg_rel(save)
    local base = os.getenv("XDG_DATA_HOME")
    if not base or base == "" then
        local home = os.getenv("HOME")
        if not home then return nil end
        base = home .. "/.local/share"
    end
    base = base:gsub("/+$", "")
    if save:sub(1, #base + 1) ~= base .. "/" then return nil end
    return save:sub(#base + 2)
end

local function sh(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

function F.prepare_versus(data_dir)
    local fs = love.filesystem
    local save = fs.getSaveDirectory()
    local rel = xdg_rel(save)
    if not rel then return false end
    local root = data_dir .. "/" .. rel
    local M = Mods()
    local forge_dir = root .. "/forge/mods"
    if fs.getInfo(forge_dir) then
        for _, name in ipairs(fs.getDirectoryItems(forge_dir)) do pcall(fs.remove, forge_dir .. "/" .. name) end
    end
    local index, n = {}, 0
    for _, m in ipairs(M and M.list or {}) do
        if m.on then
            local raw = M.raw_of(m.id)
            if raw then
                if M.ensure then M.ensure(forge_dir) else fs.createDirectory(forge_dir) end
                fs.write(forge_dir .. "/" .. m.id .. M.EXT, raw)
                index[m.id] = { on = true, mine = false, added = os.time() }
                n = n + 1
            end
        end
    end
    if n > 0 then
        local json = require("bot.sim.json")
        fs.write(forge_dir .. "/index.json", json.encode({ v = 1, mods = index }))
    end
    local BL = rawget(_G, "MODLOADER")
    local mods_dir = root .. "/mods"
    fs.createDirectory(mods_dir)
    local folders = {}
    local ok, st = pcall(function() return BL and BL.active and BL.status and BL.status() end)
    for _, e in ipairs(ok and type(st) == "table" and st.mods or {}) do
        if e.loaded and e.folder then folders[#folders + 1] = e.folder end
    end
    if #folders > 0 then
        for _, folder in ipairs(folders) do
            local src = save .. "/" .. (BL.root or "mods") .. "/" .. folder
            local dst = save .. "/" .. mods_dir .. "/" .. folder
            os.execute("rm -rf " .. sh(dst) .. " && cp -R " .. sh(src) .. " " .. sh(dst))
        end
        local ws_src, ws_dst = (BL.root or "mods") .. "/.workshop", mods_dir .. "/.workshop"
        fs.createDirectory(ws_dst)
        for _, f in ipairs({ "installed.lua", "index.lua" }) do
            local raw = fs.read(ws_src .. "/" .. f)
            if raw then fs.write(ws_dst .. "/" .. f, raw) end
        end
        fs.write(mods_dir .. "/enabled.txt", table.concat(folders, "\n") .. "\n")
        fs.write(mods_dir .. "/session.txt", "modded\n")
    else
        pcall(fs.remove, mods_dir .. "/session.txt")
    end
    if mp_log then mp_log.info("BOM_FORGE", "versus copy gets %d Forge mods and %d mods", n, #folders) end
    return true, n, #folders
end

local function strings()
    if F._strings or not mod_loc_register then return end
    F._strings = true
    mod_loc_register{
        fr = {
            ["The room is gone"] = "La salle n'existe plus",
            ["The host left"] = "L'hôte est parti",
            ["The host did not answer"] = "L'hôte n'a pas répondu",
            ["The host's copy changed"] = "La copie de l'hôte a changé",
            ["Too big to share"] = "Trop gros pour être partagé",
            ["Not a valid Forge mod"] = "Mod de la Forge non valide",
            ["Too many downloads at once"] = "Trop de téléchargements à la fois",
            ["Not in this room"] = "Absent de cette salle",
            ["The host could not send it"] = "L'hôte n'a pas pu l'envoyer",
            ["Bots can't play with mods. Use a room without mods to add a bot."] = "Les bots ne jouent pas avec des mods. Utilisez une salle sans mods pour ajouter un bot.",
            ["Bots can't play with Forge creations. Turn them off to add a bot."] = "Les bots ne jouent pas avec les créations de la Forge. Désactivez-les pour ajouter un bot.",
        },
        es = {
            ["The room is gone"] = "La sala ya no existe",
            ["The host left"] = "El anfitrión se fue",
            ["The host did not answer"] = "El anfitrión no respondió",
            ["The host's copy changed"] = "La copia del anfitrión cambió",
            ["Too big to share"] = "Demasiado grande para compartir",
            ["Not a valid Forge mod"] = "Mod de la Forja no válido",
            ["Too many downloads at once"] = "Demasiadas descargas a la vez",
            ["Not in this room"] = "No está en esta sala",
            ["The host could not send it"] = "El anfitrión no pudo enviarlo",
            ["Bots can't play with mods. Use a room without mods to add a bot."] = "Los bots no juegan con mods. Usa una sala sin mods para añadir un bot.",
            ["Bots can't play with Forge creations. Turn them off to add a bot."] = "Los bots no juegan con creaciones de la Forja. Desactívalas para añadir un bot.",
        },
    }
end

function F.register()
    strings()
    if F._registered then return end
    local E = rawget(_G, "bom_events")
    if not (E and E.register) then return end
    F._registered = true
    E.register("room_created", F.on_room)
    E.register("room_ready", F.on_room)
    E.register("party_joined", F.on_room)
    E.register("rejoin_ok", F.on_room)
    E.register("forge_room_req", F.on_req)
    E.register("forge_room_mod", F.on_mod)
    E.register("bot_error", F.on_bot_error)
    local O = rawget(_G, "ForgeOnline")
    if O then O.claim = F.claim_online end
end

pcall(F.register)
pcall(F.install_hooks)
_G.bom_forge = F

return F
