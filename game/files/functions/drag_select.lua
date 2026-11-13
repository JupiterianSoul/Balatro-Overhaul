DRAG_SELECT = {
    pending  = false,
    active   = false,
    timer    = 0,
    visited  = {},
    _prev_down = false,

    LONG_PRESS_TIME = 0.28,
    MOVE_THRESH     = 0.3,
    MAX_CARDS       = 5,

    browse_mode = false,
    _rclick_down = false,
    _start_x = nil,
    _start_y = nil,
    _from_card = false,
    _paint_on = true,
    _drag_cleared = false,
}

function DRAG_SELECT.reset()
    DRAG_SELECT.pending      = false
    DRAG_SELECT.active       = false
    DRAG_SELECT.timer        = 0
    DRAG_SELECT.visited      = {}
    DRAG_SELECT._start_x     = nil
    DRAG_SELECT._start_y     = nil
    DRAG_SELECT._from_card   = false
    DRAG_SELECT._paint_on    = true
    DRAG_SELECT._drag_cleared = false
    DRAG_SELECT._last_x      = nil
    DRAG_SELECT._last_y      = nil
end

function DRAG_SELECT.set_browse_mode(on)
    DRAG_SELECT.browse_mode = on
    if not on then
        DRAG_SELECT.reset()
        DRAG_SELECT._prev_down = false
        DRAG_SELECT._rclick_down = false
    end
end

local function screen_xy(ctrl)
    if G and G.CURSOR and G.CURSOR.T then
        return G.CURSOR.T.x, G.CURSOR.T.y
    end
    local h = ctrl.cursor_hover and ctrl.cursor_hover.T
    if h then return h.x, h.y end
    local t = ctrl.cursor_down and ctrl.cursor_down.T
    if t then return t.x, t.y end
    return nil, nil
end

local function cursor_xy(ctrl)
    local x, y = screen_xy(ctrl)
    if not (x and y) then return nil, nil end
    local R = G and G.ROOM and G.ROOM.T
    if R then return x - R.x, y - R.y end
    return x, y
end

local function moved_enough(ctrl)
    local x, y = cursor_xy(ctrl)
    local sx, sy = DRAG_SELECT._start_x, DRAG_SELECT._start_y
    if not (x and y and sx and sy) then return false end
    local dx, dy = x - sx, y - sy
    local th = math.max(DRAG_SELECT.MOVE_THRESH, G.MIN_CLICK_DIST or 0)
    return (dx * dx + dy * dy) >= th * th
end

local function clear_card_chrome(card)
    if not card then return end
    pcall(function()
        if card.stop_hover then card:stop_hover() end
        if card.states and card.states.hover then card.states.hover.is = false end
        if card.children then
            if card.children.h_popup then
                card.children.h_popup:remove()
                card.children.h_popup = nil
            end
            if card.children.focused_ui then
                card.children.focused_ui:remove()
                card.children.focused_ui = nil
            end
        end
        card.config = card.config or {}
        card.config.h_popup = nil
        card.config.h_popup_config = nil
    end)
end

local function suppress_card_drag(ctrl)
    if not ctrl then return end

    if ctrl.touch_control then
        if ctrl.touch_control.l_press then
            ctrl.touch_control.l_press.handled = true
        end
        ctrl.touch_control.l_pressed = nil
    end

    if ctrl.hovering then
        local ht = ctrl.hovering.target
        if ht then clear_card_chrome(ht) end
        ctrl.hovering.target = nil
        ctrl.hovering.handled = true
    end

    if not DRAG_SELECT._drag_cleared then
        local t = ctrl.dragging and ctrl.dragging.target
        local down = ctrl.cursor_down and ctrl.cursor_down.target
        local card = t or down
        if card then
            pcall(function()
                if card.stop_drag then card:stop_drag() end
                if card.states and card.states.drag then card.states.drag.is = false end
                if card.Click and card.T then
                    card.T.x = card.T.x
                end
                if card.VT and card.T then
                    card.VT.x, card.VT.y = card.T.x, card.T.y
                    card.VT.r = card.T.r or 0
                    card.VT.scale = card.T.scale or 1
                end
            end)
            clear_card_chrome(card)
        end
        DRAG_SELECT._drag_cleared = true
    end

    if ctrl.dragging then
        ctrl.dragging.target = nil
        ctrl.dragging.prev_target = nil
        ctrl.dragging.handled = true
    end
end

local function begin_card_drag(ctrl)
    local target = ctrl.cursor_down and ctrl.cursor_down.target
    if not (target and target.states and target.states.drag and target.states.drag.can) then
        return
    end
    pcall(function()
        target.states.drag.is = true
        if target.set_offset and ctrl.cursor_down and ctrl.cursor_down.T then
            target:set_offset(ctrl.cursor_down.T, 'Click')
        end
        ctrl.dragging.target = target
        ctrl.dragging.handled = false
        ctrl.dragging.prev_target = nil
    end)
end

local function hand_card_at(x, y)
    if not (x and y and G.hand and G.hand.cards) then return nil end
    local best, best_rank = nil, -1
    for _, card in ipairs(G.hand.cards) do
        local T = card.T
        if T and x >= T.x and x <= T.x + T.w and y >= T.y - 0.35 and y <= T.y + T.h + 0.35 then
            local rank = card.rank or 0
            if rank >= best_rank then
                best, best_rank = card, rank
            end
        end
    end
    return best
end

local function paint_card(card)
    if not card then return end
    if DRAG_SELECT.visited[card] then return end
    DRAG_SELECT.visited[card] = true
    clear_card_chrome(card)

    local highlighted = false
    for _, h in ipairs(G.hand.highlighted) do
        if h == card then highlighted = true; break end
    end
    if DRAG_SELECT._paint_on == nil then DRAG_SELECT._paint_on = not highlighted end

    if DRAG_SELECT._paint_on then
        if not highlighted and #G.hand.highlighted < DRAG_SELECT.MAX_CARDS then
            pcall(function() G.hand:add_to_highlighted(card, false) end)
        end
    else
        if highlighted then
            pcall(function() G.hand:remove_from_highlighted(card) end)
        end
    end
end

local function paint_path(x, y)
    if not (x and y) then return end
    local lx, ly = DRAG_SELECT._last_x or x, DRAG_SELECT._last_y or y
    local dx, dy = x - lx, y - ly
    local steps = math.min(40, math.ceil(math.sqrt(dx * dx + dy * dy) / 0.2))
    for i = 1, steps do
        paint_card(hand_card_at(lx + dx * i / steps, ly + dy * i / steps))
    end
    paint_card(hand_card_at(x, y))
    DRAG_SELECT._last_x, DRAG_SELECT._last_y = x, y
end

function DRAG_SELECT._update_browse(ctrl, dt)
    local is_down   = ctrl.is_cursor_down
    local prev_down = DRAG_SELECT._prev_down

    if is_down and not prev_down then
        DRAG_SELECT.pending = true
        DRAG_SELECT.active  = false
        DRAG_SELECT.timer   = 0
        DRAG_SELECT.visited = {}
    end

    if not is_down and prev_down then
        DRAG_SELECT.reset()
        DRAG_SELECT._prev_down = false
        return
    end

    if not is_down then
        DRAG_SELECT._prev_down = false
        return
    end

    if DRAG_SELECT.pending then
        DRAG_SELECT.pending = false
        DRAG_SELECT.active  = true
        DRAG_SELECT.visited = {}
        pcall(play_sound, 'card1', 1, 0.6)
    end

    if DRAG_SELECT.active then
        if ctrl.touch_control and ctrl.touch_control.l_press
           and not ctrl.touch_control.l_press.handled then
            ctrl.touch_control.l_press.handled = true
        end
        local collision = ctrl.collision_list
        if collision then
            for _, node in ipairs(collision) do
                if getmetatable(node) == Card
                   and not DRAG_SELECT.visited[node]
                   and node.single_tap then
                    DRAG_SELECT.visited[node] = true
                    pcall(node.single_tap)
                end
            end
        end
    end

    DRAG_SELECT._prev_down = is_down
end

function DRAG_SELECT.left_button()
    return G and G.SETTINGS and G.SETTINGS.drag_select_button == "left" or false
end

function DRAG_SELECT.left_press()
    DRAG_SELECT._lclick_down = true
    DRAG_SELECT._l_empty = nil
    DRAG_SELECT._l_at = G and G.TIMERS and G.TIMERS.UPTIME or 0
end

function DRAG_SELECT.left_release()
    DRAG_SELECT._lclick_down = false
    DRAG_SELECT._l_empty = nil
end

local function desktop_down(ctrl)
    if not DRAG_SELECT.left_button() then return DRAG_SELECT._rclick_down end
    if not DRAG_SELECT._lclick_down then return false end
    if DRAG_SELECT._l_empty == nil then
        local d = ctrl.cursor_down
        if ctrl.is_cursor_down and d and d.time and d.time >= (DRAG_SELECT._l_at or 0) then
            DRAG_SELECT._l_empty = d.target == G.ROOM
        end
    end
    return DRAG_SELECT._l_empty == true
end

function DRAG_SELECT._desktop_update(ctrl, dt)
    local is_down = desktop_down(ctrl)

    if not is_down and DRAG_SELECT._prev_down then
        DRAG_SELECT.reset()
        DRAG_SELECT._prev_down = false
        return
    end

    if not is_down then
        DRAG_SELECT._prev_down = false
        return
    end

    if not G.STATE or G.STATE ~= G.STATES.SELECTING_HAND or G.OVERLAY_MENU or (G.SETTINGS and G.SETTINGS.paused) then
        if DRAG_SELECT.pending or DRAG_SELECT.active then DRAG_SELECT.reset() end
        DRAG_SELECT._prev_down = is_down
        return
    end

    if not G.hand or not G.hand.cards then
        DRAG_SELECT._prev_down = is_down
        return
    end

    if is_down and not DRAG_SELECT._prev_down then
        DRAG_SELECT.active  = true
        DRAG_SELECT.visited = {}
        local x, y = cursor_xy(ctrl)
        local first = hand_card_at(x, y)
        DRAG_SELECT._paint_on = not (first and first.highlighted)
        if not first and DRAG_SELECT.left_button() then DRAG_SELECT._paint_on = nil end
        DRAG_SELECT._last_x, DRAG_SELECT._last_y = x, y
        pcall(play_sound, 'card1', 1, 0.6)
        if first then paint_card(first) end
    end

    if DRAG_SELECT.active then
        paint_path(cursor_xy(ctrl))
    end

    DRAG_SELECT._prev_down = is_down
end

function DRAG_SELECT.update(dt)
    if G and G.SETTINGS and G.SETTINGS.drag_select == false then
        if DRAG_SELECT.pending or DRAG_SELECT.active then DRAG_SELECT.reset() end
        return
    end
    if not G or not G.CONTROLLER then return end
    local ctrl = G.CONTROLLER

    if DRAG_SELECT.browse_mode and not G.OVERLAY_MENU then
        DRAG_SELECT.set_browse_mode(false)
    end

    if _G._IS_DESKTOP and not (ctrl.HID.touch and DRAG_SELECT._rclick_down ~= true) then
        DRAG_SELECT._desktop_update(ctrl, dt)
        return
    end

    if not ctrl.HID.touch then return end

    if DRAG_SELECT.browse_mode then
        DRAG_SELECT._update_browse(ctrl, dt)
        return
    end

    if not G.STATE or G.STATE ~= G.STATES.SELECTING_HAND or G.OVERLAY_MENU or (G.SETTINGS and G.SETTINGS.paused) then
        if DRAG_SELECT.pending or DRAG_SELECT.active then DRAG_SELECT.reset() end
        DRAG_SELECT._prev_down = ctrl.is_cursor_down
        return
    end

    if not G.hand or not G.hand.cards then
        DRAG_SELECT._prev_down = ctrl.is_cursor_down
        return
    end

    local is_down   = ctrl.is_cursor_down
    local prev_down = DRAG_SELECT._prev_down

    if is_down and not prev_down then
        local target = ctrl.cursor_down and ctrl.cursor_down.target
        local on_card = false
        if target and getmetatable(target) == Card then
            for _, card in ipairs(G.hand.cards) do
                if card == target then on_card = true; break end
            end
        end

        local cT = ctrl.cursor_down and ctrl.cursor_down.T
        local hT = G.hand.T
        local in_hand_y = cT and hT and (cT.y >= hT.y - 0.5) and (cT.y <= hT.y + hT.h + 0.5)
        local x, y = cursor_xy(ctrl)

        if on_card or in_hand_y then
            DRAG_SELECT.pending = true
            DRAG_SELECT.active  = false
            DRAG_SELECT.timer   = 0
            DRAG_SELECT.visited = {}
            DRAG_SELECT._start_x, DRAG_SELECT._start_y = x, y
            DRAG_SELECT._from_card = on_card
            DRAG_SELECT._drag_cleared = false
            suppress_card_drag(ctrl)
        else
            DRAG_SELECT.reset()
        end
    end

    if not is_down and prev_down then
        DRAG_SELECT.reset()
        DRAG_SELECT._prev_down = false
        return
    end

    if not is_down then
        DRAG_SELECT._prev_down = false
        return
    end

    if DRAG_SELECT.pending then
        DRAG_SELECT.timer = DRAG_SELECT.timer + dt
        suppress_card_drag(ctrl)

        if moved_enough(ctrl) then
            DRAG_SELECT.pending = false
            DRAG_SELECT.active  = true
            DRAG_SELECT.visited = {}
            local first = hand_card_at(DRAG_SELECT._start_x, DRAG_SELECT._start_y)
            DRAG_SELECT._paint_on = not (first and first.highlighted)
            DRAG_SELECT._last_x, DRAG_SELECT._last_y = DRAG_SELECT._start_x, DRAG_SELECT._start_y
            pcall(play_sound, 'card1', 1, 0.35)
            if first then paint_card(first) end
        elseif DRAG_SELECT.timer >= DRAG_SELECT.LONG_PRESS_TIME then
            DRAG_SELECT.reset()
            begin_card_drag(ctrl)
            local tc = ctrl.touch_control
            if tc and tc.l_press and tc.l_press.target then tc.l_press.handled = false end
            DRAG_SELECT._prev_down = is_down
            return
        end
    end

    if DRAG_SELECT.active then
        suppress_card_drag(ctrl)
        paint_path(cursor_xy(ctrl))
    end

    DRAG_SELECT._prev_down = is_down
end
