ProgressEvents = ProgressEvents or {}
local PE = ProgressEvents

PE.listeners = PE.listeners or {}
PE.installed = PE.installed or false

PE.LOC = PE.LOC or {}

function PE.register_loc(t)
  for lang, entries in pairs(t or {}) do
    PE.LOC[lang] = PE.LOC[lang] or {}
    for k, v in pairs(entries) do PE.LOC[lang][k] = v end
  end
  if mod_loc_register then mod_loc_register(t) end
end

function PE.loc(s)
  if s == nil then return "" end
  local lang = G and G.SETTINGS and G.SETTINGS.language or "en-us"
  if lang == "es_ES" or lang == "es_419" then lang = "es" end
  local own = PE.LOC[lang] and PE.LOC[lang][s]
  if own then return own end
  return mod_loc and mod_loc(s) or s
end

function PE.on(name, fn)
  if type(name) ~= "string" or type(fn) ~= "function" then return end
  PE.listeners[name] = PE.listeners[name] or {}
  table.insert(PE.listeners[name], fn)
end

function PE.muted()
  if rawget(_G, "QuestManager") == nil then return true end
  local pb = rawget(_G, "bom_playback")
  if pb and type(pb.active) == "function" then
    local ok, v = pcall(pb.active)
    if ok and v then return true end
  end
  return false
end

function PE.in_clean_run()
  local g = G and G.GAME
  if not g then return false end
  if g.modded_run or g.challenge or not Progress.allowed() then return false end
  if g.seeded and not g.daily and not g.multiplayer then return false end
  return true
end

function PE.emit(name, data)
  if PE.muted() then return end
  data = data or {}
  for _, fn in ipairs(PE.listeners[name] or {}) do
    local ok, err = pcall(fn, data, name)
    if not ok then print("[PROGRESS EVENTS] " .. tostring(name) .. ": " .. tostring(err)) end
  end
  for _, fn in ipairs(PE.listeners["*"] or {}) do
    pcall(fn, data, name)
  end
end

local function wrap_global(name, after)
  local orig = rawget(_G, name)
  if type(orig) ~= "function" then return false end
  _G[name] = function(...)
    local pre = after.before and after.before(...)
    local r = {orig(...)}
    pcall(after.after, pre, ...)
    return unpack(r)
  end
  return true
end

local function wrap_method(tbl, key, before, after)
  if type(tbl) ~= "table" or type(tbl[key]) ~= "function" then return false end
  local orig = tbl[key]
  tbl[key] = function(...)
    local pre
    if before then
      local ok, v = pcall(before, ...)
      if ok then pre = v end
    end
    local r = {orig(...)}
    if after then pcall(after, pre, ...) end
    return unpack(r)
  end
  return true
end
PE.wrap_method = wrap_method

local function center_of(card)
  return card and card.config and card.config.center
end

function PE.install()
  if PE.installed then return end
  PE.installed = true

  wrap_method(Card, "use_consumeable", nil, function(_, self)
    local c = center_of(self)
    if c and c.set ~= "Voucher" and PE.in_clean_run() then
      PE.emit("consumable_used", {set = c.set, key = c.key})
    end
  end)

  wrap_method(Card, "redeem", nil, function(_, self)
    local c = center_of(self)
    if c and PE.in_clean_run() then PE.emit("voucher_redeemed", {key = c.key}) end
  end)

  wrap_method(Card, "open", nil, function(_, self)
    local c = center_of(self)
    if c and c.set == "Booster" and PE.in_clean_run() then
      PE.emit("pack_opened", {key = c.key, kind = c.kind})
    end
  end)

  local function owned(card)
    local a = card and card.area
    return a ~= nil and (a == G.hand or a == G.deck or a == G.jokers or a == G.consumeables or a == G.play)
  end

  wrap_method(Card, "set_edition", nil, function(_, self, edition)
    if edition and self.edition and owned(self) and PE.in_clean_run() and G.STAGE == G.STAGES.RUN then
      PE.emit("edition_obtained", {edition = self.edition.type, joker = self.ability and self.ability.set == "Joker"})
    end
  end)

  wrap_method(Card, "set_ability", function(self, center, initial)
    return self and self.config and self.config.center and self.config.center.key
  end, function(old, self, center, initial)
    if initial or not (center and center.set == "Enhanced" and self.playing_card) then return end
    if old == center.key or not owned(self) or not PE.in_clean_run() then return end
    if G.STAGE ~= G.STAGES.RUN then return end
    PE.emit("card_enhanced", {key = center.key})
  end)

  wrap_method(Card, "add_to_deck", function(self, from_debuff)
    return self and not from_debuff and not self.added_to_deck
  end, function(fresh, self)
    if not fresh or not PE.in_clean_run() or G.STAGE ~= G.STAGES.RUN then return end
    local c = center_of(self)
    if not c then return end
    if c.set == "Joker" then
      PE.emit("joker_obtained", {key = c.key, rarity = c.rarity})
      if self.edition then PE.emit("edition_obtained", {edition = self.edition.type, joker = true}) end
    end
  end)

  wrap_method(G.FUNCS, "cash_out", nil, function()
    if PE.in_clean_run() then PE.emit("blind_won", {ante = G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante}) end
  end)

  wrap_method(G.FUNCS, "discard_cards_from_highlighted", function(e, hook)
    if hook or not (G.hand and G.hand.highlighted) then return 0 end
    return #G.hand.highlighted
  end, function(n)
    if (n or 0) > 0 and PE.in_clean_run() then PE.emit("cards_discarded", {amount = n}) end
  end)

  wrap_method(Game, "start_run", nil, function(_, self, args)
    args = args or {}
    if args.savetext then return end
    if G and G.E_MANAGER and Event then
      G.E_MANAGER:add_event(Event({trigger = 'immediate', blocking = false, blockable = false, func = function()
        if PE.in_clean_run() then
          local b = G.GAME and G.GAME.selected_back
          PE.emit("run_start", {stake = G.GAME and G.GAME.stake, deck = b and b.effect and b.effect.center and b.effect.center.key})
        end
        return true
      end}))
    end
  end)

  wrap_global("mp_record_match", {after = function(_, won, mode)
    PE.emit("mp_match", {won = won and true or false, mode = mode or (G and G.GAME and G.GAME.mp_mode)})
  end})

  if ShopManager then
    wrap_method(ShopManager, "spend_balacoin", function(amount)
      return ShopManager.get_balance and ShopManager.get_balance() or 0
    end, function(before, amount)
      local now = ShopManager.get_balance and ShopManager.get_balance() or 0
      if before and now < before then PE.emit("casino_purchase", {amount = before - now}) end
    end)
  end


  local MGt = rawget(_G, "Minigames")
  if type(MGt) == "table" then
    wrap_method(MGt, "record", nil, function(_, key, score)
      PE.emit("minigame_played", {key = key, score = score})
    end)
  end

  local store = package.loaded["functions/forge/forge_store"]
  if type(store) == "table" then
    wrap_method(store, "put", function(c)
      if type(c) ~= "table" or not c.id or not store.get then return true end
      local ok, old = pcall(store.get, c.id)
      return not (ok and old)
    end, function(is_new)
      if is_new then PE.emit("forge_created", {}) end
    end)
  end

  if DeckCreatorPersistence then
    wrap_method(DeckCreatorPersistence, "saveAllDecks", nil, function() PE.emit("deck_saved", {}) end)
  end

  wrap_method(G.FUNCS, "bo_bp_play", nil, function() PE.emit("boss_practice", {}) end)
  wrap_method(G.FUNCS, "daily_start_challenge", nil, function() PE.emit("daily_started", {}) end)
  wrap_method(G.FUNCS, "bo_hist_watch", nil, function() PE.emit("replay_watched", {}) end)
  wrap_method(G.FUNCS, "speedrun_board_watch", nil, function() PE.emit("replay_watched", {}) end)

  if AchievementManager then
    wrap_method(AchievementManager, "unlock_achievement", function(id)
      return AchievementManager.is_unlocked and AchievementManager.is_unlocked(id)
    end, function(was, id)
      if not was and AchievementManager.is_unlocked and AchievementManager.is_unlocked(id) then
        PE.emit("achievement_unlocked", {key = id})
      end
    end)
  end
end

if type(set_main_menu_UI) == "function" and not PE.menu_wrapped then
  PE.menu_wrapped = true
  local base = set_main_menu_UI
  set_main_menu_UI = function(...)
    local r = base(...)
    pcall(PE.install)
    return r
  end
end

return PE
