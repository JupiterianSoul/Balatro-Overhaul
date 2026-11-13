local install, broken = ...

local TEXT = {
	en = {
		title = "BALATRO OVERHAUL",
		checking = "Getting the Overhaul ready...",
		reading = "Reading Balatro...",
		patching = "Updating the Overhaul... %d%%",
		starting = "Starting the game...",
		retry = "RETRY",
		not_found = "Balatro is not installed on this phone. Install it from Google Play, then tap Retry.",
		bad_version = "This Overhaul does not match the Balatro on this phone (%s). Open Overhaul Launcher and rebuild the app.",
		no_patch = "The Overhaul files are missing from this app. Open Overhaul Launcher and rebuild the app.",
		failed = "The update did not finish (%s). Tap Retry.",
	},
	fr = {
		title = "BALATRO OVERHAUL",
		checking = "Préparation de l'Overhaul...",
		reading = "Lecture de Balatro...",
		patching = "Mise à jour de l'Overhaul... %d%%",
		starting = "Lancement du jeu...",
		retry = "RÉESSAYER",
		not_found = "Balatro n'est pas installé sur ce téléphone. Installe-le depuis Google Play, puis touche Réessayer.",
		bad_version = "Cet Overhaul ne correspond pas au Balatro de ce téléphone (%s). Ouvre Overhaul Launcher et refais l'app.",
		no_patch = "Les fichiers de l'Overhaul manquent dans cette app. Ouvre Overhaul Launcher et refais l'app.",
		failed = "La mise à jour n'a pas abouti (%s). Touche Réessayer.",
	},
	es = {
		title = "BALATRO OVERHAUL",
		checking = "Preparando el Overhaul...",
		reading = "Leyendo Balatro...",
		patching = "Actualizando el Overhaul... %d%%",
		starting = "Iniciando el juego...",
		retry = "REINTENTAR",
		not_found = "Balatro no está instalado en este teléfono. Instálalo desde Google Play y toca Reintentar.",
		bad_version = "Este Overhaul no coincide con el Balatro de este teléfono (%s). Abre Overhaul Launcher y vuelve a crear la app.",
		no_patch = "Faltan los archivos del Overhaul en esta app. Abre Overhaul Launcher y vuelve a crear la app.",
		failed = "La actualización no terminó (%s). Toca Reintentar.",
	},
}

local lang = (os.getenv("OVERHAUL_LANG") or "en"):lower():sub(1, 2)
local T = TEXT[lang] or TEXT.en

local S = {line = T.checking, frac = nil, err = nil, job = nil, fonts = {}, button = nil}

local function font(size)
	size = math.max(8, math.floor(size + 0.5))
	if not S.fonts[size] then S.fonts[size] = love.graphics.newFont(size) end
	return S.fonts[size]
end

local function report(phase, done, total)
	if phase == "copy" then
		S.line, S.frac = T.reading, nil
	elseif phase == "patch" and total and total > 0 then
		S.frac = math.min(1, (done or 0) / total)
		S.line = string.format(T.patching, math.floor(S.frac * 100))
	end
	coroutine.yield()
end

local function fail(why, detail)
	S.job, S.frac = nil, nil
	local fmt = T[why] or T.failed
	if why == "not_found" or why == "no_patch" then
		S.err = fmt
	else
		S.err = string.format(fmt, tostring(detail or why or "?"))
	end
	print("overhaul update: " .. tostring(why) .. " " .. tostring(detail))
end

local function start()
	S.err, S.line, S.frac = nil, T.checking, nil
	S.job = coroutine.create(function()
		local plan = install.plan(true)
		if not plan.want then
			if plan.have and not broken then return true end
			return false, "no_patch"
		end
		return install.run(report, plan)
	end)
end

function love.update()
	if not S.job then return end
	local alive, ok, why, detail = coroutine.resume(S.job)
	if not alive then
		fail("failed", ok)
	elseif coroutine.status(S.job) == "dead" then
		if ok == true then
			S.job, S.line, S.frac = nil, T.starting, 1
			install.mark_play()
			love.event.quit("restart")
		else
			fail(why, detail)
		end
	end
end

local function wrap(text, f, w)
	local _, lines = f:getWrap(text, w)
	return lines
end

function love.draw()
	local W, H = love.graphics.getDimensions()
	local u = math.min(W, H)
	love.graphics.clear(0.12, 0.17, 0.19)
	local title = font(u * 0.075)
	local body = font(u * 0.042)
	local cx = W / 2
	local y = H * 0.30
	love.graphics.setColor(0.99, 0.64, 0.0)
	love.graphics.setFont(title)
	love.graphics.print(T.title, math.floor(cx - title:getWidth(T.title) / 2), math.floor(y))
	y = y + title:getHeight() * 1.6
	love.graphics.setFont(body)
	local text = S.err or S.line
	love.graphics.setColor(S.err and 1 or 0.92, S.err and 0.42 or 0.92, S.err and 0.38 or 0.92)
	for _, line in ipairs(wrap(text, body, W * 0.84)) do
		love.graphics.print(line, math.floor(cx - body:getWidth(line) / 2), math.floor(y))
		y = y + body:getHeight() * 1.25
	end
	y = y + body:getHeight() * 0.8
	S.button = nil
	if S.err then
		local bw, bh = math.max(body:getWidth(T.retry) + u * 0.12, u * 0.45), body:getHeight() * 2.2
		local bx = math.floor(cx - bw / 2)
		love.graphics.setColor(0.0, 0.58, 1.0)
		love.graphics.rectangle("fill", bx, math.floor(y), bw, bh, bh * 0.18)
		love.graphics.setColor(1, 1, 1)
		love.graphics.print(T.retry, math.floor(cx - body:getWidth(T.retry) / 2), math.floor(y + (bh - body:getHeight()) / 2))
		S.button = {bx, y, bw, bh}
	elseif S.frac then
		local bw, bh = W * 0.6, math.max(6, u * 0.025)
		local bx = math.floor(cx - bw / 2)
		love.graphics.setColor(0.25, 0.3, 0.33)
		love.graphics.rectangle("fill", bx, math.floor(y), bw, bh, bh / 2)
		love.graphics.setColor(0.0, 0.58, 1.0)
		love.graphics.rectangle("fill", bx, math.floor(y), math.max(bh, bw * S.frac), bh, bh / 2)
	end
end

local function press(x, y)
	if not S.err then return end
	local b = S.button
	if b and x >= b[1] and x <= b[1] + b[3] and y >= b[2] and y <= b[2] + b[4] then start() end
end

function love.mousepressed(x, y)
	press(x, y)
end

function love.touchpressed(_, x, y)
	press(x, y)
end

function love.keypressed(k)
	if S.err and (k == "return" or k == "space") then start() end
	if k == "escape" then love.event.quit() end
end

function love.gamepadpressed(_, button)
	if S.err and button == "a" then start() end
	if button == "b" then love.event.quit() end
end

start()
