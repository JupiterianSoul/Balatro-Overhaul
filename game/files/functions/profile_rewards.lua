
local MAX_ITERATIONS = 1000


local DECK_UNLOCKS = {
  {id = "collab_TW",  suit = "Spades",   name = "The Witcher",       description = "Win 3 runs (Monster Slayer)",              unlock_type = "wins",   unlock_value = 3},
  {id = "collab_CYP", suit = "Spades",   name = "Cyberpunk 2077",    description = "Earn $300+ in a single run",               unlock_type = "money",  unlock_value = 300},
  {id = "collab_SK",  suit = "Spades",   name = "Shovel Knight",     description = "Win with Black Deck (dig deep)",           unlock_type = "win_deck", unlock_value = "b_black"},
  {id = "collab_DS",  suit = "Spades",   name = "Don't Starve",      description = "Win a run with $0 remaining",              unlock_type = "win_broke", unlock_value = 1},
  {id = "collab_AC",  suit = "Spades",   name = "Assassin's Creed",  description = "Win 5 runs in a row (streak)",             unlock_type = "streak", unlock_value = 5},
  {id = "collab_STP", suit = "Spades",   name = "Slay the Princess", description = "Buy from shop in TAVERN",                  unlock_type = "shop",   price = 1500},

  {id = "collab_AU",   suit = "Hearts",  name = "Among Us",          description = "Win without using any Joker abilities",     unlock_type = "win_no_joker", unlock_value = 1},
  {id = "collab_TBoI", suit = "Hearts",  name = "The Binding of Isaac", description = "Use 20 consumables in one run",          unlock_type = "consumables", unlock_value = 20},
  {id = "collab_CL",   suit = "Hearts",  name = "Cult of the Lamb",  description = "Reach Level 15",                           unlock_type = "level",  unlock_value = 15},
  {id = "collab_D2",   suit = "Hearts",  name = "Divinity: Original Sin 2", description = "Win on Gold Stake",                 unlock_type = "stake",  unlock_value = 8},
  {id = "collab_CR",   suit = "Hearts",  name = "Critical Role",     description = "Score 100,000+ chips in a single hand",    unlock_type = "hand_score", unlock_value = 100000},
  {id = "collab_BUG",  suit = "Hearts",  name = "Bugsnax",           description = "Discover 100 items in Collection",         unlock_type = "discover", unlock_value = 100},

  {id = "collab_VS",  suit = "Clubs",    name = "Vampire Survivors",  description = "Win 10 runs (survive the night)",         unlock_type = "wins",   unlock_value = 10},
  {id = "collab_STS", suit = "Clubs",    name = "Slay the Spire",     description = "Win with Red Deck and Blue Deck",         unlock_type = "win_decks", unlock_value = {"b_red","b_blue"}},
  {id = "collab_PC",  suit = "Clubs",    name = "Potion Craft",       description = "Use 50 Tarot cards total",                unlock_type = "career_stat", stat = "c_tarots_bought", unlock_value = 50},
  {id = "collab_WF",  suit = "Clubs",    name = "Warframe",           description = "Reach Level 30 (Mastery)",                unlock_type = "level",  unlock_value = 30},
  {id = "collab_FO",  suit = "Clubs",    name = "Vault-Tec",          description = "Earn $500+ in a single run (hoard caps)",  unlock_type = "money",  unlock_value = 500},
  {id = "collab_DBD", suit = "Clubs",    name = "Dead by Daylight",   description = "Win on Ante 10+ (escape the trial)",      unlock_type = "high_ante", unlock_value = 10},

  {id = "collab_DTD", suit = "Diamonds", name = "Dave the Diver",     description = "Win with Yellow Deck (dive for gold)",    unlock_type = "win_deck", unlock_value = "b_yellow"},
  {id = "collab_SV",  suit = "Diamonds", name = "Stardew Valley",     description = "Earn $200+ in a single run (farming)",    unlock_type = "money",  unlock_value = 200},
  {id = "collab_EG",  suit = "Diamonds", name = "Enter the Gungeon",  description = "Win 5 runs (clear the dungeon)",          unlock_type = "wins",   unlock_value = 5},
  {id = "collab_XR",  suit = "Diamonds", name = "1000xRESIST",        description = "Reach Ante 12 in any run",                unlock_type = "high_ante", unlock_value = 12},
  {id = "collab_C7",  suit = "Diamonds", name = "Civilization VII",   description = "Play 1000 hands total (build empire)",    unlock_type = "career_stat", stat = "c_hands_played", unlock_value = 1000},
  {id = "collab_R",   suit = "Diamonds", name = "Rust",               description = "Buy from shop in TAVERN",                 unlock_type = "shop",   price = 2000},
}



ProfileRewardsManager = ProfileRewardsManager or {}
ProfileRewardsManager.initialized = false

function ProfileRewardsManager.init()
  if ProfileRewardsManager.initialized then return true end
  if not G then return false end
  if not G.PROFILES then return false end
  if not G.SETTINGS then return false end
  if not G.SETTINGS.profile then return false end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile then return false end

  if not profile.progression then profile.progression = {} end

  if not profile.progression.unlocked_decks then
    profile.progression.unlocked_decks = {}
  end
  pcall(ProfileRewardsManager.unlock_all_decks, profile)

  if not profile.progression.equipped_icon then
    profile.progression.equipped_icon = nil
  end
  if not profile.progression.unlocked_icons then
    profile.progression.unlocked_icons = {}
  end

  ProfileRewardsManager.initialized = true
  print("[PROFILE_REWARDS] Initialized for profile " .. tostring(G.SETTINGS.profile))
  return true
end

function ProfileRewardsManager.reload_for_profile()
  ProfileRewardsManager.initialized = false
  ProfileRewardsManager.init()
end


function ProfileRewardsManager.is_deck_unlocked(collab_id)
  if not ProfileRewardsManager.init() then return false end
  if collab_id == "default" then return true end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression or not profile.progression.unlocked_decks then return false end

  for _, id in ipairs(profile.progression.unlocked_decks) do
    if id == collab_id then return true end
  end
  return false
end

function ProfileRewardsManager.unlock_deck(collab_id)
  if G and G.GAME and G.GAME.modded_run then return false end
  if not ProfileRewardsManager.init() then return false end
  if ProfileRewardsManager.is_deck_unlocked(collab_id) then return false end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression then return false end

  table.insert(profile.progression.unlocked_decks, collab_id)
  pcall(function() G:save_settings() end)
  print("[PROFILE_REWARDS] Deck unlocked: " .. tostring(collab_id))
  return true
end

function ProfileRewardsManager.unlock_all_decks(profile)
  local list = profile.progression.unlocked_decks
  local have = {}
  for _, id in ipairs(list) do have[id] = true end
  local function add(id)
    if type(id) == "string" and id ~= "default" and not have[id] then
      have[id] = true
      list[#list + 1] = id
    end
  end
  for _, d in ipairs(DECK_UNLOCKS) do add(d.id) end
  for _, opts in pairs(G.COLLABS and G.COLLABS.options or {}) do
    for _, id in ipairs(opts) do add(id) end
  end
end

function ProfileRewardsManager.get_deck_unlock_info(collab_id)
  for _, deck in ipairs(DECK_UNLOCKS) do
    if deck.id == collab_id then return deck end
  end
  return nil
end

function ProfileRewardsManager.get_unlocked_deck_count()
  if not ProfileRewardsManager.init() then return 0 end
  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression or not profile.progression.unlocked_decks then return 0 end
  return #profile.progression.unlocked_decks
end

function ProfileRewardsManager.check_deck_unlocks()
  if G and G.GAME and G.GAME.modded_run then return end
  if not ProfileRewardsManager.init() then return end
  if not G.PROFILES or not G.SETTINGS or not G.SETTINGS.profile then return end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression then return end

  local level = profile.progression.level or 0
  local wins = profile.progression.total_wins or (profile.career_stats and profile.career_stats.c_wins or 0)
  local highest_stake = profile.progression.highest_stake_beaten or 0
  local highest_ante = 0
  pcall(function()
    if profile.high_scores and profile.high_scores.furthest_ante then
      highest_ante = profile.high_scores.furthest_ante.amt or 0
    end
  end)

  for _, deck in ipairs(DECK_UNLOCKS) do
    if not ProfileRewardsManager.is_deck_unlocked(deck.id) then
      local should_unlock = false

      if deck.unlock_type == "wins" and wins >= deck.unlock_value then
        should_unlock = true
      elseif deck.unlock_type == "level" and level >= deck.unlock_value then
        should_unlock = true
      elseif deck.unlock_type == "stake" and highest_stake >= deck.unlock_value then
        should_unlock = true
      elseif deck.unlock_type == "discover" then
        local discovered = 0
        pcall(function()
          if G.DISCOVER_TALLIES then
            for _, tally in pairs(G.DISCOVER_TALLIES) do
              discovered = discovered + (tally.tally or 0)
            end
          end
        end)
        if discovered >= deck.unlock_value then should_unlock = true end
      elseif deck.unlock_type == "money" then
        pcall(function()
          if profile.high_scores and profile.high_scores.most_money then
            if (profile.high_scores.most_money.amt or 0) >= deck.unlock_value then
              should_unlock = true
            end
          end
        end)
      elseif deck.unlock_type == "high_ante" then
        if highest_ante >= deck.unlock_value then should_unlock = true end
      elseif deck.unlock_type == "streak" then
        pcall(function()
          if profile.high_scores and profile.high_scores.win_streak then
            if (profile.high_scores.win_streak.amt or 0) >= deck.unlock_value then
              should_unlock = true
            end
          end
        end)
      elseif deck.unlock_type == "win_deck" then
        pcall(function()
          if profile.deck_usage and profile.deck_usage[deck.unlock_value] then
            local usage = profile.deck_usage[deck.unlock_value]
            if usage.wins then
              for _, count in pairs(usage.wins) do
                if count and count > 0 then should_unlock = true; break end
              end
            end
          end
        end)
      elseif deck.unlock_type == "win_decks" then
        pcall(function()
          local all_won = true
          for _, dk in ipairs(deck.unlock_value) do
            local won = false
            if profile.deck_usage and profile.deck_usage[dk] and profile.deck_usage[dk].wins then
              for _, count in pairs(profile.deck_usage[dk].wins) do
                if count and count > 0 then won = true; break end
              end
            end
            if not won then all_won = false; break end
          end
          if all_won then should_unlock = true end
        end)
      elseif deck.unlock_type == "career_stat" then
        pcall(function()
          if profile.career_stats and profile.career_stats[deck.stat] then
            if profile.career_stats[deck.stat] >= deck.unlock_value then
              should_unlock = true
            end
          end
        end)
      elseif deck.unlock_type == "win_broke" then
        pcall(function()
          if profile.career_stats and (profile.career_stats.c_wins or 0) > 0 then
            if profile.high_scores and profile.high_scores.most_money then
              if (profile.high_scores.most_money.amt or 0) <= 5 then
                should_unlock = true
              end
            end
          end
        end)
      elseif deck.unlock_type == "win_no_joker" then
        should_unlock = false
      elseif deck.unlock_type == "consumables" then
        pcall(function()
          if profile.career_stats then
            local total = (profile.career_stats.c_tarots_bought or 0) +
                          (profile.career_stats.c_planets_bought or 0) +
                          (profile.career_stats.c_spectral_bought or 0)
            if total >= deck.unlock_value then should_unlock = true end
          end
        end)
      elseif deck.unlock_type == "hand_score" then
        pcall(function()
          if profile.high_scores and profile.high_scores.hand then
            if (profile.high_scores.hand.amt or 0) >= deck.unlock_value then
              should_unlock = true
            end
          end
        end)
      elseif deck.unlock_type == "shop" then
        pcall(function()
          if ShopManager and ShopManager.get_total_spent then
            if ShopManager.get_total_spent() >= (deck.price or 0) then
              should_unlock = true
            end
          end
        end)
      end

      if should_unlock then
        ProfileRewardsManager.unlock_deck(deck.id)
      end
    end
  end
end


function ProfileRewardsManager.is_icon_unlocked(joker_key)
  if not ProfileRewardsManager.init() then return false end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression or not profile.progression.unlocked_icons then return false end

  for _, key in ipairs(profile.progression.unlocked_icons) do
    if key == joker_key then return true end
  end
  return false
end

function ProfileRewardsManager.unlock_icon(joker_key)
  if G and G.GAME and G.GAME.modded_run then return false end
  if not ProfileRewardsManager.init() then return false end
  if ProfileRewardsManager.is_icon_unlocked(joker_key) then return false end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression then return false end

  table.insert(profile.progression.unlocked_icons, joker_key)
  pcall(function() G:save_settings() end)
  print("[PROFILE_REWARDS] Icon unlocked: " .. tostring(joker_key))

  pcall(function()
    if AchievementManager and AchievementManager.check_achievement then
      local count = #profile.progression.unlocked_icons
      if count >= 1 then AchievementManager.check_achievement("icon_collector_1") end
      if count >= 5 then AchievementManager.check_achievement("icon_collector_5") end
      if count >= 15 then AchievementManager.check_achievement("icon_collector_15") end
      if count >= 30 then AchievementManager.check_achievement("icon_collector_30") end
      if count >= 50 then AchievementManager.check_achievement("icon_collector_50") end
      if count >= 100 then AchievementManager.check_achievement("icon_collector_100") end
      if count >= 150 then AchievementManager.check_achievement("icon_collector_150") end
    end
  end)

  return true
end

function ProfileRewardsManager.equip_icon(joker_key)
  if not ProfileRewardsManager.init() then return false end
  if not ProfileRewardsManager.is_icon_unlocked(joker_key) then return false end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression then return false end

  profile.progression.equipped_icon = joker_key
  pcall(function() G:save_settings() end)
  return true
end

function ProfileRewardsManager.get_equipped_icon()
  if not ProfileRewardsManager.init() then return nil end
  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression then return nil end
  return profile.progression.equipped_icon
end

function ProfileRewardsManager.get_unlocked_icon_count()
  if not ProfileRewardsManager.init() then return 0 end
  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression or not profile.progression.unlocked_icons then return 0 end
  return #profile.progression.unlocked_icons
end

function ProfileRewardsManager.check_icon_unlocks()
  if G and G.GAME and G.GAME.modded_run then return end
  if not ProfileRewardsManager.init() then return end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.joker_usage then return end

  local count = 0
  for joker_key, usage in pairs(profile.joker_usage) do
    count = count + 1
    if count > MAX_ITERATIONS then break end
    if usage.wins or usage.wins_by_key then
      local has_win = false
      for _, win_count in pairs(usage.wins or {}) do
        if tonumber(win_count) and win_count > 0 then has_win = true; break end
      end
      for _, win_count in pairs(type(usage.wins_by_key) == "table" and usage.wins_by_key or {}) do
        if has_win then break end
        if tonumber(win_count) and win_count > 0 then has_win = true end
      end
      if has_win then
        ProfileRewardsManager.unlock_icon(joker_key)
      end
    end
  end
end


if Game and Game.load_profile and not ProfileRewardsManager.load_wrapped then
  ProfileRewardsManager.load_wrapped = true
  local load_profile = Game.load_profile
  function Game:load_profile(_profile, ...)
    local r = load_profile(self, _profile, ...)
    pcall(function()
      local p = G.PROFILES[_profile] or G.PROFILES[G.SETTINGS.profile]
      if not p then return end
      p.progression = p.progression or {}
      p.progression.unlocked_decks = p.progression.unlocked_decks or {}
      ProfileRewardsManager.unlock_all_decks(p)
    end)
    return r
  end
end

_G.ProfileRewardsManager = ProfileRewardsManager
_G.DECK_UNLOCKS = DECK_UNLOCKS

print("[PROFILE_REWARDS] Profile rewards system v1.0 loaded!")
