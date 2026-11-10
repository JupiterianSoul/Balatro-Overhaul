
DRAG_SELECT = {
    pending  = false,
    active   = false,

    timer    = 0,

    visited  = {},

    _prev_down = false,

    LONG_PRESS_TIME = 0,
    MAX_CARDS       = 5,

    browse_mode = false,

    _rclick_down = false,
}

function DRAG_SELECT.reset()
    DRAG_SELECT.pending    = false
    DRAG_SELECT.active     = false
    DRAG_SELECT.timer      = 0
    DRAG_SELECT.visited    = {}
end

function DRAG_SELECT.set_browse_mode(on)
    DRAG_SELECT.browse_mode = on
    if not on then
        DRAG_SELECT.reset()
        DRAG_SELECT._prev_down = false
        DRAG_SELECT._rclick_down = false
    end
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
        DRAG_SELECT.timer = DRAG_SELECT.timer + dt
        if DRAG_SELECT.timer >= DRAG_SELECT.LONG_PRESS_TIME then
            DRAG_SELECT.pending = false
            DRAG_SELECT.active  = true
            DRAG_SELECT.visited = {}
            pcall(play_sound, 'card1', 1, 0.6)
        end
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

function DRAG_SELECT._desktop_update(ctrl, dt)
    local is_down = DRAG_SELECT._rclick_down

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
        pcall(play_sound, 'card1', 1, 0.6)
    end

    if DRAG_SELECT.active then
        local collision = ctrl.collision_list
        if collision then
            for _, node in ipairs(collision) do
                if getmetatable(node) == Card then
                    for _, card in ipairs(G.hand.cards) do
                        if card == node then
                            if not DRAG_SELECT.visited[card] then
                                DRAG_SELECT.visited[card] = true
                                local already = false
                                for _, h in ipairs(G.hand.highlighted) do
                                    if h == card then already = true; break end
                                end
                                if already then
                                    pcall(function() G.hand:remove_from_highlighted(card) end)
                                elseif #G.hand.highlighted < DRAG_SELECT.MAX_CARDS then
                                    pcall(function() G.hand:add_to_highlighted(card, false) end)
                                end
                            end
                            break
                        end
                    end
                end
            end
        end
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
        if DRAG_SELECT.pending or DRAG_SELECT.active then
            DRAG_SELECT.reset()
        end
        DRAG_SELECT._prev_down = ctrl.is_cursor_down
        return
    end

    if not G.hand or not G.hand.cards then
        DRAG_SELECT._prev_down = ctrl.is_cursor_down
        return
    end

    local is_down  = ctrl.is_cursor_down
    local prev_down = DRAG_SELECT._prev_down

    if is_down and not prev_down then
        local target = ctrl.cursor_down and ctrl.cursor_down.target

        local on_card = false
        if target and getmetatable(target) == Card then
            for _, card in ipairs(G.hand.cards) do
                if card == target then
                    on_card = true
                    break
                end
            end
        end

        if not on_card then
            local cT = ctrl.cursor_down and ctrl.cursor_down.T
            local hT = G.hand.T
            local in_hand_y = cT and hT and (cT.y >= hT.y - 0.5) and (cT.y <= hT.y + hT.h + 0.5)
            if in_hand_y then
                DRAG_SELECT.pending = true
                DRAG_SELECT.active  = false
                DRAG_SELECT.timer   = 0
                DRAG_SELECT.visited = {}
            end
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
        if DRAG_SELECT.timer >= DRAG_SELECT.LONG_PRESS_TIME then
            DRAG_SELECT.pending = false
            DRAG_SELECT.active  = true
            DRAG_SELECT.visited = {}
            pcall(play_sound, 'card1', 1, 0.6)
        end
    end

    if DRAG_SELECT.active then
        if ctrl.touch_control and not ctrl.touch_control.l_press.handled then
            ctrl.touch_control.l_press.handled = true
        end

        local collision = ctrl.collision_list
        if collision then
            for _, node in ipairs(collision) do
                if getmetatable(node) == Card then
                    for _, card in ipairs(G.hand.cards) do
                        if card == node then
                            if not DRAG_SELECT.visited[card] then
                                DRAG_SELECT.visited[card] = true
                                local already = false
                                for _, h in ipairs(G.hand.highlighted) do
                                    if h == card then already = true; break end
                                end
                                if already then
                                    pcall(function()
                                        G.hand:remove_from_highlighted(card)
                                    end)
                                elseif #G.hand.highlighted < DRAG_SELECT.MAX_CARDS then
                                    pcall(function()
                                        G.hand:add_to_highlighted(card, false)
                                    end)
                                end
                            end
                            break
                        end
                    end
                end
            end
        end
    end

    DRAG_SELECT._prev_down = is_down
end
