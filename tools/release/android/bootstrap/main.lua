local install = require("overhaul_install")

local direct = install.direct()
local play = install.take_play() or direct
if direct then install.carry() end
local plan = install.plan()
local broken = false
if play and not plan.need and plan.have then
	if install.launch(plan.have) then return end
	broken = true
end
local updating = direct and love.filesystem.getInfo("updating.lua") and love.filesystem.load("updating.lua")
if updating then
	updating(install, broken)
	return
end

if not direct then
	local before = {}
	for k in pairs(package.loaded) do before[k] = true end
	local native = tonumber((love.filesystem.read("native.txt") or ""):match("%d+")) or 0
	local code = love.filesystem.load("launcher/lcode.lua")().boot("launcher/", {native = native})
	if code.file then
		for k in pairs(package.loaded) do
			if not before[k] or k == "overhaul_install" or k:match("^patcher%.") then package.loaded[k] = nil end
		end
	end
end
OVERHAUL_PHONE = {handoff = play and plan.need and (plan.have ~= nil or direct), direct = direct}
love.filesystem.setRequirePath("launcher/?.lua;launcher/?/init.lua;?.lua;?/init.lua")
love.filesystem.load("launcher/main.lua")()
