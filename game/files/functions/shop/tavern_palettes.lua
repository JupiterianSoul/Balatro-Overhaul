local P = {}

P.KEEP = {
  monochrome = "common", midnight = "common", jade = "common", royal = "common", steampunk = "common", p_saturn = "common",
  p_neptune = "uncommon", halloween = "uncommon", cosmic = "uncommon", inferno = "uncommon", deck_nebula = "uncommon", electric_lime = "uncommon",
  toxic = "rare", blacklight = "rare", j_hologram = "rare", j_brainstorm = "rare", glowstick = "rare", ultraviolet = "rare",
  deck_plasma = "epic", obsidian = "epic", supernova = "epic",
  void = "legendary", prismatic = "legendary",
  coral_reef = "common", bluebell = "common", fern = "common", honeycomb = "common", peony = "common", mint_chocolate = "common", brick_sky = "common", bumblebee = "common",
  wild_berry = "uncommon", wisteria = "uncommon", pomegranate = "uncommon", lava_lamp = "uncommon", anglerfish = "uncommon", scarab = "uncommon", pumpkin_patch = "uncommon", lavender_field = "uncommon",
  crossed_wires = "rare", pocket_screen = "rare", old_monitor = "rare", fire_and_ice = "rare", fruit_punch = "rare", bubble_tea = "rare",
  sunrise = "epic", lime_twist = "epic", ruby_tide = "epic", arcade_cabinet = "epic",
  pop_art = "legendary", jungle_neon = "legendary", jupiter_bubblegum = "legendary",
}

P.ALIAS = {
  abyss = "midnight", arcade = "prismatic", arctic = "p_neptune", aurora = "j_hologram",
  autumn = "steampunk", baby_blue = "p_saturn", bloodmoon = "inferno", bubblegum = "j_hologram",
  candy = "j_hologram", charcoal = "midnight", christmas = "jade", circus = "supernova",
  coral = "j_hologram", cotton_candy = "j_hologram", cyberpunk = "electric_lime", deck_black = "midnight",
  deck_blue = "p_neptune", deck_ghost = "monochrome", deck_green = "jade", deck_magic = "deck_nebula",
  deck_red = "p_saturn", deck_yellow = "halloween", deep_sea = "void", desert = "p_saturn",
  dreamy = "j_hologram", dusk = "midnight", eclipse = "midnight", ember = "inferno",
  ethereal = "j_hologram", fairy_tale = "j_hologram", first_snow = "p_saturn", forest = "jade",
  galaxy = "deck_nebula", glacier = "p_neptune", gothic = "midnight", harvest = "steampunk",
  hot_pink = "royal", j_ankh = "supernova", j_arrowhead = "p_saturn", j_baron = "midnight",
  j_black_hole = "void", j_bloodstone = "midnight", j_blueprint = "p_neptune", j_cavendish = "jade",
  j_glass = "j_hologram", j_golden = "supernova", j_gros_michel = "p_saturn", j_hex = "supernova",
  j_hiker = "p_saturn", j_jimbo = "supernova", j_lucky_cat = "supernova", j_mime = "monochrome",
  j_onyx_agate = "midnight", j_perkeo = "j_hologram", j_rough_gem = "p_saturn", j_seance = "deck_nebula",
  j_showman = "supernova", j_steel = "p_saturn", j_stone = "monochrome", j_tavern_ale = "p_saturn",
  j_vagabond = "p_saturn", jungle = "jade", laser = "electric_lime", lavender = "p_saturn",
  lilac = "p_saturn", lunar_new_year = "supernova", macaron = "j_hologram", matcha = "p_saturn",
  mint = "j_hologram", neon = "electric_lime", neon_nights = "prismatic", nightshade = "midnight",
  noir = "midnight", ocean = "j_hologram", p_ceres = "p_saturn", p_earth = "p_saturn",
  p_eris = "p_neptune", p_jupiter = "p_saturn", p_mars = "p_saturn", p_mercury = "p_saturn",
  p_planet_x = "blacklight", p_pluto = "p_saturn", p_uranus = "j_hologram", p_venus = "p_saturn",
  pastel = "j_hologram", peach = "p_saturn", phantom = "void", pirate = "midnight",
  raven = "midnight", retro = "electric_lime", sakura = "p_saturn", shadow = "midnight",
  slate = "p_saturn", solar = "halloween", sorbet = "j_hologram", spring_bloom = "j_hologram",
  summer_beach = "j_hologram", sunset = "cosmic", synthwave = "ultraviolet", t_chariot = "p_saturn",
  t_death = "midnight", t_devil = "inferno", t_emperor = "supernova", t_empress = "p_saturn",
  t_fool = "p_saturn", t_hanged = "p_saturn", t_hermit = "p_saturn", t_hierophant = "p_saturn",
  t_judgement = "supernova", t_justice = "p_saturn", t_lovers = "j_hologram", t_magician = "supernova",
  t_moon = "deck_nebula", t_priestess = "p_neptune", t_star = "j_hologram", t_strength = "halloween",
  t_sun = "halloween", t_temperance = "p_saturn", t_tower = "inferno", t_wheel = "j_hologram",
  t_world = "prismatic", tropical = "electric_lime", valentine = "p_saturn", vaporwave = "j_hologram",
  vintage = "steampunk", volcanic = "inferno", winter = "p_neptune",
}

function P.resolve(id)
  if id == nil or id == "polychromatic" then return id end
  return P.ALIAS[id] or id
end

function P.kept(id)
  return id == "polychromatic" or P.KEEP[id] ~= nil
end

function P.filter(list)
  if type(list) ~= "table" then return list end
  for i = #list, 1, -1 do
    if not P.kept(list[i].id) then table.remove(list, i) end
  end
  return list
end

function P.migrate(pr)
  if type(pr) ~= "table" then return false end
  local changed = false
  local owned = pr.owned_color_sets
  if type(owned) == "table" then
    local have = {}
    for _, v in ipairs(owned) do have[v] = true end
    for i = 1, #owned do
      local to = P.ALIAS[owned[i]]
      if to and not have[to] then
        owned[#owned + 1] = to
        have[to] = true
        changed = true
      end
    end
    owned._set = nil
  end
  local to = P.ALIAS[pr.equipped_color_set or ""]
  if to then
    pr.equipped_color_set = to
    changed = true
  end
  return changed
end

TAVERN_PALETTES = P
return P
