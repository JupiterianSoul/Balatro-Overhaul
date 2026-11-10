local TP = require("functions/shop/tavern_palettes")

local C = {}

C.RARITIES = {
  {key = "common", name = "Common", weight = 55, refund = 8, colour = "WHITE"},
  {key = "uncommon", name = "Uncommon", weight = 27, refund = 20, colour = "GREEN"},
  {key = "rare", name = "Rare", weight = 12, refund = 50, colour = "BLUE"},
  {key = "epic", name = "Epic", weight = 5, refund = 120, colour = "PURPLE"},
  {key = "legendary", name = "Legendary", weight = 1, refund = 300, colour = "GOLD"},
}
C.RARITY_INDEX = {}
for i, r in ipairs(C.RARITIES) do C.RARITY_INDEX[r.key] = i end
C.RARITY_BY_ID = {"common", "uncommon", "rare", "epic", "legendary"}
C.JOKER_RARITY = {"common", "uncommon", "rare", "legendary"}

C.PITY = 40
C.UNOWNED_BIAS = 3

C.TYPES = {
  {key = "palette", name = "Colour Set", plural = "Colour Sets"},
  {key = "felt", name = "Table Felt", plural = "Table Felts"},
  {key = "jimbo", name = "Jimbo Skin", plural = "Jimbo Skins"},
  {key = "portrait", name = "Portrait", plural = "Portraits"},
  {key = "back", name = "Card Back", plural = "Card Backs"},
  {key = "deck", name = "Deck Skin", plural = "Deck Skins"},
  {key = "effect", name = "Icon Effect", plural = "Icon Effects"},
  {key = "flame", name = "Score Flame", plural = "Score Flames"},
  {key = "celebration", name = "Celebration", plural = "Celebrations"},
  {key = "title", name = "Title", plural = "Titles"},
}
C.TYPE_INDEX = {}
for i, t in ipairs(C.TYPES) do C.TYPE_INDEX[t.key] = i end

C.ODDS = {55, 27, 12, 5, 1}
C.ODDS_RARE_PLUS = {0, 0, 70, 24, 6}
C.ODDS_EPIC_PLUS = {0, 0, 0, 80, 20}

C.PACKS = {
  {id = "palette", name = "Palette Pack", types = {"palette", "felt"}, cards = 3, price = 120, art = "palette", booster = {x = 0, y = 1}},
  {id = "palette_jumbo", name = "Jumbo Palette Pack", types = {"palette", "felt"}, cards = 5, price = 200, art = "palette_jumbo", jumbo = true, booster = {x = 0, y = 3}},
  {id = "jester", name = "Jester Pack", types = {"jimbo", "portrait"}, cards = 3, price = 120, art = "jester", booster = {x = 0, y = 8}},
  {id = "jester_jumbo", name = "Jumbo Jester Pack", types = {"jimbo", "portrait"}, cards = 5, price = 200, art = "jester_jumbo", jumbo = true, booster = {x = 2, y = 8}},
  {id = "sleeve", name = "Sleeve Pack", types = {"back", "deck"}, cards = 3, price = 150, art = "sleeve", booster = {x = 0, y = 6}},
  {id = "shine", name = "Shine Pack", types = {"effect", "flame", "celebration"}, cards = 3, price = 150, art = "shine", booster = {x = 0, y = 4}},
  {id = "title", name = "Title Pack", types = {"title"}, cards = 3, price = 100, art = "title", booster = {x = 0, y = 0}},
  {id = "crate", name = "Tavern Crate", cards = 5, price = 500, art = "crate", last = "rare", booster = {x = 2, y = 7}},
  {id = "legend", name = "Legend Crate", cards = 5, price = 1200, art = "legend", last = "epic", pity = true, booster = {x = 3, y = 4}},
}
C.PACK_BY_ID = {}
for _, p in ipairs(C.PACKS) do C.PACK_BY_ID[p.id] = p end

local function rgb(hex)
  return {tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)}
end

local function pal(id, name, rarity, b, r, g, y)
  return {id = id, name = name, rarity = rarity, blue = rgb(b), red = rgb(r), green = rgb(g), yellow = rgb(y)}
end

C.NEW_PALETTES = {
  pal("t_fool", "The Fool", "common", "4f8fd6", "e3574d", "5cbf8a", "f2c14e"),
  pal("t_magician", "The Magician", "common", "3d7ee0", "d9483f", "45b07c", "f0b83a"),
  pal("t_priestess", "High Priestess", "uncommon", "5b6ee8", "c9507a", "4aa3a0", "e8d27a"),
  pal("t_empress", "The Empress", "common", "6a9fe0", "f06a7a", "6cc28a", "f5cf6a"),
  pal("t_emperor", "The Emperor", "uncommon", "2f5fb8", "c0392b", "3e8e5e", "e0a526"),
  pal("t_hierophant", "The Hierophant", "common", "4b78c4", "b9474a", "5a9e74", "dcbc5c"),
  pal("t_lovers", "The Lovers", "uncommon", "6f8ff0", "ff6f91", "7ad1a6", "ffd27f"),
  pal("t_chariot", "The Chariot", "common", "3a86d1", "e0533f", "48b583", "f4b942"),
  pal("t_justice", "Justice", "common", "507cc0", "c94d4d", "5aa37c", "e6c25a"),
  pal("t_hermit", "The Hermit", "uncommon", "40608f", "9e4a3a", "5e7f63", "d9a441"),
  pal("t_wheel", "Wheel of Fortune", "rare", "1fa2ff", "ff4d6d", "2fd38f", "ffd23f"),
  pal("t_strength", "Strength", "common", "4d84d9", "e85d3a", "62b86e", "f7b733"),
  pal("t_hanged", "The Hanged Man", "uncommon", "4a6fa5", "b04a5a", "4f9c8a", "d4b26a"),
  pal("t_death", "Death", "rare", "3b4a8c", "a3243b", "3f6b5a", "c8b38a"),
  pal("t_temperance", "Temperance", "common", "5aa0e0", "e8766a", "6fc7a0", "f2d58a"),
  pal("t_devil", "The Devil", "rare", "3a2f7a", "d6252f", "4a7a3a", "e8a020"),
  pal("t_tower", "The Tower", "uncommon", "355c9e", "e04a24", "52806a", "ffb02e"),
  pal("t_star", "The Star", "rare", "4fb3ff", "ff7aa8", "64e0c0", "fff07a"),
  pal("t_moon", "The Moon", "uncommon", "5466c8", "b85c9e", "4b9fb0", "e6e0a0"),
  pal("t_sun", "The Sun", "rare", "2e9cf0", "ff6b3d", "52c96b", "ffd700"),
  pal("t_judgement", "Judgement", "epic", "2d6cdf", "e2343f", "2fbf71", "ffcc33"),
  pal("t_world", "The World", "legendary", "1e90ff", "ff3860", "23d160", "ffdd57"),
  pal("p_mercury", "Mercury", "common", "6aa6d8", "d97a5a", "79b89a", "e8c98a"),
  pal("p_venus", "Venus", "common", "7a9ee0", "e6806a", "8ac2a0", "f5d08a"),
  pal("p_earth", "Earth", "common", "2f7fd6", "d3553a", "3fa65a", "e9c46a"),
  pal("p_mars", "Mars", "uncommon", "4a6fb3", "d2462a", "6b8f4e", "e89a3c"),
  pal("p_jupiter", "Jupiter", "uncommon", "5f84c6", "c96b45", "8aa67a", "e8b878"),
  pal("p_saturn", "Saturn", "uncommon", "6b8cc9", "c98a5a", "8fb08a", "f0d29a"),
  pal("p_uranus", "Uranus", "common", "4fc0e8", "e07a8a", "6fd6c0", "e8e6a0"),
  pal("p_neptune", "Neptune", "uncommon", "2a5fd6", "c94f6d", "2fa3a0", "a8d8f0"),
  pal("p_pluto", "Pluto", "rare", "6070a0", "a06070", "708a80", "c0b090"),
  pal("p_planet_x", "Planet X", "epic", "3b1fd6", "ff2fa0", "1fd6b0", "f0ff4f"),
  pal("p_ceres", "Ceres", "rare", "7090b0", "b07a6a", "80a090", "d0c0a0"),
  pal("p_eris", "Eris", "epic", "5a4fcf", "e0507a", "4fbfa0", "ffd0f0"),
  pal("j_jimbo", "Jimbo", "common", "009dff", "fe5f55", "4bc292", "fda200"),
  pal("j_cavendish", "Cavendish", "uncommon", "4a9ad6", "d9604a", "7cc26a", "ffe14f"),
  pal("j_gros_michel", "Gros Michel", "common", "5a8fd0", "e0704a", "6ab36a", "f5d84a"),
  pal("j_blueprint", "Blueprint", "rare", "1f6fff", "ff5a5a", "3fcfcf", "cfe8ff"),
  pal("j_brainstorm", "Brainstorm", "rare", "ff6a3d", "e83f6f", "3fc0a0", "ffcf3f"),
  pal("j_baron", "Baron", "epic", "3a4fa8", "b02a3a", "2f7a5a", "f0c040"),
  pal("j_mime", "Mime", "common", "8aa0c8", "c88a9a", "9ac0b0", "e8e0c8"),
  pal("j_showman", "Showman", "uncommon", "3f6fe0", "ff4f6f", "4fdf8f", "ffbf2f"),
  pal("j_vagabond", "Vagabond", "common", "5f7fa0", "a85f4f", "6f8f6f", "c8a86f"),
  pal("j_hiker", "Hiker", "common", "4f8fbf", "cf6f4f", "5faf6f", "efbf5f"),
  pal("j_hologram", "Hologram", "rare", "5fcfff", "ff8fcf", "8fffcf", "fff08f"),
  pal("j_lucky_cat", "Lucky Cat", "uncommon", "4f7fd0", "f04f4f", "4fbf7f", "ffd04f"),
  pal("j_bloodstone", "Bloodstone", "rare", "2f4f8f", "c0102a", "1f6f4f", "d0a040"),
  pal("j_arrowhead", "Arrowhead", "uncommon", "1f5fcf", "cf3f3f", "3f9f6f", "dfbf6f"),
  pal("j_onyx_agate", "Onyx Agate", "uncommon", "3f4f7f", "9f3f5f", "3f6f5f", "bfa07f"),
  pal("j_rough_gem", "Rough Gem", "uncommon", "4f9fdf", "df5f4f", "5fbf7f", "ffaf2f"),
  pal("j_glass", "Glass Joker", "rare", "9fdfff", "ffafbf", "afffdf", "ffffcf"),
  pal("j_steel", "Steel Joker", "common", "6f8faf", "af6f6f", "7f9f8f", "cfcfbf"),
  pal("j_stone", "Stone Joker", "common", "7f8a99", "9a7f7f", "8a998a", "b8b0a0"),
  pal("j_golden", "Golden Joker", "epic", "3f6fbf", "df4f3f", "4fa06f", "ffd700"),
  pal("j_seance", "Seance", "uncommon", "4f5fcf", "bf4f9f", "3f9fbf", "dfcf9f"),
  pal("j_hex", "Hex", "rare", "3f3fbf", "df2f6f", "2fbf9f", "efdf6f"),
  pal("j_ankh", "Ankh", "epic", "2f6fcf", "df5f2f", "2fafaf", "ffcf5f"),
  pal("j_black_hole", "Black Hole", "legendary", "2a1f6f", "8f1f5f", "1f4f6f", "9f8fdf"),
  pal("j_perkeo", "Perkeo", "legendary", "4f8fff", "ff5f9f", "5fffbf", "ffef5f"),
  pal("j_tavern_ale", "Tavern Ale", "common", "4a78b0", "c0603a", "6a9a5a", "e8b040"),
  pal("coral_reef", "Coral Reef", "common", "00a0a0", "ff7f50", "2e8b57", "ffd700"),
  pal("bluebell", "Bluebell", "common", "1c4fa0", "4a90e2", "89c4f4", "cfe8ff"),
  pal("fern", "Fern", "common", "0f6b3e", "22a35a", "6fdc8c", "c6f6d5"),
  pal("honeycomb", "Honeycomb", "common", "8a4b08", "d97706", "f5a524", "fde68a"),
  pal("peony", "Peony", "common", "9c1f4a", "e0457b", "f48fb1", "ffd1e0"),
  pal("mint_chocolate", "Mint Chocolate", "common", "5d4037", "8d6e63", "98ff98", "d7ccc8"),
  pal("brick_sky", "Brick and Sky", "common", "87ceeb", "8b0000", "556b2f", "d2b48c"),
  pal("bumblebee", "Bumblebee", "common", "3a3a3a", "ffc300", "7a7a7a", "ffd60a"),
  pal("wild_berry", "Wild Berry", "uncommon", "6a1b9a", "d81b60", "7cb342", "ff8a65"),
  pal("wisteria", "Wisteria", "uncommon", "4c1d95", "7c3aed", "a78bfa", "ddd6fe"),
  pal("pomegranate", "Pomegranate", "uncommon", "6b0f1a", "b91c1c", "ef4444", "fca5a5"),
  pal("lava_lamp", "Lava Lamp", "uncommon", "ff2d95", "ff8c00", "9d4edd", "ffe066"),
  pal("anglerfish", "Anglerfish", "uncommon", "0b3c49", "e85d04", "0f7173", "f2a65a"),
  pal("scarab", "Scarab", "uncommon", "1b998b", "ed217c", "2d3047", "fffd82"),
  pal("pumpkin_patch", "Pumpkin Patch", "uncommon", "2d6a1f", "ff7518", "6b3e1e", "fff1c1"),
  pal("lavender_field", "Lavender Field", "uncommon", "9d8df1", "6c3483", "c39bd3", "f5b7b1"),
  pal("crossed_wires", "Crossed Wires", "rare", "ff8c00", "00ced1", "8b008b", "c0c0c0"),
  pal("pocket_screen", "Pocket Screen", "rare", "306230", "0f380f", "8bac0f", "9bbc0f"),
  pal("old_monitor", "Old Monitor", "rare", "00aaaa", "aa00aa", "00aa00", "aa5500"),
  pal("fire_and_ice", "Fire and Ice", "rare", "66d9ff", "ff3300", "c0f0ff", "ff9933"),
  pal("fruit_punch", "Fruit Punch", "rare", "ff8fab", "ffb703", "8ecae6", "219ebc"),
  pal("bubble_tea", "Bubble Tea", "rare", "8e7cc3", "a0522d", "f5e6c8", "2b1d14"),
  pal("sunrise", "Sunrise", "epic", "ffb4a2", "ff7f50", "ffd166", "6d597a"),
  pal("lime_twist", "Lime Twist", "epic", "2b9348", "c5f018", "1b1b3a", "f7f7f7"),
  pal("ruby_tide", "Ruby Tide", "epic", "03045e", "d00000", "00b4d8", "ffd6a5"),
  pal("arcade_cabinet", "Arcade Cabinet", "epic", "5b2a86", "ff2a2a", "1a1a2e", "ffc400"),
  pal("pop_art", "Pop Art", "legendary", "1fb5ff", "ff2e63", "202020", "fff200"),
  pal("jungle_neon", "Jungle Neon", "legendary", "0b3d0b", "ff00ff", "ff6700", "00ff7f"),
  pal("jupiter_bubblegum", "Bubblegum", "legendary", "00c2ff", "ff8add", "00ed88", "8789ff"),
}

C.NEW_EFFECTS = {
  {id = "hologram", name = "Hologram", rarity = "rare", steps = {"tshine_scan"}},
  {id = "voucher", name = "Voucher Gleam", rarity = "uncommon", steps = {"tshine_gleam"}},
  {id = "booster", name = "Booster Shine", rarity = "uncommon", steps = {"tshine_sweep"}},
  {id = "gold", name = "Gilded Gleam", rarity = "rare", steps = {"tshine_gold"}},
  {id = "foil_holo", name = "Holo Foil", rarity = "epic", steps = {"tshine_glitter"}},
  {id = "negative_foil", name = "Negative Foil", rarity = "legendary", steps = {"tshine_void"}},
  {id = "poly_holo", name = "Prism", rarity = "legendary", steps = {"tshine_prism"}},
  {id = "gold_foil", name = "Gilded", rarity = "epic", steps = {"tshine_molten"}},
  {id = "voucher_holo", name = "Showcase", rarity = "rare", steps = {"tshine_spotlight"}},
  {id = "booster_poly", name = "Fresh Pack", rarity = "epic", steps = {"tshine_wave"}},
  {id = "negative_shine", name = "Dark Shine", rarity = "rare", steps = {"tshine_noir"}},
  {id = "hologram_poly", name = "Spectral Glow", rarity = "legendary", steps = {"tshine_ghost"}},
}

local function felt(id, name, rarity, c1, c2, contrast)
  return {id = id, name = name, rarity = rarity, colour = c1, special = c2, contrast = contrast or 1}
end

C.FELTS = {
  felt("casino", "Casino Green", "common", "2e7d4f", "1f5a39"),
  felt("royal", "Royal Blue", "common", "2f5fa8", "1f3f78"),
  felt("crimson", "Crimson", "common", "a83232", "6f1f1f"),
  felt("midnight", "Midnight", "common", "1f2a4a", "131a30"),
  felt("plum", "Plum", "common", "5f2f6f", "3f1f4a"),
  felt("teal", "Teal", "common", "1f7a7a", "135050"),
  felt("amber", "Amber", "common", "b0702a", "70461a"),
  felt("rose", "Rose", "common", "b0506f", "703048"),
  felt("slate", "Slate", "common", "4a5a6a", "303a46"),
  felt("mint", "Mint", "common", "4fa88a", "33705a"),
  felt("coral", "Coral", "uncommon", "d06a5a", "8a4038"),
  felt("indigo", "Indigo", "uncommon", "3a3a9a", "24246a"),
  felt("olive", "Olive", "common", "6a7a3a", "454f24"),
  felt("copper", "Copper", "uncommon", "a8603a", "6a3a22"),
  felt("charcoal", "Charcoal", "common", "2f3236", "1c1e21"),
  felt("wine", "Wine", "uncommon", "6a1f3a", "451326"),
  felt("ocean", "Ocean", "uncommon", "1f5f9a", "133e66"),
  felt("sky", "Sky", "uncommon", "4f9fdf", "2f6a9f"),
  felt("sand", "Sand", "common", "b09a6a", "7a6a46"),
  felt("lavender", "Lavender", "uncommon", "8a7ac8", "5a4f8a"),
  felt("forest", "Forest", "common", "2a5a2f", "1a3a1e"),
  felt("cherry", "Cherry", "uncommon", "c02a4a", "801a30"),
  felt("gold_leaf", "Gold Leaf", "rare", "c8a03a", "8a6a1f", 1.5),
  felt("ice", "Ice", "rare", "8acfef", "4f8aaf", 1.5),
  felt("jade", "Jade", "rare", "2fa070", "1a6a48", 1.5),
  felt("ruby", "Ruby", "rare", "b01f3a", "6a0f22", 1.5),
  felt("sapphire", "Sapphire", "rare", "1f4fbf", "0f2f7a", 1.5),
  felt("amethyst", "Amethyst", "rare", "7a3fbf", "4a227a", 1.5),
  felt("topaz", "Topaz", "rare", "e09a2a", "9a6018", 1.5),
  felt("obsidian", "Obsidian", "epic", "16141f", "3a2f5f", 2),
  felt("pearl", "Pearl", "epic", "d8d0e0", "a098b0", 1.5),
  felt("neon_pink", "Neon Pink", "epic", "ff2f9f", "6f0f4a", 2),
  felt("neon_green", "Neon Green", "epic", "2fff7f", "0f6a33", 2),
  felt("sunset", "Sunset", "epic", "ff7a3a", "7a1f5a", 2),
  felt("aurora", "Aurora", "legendary", "2fdfaf", "5a2fbf", 2.5),
  felt("nebula", "Nebula", "legendary", "6a2fbf", "df3f8f", 2.5),
  felt("inferno", "Inferno", "legendary", "ff4f1f", "6a0f0f", 3),
  felt("abyss", "Abyss", "epic", "0f1f3a", "1f6a8a", 2),
  felt("tavern_wood", "Tavern Wood", "uncommon", "6a4a2f", "40291a"),
  felt("prism", "Prism", "legendary", "3f8fff", "ff3f8f", 3),
}

local function flame(id, name, rarity, c1, c2, m1, m2)
  return {id = id, name = name, rarity = rarity, chips = {c1, c2}, mult = {m1 or c1, m2 or c2}}
end

C.FLAMES = {
  flame("ember", "Ember", "common", "ff9a3c", "ffd08a"),
  flame("mint", "Mint", "common", "4bc292", "b8f0d8"),
  flame("violet", "Violet", "common", "8867a5", "d0b8ef"),
  flame("ice", "Ice", "common", "8bd3ff", "e8f8ff"),
  flame("rose", "Rose", "common", "ff6f91", "ffd0dc"),
  flame("lime", "Lime", "common", "9fdf2f", "e8ffb0"),
  flame("sunflower", "Sunflower", "common", "ffcf2f", "fff0a0"),
  flame("ocean", "Ocean", "common", "1f8fdf", "a0d8ff"),
  flame("copper", "Copper", "uncommon", "c87a3a", "f0c090"),
  flame("teal", "Teal", "uncommon", "1fbfbf", "a8f0f0"),
  flame("crimson", "Crimson", "uncommon", "d01f3a", "ff9aa8"),
  flame("lavender", "Lavender", "uncommon", "a890e8", "ece0ff"),
  flame("gold", "Gold", "uncommon", "eac058", "fff2c0"),
  flame("silver", "Silver", "uncommon", "b8c0cc", "ffffff"),
  flame("toxic", "Toxic", "uncommon", "6fff2f", "dfff9f"),
  flame("candy", "Candy", "uncommon", "ff6fcf", "8fdfff", "8fdfff", "ff6fcf"),
  flame("split", "Split", "rare", "009dff", "a0dcff", "fe5f55", "ffc0b8"),
  flame("swap", "Swapped", "rare", "fe5f55", "ffc0b8", "009dff", "a0dcff"),
  flame("emerald", "Emerald", "rare", "1fbf5f", "9fffbf"),
  flame("amethyst", "Amethyst", "rare", "8f3fdf", "dfb0ff"),
  flame("sunset", "Sunset", "rare", "ff6f3f", "ffd06f", "df3f8f", "ffb0d8"),
  flame("aurora", "Aurora", "rare", "2fdfaf", "bf8fff"),
  flame("shadow", "Shadow", "epic", "3c2f4f", "8f7fbf"),
  flame("solar", "Solar", "epic", "ff8f00", "ffff8f"),
  flame("frost", "Frost", "epic", "6fcfff", "ffffff", "afdfff", "ffffff"),
  flame("blood", "Blood Moon", "epic", "9f0f1f", "ff6f4f"),
  flame("spectral", "Spectral", "epic", "4f6fff", "8fffef"),
  flame("void", "Void", "legendary", "1f0f3f", "bf3fff"),
  flame("rainbow", "Rainbow", "legendary", "ff3f6f", "3fffcf", "3f8fff", "ffef3f"),
  flame("jimbo", "Jimbo", "legendary", "fda200", "009dff", "fe5f55", "fda200"),
}

C.CELEBRATIONS = {
  {id = "confetti", name = "Confetti", rarity = "common", colours = {"fe5f55", "009dff", "4bc292", "fda200"}},
  {id = "gold_rain", name = "Gold Rain", rarity = "uncommon", colours = {"eac058", "fda200", "fff2c0"}},
  {id = "ruby", name = "Ruby Shower", rarity = "uncommon", colours = {"fe5f55", "ff9aa8", "a3243b"}},
  {id = "sapphire", name = "Sapphire Shower", rarity = "uncommon", colours = {"009dff", "a0dcff", "1f4fbf"}},
  {id = "emerald", name = "Emerald Shower", rarity = "uncommon", colours = {"4bc292", "9fffbf", "1f6a48"}},
  {id = "tarot", name = "Arcana", rarity = "rare", colours = {"a782d1", "dfb0ff", "fff2c0"}},
  {id = "planet", name = "Celestial", rarity = "rare", colours = {"13afce", "8fdfff", "ffffff"}},
  {id = "spectral", name = "Spectral", rarity = "rare", colours = {"4584fa", "8fffef", "ffffff"}},
  {id = "neon", name = "Neon", rarity = "epic", colours = {"ff2f9f", "2fff7f", "2fcfff", "ffef2f"}},
  {id = "shadow", name = "Shadow", rarity = "epic", colours = {"3c2f4f", "8f7fbf", "16141f"}},
  {id = "rainbow", name = "Rainbow", rarity = "legendary", colours = {"ff3f6f", "ff9f3f", "ffef3f", "3fff8f", "3f8fff", "bf3fff"}},
  {id = "jimbo", name = "Jimbo", rarity = "legendary", colours = {"fda200", "009dff", "fe5f55", "4bc292", "ffffff"}},
}

local function title(id, name, rarity) return {id = id, name = name, rarity = rarity} end

C.NEW_TITLES = {
  title("tv_regular", "Tavern Regular", "common"), title("tv_barfly", "Barfly", "common"),
  title("tv_card_counter", "Card Counter", "common"), title("tv_high_card", "High Card", "common"),
  title("tv_small_blind", "Small Blind", "common"), title("tv_big_blind", "Big Blind", "common"),
  title("tv_pair_up", "Pair Up", "common"), title("tv_two_pair", "Two Pair Tycoon", "common"),
  title("tv_straight_talk", "Straight Talker", "common"), title("tv_flush_funds", "Flush With Cash", "common"),
  title("tv_discarder", "Serial Discarder", "common"), title("tv_rerolled", "Rerolled", "common"),
  title("tv_penny", "Penny Pincher", "common"), title("tv_interest", "Five Dollar Saver", "common"),
  title("tv_shuffler", "The Shuffler", "common"), title("tv_tourist", "Ante Tourist", "common"),
  title("tv_chip_in", "Chip In", "common"), title("tv_plus_mult", "Plus Mult", "common"),
  title("tv_jester", "Court Jester", "common"), title("tv_rookie", "Rookie Dealer", "common"),
  title("tv_pocket_aces", "Pocket Aces", "common"), title("tv_wild_card", "Wild Card", "common"),
  title("tv_bonus", "Bonus Card", "common"), title("tv_stone_cold", "Stone Cold", "common"),
  title("tv_gold_digger", "Gold Digger", "common"), title("tv_steel_nerves", "Steel Nerves", "common"),
  title("tv_glass_heart", "Glass Heart", "common"), title("tv_lucky_seven", "Lucky Seven", "common"),
  title("tv_full_house", "Full House", "uncommon"), title("tv_four_kind", "Four of a Kind", "uncommon"),
  title("tv_x_mult", "Times Mult", "uncommon"), title("tv_planet_hopper", "Planet Hopper", "uncommon"),
  title("tv_tarot_reader", "Tarot Reader", "uncommon"), title("tv_spectral", "Spectral Guest", "uncommon"),
  title("tv_voucher", "Voucher Hoarder", "uncommon"), title("tv_booster", "Pack Rat", "uncommon"),
  title("tv_crate_cracker", "Crate Cracker", "uncommon"), title("tv_sleeve_ace", "Ace Up The Sleeve", "uncommon"),
  title("tv_hand_size", "Big Hands", "uncommon"), title("tv_seal", "Sealed Deal", "uncommon"),
  title("tv_red_seal", "Red Seal", "uncommon"), title("tv_blue_seal", "Blue Seal", "uncommon"),
  title("tv_purple_seal", "Purple Seal", "uncommon"), title("tv_gold_seal", "Gold Seal", "uncommon"),
  title("tv_boss_hunter", "Boss Hunter", "uncommon"), title("tv_the_wall", "Over The Wall", "uncommon"),
  title("tv_needle", "Threaded The Needle", "uncommon"), title("tv_the_hook", "Off The Hook", "uncommon"),
  title("tv_night_owl", "Night Owl", "uncommon"), title("tv_early_bird", "Early Bird", "uncommon"),
  title("tv_bartender", "Bartender", "uncommon"), title("tv_dealer", "House Dealer", "uncommon"),
  title("tv_royal_flush", "Royal Flush", "rare"), title("tv_straight_flush", "Straight Flush", "rare"),
  title("tv_five_kind", "Five of a Kind", "rare"), title("tv_flush_five", "Flush Five", "rare"),
  title("tv_flush_house", "Flush House", "rare"), title("tv_black_hole", "Event Horizon", "rare"),
  title("tv_the_soul", "The Soul", "rare"), title("tv_negative", "Negative Thinker", "rare"),
  title("tv_polychrome", "Polychromatic", "rare"), title("tv_holo", "Holographic", "rare"),
  title("tv_foil", "Foiled", "rare"), title("tv_blueprint", "Blueprinter", "rare"),
  title("tv_brainstorm", "Brainstormer", "rare"), title("tv_cavendish", "Top Banana", "rare"),
  title("tv_eternal", "Eternal Sticker", "rare"), title("tv_perishable", "Perishable", "rare"),
  title("tv_rental", "Rental Agreement", "rare"), title("tv_showman", "The Showman", "rare"),
  title("tv_ante_eight", "Ante Eight", "epic"), title("tv_gold_stake", "Gold Staker", "epic"),
  title("tv_naneinf", "Naneinf", "epic"), title("tv_endless", "Endless", "epic"),
  title("tv_card_sharp", "Card Sharp", "epic"), title("tv_high_roller", "High Stakes", "epic"),
  title("tv_mime", "The Mime", "epic"), title("tv_baron", "The Baron", "epic"),
  title("tv_perkeo", "Perkeo's Friend", "epic"), title("tv_triboulet", "Triboulet's Heir", "epic"),
  title("tv_yorick", "Alas Poor Yorick", "epic"), title("tv_chicot", "Chicot's Rival", "epic"),
  title("tv_canio", "Canio's Pupil", "epic"), title("tv_tavern_keeper", "Tavern Keeper", "epic"),
  title("tv_jimbos_best", "Jimbo's Best Friend", "legendary"), title("tv_the_house", "The House", "legendary"),
  title("tv_infinite", "Infinite Mult", "legendary"), title("tv_legend_crate", "Crate Legend", "legendary"),
  title("tv_one_in_a_million", "One In A Million", "legendary"), title("tv_the_dealer", "The Dealer", "legendary"),
  title("tv_wheel", "Nope", "uncommon"), title("tv_oops", "Oops All Sixes", "rare"),
  title("tv_hanging_chad", "Hanging Chad", "common"), title("tv_burnt", "Burnt Joker", "uncommon"),
  title("tv_mr_bones", "Saved By Mr. Bones", "rare"), title("tv_matador", "The Matador", "uncommon"),
  title("tv_hack", "The Hack", "common"), title("tv_juggler", "Juggler", "common"),
  title("tv_drunkard", "Drunkard", "common"), title("tv_merry_andy", "Merry Andy", "uncommon"),
  title("tv_stuntman", "Stuntman", "rare"), title("tv_invisible", "Invisible", "epic"),
}

C.SHOP_TITLE_RARITY = {
  the_collector = "uncommon", high_roller = "uncommon", the_legend = "epic", card_shark = "rare",
  luck_master = "rare", joker_king = "epic", chip_master = "rare", mult_king = "rare",
  void_walker = "epic", star_child = "epic", omega = "legendary", alpha = "legendary",
  eternal = "legendary", phantom = "epic", blaze = "rare", frost = "rare", shadow = "epic",
  thunder = "epic", cosmos = "legendary", nebula = "epic",
}

C.BACK_THEMES = {
  "tavern", "dragon", "moon", "sun", "ocean_waves", "oak_leaves", "roses", "skulls", "clockwork", "crown",
  "chess", "dice", "coins", "stars", "lightning", "flames", "snowflakes", "cherry_blossom", "peacock", "butterflies",
  "mushrooms", "candy", "circus_tent", "compass", "anchor", "castle", "lion", "owl", "cat", "fox",
  "koi_fish", "tiger", "lotus", "crystal", "eye", "hourglass", "key", "music_notes", "rocket", "spider_web",
}

C.FINISHES = {
  {key = "", name = "", shader = nil, step = 0},
  {key = "foil", name = "Foil", shader = "foil", rarity = "uncommon"},
  {key = "holo", name = "Holo", shader = "holo", rarity = "rare"},
  {key = "poly", name = "Polychrome", shader = "polychrome", rarity = "epic"},
  {key = "negative", name = "Negative", shader = "negative", rarity = "legendary"},
}

C.SHOP_DECKS = {}

local function title_case(s)
  return (s:gsub("_", " "):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end
C.title_case = title_case

local function add(list, by_id, item)
  if by_id[item.id] then return end
  list[#list + 1] = item
  by_id[item.id] = item
end

function C.build(env)
  env = env or {}
  local list, by_id = {}, {}
  for _, s in ipairs(env.color_sets or {}) do
    local rk = TP.KEEP[s.id] or s.rarity and C.RARITY_BY_ID[s.rarity.id or 1] or s.rarity_key or "common"
    add(list, by_id, {id = "palette:" .. s.id, type = "palette", key = s.id, name = s.name, rarity = rk})
  end
  if env.polychromatic then
    add(list, by_id, {id = "palette:polychromatic", type = "palette", key = "polychromatic", name = "Polychromatic", rarity = "legendary"})
  end
  for _, s in ipairs(C.NEW_PALETTES) do
    if TP.kept(s.id) then
      add(list, by_id, {id = "palette:" .. s.id, type = "palette", key = s.id, name = s.name, rarity = TP.KEEP[s.id] or s.rarity, def = s})
    end
  end
  for _, f in ipairs(C.FELTS) do
    add(list, by_id, {id = "felt:" .. f.id, type = "felt", key = f.id, name = f.name, rarity = f.rarity, def = f})
  end
  for _, j in ipairs(env.jokers or {}) do
    add(list, by_id, {id = "jimbo:" .. j.key, type = "jimbo", key = j.key, name = j.name or j.key, rarity = C.JOKER_RARITY[j.rarity or 1] or "common", pos = j.pos, atlas = j.atlas})
  end
  for i, p in ipairs(env.portraits or {}) do
    add(list, by_id, {id = "portrait:" .. p.id, type = "portrait", key = p.id, name = p.name or title_case(p.id), rarity = p.rarity or "common", pos = p.pos or {x = (i - 1) % 10, y = math.floor((i - 1) / 10)}})
  end
  for i, b in ipairs(env.backs or {}) do
    local base = b.rarity or ((i % 3 == 0) and "uncommon" or "common")
    for _, f in ipairs(C.FINISHES) do
      local id = f.key == "" and b.id or (b.id .. "_" .. f.key)
      local nm = b.name or title_case(b.id)
      add(list, by_id, {id = "back:" .. id, type = "back", key = id, base = b.id, finish = f.shader, name = f.key == "" and nm or (nm .. " " .. f.name),
        rarity = f.rarity or base, atlas = b.atlas, pos = b.pos or {x = (i - 1) % 10, y = math.floor((i - 1) / 10)}})
    end
  end
  for key, rk in pairs(C.SHOP_DECKS) do
    if not env.decks or env.decks[key] then
      add(list, by_id, {id = "deck:" .. key, type = "deck", key = key, name = env.decks and env.decks[key] or key, rarity = rk})
    end
  end
  for _, e in ipairs(env.effects or {}) do
    local rk = e.rarity and C.RARITY_BY_ID[e.rarity.id or 1] or "common"
    add(list, by_id, {id = "effect:" .. e.id, type = "effect", key = e.id, name = e.name, rarity = rk})
  end
  for _, e in ipairs(C.NEW_EFFECTS) do
    add(list, by_id, {id = "effect:" .. e.id, type = "effect", key = e.id, name = e.name, rarity = e.rarity, def = e})
  end
  for _, f in ipairs(C.FLAMES) do
    add(list, by_id, {id = "flame:" .. f.id, type = "flame", key = f.id, name = f.name, rarity = f.rarity, def = f})
  end
  for _, c in ipairs(C.CELEBRATIONS) do
    add(list, by_id, {id = "celebration:" .. c.id, type = "celebration", key = c.id, name = c.name, rarity = c.rarity, def = c})
  end
  for _, t in ipairs(env.titles or {}) do
    if t.unlock_type == "shop" then
      add(list, by_id, {id = "title:" .. t.id, type = "title", key = t.id, name = t.name, rarity = C.SHOP_TITLE_RARITY[t.id] or "rare"})
    end
  end
  for _, t in ipairs(C.NEW_TITLES) do
    add(list, by_id, {id = "title:" .. t.id, type = "title", key = t.id, name = t.name, rarity = t.rarity})
  end
  table.sort(list, function(a, b)
    local ta, tb = C.TYPE_INDEX[a.type] or 99, C.TYPE_INDEX[b.type] or 99
    if ta ~= tb then return ta < tb end
    local ra, rb = C.RARITY_INDEX[a.rarity] or 1, C.RARITY_INDEX[b.rarity] or 1
    if ra ~= rb then return ra < rb end
    return a.name < b.name
  end)
  return list, by_id
end

function C.pack_odds(pack, slot)
  if pack.last and slot == pack.cards then
    return pack.last == "epic" and C.ODDS_EPIC_PLUS or C.ODDS_RARE_PLUS
  end
  return C.ODDS
end

function C.pool_for(pack, list)
  local allow
  if pack.types then
    allow = {}
    for _, t in ipairs(pack.types) do allow[t] = true end
  end
  local by_rarity = {}
  for _, r in ipairs(C.RARITIES) do by_rarity[r.key] = {} end
  for _, it in ipairs(list) do
    if (not allow or allow[it.type]) and not it.no_pack then
      local b = by_rarity[it.rarity]
      if b then b[#b + 1] = it end
    end
  end
  return by_rarity
end

function C.roll_rarity(rand, odds, by_rarity)
  local total = 0
  for i, w in ipairs(odds) do
    if #by_rarity[C.RARITIES[i].key] > 0 then total = total + w end
  end
  if total <= 0 then
    for i = #C.RARITIES, 1, -1 do
      if #by_rarity[C.RARITIES[i].key] > 0 then return C.RARITIES[i].key end
    end
    return nil
  end
  local x = rand() * total
  for i, w in ipairs(odds) do
    local k = C.RARITIES[i].key
    if #by_rarity[k] > 0 and w > 0 then
      if x < w then return k end
      x = x - w
    end
  end
  for i = #odds, 1, -1 do
    local k = C.RARITIES[i].key
    if odds[i] > 0 and #by_rarity[k] > 0 then return k end
  end
  return nil
end

function C.roll_item(rand, pool, owned, taken)
  local total = 0
  local weights = {}
  for i, it in ipairs(pool) do
    local w = (taken and taken[it.id]) and 0 or ((owned and owned(it)) and 1 or C.UNOWNED_BIAS)
    weights[i] = w
    total = total + w
  end
  if total <= 0 then return pool[math.min(#pool, math.floor(rand() * #pool) + 1)] end
  local x = rand() * total
  for i, it in ipairs(pool) do
    if x < weights[i] then return it end
    x = x - weights[i]
  end
  return pool[#pool]
end

function C.roll_pack(pack, list, rand, owned, state)
  state = state or {}
  local by_rarity = C.pool_for(pack, list)
  local out, taken = {}, {}
  for slot = 1, pack.cards do
    local odds = C.pack_odds(pack, slot)
    local rk
    if pack.pity and (state.since_legendary or 0) + 1 >= C.PITY and #by_rarity.legendary > 0 then
      rk = "legendary"
    else
      rk = C.roll_rarity(rand, odds, by_rarity)
    end
    if not rk then break end
    local it = C.roll_item(rand, by_rarity[rk], owned, taken)
    taken[it.id] = true
    if it.rarity == "legendary" then state.since_legendary = 0 else state.since_legendary = (state.since_legendary or 0) + 1 end
    out[#out + 1] = it
  end
  return out, state
end

function C.refund(rarity)
  local r = C.RARITIES[C.RARITY_INDEX[rarity] or 1]
  return r and r.refund or 0
end

return C
