local Q = QOL
local M = Q.feature("sell_total", {})

M.state = {label = "", amount = ""}

Q.default("qol_sell_total", true)

function M.total(cards)
    local sum, n = 0, 0
    for _, c in ipairs(cards or {}) do
        if not (c.ability and c.ability.eternal) then
            sum = sum + math.max(0, tonumber(c.sell_cost) or 0)
            n = n + 1
        end
    end
    return sum, n
end

function M.hovered(area)
    local ctrl = G.CONTROLLER
    if not ctrl then return false end
    local t = ctrl.hovering and ctrl.hovering.target
    if t and t.area == area then return true end
    if area.highlighted and area.highlighted[1] then return true end
    local p = ctrl.cursor_hover and ctrl.cursor_hover.T
    if p and p.x and area.collides_with_point then
        local ok, hit = pcall(area.collides_with_point, area, p)
        if ok and hit then return true end
    end
    return false
end

function M.show(area)
    if area ~= G.jokers or not area.cards or #area.cards == 0 then return false end
    if not (Q.on("qol_sell_total") and Q.in_run()) then return false end
    if G.OVERLAY_MENU or G.VIEWING_DECK then return false end
    if not M.hovered(area) then return false end
    local sum, n = M.total(area.cards)
    if n == 0 then return false end
    M.state.label = mod_loc("Sell value") .. " "
    M.state.amount = "$" .. tostring(sum)
    return true
end

M.LIFT = 0.24

function M.box(area)
    return UIBox{
        definition = {n = G.UIT.ROOT, config = {align = 'cm', colour = G.C.CLEAR}, nodes = {
            {n = G.UIT.R, config = {align = 'cr', padding = 0.03, no_fill = true}, nodes = {
                {n = G.UIT.T, config = {ref_table = M.state, ref_value = 'label', scale = 0.3, colour = G.C.WHITE, shadow = true}},
                {n = G.UIT.T, config = {ref_table = M.state, ref_value = 'amount', scale = 0.3, lang = G.LANGUAGES['en-us'], colour = G.C.MONEY, shadow = true}},
            }},
        }},
        config = {align = 'tr', offset = {x = 0, y = -M.LIFT}, major = area, parent = area},
    }
end

function M.touch_box(button)
    return UIBox{
        definition = {n = G.UIT.ROOT, config = {align = 'cm', colour = G.C.CLEAR}, nodes = {
            {n = G.UIT.R, config = {align = 'cm', padding = 0.04, r = 0.08, colour = {0, 0, 0, 0.45}}, nodes = {
                {n = G.UIT.T, config = {text = mod_loc("Total") .. " ", scale = 0.32, colour = G.C.WHITE, shadow = true}},
                {n = G.UIT.T, config = {ref_table = M.state, ref_value = 'amount', scale = 0.32, lang = G.LANGUAGES['en-us'], colour = G.C.MONEY, shadow = true}},
            }},
        }},
        config = {align = 'bm', offset = {x = 0, y = 0.08}, major = button, parent = button},
    }
end

function M.draw_touch(area)
    local card = area.highlighted and area.highlighted[1]
    local button = card and card.children and card.children.use_button
    if M.tbox and (M.tbox_major ~= button or not button) then
        M.tbox:remove()
        M.tbox, M.tbox_major = nil, nil
    end
    if not button then return end
    if not M.tbox then
        M.tbox = M.touch_box(button)
        M.tbox.states.collide.can = false
        M.tbox_major = button
    end
    if M.tbox.alignment and M.tbox.alignment.offset and button.T and card.T then
        local left = card.T.x + card.T.w + 0.05
        M.tbox.alignment.offset.x = left + M.tbox.T.w / 2 - (button.T.x + button.T.w / 2)
    end
    M.tbox:draw()
end

function M.draw(area)
    if not M.show(area) then
        if M.tbox then M.tbox:remove() M.tbox, M.tbox_major = nil, nil end
        return
    end
    if UIK.touch() then return M.draw_touch(area) end
    if not area.children.qol_sell then
        area.children.qol_sell = M.box(area)
        area.children.qol_sell.states.collide.can = false
    end
    area.children.qol_sell:draw()
end

Q.row("Shop", function()
    return Q.toggle('set_qol_sell_total', "Sell value total", "Shown when you hover or select a Joker", 'qol_sell_total')
end)

local function strings()
    if not mod_loc_register then return end
    mod_loc_register{
        fr = {["Total"] = "Total", ["Sell value"] = "Valeur de vente", ["Sell value total"] = "Total de vente", ["Shown when you hover or select a Joker"] = "Affiché au survol ou au choix d'un Joker"},
        es = {["Total"] = "Total", ["Sell value"] = "Valor de venta", ["Sell value total"] = "Total de venta", ["Shown when you hover or select a Joker"] = "Se ve al pasar sobre un comodín o elegirlo"},
    }
end

function M.init()
    strings()
    if M._wrapped or not CardArea then return end
    M._wrapped = true
    local draw = CardArea.draw
    CardArea.draw = function(self, ...)
        if self == G.jokers and self.states and self.states.visible then
            local ok, err = pcall(M.draw, self)
            if not ok and not M._warned then M._warned = true print("[QoL] sell total: " .. tostring(err)) end
        end
        return draw(self, ...)
    end
end

strings()

return M
