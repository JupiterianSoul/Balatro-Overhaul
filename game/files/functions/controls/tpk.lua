local C = Controls
local P = {}

P.SET = "trackpad_keys"
P.SAVED = "tpk_binds"
P.KEYS = {
    confirm = false,
    run_info = "tab",
    play = "space",
    use = "f",
    move_left = "a",
    move_right = "g",
}

local function kp()
    return Extras and Extras.modules and Extras.modules.keyboard_play
end

local function on()
    return C.mode() == P.SET and not C.touch()
end

local function is_card(n)
    return type(n) == "table" and n.is and Card and n:is(Card) and not n.REMOVED
end

function P.pointer_card(areas)
    if not on() then return nil end
    local c = G.CONTROLLER
    if not (c and c.HID.mouse) then return nil end
    local h = c.hovering and c.hovering.target
    if not is_card(h) then return nil end
    for _, a in ipairs(areas) do
        if a and h.area == a then return h end
    end
end

function P.follow(card)
    if not (on() and is_card(card)) then return end
    local x, y = card:put_focused_cursor()
    if x and y then love.mouse.setPosition(x, y) end
end

function P.init()
    local K = kp()
    if not K or P._hooked then return end
    P._hooked = true
    K.SETS[P.SET] = {saved = P.SAVED, keys = P.KEYS}
    K.active_set = function()
        if (C.edit_mode or C.mode()) == P.SET then return P.SET end
    end
    K.pick_target = P.pointer_card
    K.after_move = P.follow
    if K.refresh then K.refresh() end
end

function P.on_mode()
    local K = kp()
    if K and K.refresh then K.capture = nil K.refresh() end
end

return P
