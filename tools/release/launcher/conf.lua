pcall(require, "win_dpi")
LAUNCHER_CLI = false
LAUNCHER_PLAY = false
local launcher_update = false
for _, a in ipairs(arg or {}) do
    if a == "--cli" then
        LAUNCHER_CLI = true
    elseif a == "--play" then
        LAUNCHER_PLAY = true
    elseif a == "--update" then
        launcher_update = true
    end
end
if launcher_update then
    LAUNCHER_PLAY = false
end

love.conf = function(t)
    t.identity = "BalatroOverhaulLauncher"
    t.version = "11.5"
    t.console = false
    t.accelerometerjoystick = false
    t.window.title = "Balatro Overhaul Launcher"
    t.window.width = 1280
    t.window.height = 720
    t.window.minwidth = 640
    t.window.minheight = 400
    t.window.resizable = true
    t.window.highdpi = false
    t.modules.physics = false
    t.modules.video = false
    if LAUNCHER_CLI or LAUNCHER_PLAY then
        t.window = nil
        t.modules.window = false
        t.modules.graphics = false
        t.modules.font = false
        t.modules.audio = false
        t.modules.sound = false
        t.modules.joystick = false
    end
end
