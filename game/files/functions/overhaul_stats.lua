Overhaul = Overhaul or {}
Overhaul.stats = Overhaul.stats or {}
local S = Overhaul.stats
S.handlers = S.handlers or {}

S.MP_MODES = {"nemesis", "faceoff", "ranked", "ascension", "race", "br", "teams", "raid", "swap"}
S.HISTORY_MAX = 12

local function num(v) return tonumber(v) or 0 end

local function profile()
  if not (G and G.SETTINGS and G.PROFILES) then return nil end
  return G.PROFILES[G.SETTINGS.profile]
end

local function new_mode()
  return {played = 0, wins = 0, losses = 0, draws = 0, cur = 0, best = 0, pvp_w = 0, pvp_l = 0, best_ante = 0, best_hand = 0}
end
S.new_mode = new_mode

local function fill(t, defaults)
  for k, v in pairs(defaults) do
    if type(v) == 'number' then t[k] = num(t[k]) elseif type(t[k]) ~= type(v) then t[k] = v end
  end
  return t
end

local function migrate_mp(p)
  local old = type(p.progression) == 'table' and p.progression or {}
  local mpp = type(p.mp_progression) == 'table' and p.mp_progression or {}
  local played = math.max(num(old.mp_total_matches), num(mpp.matches))
  local wins = math.min(played, math.max(num(old.mp_match_wins), num(mpp.wins)))
  return {legacy = {played = played, wins = wins}, modes = {}, jokers = {}, decks = {}, history = {}}
end

function S.data(p)
  p = p or profile()
  if not p then return nil end
  local d = p.ostats
  if type(d) ~= 'table' then d = {}; p.ostats = d end
  d.v = 1
  d.time, d.run_time = num(d.time), num(d.run_time)
  if type(d.counters) ~= 'table' then d.counters = {} end
  if type(d.sp) ~= 'table' then d.sp = {} end
  fill(d.sp, {fastest = 0, fastest_deck = '', best_ante = 0, runs = 0, history = {}, deck_ante = {}})
  if type(d.mp) ~= 'table' then d.mp = migrate_mp(p) end
  fill(d.mp, {cur = 0, best = 0, pvp_w = 0, pvp_l = 0, modes = {}, jokers = {}, decks = {}, history = {}, legacy = {}})
  d.mp.legacy.played, d.mp.legacy.wins = num(d.mp.legacy.played), num(d.mp.legacy.wins)
  for _, m in pairs(d.mp.modes) do if type(m) == 'table' then fill(m, new_mode()) end end
  return d
end

function S.listen(event, fn)
  if type(fn) ~= 'function' then return end
  S.handlers[event] = S.handlers[event] or {}
  table.insert(S.handlers[event], fn)
end

local function fire(event, data)
  for _, key in ipairs({event, '*'}) do
    for _, fn in ipairs(S.handlers[key] or {}) do
      local ok, err = pcall(fn, data, event)
      if not ok then print("[OSTATS] listener " .. tostring(event) .. " failed: " .. tostring(err)) end
    end
  end
end

function S.count(key, n)
  local d = S.data()
  if not (d and key) then return 0 end
  d.counters[key] = num(d.counters[key]) + (n or 1)
  return d.counters[key]
end

function S.get(key)
  local d = S.data()
  return d and num(d.counters[key]) or 0
end

function S.set_max(key, v)
  local d = S.data()
  if not (d and key and tonumber(v)) then return 0 end
  if tonumber(v) > num(d.counters[key]) then d.counters[key] = tonumber(v) end
  return d.counters[key]
end

local RECORD = {}

function S.on(event, data)
  data = data or {}
  local rec = RECORD[event]
  if rec then
    local ok, err = pcall(rec, data)
    if not ok then print("[OSTATS] " .. tostring(event) .. " failed: " .. tostring(err)) end
  elseif type(event) == 'string' and not data.no_count then
    S.count(event, tonumber(data.n) or 1)
  end
  fire(event, data)
end

local function deck_key()
  local b = G.GAME and G.GAME.selected_back
  local c = b and b.effect and b.effect.center
  return c and c.key or nil
end

local function run_kind(g)
  if g.daily then return 'daily' end
  if g.challenge then return 'challenge' end
  if g.seeded then return 'seeded' end
  if g.custom_run or g.custom_rules then return 'custom' end
  return 'normal'
end

local function push_history(list, entry)
  table.insert(list, 1, entry)
  while #list > S.HISTORY_MAX do table.remove(list) end
end

function S.run_time()
  return G and G.GAME and num(G.GAME.ostats_t) or 0
end

RECORD.run_end = function(data)
  local g = G and G.GAME
  if not g or g.multiplayer or g.modded_run then return end
  local won = data.won and true or false
  if g.ostats_done or (won and g.ostats_won) then return end
  if won then g.ostats_won = true elseif g.ostats_won then return end
  g.ostats_done = not won and true or nil
  local d = S.data()
  if not d then return end
  local ante = g.round_resets and num(g.round_resets.ante) or 0
  local t = num(g.ostats_t)
  local key = deck_key()
  d.sp.runs = d.sp.runs + 1
  if ante > d.sp.best_ante then d.sp.best_ante = ante end
  if key then
    d.sp.deck_ante[key] = math.max(num(d.sp.deck_ante[key]), ante)
  end
  local kind = run_kind(g)
  if won and kind ~= 'seeded' and t > 0 and (d.sp.fastest <= 0 or t < d.sp.fastest) then
    d.sp.fastest, d.sp.fastest_deck = t, key or ''
  end
  local best = g.round_scores and g.round_scores.hand and num(g.round_scores.hand.amt) or 0
  push_history(d.sp.history, {won = won, deck = key, stake = num(g.stake), ante = ante, t = math.floor(t), kind = kind, best = best, at = os.time()})
  data.time, data.ante, data.deck, data.kind = t, ante, key, kind
end

RECORD.mp_match_end = function(data)
  local d = S.data()
  if not d then return end
  local result = data.result == 'win' and 'win' or data.result == 'draw' and 'draw' or 'lose'
  local now = os.time()
  local last = d.mp._last
  if type(last) == 'table' and last.result == result and math.abs(now - num(last.at)) < 10 then
    data.duplicate = true
    return
  end
  d.mp._last = {result = result, at = now}
  local mode = tostring(data.mode or 'nemesis')
  local m = d.mp.modes[mode]
  if type(m) ~= 'table' then m = new_mode(); d.mp.modes[mode] = m end
  m.played = m.played + 1
  if result == 'win' then
    m.wins, m.cur = m.wins + 1, m.cur + 1
    d.mp.cur = d.mp.cur + 1
  elseif result == 'lose' then
    m.losses, m.cur = m.losses + 1, 0
    d.mp.cur = 0
  else
    m.draws = m.draws + 1
  end
  m.best = math.max(m.best, m.cur)
  d.mp.best = math.max(d.mp.best, d.mp.cur)
  local pw, pl = num(data.pvp_wins), num(data.pvp_losses)
  m.pvp_w, m.pvp_l = m.pvp_w + pw, m.pvp_l + pl
  d.mp.pvp_w, d.mp.pvp_l = d.mp.pvp_w + pw, d.mp.pvp_l + pl
  local ante = num(data.ante)
  if ante <= 0 and G and G.GAME and G.GAME.round_resets then ante = num(G.GAME.round_resets.ante) end
  m.best_ante = math.max(m.best_ante, ante)
  local best = num(data.best_hand)
  if best <= 0 and G and G.GAME and G.GAME.round_scores and G.GAME.round_scores.hand then best = num(G.GAME.round_scores.hand.amt) end
  m.best_hand = math.max(m.best_hand, best)
  if G and G.jokers and G.jokers.cards then
    for _, c in ipairs(G.jokers.cards) do
      local k = c.config and c.config.center_key
      if k and c.ability and c.ability.set == 'Joker' then
        local j = d.mp.jokers[k]
        if type(j) ~= 'table' then j = {count = 0, wins = 0}; d.mp.jokers[k] = j end
        j.count = num(j.count) + 1
        if result == 'win' then j.wins = num(j.wins) + 1 end
      end
    end
  end
  local key = G and G.GAME and deck_key()
  if key then
    local dk = d.mp.decks[key]
    if type(dk) ~= 'table' then dk = {count = 0, wins = 0}; d.mp.decks[key] = dk end
    dk.count = num(dk.count) + 1
    if result == 'win' then dk.wins = num(dk.wins) + 1 end
  end
  push_history(d.mp.history, {mode = mode, result = result, opp = data.opp and tostring(data.opp):sub(1, 24) or nil,
    ante = ante, pvp_w = pw, pvp_l = pl, lives = tonumber(data.lives), place = tonumber(data.placement), at = now})
  data.mode, data.result, data.ante, data.streak = mode, result, ante, d.mp.cur
  data.deck = key
end

function S.mp_totals(d)
  d = d or S.data()
  local t = {played = 0, wins = 0, losses = 0, draws = 0}
  if not d then return t end
  for _, m in pairs(d.mp.modes) do
    if type(m) == 'table' then
      t.played, t.wins, t.losses, t.draws = t.played + m.played, t.wins + m.wins, t.losses + m.losses, t.draws + m.draws
    end
  end
  t.played = t.played + d.mp.legacy.played
  t.wins = t.wins + d.mp.legacy.wins
  t.losses = t.losses + math.max(0, d.mp.legacy.played - d.mp.legacy.wins)
  return t
end

function S.sp_totals(p)
  p = p or profile()
  local t = {runs = 0, wins = 0, losses = 0}
  if not p then return t end
  local cs = p.career_stats or {}
  t.wins, t.losses = num(cs.c_wins), num(cs.c_losses)
  for _, u in pairs(p.deck_usage or {}) do t.runs = t.runs + num(u.count) end
  t.runs = math.max(t.runs, t.wins + t.losses)
  return t
end

function S.tick(dt)
  if not (dt and dt > 0 and dt < 1) then return end
  local p = profile()
  if not p then return end
  local d = p.ostats
  if type(d) ~= 'table' or type(d.sp) ~= 'table' then d = S.data(p) end
  d.time = num(d.time) + dt
  if G.STAGE == G.STAGES.RUN and G.GAME then
    d.run_time = num(d.run_time) + dt
    if not G.SETTINGS.paused and not G.GAME.ostats_done then G.GAME.ostats_t = num(G.GAME.ostats_t) + dt end
  end
end

function S.format_time(sec)
  sec = math.floor(num(sec))
  local h, m = math.floor(sec / 3600), math.floor(sec % 3600 / 60)
  if h > 0 then return string.format("%dh %02dm", h, m) end
  return string.format("%dm %02ds", m, sec % 60)
end

function S.rate(w, n)
  if num(n) <= 0 then return "-" end
  return string.format("%d%%", math.floor(100 * num(w) / num(n) + 0.5))
end

if type(win_game) == 'function' and not S._win_hooked then
  S._win_hooked = true
  local orig = win_game
  win_game = function(...)
    pcall(S.on, 'run_end', {won = true})
    return orig(...)
  end
end

if Game and type(Game.update_game_over) == 'function' and not S._loss_hooked then
  S._loss_hooked = true
  local orig = Game.update_game_over
  Game.update_game_over = function(self, dt, ...)
    if not G.STATE_COMPLETE and G.GAME and not G.GAME.ostats_done and not G.GAME.ostats_won then
      pcall(S.on, 'run_end', {won = false})
    end
    return orig(self, dt, ...)
  end
end

if AchievementManager and AchievementManager.bridge then AchievementManager.bridge() end

return S
