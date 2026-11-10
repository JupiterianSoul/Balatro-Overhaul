

require("functions/shop/tavern_palettes")

SHOP_RARITY = {
  COMMON    = {id = 1, name = "Common",    color = "WHITE",  price_mult = 1.0},
  UNCOMMON  = {id = 2, name = "Uncommon",  color = "GREEN",  price_mult = 2.0},
  RARE      = {id = 3, name = "Rare",      color = "BLUE",   price_mult = 4.0},
  EPIC      = {id = 4, name = "Epic",      color = "PURPLE", price_mult = 8.0},
  LEGENDARY = {id = 5, name = "Legendary", color = "GOLD",   price_mult = 16.0},
}

local BASE_PRICE = {
  color_set   = 80,
  icon_effect = 150,
}

local function rarity_price(base, rarity)
  return math.floor(base * rarity.price_mult)
end


SHOP_COLOR_SETS = {
  {id="ocean",      name="Ocean",       rarity=SHOP_RARITY.COMMON,
    blue={0,180,220}, red={255,100,80}, green={0,200,170}, yellow={255,220,100}},
  {id="forest",     name="Forest",      rarity=SHOP_RARITY.COMMON,
    blue={60,140,90}, red={180,70,50}, green={30,160,60}, yellow={220,190,50}},
  {id="pastel",     name="Pastel",      rarity=SHOP_RARITY.COMMON,
    blue={140,180,255}, red={255,150,160}, green={150,230,180}, yellow={255,240,170}},
  {id="monochrome", name="Monochrome",  rarity=SHOP_RARITY.COMMON,
    blue={170,170,190}, red={130,130,140}, green={200,200,210}, yellow={240,240,245}},
  {id="candy",      name="Candy",       rarity=SHOP_RARITY.COMMON,
    blue={100,200,255}, red={255,80,130}, green={100,230,150}, yellow={255,240,80}},

  {id="sunset",     name="Sunset",      rarity=SHOP_RARITY.UNCOMMON,
    blue={80,60,160}, red={240,80,50}, green={200,120,180}, yellow={255,180,50}},
  {id="neon",       name="Neon",        rarity=SHOP_RARITY.UNCOMMON,
    blue={0,255,255}, red={255,0,128}, green={0,255,64}, yellow={255,255,0}},
  {id="autumn",     name="Autumn",      rarity=SHOP_RARITY.UNCOMMON,
    blue={100,80,60}, red={200,60,30}, green={140,120,40}, yellow={230,170,40}},
  {id="retro",      name="Retro",       rarity=SHOP_RARITY.UNCOMMON,
    blue={0,200,220}, red={220,50,80}, green={80,200,80}, yellow={240,220,60}},
  {id="sakura",     name="Sakura",      rarity=SHOP_RARITY.UNCOMMON,
    blue={180,160,210}, red={240,130,150}, green={140,190,140}, yellow={255,230,200}},

  {id="midnight",   name="Midnight",    rarity=SHOP_RARITY.RARE,
    blue={30,40,120}, red={150,30,50}, green={40,80,100}, yellow={180,160,100}},
  {id="winter",     name="Winter",      rarity=SHOP_RARITY.RARE,
    blue={140,200,255}, red={180,60,90}, green={60,130,100}, yellow={230,240,255}},
  {id="royal",      name="Royal",       rarity=SHOP_RARITY.RARE,
    blue={50,50,200}, red={160,30,160}, green={30,160,100}, yellow={255,200,50}},
  {id="steampunk",  name="Steampunk",   rarity=SHOP_RARITY.RARE,
    blue={120,90,60}, red={160,50,40}, green={140,110,70}, yellow={200,160,80}},
  {id="toxic",      name="Toxic",       rarity=SHOP_RARITY.RARE,
    blue={40,180,60}, red={160,40,200}, green={80,255,80}, yellow={220,255,0}},

  {id="volcanic",   name="Volcanic",    rarity=SHOP_RARITY.EPIC,
    blue={40,50,80}, red={230,50,20}, green={100,90,80}, yellow={255,160,30}},
  {id="cosmic",     name="Cosmic",      rarity=SHOP_RARITY.EPIC,
    blue={80,40,180}, red={255,120,40}, green={60,100,180}, yellow={255,210,80}},
  {id="arctic",     name="Arctic",      rarity=SHOP_RARITY.EPIC,
    blue={100,180,240}, red={220,100,160}, green={80,200,180}, yellow={220,230,250}},
  {id="ember",      name="Ember",       rarity=SHOP_RARITY.EPIC,
    blue={50,60,80}, red={230,80,30}, green={120,110,100}, yellow={255,140,20}},

  {id="abyss",      name="Abyss",       rarity=SHOP_RARITY.LEGENDARY,
    blue={20,60,140}, red={180,20,40}, green={10,40,30}, yellow={40,200,220}},


  {id="lavender",   name="Lavender",    rarity=SHOP_RARITY.COMMON,
    blue={150,130,220}, red={220,130,160}, green={160,200,170}, yellow={240,220,180}},
  {id="desert",     name="Desert",      rarity=SHOP_RARITY.COMMON,
    blue={120,140,170}, red={200,110,70}, green={170,160,100}, yellow={240,200,80}},
  {id="bubblegum",  name="Bubblegum",   rarity=SHOP_RARITY.COMMON,
    blue={130,180,255}, red={255,120,170}, green={120,220,160}, yellow={255,230,120}},
  {id="slate",      name="Slate",       rarity=SHOP_RARITY.COMMON,
    blue={100,120,150}, red={160,100,100}, green={120,140,130}, yellow={190,180,160}},

  {id="tropical",   name="Tropical",    rarity=SHOP_RARITY.UNCOMMON,
    blue={0,190,200}, red={255,70,90}, green={50,220,100}, yellow={255,210,0}},
  {id="aurora",     name="Aurora",      rarity=SHOP_RARITY.UNCOMMON,
    blue={80,200,220}, red={200,100,180}, green={100,255,150}, yellow={255,240,130}},
  {id="vintage",    name="Vintage",     rarity=SHOP_RARITY.UNCOMMON,
    blue={90,100,120}, red={180,80,60}, green={100,120,80}, yellow={210,180,100}},
  {id="coral",      name="Coral",       rarity=SHOP_RARITY.UNCOMMON,
    blue={60,160,190}, red={240,100,100}, green={80,200,160}, yellow={255,200,120}},

  {id="cyberpunk",  name="Cyberpunk",   rarity=SHOP_RARITY.RARE,
    blue={0,200,255}, red={255,0,100}, green={0,255,100}, yellow={255,200,0}},
  {id="glacier",    name="Glacier",     rarity=SHOP_RARITY.RARE,
    blue={100,200,240}, red={160,80,120}, green={70,180,180}, yellow={200,220,240}},
  {id="inferno",    name="Inferno",     rarity=SHOP_RARITY.RARE,
    blue={30,30,80}, red={255,40,10}, green={80,60,30}, yellow={255,120,0}},
  {id="jade",       name="Jade",        rarity=SHOP_RARITY.RARE,
    blue={40,100,120}, red={160,60,80}, green={20,180,100}, yellow={180,200,80}},

  {id="phantom",    name="Phantom",     rarity=SHOP_RARITY.EPIC,
    blue={60,20,140}, red={200,40,120}, green={30,80,100}, yellow={180,120,220}},
  {id="solar",      name="Solar",       rarity=SHOP_RARITY.EPIC,
    blue={60,80,150}, red={255,80,0}, green={180,140,40}, yellow={255,220,50}},
  {id="deep_sea",   name="Deep Sea",    rarity=SHOP_RARITY.EPIC,
    blue={10,60,120}, red={120,40,80}, green={20,100,90}, yellow={80,180,200}},
  {id="bloodmoon",  name="Blood Moon",  rarity=SHOP_RARITY.EPIC,
    blue={40,30,60}, red={200,20,30}, green={60,40,50}, yellow={180,100,40}},

  {id="prismatic",  name="Prismatic",   rarity=SHOP_RARITY.LEGENDARY,
    blue={40,80,255}, red={255,40,80}, green={40,255,120}, yellow={255,240,40}},
  {id="ethereal",   name="Ethereal",    rarity=SHOP_RARITY.LEGENDARY,
    blue={180,200,255}, red={255,180,200}, green={180,255,220}, yellow={255,255,200}},
  {id="obsidian",   name="Obsidian",    rarity=SHOP_RARITY.LEGENDARY,
    blue={20,20,50}, red={100,10,20}, green={10,30,20}, yellow={60,50,30}},
  {id="supernova",  name="Supernova",   rarity=SHOP_RARITY.LEGENDARY,
    blue={125,60,255}, red={255,60,20}, green={40,200,160}, yellow={255,245,200}},
  {id="noir", name="Noir", rarity=SHOP_RARITY.RARE, group="Themes", bonus=true,
    blue={70,90,130}, red={170,40,50}, green={90,120,100}, yellow={210,180,110}},
  {id="vaporwave", name="Vaporwave", rarity=SHOP_RARITY.EPIC, group="Themes", bonus=true,
    blue={90,160,255}, red={255,90,200}, green={80,230,200}, yellow={255,200,120}},
  {id="synthwave", name="Synthwave", rarity=SHOP_RARITY.EPIC, group="Themes", bonus=true,
    blue={60,80,230}, red={255,60,140}, green={0,220,200}, yellow={255,170,40}},
  {id="matcha", name="Matcha", rarity=SHOP_RARITY.UNCOMMON, group="Themes", bonus=true,
    blue={110,150,170}, red={200,110,90}, green={120,170,90}, yellow={230,210,150}},
  {id="circus", name="Circus", rarity=SHOP_RARITY.COMMON, group="Themes", bonus=true,
    blue={40,110,220}, red={230,40,50}, green={40,170,90}, yellow={255,200,30}},
  {id="jungle", name="Jungle", rarity=SHOP_RARITY.UNCOMMON, group="Themes", bonus=true,
    blue={40,120,130}, red={210,90,40}, green={50,150,50}, yellow={230,200,60}},
  {id="pirate", name="Pirate", rarity=SHOP_RARITY.RARE, group="Themes", bonus=true,
    blue={40,80,140}, red={170,40,40}, green={70,110,80}, yellow={220,170,60}},
  {id="fairy_tale", name="Fairy Tale", rarity=SHOP_RARITY.RARE, group="Themes", bonus=true,
    blue={130,150,240}, red={230,100,170}, green={120,210,160}, yellow={255,220,140}},
  {id="galaxy", name="Galaxy", rarity=SHOP_RARITY.LEGENDARY, group="Themes", bonus=true,
    blue={70,60,200}, red={220,60,160}, green={60,160,200}, yellow={250,210,120}},
  {id="mint", name="Mint", rarity=SHOP_RARITY.COMMON, group="Pastels", bonus=true,
    blue={140,200,230}, red={250,160,160}, green={160,235,200}, yellow={250,235,170}},
  {id="peach", name="Peach", rarity=SHOP_RARITY.COMMON, group="Pastels", bonus=true,
    blue={150,180,230}, red={255,150,130}, green={170,220,170}, yellow={255,215,160}},
  {id="lilac", name="Lilac", rarity=SHOP_RARITY.COMMON, group="Pastels", bonus=true,
    blue={170,160,235}, red={235,150,200}, green={170,220,200}, yellow={245,225,190}},
  {id="baby_blue", name="Baby Blue", rarity=SHOP_RARITY.COMMON, group="Pastels", bonus=true,
    blue={150,200,250}, red={240,170,180}, green={170,220,210}, yellow={245,235,200}},
  {id="cotton_candy", name="Cotton Candy", rarity=SHOP_RARITY.UNCOMMON, group="Pastels", bonus=true,
    blue={150,200,255}, red={255,160,210}, green={170,240,210}, yellow={255,245,180}},
  {id="macaron", name="Macaron", rarity=SHOP_RARITY.UNCOMMON, group="Pastels", bonus=true,
    blue={160,190,240}, red={240,140,160}, green={180,225,160}, yellow={250,220,150}},
  {id="sorbet", name="Sorbet", rarity=SHOP_RARITY.UNCOMMON, group="Pastels", bonus=true,
    blue={140,210,240}, red={255,140,140}, green={180,240,170}, yellow={255,225,120}},
  {id="dreamy", name="Dreamy", rarity=SHOP_RARITY.RARE, group="Pastels", bonus=true,
    blue={180,180,255}, red={255,180,220}, green={180,255,230}, yellow={255,240,210}},
  {id="arcade", name="Arcade", rarity=SHOP_RARITY.COMMON, group="Neons", bonus=true,
    blue={20,140,255}, red={255,40,40}, green={0,230,90}, yellow={255,210,0}},
  {id="neon_nights", name="Neon Nights", rarity=SHOP_RARITY.UNCOMMON, group="Neons", bonus=true,
    blue={40,120,255}, red={255,30,90}, green={60,255,120}, yellow={255,230,0}},
  {id="laser", name="Laser", rarity=SHOP_RARITY.UNCOMMON, group="Neons", bonus=true,
    blue={0,160,255}, red={255,0,60}, green={120,255,0}, yellow={255,255,60}},
  {id="hot_pink", name="Hot Pink", rarity=SHOP_RARITY.UNCOMMON, group="Neons", bonus=true,
    blue={80,140,255}, red={255,20,150}, green={40,240,170}, yellow={255,200,60}},
  {id="blacklight", name="Blacklight", rarity=SHOP_RARITY.RARE, group="Neons", bonus=true,
    blue={120,60,255}, red={255,40,200}, green={80,255,200}, yellow={230,255,60}},
  {id="electric_lime", name="Electric Lime", rarity=SHOP_RARITY.RARE, group="Neons", bonus=true,
    blue={0,200,230}, red={255,60,120}, green={170,255,0}, yellow={255,240,0}},
  {id="ultraviolet", name="Ultraviolet", rarity=SHOP_RARITY.EPIC, group="Neons", bonus=true,
    blue={100,40,255}, red={255,40,120}, green={40,220,255}, yellow={255,220,80}},
  {id="glowstick", name="Glowstick", rarity=SHOP_RARITY.EPIC, group="Neons", bonus=true,
    blue={0,230,255}, red={255,80,0}, green={0,255,80}, yellow={255,255,120}},
  {id="charcoal", name="Charcoal", rarity=SHOP_RARITY.COMMON, group="Dark", bonus=true,
    blue={70,90,120}, red={150,60,60}, green={70,110,90}, yellow={180,160,110}},
  {id="dusk", name="Dusk", rarity=SHOP_RARITY.UNCOMMON, group="Dark", bonus=true,
    blue={60,70,140}, red={170,70,90}, green={60,110,110}, yellow={200,150,90}},
  {id="nightshade", name="Nightshade", rarity=SHOP_RARITY.UNCOMMON, group="Dark", bonus=true,
    blue={50,40,120}, red={130,30,110}, green={40,90,80}, yellow={180,160,90}},
  {id="shadow", name="Shadow", rarity=SHOP_RARITY.RARE, group="Dark", bonus=true,
    blue={50,60,110}, red={140,40,60}, green={40,90,80}, yellow={170,140,80}},
  {id="gothic", name="Gothic", rarity=SHOP_RARITY.RARE, group="Dark", bonus=true,
    blue={60,40,110}, red={150,20,40}, green={50,80,60}, yellow={170,130,60}},
  {id="raven", name="Raven", rarity=SHOP_RARITY.EPIC, group="Dark", bonus=true,
    blue={40,60,100}, red={120,40,70}, green={40,80,90}, yellow={160,150,120}},
  {id="eclipse", name="Eclipse", rarity=SHOP_RARITY.EPIC, group="Dark", bonus=true,
    blue={40,40,90}, red={180,50,30}, green={50,70,70}, yellow={230,170,50}},
  {id="void", name="Void", rarity=SHOP_RARITY.LEGENDARY, group="Dark", bonus=true,
    blue={30,30,80}, red={120,20,80}, green={20,60,70}, yellow={120,90,160}},
  {id="spring_bloom", name="Spring Bloom", rarity=SHOP_RARITY.COMMON, group="Seasonal", bonus=true,
    blue={110,180,230}, red={240,120,150}, green={110,210,110}, yellow={255,225,90}},
  {id="summer_beach", name="Summer Beach", rarity=SHOP_RARITY.COMMON, group="Seasonal", bonus=true,
    blue={0,170,230}, red={255,110,80}, green={40,200,160}, yellow={255,220,90}},
  {id="harvest", name="Harvest", rarity=SHOP_RARITY.UNCOMMON, group="Seasonal", bonus=true,
    blue={90,100,130}, red={200,80,30}, green={130,140,50}, yellow={240,170,40}},
  {id="first_snow", name="First Snow", rarity=SHOP_RARITY.UNCOMMON, group="Seasonal", bonus=true,
    blue={150,190,240}, red={190,80,100}, green={120,170,160}, yellow={235,225,190}},
  {id="valentine", name="Valentine", rarity=SHOP_RARITY.UNCOMMON, group="Seasonal", bonus=true,
    blue={150,120,220}, red={240,40,90}, green={120,200,160}, yellow={255,200,150}},
  {id="halloween", name="Halloween", rarity=SHOP_RARITY.RARE, group="Seasonal", bonus=true,
    blue={90,60,150}, red={255,110,0}, green={100,200,40}, yellow={255,190,0}},
  {id="christmas", name="Christmas", rarity=SHOP_RARITY.RARE, group="Seasonal", bonus=true,
    blue={40,110,170}, red={210,30,40}, green={20,150,70}, yellow={240,200,60}},
  {id="lunar_new_year", name="Lunar New Year", rarity=SHOP_RARITY.EPIC, group="Seasonal", bonus=true,
    blue={60,90,170}, red={220,30,30}, green={40,150,100}, yellow={255,200,0}},
  {id="deck_red", name="Red Deck", rarity=SHOP_RARITY.COMMON, group="Balatro Decks", bonus=true,
    blue={90,110,160}, red={240,60,50}, green={90,160,120}, yellow={250,190,90}},
  {id="deck_blue", name="Blue Deck", rarity=SHOP_RARITY.COMMON, group="Balatro Decks", bonus=true,
    blue={0,140,255}, red={200,80,110}, green={60,170,190}, yellow={220,220,120}},
  {id="deck_yellow", name="Yellow Deck", rarity=SHOP_RARITY.COMMON, group="Balatro Decks", bonus=true,
    blue={90,120,200}, red={230,110,60}, green={150,190,80}, yellow={255,215,0}},
  {id="deck_green", name="Green Deck", rarity=SHOP_RARITY.UNCOMMON, group="Balatro Decks", bonus=true,
    blue={60,150,150}, red={200,90,70}, green={50,190,90}, yellow={220,220,90}},
  {id="deck_black", name="Black Deck", rarity=SHOP_RARITY.UNCOMMON, group="Balatro Decks", bonus=true,
    blue={60,70,100}, red={170,50,60}, green={60,100,90}, yellow={200,180,120}},
  {id="deck_magic", name="Magic Deck", rarity=SHOP_RARITY.RARE, group="Balatro Decks", bonus=true,
    blue={110,80,220}, red={220,70,140}, green={80,180,180}, yellow={240,200,110}},
  {id="deck_nebula", name="Nebula Deck", rarity=SHOP_RARITY.RARE, group="Balatro Decks", bonus=true,
    blue={60,60,190}, red={200,60,170}, green={60,140,200}, yellow={240,210,130}},
  {id="deck_ghost", name="Ghost Deck", rarity=SHOP_RARITY.EPIC, group="Balatro Decks", bonus=true,
    blue={130,170,220}, red={180,110,170}, green={130,200,190}, yellow={220,230,240}},
  {id="deck_plasma", name="Plasma Deck", rarity=SHOP_RARITY.LEGENDARY, group="Balatro Decks", bonus=true,
    blue={60,130,255}, red={255,70,120}, green={150,90,255}, yellow={255,200,120}},
}

SHOP_COLOR_GROUPS = {"Themes", "Pastels", "Neons", "Dark", "Seasonal", "Balatro Decks"}

SHOP_POLYCHROMATIC = {
  id = "polychromatic",
  name = "Polychromatic",
  rarity = SHOP_RARITY.LEGENDARY,
  description = "Full RGB control over all 4 colors",
}

for _, set in ipairs(SHOP_COLOR_SETS) do
  set.price = rarity_price(BASE_PRICE.color_set, set.rarity)
end
SHOP_POLYCHROMATIC.price = rarity_price(BASE_PRICE.color_set * 2, SHOP_POLYCHROMATIC.rarity)
TAVERN_PALETTES.filter(SHOP_COLOR_SETS)


SHOP_ICON_EFFECTS = {
  {id="foil",        name="Foil",         rarity=SHOP_RARITY.UNCOMMON,
    description="Metallic shimmer on your profile icon",        shader="foil"},
  {id="holographic", name="Holographic",  rarity=SHOP_RARITY.RARE,
    description="Rainbow holographic effect on your icon",      shader="holo"},
  {id="polychrome",  name="Polychrome",   rarity=SHOP_RARITY.EPIC,
    description="Shifting polychrome colors on your icon",      shader="polychrome"},
  {id="negative",    name="Negative",     rarity=SHOP_RARITY.LEGENDARY,
    description="Dark inverted aura around your icon",          shader="negative"},
}

for _, eff in ipairs(SHOP_ICON_EFFECTS) do
  eff.price = rarity_price(BASE_PRICE.icon_effect, eff.rarity)
end


AshCardManager = {
  initialized_profile = nil,
}

function AshCardManager.init()
  if not G or not G.PROFILES or not G.SETTINGS or not G.SETTINGS.profile then return false end

  local prof_id = G.SETTINGS.profile
  if AshCardManager.initialized_profile == prof_id then return true end

  local profile = G.PROFILES[prof_id]
  if not profile then return false end
  if not profile.progression then profile.progression = {} end

  if not profile.progression.owned_color_sets then
    profile.progression.owned_color_sets = {}
  end
  if not profile.progression.poly_colors then
    profile.progression.poly_colors = {
      blue_r=0, blue_g=157, blue_b=255,
      red_r=254, red_g=95, red_b=85,
      green_r=75, green_g=194, green_b=146,
      yellow_r=255, yellow_g=255, yellow_b=0,
    }
  end

  TAVERN_PALETTES.migrate(profile.progression)

  if not profile.progression.owned_icon_effects then
    profile.progression.owned_icon_effects = {}
  end

  AshCardManager.initialized_profile = prof_id
  return true
end

function AshCardManager.owns_color_set(set_id)
  if not AshCardManager.init() then return false end
  local profile = G.PROFILES[G.SETTINGS.profile]
  for _, v in ipairs(profile.progression.owned_color_sets) do
    if v == set_id then return true end
  end
  return false
end

function AshCardManager.owns_all_color_sets()
  if not AshCardManager.init() then return false end
  for _, set in ipairs(SHOP_COLOR_SETS) do
    if not set.bonus and not AshCardManager.owns_color_set(set.id) then return false end
  end
  return true
end

function AshCardManager.owns_icon_effect(effect_id)
  if not AshCardManager.init() then return false end
  local profile = G.PROFILES[G.SETTINGS.profile]
  for _, v in ipairs(profile.progression.owned_icon_effects) do
    if v == effect_id then return true end
  end
  return false
end

function AshCardManager.buy_color_set(set_id)
  if not AshCardManager.init() then return false, "Not initialized" end
  if AshCardManager.owns_color_set(set_id) then return false, "Already owned" end
  local price = 0
  for _, set in ipairs(SHOP_COLOR_SETS) do
    if set.id == set_id then price = set.price; break end
  end
  if set_id == "polychromatic" then price = SHOP_POLYCHROMATIC.price end
  if price <= 0 then return false, "Item not found" end
  if not ShopManager.spend_balacoin(price) then return false, "Insufficient Balacoins" end
  local profile = G.PROFILES[G.SETTINGS.profile]
  table.insert(profile.progression.owned_color_sets, set_id)
  if set_id ~= "polychromatic" then
    pcall(function()
      if AshCardManager.owns_all_color_sets() and not AshCardManager.owns_color_set("polychromatic") then
        table.insert(profile.progression.owned_color_sets, "polychromatic")
        print("[SHOP] Polychromatic auto-unlocked!")
      end
    end)
  end
  if G and G.save_progress then G:save_progress() end
  return true, "Purchased!"
end

function AshCardManager.buy_icon_effect(effect_id)
  if not AshCardManager.init() then return false, "Not initialized" end
  if AshCardManager.owns_icon_effect(effect_id) then return false, "Already owned" end
  local price = 0
  for _, eff in ipairs(SHOP_ICON_EFFECTS) do
    if eff.id == effect_id then price = eff.price; break end
  end
  if price <= 0 then return false, "Item not found" end
  if not ShopManager.spend_balacoin(price) then return false, "Insufficient Balacoins" end
  local profile = G.PROFILES[G.SETTINGS.profile]
  table.insert(profile.progression.owned_icon_effects, effect_id)
  if G and G.save_progress then G:save_progress() end
  return true, "Purchased!"
end

function AshCardManager.equip_color_set(set_id)
  if not AshCardManager.init() then return false end
  if set_id and set_id ~= "none" and not AshCardManager.owns_color_set(set_id) then return false end
  local profile = G.PROFILES[G.SETTINGS.profile]
  profile.progression.equipped_color_set = (set_id == "none") and nil or set_id
  if G and G.save_progress then G:save_progress() end
  return true
end

function AshCardManager.equip_icon_effect(effect_id)
  if not AshCardManager.init() then return false end
  if effect_id and effect_id ~= "none" and not AshCardManager.owns_icon_effect(effect_id) then return false end
  local profile = G.PROFILES[G.SETTINGS.profile]
  profile.progression.equipped_icon_effect = (effect_id == "none") and nil or effect_id
  if G and G.save_progress then G:save_progress() end
  return true
end

function AshCardManager.get_equipped_color_set()
  if not AshCardManager.init() then return nil end
  return G.PROFILES[G.SETTINGS.profile].progression.equipped_color_set
end

function AshCardManager.get_equipped_icon_effect()
  if not AshCardManager.init() then return nil end
  return G.PROFILES[G.SETTINGS.profile].progression.equipped_icon_effect
end

function AshCardManager.get_poly_colors()
  if not AshCardManager.init() then return nil end
  return G.PROFILES[G.SETTINGS.profile].progression.poly_colors
end

function AshCardManager.save_poly_colors(colors)
  if not AshCardManager.init() then return false end
  local profile = G.PROFILES[G.SETTINGS.profile]
  profile.progression.poly_colors = colors
  if G and G.save_progress then G:save_progress() end
  return true
end


function apply_color_set(set_id)
  if not G or not G.C then return end

  local function ic(t,a,b,c) t[1]=a; t[2]=b; t[3]=c; t[4]=1 end
  set_id = TAVERN_PALETTES.resolve(set_id)

  local colors = nil
  if set_id == "polychromatic" then
    local poly = AshCardManager.get_poly_colors()
    if poly then
      colors = {
        blue  = {poly.blue_r,  poly.blue_g,  poly.blue_b},
        red   = {poly.red_r,   poly.red_g,   poly.red_b},
        green = {poly.green_r, poly.green_g, poly.green_b},
        yellow= {poly.yellow_r,poly.yellow_g,poly.yellow_b},
      }
    end
  else
    for _, set in ipairs(SHOP_COLOR_SETS) do
      if set.id == set_id then
        colors = {blue=set.blue, red=set.red, green=set.green, yellow=set.yellow}
        break
      end
    end
  end

  if not colors then return end

  local r,g,b = colors.blue[1]/255, colors.blue[2]/255, colors.blue[3]/255
  ic(G.C.BLUE, r, g, b)
  ic(G.C.CHIPS, r, g, b)
  if G.C.UI_CHIPS then ic(G.C.UI_CHIPS, r, g, b) end

  r,g,b = colors.red[1]/255, colors.red[2]/255, colors.red[3]/255
  ic(G.C.RED, r, g, b)
  ic(G.C.MULT, r, g, b)
  if G.C.XMULT then ic(G.C.XMULT, r, g, b) end
  if G.C.UI_MULT then ic(G.C.UI_MULT, r, g, b) end

  r,g,b = colors.green[1]/255, colors.green[2]/255, colors.green[3]/255
  ic(G.C.GREEN, r, g, b)
  if G.C.CHANCE then ic(G.C.CHANCE, r, g, b) end
  if G.C.PALE_GREEN then ic(G.C.PALE_GREEN, r*0.85, g*0.85, b*0.85) end

  r,g,b = colors.yellow[1]/255, colors.yellow[2]/255, colors.yellow[3]/255
  ic(G.C.YELLOW, r, g, b)
  ic(G.C.GOLD, r, g, b)
  ic(G.C.ORANGE, r, g, b)
  ic(G.C.MONEY, r, g, b)
  if G.C.IMPORTANT then ic(G.C.IMPORTANT, r, g, b) end
  if G.C.FILTER then ic(G.C.FILTER, r, g, b) end

  if G.C.SUITS then
    r,g,b = colors.red[1]/255, colors.red[2]/255, colors.red[3]/255
    ic(G.C.SUITS.Hearts, r, g, b)
    r,g,b = colors.yellow[1]/255, colors.yellow[2]/255, colors.yellow[3]/255
    ic(G.C.SUITS.Diamonds, r, g, b)
    r,g,b = colors.blue[1]/255, colors.blue[2]/255, colors.blue[3]/255
    ic(G.C.SUITS.Spades, r*0.45+0.05, g*0.45+0.05, b*0.45+0.05)
    r,g,b = colors.green[1]/255, colors.green[2]/255, colors.green[3]/255
    ic(G.C.SUITS.Clubs, r*0.5+0.05, g*0.5+0.05, b*0.5+0.05)
  end

  if G.C.SO_2 then
    r,g,b = colors.red[1]/255, colors.red[2]/255, colors.red[3]/255
    ic(G.C.SO_2.Hearts, r*0.97, g*0.23, b*0.18)
    r,g,b = colors.yellow[1]/255, colors.yellow[2]/255, colors.yellow[3]/255
    ic(G.C.SO_2.Diamonds, r, g, b)
    r,g,b = colors.blue[1]/255, colors.blue[2]/255, colors.blue[3]/255
    ic(G.C.SO_2.Spades, r*0.31, g*0.19+0.01, b*0.73)
    r,g,b = colors.green[1]/255, colors.green[2]/255, colors.green[3]/255
    ic(G.C.SO_2.Clubs, r*0.0, g*0.56, b*0.9)
  end
end

function reset_colors_to_default()
  if not G or not G.C then return end
  local function ic(t,a,b,c) t[1]=a; t[2]=b; t[3]=c; t[4]=1 end
  local function ihex(t, hex) local _c = HEX(hex); t[1]=_c[1]; t[2]=_c[2]; t[3]=_c[3]; t[4]=_c[4] end
  ic(G.C.BLUE,      0, 157/255, 1)
  ic(G.C.CHIPS,     0, 157/255, 1)
  if G.C.UI_CHIPS then ic(G.C.UI_CHIPS, 0, 157/255, 1) end
  ic(G.C.RED,       254/255, 95/255, 85/255)
  ic(G.C.MULT,      254/255, 95/255, 85/255)
  if G.C.XMULT then ic(G.C.XMULT, 254/255, 95/255, 85/255) end
  if G.C.UI_MULT then ic(G.C.UI_MULT, 254/255, 95/255, 85/255) end
  ic(G.C.GREEN,     75/255, 194/255, 146/255)
  if G.C.CHANCE then ic(G.C.CHANCE, 75/255, 194/255, 146/255) end
  if G.C.PALE_GREEN then ic(G.C.PALE_GREEN, 86/255, 168/255, 135/255) end
  ic(G.C.YELLOW,    1, 1, 0)
  ihex(G.C.GOLD,      'eac058')
  ihex(G.C.ORANGE,    'fda200')
  ihex(G.C.MONEY,     'f3b958')
  if G.C.IMPORTANT then ihex(G.C.IMPORTANT, 'ff9a00') end
  if G.C.FILTER then ihex(G.C.FILTER, 'ff9a00') end
  if G.C.SUITS then
    ihex(G.C.SUITS.Hearts,   'FE5F55')
    ihex(G.C.SUITS.Diamonds, 'FE5F55')
    ihex(G.C.SUITS.Spades,   '374649')
    ihex(G.C.SUITS.Clubs,    '424e54')
  end
  if G.C.SO_2 then
    ihex(G.C.SO_2.Hearts,   'f83b2f')
    ihex(G.C.SO_2.Diamonds, 'e29000')
    ihex(G.C.SO_2.Spades,   '4f31b9')
    ihex(G.C.SO_2.Clubs,    '008ee6')
  end
end

function auto_apply_color_set()
  pcall(function()
    AshCardManager.init()
    local equipped = AshCardManager.get_equipped_color_set()
    if equipped then
      apply_color_set(equipped)
    end
  end)
end

_G.SHOP_RARITY = SHOP_RARITY
_G.SHOP_COLOR_SETS = SHOP_COLOR_SETS
_G.SHOP_POLYCHROMATIC = SHOP_POLYCHROMATIC
_G.SHOP_ICON_EFFECTS = SHOP_ICON_EFFECTS
_G.AshCardManager = AshCardManager
_G.apply_color_set = apply_color_set
_G.reset_colors_to_default = reset_colors_to_default
_G.auto_apply_color_set = auto_apply_color_set

print("[SHOP_CATALOG] Shop catalog + rarity system loaded!")
