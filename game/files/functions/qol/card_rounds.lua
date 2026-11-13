local Q = QOL
local M = Q.feature("card_rounds", {})

M.CHILD = "qol_rounds"
M.Y = 0.32
M.TOUCH_Y = 0.46

Q.default("qol_card_rounds", true)

function M.label(ability, game)
    if type(ability) ~= "table" then return nil end
    if ability.perishable then
        local left = tonumber(ability.perish_tally)
        if left and left > 0 then
            local total = tonumber(game and game.perishable_rounds) or left
            return tostring(left) .. "/" .. tostring(math.max(total, left)), "PERISHABLE"
        end
    end
    if ability.rental then
        return "-$" .. tostring(tonumber(game and game.rental_rate) or 3), "RENTAL"
    end
    return nil
end

function M.wanted(card)
    if not (card.area and (card.area == G.jokers or card.area == G.shop_jokers or card.area == G.pack_cards)) then return nil end
    if not (Q.on("qol_card_rounds") and Q.in_run()) then return nil end
    if card.facing == "back" or card.states.drag.is then return nil end
    return M.label(card.ability, G.GAME)
end

function M.box(card, state, colour)
    return UIBox{
        definition = {n = G.UIT.ROOT, config = {align = 'cm', colour = G.C.CLEAR}, nodes = {
            {n = G.UIT.C, config = {align = 'cm', r = 0.06, padding = 0.04, minw = 0.42, colour = colour, emboss = 0.03}, nodes = {
                {n = G.UIT.T, config = {ref_table = state, ref_value = 'text', scale = 0.3, lang = G.LANGUAGES['en-us'], colour = G.C.WHITE, shadow = true}},
            }},
        }},
        config = {align = 'tm', offset = {x = 0, y = UIK.touch() and M.TOUCH_Y or M.Y}, major = card, parent = card, bond = 'Strong'},
    }
end

function M.sync(card)
    local text, kind = M.wanted(card)
    local box = card.children[M.CHILD]
    if box and (not text or box.qol_kind ~= kind) then
        box:remove()
        card.children[M.CHILD] = nil
        box = nil
    end
    if not text then return end
    if not box then
        local state = {text = text}
        box = M.box(card, state, G.C[kind] or G.C.BLACK)
        box.states.collide.can = false
        box.qol_kind = kind
        box.qol_state = state
        card.children[M.CHILD] = box
    end
    box.qol_state.text = text
end

Q.row("Run", function()
    return Q.toggle('set_qol_card_rounds', "Sticker counters", "Rounds left and rent shown on the card", 'qol_card_rounds')
end)

local function strings()
    if not mod_loc_register then return end
    mod_loc_register{
        fr = {["Sticker counters"] = "Compteurs d'autocollants", ["Rounds left and rent shown on the card"] = "Manches restantes et loyer sur la carte"},
        es = {["Sticker counters"] = "Contadores de pegatinas", ["Rounds left and rent shown on the card"] = "Rondas restantes y alquiler en la carta"},
    }
end

function M.init()
    strings()
    if M._wrapped or not Card then return end
    M._wrapped = true
    local draw = Card.draw
    Card.draw = function(self, layer, ...)
        if self.children and self.ability and (self.ability.perishable or self.ability.rental or self.children[M.CHILD]) then
            local ok, err = pcall(M.sync, self)
            if not ok and not M._warned then M._warned = true print("[QoL] card rounds: " .. tostring(err)) end
        end
        return draw(self, layer, ...)
    end
end

strings()

return M
