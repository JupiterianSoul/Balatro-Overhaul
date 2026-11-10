SpeedrunWatch = SpeedrunWatch or {}
local W = SpeedrunWatch
local SR = Speedrun

W.FETCH_TIMEOUT = 20

local function L(s) return mod_loc(s) end

local function popup(text)
  local R = rawget(_G, 'bom_replay')
  if R and R.popup then pcall(R.popup, text) end
end

local function list_of(v, n)
  local out = {}
  if type(v) ~= 'table' then return out end
  for a = 1, n do
    local x = tonumber(v[a])
    if x and x >= 0 then out[a] = x end
  end
  return out
end

function W.begin(sprp, o)
  o = o or {}
  local SPR = rawget(_G, 'BO_SPREPLAY')
  if not (SPR and SPR.load and SPR.watch and sprp) then return false end
  local P = rawget(_G, 'bom_playback')
  if (P and P.active and P.active()) or SPR.watching then return false end
  local t = SPR.load(sprp)
  if not t then
    popup(L("No replay for this run"))
    return false
  end
  local sr = type(t.x) == 'table' and type(t.x.sr) == 'table' and t.x.sr or {}
  local cat = SR.cat(sr.cat) or SR.cat(o.cat)
  local target = cat and cat.target or 8
  W.cur = nil
  if not SPR.watch(sprp, nil, nil, {name = o.name, sr = true, data = t}) then return false end
  local pz = {}
  for i, p in ipairs(type(sr.pz) == 'table' and sr.pz or {}) do
    if type(p) == 'table' then pz[i] = {a = tonumber(p.a) or -1, b = tonumber(p.b) or -1} end
    if pz[i] and pz[i].b < 0 then pz[i].b = nil end
  end
  local splits = list_of(sr.splits, target)
  W.cur = {
    id = sprp, ms = 0, scan = 0, shown = 0, pz = pz, splits = splits, final = tonumber(sr.time) or splits[target],
    c = {watch = true, t = 0, splits = {}, cat = cat and cat.key or sr.cat, target = target, pb_splits = list_of(sr.pb_splits, target)},
  }
  return true
end

function W.clock()
  local w = W.cur
  local SPR = rawget(_G, 'BO_SPREPLAY')
  if not (w and SPR and SPR.watching and SPR.watching.id == w.id) then
    W.cur = nil
    return nil
  end
  local P = rawget(_G, 'bom_playback')
  local S = P and P.state and P.state()
  if not (S and type(S.entries) == 'table') then return nil end
  local last = math.min((tonumber(S.i) or 1) - 1, #S.entries)
  for i = w.scan + 1, last do
    local e = S.entries[i]
    local t = type(e) == 'table' and tonumber(e.t) or nil
    if t and t > w.ms then w.ms = t end
  end
  w.scan = math.max(w.scan, last)
  local c = w.c
  local goal = (w.ms - SR.paused_before(w.pz, w.ms)) / 1000
  local ante = G.GAME and G.GAME.round_resets and tonumber(G.GAME.round_resets.ante) or 1
  local ended = S.done and not S.drifted and last >= #S.entries
  for a = 1, c.target do
    local s = w.splits[a]
    if s and not c.splits[a] and (ended or ante > a or goal >= s) then c.splits[a] = s end
    if c.splits[a] then goal = math.max(goal, c.splits[a]) end
  end
  if c.splits[c.target] then
    goal = w.final or goal
    c.done = true
  end
  local dt = love.timer.getDelta()
  if goal > w.shown then
    w.shown = w.shown + (goal - w.shown) * math.min(1, dt * 6)
    if goal - w.shown < 0.05 then w.shown = goal end
  end
  c.t = w.shown
  return c
end

W.MAX_B64 = 256 * 1024

function W.pack(sprp)
  local SPR = rawget(_G, 'BO_SPREPLAY')
  if not (SPR and sprp and SPR.exists(sprp)) then return nil, 'missing' end
  local ok, raw = pcall(love.filesystem.read, SPR.path(sprp))
  if not ok or type(raw) ~= 'string' or #raw == 0 then return nil, 'missing' end
  local okz, z = pcall(love.data.compress, 'string', 'zlib', raw, 9)
  if not okz or type(z) ~= 'string' then return nil, 'missing' end
  local okb, b64 = pcall(love.data.encode, 'string', 'base64', z)
  if not okb or type(b64) ~= 'string' then return nil, 'missing' end
  if #b64 > W.MAX_B64 then return nil, 'too_big', #raw, #b64 end
  return b64, #raw
end

function W.unpack(b64, n)
  if type(b64) ~= 'string' then return nil end
  local okb, z = pcall(love.data.decode, 'string', 'base64', b64)
  if not okb or type(z) ~= 'string' then return nil end
  local okz, raw = pcall(love.data.decompress, 'string', 'zlib', z)
  if not okz or type(raw) ~= 'string' or (n and #raw ~= n) then return nil end
  return raw
end

function W.fetch(r)
  local SO = rawget(_G, 'SpeedrunOnline')
  if not (SO and r and r.id) then return false end
  if not SO.connected() then
    popup(L("Could not reach the server"))
    return false
  end
  SO.fetching = {id = r.id, row = r, at = love.timer.getTime()}
  SO.send({type = 'speedrun_replay_get', id = r.id})
  popup(L("Loading replay..."))
  return true
end

function W.on_replay(d)
  local SO = rawget(_G, 'SpeedrunOnline')
  local f = SO and SO.fetching
  if not (f and d and d.id == f.id) then return true end
  SO.fetching = nil
  local SB = rawget(_G, 'SpeedrunBoard')
  local function fail(text)
    if SB then SB.after_replay = nil end
    popup(text)
  end
  local SPR = rawget(_G, 'BO_SPREPLAY')
  local P = rawget(_G, 'bom_playback')
  if G.STAGE ~= G.STAGES.MAIN_MENU or (P and P.active and P.active()) or (SPR and SPR.watching) then
    if SB then SB.after_replay = nil end
    return true
  end
  if not d.ok then
    fail(L("This replay is not online"))
    return true
  end
  local raw = W.unpack(d.z, tonumber(d.n))
  if not (raw and SPR) then
    fail(L("This replay could not be read"))
    return true
  end
  local id = 'sro-' .. tostring(d.id):gsub('[^%w_%-]', '')
  pcall(love.filesystem.createDirectory, SPR.DIR)
  local ok = pcall(love.filesystem.write, SPR.path(id), raw)
  if not ok or not W.begin(id, {name = d.name ~= '' and d.name or f.row.name, cat = f.row.cat}) then fail(L("This replay could not be read")) end
  return true
end

function W.tick()
  local SO = rawget(_G, 'SpeedrunOnline')
  local f = SO and SO.fetching
  if f and love.timer.getTime() - f.at > W.FETCH_TIMEOUT then
    SO.fetching = nil
    local SB = rawget(_G, 'SpeedrunBoard')
    if SB then SB.after_replay = nil end
    popup(L("Could not reach the server"))
  end
end

local ev = rawget(_G, 'bom_events')
if ev and ev.register then
  ev.register('speedrun_replay', W.on_replay)
end

mod_loc_register{
  fr = {
    ["Loading replay..."] = "Chargement du replay...", ["This replay is not online"] = "Ce replay n'est pas en ligne",
    ["This replay could not be read"] = "Impossible de lire ce replay", ["Could not reach the server"] = "Serveur injoignable",
    ["No replay for this run"] = "Pas de replay pour cette partie",
  },
  es = {
    ["Loading replay..."] = "Cargando la repetición...", ["This replay is not online"] = "Esta repetición no está en línea",
    ["This replay could not be read"] = "No se pudo leer esta repetición", ["Could not reach the server"] = "No se pudo contactar con el servidor",
    ["No replay for this run"] = "No hay repetición de esta partida",
  },
}

return W
