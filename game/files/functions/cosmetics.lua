

local TITLES = {
  {id = "beginner", name = "Beginner", description = "Reach Level 5", unlock_type = "level", unlock_value = 5, category = "milestone"},
  {id = "rising_star", name = "Rising Star", description = "Reach Level 10", unlock_type = "level", unlock_value = 10, category = "milestone"},
  {id = "dedicated", name = "Dedicated", description = "Reach Level 25", unlock_type = "level", unlock_value = 25, category = "milestone"},
  {id = "veteran", name = "Veteran", description = "Reach Level 50", unlock_type = "level", unlock_value = 50, category = "milestone"},
  {id = "master", name = "Master", description = "Reach Level 100", unlock_type = "level", unlock_value = 100, category = "milestone"},
  {id = "grandmaster", name = "Grandmaster", description = "Reach Level 150", unlock_type = "level", unlock_value = 150, category = "milestone"},
  {id = "celestial_being", name = "Celestial Being", description = "Reach Level 200", unlock_type = "level", unlock_value = 200, category = "milestone"},
  {id = "transcendent", name = "Transcendent", description = "Reach Level 500", unlock_type = "level", unlock_value = 500, category = "milestone"},
  {id = "immortal", name = "Immortal", description = "Win 5000 runs", unlock_type = "wins", unlock_value = 5000, category = "milestone"},
  {id = "champion", name = "Champion", description = "Win 1000 runs", unlock_type = "wins", unlock_value = 1000, category = "milestone"},
  {id = "legend", name = "Legend", description = "Win 500 runs", unlock_type = "wins", unlock_value = 500, category = "milestone"},

  {id = "red_conqueror", name = "Red Conqueror", description = "Beat Red Stake", unlock_type = "stake", unlock_value = 2, category = "stake"},
  {id = "orange_conqueror", name = "Orange Conqueror", description = "Beat Orange Stake", unlock_type = "stake", unlock_value = 3, category = "stake"},
  {id = "green_victor", name = "Green Victor", description = "Beat Green Stake", unlock_type = "stake", unlock_value = 4, category = "stake"},
  {id = "blue_victor", name = "Blue Victor", description = "Beat Blue Stake", unlock_type = "stake", unlock_value = 5, category = "stake"},
  {id = "purple_victor", name = "Purple Victor", description = "Beat Purple Stake", unlock_type = "stake", unlock_value = 6, category = "stake"},
  {id = "black_victor", name = "Black Victor", description = "Beat Black Stake", unlock_type = "stake", unlock_value = 7, category = "stake"},
  {id = "gold_legend", name = "Gold Legend", description = "Beat Gold Stake", unlock_type = "stake", unlock_value = 8, category = "stake"},
  {id = "insanity_victor", name = "Insanity Victor", description = "Beat Insanity Stake", unlock_type = "stake", unlock_value = 9, category = "stake"},
  {id = "stakes_master", name = "Stakes Master", description = "Beat all 9 Stakes", unlock_type = "all_stakes", unlock_value = 9, category = "stake"},

  {id = "quest_hunter", name = "Quest Hunter", description = "Complete 100 quests", unlock_type = "quests", unlock_value = 100, category = "quest"},
  {id = "daily_warrior", name = "Daily Warrior", description = "Complete 50 daily quests", unlock_type = "daily_quests", unlock_value = 50, category = "quest"},
  {id = "weekly_champion", name = "Weekly Champion", description = "Complete 25 weekly quests", unlock_type = "weekly_quests", unlock_value = 25, category = "quest"},
  {id = "quest_master", name = "Quest Master", description = "Complete 500 quests", unlock_type = "quests", unlock_value = 500, category = "quest"},

  {id = "achievement_hunter", name = "Achievement Hunter", description = "Unlock 50 achievements", unlock_type = "achievements", unlock_value = 50, category = "achievement"},
  {id = "completionist", name = "Completionist", description = "Unlock all achievements", unlock_type = "all_achievements", unlock_value = 150, category = "achievement"},

  {id = "the_collector", name = "The Collector", description = "Special title for collectors", unlock_type = "shop", price = 500, category = "shop"},
  {id = "high_roller", name = "High Roller", description = "For big spenders", unlock_type = "shop", price = 750, category = "shop"},
  {id = "the_legend", name = "The Legend", description = "Legendary title", unlock_type = "shop", price = 2000, category = "shop"},
  {id = "card_shark", name = "Card Shark", description = "Master of cards", unlock_type = "shop", price = 1000, category = "shop"},
  {id = "luck_master", name = "Luck Master", description = "Fortune favors you", unlock_type = "shop", price = 1500, category = "shop"},
  {id = "joker_king", name = "Joker King", description = "Ruler of Jokers", unlock_type = "shop", price = 2500, category = "shop"},
  {id = "chip_master", name = "Chip Master", description = "Master of chips", unlock_type = "shop", price = 1000, category = "shop"},
  {id = "mult_king", name = "Mult King", description = "Multiplier royalty", unlock_type = "shop", price = 1500, category = "shop"},
  {id = "void_walker", name = "Void Walker", description = "From the void", unlock_type = "shop", price = 3000, category = "shop"},
  {id = "star_child", name = "Star Child", description = "Born of stars", unlock_type = "shop", price = 2000, category = "shop"},
  {id = "omega", name = "Omega", description = "The end", unlock_type = "shop", price = 5000, category = "shop"},
  {id = "alpha", name = "Alpha", description = "The beginning", unlock_type = "shop", price = 5000, category = "shop"},
  {id = "eternal", name = "Eternal", description = "Beyond time", unlock_type = "shop", price = 4000, category = "shop"},
  {id = "phantom", name = "Phantom", description = "Unseen presence", unlock_type = "shop", price = 2500, category = "shop"},
  {id = "blaze", name = "Blaze", description = "Burning bright", unlock_type = "shop", price = 1500, category = "shop"},
  {id = "frost", name = "Frost", description = "Cold as ice", unlock_type = "shop", price = 1500, category = "shop"},
  {id = "shadow", name = "Shadow", description = "In the darkness", unlock_type = "shop", price = 2000, category = "shop"},
  {id = "thunder", name = "Thunder", description = "Strike like lightning", unlock_type = "shop", price = 2000, category = "shop"},
  {id = "cosmos", name = "Cosmos", description = "Universal being", unlock_type = "shop", price = 3500, category = "shop"},
  {id = "nebula", name = "Nebula", description = "Star born", unlock_type = "shop", price = 3000, category = "shop"},
}

local BANNERS = {
  {id = "default", name = "Default", description = "Standard banner", unlock_type = "default", category = "default"},

  {id = "bronze_banner", name = "Bronze Frame", description = "Reach Bronze Rank", unlock_type = "rank", unlock_value = "Bronze", category = "rank"},
  {id = "silver_banner", name = "Silver Frame", description = "Reach Silver Rank", unlock_type = "rank", unlock_value = "Silver", category = "rank"},
  {id = "gold_banner", name = "Gold Frame", description = "Reach Gold Rank", unlock_type = "rank", unlock_value = "Gold", category = "rank"},
  {id = "platinum_banner", name = "Platinum Frame", description = "Reach Platinum Rank", unlock_type = "rank", unlock_value = "Platinum", category = "rank"},
  {id = "diamond_banner", name = "Diamond Frame", description = "Reach Diamond Rank", unlock_type = "rank", unlock_value = "Diamond", category = "rank"},
  {id = "master_banner", name = "Master Frame", description = "Reach Master Rank", unlock_type = "rank", unlock_value = "Master", category = "rank"},
  {id = "grandmaster_banner", name = "Grandmaster Frame", description = "Reach Grandmaster Rank", unlock_type = "rank", unlock_value = "Grandmaster", category = "rank"},
  {id = "celestial_banner", name = "Celestial Frame", description = "Reach Celestial Rank", unlock_type = "rank", unlock_value = "Celestial", category = "rank"},

  {id = "holographic", name = "Holographic", description = "Shimmering effect", unlock_type = "shop", price = 5000, category = "shop"},
  {id = "rainbow", name = "Rainbow", description = "All colors", unlock_type = "shop", price = 7500, category = "shop"},
  {id = "neon", name = "Neon", description = "Glowing neon", unlock_type = "shop", price = 6000, category = "shop"},
  {id = "flame", name = "Flame", description = "Burning flames", unlock_type = "shop", price = 5000, category = "shop"},
  {id = "ice", name = "Ice", description = "Frozen beauty", unlock_type = "shop", price = 5000, category = "shop"},
  {id = "galaxy", name = "Galaxy", description = "Cosmic display", unlock_type = "shop", price = 8000, category = "shop"},
  {id = "polychrome", name = "Polychrome", description = "Shifting colors", unlock_type = "shop", price = 10000, category = "shop"},
  {id = "negative", name = "Negative", description = "Inverted space", unlock_type = "shop", price = 7500, category = "shop"},
  {id = "foil", name = "Foil", description = "Metallic shine", unlock_type = "shop", price = 4000, category = "shop"},
  {id = "glass", name = "Glass", description = "Transparent elegance", unlock_type = "shop", price = 4500, category = "shop"},
  {id = "stone", name = "Stone", description = "Solid rock", unlock_type = "shop", price = 3000, category = "shop"},
  {id = "lucky", name = "Lucky", description = "Fortune frame", unlock_type = "shop", price = 5500, category = "shop"},
  {id = "wild", name = "Wild", description = "Untamed design", unlock_type = "shop", price = 4000, category = "shop"},
  {id = "steel", name = "Steel", description = "Metallic strength", unlock_type = "shop", price = 3500, category = "shop"},
  {id = "gold_plated", name = "Gold Plated", description = "Luxurious gold", unlock_type = "shop", price = 6000, category = "shop"},
  {id = "royal", name = "Royal", description = "Fit for royalty", unlock_type = "shop", price = 8000, category = "shop"},
  {id = "ancient", name = "Ancient", description = "Timeless design", unlock_type = "shop", price = 5000, category = "shop"},
  {id = "futuristic", name = "Futuristic", description = "From the future", unlock_type = "shop", price = 6500, category = "shop"},
  {id = "mystic", name = "Mystic", description = "Magical aura", unlock_type = "shop", price = 7000, category = "shop"},
  {id = "void", name = "Void", description = "Endless darkness", unlock_type = "shop", price = 9000, category = "shop"},
}

local BADGES = {
  {id = "default", name = "Default", description = "Standard badge", unlock_type = "default", category = "default"},

  {id = "bronze_badge", name = "Bronze Badge", description = "Reach Bronze Rank", unlock_type = "rank", unlock_value = "Bronze", category = "rank", icon = "star"},
  {id = "silver_badge", name = "Silver Badge", description = "Reach Silver Rank", unlock_type = "rank", unlock_value = "Silver", category = "rank", icon = "star"},
  {id = "gold_badge", name = "Gold Badge", description = "Reach Gold Rank", unlock_type = "rank", unlock_value = "Gold", category = "rank", icon = "star"},
  {id = "platinum_badge", name = "Platinum Badge", description = "Reach Platinum Rank", unlock_type = "rank", unlock_value = "Platinum", category = "rank", icon = "diamond"},
  {id = "diamond_badge", name = "Diamond Badge", description = "Reach Diamond Rank", unlock_type = "rank", unlock_value = "Diamond", category = "rank", icon = "diamond"},
  {id = "master_badge", name = "Master Badge", description = "Reach Master Rank", unlock_type = "rank", unlock_value = "Master", category = "rank", icon = "crown"},
  {id = "grandmaster_badge", name = "Grandmaster Badge", description = "Reach Grandmaster Rank", unlock_type = "rank", unlock_value = "Grandmaster", category = "rank", icon = "crown"},
  {id = "celestial_badge", name = "Celestial Badge", description = "Reach Celestial Rank", unlock_type = "rank", unlock_value = "Celestial", category = "rank", icon = "omega"},

  {id = "winner_badge", name = "Winner", description = "Win 100 runs", unlock_type = "wins", unlock_value = 100, category = "achievement", icon = "checkmark"},
  {id = "millionaire_badge", name = "Millionaire", description = "Score 1M+ chips", unlock_type = "score", unlock_value = 1000000, category = "achievement", icon = "chips"},
  {id = "collector_badge", name = "Collector", description = "Collect all Jokers", unlock_type = "collection", unlock_value = "jokers", category = "achievement", icon = "star"},

  {id = "chips_badge", name = "Chips Icon", description = "Blue chip badge", unlock_type = "shop", price = 1000, category = "shop", icon = "chips"},
  {id = "mult_badge", name = "Mult Icon", description = "Red mult badge", unlock_type = "shop", price = 1000, category = "shop", icon = "mult"},
  {id = "money_badge", name = "Money Icon", description = "Dollar badge", unlock_type = "shop", price = 1500, category = "shop", icon = "money"},
  {id = "joker_badge", name = "Joker Icon", description = "Joker face badge", unlock_type = "shop", price = 2000, category = "shop", icon = "joker"},
  {id = "tarot_badge", name = "Tarot Icon", description = "Mystical badge", unlock_type = "shop", price = 2000, category = "shop", icon = "tarot"},
  {id = "planet_badge", name = "Planet Icon", description = "Cosmic badge", unlock_type = "shop", price = 2000, category = "shop", icon = "planet"},
  {id = "spectral_badge", name = "Spectral Icon", description = "Ghostly badge", unlock_type = "shop", price = 3000, category = "shop", icon = "spectral"},
  {id = "legendary_badge", name = "Legendary Icon", description = "Legendary badge", unlock_type = "shop", price = 5000, category = "shop", icon = "legendary"},
  {id = "holo_badge", name = "Holographic", description = "Shimmering badge", unlock_type = "shop", price = 6000, category = "shop", icon = "holo"},
  {id = "poly_badge", name = "Polychrome", description = "Colorful badge", unlock_type = "shop", price = 8000, category = "shop", icon = "poly"},
  {id = "negative_badge", name = "Negative", description = "Dark badge", unlock_type = "shop", price = 7000, category = "shop", icon = "negative"},
  {id = "foil_badge", name = "Foil", description = "Shiny badge", unlock_type = "shop", price = 4000, category = "shop", icon = "foil"},
  {id = "crown_badge", name = "Crown", description = "Royal badge", unlock_type = "shop", price = 5000, category = "shop", icon = "crown"},
  {id = "omega_badge", name = "Omega", description = "Ultimate badge", unlock_type = "shop", price = 10000, category = "shop", icon = "omega"},
  {id = "fire_badge", name = "Fire", description = "Burning badge", unlock_type = "shop", price = 3500, category = "shop", icon = "fire"},
  {id = "ice_badge", name = "Ice", description = "Frozen badge", unlock_type = "shop", price = 3500, category = "shop", icon = "ice"},
  {id = "lightning_badge", name = "Lightning", description = "Electric badge", unlock_type = "shop", price = 4000, category = "shop", icon = "lightning"},
  {id = "heart_badge", name = "Heart", description = "Love badge", unlock_type = "shop", price = 2500, category = "shop", icon = "heart"},
  {id = "skull_badge", name = "Skull", description = "Dark badge", unlock_type = "shop", price = 3000, category = "shop", icon = "skull"},
}

local BORDERS = {
  {id = "default", name = "Default", description = "Standard border", unlock_type = "default", category = "default", style = "solid"},

  {id = "clean", name = "Clean", description = "Minimal border", unlock_type = "level", unlock_value = 10, category = "basic", style = "thin"},
  {id = "thick", name = "Thick", description = "Bold border", unlock_type = "level", unlock_value = 20, category = "basic", style = "thick"},
  {id = "double", name = "Double", description = "Double line", unlock_type = "level", unlock_value = 30, category = "basic", style = "double"},
  {id = "ornate", name = "Ornate", description = "Decorative border", unlock_type = "level", unlock_value = 50, category = "basic", style = "ornate"},

  {id = "shiny", name = "Shiny", description = "Reflective border", unlock_type = "shop", price = 750, category = "shop", style = "shiny"},
  {id = "legendary", name = "Legendary", description = "Legendary border", unlock_type = "shop", price = 3000, category = "shop", style = "legendary"},
  {id = "rainbow_border", name = "Rainbow", description = "Colorful border", unlock_type = "shop", price = 5000, category = "shop", style = "rainbow"},
  {id = "transcendent", name = "Transcendent", description = "Beyond mortal", unlock_type = "shop", price = 7500, category = "shop", style = "transcendent"},
  {id = "glow", name = "Glow", description = "Glowing effect", unlock_type = "shop", price = 2000, category = "shop", style = "glow"},
  {id = "animated", name = "Animated", description = "Moving border", unlock_type = "shop", price = 4000, category = "shop", style = "animated"},
  {id = "holographic_border", name = "Holographic", description = "Holo effect", unlock_type = "shop", price = 5000, category = "shop", style = "holographic"},
  {id = "neon_border", name = "Neon", description = "Neon glow", unlock_type = "shop", price = 3500, category = "shop", style = "neon"},
  {id = "golden", name = "Golden", description = "Pure gold", unlock_type = "shop", price = 4500, category = "shop", style = "golden"},
  {id = "platinum", name = "Platinum", description = "Platinum shine", unlock_type = "shop", price = 5500, category = "shop", style = "platinum"},
  {id = "diamond", name = "Diamond", description = "Crystalline", unlock_type = "shop", price = 6500, category = "shop", style = "diamond"},
  {id = "flame_border", name = "Flame", description = "Burning edges", unlock_type = "shop", price = 4000, category = "shop", style = "flame"},
  {id = "frost_border", name = "Frost", description = "Icy edges", unlock_type = "shop", price = 4000, category = "shop", style = "frost"},
  {id = "void_border", name = "Void", description = "Dark void", unlock_type = "shop", price = 6000, category = "shop", style = "void"},
  {id = "celestial_border", name = "Celestial", description = "Star adorned", unlock_type = "shop", price = 7000, category = "shop", style = "celestial"},
}


CosmeticsManager = {
  initialized = false,
}

function CosmeticsManager.init()
  if CosmeticsManager.initialized then return true end
  if not G then return false end
  if not G.PROFILES then return false end
  if not G.SETTINGS then return false end
  if not G.SETTINGS.profile then return false end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile then return false end

  if not profile.progression then
    profile.progression = {}
  end

  if not profile.progression.unlocked_titles then
    profile.progression.unlocked_titles = {}
  end
  if not profile.progression.unlocked_banners then
    profile.progression.unlocked_banners = {"default"}
  end
  if not profile.progression.unlocked_badges then
    profile.progression.unlocked_badges = {"default"}
  end
  if not profile.progression.unlocked_borders then
    profile.progression.unlocked_borders = {"default"}
  end

  if not profile.progression.equipped_title then
    profile.progression.equipped_title = nil
  end
  if not profile.progression.equipped_banner then
    profile.progression.equipped_banner = "default"
  end
  if not profile.progression.equipped_badge then
    profile.progression.equipped_badge = "default"
  end
  if not profile.progression.equipped_border then
    profile.progression.equipped_border = "default"
  end

  CosmeticsManager.initialized = true

  CosmeticsManager.check_all_unlocks()

  print("[COSMETICS] Cosmetics system initialized!")
  return true
end

function CosmeticsManager.is_unlocked(cosmetic_type, id)
  if not CosmeticsManager.init() then return false end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression then return false end

  local unlock_table = nil
  if cosmetic_type == "title" then
    unlock_table = profile.progression.unlocked_titles
  elseif cosmetic_type == "banner" then
    unlock_table = profile.progression.unlocked_banners
  elseif cosmetic_type == "badge" then
    unlock_table = profile.progression.unlocked_badges
  elseif cosmetic_type == "border" then
    unlock_table = profile.progression.unlocked_borders
  end

  if not unlock_table then return false end

  if not unlock_table._set or unlock_table._n ~= #unlock_table then
    unlock_table._set = {}
    for _, unlocked_id in ipairs(unlock_table) do
      unlock_table._set[unlocked_id] = true
    end
    unlock_table._n = #unlock_table
  end
  return unlock_table._set[id] == true
end

function CosmeticsManager.unlock(cosmetic_type, id)
  if not Progress.allowed() then return false end
  if not CosmeticsManager.init() then return false end
  if CosmeticsManager.is_unlocked(cosmetic_type, id) then return false end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression then return false end

  local unlock_table = nil
  if cosmetic_type == "title" then
    unlock_table = profile.progression.unlocked_titles
  elseif cosmetic_type == "banner" then
    unlock_table = profile.progression.unlocked_banners
  elseif cosmetic_type == "badge" then
    unlock_table = profile.progression.unlocked_badges
  elseif cosmetic_type == "border" then
    unlock_table = profile.progression.unlocked_borders
  end

  if unlock_table then
    table.insert(unlock_table, id)
    unlock_table._set = nil
    return true
  end
  return false
end

function CosmeticsManager.equip(cosmetic_type, id)
  if not CosmeticsManager.init() then return false end
  if not CosmeticsManager.is_unlocked(cosmetic_type, id) then return false end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression then return false end

  if cosmetic_type == "title" then
    profile.progression.equipped_title = id
    local SC = rawget(_G, "BO_SHOWCASE")
    if SC and SC.data then SC.data().t = "c:" .. tostring(id) end
  elseif cosmetic_type == "banner" then
    profile.progression.equipped_banner = id
  elseif cosmetic_type == "badge" then
    profile.progression.equipped_badge = id
  elseif cosmetic_type == "border" then
    profile.progression.equipped_border = id
  end

  if G and G.save_progress then G:save_progress() end
  return true
end

function CosmeticsManager.get_equipped(cosmetic_type)
  if not CosmeticsManager.init() then return nil end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression then return nil end

  if cosmetic_type == "title" then
    return profile.progression.equipped_title
  elseif cosmetic_type == "banner" then
    return profile.progression.equipped_banner
  elseif cosmetic_type == "badge" then
    return profile.progression.equipped_badge
  elseif cosmetic_type == "border" then
    return profile.progression.equipped_border
  end
  return nil
end

function CosmeticsManager.get_cosmetic(cosmetic_type, id)
  local pool = nil
  if cosmetic_type == "title" then pool = TITLES
  elseif cosmetic_type == "banner" then pool = BANNERS
  elseif cosmetic_type == "badge" then pool = BADGES
  elseif cosmetic_type == "border" then pool = BORDERS
  end

  if not pool then return nil end

  for _, item in ipairs(pool) do
    if item.id == id then return item end
  end
  return nil
end

function CosmeticsManager.check_all_unlocks()
  if not Progress.allowed() then return end
  if not CosmeticsManager.init() then return end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression then return end

  local level = profile.progression.level or 1
  local wins = profile.progression.total_wins or 0
  local highest_stake = profile.progression.highest_stake_beaten or 0

  for _, title in ipairs(TITLES) do
    if not CosmeticsManager.is_unlocked("title", title.id) then
      local should_unlock = false

      if title.unlock_type == "level" and level >= title.unlock_value then
        should_unlock = true
      elseif title.unlock_type == "wins" and wins >= title.unlock_value then
        should_unlock = true
      elseif title.unlock_type == "stake" and highest_stake >= title.unlock_value then
        should_unlock = true
      elseif title.unlock_type == "default" then
        should_unlock = true
      end

      if should_unlock then
        CosmeticsManager.unlock("title", title.id)
      end
    end
  end

  for _, banner in ipairs(BANNERS) do
    if not CosmeticsManager.is_unlocked("banner", banner.id) then
      local should_unlock = false

      if banner.unlock_type == "default" then
        should_unlock = true
      elseif banner.unlock_type == "rank" then
        local rank = get_rank and get_rank(level)
        if rank and rank.name == banner.unlock_value then
          should_unlock = true
        end
      end

      if should_unlock then
        CosmeticsManager.unlock("banner", banner.id)
      end
    end
  end

  for _, badge in ipairs(BADGES) do
    if not CosmeticsManager.is_unlocked("badge", badge.id) then
      local should_unlock = false

      if badge.unlock_type == "default" then
        should_unlock = true
      elseif badge.unlock_type == "rank" then
        local rank = get_rank and get_rank(level)
        if rank and rank.name == badge.unlock_value then
          should_unlock = true
        end
      elseif badge.unlock_type == "wins" and wins >= badge.unlock_value then
        should_unlock = true
      end

      if should_unlock then
        CosmeticsManager.unlock("badge", badge.id)
      end
    end
  end

  for _, border in ipairs(BORDERS) do
    if not CosmeticsManager.is_unlocked("border", border.id) then
      local should_unlock = false

      if border.unlock_type == "default" then
        should_unlock = true
      elseif border.unlock_type == "level" and level >= border.unlock_value then
        should_unlock = true
      end

      if should_unlock then
        CosmeticsManager.unlock("border", border.id)
      end
    end
  end
end

function CosmeticsManager.get_unlocked_count(cosmetic_type)
  if not CosmeticsManager.init() then return 0 end

  local profile = G.PROFILES[G.SETTINGS.profile]
  if not profile or not profile.progression then return 0 end

  local unlock_table = nil
  if cosmetic_type == "title" then
    unlock_table = profile.progression.unlocked_titles
  elseif cosmetic_type == "banner" then
    unlock_table = profile.progression.unlocked_banners
  elseif cosmetic_type == "badge" then
    unlock_table = profile.progression.unlocked_badges
  elseif cosmetic_type == "border" then
    unlock_table = profile.progression.unlocked_borders
  end

  return unlock_table and #unlock_table or 0
end

function CosmeticsManager.get_total_count(cosmetic_type)
  if cosmetic_type == "title" then return #TITLES
  elseif cosmetic_type == "banner" then return #BANNERS
  elseif cosmetic_type == "badge" then return #BADGES
  elseif cosmetic_type == "border" then return #BORDERS
  end
  return 0
end

_G.TITLES = TITLES
_G.BANNERS = BANNERS
_G.BADGES = BADGES
_G.BORDERS = BORDERS
_G.CosmeticsManager = CosmeticsManager

print("[COSMETICS] Cosmetics system v10.5 loaded!")
