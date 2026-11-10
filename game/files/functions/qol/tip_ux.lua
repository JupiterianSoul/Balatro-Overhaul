local Q = QOL
local M = Q.feature("tip_ux", {})

-- Only long enough to stop the same-release hover path from recreating the tip.
M._block_until = 0
M._block_card = nil

local function now()
    return (G and G.TIMERS and G.TIMERS.REAL) or 0
end

local function blocked(card)
    return card and M._block_card == card and now() < M._block_until
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
    M._block_card = card
    -- ~6 frames @ 60Hz; covers same-tap reopen without eating the next tap.
    M._block_until = now() + 0.1
end

function M.clamp_popup(cfg)
    if type(cfg) ~= "table" then return cfg end
    cfg.lr_clamp = true
    return cfg
end

local function has_tip(card)
    if not card then return false end
    if card.children and (card.children.h_popup or card.children.focused_ui or card.children.use_button) then
        return true
    end
    if card.config and card.config.h_popup then
        return true
    end
    return false
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
        },
    }
    e.children.info:align_to_major()

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
    if not M._block_card then return end
    if now() >= M._block_until then
        M._block_card = nil
        M._block_until = 0
        return
    end
    -- Drop the suppress as soon as the dismiss finger is fully up.
    local c = G and G.CONTROLLER
    if c and not c.is_cursor_down then
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
            return prev_hover(self, ...)
        end
    end

    local function wrap_tap(method_name)
        local prev = Card[method_name]
        if type(prev) ~= "function" then return end
        Card[method_name] = function(self, ...)
            -- Only consume the tap when a tip is actually open.
            if has_tip(self) then
                clear_card_tip(self)
                return
            end

            local prev_focus = G and G.CONTROLLER and G.CONTROLLER.focused and G.CONTROLLER.focused.target
            local ret = prev(self, ...)

            if prev_focus and prev_focus ~= self and getmetatable(prev_focus) == Card then
                if prev_focus.ability and prev_focus.ability.consumeable and has_tip(prev_focus) then
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