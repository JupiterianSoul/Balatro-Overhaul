ModWorkshop = ModWorkshop or {}
local W = ModWorkshop

W.REPO = "kasimeka/balatro-mod-index"
W.BRANCH = "main"
W.DIR = "mods/.workshop"
W.THUMB_W, W.THUMB_H = 384, 216
W.REFRESH_EVERY = 1800
W.state = W.state or {}
W.jobs = W.jobs or {}
W.thumbs = W.thumbs or {}
W.later_queue = W.later_queue or {}
W.next_id = W.next_id or 0
W.net = W.net or {}

local TRANSLATIONS = {
  fr = {
    ["Installed"] = "Installés", ["Workshop"] = "Atelier", ["Mods Workshop"] = "Atelier de mods",
    ["Install"] = "Installer", ["Update"] = "Mettre à jour", ["Uninstall"] = "Désinstaller", ["Built in"] = "Intégré",
    ["Search mods"] = "Chercher un mod", ["All categories"] = "Toutes catégories", ["Recently updated"] = "Mis à jour récemment",
    ["Name A-Z"] = "Nom A-Z", ["Author"] = "Auteur", ["All mods"] = "Tous les mods", ["Not installed"] = "Non installés",
    ["Updates"] = "Mises à jour", ["Refresh"] = "Actualiser", ["Updating the list..."] = "Mise à jour de la liste...",
    ["Offline: saved list"] = "Hors ligne : liste enregistrée", ["No mods found"] = "Aucun mod trouvé",
    ["Downloading"] = "Téléchargement", ["Installing"] = "Installation", ["Waiting"] = "En attente", ["Done"] = "Terminé",
    ["Failed"] = "Échec", ["No connection"] = "Pas de connexion", ["Open page"] = "Ouvrir la page",
    ["Needs Talisman"] = "Nécessite Talisman", ["Update available"] = "Mise à jour disponible",
    ["Installing required mods"] = "Installation des mods requis", ["mods"] = "mods", ["by"] = "par",
    ["Not loaded"] = "Non chargé", ["Restart to apply"] = "Redémarrer pour appliquer", ["Version"] = "Version",
    ["Not a zip file"] = "Pas un fichier zip", ["Not in the Mods Workshop"] = "Absent de l'atelier",
    ["Version not available"] = "Version indisponible", ["Mod list from"] = "Liste du",
    ["Needs"] = "Nécessite", ["Conflicts with"] = "En conflit avec", ["Outdated"] = "Obsolète", ["Main file missing"] = "Fichier principal absent",
    ["Updated"] = "Récents", ["Name"] = "Nom", ["All"] = "Tous",
    ["Most popular"] = "Populaires", ["Most downloaded"] = "Téléchargements", ["Most liked"] = "Mieux notés",
    ["Enable"] = "Activer", ["Disable"] = "Désactiver", ["This mod needs"] = "Ce mod nécessite", ["Install all"] = "Tout installer",
    ["Cancel"] = "Annuler", ["Needs mods"] = "Mods requis",
    ["Tested"] = "Testé", ["Known issue"] = "Problème connu", ["Does not work"] = "Ne marche pas",
    ["Tested on"] = "Testé sur", ["Known issue on"] = "Problème connu sur", ["Does not work on"] = "Ne marche pas sur", ["Install anyway"] = "Installer quand même", ["Workshop has"] = "l'atelier a",
    ["Off"] = "Désactivé", ["not in the Workshop"] = "absent de l'atelier", ["more"] = "de plus",
    ["Download link broken"] = "Lien de téléchargement cassé", ["Broken link"] = "Lien cassé", ["you have"] = "vous avez", ["Cancelled"] = "Annulé",
    ["Source"] = "Source", ["Sources"] = "Sources", ["Mod Index"] = "Index des mods", ["Open on Nexus Mods"] = "Ouvrir sur Nexus Mods",
    ["nexus_note"] = "Ce mod vient de Nexus Mods. Il n'est pas intégré : téléchargez-le en dehors du jeu. Une fois le zip dans votre dossier Téléchargements, le jeu l'installe tout seul.",
  },
  es = {
    ["Installed"] = "Instalados", ["Workshop"] = "Taller", ["Mods Workshop"] = "Taller de mods",
    ["Install"] = "Instalar", ["Update"] = "Actualizar", ["Uninstall"] = "Desinstalar", ["Built in"] = "Integrado",
    ["Search mods"] = "Buscar mods", ["All categories"] = "Todas las categorías", ["Recently updated"] = "Actualizados hace poco",
    ["Name A-Z"] = "Nombre A-Z", ["Author"] = "Autor", ["All mods"] = "Todos los mods", ["Not installed"] = "No instalados",
    ["Updates"] = "Actualizaciones", ["Refresh"] = "Recargar", ["Updating the list..."] = "Actualizando la lista...",
    ["Offline: saved list"] = "Sin conexión: lista guardada", ["No mods found"] = "No hay mods",
    ["Downloading"] = "Descargando", ["Installing"] = "Instalando", ["Waiting"] = "En espera", ["Done"] = "Listo",
    ["Failed"] = "Error", ["No connection"] = "Sin conexión", ["Open page"] = "Abrir página",
    ["Needs Talisman"] = "Necesita Talisman", ["Update available"] = "Actualización disponible",
    ["Installing required mods"] = "Instalando los mods necesarios", ["mods"] = "mods", ["by"] = "por",
    ["Not loaded"] = "No cargado", ["Restart to apply"] = "Reinicia para aplicar", ["Version"] = "Versión",
    ["Not a zip file"] = "No es un archivo zip", ["Not in the Mods Workshop"] = "No está en el taller",
    ["Version not available"] = "Versión no disponible", ["Mod list from"] = "Lista del",
    ["Needs"] = "Necesita", ["Conflicts with"] = "En conflicto con", ["Outdated"] = "Obsoleto", ["Main file missing"] = "Falta el archivo principal",
    ["Updated"] = "Recientes", ["Name"] = "Nombre", ["All"] = "Todos",
    ["Most popular"] = "Populares", ["Most downloaded"] = "Más descargados", ["Most liked"] = "Mejor valorados",
    ["Enable"] = "Activar", ["Disable"] = "Desactivar", ["This mod needs"] = "Este mod necesita", ["Install all"] = "Instalar todo",
    ["Cancel"] = "Cancelar", ["Needs mods"] = "Faltan mods", ["Off"] = "Desactivado", ["not in the Workshop"] = "no está en el taller", ["more"] = "más",
    ["Tested"] = "Probado", ["Known issue"] = "Problema conocido", ["Does not work"] = "No funciona",
    ["Tested on"] = "Probado en", ["Known issue on"] = "Problema conocido en", ["Does not work on"] = "No funciona en", ["Install anyway"] = "Instalar igualmente", ["Workshop has"] = "el taller tiene",
    ["Download link broken"] = "Enlace de descarga roto", ["Broken link"] = "Enlace roto", ["you have"] = "tienes", ["Cancelled"] = "Cancelado",
    ["Source"] = "Fuente", ["Sources"] = "Fuentes", ["Mod Index"] = "Índice de mods", ["Open on Nexus Mods"] = "Abrir en Nexus Mods",
    ["nexus_note"] = "Este mod viene de Nexus Mods. No está integrado: descárgalo fuera del juego. Cuando el zip esté en tu carpeta de Descargas, el juego lo instala solo.",
  },
}

function W.loc(s)
  local lang = G and G.SETTINGS and G.SETTINGS.language or "en-us"
  if lang == "es_ES" or lang == "es_419" then lang = "es" end
  local t = TRANSLATIONS[lang]
  if t and t[s] then return t[s] end
  if s == "nexus_note" then return "This mod comes from Nexus Mods. It is not integrated: download it outside the game. Once the zip is in your Downloads folder, the game installs it by itself." end
  if mod_loc then return mod_loc(s) end
  return s
end

local function loader() return rawget(_G, "MODLOADER") end

function W.safe(s)
  return (tostring(s or ""):gsub("[^%w%-_%.@]", "_")):sub(1, 80)
end

local function serialize(v, out)
  local t = type(v)
  if t == "table" then
    out[#out + 1] = "{"
    local n = #v
    for i = 1, n do serialize(v[i], out); out[#out + 1] = "," end
    local keys = {}
    for k in pairs(v) do
      if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      out[#out + 1] = "["; serialize(k, out); out[#out + 1] = "]="; serialize(v[k], out); out[#out + 1] = ","
    end
    out[#out + 1] = "}"
  elseif t == "string" then
    out[#out + 1] = string.format("%q", v)
  elseif t == "number" or t == "boolean" then
    out[#out + 1] = tostring(v)
  else
    out[#out + 1] = "nil"
  end
end

local function write_table(path, tbl)
  local out = {"return "}
  serialize(tbl, out)
  love.filesystem.createDirectory(W.DIR)
  return love.filesystem.write(path, table.concat(out))
end

local function read_table(path)
  if not love.filesystem.getInfo(path, "file") then return nil end
  local ok, chunk = pcall(love.filesystem.load, path)
  if not ok or not chunk then return nil end
  setfenv(chunk, {})
  local ok2, data = pcall(chunk)
  if ok2 and type(data) == "table" then return data end
end

local PLATFORMS = {Android = "android", Windows = "windows", Linux = "linux"}
local PLATFORM_NAMES = {android = "Android", windows = "Windows", linux = "Linux"}

function W.platform()
  if W.platform_override then return W.platform_override end
  return PLATFORMS[love.system.getOS()]
end

function W.compat_table()
  if W._compat == nil then W._compat = read_table("resources/workshop/compat.lua") or false end
  return W._compat or nil
end

function W.compat_for(entry, platform)
  platform = platform or W.platform()
  local t = W.compat_table()
  local rec = platform and t and t.mods and entry and t.mods[entry.key]
  local r = rec and rec[platform]
  if type(r) ~= "table" or not r[1] then return nil end
  return r[1], r[2], platform, PLATFORM_NAMES[platform]
end

function W.mp_table()
  if W._mp == nil then W._mp = read_table("resources/workshop/mp_compat.lua") or false end
  return W._mp or nil
end

function W.mp_ok(entry)
  if type(entry) ~= "table" then return false end
  if entry.mp ~= nil then return entry.mp == true end
  local t = W.mp_table()
  local flag = t and t.mods and entry.key and t.mods[entry.key]
  if flag ~= nil then return flag == true end
  local c = W.compat_table()
  local rec = c and c.mods and entry.key and c.mods[entry.key]
  if type(rec) ~= "table" then return false end
  for _, p in ipairs({"linux", "windows", "android"}) do
    local r = rec[p]
    if type(r) ~= "table" or r[1] ~= "ok" then return false end
  end
  return true
end

function W.start()
  W.hook_update()
  if W.threads then return end
  W.threads = {}
  local L = loader()
  if L and L.kill_channels then
    L.kill_channels.workshop_req = {type = "kill"}
    L.kill_channels.workshop_thumb = {type = "kill"}
    L.kill_channels.workshop_update = {type = "kill"}
  end
  if L and L.thread_channels then
    local have = {}
    for _, c in ipairs(L.thread_channels) do have[c] = true end
    for _, c in ipairs({"workshop_req", "workshop_thumb", "workshop_update", "workshop_res"}) do
      if not have[c] then L.thread_channels[#L.thread_channels + 1] = c end
    end
  end
  love.filesystem.createDirectory(W.DIR)
  for _, name in ipairs({"workshop_req", "workshop_thumb", "workshop_update"}) do
    love.thread.getChannel(name):clear()
    local t = love.thread.newThread("functions/mod_workshop_http.lua")
    t:start(name)
    W.threads[name] = t
  end
end

function W.request(kind, job, cb, progress)
  W.start()
  W.next_id = W.next_id + 1
  job.id = W.next_id
  job.type = kind
  W.jobs[job.id] = {cb = cb, progress = progress, kind = kind}
  local lane = kind == "thumb" and "workshop_thumb" or (job.lane == "update" and "workshop_update") or "workshop_req"
  love.thread.getChannel(lane):push(job)
  return job.id
end

function W.later(fn, frames)
  W.hook_update()
  W.later_queue[#W.later_queue + 1] = {fn = fn, frames = frames or 2}
end

local function friendly(err, code)
  err = tostring(err or "")
  if err:find("no_tunnel") or err:find("refused") or err:find("unreachable") or err:find("no backend")
    or err:find("curl failed") or err:find("https:") or err:find("tunnel:") or err:find("host") then
    return W.loc("No connection")
  end
  if err:find("timeout") then return W.loc("No connection") end
  local c = code or tonumber(err:match("http (%d+)"))
  if c == 404 then return "404" end
  if c == 403 or c == 429 then return "GitHub " .. c end
  if c then return "HTTP " .. c end
  return err:sub(1, 60)
end
W.friendly = friendly

function W.poll()
  if not W.threads then return end
  local ch = love.thread.getChannel("workshop_res")
  for _ = 1, 50 do
    local msg = ch:pop()
    if not msg then break end
    local job = W.jobs[msg.id]
    if job then
      if msg.type == "progress" then
        if job.progress then pcall(job.progress, msg.got, msg.total) end
      else
        W.jobs[msg.id] = nil
        if msg.backend then W.net.backend = msg.backend end
        if job.cb then
          local ok, err = pcall(job.cb, msg)
          if not ok then print("[workshop] callback error: " .. tostring(err)) end
        end
      end
    end
  end
  for name, t in pairs(W.threads) do
    local err = t:getError()
    if err then
      print("[workshop] thread " .. name .. " error: " .. tostring(err))
      W.threads = nil
      for id, job in pairs(W.jobs) do
        W.jobs[id] = nil
        if job.cb then pcall(job.cb, {ok = false, err = "worker stopped"}) end
      end
      break
    end
  end
end

local function run_later()
  if #W.later_queue == 0 then return end
  local q = W.later_queue
  W.later_queue = {}
  for _, item in ipairs(q) do
    item.frames = item.frames - 1
    if item.frames <= 0 then
      local ok, err = pcall(item.fn)
      if not ok then print("[workshop] " .. tostring(err)) end
    else
      W.later_queue[#W.later_queue + 1] = item
    end
  end
end

function W.tick()
  W.poll()
  run_later()
end

function W.hook_update()
  if not G or rawget(G, "_workshop_hooked") then return end
  local orig = rawget(G, "update")
  G.update = function(self, dt, ...)
    local r
    if orig then r = orig(self, dt, ...) else r = Game.update(self, dt, ...) end
    W.tick()
    return r
  end
  G._workshop_hooked = true
end

local function index_by_key(idx)
  idx.by_key = {}
  for _, m in ipairs(idx.mods) do idx.by_key[m.key] = m end
end

function W.load_index()
  if W.index then return W.index end
  local bundle = read_table("resources/workshop/index.lua") or {mods = {}, built = 0}
  local cache = read_table(W.DIR .. "/index.lua")
  local idx = bundle
  if cache and type(cache.mods) == "table" and (cache.built or 0) >= (bundle.built or 0) then idx = cache end
  idx.mods = idx.mods or {}
  index_by_key(idx)
  W.index = idx
  W.installed = read_table(W.DIR .. "/installed.lua") or {}
  return idx
end

function W.save_index()
  W._find_cache = nil
  local idx = W.index
  if not idx then return end
  local by_key = idx.by_key
  idx.by_key = nil
  write_table(W.DIR .. "/index.lua", idx)
  idx.by_key = by_key
end

function W.save_installed()
  W._find_cache = nil
  write_table(W.DIR .. "/installed.lua", W.installed or {})
end

function W.refresh(force, done)
  local idx = W.load_index()
  if W.net.refreshing then return end
  if not force and os.time() - (idx.refreshed or 0) < W.REFRESH_EVERY and not W.net.failed then
    if done then done(true) end
    return
  end
  if not force and W.net.failed and os.time() - (W.net.failed_at or 0) < 60 then return end
  local known = {}
  for _, m in ipairs(idx.mods) do if not m.extra then known[m.key] = m.sha or "" end end
  W.net.refreshing = true
  W.net.refresh_progress = nil
  W.request("refresh", {repo = idx.source or W.REPO, branch = idx.branch or W.BRANCH, mods_sha = idx.mods_sha, known = known}, function(res)
    W.net.refreshing = false
    if not res.ok then
      W.net.failed = friendly(res.err, res.code)
      W.net.failed_at = os.time()
      if done then done(false, W.net.failed) end
      W.changed = true
      return
    end
    W.net.failed = nil
    local now = os.time()
    idx.mods_sha = res.mods_sha
    idx.refreshed = now
    if not res.same then
      for _, u in ipairs(res.updates or {}) do
        local old = idx.by_key[u.key]
        if old then
          if u.url ~= old.url then
            old.broken = nil
            for _, src in ipairs(type(old.sources) == "table" and old.sources or {}) do
              if src.kind == "index" then
                src.dl, src.version, src.broken = u.url, u.version, nil
              end
            end
          end
          for k, v in pairs(u) do old[k] = v end
          if old.folder and not u.folder then old.folder = nil end
          old.updated = now
        else
          u.updated = now
          idx.mods[#idx.mods + 1] = u
          idx.by_key[u.key] = u
        end
      end
      local gone = {}
      for _, key in ipairs(res.removed or {}) do gone[key] = true end
      if next(gone) then
        local keep = {}
        for _, m in ipairs(idx.mods) do if not gone[m.key] then keep[#keep + 1] = m end end
        idx.mods = keep
        index_by_key(idx)
      end
    end
    W.save_index()
    W.changed = true
    if done then done(true) end
  end, function(got, total)
    W.net.refresh_progress = total and total > 0 and (got / total) or nil
  end)
end

function W.thumb_path(entry)
  return W.DIR .. "/thumbs/" .. W.safe(entry.key) .. ".png"
end

function W.thumb(entry)
  local key = entry.key
  local cur = W.thumbs[key]
  if cur then return cur ~= "loading" and cur or nil end
  if cur == false then return nil end
  local path = W.thumb_path(entry)
  if love.filesystem.getInfo(path, "file") then
    local ok, img = pcall(love.graphics.newImage, path, {mipmaps = true})
    if ok and img then
      img:setFilter("linear", "linear")
      pcall(img.setMipmapFilter, img, "linear")
      local w, h = img:getDimensions()
      local atlas = {name = "workshop_thumb_" .. key, image = img, px = w, py = h, type = "asset_atli"}
      W.thumbs[key] = atlas
      return atlas
    end
    love.filesystem.remove(path)
  end
  if entry.thumb == false then
    W.thumbs[key] = false
    return nil
  end
  W.thumbs[key] = "loading"
  local idx = W.load_index()
  local url = entry.thumb_url or ("https://raw.githubusercontent.com/" .. (idx.source or W.REPO) .. "/" .. (idx.branch or W.BRANCH) .. "/mods/" .. key .. "/thumbnail.jpg")
  W.request("thumb", {url = url, path = path, w = W.THUMB_W, h = W.THUMB_H}, function(res)
    if res.ok then
      W.thumbs[key] = nil
      entry.thumb = true
      W.thumb_done = W.thumb_done or {}
      W.thumb_done[key] = true
    else
      W.thumbs[key] = false
      if tostring(res.err):find("http 404") then entry.thumb = false end
    end
    W.thumbs_changed = true
  end)
  return nil
end

local function norm(s)
  return tostring(s or ""):lower():gsub("[^%w]", "")
end
W.norm = norm

local function norm_version(v)
  v = tostring(v or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  return (v:gsub("^v", ""))
end
W.norm_version = norm_version

local function semver(v)
  v = norm_version(v)
  if not v:match("^%d+[%.%d]*$") then return nil end
  local parts = {}
  for n in v:gmatch("%d+") do parts[#parts + 1] = tonumber(n) end
  return parts
end

local function newer(a, b)
  local pa, pb = semver(a), semver(b)
  if not pa or not pb then return false end
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x > y end
  end
  return false
end

function W.local_mods(force)
  if W._local and not force then return W._local end
  local L = loader()
  local status = L and L.status and L.status() or {mods = {}}
  local by_id, by_folder, by_name = {}, {}, {}
  for _, m in ipairs(status.mods or {}) do
    if m.id then by_id[norm(m.id)] = m end
    by_folder[m.folder] = m
    by_name[norm(m.name)] = m
  end
  W._local = {mods = status.mods or {}, by_id = by_id, by_folder = by_folder, by_name = by_name}
  return W._local
end

function W.invalidate_local()
  W._local = nil
end

function W.find_local(entry)
  local lm = W.local_mods()
  local rec = W.installed and W.installed[entry.key]
  if rec then
    for _, f in ipairs(rec.folders or {}) do
      if lm.by_folder[f] then return lm.by_folder[f], rec end
    end
  end
  local m = (entry.id and lm.by_id[norm(entry.id)]) or (entry.folder and lm.by_folder[entry.folder])
    or lm.by_name[norm(entry.title)]
  return m, rec
end

function W.builtin(entry)
  local k = entry.key:lower()
  return k:match("^steamodded@") ~= nil or norm(entry.title) == "steamodded" or norm(entry.title) == "smods"
end

function W.entry_status(entry)
  local st = W.state[entry.key]
  if st and (st.stage == "download" or st.stage == "install" or st.stage == "queued") then return "busy", st end
  if st and st.stage == "deps" then return "deps", st end
  if st and st.stage == "warn" then return "warn", st end
  if W.builtin(entry) then return "builtin" end
  local m, rec = W.find_local(entry)
  if not m then return "none", st end
  if rec and rec.version and entry.version ~= "" and rec.version ~= entry.version then return "update", st, m end
  if not rec and m.version and newer(entry.version, m.version) then return "update", st, m end
  return "installed", st, m
end

function W.update_for_local(m)
  local idx = W.load_index()
  for _, entry in ipairs(idx.mods) do
    local lm, rec = W.find_local(entry)
    if lm == m then
      local s = W.entry_status(entry)
      return s == "update" and entry or nil, entry
    end
  end
end

local function github_repo(entry)
  local o, r = tostring(entry.repo or ""):match("^https?://github%.com/([^/]+)/([^/#?]+)")
  if o then return o, (r:gsub("%.git$", "")) end
end

local SKIP_DEPS = {steamodded = true, smods = true, lovely = true, balatro = true}

local DEP_OPS = {
  ["<<"] = function(a, b) return a < b end,
  [">>"] = function(a, b) return a > b end,
  ["<="] = function(a, b) return a <= b end,
  [">="] = function(a, b) return a >= b end,
  ["=="] = function(a, b) return a == b end,
}

local function dep_checks(alt)
  local checks = {}
  for vs in alt:gmatch("%((.-)%)") do
    vs = vs:gsub("%s", "")
    local op, ver = vs:match("^(..)(.+)$")
    if op and DEP_OPS[op] then checks[#checks + 1] = {op = op, ver = ver} end
  end
  if #checks == 0 then
    local op, ver = alt:match("^%s*[^%s%(<>=]+%s*([<>=][<>=])%s*([^%s%)]+)")
    if op and DEP_OPS[op] then checks[1] = {op = op, ver = ver} end
  end
  return checks
end

local function dep_alts(d)
  local out = {}
  for alt in tostring(d or ""):gmatch("[^|]+") do
    local id = alt:match("^%s*([^%s%(<>=]+)")
    if id then out[#out + 1] = id end
  end
  return out
end

local function version_lib()
  if W._vlib ~= nil then return W._vlib or nil end
  local L = loader()
  local lib = L and L._libs and L._libs.util
  if not (lib and lib.V) then
    local ok, chunk = pcall(love.filesystem.load, ((L and L.fork_dir) or "smods") .. "/src/preflight/sharedUtil.lua")
    if ok and chunk then
      local ok2, res = pcall(chunk)
      if ok2 and type(res) == "table" then lib = res end
    end
  end
  W._vlib = (lib and lib.V) and lib or false
  return W._vlib or nil
end

function W.version_ok(have, checks)
  if not checks or #checks == 0 then return true end
  local lib = version_lib()
  if not lib then return true end
  for _, c in ipairs(checks) do
    local ok, res = pcall(function()
      local a, b = lib.V(norm_version(have)), lib.V(norm_version(c.ver))
      if not (a:is_valid(true) and b:is_valid(true)) then return true end
      return DEP_OPS[c.op](a, b)
    end)
    if ok and not res then return false end
  end
  return true
end

function W.range_text(checks)
  local parts = {}
  for _, c in ipairs(checks or {}) do
    local op = c.op == "<<" and "<" or c.op == ">>" and ">" or c.op
    parts[#parts + 1] = op .. norm_version(c.ver)
  end
  return table.concat(parts, " ")
end

local function local_dep(alts, checks)
  local lm = W.local_mods()
  local wrong
  for i, id in ipairs(alts) do
    local n = norm(id)
    local m = lm.by_id[n] or lm.by_folder[id]
    local amulet = false
    if not m and n == "talisman" and lm.by_id["amulet"] then m, amulet = lm.by_id["amulet"], true end
    if m then
      if amulet or W.version_ok(m.version, checks and checks[i]) then return m end
      wrong = wrong or m
    end
  end
  return nil, wrong
end

local function meta_deps(res)
  local out = {}
  for _, m in ipairs(res or {}) do
    for _, d in ipairs(m.meta and type(m.meta.dependencies) == "table" and m.meta.dependencies or {}) do out[#out + 1] = tostring(d) end
  end
  return out
end

W.dep_cache = W.dep_cache or {}

function W.fork_version()
  if W._fork_version == nil then
    local L = loader()
    local ok, chunk = pcall(love.filesystem.load, ((L and L.fork_dir) or "smods") .. "/version.lua")
    local v = ok and chunk and select(2, pcall(chunk))
    W._fork_version = type(v) == "string" and v or false
  end
  return W._fork_version or nil
end

function W.deps_for(entry, manifest_deps)
  local out, seen = {}, {}
  local own = {}
  if entry.id then own[norm(entry.id)] = true end
  local function add(d)
    local alts = dep_alts(d)
    if #alts == 0 then return end
    local checks = {}
    local i = 0
    for alt in tostring(d):gmatch("[^|]+") do
      if alt:match("^%s*([^%s%(<>=]+)") then
        i = i + 1
        checks[i] = dep_checks(alt)
      end
    end
    local n1 = norm(alts[1])
    if (n1 == "steamodded" or n1 == "smods") and not seen[n1] and checks[1] and #checks[1] > 0 then
      local fv = W.fork_version()
      if fv and not W.version_ok(fv, checks[1]) then
        seen[n1] = true
        out[#out + 1] = {id = "Steamodded", name = "Steamodded", missing = true, wrong = {version = fv},
          range = W.range_text(checks[1]), fixed = true}
        return
      end
    end
    for _, id in ipairs(alts) do
      local n = norm(id)
      if SKIP_DEPS[n] or own[n] or seen[n] then return end
    end
    for _, id in ipairs(alts) do seen[norm(id)] = true end
    local dep
    for _, id in ipairs(alts) do dep = dep or W.find_by_id(id) end
    if not dep then
      for _, id in ipairs(alts) do
        if norm(id) == "talisman" then dep = W.find_by_id("Amulet") end
      end
    end
    if dep and (W.builtin(dep) or dep == entry) then return end
    local have, wrong = local_dep(alts, checks)
    local busy = dep and W.entry_status(dep) == "busy"
    local range
    for j = 1, #alts do
      if not range and checks[j] and #checks[j] > 0 then range = W.range_text(checks[j]) end
    end
    local index_has
    if dep and not have then
      local fits = false
      for j = 1, #alts do
        if W.version_ok(dep.version, checks[j]) then fits = true end
      end
      if not fits then index_has, dep = dep.version, nil end
    end
    out[#out + 1] = {id = alts[1], name = dep and dep.title or alts[1], entry = dep, have = have, missing = not have and not busy,
      wrong = wrong, range = range, index_has = index_has}
  end
  if entry.talisman then add("Talisman") end
  local rec = W.installed and W.installed[entry.key]
  for _, d in ipairs(manifest_deps or W.dep_cache[entry.key] or (rec and rec.deps) or entry.deps or {}) do add(d) end
  return out
end

function W.missing_deps(entry, manifest_deps)
  local out = {}
  for _, d in ipairs(W.deps_for(entry, manifest_deps)) do
    if d.missing then out[#out + 1] = d end
  end
  return out
end

function W.install_deps(deps)
  for _, d in ipairs(deps or {}) do
    local s = d.entry and W.entry_status(d.entry)
    if d.missing and d.entry and (s == "none" or (d.wrong and s == "update")) then
      W.install(d.entry, {auto_deps = true}, function() W.changed = true end)
    end
  end
end

function W.enable_entry(entry, on, seen)
  local L = loader()
  if not (L and L.set_enabled) then return end
  seen = seen or {}
  if seen[entry.key] then return end
  seen[entry.key] = true
  local m, rec = W.find_local(entry)
  local folders = rec and rec.folders or (m and {m.folder}) or {}
  for _, f in ipairs(folders) do pcall(L.set_enabled, f, on) end
  if on then
    for _, d in ipairs(W.deps_for(entry)) do
      if d.have and not d.have.enabled then
        local dep = d.entry or W.find_by_id(d.have.id or d.have.folder, d.have.name)
        local dl = dep and W.find_local(dep)
        if dl and dl.folder == d.have.folder then
          W.enable_entry(dep, true, seen)
        else
          pcall(L.set_enabled, d.have.folder, true)
        end
      end
    end
  end
  W.invalidate_local()
  W.changed = true
end

function W.entry_enabled(entry)
  local m, rec = W.find_local(entry)
  if not m then return false end
  local lm = W.local_mods()
  for _, f in ipairs(rec and rec.folders or {m.folder}) do
    local x = lm.by_folder[f]
    if x and not x.enabled then return false end
  end
  return true
end

local function find_by_id(id, name)
  local idx = W.load_index()
  local nid = norm(id)
  for key, rec in pairs(W.installed or {}) do
    for _, i in ipairs(rec.ids or {}) do
      if norm(i) == nid and idx.by_key[key] then return idx.by_key[key] end
    end
  end
  for _, e in ipairs(idx.mods) do if e.id and norm(e.id) == nid then return e end end
  for _, e in ipairs(idx.mods) do if e.folder and norm(e.folder) == nid then return e end end
  for _, e in ipairs(idx.mods) do if norm(e.key:match("@(.*)$")) == nid then return e end end
  local nn = norm(name or id)
  for _, e in ipairs(idx.mods) do if norm(e.title) == nn then return e end end
end

function W.find_by_id(id, name)
  local idx = W.load_index()
  local c = W._find_cache
  if not (c and c.idx == idx and c.n == #idx.mods) then
    c = {idx = idx, n = #idx.mods, map = {}}
    W._find_cache = c
  end
  local ck = tostring(id) .. "\0" .. tostring(name)
  local hit = c.map[ck]
  if hit == nil then
    hit = find_by_id(id, name) or false
    c.map[ck] = hit
  end
  return hit or nil
end

local function unpack_install(entry, path, opts, cb)
  local st = W.state[entry.key]
  st.stage = "install"
  local ok_req, installer = pcall(require, "modloader.installer")
  if not ok_req then
    st.stage, st.err = "error", "installer missing"
    return cb(false, st.err)
  end
  local name = W.safe(entry.folder or (entry.title or entry.key):gsub("%s+", "")) .. ".zip"
  local abs = love.filesystem.getSaveDirectory() .. "/" .. path
  local ok, res, err = pcall(installer.install_zip, abs, name)
  love.filesystem.remove(path)
  if not ok or not res then
    st.stage, st.err = "error", tostring(ok and err or res):sub(1, 60)
    return cb(false, st.err)
  end
  local L = loader()
  local rec = {version = entry.version, folders = {}, ids = {}, versions = {}, time = os.time(), deps = meta_deps(res)}
  for _, m in ipairs(res) do
    rec.folders[#rec.folders + 1] = m.folder
    if m.meta and m.meta.id then rec.ids[#rec.ids + 1] = m.meta.id end
    rec.versions[#rec.versions + 1] = m.meta and m.meta.version and tostring(m.meta.version) or ""
    if opts.enable and L and L.set_enabled then pcall(L.set_enabled, m.folder, true) end
    W.thumbs["installed_icon_" .. m.folder] = nil
  end
  if opts.version then rec.version = opts.index_version or entry.version end
  if L then L._manifests = nil end
  W.installed = W.installed or {}
  W.installed[entry.key] = rec
  W.dep_cache[entry.key] = rec.deps
  W.save_installed()
  W.invalidate_local()
  st.stage = "done"
  st.result = res
  W.changed = true
  if opts.auto_deps then W.install_deps(W.missing_deps(entry)) end
  cb(true, nil, res)
end

local function finish_install(entry, path, opts, cb)
  local st = W.state[entry.key]
  local head = love.filesystem.read(path, 4) or ""
  if head:sub(1, 2) ~= "PK" then
    love.filesystem.remove(path)
    st.stage, st.err = "error", W.loc("Not a zip file")
    return cb(false, st.err)
  end
  st.stage = "install"
  W.later(function()
    if opts.ask_deps or opts.auto_deps then
      local ok_req, installer = pcall(require, "modloader.installer")
      local roots = ok_req and installer.zip_roots and installer.zip_roots(love.filesystem.getSaveDirectory() .. "/" .. path)
      if roots then
        W.dep_cache[entry.key] = meta_deps(roots)
        local missing = {}
        for _, d in ipairs(W.missing_deps(entry, W.dep_cache[entry.key])) do
          if not (opts.accepted and opts.accepted[norm(d.id)]) then missing[#missing + 1] = d end
        end
        if #missing > 0 and opts.auto_deps then
          W.install_deps(missing)
        elseif #missing > 0 then
          st.stage, st.deps, st.path, st.opts, st.cb = "deps", missing, path, opts, cb
          W.changed = true
          return
        end
      end
    end
    unpack_install(entry, path, opts, cb)
  end, 2)
end

function W.deps_answer(entry, go)
  local st = W.state[entry.key]
  if not st or st.stage ~= "deps" then return end
  if st.path then
    if not go then
      love.filesystem.remove(st.path)
      W.state[entry.key] = nil
      W.changed = true
      return
    end
    W.install_deps(st.deps)
    local path, opts, cb = st.path, st.opts, st.cb
    st.deps, st.path, st.opts, st.cb = nil, nil, nil, nil
    st.stage = "install"
    W.changed = true
    W.later(function() unpack_install(entry, path, opts, cb) end, 2)
    return
  end
  local cb = st.cb
  W.state[entry.key] = nil
  W.changed = true
  if not go then return end
  W.install_deps(st.deps)
  local opts = st.opts or {ask_deps = true}
  opts.accepted = opts.accepted or {}
  for _, d in ipairs(st.deps or {}) do opts.accepted[norm(d.id)] = true end
  W.install(entry, opts, cb)
end

W.SOURCE_NAMES = {index = "Mod Index", imm = "imm", github = "GitHub", thunderstore = "Thunderstore", awesome = "GitHub", gamebanana = "GameBanana", nexus = "Nexus Mods"}

function W.sources(entry)
  if type(entry.sources) == "table" and #entry.sources > 0 then return entry.sources end
  return {{kind = entry.extra and "github" or "index", url = entry.repo, dl = entry.url, version = entry.version, broken = entry.broken}}
end

function W.source_names(entry)
  local out, seen = {}, {}
  for _, s in ipairs(W.sources(entry)) do
    local name = W.SOURCE_NAMES[s.kind] or tostring(s.kind)
    if not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  return out
end

function W.download_urls(entry)
  local urls, seen = {}, {}
  local function add(u)
    if u and u ~= "" and not seen[u] then
      seen[u] = true
      urls[#urls + 1] = u
    end
  end
  if not entry.broken then add(entry.url) end
  for _, s in ipairs(W.sources(entry)) do
    if not s.broken and (s.version == nil or s.version == "" or norm_version(s.version) == norm_version(entry.version)) then add(s.dl) end
  end
  return urls
end

function W.link_broken(entry)
  if W.nexus_page(entry) then return false end
  if entry.broken and #W.download_urls(entry) == 0 then return true end
  return false
end

function W.nexus_page(entry)
  if entry.url and entry.url ~= "" then return nil end
  local page
  for _, s in ipairs(W.sources(entry)) do
    if s.dl and s.dl ~= "" then return nil end
    if s.kind == "nexus" and s.url and s.url:match("^https?://") then page = page or s.url end
  end
  return page
end

function W.request_install(entry, cb, anyway)
  cb = cb or function() W.changed = true end
  local nexus = W.nexus_page(entry)
  if nexus then
    love.system.openURL(nexus)
    return
  end
  if W.link_broken(entry) then
    W.state[entry.key] = {stage = "error", err = W.loc("Download link broken")}
    W.changed = true
    return cb(false, W.loc("Download link broken"))
  end
  local cs, reason = W.compat_for(entry)
  if cs == "no" and not anyway then
    W.state[entry.key] = {stage = "warn", reason = reason, cb = cb}
    W.changed = true
    return
  end
  local missing = W.missing_deps(entry)
  if #missing > 0 then
    W.state[entry.key] = {stage = "deps", deps = missing, opts = {ask_deps = true}, cb = cb}
    W.changed = true
    return
  end
  W.install(entry, {ask_deps = true}, cb)
end

function W.warn_answer(entry, yes)
  local st = W.state[entry.key]
  if not (st and st.stage == "warn") then return end
  W.state[entry.key] = nil
  W.changed = true
  if yes then W.request_install(entry, st.cb, true) end
end

function W.mark_broken(entry, url)
  local changed = false
  if url == entry.url and not entry.broken then
    entry.broken = true
    changed = true
  end
  for _, src in ipairs(W.sources(entry)) do
    if src.dl == url and not src.broken then
      src.broken = true
      changed = true
    end
  end
  if changed then W.save_index() end
end

function W.install(entry, opts, cb)
  opts = opts or {}
  cb = cb or function() end
  if W.builtin(entry) then return cb(true) end
  local st = W.state[entry.key]
  if st and (st.stage == "download" or st.stage == "install") then return cb(false, "busy") end
  st = {stage = "download", got = 0, total = -1}
  W.state[entry.key] = st
  W.changed = true
  local urls = opts.urls or W.download_urls(entry)
  local path = W.DIR .. "/dl/" .. W.safe(entry.key) .. ".zip"
  local function try(i)
    local url = urls[i]
    if not url or url == "" then
      st.stage = "error"
      st.err = st.err or (W.link_broken(entry) and W.loc("Download link broken")) or "no download"
      return cb(false, st.err)
    end
    st.got, st.total = 0, -1
    st.cb = cb
    st.job = W.request("download", {url = url, path = path}, function(res)
      st.job = nil
      if st.cancelled then return end
      if res.ok then return finish_install(entry, path, opts, cb) end
      st.err = friendly(res.err, res.code)
      local gone = res.code == 404 or res.code == 410 or tostring(res.err):find("http 404") or tostring(res.err):find("http 410")
      if gone and not opts.urls then W.mark_broken(entry, url) end
      if urls[i + 1] and gone then return try(i + 1) end
      if gone and not opts.urls and W.link_broken(entry) then st.err = W.loc("Download link broken") end
      st.stage = "error"
      W.changed = true
      cb(false, st.err)
    end, function(got, total)
      st.got, st.total = got, total
    end)
  end
  try(1)
end

function W.cancel(entry)
  local st = W.state[entry.key]
  if not st or st.stage ~= "download" then return false end
  st.cancelled = true
  if st.job then
    love.thread.getChannel("workshop_cancel_" .. tostring(st.job)):push(true)
    W.jobs[st.job] = nil
    st.job = nil
  end
  W.state[entry.key] = nil
  W.changed = true
  if st.cb then pcall(st.cb, false, W.loc("Cancelled")) end
  return true
end

function W.uninstall(entry)
  local L = loader()
  local m, rec = W.find_local(entry)
  local folders = rec and rec.folders or (m and {m.folder}) or {}
  for _, f in ipairs(folders) do
    if L and L.remove_mod then pcall(L.remove_mod, f) end
    W.thumbs["installed_icon_" .. f] = nil
  end
  if W.installed then W.installed[entry.key] = nil end
  W.save_installed()
  W.state[entry.key] = nil
  W.invalidate_local()
  W.changed = true
end

function W.forget_folder(folder)
  if not W.installed then W.load_index() end
  for key, rec in pairs(W.installed or {}) do
    for _, f in ipairs(rec.folders or {}) do
      if f == folder then W.installed[key] = nil end
    end
  end
  W.save_installed()
  W.invalidate_local()
end

local function version_urls(entry, version)
  local urls = {}
  if norm_version(version) == norm_version(entry.version) or version == nil or version == "" then
    urls[1] = entry.url
  end
  local o, r = github_repo(entry)
  if o and version and version ~= "" then
    local v = tostring(version)
    local bare = v:gsub("^[vV]", "")
    for _, tag in ipairs({v, "v" .. bare, bare}) do
      local u = "https://github.com/" .. o .. "/" .. r .. "/archive/refs/tags/" .. tag .. ".zip"
      local dup = false
      for _, x in ipairs(urls) do if x == u then dup = true end end
      if not dup then urls[#urls + 1] = u end
    end
  end
  local listed = false
  for _, x in ipairs(urls) do if x == entry.url then listed = true end end
  if not listed and entry.url and entry.url ~= "" then urls[#urls + 1] = entry.url end
  for _, src in ipairs(W.sources(entry)) do
    if src.dl and src.dl ~= "" and (version == nil or version == "" or norm_version(src.version) == norm_version(version)) then
      local dup = false
      for _, x in ipairs(urls) do if x == src.dl then dup = true end end
      if not dup then urls[#urls + 1] = src.dl end
    end
  end
  return urls
end
W.version_urls = version_urls

function W.set_exact(mods)
  local L = loader()
  if not (L and L.status and L.set_enabled) then return end
  local want = {}
  for _, m in ipairs(mods or {}) do want[norm(m.id)] = true; want[norm(m.name)] = true end
  for _, m in ipairs((L.status() or {}).mods or {}) do
    local on = want[norm(m.id or m.folder)] or want[norm(m.folder)] or false
    if m.enabled ~= on then pcall(L.set_enabled, m.folder, on) end
  end
  W.invalidate_local()
end

function W.install_required(mods, cb)
  cb = cb or function() end
  W.load_index()
  local req = {rows = {}, done = false, ok = nil, cb = cb}
  W.required = req
  for i, m in ipairs(mods or {}) do
    req.rows[i] = {id = tostring(m.id or m.name or ""), name = tostring(m.name or m.id or "?"), version = m.version and tostring(m.version) or nil,
      status = W.loc("Waiting"), stage = "wait", progress = 0}
  end
  if W.open_required_ui then W.open_required_ui(req) end
  local function finish(ok, err)
    req.done, req.ok, req.err = true, ok, err
    W.invalidate_local()
    W.later(function()
      if W.close_required_ui then W.close_required_ui(req, ok) end
      if W.required == req then W.required = nil end
      local good, e = pcall(cb, ok, err)
      if not good then print("[workshop] install_required callback: " .. tostring(e)) end
    end, ok and 30 or 90)
  end
  local function step(i)
    if req.cancelled then return finish(false, W.loc("Cancelled")) end
    local row = req.rows[i]
    if not row then return finish(true) end
    req.current = i
    local lm = W.local_mods(true)
    local have = lm.by_id[norm(row.id)] or lm.by_folder[row.id]
    if have and (not row.version or norm_version(have.version) == norm_version(row.version)) then
      local L = loader()
      if L and L.set_enabled and not have.enabled then pcall(L.set_enabled, have.folder, true) end
      row.stage, row.status, row.progress = "done", W.loc("Installed"), 1
      return step(i + 1)
    end
    local entry = W.find_by_id(row.id, row.name)
    if not entry then
      row.stage, row.status = "error", W.loc("Not in the Mods Workshop")
      return finish(false, row.name .. ": " .. W.loc("Not in the Mods Workshop"))
    end
    row.stage, row.status = "download", W.loc("Downloading")
    row.entry = entry
    local urls = version_urls(entry, row.version)
    local touched = false
    local function attempt(k)
      local url = urls[k]
      if not url then
        if touched and not have then W.uninstall(entry) end
        row.stage = "error"
        row.status = W.loc("Version not available")
        return finish(false, row.name .. (row.version and (" " .. row.version) or "") .. ": " .. W.loc("Version not available"))
      end
      row.stage, row.status = "download", W.loc("Downloading")
      W.install(entry, {urls = {url}, version = row.version, index_version = entry.version, enable = true}, function(ok, err, res)
        if not ok and req.cancelled then
          row.stage, row.status = "error", W.loc("Cancelled")
          return finish(false, W.loc("Cancelled"))
        end
        if not ok then
          if err == "404" then return attempt(k + 1) end
          row.stage = "error"
          row.status = tostring(err)
          return finish(false, row.name .. ": " .. tostring(err))
        end
        touched = true
        local got_version, got_id
        for _, r in ipairs(res or {}) do
          if r.meta and (not got_id or norm(r.meta.id) == norm(row.id)) then got_id, got_version = r.meta.id, r.meta.version end
        end
        if row.version and got_version and norm_version(got_version) ~= norm_version(row.version) then
          return attempt(k + 1)
        end
        row.stage, row.status, row.progress = "done", W.loc("Done"), 1
        step(i + 1)
      end)
    end
    attempt(1)
  end
  W.later(function() step(1) end, 3)
end

function W.cancel_required()
  local req = W.required
  if not req or req.done or req.cancelled then return false end
  req.cancelled = true
  local row = req.rows[req.current or 0]
  if row and row.entry then W.cancel(row.entry) end
  W.changed = true
  return true
end

function W.row_progress(row)
  if row.stage == "download" and row.entry then
    local st = W.state[row.entry.key]
    if st then
      if st.stage == "install" then row.status = W.loc("Installing") end
      if st.total and st.total > 0 then return math.min(1, st.got / st.total) end
      return -1
    end
  end
  return row.progress or 0
end
