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

local function find_row(node, func, depth)
    if type(node) ~= "table" or (depth or 0) > 8 then return false end
    if node.config and node.config.button == func then return true end
    for _, c in ipairs(node.nodes or {}) do
        if find_row(c, func, (depth or 0) + 1) then return true end
    end
    return false
end

function M.bar_row(def)
    local S = state()
    local rows = def and def.nodes and def.nodes[1] and def.nodes[1].nodes and def.nodes[1].nodes[1] and def.nodes[1].nodes[1].nodes
    if not (S and rows) then return end
    local at
    for i, r in ipairs(rows) do
        if find_row(r, "pb_pause") then at = i break end
    end
    if not at then return end
    local z = PB().sizes()
    local w, h, scale, pad = z.w, z.h, z.scale, 0.04
    local mp = not (type(S.header) == "table" and S.header.kind == "local")
    local each = mp and (w - 4 * pad) / 2 or (w - 2 * pad)
    local has_pvp = M.next_pvp_index(S) ~= nil
    local function b(label, func, colour, disabled)
        return {n = G.UIT.C, config = {align = "cm", padding = pad}, nodes = {
            UIK.button{label = label, button = func, colour = colour, w = each, h = h, scale = scale, disabled = disabled, id = func},
        }}
    end
    local nodes = {}
    if mp then nodes[#nodes + 1] = b(L("Next PvP"), "pb_next_pvp", G.C.PURPLE, not has_pvp) end
    nodes[#nodes + 1] = b(L("Next hand"), "pb_step_hand", S.step_to and S.step_kind == "pl" and G.C.GOLD or G.C.BLUE)
    table.insert(rows, at + 1, {n = G.UIT.R, config = {align = "cm"}, nodes = nodes})
end

function M.init()
    local pb = PB()
    if M._wrapped or not pb or type(pb.bar_definition) ~= "function" or type(pb.step) ~= "function" then return end
    M._wrapped = true
    local bar = pb.bar_definition
    pb.bar_definition = function(...)
        local def = bar(...)
        if X.on(KEY) then pcall(M.bar_row, def) end
        return def
    end
end

mod_loc_register{
    fr = {["Next PvP"] = "JcJ suivant", ["Next hand"] = "Main suivante"},
    es = {["Next PvP"] = "JcJ siguiente", ["Next hand"] = "Mano siguiente"},
}

return M
