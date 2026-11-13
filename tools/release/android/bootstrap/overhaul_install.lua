local A = require("patcher.apply")
local love_ctx = require("patcher.love_ctx")

local M = {}

M.GAME_DIR = "overhaul_game"
M.NEW_DIR = "overhaul_game.new"
M.MARKER_NAME = ".overhaul_installed"
M.MARKER = M.GAME_DIR .. "/" .. M.MARKER_NAME
M.COPY = "official.zip"
M.MOUNT = "official"
M.VANILLA = "vanilla"
M.UPDATE = "update/patch.zip"
M.UPDATE_SUM = M.UPDATE .. ".sha256"
M.UPDATE_MOUNT = "update_patch"
M.SKIP = "update/skip"
M.FEEDS = {mobile = "android_patch", pc = "android_patch_pc"}
M.PLAY = "launcher_play"
M.DIRECT = "direct_play"
M.CARRY = "carry"
M.CARRY_DONE = "carry_done"
M.SLOTS = {"1", "2", "3"}
M.BUILT = "overhaul_built"
M.BUILT_MAIN = "game_main.lua"
M.BUILT_CONF = "game_conf.lua"
M.SHARED = "vanilla_shared.txt"

local function hex(data)
	return love.data.encode("string", "hex", love.data.hash("sha256", data))
end

function M.newer(a, b)
	local pa, pb = {}, {}
	for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
	for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
	for i = 1, math.max(#pa, #pb) do
		local x, y = pa[i] or 0, pb[i] or 0
		if x ~= y then return x > y end
	end
	return false
end

local function read_patch(root, source)
	local data = love.filesystem.read(root .. "/manifest.lua")
	if not data then return nil end
	local man = A.load_manifest(data)
	if not man or type(man.vanilla) ~= "table" then return nil end
	return {root = root, source = source, id = hex(data), man = man, version = tostring(man.overhaul_version or "0")}
end

function M.patch_id()
	local p = read_patch("patch", "bundled")
	return p and p.id or nil
end

local function update_sum()
	return ((love.filesystem.read(M.UPDATE_SUM) or ""):match("^(%x+)") or ""):lower()
end

function M.drop_update()
	love.filesystem.unmount(M.UPDATE)
	love.filesystem.remove(M.UPDATE)
	love.filesystem.remove(M.UPDATE_SUM)
end

local function mount_update()
	if #update_sum() ~= 64 then return nil end
	love.filesystem.unmount(M.UPDATE)
	if not love.filesystem.mount(M.UPDATE, M.UPDATE_MOUNT) then return nil end
	return read_patch(M.UPDATE_MOUNT, "update")
end

local function parse_marker(data)
	if not data then return nil end
	local id, version, vanilla, name, base = data:match("^(%x+)\n?([^\n]*)\n?([^\n]*)\n?([^\n]*)\n?([^\n]*)")
	if not id then return nil end
	return {id = id, version = version ~= "" and version or "0", vanilla = vanilla, name = name ~= "" and name or nil, base = base ~= "" and base or nil}
end

function M.marker_text(id, version, vanilla, name, base)
	return id .. "\n" .. tostring(version) .. "\n" .. tostring(vanilla or "") .. "\n" .. tostring(name or "") .. "\n" .. tostring(base or "") .. "\n"
end

function M.built()
	if not love.filesystem.getInfo(M.BUILT, "file") or not love.filesystem.getInfo(M.BUILT_MAIN, "file") then return nil end
	if love.filesystem.getRealDirectory(M.BUILT) == love.filesystem.getSaveDirectory() then return nil end
	local built = parse_marker(love.filesystem.read(M.BUILT))
	if built then built.built = true end
	return built
end

function M.installed()
	local saved = parse_marker(love.filesystem.read(M.MARKER))
	local built = M.built()
	if built and not (saved and (saved.base == built.id or M.newer(saved.version, built.version))) then
		built.stale = saved ~= nil
		return built
	end
	return saved
end

local function remove_tree(path)
	local info = love.filesystem.getInfo(path)
	if not info then return end
	if info.type == "directory" then
		for _, item in ipairs(love.filesystem.getDirectoryItems(path)) do
			remove_tree(path .. "/" .. item)
		end
	end
	love.filesystem.remove(path)
end

local function parent_dir(path)
	return path:match("^(.*)/[^/]*$")
end

local function write_file(rel, data)
	local path = M.NEW_DIR .. "/" .. rel
	local dir = parent_dir(path)
	if dir then love.filesystem.createDirectory(dir) end
	return love.filesystem.write(path, data)
end

local function mounted_game(root)
	local shared = {}
	if root == M.VANILLA .. "/" then
		for line in (love.filesystem.read(M.SHARED) or ""):gmatch("[^\r\n]+") do shared[line] = true end
	end
	local function where(name)
		if love.filesystem.getInfo(root .. name, "file") then return root .. name end
		if shared[name] and love.filesystem.getInfo(name, "file") then return name end
		return nil
	end
	local entries = setmetatable({}, {__index = function(_, name)
		return where(name) ~= nil or nil
	end})
	return {entries = entries, read = function(_, name)
		local path = where(name)
		return path and love.filesystem.read(path) or nil
	end}
end

local function copy_official(src, report)
	local inp = io.open(src, "rb")
	if not inp then error("open " .. src, 0) end
	local size = inp:seek("end") or 0
	inp:seek("set", 0)
	local out = love.filesystem.newFile(M.COPY, "w")
	local done = 0
	while true do
		local chunk = inp:read(4 * 1024 * 1024)
		if not chunk then break end
		out:write(chunk)
		done = done + #chunk
		report("copy", done, size)
	end
	out:close()
	inp:close()
end

local function first_line(data)
	return (data or ""):match("^([^\r\n]*)") or ""
end

local function swap()
	local base = love.filesystem.getSaveDirectory() .. "/"
	remove_tree(M.GAME_DIR)
	if love.filesystem.getInfo(M.GAME_DIR) then error("remove " .. M.GAME_DIR, 0) end
	if not os.rename(base .. M.NEW_DIR, base .. M.GAME_DIR) then error("rename " .. M.NEW_DIR, 0) end
end

function M.recover()
	if love.filesystem.getInfo(M.MARKER) then
		remove_tree(M.NEW_DIR)
	elseif love.filesystem.getInfo(M.NEW_DIR .. "/" .. M.MARKER_NAME) then
		pcall(swap)
	end
end

function M.plan(force)
	M.recover()
	local list = {}
	local bundled = read_patch("patch", "bundled")
	if bundled then list[#list + 1] = bundled end
	if love.filesystem.getInfo(M.UPDATE) then
		local upd = mount_update()
		if upd then list[#list + 1] = upd else M.drop_update() end
	end
	local have = M.installed()
	if have and have.stale then
		remove_tree(M.GAME_DIR)
		have.stale = nil
	end
	local skip = have and love.filesystem.read(M.SKIP)
	local want
	for _, p in ipairs(list) do
		if (p.source ~= "bundled" or p.id ~= skip) and (not want or M.newer(p.version, want.version)
			or (not M.newer(want.version, p.version) and have and p.id == have.id)) then
			want = p
		end
	end
	local need = want ~= nil and (not have or (want.id ~= have.id and not M.newer(have.version, want.version)))
	if force and want and have and not M.newer(have.version, want.version) then need = true end
	for _, p in ipairs(list) do
		if p.source == "update" and not (need and p == want) then M.drop_update() end
	end
	return {have = have, want = need and want or nil, need = need, updating = need and have ~= nil}
end

function M.is_installed()
	local plan = M.plan()
	return plan.have ~= nil and not plan.need
end

local function open_vanilla(report)
	if love.filesystem.getInfo(M.VANILLA .. "/version.jkr") then return M.VANILLA .. "/" end
	local src = os.getenv("OVERHAUL_OFFICIAL_APK")
	if not src or src == "" then return nil, "not_found" end
	copy_official(src, report)
	love.filesystem.unmount(M.COPY)
	if not love.filesystem.mount(M.COPY, M.MOUNT) then
		love.filesystem.remove(M.COPY)
		return nil, "failed", "mount"
	end
	if not love.filesystem.getInfo(M.MOUNT .. "/assets/version.jkr") and love.filesystem.getInfo(M.MOUNT .. "/assets/game.love") then
		local inner = love.filesystem.read(M.MOUNT .. "/assets/game.love")
		love.filesystem.unmount(M.COPY)
		love.filesystem.remove(M.COPY)
		if not inner or not love.filesystem.write(M.COPY, inner) then return nil, "failed", "inner" end
		inner = nil
		collectgarbage()
		if not love.filesystem.mount(M.COPY, M.MOUNT) then
			love.filesystem.remove(M.COPY)
			return nil, "failed", "mount"
		end
		return M.MOUNT .. "/"
	end
	return M.MOUNT .. "/assets/"
end

local function check_update()
	local ok, fd = pcall(love.filesystem.newFileData, M.UPDATE)
	if not ok or not fd then return false end
	local sum = hex(fd)
	fd:release()
	return sum == update_sum()
end

function M.bundled()
	return read_patch("patch", "bundled")
end

function M.choose(pick, z, yield)
	local man = pick.man
	local ctx = love_ctx(function(rel) return love.filesystem.read(pick.root .. "/" .. rel) end)
	ctx.yield = yield
	local fine, cerr = A.check(man, z, ctx)
	local alt = pick.source == "bundled" and not (fine and fine.exact) and read_patch("patch_pc", "bundled")
	if alt then
		local actx = love_ctx(function(rel) return love.filesystem.read(alt.root .. "/" .. rel) end)
		actx.yield = yield
		local afine = A.check(alt.man, z, actx)
		if afine and (not fine or #afine.drift < #fine.drift) then
			man, ctx, fine, cerr = alt.man, actx, afine, nil
		end
	end
	if not fine then return nil, cerr end
	return man, ctx
end

function M.check_text(cerr, version)
	if cerr.code == "modded" then return tostring(version) .. " (" .. tostring(cerr.files[1]) .. ")" end
	return cerr.found or (version ~= "" and version) or "?"
end

function M.run(report, plan)
	plan = plan or M.plan()
	local pick = plan.want
	if not pick then return false, "failed", "patch missing" end
	report("find", 0, 1)
	local ok, a, b, c = pcall(function()
		if pick.source == "update" and not check_update() then return false, "damaged" end
		local root, why, detail = open_vanilla(report)
		if not root then return false, why, detail end
		local z = mounted_game(root)
		local version = A.game_version(z) or first_line(love.filesystem.read(root .. "version.jkr"))
		local man, ctx = M.choose(pick, z, function() report("find", 0, 1) end)
		if not man then return false, "bad_version", M.check_text(ctx, version) end
		remove_tree(M.NEW_DIR)
		love.filesystem.createDirectory(M.NEW_DIR)
		ctx.yield = function(i, n) report("patch", i, n) end
		local built, berr = A.build(man, z, ctx, write_file)
		if not built then error(tostring(berr.code) .. " " .. tostring(berr.file or berr.detail or ""), 0) end
		local over = M.built()
		local marker = M.marker_text(pick.id, pick.version, version, man.overhaul_name, over and over.id)
		local wrote, err = love.filesystem.write(M.NEW_DIR .. "/" .. M.MARKER_NAME, marker)
		if not wrote then error("write marker: " .. tostring(err), 0) end
		swap()
		return true
	end)
	love.filesystem.unmount(M.COPY)
	love.filesystem.remove(M.COPY)
	if pick.source == "update" then M.drop_update() end
	if ok and a == true then
		love.filesystem.remove(M.SKIP)
	else
		remove_tree(M.NEW_DIR)
		if plan.have and pick.source == "bundled" then
			love.filesystem.createDirectory("update")
			love.filesystem.write(M.SKIP, pick.id)
		end
	end
	if not ok then return false, "failed", tostring(a) end
	return a, b, c
end

local function pid()
	local ok, ffi = pcall(require, "ffi")
	if not ok then return "0" end
	pcall(ffi.cdef, "int getpid(void);")
	local got, n = pcall(function() return ffi.C.getpid() end)
	return got and tostring(tonumber(n)) or "0"
end

function M.mark_play()
	return love.filesystem.write(M.PLAY, pid() .. "\n")
end

function M.take_play()
	local data = love.filesystem.read(M.PLAY)
	if not data then return false end
	love.filesystem.remove(M.PLAY)
	return data:match("^(%d+)") == pid()
end

function M.drop_game()
	remove_tree(M.NEW_DIR)
	remove_tree(M.GAME_DIR)
	love.filesystem.remove(M.PLAY)
end

function M.direct()
	return love.filesystem.getInfo(M.DIRECT, "file") ~= nil and love.filesystem.getRealDirectory(M.DIRECT) ~= love.filesystem.getSaveDirectory()
end

local function carry_tree(dir, rel, overwrite)
	for _, item in ipairs(love.filesystem.getDirectoryItems(dir)) do
		local p = dir .. "/" .. item
		local r = rel == "" and item or rel .. "/" .. item
		local info = love.filesystem.getInfo(p)
		if item == ".import_id" then
		elseif info and info.type == "directory" then
			carry_tree(p, r, overwrite)
		elseif info and (overwrite or not love.filesystem.getInfo(r)) then
			local data = love.filesystem.read(p)
			if data then
				local parent = r:match("^(.*)/[^/]+$")
				if parent then love.filesystem.createDirectory(parent) end
				love.filesystem.write(r, data)
			end
		end
	end
end

local function backup_slots(tag, dir, rel)
	local out = "backups/before-import-" .. tag
	for _, item in ipairs(love.filesystem.getDirectoryItems(dir)) do
		local p = dir .. "/" .. item
		local r = rel == "" and item or rel .. "/" .. item
		local info = love.filesystem.getInfo(p)
		if item == ".import_id" then
		elseif info and info.type == "directory" then
			backup_slots(tag, p, r)
		elseif love.filesystem.getInfo(r, "file") and love.filesystem.getRealDirectory(r) == love.filesystem.getSaveDirectory() then
			local data = love.filesystem.read(r)
			if not data then error("read " .. r, 0) end
			local parent = (out .. "/" .. r):match("^(.*)/[^/]+$")
			love.filesystem.createDirectory(parent)
			if not love.filesystem.write(out .. "/" .. r, data) or love.filesystem.read(out .. "/" .. r) ~= data then
				error("backup " .. r, 0)
			end
		end
	end
end

function M.carry()
	if not love.filesystem.getInfo(M.CARRY, "directory") then return false end
	local import_id = love.filesystem.read(M.CARRY .. "/.import_id")
	if import_id and import_id ~= "" then
		local done = love.filesystem.read(M.CARRY_DONE) or ""
		if done:find("import " .. import_id, 1, true) then return false end
		local tag = import_id:gsub("[^%w%-]", "")
		if not pcall(backup_slots, tag, M.CARRY, "") then
			love.filesystem.write(M.CARRY_DONE, "failed\nbackup\n")
			return false
		end
		local ok = pcall(carry_tree, M.CARRY, "", true)
		love.filesystem.write(M.CARRY_DONE, (ok and "copied" or "failed") .. "\nimport " .. import_id .. "\n")
		return ok
	end
	if love.filesystem.getInfo(M.CARRY_DONE) then return false end
	for _, slot in ipairs(M.SLOTS) do
		if love.filesystem.getInfo(slot .. "/profile.jkr") then
			love.filesystem.write(M.CARRY_DONE, "kept\n")
			return false
		end
	end
	local ok = pcall(carry_tree, M.CARRY, "")
	love.filesystem.write(M.CARRY_DONE, ok and "copied\n" or "failed\n")
	return ok
end

function M.installed_name()
	local src = love.filesystem.read(M.GAME_DIR .. "/globals.lua") or ""
	return src:match("OVERHAUL_NAME%s*=%s*['\"]([^'\"]+)['\"]")
end

function M.feed_for(vanilla)
	if vanilla == "" or vanilla:find("[M]", 1, true) then return M.FEEDS.mobile end
	return M.FEEDS.pc
end

function M.feed()
	local have = M.installed()
	local vanilla = have and have.vanilla or ""
	if vanilla == "" and love.filesystem.getInfo(M.VANILLA .. "/version.jkr") then
		vanilla = first_line(love.filesystem.read(M.VANILLA .. "/version.jkr"))
	end
	return M.feed_for(vanilla)
end

function M.launch(have)
	have = have or M.installed()
	if not have then return false end
	love.filesystem.unmount(M.UPDATE)
	if have.built then
		if not love.filesystem.getInfo(M.BUILT_MAIN, "file") then return false end
	elseif not love.filesystem.getInfo(M.GAME_DIR .. "/main.lua", "file") or not love.filesystem.mount(M.GAME_DIR, "", false) then
		return false
	end
	local quit = love.event.quit
	love.event.quit = function(code, ...)
		if code == "restart" then M.mark_play() end
		return quit(code, ...)
	end
	rawset(_G, "OVERHAUL_BOOTSTRAP", {feed = M.feed_for(have.vanilla or ""), update = M.UPDATE, version = have.version, vanilla = have.vanilla, patch = have.id, main = have.built and M.BUILT_MAIN or nil})
	local conf = love.filesystem.load(have.built and M.BUILT_CONF or "conf.lua")
	if conf then conf() end
	package.loaded.main = nil
	if have.built then
		local name = M.BUILT_MAIN:gsub("%.lua$", "")
		package.preload.main = function()
			package.preload.main = nil
			return require(name)
		end
	end
	require("main")
	return true
end

return M
