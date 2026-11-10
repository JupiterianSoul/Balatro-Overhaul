-- ============================================
-- ACHIEVEMENT DEFINITIONS for Balatro v10.0
-- 85 achievements with safe unlock conditions
-- PROTOCOL: Full null-safety, no raw global access
-- ============================================

ACHIEVEMENT_DEFINITIONS = {}

-- ============================================
-- HELPER FUNCTION
-- ============================================

local function add_achievement(data)
    if not data then return end
    if not data.id then return end
    table.insert(ACHIEVEMENT_DEFINITIONS, data)
end

-- ============================================
-- CATEGORY: PROGRESSION (15 achievements)
-- ============================================

add_achievement({
    id = "ante_1",
    name = "First Steps",
    description = "Complete Ante 1",
    category = "Progression",
    rarity = "Common",
    order = 1,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_ante_1", name = "Beginner Badge", icon = "badge_bronze"}
})

add_achievement({
    id = "ante_4",
    name = "Getting Serious",
    description = "Complete Ante 4",
    category = "Progression",
    rarity = "Common",
    order = 2,
    is_tracked = true,
    progress_required = 4,
    reward_type = "badge",
    reward_data = {id = "badge_ante_4", name = "Explorer Badge", icon = "badge_bronze"}
})

add_achievement({
    id = "ante_5",
    name = "Ante Explorer",
    description = "Reach Ante 5",
    category = "Progression",
    rarity = "Common",
    order = 3,
    is_tracked = true,
    progress_required = 5,
    reward_type = "badge",
    reward_data = {id = "badge_ante_5", name = "Bronze Medal", icon = "badge_bronze"}
})

add_achievement({
    id = "ante_8",
    name = "The Boss",
    description = "Complete Ante 8",
    category = "Progression",
    rarity = "Rare",
    order = 4,
    is_tracked = true,
    progress_required = 8,
    reward_type = "title",
    reward_data = {id = "title_veteran", name = "Veteran"}
})

add_achievement({
    id = "ante_10",
    name = "Ante Master",
    description = "Reach Ante 10",
    category = "Progression",
    rarity = "Rare",
    order = 5,
    is_tracked = true,
    progress_required = 10,
    reward_type = "cosmetic",
    reward_data = {id = "back_gold", type = "card_back", name = "Golden Card Back"}
})

add_achievement({
    id = "ante_12",
    name = "Legendary",
    description = "Complete Ante 12",
    category = "Progression",
    rarity = "Epic",
    order = 6,
    is_tracked = true,
    progress_required = 12,
    reward_type = "title",
    reward_data = {id = "title_high_roller", name = "High Roller"}
})

add_achievement({
    id = "ante_15",
    name = "Ante Conqueror",
    description = "Reach Ante 15",
    category = "Progression",
    rarity = "Epic",
    order = 7,
    is_tracked = true,
    progress_required = 15,
    reward_type = "title",
    reward_data = {id = "title_conqueror", name = "Conqueror"}
})

add_achievement({
    id = "ante_20",
    name = "Ante Legend",
    description = "Reach Ante 20",
    category = "Progression",
    rarity = "Legendary",
    order = 8,
    is_tracked = true,
    progress_required = 20,
    reward_type = "title",
    reward_data = {id = "title_legend", name = "Legend"}
})

add_achievement({
    id = "first_win",
    name = "Winner!",
    description = "Win your first run",
    category = "Progression",
    rarity = "Common",
    order = 10,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_winner", name = "Winner Badge", icon = "badge_gold"}
})

add_achievement({
    id = "wins_10",
    name = "Consistent",
    description = "Win 10 runs",
    category = "Progression",
    rarity = "Rare",
    order = 11,
    is_tracked = true,
    progress_required = 10,
    reward_type = "title",
    reward_data = {id = "title_consistent", name = "Consistent"}
})

add_achievement({
    id = "wins_50",
    name = "Expert Player",
    description = "Win 50 runs",
    category = "Progression",
    rarity = "Epic",
    order = 12,
    is_tracked = true,
    progress_required = 50,
    reward_type = "title",
    reward_data = {id = "title_expert", name = "Expert"}
})

add_achievement({
    id = "wins_100",
    name = "Master of Balatro",
    description = "Win 100 runs",
    category = "Progression",
    rarity = "Legendary",
    order = 13,
    is_tracked = true,
    progress_required = 100,
    reward_type = "cosmetic",
    reward_data = {id = "back_master", type = "card_back", name = "Master's Deck"}
})

add_achievement({
    id = "runs_started",
    name = "Persistent",
    description = "Start 100 runs",
    category = "Progression",
    rarity = "Common",
    order = 14,
    is_tracked = true,
    progress_required = 100,
    reward_type = "badge",
    reward_data = {id = "badge_persistent", name = "Persistent Badge"}
})

add_achievement({
    id = "blinds_beaten_100",
    name = "Blind Annihilator",
    description = "Beat 100 blinds",
    category = "Progression",
    rarity = "Rare",
    order = 15,
    is_tracked = true,
    progress_required = 100,
    reward_type = "title",
    reward_data = {id = "title_annihilator", name = "Annihilator"}
})

-- ============================================
-- CATEGORY: SCORING (16 achievements)
-- ============================================

add_achievement({
    id = "score_10k",
    name = "Highscore 10K",
    description = "Score 10,000 chips in one hand",
    category = "Scoring",
    rarity = "Common",
    order = 16,
    is_tracked = true,
    progress_required = 10000,
    reward_type = "badge",
    reward_data = {id = "badge_10k", name = "10K Badge"}
})

add_achievement({
    id = "score_100k",
    name = "Highscore 100K",
    description = "Score 100,000 chips in one hand",
    category = "Scoring",
    rarity = "Rare",
    order = 17,
    is_tracked = true,
    progress_required = 100000,
    reward_type = "badge",
    reward_data = {id = "badge_100k", name = "100K Badge"}
})

add_achievement({
    id = "score_1m",
    name = "Highscore 1M",
    description = "Score 1,000,000 chips in one hand",
    category = "Scoring",
    rarity = "Epic",
    order = 18,
    is_tracked = true,
    progress_required = 1000000,
    reward_type = "title",
    reward_data = {id = "title_millionaire", name = "Millionaire"}
})

add_achievement({
    id = "score_10m",
    name = "Highscore 10M",
    description = "Score 10,000,000 chips in one hand",
    category = "Scoring",
    rarity = "Epic",
    order = 19,
    is_tracked = true,
    progress_required = 10000000,
    reward_type = "title",
    reward_data = {id = "title_10m", name = "Ten Millionaire"}
})

add_achievement({
    id = "score_100m",
    name = "Highscore 100M",
    description = "Score 100,000,000 chips in one hand",
    category = "Scoring",
    rarity = "Legendary",
    order = 20,
    is_tracked = true,
    progress_required = 100000000,
    reward_type = "cosmetic",
    reward_data = {id = "back_chips", name = "Chip Master Back"}
})

add_achievement({
    id = "score_1b",
    name = "Highscore 1B",
    description = "Score 1,000,000,000 chips in one hand",
    category = "Scoring",
    rarity = "Legendary",
    order = 21,
    is_tracked = true,
    progress_required = 1000000000,
    reward_type = "title",
    reward_data = {id = "title_billionaire", name = "Billionaire"}
})

add_achievement({
    id = "play_flush_five",
    name = "Flush Five",
    description = "Play a Flush Five hand",
    category = "Scoring",
    rarity = "Rare",
    order = 22,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_flush_five", name = "Flush Five Badge"}
})

add_achievement({
    id = "play_flush_house",
    name = "Flush House",
    description = "Play a Flush House hand",
    category = "Scoring",
    rarity = "Rare",
    order = 23,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_flush_house", name = "Flush House Badge"}
})

add_achievement({
    id = "play_five_of_kind",
    name = "Five of a Kind",
    description = "Play a Five of a Kind hand",
    category = "Scoring",
    rarity = "Rare",
    order = 24,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_five_kind", name = "Five of a Kind Badge"}
})

add_achievement({
    id = "play_straight_flush",
    name = "Straight Flush",
    description = "Play a Straight Flush hand",
    category = "Scoring",
    rarity = "Rare",
    order = 25,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_straight_flush", name = "Straight Flush Badge"}
})

add_achievement({
    id = "play_royal_flush",
    name = "Royal Flush",
    description = "Play a Royal Flush hand",
    category = "Scoring",
    rarity = "Epic",
    order = 26,
    is_tracked = true,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_royal", name = "Royal"}
})

add_achievement({
    id = "play_full_house",
    name = "Full House",
    description = "Play a Full House hand",
    category = "Scoring",
    rarity = "Common",
    order = 27,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_full_house", name = "Full House Badge"}
})

add_achievement({
    id = "hands_played_100",
    name = "Hands Played 100",
    description = "Play 100 hands total",
    category = "Scoring",
    rarity = "Common",
    order = 28,
    is_tracked = true,
    progress_required = 100,
    reward_type = "badge",
    reward_data = {id = "badge_player", name = "Player Badge"}
})

add_achievement({
    id = "hands_played_500",
    name = "Hands Played 500",
    description = "Play 500 hands total",
    category = "Scoring",
    rarity = "Rare",
    order = 29,
    is_tracked = true,
    progress_required = 500,
    reward_type = "badge",
    reward_data = {id = "badge_dealer", name = "Dealer Badge"}
})

add_achievement({
    id = "hands_played_1000",
    name = "Hands Played 1K",
    description = "Play 1000 hands total",
    category = "Scoring",
    rarity = "Epic",
    order = 30,
    is_tracked = true,
    progress_required = 1000,
    reward_type = "title",
    reward_data = {id = "title_shark", name = "Card Shark"}
})

add_achievement({
    id = "perfect_ante",
    name = "Perfect Ante",
    description = "Complete an Ante using only 1 hand per blind",
    category = "Scoring",
    rarity = "Epic",
    order = 31,
    is_tracked = false,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_perfect", name = "Perfect"}
})

-- ============================================
-- CATEGORY: JOKER EXPERTISE (12 achievements)
-- ============================================

add_achievement({
    id = "jokers_obtained_50",
    name = "Jokers Obtained 50",
    description = "Obtain 50 Jokers total",
    category = "Joker Expertise",
    rarity = "Common",
    order = 32,
    is_tracked = true,
    progress_required = 50,
    reward_type = "badge",
    reward_data = {id = "badge_collector", name = "Collector Badge"}
})

add_achievement({
    id = "jokers_obtained_100",
    name = "Jokers Obtained 100",
    description = "Obtain 100 Jokers total",
    category = "Joker Expertise",
    rarity = "Rare",
    order = 33,
    is_tracked = true,
    progress_required = 100,
    reward_type = "badge",
    reward_data = {id = "badge_hoarder", name = "Hoarder Badge"}
})

add_achievement({
    id = "joker_5_at_once",
    name = "Joker Full House",
    description = "Have 5 Jokers at once",
    category = "Joker Expertise",
    rarity = "Common",
    order = 34,
    is_tracked = true,
    progress_required = 5,
    reward_type = "badge",
    reward_data = {id = "badge_full_house_j", name = "Full House Badge"}
})

add_achievement({
    id = "joker_10_at_once",
    name = "Joker Army",
    description = "Have 10 Jokers at once",
    category = "Joker Expertise",
    rarity = "Rare",
    order = 35,
    is_tracked = true,
    progress_required = 10,
    reward_type = "title",
    reward_data = {id = "title_army", name = "Joker General"}
})

add_achievement({
    id = "joker_20_at_once",
    name = "Joker Overflow",
    description = "Have 20 Jokers at once",
    category = "Joker Expertise",
    rarity = "Legendary",
    order = 36,
    is_tracked = true,
    progress_required = 20,
    reward_type = "title",
    reward_data = {id = "title_overflow", name = "Overflowing"}
})

add_achievement({
    id = "legendary_obtained",
    name = "Legendary Find",
    description = "Obtain 5 Legendary Jokers",
    category = "Joker Expertise",
    rarity = "Legendary",
    order = 37,
    is_tracked = true,
    progress_required = 5,
    reward_type = "title",
    reward_data = {id = "title_legendary_finder", name = "Legend Hunter"}
})

add_achievement({
    id = "minimalist",
    name = "Minimalist",
    description = "Win a run with only 1 Joker",
    category = "Joker Expertise",
    rarity = "Epic",
    order = 38,
    is_tracked = false,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_minimalist", name = "Minimalist"}
})

add_achievement({
    id = "win_5_jokers",
    name = "Joker Fan",
    description = "Win with 5+ Jokers",
    category = "Joker Expertise",
    rarity = "Common",
    order = 39,
    is_tracked = false,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_fan", name = "Fan Badge"}
})

add_achievement({
    id = "common_only_win",
    name = "Common Legend",
    description = "Win using only Common rarity Jokers",
    category = "Joker Expertise",
    rarity = "Epic",
    order = 40,
    is_tracked = false,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_common_legend", name = "Common Legend"}
})

add_achievement({
    id = "no_jokers_win",
    name = "No Funny Business",
    description = "Win without any Jokers",
    category = "Joker Expertise",
    rarity = "Legendary",
    order = 41,
    is_tracked = false,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_serious", name = "Serious"}
})

add_achievement({
    id = "all_legendary",
    name = "Legendary Collection",
    description = "Have 4 Legendary Jokers at once",
    category = "Joker Expertise",
    rarity = "Legendary",
    order = 42,
    is_tracked = true,
    progress_required = 4,
    reward_type = "cosmetic",
    reward_data = {id = "back_legendary", name = "Legendary Back"}
})

add_achievement({
    id = "sell_jokers_50",
    name = "Joker Trader",
    description = "Sell 50 Jokers",
    category = "Joker Expertise",
    rarity = "Rare",
    order = 43,
    is_tracked = true,
    progress_required = 50,
    reward_type = "badge",
    reward_data = {id = "badge_trader", name = "Trader Badge"}
})

-- ============================================
-- CATEGORY: DECK MASTERY (15 achievements)
-- ============================================

add_achievement({
    id = "deck_win_b_red",
    name = "Red Deck Master",
    description = "Win with Red Deck",
    category = "Deck Mastery",
    rarity = "Common",
    order = 44,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_red_deck", name = "Red Deck Badge"}
})

add_achievement({
    id = "deck_win_b_blue",
    name = "Blue Deck Master",
    description = "Win with Blue Deck",
    category = "Deck Mastery",
    rarity = "Common",
    order = 45,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_blue_deck", name = "Blue Deck Badge"}
})

add_achievement({
    id = "deck_win_b_yellow",
    name = "Yellow Deck Master",
    description = "Win with Yellow Deck",
    category = "Deck Mastery",
    rarity = "Common",
    order = 46,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_yellow_deck", name = "Yellow Deck Badge"}
})

add_achievement({
    id = "deck_win_b_green",
    name = "Green Deck Master",
    description = "Win with Green Deck",
    category = "Deck Mastery",
    rarity = "Common",
    order = 47,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_green_deck", name = "Green Deck Badge"}
})

add_achievement({
    id = "deck_win_b_black",
    name = "Black Deck Master",
    description = "Win with Black Deck",
    category = "Deck Mastery",
    rarity = "Rare",
    order = 48,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_black_deck", name = "Black Deck Badge"}
})

add_achievement({
    id = "deck_win_b_magic",
    name = "Magic Deck Master",
    description = "Win with Magic Deck",
    category = "Deck Mastery",
    rarity = "Rare",
    order = 49,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_magic_deck", name = "Magic Deck Badge"}
})

add_achievement({
    id = "deck_win_b_nebula",
    name = "Nebula Deck Master",
    description = "Win with Nebula Deck",
    category = "Deck Mastery",
    rarity = "Rare",
    order = 50,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_nebula_deck", name = "Nebula Deck Badge"}
})

add_achievement({
    id = "deck_win_b_ghost",
    name = "Ghost Deck Master",
    description = "Win with Ghost Deck",
    category = "Deck Mastery",
    rarity = "Epic",
    order = 51,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_ghost_deck", name = "Ghost Deck Badge"}
})

add_achievement({
    id = "deck_win_b_abandoned",
    name = "Abandoned Deck Master",
    description = "Win with Abandoned Deck",
    category = "Deck Mastery",
    rarity = "Epic",
    order = 52,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_abandoned_deck", name = "Abandoned Deck Badge"}
})

add_achievement({
    id = "deck_win_b_checkered",
    name = "Checkered Deck Master",
    description = "Win with Checkered Deck",
    category = "Deck Mastery",
    rarity = "Rare",
    order = 53,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_checkered_deck", name = "Checkered Deck Badge"}
})

add_achievement({
    id = "deck_win_b_zodiac",
    name = "Zodiac Deck Master",
    description = "Win with Zodiac Deck",
    category = "Deck Mastery",
    rarity = "Epic",
    order = 54,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_zodiac_deck", name = "Zodiac Deck Badge"}
})

add_achievement({
    id = "deck_win_b_painted",
    name = "Painted Deck Master",
    description = "Win with Painted Deck",
    category = "Deck Mastery",
    rarity = "Rare",
    order = 55,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_painted_deck", name = "Painted Deck Badge"}
})

add_achievement({
    id = "deck_win_b_anaglyph",
    name = "Anaglyph Deck Master",
    description = "Win with Anaglyph Deck",
    category = "Deck Mastery",
    rarity = "Epic",
    order = 56,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_anaglyph_deck", name = "Anaglyph Deck Badge"}
})

add_achievement({
    id = "deck_win_b_plasma",
    name = "Plasma Deck Master",
    description = "Win with Plasma Deck",
    category = "Deck Mastery",
    rarity = "Epic",
    order = 57,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_plasma_deck", name = "Plasma Deck Badge"}
})

add_achievement({
    id = "deck_win_b_erratic",
    name = "Erratic Deck Master",
    description = "Win with Erratic Deck",
    category = "Deck Mastery",
    rarity = "Rare",
    order = 58,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_erratic_deck", name = "Erratic Deck Badge"}
})

-- ============================================
-- CATEGORY: CHALLENGE MASTER (12 achievements)
-- ============================================

add_achievement({
    id = "stake_white",
    name = "White Stake Victory",
    description = "Win on White Stake",
    category = "Challenge Master",
    rarity = "Common",
    order = 59,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_stake_white", name = "White Stake Badge"}
})

add_achievement({
    id = "stake_red",
    name = "Red Stake Victory",
    description = "Win on Red Stake",
    category = "Challenge Master",
    rarity = "Common",
    order = 60,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_stake_red", name = "Red Stake Badge"}
})

add_achievement({
    id = "stake_green",
    name = "Green Stake Victory",
    description = "Win on Green Stake",
    category = "Challenge Master",
    rarity = "Rare",
    order = 61,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_stake_green", name = "Green Stake Badge"}
})

add_achievement({
    id = "stake_black",
    name = "Black Stake Victory",
    description = "Win on Black Stake",
    category = "Challenge Master",
    rarity = "Rare",
    order = 62,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_stake_black", name = "Black Stake Badge"}
})

add_achievement({
    id = "stake_blue",
    name = "Blue Stake Victory",
    description = "Win on Blue Stake",
    category = "Challenge Master",
    rarity = "Epic",
    order = 63,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_stake_blue", name = "Blue Stake Badge"}
})

add_achievement({
    id = "stake_purple",
    name = "Purple Stake Victory",
    description = "Win on Purple Stake",
    category = "Challenge Master",
    rarity = "Epic",
    order = 64,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_stake_purple", name = "Purple Stake Badge"}
})

add_achievement({
    id = "stake_orange",
    name = "Orange Stake Victory",
    description = "Win on Orange Stake",
    category = "Challenge Master",
    rarity = "Legendary",
    order = 65,
    is_tracked = true,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_orange_master", name = "Orange Master"}
})

add_achievement({
    id = "stake_gold",
    name = "Gold Stake Victory",
    description = "Win on Gold Stake",
    category = "Challenge Master",
    rarity = "Legendary",
    order = 66,
    is_tracked = true,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_gold_master", name = "Gold Master"}
})

add_achievement({
    id = "speed_runner",
    name = "Speed Runner",
    description = "Win a run in under 15 minutes",
    category = "Challenge Master",
    rarity = "Epic",
    order = 67,
    is_tracked = false,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_speedster", name = "Speedster"}
})

add_achievement({
    id = "speed_demon",
    name = "Speed Demon",
    description = "Win a run in under 10 minutes",
    category = "Challenge Master",
    rarity = "Legendary",
    order = 68,
    is_tracked = false,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_demon", name = "Speed Demon"}
})

add_achievement({
    id = "perfectionist",
    name = "Perfectionist",
    description = "Win a run without skipping a blind",
    category = "Challenge Master",
    rarity = "Legendary",
    order = 69,
    is_tracked = false,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_perfectionist", name = "Perfectionist"}
})

add_achievement({
    id = "no_discards_win",
    name = "No Discards",
    description = "Win without discarding any cards",
    category = "Challenge Master",
    rarity = "Legendary",
    order = 70,
    is_tracked = false,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_efficient", name = "Efficient"}
})

-- ============================================
-- CATEGORY: COLLECTION (8 achievements)
-- ============================================

add_achievement({
    id = "money_100",
    name = "Money $100",
    description = "Have $100 at once",
    category = "Collection",
    rarity = "Common",
    order = 71,
    is_tracked = true,
    progress_required = 100,
    reward_type = "badge",
    reward_data = {id = "badge_money_100", name = "Rich Badge"}
})

add_achievement({
    id = "money_500",
    name = "Money $500",
    description = "Have $500 at once",
    category = "Collection",
    rarity = "Rare",
    order = 72,
    is_tracked = true,
    progress_required = 500,
    reward_type = "badge",
    reward_data = {id = "badge_money_500", name = "Wealthy Badge"}
})

add_achievement({
    id = "money_1000",
    name = "Money $1K",
    description = "Have $1000 at once",
    category = "Collection",
    rarity = "Epic",
    order = 73,
    is_tracked = true,
    progress_required = 1000,
    reward_type = "title",
    reward_data = {id = "title_loaded", name = "Loaded"}
})

add_achievement({
    id = "vouchers_used",
    name = "Voucher Collector",
    description = "Use 50 vouchers total",
    category = "Collection",
    rarity = "Rare",
    order = 74,
    is_tracked = true,
    progress_required = 50,
    reward_type = "badge",
    reward_data = {id = "badge_voucher", name = "Voucher Badge"}
})

add_achievement({
    id = "shops_visited",
    name = "Shopaholic",
    description = "Visit 100 shops",
    category = "Collection",
    rarity = "Rare",
    order = 75,
    is_tracked = true,
    progress_required = 100,
    reward_type = "badge",
    reward_data = {id = "badge_shop", name = "Shopaholic Badge"}
})

add_achievement({
    id = "discards_100",
    name = "Discards 100",
    description = "Discard 100 cards total",
    category = "Collection",
    rarity = "Common",
    order = 76,
    is_tracked = true,
    progress_required = 100,
    reward_type = "badge",
    reward_data = {id = "badge_discard", name = "Tosser Badge"}
})

add_achievement({
    id = "discards_500",
    name = "Discards 500",
    description = "Discard 500 cards total",
    category = "Collection",
    rarity = "Rare",
    order = 77,
    is_tracked = true,
    progress_required = 500,
    reward_type = "badge",
    reward_data = {id = "badge_discard_expert", name = "Discard Expert Badge"}
})

add_achievement({
    id = "consumables_used_100",
    name = "Consumer",
    description = "Use 100 consumables",
    category = "Collection",
    rarity = "Rare",
    order = 78,
    is_tracked = true,
    progress_required = 100,
    reward_type = "badge",
    reward_data = {id = "badge_consumer", name = "Consumer Badge"}
})

-- ============================================
-- CATEGORY: DAILY CHAMPION (5 achievements)
-- ============================================

add_achievement({
    id = "daily_complete_1",
    name = "Daily Participant",
    description = "Finish your first Daily Challenge",
    category = "Daily Champion",
    rarity = "Common",
    order = 79,
    is_tracked = true,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_daily_1", name = "Daily Badge"}
})

add_achievement({
    id = "daily_complete_7",
    name = "Weekly Warrior",
    description = "Finish 7 Daily Challenges",
    category = "Daily Champion",
    rarity = "Rare",
    order = 80,
    is_tracked = true,
    progress_required = 7,
    reward_type = "badge",
    reward_data = {id = "badge_daily_7", name = "Weekly Badge"}
})

add_achievement({
    id = "daily_complete_30",
    name = "Monthly Master",
    description = "Finish 30 Daily Challenges",
    category = "Daily Champion",
    rarity = "Epic",
    order = 81,
    is_tracked = true,
    progress_required = 30,
    reward_type = "title",
    reward_data = {id = "title_monthly", name = "Monthly Master"}
})

add_achievement({
    id = "daily_streak_7",
    name = "Weekly Streak",
    description = "Finish a Daily Challenge 7 days in a row",
    category = "Daily Champion",
    rarity = "Epic",
    order = 82,
    is_tracked = true,
    progress_required = 7,
    reward_type = "title",
    reward_data = {id = "title_streaker", name = "Streaker"}
})

add_achievement({
    id = "daily_streak_30",
    name = "Daily Legend",
    description = "Finish a Daily Challenge 30 days in a row",
    category = "Daily Champion",
    rarity = "Legendary",
    order = 83,
    is_tracked = true,
    progress_required = 30,
    reward_type = "cosmetic",
    reward_data = {id = "back_daily", name = "Daily Champion Back"}
})

-- ============================================
-- CATEGORY: SECRET (7 achievements)
-- ============================================

add_achievement({
    id = "secret_mod_user",
    name = "Cheat Sheet",
    description = "Open the Cheats menu",
    secret_hint = "Not every button is for honest players...",
    category = "Secret",
    rarity = "Secret",
    order = 84,
    is_secret = true,
    is_tracked = false,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_modder", name = "Modder"}
})

add_achievement({
    id = "secret_jukebox",
    name = "DJ",
    description = "You found the Jukebox!",
    secret_hint = "Listen carefully...",
    category = "Secret",
    rarity = "Secret",
    order = 85,
    is_secret = true,
    is_tracked = false,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_dj", name = "DJ"}
})

add_achievement({
    id = "secret_custom_run",
    name = "Custom Creator",
    description = "Finish a Custom Run",
    secret_hint = "Make your own rules...",
    category = "Secret",
    rarity = "Secret",
    order = 86,
    is_secret = true,
    is_tracked = false,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_custom", name = "Custom Creator"}
})

add_achievement({
    id = "secret_zero_dollars",
    name = "Broke",
    description = "Have exactly $0 and win a blind",
    secret_hint = "Spend it all...",
    category = "Secret",
    rarity = "Secret",
    order = 87,
    is_secret = true,
    is_tracked = false,
    progress_required = 1,
    reward_type = "badge",
    reward_data = {id = "badge_broke", name = "Broke Badge"}
})

-- ============================================
-- PROFILE ICON COLLECTION ACHIEVEMENTS
-- Unlocked by collecting joker profile icons
-- ============================================

add_achievement({
    id = "icon_collector_1",
    name = "First Impression",
    description = "Unlock 1 Profile Icon",
    category = "Collection",
    rarity = "Common",
    order = 91,
    is_secret = false,
    is_tracked = true,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_first_icon", name = "Portrait Starter"}
})

add_achievement({
    id = "icon_collector_5",
    name = "Familiar Faces",
    description = "Unlock 5 Profile Icons",
    category = "Collection",
    rarity = "Common",
    order = 92,
    is_secret = false,
    is_tracked = true,
    progress_required = 5,
    reward_type = "title",
    reward_data = {id = "title_faces", name = "Face Collector"}
})

add_achievement({
    id = "icon_collector_15",
    name = "Rogues Gallery",
    description = "Unlock 15 Profile Icons",
    category = "Collection",
    rarity = "Uncommon",
    order = 93,
    is_secret = false,
    is_tracked = true,
    progress_required = 15,
    reward_type = "title",
    reward_data = {id = "title_gallery", name = "Gallery Curator"}
})

add_achievement({
    id = "icon_collector_30",
    name = "Hall of Jesters",
    description = "Unlock 30 Profile Icons",
    category = "Collection",
    rarity = "Uncommon",
    order = 94,
    is_secret = false,
    is_tracked = true,
    progress_required = 30,
    reward_type = "title",
    reward_data = {id = "title_jesters", name = "Hall Keeper"}
})

add_achievement({
    id = "icon_collector_50",
    name = "Portrait Master",
    description = "Unlock 50 Profile Icons",
    category = "Collection",
    rarity = "Rare",
    order = 95,
    is_secret = false,
    is_tracked = true,
    progress_required = 50,
    reward_type = "title",
    reward_data = {id = "title_portraits", name = "Portrait Master"}
})

add_achievement({
    id = "icon_collector_100",
    name = "Century of Fools",
    description = "Unlock 100 Profile Icons",
    category = "Collection",
    rarity = "Rare",
    order = 96,
    is_secret = false,
    is_tracked = true,
    progress_required = 100,
    reward_type = "title",
    reward_data = {id = "title_century", name = "Fool's Centurion"}
})

add_achievement({
    id = "icon_collector_150",
    name = "Full Court",
    description = "Unlock all 150 Profile Icons",
    category = "Collection",
    rarity = "Legendary",
    order = 97,
    is_secret = false,
    is_tracked = true,
    progress_required = 150,
    reward_type = "title",
    reward_data = {id = "title_full_court", name = "Grand Collector"}
})

-- ============================================
-- Unlocked by collecting boss blind badges
-- ============================================

add_achievement({
    id = "secret_999_dollars",
    name = "Money Cap",
    description = "Reach $999",
    secret_hint = "Maximum cash...",
    category = "Secret",
    rarity = "Secret",
    order = 88,
    is_secret = true,
    is_tracked = false,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_maxed", name = "Maxed Out"}
})

add_achievement({
    id = "secret_exactly_52",
    name = "Classic Deck",
    description = "Win with exactly 52 cards in deck",
    secret_hint = "Keep it classic...",
    category = "Secret",
    rarity = "Secret",
    order = 89,
    is_secret = true,
    is_tracked = false,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_classic", name = "Classic"}
})

add_achievement({
    id = "secret_lucky_7",
    name = "Lucky 7",
    description = "Beat the Ante 7 Boss Blind with exactly $77",
    secret_hint = "7-7-7...",
    category = "Secret",
    rarity = "Secret",
    order = 90,
    is_secret = true,
    is_tracked = false,
    progress_required = 1,
    reward_type = "title",
    reward_data = {id = "title_lucky", name = "Lucky"}
})

-- ============================================
-- NEW MODDED ACHIEVEMENTS (97 new, IDs 104-200)
-- ============================================

-- ============================================
-- CATEGORY: CREATIVE STAKES (8 achievements)
-- ============================================

add_achievement({
    id = "stake_chaos", name = "Chaos Victory", description = "Win on Chaos Stake",
    category = "Challenge Master", rarity = "Epic", order = 105, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_chaotic", name = "Chaotic"}
})
add_achievement({
    id = "stake_oblivion", name = "Oblivion Victory", description = "Win on Oblivion Stake",
    category = "Challenge Master", rarity = "Legendary", order = 106, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_oblivion", name = "Forgotten"}
})
add_achievement({
    id = "stake_apocalypse", name = "Apocalypse Victory", description = "Win on Apocalypse Stake",
    category = "Challenge Master", rarity = "Legendary", order = 107, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_apocalypse", name = "Apocalyptic"}
})
add_achievement({
    id = "stake_transcendent", name = "Transcendent Victory", description = "Win on Transcendent Stake",
    category = "Challenge Master", rarity = "Legendary", order = 108, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_transcendent", name = "Transcendent"}
})
add_achievement({
    id = "creative_first", name = "Creative First", description = "Win on any Creative Stake (Chaos or higher)",
    category = "Challenge Master", rarity = "Rare", order = 109, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_creative", name = "Creative Badge", icon = "badge_gold"}
})
add_achievement({
    id = "creative_3_stakes", name = "Creative Trio", description = "Win on 3 different Creative Stakes",
    category = "Challenge Master", rarity = "Epic", order = 110, is_tracked = true,
    progress_required = 3, reward_type = "title", reward_data = {id = "title_creative_trio", name = "Creative Mind"}
})
add_achievement({
    id = "creative_all_stakes", name = "Creative Master", description = "Win on all 4 Creative Stakes",
    category = "Challenge Master", rarity = "Legendary", order = 111, is_tracked = true,
    progress_required = 4, reward_type = "title", reward_data = {id = "title_creative_master", name = "Creative Master"}
})

-- ============================================
-- CATEGORY: CHALLENGE COMPLETIONIST (10 achievements)
-- ============================================

add_achievement({
    id = "challenge_first", name = "Challenger", description = "Win your first Challenge",
    category = "Challenge Master", rarity = "Common", order = 112, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_challenger", name = "Challenger Badge", icon = "badge_bronze"}
})
add_achievement({
    id = "challenge_5", name = "Challenge Seeker", description = "Win 5 different Challenges",
    category = "Challenge Master", rarity = "Rare", order = 113, is_tracked = true,
    progress_required = 5, reward_type = "badge", reward_data = {id = "badge_challenge_5", name = "Challenge Seeker", icon = "badge_silver"}
})
add_achievement({
    id = "challenge_10", name = "Challenge Veteran", description = "Win 10 different Challenges",
    category = "Challenge Master", rarity = "Rare", order = 114, is_tracked = true,
    progress_required = 10, reward_type = "title", reward_data = {id = "title_challenge_vet", name = "Challenge Veteran"}
})
add_achievement({
    id = "challenge_20", name = "Challenge Expert", description = "Win 20 different Challenges",
    category = "Challenge Master", rarity = "Epic", order = 115, is_tracked = true,
    progress_required = 20, reward_type = "title", reward_data = {id = "title_challenge_exp", name = "Challenge Expert"}
})
add_achievement({
    id = "challenge_30", name = "Challenge Conqueror", description = "Win 30 different Challenges",
    category = "Challenge Master", rarity = "Legendary", order = 116, is_tracked = true,
    progress_required = 30, reward_type = "title", reward_data = {id = "title_challenge_conq", name = "Challenge Conqueror"}
})
add_achievement({
    id = "challenge_bankruptcy", name = "Survived Bankruptcy", description = "Win the Bankruptcy challenge",
    category = "Challenge Master", rarity = "Epic", order = 117, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_bankruptcy", name = "Bankruptcy Survivor", icon = "badge_gold"}
})
add_achievement({
    id = "challenge_gauntlet", name = "Gauntlet Runner", description = "Win The Gauntlet challenge",
    category = "Challenge Master", rarity = "Epic", order = 118, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_gauntlet", name = "Gauntlet Runner", icon = "badge_gold"}
})
add_achievement({
    id = "challenge_glass_cannon", name = "Shattered Victory", description = "Win the Glass Cannon challenge",
    category = "Challenge Master", rarity = "Epic", order = 119, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_glass_cannon", name = "Glass Champion", icon = "badge_gold"}
})
add_achievement({
    id = "challenge_duality", name = "Two-Faced", description = "Win the Duality challenge",
    category = "Challenge Master", rarity = "Epic", order = 120, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_duality", name = "Two-Faced", icon = "badge_gold"}
})
add_achievement({
    id = "challenge_alchemist", name = "Master Alchemist", description = "Win The Alchemist challenge",
    category = "Challenge Master", rarity = "Epic", order = 121, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_alchemist", name = "Master Alchemist", icon = "badge_gold"}
})

-- ============================================
-- CATEGORY: ECONOMY (8 achievements)
-- ============================================

add_achievement({
    id = "money_2000", name = "Money $2K", description = "Have $2,000 at once",
    category = "Collection", rarity = "Epic", order = 122, is_tracked = true,
    progress_required = 2000, reward_type = "title", reward_data = {id = "title_rich", name = "Wealthy"}
})
add_achievement({
    id = "money_5000", name = "Money $5K", description = "Have $5,000 at once",
    category = "Collection", rarity = "Legendary", order = 123, is_tracked = true,
    progress_required = 5000, reward_type = "title", reward_data = {id = "title_tycoon", name = "Tycoon"}
})
add_achievement({
    id = "bankrupt_swing", name = "Bankrupt Swing", description = "Go from $100+ to $0 in a single ante",
    category = "Collection", rarity = "Rare", order = 124, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_bankrupt", name = "Bankrupt Badge", icon = "badge_silver"}
})
add_achievement({
    id = "big_spender", name = "Big Spender", description = "Spend $500 total in shops",
    category = "Collection", rarity = "Rare", order = 125, is_tracked = true,
    progress_required = 500, reward_type = "badge", reward_data = {id = "badge_spender", name = "Big Spender", icon = "badge_silver"}
})
add_achievement({
    id = "rerolls_50", name = "Reroll Addict", description = "Reroll the shop 50 times",
    category = "Collection", rarity = "Rare", order = 126, is_tracked = true,
    progress_required = 50, reward_type = "badge", reward_data = {id = "badge_reroll_50", name = "Reroll Addict", icon = "badge_silver"}
})
add_achievement({
    id = "rerolls_200", name = "Reroll Maniac", description = "Reroll the shop 200 times",
    category = "Collection", rarity = "Epic", order = 127, is_tracked = true,
    progress_required = 200, reward_type = "title", reward_data = {id = "title_reroll_maniac", name = "Reroll Maniac"}
})
add_achievement({
    id = "sell_100", name = "Seller", description = "Sell 100 cards total",
    category = "Collection", rarity = "Rare", order = 128, is_tracked = true,
    progress_required = 100, reward_type = "badge", reward_data = {id = "badge_seller", name = "Seller Badge", icon = "badge_silver"}
})
add_achievement({
    id = "sell_500", name = "Merchant Master", description = "Sell 500 cards total",
    category = "Collection", rarity = "Epic", order = 129, is_tracked = true,
    progress_required = 500, reward_type = "title", reward_data = {id = "title_merchant", name = "Merchant Master"}
})

-- ============================================
-- CATEGORY: HAND MASTERY (10 achievements)
-- ============================================

add_achievement({
    id = "play_pair_100", name = "Pair Pro", description = "Play 100 Pair hands",
    category = "Scoring", rarity = "Common", order = 130, is_tracked = true,
    progress_required = 100, reward_type = "badge", reward_data = {id = "badge_pair", name = "Pair Pro", icon = "badge_bronze"}
})
add_achievement({
    id = "play_two_pair_50", name = "Two Pair Expert", description = "Play 50 Two Pair hands",
    category = "Scoring", rarity = "Common", order = 131, is_tracked = true,
    progress_required = 50, reward_type = "badge", reward_data = {id = "badge_two_pair", name = "Two Pair Expert", icon = "badge_bronze"}
})
add_achievement({
    id = "play_three_kind_50", name = "Triple Expert", description = "Play 50 Three of a Kind hands",
    category = "Scoring", rarity = "Rare", order = 132, is_tracked = true,
    progress_required = 50, reward_type = "badge", reward_data = {id = "badge_three_kind", name = "Triple Expert", icon = "badge_silver"}
})
add_achievement({
    id = "play_four_kind_25", name = "Quad Expert", description = "Play 25 Four of a Kind hands",
    category = "Scoring", rarity = "Rare", order = 133, is_tracked = true,
    progress_required = 25, reward_type = "badge", reward_data = {id = "badge_four_kind", name = "Quad Expert", icon = "badge_silver"}
})
add_achievement({
    id = "play_straight_25", name = "Straight Expert", description = "Play 25 Straight hands",
    category = "Scoring", rarity = "Rare", order = 134, is_tracked = true,
    progress_required = 25, reward_type = "badge", reward_data = {id = "badge_straight", name = "Straight Expert", icon = "badge_silver"}
})
add_achievement({
    id = "play_flush_25", name = "Flush Expert", description = "Play 25 Flush hands",
    category = "Scoring", rarity = "Rare", order = 135, is_tracked = true,
    progress_required = 25, reward_type = "badge", reward_data = {id = "badge_flush", name = "Flush Expert", icon = "badge_silver"}
})
add_achievement({
    id = "play_full_house_25", name = "Full House Expert", description = "Play 25 Full House hands",
    category = "Scoring", rarity = "Rare", order = 136, is_tracked = true,
    progress_required = 25, reward_type = "badge", reward_data = {id = "badge_full_house_exp", name = "Full House Expert", icon = "badge_silver"}
})
add_achievement({
    id = "high_card_blind", name = "High Card Hero", description = "Win a blind playing only High Card hands",
    category = "Scoring", rarity = "Epic", order = 137, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_high_card", name = "High Card Hero"}
})
add_achievement({
    id = "hands_played_5000", name = "Hands Played 5K", description = "Play 5,000 hands total",
    category = "Scoring", rarity = "Epic", order = 138, is_tracked = true,
    progress_required = 5000, reward_type = "title", reward_data = {id = "title_5k_hands", name = "Marathon Player"}
})
add_achievement({
    id = "hands_played_10000", name = "Hands Played 10K", description = "Play 10,000 hands total",
    category = "Scoring", rarity = "Legendary", order = 139, is_tracked = true,
    progress_required = 10000, reward_type = "title", reward_data = {id = "title_10k_hands", name = "Eternal Player"}
})

-- ============================================
-- CATEGORY: CONSUMABLE MASTERY (10 achievements)
-- ============================================

add_achievement({
    id = "tarots_50", name = "Tarot Reader", description = "Use 50 Tarot cards total",
    category = "Collection", rarity = "Rare", order = 140, is_tracked = true,
    progress_required = 50, reward_type = "badge", reward_data = {id = "badge_tarot_50", name = "Tarot Reader", icon = "badge_silver"}
})
add_achievement({
    id = "tarots_200", name = "Tarot Master", description = "Use 200 Tarot cards total",
    category = "Collection", rarity = "Epic", order = 141, is_tracked = true,
    progress_required = 200, reward_type = "title", reward_data = {id = "title_tarot_master", name = "Tarot Master"}
})
add_achievement({
    id = "planets_50", name = "Astronomer", description = "Use 50 Planet cards total",
    category = "Collection", rarity = "Rare", order = 142, is_tracked = true,
    progress_required = 50, reward_type = "badge", reward_data = {id = "badge_planet_50", name = "Astronomer", icon = "badge_silver"}
})
add_achievement({
    id = "planets_200", name = "Astrophysicist", description = "Use 200 Planet cards total",
    category = "Collection", rarity = "Epic", order = 143, is_tracked = true,
    progress_required = 200, reward_type = "title", reward_data = {id = "title_astrophysicist", name = "Astrophysicist"}
})
add_achievement({
    id = "spectrals_25", name = "Spectral User", description = "Use 25 Spectral cards total",
    category = "Collection", rarity = "Rare", order = 144, is_tracked = true,
    progress_required = 25, reward_type = "badge", reward_data = {id = "badge_spectral_25", name = "Spectral User", icon = "badge_silver"}
})
add_achievement({
    id = "spectrals_100", name = "Spectral Master", description = "Use 100 Spectral cards total",
    category = "Collection", rarity = "Epic", order = 145, is_tracked = true,
    progress_required = 100, reward_type = "title", reward_data = {id = "title_spectral_master", name = "Spectral Master"}
})
add_achievement({
    id = "consumables_500", name = "Consumer Pro", description = "Use 500 consumables total",
    category = "Collection", rarity = "Epic", order = 146, is_tracked = true,
    progress_required = 500, reward_type = "title", reward_data = {id = "title_consumer_pro", name = "Consumer Pro"}
})
add_achievement({
    id = "consumables_1000", name = "Consumer Legend", description = "Use 1,000 consumables total",
    category = "Collection", rarity = "Legendary", order = 147, is_tracked = true,
    progress_required = 1000, reward_type = "title", reward_data = {id = "title_consumer_legend", name = "Consumer Legend"}
})
add_achievement({
    id = "all_planet_types", name = "Solar System", description = "Use every Planet card type in one run",
    category = "Collection", rarity = "Epic", order = 148, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_solar_system", name = "Solar System"}
})
add_achievement({
    id = "all_tarot_types", name = "Major Arcana", description = "Use every Tarot card type in one run",
    category = "Collection", rarity = "Legendary", order = 149, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_major_arcana", name = "Major Arcana"}
})

-- ============================================
-- CATEGORY: JOKER ADVANCED (8 achievements)
-- ============================================

add_achievement({
    id = "jokers_sold_200", name = "Joker Liquidator", description = "Sell 200 Jokers total",
    category = "Joker Expertise", rarity = "Epic", order = 150, is_tracked = true,
    progress_required = 200, reward_type = "title", reward_data = {id = "title_liquidator", name = "Liquidator"}
})
add_achievement({
    id = "jokers_obtained_500", name = "Joker Hoarder", description = "Obtain 500 Jokers total",
    category = "Joker Expertise", rarity = "Legendary", order = 151, is_tracked = true,
    progress_required = 500, reward_type = "title", reward_data = {id = "title_hoarder", name = "Hoarder"}
})
add_achievement({
    id = "negative_joker", name = "Negative Energy", description = "Own a Negative edition Joker",
    category = "Joker Expertise", rarity = "Rare", order = 152, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_negative", name = "Negative Badge", icon = "badge_silver"}
})
add_achievement({
    id = "polychrome_joker", name = "Polychrome Power", description = "Own a Polychrome edition Joker",
    category = "Joker Expertise", rarity = "Rare", order = 153, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_polychrome", name = "Polychrome Badge", icon = "badge_silver"}
})
add_achievement({
    id = "holographic_joker", name = "Holographic Shine", description = "Own a Holographic edition Joker",
    category = "Joker Expertise", rarity = "Rare", order = 154, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_holographic", name = "Holographic Badge", icon = "badge_silver"}
})
add_achievement({
    id = "foil_joker", name = "Foil Finder", description = "Own a Foil edition Joker",
    category = "Joker Expertise", rarity = "Common", order = 155, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_foil", name = "Foil Badge", icon = "badge_bronze"}
})
add_achievement({
    id = "full_legendary_5", name = "Legendary Quintet", description = "Own all 5 Legendary Jokers at once",
    category = "Joker Expertise", rarity = "Legendary", order = 156, is_tracked = false,
    progress_required = 5, reward_type = "title", reward_data = {id = "title_legendary_quintet", name = "Legendary Quintet"}
})
add_achievement({
    id = "edition_variety", name = "Edition Variety", description = "Own 3 different edition Jokers at once",
    category = "Joker Expertise", rarity = "Epic", order = 157, is_tracked = false,
    progress_required = 3, reward_type = "title", reward_data = {id = "title_edition_variety", name = "Edition Collector"}
})

-- ============================================
-- CATEGORY: BLIND EXPERTISE (8 achievements)
-- ============================================

add_achievement({
    id = "blinds_beaten_500", name = "Blind Crusher", description = "Beat 500 blinds total",
    category = "Progression", rarity = "Epic", order = 158, is_tracked = true,
    progress_required = 500, reward_type = "title", reward_data = {id = "title_crusher", name = "Crusher"}
})
add_achievement({
    id = "blinds_beaten_1000", name = "Blind Destroyer", description = "Beat 1,000 blinds total",
    category = "Progression", rarity = "Legendary", order = 159, is_tracked = true,
    progress_required = 1000, reward_type = "title", reward_data = {id = "title_destroyer", name = "Destroyer"}
})
add_achievement({
    id = "boss_defeated_50", name = "Boss Slayer", description = "Defeat 50 Boss Blinds total",
    category = "Progression", rarity = "Epic", order = 160, is_tracked = true,
    progress_required = 50, reward_type = "title", reward_data = {id = "title_boss_slayer", name = "Boss Slayer"}
})
add_achievement({
    id = "boss_defeated_100", name = "Boss Annihilator", description = "Defeat 100 Boss Blinds total",
    category = "Progression", rarity = "Legendary", order = 161, is_tracked = true,
    progress_required = 100, reward_type = "title", reward_data = {id = "title_boss_annihilator", name = "Boss Annihilator"}
})
add_achievement({
    id = "overkill", name = "Overkill", description = "Beat a blind with 10x the required chips",
    category = "Scoring", rarity = "Epic", order = 162, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_overkill", name = "Overkill"}
})
add_achievement({
    id = "close_call", name = "Close Call", description = "Beat a blind with less than 5% chips to spare",
    category = "Scoring", rarity = "Rare", order = 163, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_close_call", name = "Close Call", icon = "badge_silver"}
})
add_achievement({
    id = "first_skip", name = "First Skip", description = "Skip your first blind",
    category = "Progression", rarity = "Common", order = 164, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_first_skip", name = "First Skip", icon = "badge_bronze"}
})
add_achievement({
    id = "skip_50", name = "Skip Master", description = "Skip 50 blinds total",
    category = "Progression", rarity = "Rare", order = 165, is_tracked = true,
    progress_required = 50, reward_type = "title", reward_data = {id = "title_skip_master", name = "Skip Master"}
})

-- ============================================
-- CATEGORY: ENDURANCE (8 achievements)
-- ============================================

add_achievement({
    id = "ante_25", name = "Ante 25", description = "Reach Ante 25",
    category = "Progression", rarity = "Epic", order = 166, is_tracked = true,
    progress_required = 25, reward_type = "title", reward_data = {id = "title_ante_25", name = "Endurance Runner"}
})
add_achievement({
    id = "ante_30", name = "Ante 30", description = "Reach Ante 30",
    category = "Progression", rarity = "Legendary", order = 167, is_tracked = true,
    progress_required = 30, reward_type = "title", reward_data = {id = "title_ante_30", name = "Endurance Champion"}
})
add_achievement({
    id = "ante_39", name = "Infinity +1", description = "Reach Ante 39",
    category = "Progression", rarity = "Legendary", order = 168, is_tracked = true,
    progress_required = 39, reward_type = "cosmetic", reward_data = {id = "back_endless", type = "card_back", name = "Endless Card Back"}
})
add_achievement({
    id = "hours_played_10", name = "Dedicated Player", description = "Play for 10 hours total",
    category = "Progression", rarity = "Common", order = 169, is_tracked = true,
    progress_required = 36000, reward_type = "badge", reward_data = {id = "badge_10h", name = "10 Hour Badge", icon = "badge_bronze"}
})
add_achievement({
    id = "hours_played_50", name = "Committed Player", description = "Play for 50 hours total",
    category = "Progression", rarity = "Rare", order = 170, is_tracked = true,
    progress_required = 180000, reward_type = "title", reward_data = {id = "title_committed", name = "Committed"}
})
add_achievement({
    id = "hours_played_100", name = "Balatro Addict", description = "Play for 100 hours total",
    category = "Progression", rarity = "Epic", order = 171, is_tracked = true,
    progress_required = 360000, reward_type = "title", reward_data = {id = "title_addict", name = "Addicted"}
})
add_achievement({
    id = "runs_500", name = "Run Veteran", description = "Start 500 runs",
    category = "Progression", rarity = "Epic", order = 172, is_tracked = true,
    progress_required = 500, reward_type = "title", reward_data = {id = "title_run_veteran", name = "Run Veteran"}
})
add_achievement({
    id = "win_streak_5", name = "Win Streak 5", description = "Win 5 runs in a row",
    category = "Progression", rarity = "Epic", order = 173, is_tracked = true,
    progress_required = 5, reward_type = "title", reward_data = {id = "title_streak_5", name = "On a Roll"}
})

-- ============================================
-- CATEGORY: ENHANCEMENT & EDITION (8 achievements)
-- ============================================

add_achievement({
    id = "enhance_50", name = "Enhancer", description = "Enhance 50 cards total",
    category = "Collection", rarity = "Rare", order = 174, is_tracked = true,
    progress_required = 50, reward_type = "badge", reward_data = {id = "badge_enhance_50", name = "Enhancer", icon = "badge_silver"}
})
add_achievement({
    id = "enhance_200", name = "Enhancement Master", description = "Enhance 200 cards total",
    category = "Collection", rarity = "Epic", order = 175, is_tracked = true,
    progress_required = 200, reward_type = "title", reward_data = {id = "title_enhance_master", name = "Enhancement Master"}
})
add_achievement({
    id = "editions_10", name = "Edition Finder", description = "Obtain 10 edition cards total",
    category = "Collection", rarity = "Rare", order = 176, is_tracked = true,
    progress_required = 10, reward_type = "badge", reward_data = {id = "badge_edition_10", name = "Edition Finder", icon = "badge_silver"}
})
add_achievement({
    id = "editions_50", name = "Edition Expert", description = "Obtain 50 edition cards total",
    category = "Collection", rarity = "Epic", order = 177, is_tracked = true,
    progress_required = 50, reward_type = "title", reward_data = {id = "title_edition_expert", name = "Edition Expert"}
})
add_achievement({
    id = "all_enhancements", name = "Rainbow Deck", description = "Have 7 different enhancements in your deck at once",
    category = "Collection", rarity = "Legendary", order = 178, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_rainbow_deck", name = "Rainbow Deck"}
})
add_achievement({
    id = "gold_card_5", name = "Gold Collection", description = "Have 5 Gold cards in your deck at once",
    category = "Collection", rarity = "Rare", order = 179, is_tracked = false,
    progress_required = 5, reward_type = "badge", reward_data = {id = "badge_gold_cards", name = "Gold Collector", icon = "badge_gold"}
})
add_achievement({
    id = "steel_card_5", name = "Steel Collection", description = "Have 5 Steel cards in your deck at once",
    category = "Collection", rarity = "Rare", order = 180, is_tracked = false,
    progress_required = 5, reward_type = "badge", reward_data = {id = "badge_steel_cards", name = "Steel Collector", icon = "badge_silver"}
})
add_achievement({
    id = "glass_card_5", name = "Fragile Collection", description = "Have 5 Glass cards in your deck at once",
    category = "Collection", rarity = "Rare", order = 181, is_tracked = false,
    progress_required = 5, reward_type = "badge", reward_data = {id = "badge_glass_cards", name = "Glass Collector", icon = "badge_silver"}
})

-- ============================================
-- CATEGORY: QUEST MASTERY (6 achievements)
-- ============================================

add_achievement({
    id = "quests_10", name = "Quest Beginner", description = "Complete 10 quests",
    category = "Daily Champion", rarity = "Common", order = 182, is_tracked = true,
    progress_required = 10, reward_type = "badge", reward_data = {id = "badge_quest_10", name = "Quest Beginner", icon = "badge_bronze"}
})
add_achievement({
    id = "quests_50", name = "Quest Adept", description = "Complete 50 quests",
    category = "Daily Champion", rarity = "Rare", order = 183, is_tracked = true,
    progress_required = 50, reward_type = "badge", reward_data = {id = "badge_quest_50", name = "Quest Adept", icon = "badge_silver"}
})
add_achievement({
    id = "quests_100", name = "Quest Master", description = "Complete 100 quests",
    category = "Daily Champion", rarity = "Epic", order = 184, is_tracked = true,
    progress_required = 100, reward_type = "title", reward_data = {id = "title_quest_master", name = "Quest Master"}
})
add_achievement({
    id = "quests_250", name = "Quest Legend", description = "Complete 250 quests",
    category = "Daily Champion", rarity = "Legendary", order = 185, is_tracked = true,
    progress_required = 250, reward_type = "title", reward_data = {id = "title_quest_legend", name = "Quest Legend"}
})
add_achievement({
    id = "all_daily_quests", name = "Daily Sweep", description = "Complete all daily quests in one day",
    category = "Daily Champion", rarity = "Epic", order = 186, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_daily_sweep", name = "Daily Sweep"}
})
add_achievement({
    id = "quest_streak_14", name = "Two Week Warrior", description = "Complete quests 14 days in a row",
    category = "Daily Champion", rarity = "Epic", order = 187, is_tracked = true,
    progress_required = 14, reward_type = "title", reward_data = {id = "title_two_week", name = "Two Week Warrior"}
})

-- ============================================
-- CATEGORY: SECRET ADVANCED (13 achievements)
-- ============================================

add_achievement({
    id = "secret_all_aces", name = "Ace High",
    description = "Play a hand with all Aces",
    secret_hint = "Four of a kind, but better...",
    category = "Secret", rarity = "Secret", order = 188, is_secret = true, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_ace_high", name = "Ace High"}
})
add_achievement({
    id = "secret_full_consumables", name = "Stocked Up",
    description = "Fill all consumable slots at once",
    secret_hint = "No room at the inn...",
    category = "Secret", rarity = "Secret", order = 189, is_secret = true, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_stocked", name = "Stocked Up", icon = "badge_gold"}
})
add_achievement({
    id = "secret_13_cards", name = "Baker's Dozen",
    description = "Hold exactly 13 cards in your hand",
    secret_hint = "An unlucky number...",
    category = "Secret", rarity = "Secret", order = 190, is_secret = true, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_bakers_dozen", name = "Baker's Dozen"}
})
add_achievement({
    id = "secret_one_card_deck", name = "Last Card Standing",
    description = "Win a blind with only 1 card in your deck",
    secret_hint = "One is enough...",
    category = "Secret", rarity = "Secret", order = 191, is_secret = true, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_last_card", name = "Last Card"}
})
add_achievement({
    id = "secret_all_face", name = "Face Off",
    description = "Play a 5-card hand with all face cards",
    secret_hint = "Put on a brave face...",
    category = "Secret", rarity = "Secret", order = 192, is_secret = true, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_face_off", name = "Face Off"}
})
add_achievement({
    id = "secret_rainbow", name = "Rainbow Collection",
    description = "Own Jokers of Common, Uncommon, Rare, and Legendary rarity at once",
    secret_hint = "Collect the full spectrum...",
    category = "Secret", rarity = "Secret", order = 193, is_secret = true, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_rainbow", name = "Rainbow"}
})
add_achievement({
    id = "secret_debt", name = "In the Red",
    description = "Go into debt",
    secret_hint = "Spend beyond your means...",
    category = "Secret", rarity = "Secret", order = 194, is_secret = true, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_debt", name = "In Debt", icon = "badge_bronze"}
})
add_achievement({
    id = "secret_negative_win", name = "Debt Victory",
    description = "Win a run while in debt",
    secret_hint = "Victory from the red...",
    category = "Secret", rarity = "Secret", order = 195, is_secret = true, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_debt_victory", name = "Debt Victor"}
})
add_achievement({
    id = "secret_flush_five_royal", name = "Ultimate Hand",
    description = "Play a Flush Five with face cards",
    secret_hint = "The ultimate poker hand...",
    category = "Secret", rarity = "Secret", order = 196, is_secret = true, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_ultimate_hand", name = "Ultimate"}
})
add_achievement({
    id = "secret_guide_reader", name = "Student",
    description = "Open a guide",
    secret_hint = "Knowledge is power...",
    category = "Secret", rarity = "Secret", order = 197, is_secret = true, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_student", name = "Student", icon = "badge_bronze"}
})
add_achievement({
    id = "secret_max_hand_size", name = "Big Hands",
    description = "Have a hand size of 12 or more",
    secret_hint = "The more the merrier...",
    category = "Secret", rarity = "Secret", order = 198, is_secret = true, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_big_hands", name = "Big Hands"}
})
add_achievement({
    id = "secret_10_vouchers", name = "VIP",
    description = "Have 10 vouchers redeemed in one run",
    secret_hint = "Loyal customer...",
    category = "Secret", rarity = "Secret", order = 199, is_secret = true, is_tracked = false,
    progress_required = 1, reward_type = "title", reward_data = {id = "title_vip", name = "VIP"}
})
add_achievement({
    id = "secret_all_suits_hand", name = "Full Spectrum",
    description = "Play a hand with all 4 suits represented",
    secret_hint = "A suit for every occasion...",
    category = "Secret", rarity = "Secret", order = 200, is_secret = true, is_tracked = false,
    progress_required = 1, reward_type = "badge", reward_data = {id = "badge_full_spectrum", name = "Full Spectrum", icon = "badge_silver"}
})

-- ============================================
-- CATEGORY: MULTIPLAYER (6 achievements)
-- ============================================

add_achievement({
    id = "mp_first_blood",
    name = "First Blood",
    description = "Outscore your opponent in a multiplayer blind",
    category = "Multiplayer",
    rarity = "Common",
    order = 201,
    is_tracked = true,
    progress_required = 1,
    condition = function()
        return G and G.GAME and (G.GAME.mp_boss_wins or 0) >= 1
    end,
    reward_type = "title",
    reward_data = { id = "title_first_blood", name = "First Blood" }
})

add_achievement({
    id = "mp_comeback_kid",
    name = "Comeback Kid",
    description = "Win a match from 1 life remaining",
    category = "Multiplayer",
    rarity = "Rare",
    order = 202,
    is_tracked = false,
    progress_required = 1,
    condition = function()
        return G and G.GAME and G.GAME.mp_won_from_one_life == true
    end,
    reward_type = "title",
    reward_data = { id = "title_comeback_kid", name = "Comeback Kid" }
})

add_achievement({
    id = "mp_nemesis",
    name = "Arch-Rival",
    description = "Win 10 multiplayer matches",
    category = "Multiplayer",
    rarity = "Rare",
    order = 203,
    is_tracked = true,
    progress_required = 10,
    condition = function()
        if not G then return false end
        local wins = 0
        pcall(function()
            local profile = G.PROFILES[G.SETTINGS.profile]
            if profile and profile.progression then
                wins = profile.progression.mp_match_wins or 0
            end
        end)
        return wins >= 10
    end,
    reward_type = "badge",
    reward_data = { id = "badge_nemesis", name = "Arch-Rival", icon = "badge_gold" }
})

add_achievement({
    id = "mp_untouchable",
    name = "Untouchable",
    description = "Win a match without losing a life",
    category = "Multiplayer",
    rarity = "Rare",
    order = 204,
    is_tracked = false,
    progress_required = 1,
    condition = function()
        return G and G.GAME and G.GAME.mp_untouchable_flag == true
    end,
    reward_type = "title",
    reward_data = { id = "title_untouchable", name = "Untouchable" }
})

add_achievement({
    id = "mp_saboteur",
    name = "Saboteur",
    description = "Use 5 sabotage cards in one match",
    category = "Multiplayer",
    rarity = "Uncommon",
    order = 205,
    is_tracked = true,
    progress_required = 5,
    condition = function()
        return G and G.GAME and (G.GAME.bom_sabotages_used or 0) >= 5
    end,
    reward_type = "title",
    reward_data = { id = "title_saboteur", name = "Saboteur" }
})

add_achievement({
    id = "bom_daily_streak",
    name = "Daily Rival",
    description = "Play the Daily MP Challenge 7 days in a row",
    category = "Multiplayer",
    rarity = "Epic",
    order = 206,
    is_tracked = true,
    progress_required = 7,
    condition = function()
        if not G then return false end
        local streak = 0
        pcall(function()
            local profile = G.PROFILES[G.SETTINGS.profile]
            if profile and profile.progression then
                streak = profile.progression.bom_daily_streak or 0
            end
        end)
        return streak >= 7
    end,
    reward_type = "badge",
    reward_data = { id = "badge_daily_rival", name = "Daily Rival", icon = "badge_gold" }
})

local NEW_ACHIEVEMENTS = {
    {"casino_first", "Welcome In", "Visit The Casino", "Overhaul", "Common", 1},
    {"casino_visits_50", "Regular", "Visit The Casino 50 times", "Overhaul", "Rare", 50},
    {"casino_all_places", "Grand Tour", "Visit every place in The Casino", "Overhaul", "Rare", 8},
    {"forge_first", "Blacksmith", "Create a card in The Forge", "Overhaul", "Common", 1},
    {"forge_10", "Master Smith", "Create 10 cards in The Forge", "Overhaul", "Epic", 10},
    {"tailor_first", "Dressed Up", "Change your look at the Tailor", "Overhaul", "Common", 1},
    {"tailor_10", "Fashionista", "Change your look 10 times", "Overhaul", "Rare", 10},
    {"replay_first", "Rewind", "Watch a replay", "Overhaul", "Common", 1},
    {"replay_10", "Film Critic", "Watch 10 replays", "Overhaul", "Rare", 10},
    {"training_first", "Sparring Partner", "Fight a boss in the Training Grounds", "Overhaul", "Common", 1},
    {"arcade_first", "Coin Op", "Play a game in the Arcade", "Overhaul", "Common", 1},
    {"library_first", "Seed Collector", "Save a seed in the Library", "Overhaul", "Common", 1},
    {"history_first", "Historian", "Look back at your past runs", "Overhaul", "Common", 1},
    {"seeded_win", "Known Path", "Win a seeded run", "Overhaul", "Rare", 1},
    {"speed_20", "Quick Hands", "Win a run in under 20 minutes", "Runs", "Rare", 1},
    {"mp_play_1", "Shuffle Up", "Play your first multiplayer match", "Multiplayer", "Common", 1},
    {"mp_play_50", "Table Regular", "Play 50 multiplayer matches", "Multiplayer", "Rare", 50},
    {"mp_play_200", "Card Shark", "Play 200 multiplayer matches", "Multiplayer", "Epic", 200},
    {"mp_wins_50", "Table Boss", "Win 50 multiplayer matches", "Multiplayer", "Epic", 50},
    {"mp_wins_200", "House Always Wins", "Win 200 multiplayer matches", "Multiplayer", "Legendary", 200},
    {"mp_streak_3", "Hot Hand", "Win 3 multiplayer matches in a row", "Multiplayer", "Rare", 3},
    {"mp_streak_10", "Unstoppable", "Win 10 multiplayer matches in a row", "Multiplayer", "Legendary", 10},
    {"mp_pvp_25", "Duelist", "Outscore your opponent in 25 blinds", "Multiplayer", "Rare", 25},
    {"mp_pvp_100", "Blind Champion", "Outscore your opponent in 100 blinds", "Multiplayer", "Epic", 100},
    {"mp_win_nemesis", "Rival Slayer", "Win a Rivals match", "Multiplayer", "Common", 1},
    {"mp_win_faceoff", "Face to Face", "Win a FaceOff match", "Multiplayer", "Common", 1},
    {"mp_win_ranked", "Ranked Up", "Win a Ranked match", "Multiplayer", "Rare", 1},
    {"mp_ranked_10", "Climber", "Win 10 Ranked matches", "Multiplayer", "Epic", 10},
    {"mp_win_ascension", "Ascended", "Win an Ascension match", "Multiplayer", "Rare", 1},
    {"mp_win_race", "Photo Finish", "Win a Race match", "Multiplayer", "Rare", 1},
    {"mp_win_br", "Last One Standing", "Win a Battle Royale", "Multiplayer", "Epic", 1},
    {"mp_win_teams", "Team Player", "Win a Teams match", "Multiplayer", "Rare", 1},
    {"mp_win_raid", "Raid Boss", "Beat a Co-op Raid", "Multiplayer", "Rare", 1},
    {"mp_win_swap", "Switch Hitter", "Win a Switcheroo match", "Multiplayer", "Rare", 1},
    {"mp_all_modes", "Jack of All Modes", "Win a match in every multiplayer mode", "Multiplayer", "Legendary", 9},
    {"mp_random_deck", "Chaos Theory", "Win a multiplayer match with the Random Deck", "Multiplayer", "Epic", 1},
}

for i, a in ipairs(NEW_ACHIEVEMENTS) do
    add_achievement({
        id = a[1], name = a[2], description = a[3], category = a[4], rarity = a[5],
        order = (a[4] == "Overhaul" or a[4] == "Multiplayer") and (i - 100) or (300 + i), is_tracked = a[6] > 1, progress_required = a[6],
    })
end

local CATEGORY_OF = {
    ["Progression"] = "Runs", ["Scoring"] = "Hands", ["Joker Expertise"] = "Jokers & Cards", ["Collection"] = "Jokers & Cards",
    ["Deck Mastery"] = "Decks & Stakes", ["Challenge Master"] = "Decks & Stakes", ["Daily Champion"] = "Overhaul",
}
local CATEGORY_BY_ID = {
    speed_runner = "Runs", speed_demon = "Runs", perfectionist = "Runs", no_discards_win = "Runs",
}

for _, a in ipairs(ACHIEVEMENT_DEFINITIONS) do
    if a.id:find("^icon_collector_") then
        a.category = "Overhaul"
    else
        a.category = CATEGORY_BY_ID[a.id] or CATEGORY_OF[a.category] or a.category
    end
    if a.rarity == "Secret" then a.is_secret = true end
end

ACHIEVEMENT_CATEGORY_LIST = {"Runs", "Decks & Stakes", "Hands", "Jokers & Cards", "Overhaul", "Multiplayer", "Secret"}

-- ============================================
-- ACHIEVEMENT REGISTRY - Easy Add Framework
-- ============================================

AchievementRegistry = AchievementRegistry or {}

---@brief Register a new achievement (easy framework for adding new ones)
---@param data table Achievement definition
---@return boolean Success
function AchievementRegistry.register(data)
    -- Validate required fields
    if not data then
        print("[ACHIEVEMENTS] ERROR: nil achievement data")
        return false
    end
    if not data.id then
        print("[ACHIEVEMENTS] ERROR: Achievement missing id")
        return false
    end
    if not data.name then
        print("[ACHIEVEMENTS] ERROR: Achievement missing name")
        return false
    end
    if not data.description then
        print("[ACHIEVEMENTS] ERROR: Achievement missing description")
        return false
    end
    
    -- Set defaults for optional fields
    data.category = data.category or "Misc"
    data.rarity = data.rarity or "Common"
    data.is_secret = data.is_secret or false
    data.is_tracked = data.is_tracked or false
    data.progress_required = data.progress_required or 1
    data.order = data.order or (#ACHIEVEMENT_DEFINITIONS + 1)
    
    -- Add to definitions
    add_achievement(data)
    
    print("[ACHIEVEMENTS] Registered: " .. data.name)
    return true
end

---@brief Get total achievement count
---@return number count
function AchievementRegistry.count()
    return #ACHIEVEMENT_DEFINITIONS
end

---@brief Get all achievement IDs
---@return table ids
function AchievementRegistry.get_all_ids()
    local ids = {}
    for i = 1, #ACHIEVEMENT_DEFINITIONS do
        if ACHIEVEMENT_DEFINITIONS[i] and ACHIEVEMENT_DEFINITIONS[i].id then
            table.insert(ids, ACHIEVEMENT_DEFINITIONS[i].id)
        end
    end
    return ids
end

print("[ACHIEVEMENTS] Data module loaded with " .. tostring(#ACHIEVEMENT_DEFINITIONS) .. " achievements")
return ACHIEVEMENT_DEFINITIONS
