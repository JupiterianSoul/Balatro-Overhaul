local CE = rawget(_G, "social_chat_emotes") or {}
social_chat_emotes = CE

local function L(s) return mod_loc and mod_loc(s) or s end
local function touch() return UIK and UIK.touch and UIK.touch() end
local function EM() return rawget(_G, "bom_emotes") end
local function state() return require("multiplayer.mps_state") end

function CE.token(id) return ":" .. tostring(id) .. ":" end

function CE.parse(text)
    if type(text) ~= "string" then return nil end
    local id = text:match("^:([%a_]+):$")
    local e = EM()
    if id and e and e.BY_ID and e.BY_ID[id] then return id end
    return nil
end

function CE.size() return touch() and 0.82 or 0.7 end

function CE.chip(id, scale)
    local e = EM()
    local def = e and e.BY_ID and e.BY_ID[id]
    if not def then return nil end
    local sz = CE.size()
    local obj
    if e.fx_class then
        local ok, fx = pcall(function() return e.fx_class()({id = id, mode = "preview", size = sz, offset = (def.index or 1) * 0.37}) end)
        if ok then obj = fx end
    end
    local nodes = {}
    if obj then
        nodes[#nodes + 1] = {n = G.UIT.C, config = {align = "cm", minw = sz, minh = sz, padding = 0}, nodes = {
            {n = G.UIT.O, config = {object = obj, can_collide = false}},
        }}
        nodes[#nodes + 1] = {n = G.UIT.C, config = {minw = 0.1, padding = 0}, nodes = {}}
    end
    nodes[#nodes + 1] = {n = G.UIT.C, config = {align = "cm", minh = sz, padding = 0}, nodes = {
        bom_kit.text(L(def.label), {scale = scale, colour = G.C.WHITE}),
    }}
    return {n = G.UIT.R, config = {align = "cl", minh = sz, padding = 0}, nodes = nodes}
end

local function later(fn)
    if G.E_MANAGER and Event then
        G.E_MANAGER:add_event(Event({trigger = "after", delay = 0.05, timer = "REAL", blocking = false, blockable = false, pause_force = true,
            func = function() fn() return true end}))
    else
        fn()
    end
end

local function back()
    local ctx = CE.ctx
    CE.ctx = nil
    if ctx == "dm" then return require("multiplayer.mps_friends").open("messages") end
    local C = require("multiplayer.mps_chat")
    return C.open_panel()
end

local function pick_lobby(id)
    local e = EM()
    if not (e and e.send and e.send(id)) then return false end
    local T = state()
    T.send({type = "chat_lobby_send", text = CE.token(id)})
    back()
    return true
end

local function pick_dm(id)
    local e = EM()
    local T = state()
    local code = T.S.dm_sel
    if not (e and code) then return false end
    if e.can_send and not e.can_send() then
        if play_sound then pcall(play_sound, "cancel", 1, 0.5) end
        return false
    end
    e._next_send = e.clock() + (e.SEND_GAP or 2)
    T.send({type = "chat_dm_send", to = code, text = CE.token(id)})
    back()
    later(function() e.play(id, {mine = true}) end)
    return true
end

function CE.open(ctx)
    local e = EM()
    if not (e and e.open_picker) then return end
    if G.CONTROLLER then G.CONTROLLER.text_input_hook = nil end
    CE.ctx = ctx
    e.open_picker({back = "social_chat_emote_back", pick = ctx == "dm" and pick_dm or pick_lobby})
end

function CE.on_dm(code, d)
    local T = state()
    local S = T.S
    if type(d) ~= "table" or d.from == T.my_code() then return end
    local id = CE.parse(d.text)
    if not id or S.dm_sel ~= code or not S.dm_open then return end
    local F = require("multiplayer.mps_friends")
    if not (F.is_open and F.is_open()) then return end
    local f = T.friend(code)
    local e = EM()
    if e and e.play then e.play(id, {name = f and f.name or nil}) end
end

function CE.init()
    G.FUNCS.social_chat_emote_lobby = function() CE.open("lobby") end
    G.FUNCS.social_chat_emote_dm = function() CE.open("dm") end
    G.FUNCS.social_chat_emote_back = function() back() end
end

return CE
