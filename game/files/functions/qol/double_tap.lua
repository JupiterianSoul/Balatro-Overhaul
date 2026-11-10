local Q = QOL
local M = Q.feature("double_tap", {})

M.WINDOW = 0.35

Q.default("qol_double_tap", true)

function M.allowed()
    if not (UIK and UIK.touch and UIK.touch()) then return false end
    if not (Q.on("qol_double_tap") and Q.in_run()) then return false end
    if bom_playback and bom_playback.active and bom_playback.active() then return false end
    return G.STATE == G.STATES.SELECTING_HAND and not G.OVERLAY_MENU
end

function M.find(node, depth)
    depth = depth or 0
    if not node or depth > 40 then return nil end
    if node.config and node.config.button == "play_cards_from_highlighted" then return node end
    for _, v in pairs(node.children or {}) do
        local r = M.find(v, depth + 1)
        if r then return r end
    end
    return nil
end

function M.play_button()
    if not (G.buttons and G.buttons.UIRoot) then return nil end
    return M.find(G.buttons.UIRoot)
end

function M.tap(card, now)
    if card.area ~= G.hand then M.last = nil return false end
    local prev = M.last
    if prev and prev.card == card and now - prev.t <= M.WINDOW then
        M.last = nil
        if G.CONTROLLER and G.CONTROLLER.locked then return false end
        if #G.hand.highlighted == 0 then return false end
        local btn = M.play_button()
        if not btn then return false end
        btn:click()
        return true
    end
    M.last = {card = card, t = now}
    return false
end

Q.row("Hand", function()
    if not UIK.touch() then return nil end
    return Q.toggle('set_qol_double_tap', "Double tap to play", "Tap a card twice to play your selection", 'qol_double_tap')
end)

local function strings()
    if not mod_loc_register then return end
    mod_loc_register{
        fr = {["Double tap to play"] = "Double appui pour jouer", ["Tap a card twice to play your selection"] = "Touchez une carte deux fois pour jouer la sélection"},
        es = {["Double tap to play"] = "Doble toque para jugar", ["Tap a card twice to play your selection"] = "Toca una carta dos veces para jugar tu selección"},
    }
end

function M.init()
    strings()
    if M._wrapped or not (Card and Card.click) then return end
    M._wrapped = true
    local click = Card.click
    Card.click = function(self, ...)
        local ok, used = false, false
        if M.allowed() then
            ok, used = pcall(M.tap, self, G.TIMERS and G.TIMERS.REAL or 0)
            if not ok then print("[QoL] double tap: " .. tostring(used)) end
        end
        if ok and used then return end
        return click(self, ...)
    end
end

strings()

return M
