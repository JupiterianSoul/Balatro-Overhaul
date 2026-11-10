local install = require("overhaul_install")

local direct = install.direct()
local play = install.take_play() or direct
if direct then install.carry() end
local plan = install.plan()
if play and not plan.need and plan.have and install.launch(plan.have) then return end

OVERHAUL_PHONE = {handoff = play and plan.need and (plan.have ~= nil or direct), direct = direct}
love.filesystem.setRequirePath("launcher/?.lua;launcher/?/init.lua;?.lua;?/init.lua")
love.filesystem.load("launcher/main.lua")()
