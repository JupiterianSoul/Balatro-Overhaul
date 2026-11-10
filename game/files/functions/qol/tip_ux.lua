local Q = QOL
local M = Q.feature("tip_ux", {})

-- Hover suppress after an intentional dismiss (must outlive the release frame).
M._block_until = 0
M._block_card = nil

-- Sticky owner survives the brief clear_touch gap on a second press.
M._tip_shown_at = 0
M._tip_owner = nil

-- Tip must stay up at least this long before a tap can dismiss it.
M.DISMISS_GRACE = 0.2
M.BLOCK_AFTER_DISMISS = 0.35

local function now()
    return (G and G.TIMERS and G.TIMERS.REAL) or 0
end

local function blocked(card)
    return card and M._block_card == card and now() < M._block_until
end

-- Tip UIBoxes are drawn above cards; if they collide they steal hover when the
-- finger rests on the middle of the card (where the tip often overlays).
local function disable_tip_collision(node, depth)
    depth = depth or 0
    if not node or depth > 80 then return end
    if node.states then
        if node.states.collide then node.states.collide.can = false end
        if node.states.hover then node.states.hover.can = false end
        if node.states.click then node.states.click.can = false end
    end
    if node.UIRoot then
        disable_tip_collision(node.UIRoot, depth + 1)
    end
    if node.children then
        for _, child in pairs(node.children) do
            disable_tip_collision(child, depth + 1)
        end
    end
end

local function sanitize_card_tip(card)
    if not (card and card.children) then return end
    if card.children.h_popup then
        disable_tip_collision(card.children.h_popup)
    end
    if card.children.focused_ui then
        -- Keep Use/Sell clickable; only the tip popup must be pass-through.
    end
end

local function clear_controller_tip()
    local c = G and G.CONTROLLER
    if not c then return end
    pcall(function()
        c.finger_focus = nil
        if c.hovering then
            c.hovering.target = nil
            c.hovering.handled = true
        end
        if c.touch_control then
            c.touch_control.l_pressed = nil
            if c.touch_control.l_press then
                c.touch_control.l_press.target = nil
                c.touch_control.l_press.handled = true
            end
            c.touch_control.clear_touch = true
        end
        if c.focused and c.focused.target and c.focused.target.states and c.focused.target.states.focus then
            c.focused.target.states.focus.is = false
        end
    end)
end

local function clear_card_tip(card)
    if not card then return end
    pcall(function()
        if card.stop_hover then card:stop_hover() end
        if card.children then
            if card.children.h_popup then
                card.children.h_popup:remove()
                card.children.h_popup = nil
            end
            if card.children.focused_ui then
                card.children.focused_ui:remove()
                card.children.focused_ui = nil
            end
            if card.children.use_button then
                card.children.use_button:remove()
                card.children.use_button = nil
            end
        end
        if card.states and card.states.focus then
            card.states.focus.is = false
        end
        if card.states and card.states.hover then
            card.states.hover.is = false
        end
        card.config = card.config or {}
        card.config.h_popup = nil
        card.config.h_popup_config = nil
    end)
    clear_controller_tip()
    M._tip_owner = nil
    M._tip_shown_at = 0
    M._block_card = card
    M._block_until = now() + M.BLOCK_AFTER_DISMISS
end

function M.clamp_popup(cfg)
    if type(cfg) ~= "table" then return cfg end
    cfg.lr_clamp = true
    return cfg
end

local function has_card_tip(card)
    return card and card.children and card.children.h_popup and true or false
end

local function mark_tip_shown(card)
    if not card then return end
    sanitize_card_tip(card)
    if not has_card_tip(card) then return end
    if M._tip_owner ~= card then
        M._tip_owner = card
        M._tip_shown_at = now()
    elseif not M._tip_shown_at or M._tip_shown_at == 0 then
        M._tip_shown_at = now()
    end
end

-- Sticky: second press can briefly clear the tip via clear_touch before release.
-- Still treat that card as tipped so the release dismisses instead of reopening.
local function tip_ready_to_dismiss(card)
    if not card then return false end
    if M._tip_owner ~= card then
        return has_card_tip(card)
    end
    return (now() - (M._tip_shown_at or 0)) >= M.DISMISS_GRACE
end

-- Secondary info tips (Stone Card, Mult, etc.) always spawn on the left in vanilla.
-- Pick the side with more room, then flip once if that side still overflows.
function M.place_infotip(e)
    if not (e and e.config and e.config.ref_table) then return end
    local room_w = (G and G.ROOM and G.ROOM.T and G.ROOM.T.w) or 0
    local left_room = (e.T and e.T.x) or 0
    local right_room = room_w - ((e.T and (e.T.x + e.T.w)) or 0)
    local est = 2.4
    local prefer_left
    if left_room < est and right_room > left_room then
        prefer_left = false
    elseif right_room < est and left_room > right_room then
        prefer_left = true
    else
        prefer_left = left_room >= right_room
    end

    local align = prefer_left and "cl" or "cr"
    local ox = prefer_left and -0.03 or 0.03

    e.children.info = UIBox{
        definition = {
            n = G.UIT.ROOT,
            config = {align = "cm", colour = G.C.CLEAR, padding = 0.02},
            nodes = e.config.ref_table,
        },
        config = {
            offset = {x = ox, y = 0},
            align = align,
            parent = e,
            lr_clamp = true,
            can_collide = false,
        },
    }
    e.children.info:align_to_major()
    disable_tip_collision(e.children.info)

    local info = e.children.info
    if info and info.T and room_w > 0 then
        local overflow_l = info.T.x < -0.02
        local overflow_r = (info.T.x + info.T.w) > (room_w + 0.02)
        if (prefer_left and overflow_l) or ((not prefer_left) and overflow_r) then
            align = prefer_left and "cr" or "cl"
            ox = prefer_left and 0.03 or -0.03
            info:set_alignment({
                type = align,
                offset = {x = ox, y = 0},
                major = e,
                lr_clamp = true,
            })
            info:align_to_major()
            disable_tip_collision(info)
        end
        if info.lr_clamp then info:lr_clamp() end
    end
    e.config.ref_table = nil
end

function M.wrap_infotip()
    if M._infotip_wrapped then return true end
    if not (G and G.FUNCS and type(G.FUNCS.show_infotip) == "function") then return false end
    M._infotip_wrapped = true
    G.FUNCS.show_infotip = function(e)
        M.place_infotip(e)
    end
    return true
end

function M.tick()
    M.wrap_infotip()

    -- Keep tip trees pass-through even after delayed secondary tips attach.
    if M._tip_owner and has_card_tip(M._tip_owner) then
        sanitize_card_tip(M._tip_owner)
    elseif M._tip_owner and not has_card_tip(M._tip_owner) then
        -- Tip was lost without our dismiss (e.g. hover stolen). Clear sticky
        -- only after a short moment so a second press still dismisses.
        if (now() - (M._tip_shown_at or 0)) > 1.0 then
            M._tip_owner = nil
            M._tip_shown_at = 0
        end
    end

    if M._block_card and now() >= M._block_until then
        M._block_card = nil
        M._block_until = 0
    end
end

function M.init()
    if M._wrapped or not Card then return end
    M._wrapped = true

    if type(Card.align_h_popup) == "function" then
        local prev = Card.align_h_popup
        Card.align_h_popup = function(self, ...)
            return M.clamp_popup(prev(self, ...))
        end
    end

    if type(Card.hover) == "function" then
        local prev_hover = Card.hover
        Card.hover = function(self, ...)
            if blocked(self) then return end
            local ret = prev_hover(self, ...)
            mark_tip_shown(self)
            return ret
        end
    end

    local function wrap_tap(method_name)
        local prev = Card[method_name]
        if type(prev) ~= "function" then return end
        Card[method_name] = function(self, ...)
            if tip_ready_to_dismiss(self) then
                clear_card_tip(self)
                return
            end

            local prev_focus = G and G.CONTROLLER and G.CONTROLLER.focused and G.CONTROLLER.focused.target
            local ret = prev(self, ...)

            if prev_focus and prev_focus ~= self and getmetatable(prev_focus) == Card then
                if prev_focus.ability and prev_focus.ability.consumeable and (
                    has_card_tip(prev_focus) or M._tip_owner == prev_focus
                ) then
                    clear_card_tip(prev_focus)
                end
            end
            return ret
        end
    end

    wrap_tap("click")
    wrap_tap("single_tap")
    M.wrap_infotip()

    if not M._tick_wrapped and love and love.update then
        M._tick_wrapped = true
        local prev_update = love.update
        love.update = function(dt, ...)
            if prev_update then prev_update(dt, ...) end
            pcall(M.tick)
        end
    end
end

return M
