SpeedrunOnline = SpeedrunOnline or {}
local SO = SpeedrunOnline
local SR = Speedrun

SO.board = SO.board or {state = 'idle', rows = {}, total = 0}
SO.PERMANENT = {too_fast = true, time_mismatch = true, weekly_seed = true, splits = true, run_data = true, replay = true}

local function core() return rawget(_G, 'bom_core') end

function SO.connected()
  local c = core()
  return c and c.is_connected and c.is_connected() or false
end

function SO.send(msg)
  local c = core()
  if not (c and SO.connected()) then return false end
  msg.pkey = msg.pkey or (c.player_key and c.player_key()) or nil
  local p = G.PROFILES and G.SETTINGS and G.PROFILES[G.SETTINGS.profile]
  if msg.type == 'speedrun_submit' and not SO.no_name and p and type(p.name) == 'string' and p.name ~= '' then msg.name = msg.name or p.name end
  return c.send(msg)
end

local function find_run(id)
  for _, r in ipairs(SR.load().runs) do if r.id == id then return r end end
end

local function round2(v) return math.floor(v * 100 + 0.5) / 100 end

function SO.payload(r)
  local cat = SR.cat(r.cat)
  if not (cat and r.id and type(r.time) == 'number') then return nil end
  local list, blinds, hands = {}, {}, {}
  for a = 1, cat.target do
    local s = r.splits and r.splits[a]
    local b = r.blinds and r.blinds[a]
    local h = r.hands and r.hands[a]
    if type(s) ~= 'number' or type(b) ~= 'number' or type(h) ~= 'number' then return nil end
    list[a], blinds[a], hands[a] = round2(s), math.floor(b), math.floor(h)
  end
  list[cat.target] = round2(r.time)
  return {id = r.id, cat = r.cat, deck = r.deck, stake = r.stake, seed_type = r.seed_type, seed = tostring(r.seed or ''), time = round2(r.time),
    splits = list, blinds = blinds, hands = hands, rp = SO.digest(r.rp, cat.target), v = r.v or 1}
end

function SO.digest(rp, target)
  if type(rp) ~= 'table' or type(rp.n) ~= 'number' then return nil end
  local out = {n = math.floor(rp.n), pl = {}, bs = {}, fb = {}, lp = {}}
  for a = 1, target do
    for _, k in ipairs({'pl', 'bs', 'fb', 'lp'}) do
      local v = type(rp[k]) == 'table' and rp[k][a]
      if type(v) ~= 'number' then return nil end
      out[k][a] = (k == 'pl' or k == 'bs') and math.floor(v) or round2(v)
    end
  end
  return out
end

SO.RP_PERMANENT = {not_best = true, replay_data = true, too_big = true}

function SO.put_replay(r)
  local W = rawget(_G, 'SpeedrunWatch')
  if not (W and W.pack and r and r.id and r.sprp and SO.connected()) then return false end
  local z, n = W.pack(r.sprp)
  if not z then
    if n == 'too_big' then r.rp_up = 'too_big' end
    return false
  end
  r.rp_up = 'sending'
  return SO.send({type = 'speedrun_replay_put', id = r.id, z = z, n = n})
end

function SR.flush()
  if not SO.connected() then return end
  local d = SR.load()
  local keep = {}
  for _, id in ipairs(d.pending or {}) do
    local r = find_run(id)
    local p = r and SO.payload(r)
    if p then
      keep[#keep + 1] = id
      SO.send({type = 'speedrun_submit', run = p})
    elseif r then
      r.online, r.online_reason = 'refused', 'splits'
    end
  end
  d.pending = keep
  local sent = 0
  for _, r in ipairs(d.runs) do
    if sent >= 2 then break end
    if r.online == 'sent' and r.sprp and (r.rp_up == nil or r.rp_up == 'sending') then
      if SO.put_replay(r) then sent = sent + 1 end
    end
  end
  SR.save()
end

function SO.on_replay_saved(d)
  local r = d and find_run(d.id)
  if not r then return true end
  if d.ok then
    r.rp_up = 'sent'
  elseif SO.RP_PERMANENT[d.reason] then
    r.rp_up = 'refused'
  else
    r.rp_up = nil
  end
  SR.save()
  return true
end

function SO.watch_online(r)
  local W = rawget(_G, 'SpeedrunWatch')
  return W and W.fetch and W.fetch(r) or false
end

function SO.filter_msg()
  local f = SpeedrunBoard and SpeedrunBoard.f or {cat = 'any'}
  return {type = 'speedrun_board', cat = f.cat, deck = f.deck or 'all', stake = f.stake or 0, seed_type = f.seed or 'all', limit = 50}
end

local function refresh_ui()
  if G.OVERLAY_MENU and UIK._win and UIK._win.id == 'speedrun_board' and UIK._last_tab.speedrun_board == 'online' then UIK.refresh() end
end

function SO.request()
  local msg = SO.filter_msg()
  SO.board.want = msg
  if SO.connected() then
    SO.board.state = 'loading'
    SR.flush()
    SO.send(msg)
    return
  end
  local c = core()
  if not (c and c.connect and rawget(_G, 'AndroidWS')) then
    SO.board.state = 'offline'
    return
  end
  SO.board.state = 'loading'
  c.connect(function()
    SR.flush()
    SO.send(SO.board.want or SO.filter_msg())
  end, {silent = true, on_fail = function()
    SO.board.state = 'offline'
    refresh_ui()
  end})
end

function SO.on_board(d)
  local w = SO.board.want
  if w and (d.cat ~= w.cat or (d.deck or 'all') ~= w.deck or (d.stake or 0) ~= w.stake or (d.seed_type or 'all') ~= w.seed_type) then return true end
  SO.board.rows = type(d.rows) == 'table' and d.rows or {}
  SO.board.total = tonumber(d.total) or #SO.board.rows
  SO.board.my_rank = tonumber(d.my_rank)
  SO.board.state = d.error and 'offline' or 'ready'
  refresh_ui()
  return true
end

function SO.on_submitted(d)
  local data = SR.load()
  local keep = {}
  for _, id in ipairs(data.pending or {}) do
    if id == d.id then
      local r = find_run(id)
      if d.ok then
        if r then
          r.online, r.online_rank = 'sent', tonumber(d.rank)
          if r.sprp and r.rp_up == nil then SO.put_replay(r) end
        end
      elseif SO.PERMANENT[d.reason] then
        if r then r.online, r.online_reason = 'refused', d.reason end
      else
        keep[#keep + 1] = id
      end
    else
      keep[#keep + 1] = id
    end
  end
  data.pending = keep
  SR.save()
  return true
end

function SO.on_name_refused(d)
  if d['for'] ~= 'speedrun_submit' then return false end
  if not SO.no_name then
    SO.no_name = true
    pcall(SR.flush)
  end
  return true
end

local ev = rawget(_G, 'bom_events')
if ev and ev.register then
  ev.register('speedrun_board', SO.on_board)
  ev.register('speedrun_submitted', SO.on_submitted)
  ev.register('speedrun_replay_saved', SO.on_replay_saved)
  ev.register('name_refused', SO.on_name_refused)
end

return SO
