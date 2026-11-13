package.path = "tools/release/launcher/?.lua;" .. package.path
love = {graphics = {}, mouse = {getPosition = function() return 0, 0 end}}
local U = require("ui")
local function hit(id, x, y, w, h, default)
    U.add_hit(id, x, y, w, h, function() end, {default = default})
end
U.begin_frame()
hit("tab_play", 100, 10, 80, 30)
hit("tab_game", 200, 10, 80, 30)
hit("main", 300, 100, 400, 60, true)
hit("second", 300, 180, 190, 40)
hit("folder", 510, 180, 190, 40)
U.add_hit("card", 50, 80, 150, 200, nil)
hit("quit", 50, 400, 650, 40)
U.focus = nil
U.move_focus(0, 1)
assert(U.focus == "main", "first press lands on the main button, got " .. tostring(U.focus))
U.move_focus(0, 1)
assert(U.focus == "second" or U.focus == "folder", "down goes to the row under it")
U.focus = "second"
U.move_focus(1, 0)
assert(U.focus == "folder", "right moves along the row")
U.move_focus(0, 1)
assert(U.focus == "quit", "down from the row reaches quit")
U.move_focus(0, -1)
assert(U.focus == "second" or U.focus == "folder", "up comes back")
U.focus = "main"
U.move_focus(0, -1)
assert(U.focus == "tab_game" or U.focus == "tab_play", "up from main reaches the tabs")
U.focus = "quit"
U.move_focus(0, 1)
assert(U.focus == "quit", "nothing below quit keeps the focus")
U.focus = "tab_play"
U.focus_cycle(-1)
assert(U.focus == "quit", "tab cycles round")
local pressed
U.begin_frame()
U.add_hit("a", 0, 0, 10, 10, function() pressed = true end)
U.focus = "a"
U.time = 1
assert(U.activate_focus() and pressed, "enter presses the focused button")
print("launcher ui nav tests ok")
