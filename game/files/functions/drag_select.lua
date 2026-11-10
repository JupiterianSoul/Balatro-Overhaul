-- FEATURE: Mobile multi-select drag
-- Long-press (0.3s) on empty hand area → selection mode.
-- Dragging finger over cards selects OR unselects them (max 5).
-- Released finger or leaving SELECTING_HAND state exits selection mode.

DRAG_SELECT = {
    -- State flags
    pending  = false,   -- counting down toward long-press activation
    active   = false,   -- in selection mode; cards under finger are selected

    -- Pending timer
    timer    = 0,

    -- Cards already processed during this drag (prevent double-select)
    visited  = {},

    -- Previous is_cursor_down for edge-detection
    _prev_down = false,

    -- Tunable constants
    -- FIX: Set to 0 for INSTANT activation — selection starts immediately when finger lands on empty hand area, no perceptible delay.
    LONG_PRESS_TIME = 0,
    MAX_CARDS       = 5,

    -- Browse mode: active when a mod menu Browse/Remove window is open
    browse_mode = false,

    -- Desktop right-click drag state (PC only, set by love.mousepressed/released)
    _rclick_down = false,
}

-- ─────────────────────────────────────────────────
-- Reset all state (call on finger-up or state exit)
-- ─────────────────────────────────────────────────
function DRAG_SELECT.reset()
    DRAG_SELECT.pending    = false
    DRAG_SELECT.active     = false
    DRAG_SELECT.timer      = 0
    DRAG_SELECT.visited    = {}
end

-- ─────────────────────────────────────────────────
-- Enable/disable browse mode (call from mod_menu open/close)
-- ─────────────────────────────────────────────────
function DRAG_SELECT.set_browse_mode(on)
    DRAG_SELECT.browse_mode = on
    if not on then
        DRAG_SELECT.reset()
        -- FIX: Clear stale finger-down edge so the next press in hand re-arms pending
        DRAG_SELECT._prev_down = false
        DRAG_SELECT._rclick_down = false
    end
end

-- ─────────────────────────────────────────────────
-- Internal: per-frame drag logic for browse windows
-- Calls card.single_tap() on each unvisited card
-- the finger passes over, giving the same toggle
-- behaviour as a tap but across a drag gesture.
-- ─────────────────────────────────────────────────
function DRAG_SELECT._update_browse(ctrl, dt)
    local is_down   = ctrl.is_cursor_down
    local prev_down = DRAG_SELECT._prev_down

    -- Fresh finger-down: begin pending countdown
    if is_down and not prev_down then
        DRAG_SELECT.pending = true
        DRAG_SELECT.active  = false
        DRAG_SELECT.timer   = 0
        DRAG_SELECT.visited = {}
    end

    -- Finger released: cancel everything
    if not is_down and prev_down then
        DRAG_SELECT.reset()
        DRAG_SELECT._prev_down = false
        return
    end

    -- No finger on screen
    if not is_down then
        DRAG_SELECT._prev_down = false
        return
    end

    -- Pending: count down to activation
    if DRAG_SELECT.pending then
        DRAG_SELECT.timer = DRAG_SELECT.timer + dt
        if DRAG_SELECT.timer >= DRAG_SELECT.LONG_PRESS_TIME then
            DRAG_SELECT.pending = false
            DRAG_SELECT.active  = true
            DRAG_SELECT.visited = {}
            pcall(play_sound, 'card1', 1, 0.6)
        end
    end

    -- Active: call single_tap on every card the finger passes over
    if DRAG_SELECT.active then
        -- Suppress l_press so the normal tap handler doesn't also fire
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

-- ─────────────────────────────────────────────────
-- FEATURE: Desktop right-click drag-select
-- Right-click hold activates instantly (no long-press delay).
-- Dragging over hand cards selects/deselects them.
-- ─────────────────────────────────────────────────
function DRAG_SELECT._desktop_update(ctrl, dt)
    local is_down = DRAG_SELECT._rclick_down

    -- Released: reset
    if not is_down and DRAG_SELECT._prev_down then
        DRAG_SELECT.reset()
        DRAG_SELECT._prev_down = false
        return
    end

    if not is_down then
        DRAG_SELECT._prev_down = false
        return
    end

    -- Only active during card selection
    if not G.STATE or G.STATE ~= G.STATES.SELECTING_HAND or G.OVERLAY_MENU or (G.SETTINGS and G.SETTINGS.paused) then
        if DRAG_SELECT.pending or DRAG_SELECT.active then DRAG_SELECT.reset() end
        DRAG_SELECT._prev_down = is_down
        return
    end

    if not G.hand or not G.hand.cards then
        DRAG_SELECT._prev_down = is_down
        return
    end

    -- Fresh right-click: activate immediately
    if is_down and not DRAG_SELECT._prev_down then
        DRAG_SELECT.active  = true
        DRAG_SELECT.visited = {}
        pcall(play_sound, 'card1', 1, 0.6)
    end

    -- Active: select/unselect hand cards under cursor
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

-- ─────────────────────────────────────────────────
-- Main per-frame update, called from love.update
-- ─────────────────────────────────────────────────
function DRAG_SELECT.update(dt)
    -- Guard: feature disabled
    if G and G.SETTINGS and G.SETTINGS.drag_select == false then
        if DRAG_SELECT.pending or DRAG_SELECT.active then DRAG_SELECT.reset() end
        return
    end
    -- Guard: need controller and touch HID
    if not G or not G.CONTROLLER then return end
    local ctrl = G.CONTROLLER

    -- FIX: Auto-clear stale browse_mode when no overlay menu is open.
    -- Prevents drag-select from being stuck routing to _update_browse after
    -- the mod menu Add/Remove cards window was closed by an unexpected path
    -- that didn't trigger mod_browse_back_cards.
    if DRAG_SELECT.browse_mode and not G.OVERLAY_MENU then
        DRAG_SELECT.set_browse_mode(false)
    end

    -- FEATURE: Desktop right-click drag-select (PC only)
    if _G._IS_DESKTOP and not (ctrl.HID.touch and DRAG_SELECT._rclick_down ~= true) then
        DRAG_SELECT._desktop_update(ctrl, dt)
        return
    end

    if not ctrl.HID.touch then return end

    -- Route to browse mode handler when a browse window is open
    if DRAG_SELECT.browse_mode then
        DRAG_SELECT._update_browse(ctrl, dt)
        return
    end

    -- Guard: only active during card selection phase
    if not G.STATE or G.STATE ~= G.STATES.SELECTING_HAND or G.OVERLAY_MENU or (G.SETTINGS and G.SETTINGS.paused) then
        if DRAG_SELECT.pending or DRAG_SELECT.active then
            DRAG_SELECT.reset()
        end
        DRAG_SELECT._prev_down = ctrl.is_cursor_down
        return
    end

    -- Guard: need a valid hand area
    if not G.hand or not G.hand.cards then
        DRAG_SELECT._prev_down = ctrl.is_cursor_down
        return
    end

    local is_down  = ctrl.is_cursor_down
    local prev_down = DRAG_SELECT._prev_down

    -- ── Detect fresh finger-down ─────────────────────────────────────
    if is_down and not prev_down then
        -- cursor_down.T is already in game units (set by L_cursor_press)
        local target = ctrl.cursor_down and ctrl.cursor_down.target

        -- Only start if touch is NOT on a hand card
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
            -- Also verify position is roughly within the hand area Y-range
            -- cursor_down.T is in game units; G.hand.T is also in game units
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
            -- Touch is on a card — make sure we're not in pending/active
            DRAG_SELECT.reset()
        end
    end

    -- ── Finger released ──────────────────────────────────────────────
    if not is_down and prev_down then
        DRAG_SELECT.reset()
        DRAG_SELECT._prev_down = false
        return
    end

    -- ── No finger → nothing to do ────────────────────────────────────
    if not is_down then
        DRAG_SELECT._prev_down = false
        return
    end

    -- ── Pending: count down (no cancel on movement) ─────────────────
    if DRAG_SELECT.pending then
        DRAG_SELECT.timer = DRAG_SELECT.timer + dt
        if DRAG_SELECT.timer >= DRAG_SELECT.LONG_PRESS_TIME then
            -- ── ACTIVATE selection mode ───────────────────────────
            DRAG_SELECT.pending = false
            DRAG_SELECT.active  = true
            DRAG_SELECT.visited = {}
            -- Haptic-style audio cue
            pcall(play_sound, 'card1', 1, 0.6)
        end
    end

    -- ── Active: select/unselect cards under finger ──────────────────
    if DRAG_SELECT.active then
        -- Prevent accidental s_tap / l_press from firing during this drag.
        -- Mark l_press as handled so the controller skips it.
        if ctrl.touch_control and not ctrl.touch_control.l_press.handled then
            ctrl.touch_control.l_press.handled = true
        end

        -- Walk the current collision list for hand cards
        local collision = ctrl.collision_list
        if collision then
            for _, node in ipairs(collision) do
                if getmetatable(node) == Card then
                    -- Is this card in G.hand.cards?
                    for _, card in ipairs(G.hand.cards) do
                        if card == node then
                            -- Not yet visited in this drag
                            if not DRAG_SELECT.visited[card] then
                                DRAG_SELECT.visited[card] = true
                                -- Check current highlight state
                                local already = false
                                for _, h in ipairs(G.hand.highlighted) do
                                    if h == card then already = true; break end
                                end
                                if already then
                                    -- Unselect
                                    pcall(function()
                                        G.hand:remove_from_highlighted(card)
                                    end)
                                elseif #G.hand.highlighted < DRAG_SELECT.MAX_CARDS then
                                    -- Select (only if under limit)
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
