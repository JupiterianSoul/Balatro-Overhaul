local X = Extras
local KEY = "replay_bar"
local M = X.feature(KEY, {})
local L = function(s) return mod_loc(s) end

local function PB() return rawget(_G, "bom_playback") end

local function state()
    local pb = PB()
    local S = pb and pb.active() and pb.state()
    if not S or S.done or S.script or not S.entries then return nil end
    return S
end

function M.next_pvp_index(S)
    S = S or state()
    if not S then return nil end
    for j = (S.i or 1) + 1, #S.entries do
        local e = S.entries[j]
        if type(e) == "table" and e.k == "in" and type(e.m) == "table" and e.m.type == "start_blind" and not e.m.solo then return j end
    end
end

G.FUNCS.pb_next_pvp = function()
    local S = state()
    local idx = S and M.next_pvp_index(S)
    if not idx then
        pcall(play_sound, "cancel")
        return
    end
    S.ff_to, S.step_to, S.back_to = idx, nil, nil
    PB().build_bar()
end

G.FUNCS.pb_step_hand = function()
    local pb = PB()
    if not (state() and pb.step_action) then return end
    pb.step_action(1, "pl")
end

function M.extras(S)
    if not (X.on(KEY) and state()) then return {} end
    local out = {}
    if not (type(S.header) == "table" and S.header.kind == "local") then
        out[#out + 1] = {L("Next PvP"), "pb_next_pvp", G.C.PURPLE, M.next_pvp_index(S) == nil}
    end
    out[#out + 1] = {L("Next hand"), "pb_step_hand", S.step_to and S.step_kind == "pl" and G.C.GOLD or G.C.BLUE}
    return out
end

function M.init()
    local pb = PB()
    if M._wrapped or not pb or type(pb.step) ~= "function" then return end
    M._wrapped = true
    pb.bar_extras = function(S)
        local ok, list = pcall(M.extras, S)
        return ok and list or {}
    end
end

mod_loc_register{
    fr = {["Next PvP"] = "JcJ suivant", ["Next hand"] = "Main suivante"},
    es = {["Next PvP"] = "JcJ siguiente", ["Next hand"] = "Mano siguiente"},
}

return M
