QuestManager = QuestManager or {}
local QM = QuestManager

QM.VERSION = 2
QM.DAILY_COUNT = 4
QM.WEEKLY_COUNT = 4

QM.REWARDS = {
  easy = {xp = 250, bc = 50},
  medium = {xp = 500, bc = 100},
  hard = {xp = 1000, bc = 250},
  feature = {xp = 400, bc = 120},
  w_medium = {xp = 2000, bc = 400},
  w_hard = {xp = 4000, bc = 800},
}
QM.STAGE_XP = {500, 1500, 4000, 10000, 25000}
QM.STAGE_BC = {50, 150, 400, 1000, 2500}

local DAILY = {
  {id = "d_hands", tier = "easy", ev = "hand_played", n = 20, name = "Hand Dealer", desc = "Play #1# hands"},
  {id = "d_discard", tier = "easy", ev = "cards_discarded", sum = true, n = 15, name = "Card Thrower", desc = "Discard #1# cards"},
  {id = "d_money", tier = "easy", ev = "money_earned", sum = true, n = 75, name = "Pocket Change", desc = "Earn $#1# in runs"},
  {id = "d_tarot", tier = "easy", ev = "consumable_used", set = "Tarot", n = 3, name = "Tarot Reader", desc = "Use #1# Tarot cards"},
  {id = "d_planet", tier = "easy", ev = "consumable_used", set = "Planet", n = 3, name = "Stargazer", desc = "Use #1# Planet cards"},
  {id = "d_joker_buy", tier = "easy", ev = "joker_bought", n = 2, name = "Joker Shopper", desc = "Buy #1# Jokers"},
  {id = "d_boss", tier = "easy", ev = "boss_defeated", n = 2, name = "Boss Slayer", desc = "Defeat #1# Boss Blinds"},
  {id = "d_blinds", tier = "easy", ev = "blind_won", n = 6, name = "Blind Runner", desc = "Beat #1# Blinds"},
  {id = "d_ante4", tier = "easy", ev = "ante_reached", at = "ante", min = 4, n = 1, name = "Getting Started", desc = "Reach Ante #2#"},
  {id = "d_flush", tier = "easy", ev = "hand_played", hand = "Flush", n = 2, name = "Flush Finder", desc = "Play #1# Flushes"},
  {id = "d_straight", tier = "easy", ev = "hand_played", hand = "Straight", n = 2, name = "Straight Shooter", desc = "Play #1# Straights"},
  {id = "d_two_pair", tier = "easy", ev = "hand_played", hand = "Two Pair", n = 3, name = "Double Trouble", desc = "Play #1# Two Pairs"},
  {id = "d_packs", tier = "easy", ev = "pack_opened", n = 3, name = "Pack Opener", desc = "Open #1# Booster Packs"},
  {id = "d_reroll", tier = "easy", ev = "shop_reroll", n = 4, name = "Lucky Reroller", desc = "Reroll the shop #1# times"},
  {id = "d_sell", tier = "easy", ev = "card_sold", n = 3, name = "Card Seller", desc = "Sell #1# cards"},
  {id = "d_skip", tier = "easy", ev = "blind_skipped", n = 2, name = "Tag Collector", desc = "Skip #1# Blinds"},
  {id = "d_voucher", tier = "easy", ev = "voucher_redeemed", n = 1, name = "Voucher Finder", desc = "Redeem a Voucher"},
  {id = "d_runs", tier = "easy", ev = "run_start", n = 2, name = "Shuffle Up", desc = "Start #1# runs"},

  {id = "d_win", tier = "medium", ev = "run_won", n = 1, name = "Victory", desc = "Win a run"},
  {id = "d_ante8", tier = "medium", ev = "ante_reached", at = "ante", min = 8, n = 1, name = "Final Ante", desc = "Reach Ante #2#"},
  {id = "d_boss5", tier = "medium", ev = "boss_defeated", n = 5, name = "Boss Hunter", desc = "Defeat #1# Boss Blinds"},
  {id = "d_full_house", tier = "medium", ev = "hand_played", hand = "Full House", n = 2, name = "Full House Party", desc = "Play #1# Full Houses"},
  {id = "d_three_kind", tier = "medium", ev = "hand_played", hand = "Three of a Kind", n = 4, name = "Triple Threat", desc = "Play Three of a Kind #1# times"},
  {id = "d_score50k", tier = "medium", ev = "hand_played", at = "score", min = 50000, n = 1, name = "High Scorer", desc = "Score #2# or more in one hand"},
  {id = "d_jokers5", tier = "medium", ev = "jokers_owned", at = "count", min = 5, n = 1, name = "Full Bench", desc = "Have #2# Jokers at once"},
  {id = "d_enhance", tier = "medium", ev = "card_enhanced", n = 4, name = "Card Enhancer", desc = "Enhance #1# playing cards"},
  {id = "d_edition", tier = "medium", ev = "edition_obtained", n = 1, name = "Shiny Find", desc = "Get a card with an Edition"},
  {id = "d_spectral", tier = "medium", ev = "consumable_used", set = "Spectral", n = 2, name = "Spectral Touch", desc = "Use #1# Spectral cards"},
  {id = "d_consumables", tier = "medium", ev = "consumable_used", n = 10, name = "Item Hoarder", desc = "Use #1# consumables"},
  {id = "d_money250", tier = "medium", ev = "money_earned", sum = true, n = 250, name = "Growing Savings", desc = "Earn $#1# in runs"},
  {id = "d_voucher2", tier = "medium", ev = "voucher_redeemed", n = 2, name = "Voucher Fan", desc = "Redeem #1# Vouchers"},
  {id = "d_packs6", tier = "medium", ev = "pack_opened", n = 6, name = "Pack Rat", desc = "Open #1# Booster Packs"},
  {id = "d_blinds15", tier = "medium", ev = "blind_won", n = 15, name = "Blind Marathon", desc = "Beat #1# Blinds"},
  {id = "d_rare", tier = "medium", ev = "joker_obtained", at = "rarity", min = 3, n = 1, name = "Rare Taste", desc = "Get a Rare or Legendary Joker"},

  {id = "d_win2", tier = "hard", ev = "run_won", n = 2, name = "Double Victory", desc = "Win #1# runs"},
  {id = "d_win_red", tier = "hard", ev = "run_won", at = "stake", min = 2, n = 1, name = "Red Challenge", desc = "Win on Red Stake or higher"},
  {id = "d_win_black", tier = "hard", ev = "run_won", at = "stake", min = 4, n = 1, name = "Black Challenge", desc = "Win on Black Stake or higher"},
  {id = "d_score500k", tier = "hard", ev = "hand_played", at = "score", min = 500000, n = 1, name = "Mega Scorer", desc = "Score #2# or more in one hand"},
  {id = "d_four_kind", tier = "hard", ev = "hand_played", hand = "Four of a Kind", n = 2, name = "Quad Squad", desc = "Play Four of a Kind #1# times"},
  {id = "d_straight_flush", tier = "hard", ev = "hand_played", hand = "Straight Flush", n = 1, name = "Straight Flush!", desc = "Play a Straight Flush"},
  {id = "d_no_joker_win", tier = "hard", ev = "run_won", flag = "no_jokers_bought", n = 1, name = "Pure Skill", desc = "Win a run without buying a Joker"},
  {id = "d_legendary", tier = "hard", ev = "joker_obtained", at = "rarity", min = 4, n = 1, name = "Legendary Find", desc = "Get a Legendary Joker"},
  {id = "d_ante10", tier = "hard", ev = "ante_reached", at = "ante", min = 10, n = 1, name = "Endless Road", desc = "Reach Ante #2#"},
  {id = "d_boss10", tier = "hard", ev = "boss_defeated", n = 10, name = "Boss Slayer Pro", desc = "Defeat #1# Boss Blinds"},
  {id = "d_money600", tier = "hard", ev = "money_earned", sum = true, n = 600, name = "Wealthy Player", desc = "Earn $#1# in runs"},

  {id = "f_mp_match", tier = "feature", ev = "mp_match", n = 1, area = "mp", name = "Table Talk", desc = "Play a Multiplayer match"},
  {id = "f_mp_win", tier = "feature", ev = "mp_match", flag = "won", n = 1, area = "mp", name = "Head to Head", desc = "Win a Multiplayer match"},
  {id = "f_arcade", tier = "feature", ev = "minigame_played", n = 2, area = "casino", name = "Arcade Break", desc = "Play #1# Arcade games in The Casino"},
  {id = "f_practice", tier = "feature", ev = "boss_practice", n = 1, area = "casino", name = "Training Day", desc = "Fight a boss in the Training Grounds"},
  {id = "f_daily", tier = "feature", ev = "daily_started", n = 1, area = "daily", name = "Daily Ritual", desc = "Play the Daily Challenge"},
  {id = "f_tailor", tier = "feature", ev = "cosmetic_equipped", n = 1, area = "casino", name = "New Look", desc = "Change your look at the Tailor"},
  {id = "f_forge", tier = "feature", ev = "forge_created", n = 1, area = "forge", name = "Smith", desc = "Make a new card in The Forge"},
  {id = "f_replay", tier = "feature", ev = "replay_watched", n = 1, area = "casino", name = "Film Study", desc = "Watch a replay of a past run"},
  {id = "f_deck", tier = "feature", ev = "deck_saved", n = 1, area = "forge", name = "Deck Builder", desc = "Save a deck in the Deck Creator"},
  {id = "f_achievement", tier = "feature", ev = "achievement_unlocked", n = 1, area = "trophy", name = "Trophy Shelf", desc = "Unlock an achievement"},
}

local WEEKLY = {
  {id = "w_wins5", tier = "medium", ev = "run_won", n = 5, name = "Weekly Winner", desc = "Win #1# runs"},
  {id = "w_decks3", tier = "medium", ev = "run_won", uniq = "deck", n = 3, name = "Deck Explorer", desc = "Win with #1# different decks"},
  {id = "w_boss20", tier = "medium", ev = "boss_defeated", n = 20, name = "Boss Crusher", desc = "Defeat #1# Boss Blinds"},
  {id = "w_hands150", tier = "medium", ev = "hand_played", n = 150, name = "Hand Veteran", desc = "Play #1# hands"},
  {id = "w_money1500", tier = "medium", ev = "money_earned", sum = true, n = 1500, name = "Big Earner", desc = "Earn $#1# in runs"},
  {id = "w_consumables30", tier = "medium", ev = "consumable_used", n = 30, name = "Item Expert", desc = "Use #1# consumables"},
  {id = "w_jokers15", tier = "medium", ev = "joker_bought", n = 15, name = "Joker Expert", desc = "Buy #1# Jokers"},
  {id = "w_tarots15", tier = "medium", ev = "consumable_used", set = "Tarot", n = 15, name = "Tarot Master", desc = "Use #1# Tarot cards"},
  {id = "w_planets15", tier = "medium", ev = "consumable_used", set = "Planet", n = 15, name = "Planet Master", desc = "Use #1# Planet cards"},
  {id = "w_vouchers6", tier = "medium", ev = "voucher_redeemed", n = 6, name = "Voucher Hunter", desc = "Redeem #1# Vouchers"},
  {id = "w_blinds60", tier = "medium", ev = "blind_won", n = 60, name = "Blind Breaker", desc = "Beat #1# Blinds"},
  {id = "w_flush10", tier = "medium", ev = "hand_played", hand = "Flush", n = 10, name = "Flush Expert", desc = "Play #1# Flushes"},
  {id = "w_straight10", tier = "medium", ev = "hand_played", hand = "Straight", n = 10, name = "Straight Expert", desc = "Play #1# Straights"},
  {id = "w_full_house8", tier = "medium", ev = "hand_played", hand = "Full House", n = 8, name = "Full House Fanatic", desc = "Play #1# Full Houses"},
  {id = "w_enhance15", tier = "medium", ev = "card_enhanced", n = 15, name = "Enhancement Pro", desc = "Enhance #1# playing cards"},
  {id = "w_editions5", tier = "medium", ev = "edition_obtained", n = 5, name = "Edition Collector", desc = "Get #1# cards with an Edition"},
  {id = "w_packs20", tier = "medium", ev = "pack_opened", n = 20, name = "Booster Binge", desc = "Open #1# Booster Packs"},
  {id = "w_reroll25", tier = "medium", ev = "shop_reroll", n = 25, name = "Shop Explorer", desc = "Reroll the shop #1# times"},
  {id = "w_sell25", tier = "medium", ev = "card_sold", n = 25, name = "Card Trader", desc = "Sell #1# cards"},
  {id = "w_skip10", tier = "medium", ev = "blind_skipped", n = 10, name = "Skip Strategist", desc = "Skip #1# Blinds"},
  {id = "w_dailies7", tier = "medium", ev = "quest_claimed", of = "daily", n = 7, name = "Daily Habit", desc = "Claim #1# daily quests"},
  {id = "w_arcade8", tier = "medium", ev = "minigame_played", n = 8, area = "casino", name = "Arcade Regular", desc = "Play #1# Arcade games in The Casino"},
  {id = "w_mp3", tier = "medium", ev = "mp_match", n = 3, area = "mp", name = "Matchmaker", desc = "Play #1# Multiplayer matches"},

  {id = "w_wins12", tier = "hard", ev = "run_won", n = 12, name = "Winning Week", desc = "Win #1# runs"},
  {id = "w_stakes3", tier = "hard", ev = "run_won", uniq = "stake", n = 3, name = "Stake Climber", desc = "Win on #1# different stakes"},
  {id = "w_win_gold", tier = "hard", ev = "run_won", at = "stake", min = 8, n = 1, name = "Gold Champion", desc = "Win on Gold Stake or higher"},
  {id = "w_streak3", tier = "hard", ev = "run_won", streak = true, n = 3, name = "Hot Streak", desc = "Win #1# runs in a row"},
  {id = "w_score1m", tier = "hard", ev = "hand_played", at = "score", min = 1000000, n = 3, name = "Millionaire Club", desc = "Score #2# or more in one hand, #1# times"},
  {id = "w_legendary2", tier = "hard", ev = "joker_obtained", at = "rarity", min = 4, n = 2, name = "Legendary Hunter", desc = "Get #1# Legendary Jokers"},
  {id = "w_ante12", tier = "hard", ev = "ante_reached", at = "ante", min = 12, n = 1, name = "Deep Endless", desc = "Reach Ante #2#"},
  {id = "w_boss50", tier = "hard", ev = "boss_defeated", n = 50, name = "Boss Exterminator", desc = "Defeat #1# Boss Blinds"},
  {id = "w_mp_wins3", tier = "hard", ev = "mp_match", flag = "won", n = 3, area = "mp", name = "Rival Breaker", desc = "Win #1# Multiplayer matches"},
  {id = "w_dailies18", tier = "hard", ev = "quest_claimed", of = "daily", n = 18, name = "Daily Warrior", desc = "Claim #1# daily quests"},
  {id = "w_achievements2", tier = "hard", ev = "achievement_unlocked", n = 2, area = "trophy", name = "Trophy Hunter", desc = "Unlock #1# achievements"},
}

local LONG = {
  {id = "j_wins", desc1 = "Win a run", ev = "run_won", stages = {1, 5, 25, 100, 250}, name = "Champion's Road", desc = "Win #1# runs", seed = "wins", ach = "wins_100"},
  {id = "j_hands", ev = "hand_played", stages = {100, 500, 2000, 5000, 10000}, name = "Card Sharp", desc = "Play #1# hands", seed = "c_hands_played", ach = "hands_played_10000"},
  {id = "j_bosses", ev = "boss_defeated", stages = {10, 50, 150, 400, 1000}, name = "Boss Breaker", desc = "Defeat #1# Boss Blinds", ach = "boss_defeated_100"},
  {id = "j_ante", ev = "ante_reached", best = "ante", stages = {4, 8, 12, 16, 20}, name = "Into the Deep", desc = "Reach Ante #1#", ach = "ante_20"},
  {id = "j_score", ev = "hand_played", best = "score", stages = {10000, 100000, 1000000, 10000000, 100000000}, name = "Big Numbers", desc = "Score #1# in one hand", ach = "score_100m"},
  {id = "j_stakes", ev = "run_won", best = "stake", stages = {2, 4, 6, 8}, fmt = "stake", name = "Stake Ladder", desc = "Win on #1# Stake or higher", ach = "stake_gold"},
  {id = "j_decks", ev = "run_won", uniq = "deck", stages = {3, 8, 15}, name = "Deck Master", desc = "Win with #1# different decks"},
  {id = "j_money", ev = "money_earned", sum = true, stages = {1000, 10000, 50000, 200000}, name = "Fortune", desc = "Earn $#1# in runs", seed = "c_dollars_earned", ach = "money_5000"},
  {id = "j_jokers", ev = "joker_obtained", stages = {25, 100, 300, 1000}, name = "Joker Collector", desc = "Get #1# Jokers", ach = "jokers_obtained_500"},
  {id = "j_legendary", desc1 = "Get a Legendary Joker", ev = "joker_obtained", at = "rarity", min = 4, stages = {1, 5, 15}, name = "Legend Seeker", desc = "Get #1# Legendary Jokers", ach = "legendary_obtained"},
  {id = "j_consumables", ev = "consumable_used", stages = {50, 250, 1000, 3000}, name = "Arcana", desc = "Use #1# consumables", ach = "consumables_1000"},
  {id = "j_vouchers", ev = "voucher_redeemed", stages = {10, 50, 150}, name = "Coupon Clipper", desc = "Redeem #1# Vouchers", seed = "c_vouchers_bought", ach = "secret_10_vouchers"},
  {id = "j_editions", ev = "edition_obtained", stages = {5, 25, 100}, name = "Shiny Things", desc = "Get #1# cards with an Edition", ach = "editions_50"},
  {id = "j_enhance", ev = "card_enhanced", stages = {20, 100, 400}, name = "Workshop", desc = "Enhance #1# playing cards", ach = "enhance_200"},
  {id = "j_packs", ev = "pack_opened", stages = {25, 100, 400}, name = "Pack Hunter", desc = "Open #1# Booster Packs"},
  {id = "j_mp", desc1 = "Play a Multiplayer match", ev = "mp_match", stages = {1, 10, 50, 200}, area = "mp", name = "Table Regular", desc = "Play #1# Multiplayer matches"},
  {id = "j_mp_wins", desc1 = "Win a Multiplayer match", ev = "mp_match", flag = "won", stages = {1, 10, 50, 150}, area = "mp", name = "Rival of the Table", desc = "Win #1# Multiplayer matches", ach = "mp_nemesis"},
  {id = "j_arcade", ev = "minigame_played", stages = {5, 25, 100}, area = "casino", name = "Arcade Legend", desc = "Play #1# Arcade games in The Casino"},
  {id = "j_casino", desc1 = "Buy an item with Balacoin in The Casino", ev = "casino_purchase", stages = {1, 5, 15, 40}, area = "casino", name = "High Roller", desc = "Buy #1# items with Balacoin in The Casino"},
  {id = "j_forge", desc1 = "Make a card in The Forge", ev = "forge_created", stages = {1, 5, 20}, area = "forge", name = "Master Smith", desc = "Make #1# cards in The Forge"},
  {id = "j_practice", desc1 = "Fight a boss in the Training Grounds", ev = "boss_practice", stages = {1, 10, 50}, area = "casino", name = "Sparring Partner", desc = "Fight #1# bosses in the Training Grounds"},
  {id = "j_daily", desc1 = "Play the Daily Challenge", ev = "daily_started", stages = {1, 7, 30}, area = "daily", name = "Every Day", desc = "Play #1# Daily Challenges", ach = "daily_complete_30"},
  {id = "j_achievements", ev = "achievement_unlocked", stages = {5, 25, 75, 150}, area = "trophy", name = "Trophy Room", desc = "Unlock #1# achievements"},
  {id = "j_quests", ev = "quest_claimed", not_kind = "long", stages = {10, 50, 150, 400}, name = "Questmaster", desc = "Claim #1# daily or weekly quests", seed = "quests", ach = "quests_250"},
}

local DEFS = {}
for _, d in ipairs(DAILY) do d.kind = "daily"; DEFS[d.id] = d end
for _, d in ipairs(WEEKLY) do d.kind = "weekly"; DEFS[d.id] = d end
for _, d in ipairs(LONG) do d.kind = "long"; DEFS[d.id] = d end
QM.DAILY, QM.WEEKLY, QM.LONG, QM.DEFS = DAILY, WEEKLY, LONG, DEFS
QM.links = QM.links or {}

local rng
local function rand(n)
  if not rng then
    if love and love.math and love.math.newRandomGenerator then
      rng = love.math.newRandomGenerator(os.time())
    else
      local s = os.time() % 2147483647
      rng = {random = function(_, k) s = (s * 16807) % 2147483647; return s % k + 1 end}
    end
  end
  return rng:random(n)
end

local function profile()
  if not (G and G.PROFILES and G.SETTINGS and G.SETTINGS.profile) then return nil end
  return G.PROFILES[G.SETTINGS.profile]
end

function QM.data()
  local p = profile()
  if not p then return nil end
  local q = p.quests
  if type(q) ~= "table" or q.v ~= QM.VERSION then
    local old = type(q) == "table" and q or {}
    q = {
      v = QM.VERSION,
      daily = {}, weekly = {}, long = {},
      recent_daily = {}, recent_weekly = {},
      day = "", week = "", reroll_day = "",
      total = tonumber(old.total_quests_completed) or 0,
      daily_claimed_days = {}, daily_streak = 0, last_full_day = "",
    }
    p.quests = q
    QM.seed_long(q, p)
  end
  q.daily = q.daily or {}
  q.weekly = q.weekly or {}
  q.long = q.long or {}
  return q
end

local function career(p, key)
  local cs = p and p.career_stats
  return cs and tonumber(cs[key]) or 0
end

function QM.seed_long(q, p)
  for _, d in ipairs(LONG) do
    local st = {p = 0, s = 0}
    local v = 0
    if d.seed == "wins" then v = math.max(career(p, "c_wins"), tonumber(p.progression and p.progression.total_wins) or 0)
    elseif d.seed == "quests" then v = q.total or 0
    elseif d.seed then v = career(p, d.seed) end
    st.p = math.floor(v)
    for i, t in ipairs(d.stages) do
      if st.p >= t then st.s = i end
    end
    q.long[d.id] = st
  end
end

function QM.utc_date(t) return os.date("!%Y-%m-%d", t) end

function QM.week_start(t)
  t = t or os.time()
  local wd = tonumber(os.date("!%w", t))
  local back = (wd + 6) % 7
  return os.date("!%Y-%m-%d", t - back * 86400)
end

local function new_inst(d)
  return {id = d.id, p = 0, done = false, claimed = false}
end

local function pick(pool, tier, avoid)
  local c = {}
  for _, d in ipairs(pool) do
    if d.tier == tier and not avoid[d.id] then c[#c + 1] = d end
  end
  if #c == 0 then
    for _, d in ipairs(pool) do
      if d.tier == tier then c[#c + 1] = d end
    end
  end
  if #c == 0 then return nil end
  return c[rand(#c)]
end

local function as_set(list)
  local s = {}
  for _, v in ipairs(list or {}) do s[v] = true end
  return s
end

function QM.generate_daily(q)
  q.recent_daily = q.recent_daily or {}
  for _, i in ipairs(q.daily or {}) do q.recent_daily[#q.recent_daily + 1] = i.id end
  while #q.recent_daily > 16 do table.remove(q.recent_daily, 1) end
  local avoid = as_set(q.recent_daily)
  q.daily = {}
  for _, tier in ipairs({"easy", "medium", "hard", "feature"}) do
    local d = pick(DAILY, tier, avoid)
    if d then q.daily[#q.daily + 1] = new_inst(d); avoid[d.id] = true end
  end
end

function QM.generate_weekly(q)
  q.recent_weekly = q.recent_weekly or {}
  for _, i in ipairs(q.weekly or {}) do q.recent_weekly[#q.recent_weekly + 1] = i.id end
  while #q.recent_weekly > 8 do table.remove(q.recent_weekly, 1) end
  local avoid = as_set(q.recent_weekly)
  q.weekly = {}
  for _, tier in ipairs({"medium", "medium", "hard", "hard"}) do
    local d = pick(WEEKLY, tier, avoid)
    if d then q.weekly[#q.weekly + 1] = new_inst(d); avoid[d.id] = true end
  end
end

function QM.refresh(now)
  local q = QM.data()
  if not q then return nil end
  now = now or os.time()
  local day, week = QM.utc_date(now), QM.week_start(now)
  local changed = false
  if q.day ~= day then
    QM.generate_daily(q)
    q.day = day
    changed = true
  end
  if q.week ~= week then
    QM.generate_weekly(q)
    q.week = week
    changed = true
  end
  for id, _ in pairs(q.long) do
    if not DEFS[id] then q.long[id] = nil end
  end
  for _, d in ipairs(LONG) do
    if not q.long[d.id] then q.long[d.id] = {p = 0, s = 0}; changed = true end
  end
  if changed then QM.queue_save() end
  return q
end

function QM.init()
  local ok, q = pcall(QM.refresh)
  QM.initialized = ok and q ~= nil
  return QM.initialized
end

function QM.check_daily_reset() QM.refresh() end
function QM.check_weekly_reset() QM.refresh() end

function QM.queue_save(force)
  if not (G and G.save_progress) then return end
  if force or not (G.E_MANAGER and Event) then
    QM.save_pending = false
    pcall(function() G:save_progress() end)
    return
  end
  if QM.save_pending then return end
  QM.save_pending = true
  G.E_MANAGER:add_event(Event({trigger = 'after', delay = 1.5, timer = 'REAL', blocking = false, blockable = false, no_delete = true,
    func = function()
      if QM.save_pending then
        QM.save_pending = false
        pcall(function() G:save_progress() end)
      end
      return true
    end}))
end

local function stage_target(d, st)
  return d.stages[math.min((st.s or 0) + 1, #d.stages)]
end

function QM.target(d, inst)
  if d.kind == "long" then return stage_target(d, inst) end
  return d.n
end

function QM.long_ready(d, st)
  local t = d.stages[(st.s or 0) + 1]
  return t ~= nil and (st.p or 0) >= t
end

function QM.long_finished(d, st)
  return (st.s or 0) >= #d.stages
end

local function matches(d, data)
  if d.hand and data.hand ~= d.hand then return false end
  if d.set and data.set ~= d.set then return false end
  if d.of and data.kind ~= d.of then return false end
  if d.not_kind and data.kind == d.not_kind then return false end
  if d.at and (tonumber(data[d.at]) or 0) < (d.min or 0) then return false end
  if d.flag and not data[d.flag] then return false end
  return true
end

local function step_amount(d, inst, data)
  if d.best then
    local v = tonumber(data[d.best]) or 0
    if v > (inst.p or 0) then return v - (inst.p or 0) end
    return 0
  end
  if d.uniq then
    local k = data[d.uniq]
    if k == nil then return 0 end
    inst.seen = inst.seen or {}
    k = tostring(k)
    if inst.seen[k] then return 0 end
    inst.seen[k] = true
    return 1
  end
  if d.sum then return math.max(0, math.floor(tonumber(data.amount) or 0)) end
  return 1
end

QM.completed_queue = QM.completed_queue or {}

function QM.handle(name, data)
  local q = QM.refresh()
  if not q then return end
  data = data or {}
  local any, done_any = false, false
  for _, list in ipairs({q.daily, q.weekly}) do
    for _, inst in ipairs(list) do
      local d = DEFS[inst.id]
      if d and not inst.done and not inst.claimed then
        if d.streak and name == "run_lost" then
          if (inst.p or 0) > 0 then inst.p = 0; inst.seen = nil; any = true end
        elseif d.ev == name and matches(d, data) then
          local a = step_amount(d, inst, data)
          if a > 0 then
            inst.p = math.min((inst.p or 0) + a, d.n)
            any = true
            if inst.p >= d.n then
              inst.done = true
              done_any = true
              QM.on_complete(d, inst)
            end
          end
        end
      end
    end
  end
  for _, d in ipairs(LONG) do
    local st = q.long[d.id]
    if st and d.ev == name and not QM.long_finished(d, st) and matches(d, data) then
      local before = QM.long_ready(d, st)
      local a = step_amount(d, st, data)
      if a > 0 then
        st.p = (st.p or 0) + a
        any = true
        if not before and QM.long_ready(d, st) then
          done_any = true
          QM.on_complete(d, st)
        end
      end
    end
  end
  if any then QM.queue_save(done_any) end
end

function QM.on_complete(d, inst)
  QM.completed_queue[#QM.completed_queue + 1] = {id = d.id}
  if QM.popup then pcall(QM.popup, d, inst) end
end

function QM.find(id)
  local q = QM.data()
  if not q then return nil end
  for _, list in ipairs({q.daily, q.weekly}) do
    for idx, inst in ipairs(list) do
      if inst.id == id then return inst, DEFS[id], idx end
    end
  end
  if q.long[id] then return q.long[id], DEFS[id] end
end

function QM.claimable(id)
  local inst, d = QM.find(id)
  if not (inst and d) then return false end
  if d.kind == "long" then return QM.long_ready(d, inst) end
  return inst.done and not inst.claimed
end

function QM.reward(d, inst)
  if d.kind == "long" then
    local i = math.min((inst.s or 0) + 1, #QM.STAGE_XP)
    return QM.STAGE_XP[i], QM.STAGE_BC[i]
  end
  local r = QM.REWARDS[d.kind == "weekly" and ("w_" .. d.tier) or d.tier] or QM.REWARDS.easy
  return r.xp, r.bc
end

function QM.give(xp, bc)
  local p = profile()
  if not p then return end
  if progression_init then progression_init() end
  p.progression = p.progression or {}
  local pr = p.progression
  pr.total_xp = (tonumber(pr.total_xp) or 0) + (xp or 0)
  pr.balacoin = (tonumber(pr.balacoin) or 0) + (bc or 0)
  pr.total_balacoin_earned = (tonumber(pr.total_balacoin_earned) or 0) + (bc or 0)
  pr.xp_sources = pr.xp_sources or {}
  pr.xp_sources.quests = (pr.xp_sources.quests or 0) + (xp or 0)
  if check_level_up then pcall(check_level_up) end
  if check_milestones then pcall(check_milestones) end
end

function QM.claim(id)
  local inst, d = QM.find(id)
  if not (inst and d) or not QM.claimable(id) then return false end
  local q = QM.data()
  local xp, bc = QM.reward(d, inst)
  if d.kind == "long" then
    inst.s = (inst.s or 0) + 1
  else
    inst.claimed = true
    q.total = (q.total or 0) + 1
    if d.kind == "daily" then QM.note_daily_claim(q) end
  end
  for i = #QM.completed_queue, 1, -1 do
    if QM.completed_queue[i].id == id and not QM.claimable(id) then table.remove(QM.completed_queue, i) end
  end
  QM.give(xp, bc)
  local p = profile()
  if p and p.progression then
    if d.kind == "daily" then p.progression.daily_quests_completed = (p.progression.daily_quests_completed or 0) + 1 end
    if d.kind == "weekly" then p.progression.weekly_quests_completed = (p.progression.weekly_quests_completed or 0) + 1 end
    if d.kind ~= "long" then p.progression.total_quests_completed = (p.progression.total_quests_completed or 0) + 1 end
  end
  if d.kind ~= "long" and AchievementManager and AchievementManager.on_quest_claimed then
    pcall(AchievementManager.on_quest_claimed)
  end
  if ProgressEvents then ProgressEvents.emit("quest_claimed", {id = id, kind = d.kind, xp = xp, bc = bc}) end
  QM.queue_save(true)
  return true, xp, bc
end

function QM.note_daily_claim(q)
  local all = #q.daily > 0
  for _, i in ipairs(q.daily) do
    if not i.claimed then all = false end
  end
  if all and q.last_full_day ~= q.day then
    local yesterday = QM.utc_date(os.time() - 86400)
    q.daily_streak = (q.last_full_day == yesterday) and ((q.daily_streak or 0) + 1) or 1
    q.last_full_day = q.day
  end
end

function QM.can_reroll()
  local q = QM.data()
  return q ~= nil and q.reroll_day ~= q.day
end

function QM.reroll(id)
  local q = QM.refresh()
  if not q or not QM.can_reroll() then return false end
  for idx, inst in ipairs(q.daily) do
    if inst.id == id and not inst.claimed and not inst.done then
      local d = DEFS[id]
      local cur = {}
      for _, i in ipairs(q.daily) do cur[i.id] = true end
      local avoid = as_set(q.recent_daily)
      for k in pairs(cur) do avoid[k] = true end
      local nd = pick(DAILY, d.tier, avoid)
      if not nd or cur[nd.id] then nd = pick(DAILY, d.tier, cur) end
      if not nd or cur[nd.id] then return false end
      q.daily[idx] = new_inst(nd)
      q.reroll_day = q.day
      QM.queue_save(true)
      return true
    end
  end
  return false
end

function QM.ready_count()
  local q = QM.data()
  if not q then return 0 end
  local n = 0
  for _, list in ipairs({q.daily, q.weekly}) do
    for _, i in ipairs(list) do
      if i.done and not i.claimed then n = n + 1 end
    end
  end
  for _, d in ipairs(LONG) do
    if q.long[d.id] and QM.long_ready(d, q.long[d.id]) then n = n + 1 end
  end
  return n
end

local function fmt_num(v)
  if number_format then return number_format(v) end
  return tostring(v)
end

function QM.text(d, inst)
  local target = QM.target(d, inst or {s = 0})
  local shown = target
  if d.fmt == "stake" and get_stake_name then shown = get_stake_name(target) else shown = fmt_num(target) end
  local desc = ProgressEvents.loc((target == 1 and d.desc1) or d.desc):gsub("#1#", function() return shown end):gsub("#2#", function() return fmt_num(d.min or 0) end)
  return ProgressEvents.loc(d.name), desc
end

function QM.progress(d, inst)
  local t = QM.target(d, inst)
  local p = math.min(inst.p or 0, t)
  if d.fmt == "stake" and get_stake_name then
    return p >= t and 1 or 0, (p >= t and 1 or 0), 1
  end
  return t > 0 and p / t or 0, p, t
end

function QM.link_achievement(quest_id, ach_id)
  QM.links[quest_id] = ach_id
end

function QM.achievement_for(d)
  local id = QM.links[d.id] or d.ach
  if not id then return nil end
  local AM = rawget(_G, "AchievementManager")
  if not (AM and AM.get_achievement) then return nil end
  local ok, a = pcall(AM.get_achievement, id)
  if not (ok and a) then return nil end
  local name = a.name
  if AM.get_display_name then
    local ok2, n = pcall(AM.get_display_name, a)
    if ok2 and n then name = n end
  end
  local unlocked = AM.is_unlocked and AM.is_unlocked(id)
  return {id = id, name = name, unlocked = unlocked and true or false}
end

QM.quest_data = setmetatable({}, {__index = function(_, k)
  local q = QM.data()
  if not q then return nil end
  if k == "daily" then
    local out = {}
    for _, i in ipairs(q.daily) do
      out[#out + 1] = {id = i.id, status = i.claimed and "claimed" or (i.done and "completed" or "active")}
    end
    return out
  elseif k == "daily_streak" then
    return q.daily_streak or 0
  end
end})

local function clean() return ProgressEvents and ProgressEvents.in_clean_run and ProgressEvents.in_clean_run() end
local function emit(name, data)
  if ProgressEvents and clean() then ProgressEvents.emit(name, data) end
end

function QM.process_event() end
function QM.on_hand_played() end
function QM.on_cards_discarded() end
function QM.on_card_enhanced() end
function QM.on_edition_obtained() end
function QM.on_consumable_used() end
function QM.on_voucher_used() end

function QM.on_hand_scored(s)
  if not s then return end
  emit("hand_played", {hand = s.hand_name, score = tonumber(s.chips) or 0})
end

function QM.on_boss_defeated()
  emit("boss_defeated", {ante = G.GAME and G.GAME.round_resets and G.GAME.round_resets.ante})
end

function QM.on_ante_reached(ante)
  emit("ante_reached", {ante = tonumber(ante) or 0})
end

function QM.on_money_earned(amount)
  if amount and amount > 0 then emit("money_earned", {amount = amount}) end
end

local function run_id()
  local g = G and G.GAME
  return g and g.pseudorandom and g.pseudorandom.seed or nil
end

function QM.on_joker_bought(is_legendary)
  if QM.run and QM.run.id == run_id() then QM.run.bought = true end
  emit("joker_bought", {legendary = is_legendary and true or false})
end

function QM.on_joker_count_changed(count)
  emit("jokers_owned", {count = tonumber(count) or 0})
end

function QM.on_card_sold() emit("card_sold", {}) end
function QM.on_shop_reroll() emit("shop_reroll", {}) end
function QM.on_blind_skipped() emit("blind_skipped", {}) end

function QM.on_run_won(stake, deck_key)
  local bought = not (QM.run and QM.run.id ~= nil and QM.run.id == run_id()) or QM.run.bought
  emit("run_won", {stake = tonumber(stake) or 1, deck = deck_key, no_jokers_bought = not bought})
end

function QM.on_run_lost()
  if ProgressEvents then ProgressEvents.emit("run_lost", {}) end
end

function QM.claim_quest(quest)
  if type(quest) == "table" and quest.id then return QM.claim(quest.id) end
  return false
end

function QM.get_time_until_daily_reset()
  local now = os.time()
  local secs = 86400 - (now % 86400)
  return string.format("%02dh %02dm", math.floor(secs / 3600), math.floor((secs % 3600) / 60))
end

function QM.get_time_until_weekly_reset()
  local now = os.time()
  local wd = tonumber(os.date("!%w", now))
  local days = (8 - wd) % 7
  if days == 0 then days = 7 end
  local secs = (days - 1) * 86400 + (86400 - now % 86400)
  local d = math.floor(secs / 86400)
  local h = math.floor((secs % 86400) / 3600)
  if d > 0 then return string.format("%dd %dh", d, h) end
  return string.format("%02dh %02dm", h, math.floor((secs % 3600) / 60))
end

if ProgressEvents and not QM.listening then
  QM.listening = true
  ProgressEvents.on("run_start", function() QM.run = {id = run_id(), bought = false} end)
  ProgressEvents.on("*", function(data, name) QM.handle(name, data) end)
end

_G.QuestManager = QM
_G.DAILY_QUEST_POOL = DAILY
_G.WEEKLY_QUEST_POOL = WEEKLY
_G.REPEATABLE_QUEST_POOL = LONG

ProgressEvents.register_loc{
  fr = {
    ["Buy an item with Balacoin in The Casino"] = "Achète un article en Balacoin au Casino",
    ["Make a card in The Forge"] = "Crée une carte à la Forge",
    ["Arcade Break"] = "Pause arcade",
    ["Arcade Legend"] = "Légende de l'arcade",
    ["Arcade Regular"] = "Habitué de l'arcade",
    ["Arcana"] = "Arcanes",
    ["Beat #1# Blinds"] = "Bats #1# Blinds",
    ["Big Earner"] = "Gros gains",
    ["Big Numbers"] = "Gros chiffres",
    ["Black Challenge"] = "Défi noir",
    ["Blind Breaker"] = "Briseur de Blinds",
    ["Blind Marathon"] = "Marathon de Blinds",
    ["Blind Runner"] = "Coureur de Blinds",
    ["Booster Binge"] = "Frénésie de boosters",
    ["Boss Breaker"] = "Briseur de boss",
    ["Boss Crusher"] = "Écraseur de boss",
    ["Boss Exterminator"] = "Exterminateur de boss",
    ["Boss Hunter"] = "Chasseur de boss",
    ["Boss Slayer"] = "Tueur de boss",
    ["Boss Slayer Pro"] = "Tueur de boss confirmé",
    ["Buy #1# items with Balacoin in The Casino"] = "Achète #1# articles en Balacoin au Casino",
    ["Buy #1# Jokers"] = "Achète #1# Jokers",
    ["Card Enhancer"] = "Améliorateur",
    ["Card Seller"] = "Vendeur de cartes",
    ["Card Sharp"] = "As des cartes",
    ["Card Thrower"] = "Lanceur de cartes",
    ["Card Trader"] = "Marchand de cartes",
    ["Champion's Road"] = "La route du champion",
    ["Change your look at the Tailor"] = "Changez de style chez le Tailleur",
    ["Claim #1# daily or weekly quests"] = "Récupère #1# quêtes du jour ou de la semaine",
    ["Claim #1# daily quests"] = "Récupère #1# quêtes du jour",
    ["Coupon Clipper"] = "Chasseur de bons",
    ["Daily Habit"] = "Bonne habitude",
    ["Daily Ritual"] = "Rituel du jour",
    ["Daily Warrior"] = "Guerrier du quotidien",
    ["Deck Builder"] = "Bâtisseur de jeu",
    ["Deck Explorer"] = "Explorateur de jeux",
    ["Deck Master"] = "Maître des jeux",
    ["Deep Endless"] = "Très loin dans l'infini",
    ["Defeat #1# Boss Blinds"] = "Bats #1# Blinds de boss",
    ["Discard #1# cards"] = "Défausse #1# cartes",
    ["Double Trouble"] = "Double peine",
    ["Double Victory"] = "Double victoire",
    ["Earn $#1# in runs"] = "Gagne #1# $ en partie",
    ["Edition Collector"] = "Collectionneur d'éditions",
    ["Endless Road"] = "Route sans fin",
    ["Enhance #1# playing cards"] = "Améliore #1# cartes à jouer",
    ["Enhancement Pro"] = "Pro de l'amélioration",
    ["Every Day"] = "Tous les jours",
    ["Fight #1# bosses in the Training Grounds"] = "Affronte #1# boss à l'Entraînement",
    ["Fight a boss in the Training Grounds"] = "Affronte un boss à l'Entraînement",
    ["Film Study"] = "Séance vidéo",
    ["Final Ante"] = "Dernière Ante",
    ["Flush Expert"] = "Expert des couleurs",
    ["Flush Finder"] = "Chercheur de couleurs",
    ["Fortune"] = "Fortune",
    ["Full Bench"] = "Banc complet",
    ["Full House Fanatic"] = "Fan de full",
    ["Full House Party"] = "La fête au full",
    ["Get #1# cards with an Edition"] = "Obtiens #1# cartes avec une édition",
    ["Get #1# Jokers"] = "Obtiens #1# Jokers",
    ["Get #1# Legendary Jokers"] = "Obtiens #1# Jokers légendaires",
    ["Get a card with an Edition"] = "Obtiens une carte avec une édition",
    ["Get a Legendary Joker"] = "Obtiens un Joker légendaire",
    ["Get a Rare or Legendary Joker"] = "Obtiens un Joker rare ou légendaire",
    ["Getting Started"] = "Premiers pas",
    ["Gold Champion"] = "Champion d'or",
    ["Growing Savings"] = "Économies en hausse",
    ["Hand Dealer"] = "Donneur de mains",
    ["Hand Veteran"] = "Vétéran des mains",
    ["Have #2# Jokers at once"] = "Aie #2# Jokers en même temps",
    ["Head to Head"] = "Face à face",
    ["High Roller"] = "Gros joueur",
    ["High Scorer"] = "Gros score",
    ["Hot Streak"] = "Série brûlante",
    ["Into the Deep"] = "Vers les profondeurs",
    ["Item Expert"] = "Expert des objets",
    ["Item Hoarder"] = "Accumulateur",
    ["Joker Collector"] = "Collectionneur de Jokers",
    ["Joker Expert"] = "Expert des Jokers",
    ["Joker Shopper"] = "Acheteur de Jokers",
    ["Legendary Find"] = "Trouvaille légendaire",
    ["Legendary Hunter"] = "Chasseur de légendes",
    ["Legend Seeker"] = "En quête de légendes",
    ["Lucky Reroller"] = "Relance chanceuse",
    ["Make #1# cards in The Forge"] = "Crée #1# cartes à la Forge",
    ["Make a new card in The Forge"] = "Crée une nouvelle carte à la Forge",
    ["Master Smith"] = "Maître forgeron",
    ["Matchmaker"] = "Habitué des tables",
    ["Mega Scorer"] = "Méga score",
    ["Millionaire Club"] = "Club des millionnaires",
    ["New Look"] = "Nouveau style",
    ["Open #1# Booster Packs"] = "Ouvre #1# paquets boosters",
    ["Pack Hunter"] = "Chasseur de paquets",
    ["Pack Opener"] = "Ouvreur de paquets",
    ["Pack Rat"] = "Collectionneur de paquets",
    ["Planet Master"] = "Maître des planètes",
    ["Play #1# Arcade games in The Casino"] = "Joue #1# parties d'arcade au Casino",
    ["Play #1# Daily Challenges"] = "Joue #1# défis du jour",
    ["Play #1# Flushes"] = "Joue #1# couleurs",
    ["Play Four of a Kind #1# times"] = "Joue un carré #1# fois",
    ["Play #1# Full Houses"] = "Joue #1# fulls",
    ["Play #1# hands"] = "Joue #1# mains",
    ["Play #1# Multiplayer matches"] = "Joue #1# matchs multijoueur",
    ["Play #1# Straights"] = "Joue #1# quintes",
    ["Play Three of a Kind #1# times"] = "Joue un brelan #1# fois",
    ["Play #1# Two Pairs"] = "Joue #1# doubles paires",
    ["Play a Multiplayer match"] = "Joue un match multijoueur",
    ["Play a Straight Flush"] = "Joue une quinte flush",
    ["Play the Daily Challenge"] = "Joue le défi du jour",
    ["Pocket Change"] = "Petite monnaie",
    ["Pure Skill"] = "Pur talent",
    ["Quad Squad"] = "Le gang des carrés",
    ["Questmaster"] = "Maître des quêtes",
    ["Rare Taste"] = "Goût du rare",
    ["Reach Ante #1#"] = "Atteins l'Ante #1#",
    ["Reach Ante #2#"] = "Atteins l'Ante #2#",
    ["Red Challenge"] = "Défi rouge",
    ["Redeem #1# Vouchers"] = "Utilise #1# bons",
    ["Redeem a Voucher"] = "Utilise un bon",
    ["Reroll the shop #1# times"] = "Relance la boutique #1# fois",
    ["Rival Breaker"] = "Briseur de rivaux",
    ["Rival of the Table"] = "Rival de la table",
    ["Save a deck in the Deck Creator"] = "Enregistre un jeu dans le Créateur de Deck",
    ["Score #1# in one hand"] = "Marque #1# en une main",
    ["Score #2# or more in one hand"] = "Marque #2# ou plus en une main",
    ["Score #2# or more in one hand, #1# times"] = "Marque #2# ou plus en une main, #1# fois",
    ["Sell #1# cards"] = "Vends #1# cartes",
    ["Shiny Find"] = "Trouvaille brillante",
    ["Shiny Things"] = "Ça brille",
    ["Shop Explorer"] = "Explorateur de boutique",
    ["Shuffle Up"] = "On mélange",
    ["Skip #1# Blinds"] = "Passe #1# Blinds",
    ["Skip Strategist"] = "Stratège du saut",
    ["Smith"] = "Forgeron",
    ["Sparring Partner"] = "Partenaire d'entraînement",
    ["Spectral Touch"] = "Toucher spectral",
    ["Stake Climber"] = "Grimpeur de mises",
    ["Stake Ladder"] = "L'échelle des mises",
    ["Stargazer"] = "Astronome",
    ["Start #1# runs"] = "Lance #1# parties",
    ["Straight Expert"] = "Expert des quintes",
    ["Straight Flush!"] = "Quinte flush !",
    ["Straight Shooter"] = "Tireur d'élite",
    ["Table Regular"] = "Habitué de la table",
    ["Table Talk"] = "On cause à table",
    ["Tag Collector"] = "Collectionneur d'étiquettes",
    ["Tarot Master"] = "Maître du tarot",
    ["Tarot Reader"] = "Tireur de tarot",
    ["Training Day"] = "Jour d'entraînement",
    ["Triple Threat"] = "Triple menace",
    ["Trophy Hunter"] = "Chasseur de trophées",
    ["Trophy Room"] = "Salle des trophées",
    ["Trophy Shelf"] = "Étagère à trophées",
    ["Unlock #1# achievements"] = "Débloque #1# succès",
    ["Unlock an achievement"] = "Débloque un succès",
    ["Use #1# consumables"] = "Utilise #1# consommables",
    ["Use #1# Planet cards"] = "Utilise #1# cartes Planète",
    ["Use #1# Spectral cards"] = "Utilise #1# cartes Spectrales",
    ["Use #1# Tarot cards"] = "Utilise #1# cartes Tarot",
    ["Victory"] = "Victoire",
    ["Voucher Fan"] = "Fan de bons",
    ["Voucher Finder"] = "Chercheur de bons",
    ["Voucher Hunter"] = "Chasseur de bons",
    ["Watch a replay of a past run"] = "Regarde le replay d'une ancienne partie",
    ["Wealthy Player"] = "Joueur fortuné",
    ["Weekly Winner"] = "Gagnant de la semaine",
    ["Win #1# Multiplayer matches"] = "Gagne #1# matchs multijoueur",
    ["Win #1# runs"] = "Gagne #1# parties",
    ["Win #1# runs in a row"] = "Gagne #1# parties d'affilée",
    ["Win a Multiplayer match"] = "Gagne un match multijoueur",
    ["Win a run"] = "Gagne une partie",
    ["Win a run without buying a Joker"] = "Gagne une partie sans acheter de Joker",
    ["Winning Week"] = "Semaine gagnante",
    ["Win on #1# different stakes"] = "Gagne sur #1# mises différentes",
    ["Win on #1# Stake or higher"] = "Gagne en mise #1# ou plus",
    ["Win on Black Stake or higher"] = "Gagne en mise noire ou plus",
    ["Win on Gold Stake or higher"] = "Gagne en mise dorée ou plus",
    ["Win on Red Stake or higher"] = "Gagne en mise rouge ou plus",
    ["Win with #1# different decks"] = "Gagne avec #1# jeux différents",
    ["Workshop"] = "Atelier",
  },
  es = {
    ["Buy an item with Balacoin in The Casino"] = "Compra un artículo con Balacoin en El Casino",
    ["Make a card in The Forge"] = "Crea una carta en La Forja",
    ["Arcade Break"] = "Pausa recreativa",
    ["Arcade Legend"] = "Leyenda recreativa",
    ["Arcade Regular"] = "Habitual del salón",
    ["Arcana"] = "Arcanos",
    ["Beat #1# Blinds"] = "Supera #1# ciegas",
    ["Big Earner"] = "Grandes ganancias",
    ["Big Numbers"] = "Números grandes",
    ["Black Challenge"] = "Desafío negro",
    ["Blind Breaker"] = "Rompeciegas",
    ["Blind Marathon"] = "Maratón de ciegas",
    ["Blind Runner"] = "Corredor de ciegas",
    ["Booster Binge"] = "Atracón de sobres",
    ["Boss Breaker"] = "Rompejefes",
    ["Boss Crusher"] = "Aplastajefes",
    ["Boss Exterminator"] = "Exterminador de jefes",
    ["Boss Hunter"] = "Cazador de jefes",
    ["Boss Slayer"] = "Matajefes",
    ["Boss Slayer Pro"] = "Matajefes experto",
    ["Buy #1# items with Balacoin in The Casino"] = "Compra #1# artículos con Balacoin en El Casino",
    ["Buy #1# Jokers"] = "Compra #1# comodines",
    ["Card Enhancer"] = "Mejorador de cartas",
    ["Card Seller"] = "Vendedor de cartas",
    ["Card Sharp"] = "Tahúr",
    ["Card Thrower"] = "Lanzacartas",
    ["Card Trader"] = "Comerciante de cartas",
    ["Champion's Road"] = "El camino del campeón",
    ["Change your look at the Tailor"] = "Cambia tu estilo en el Sastre",
    ["Claim #1# daily or weekly quests"] = "Reclama #1# misiones diarias o semanales",
    ["Claim #1# daily quests"] = "Reclama #1# misiones diarias",
    ["Coupon Clipper"] = "Cazador de vales",
    ["Daily Habit"] = "Buen hábito",
    ["Daily Ritual"] = "Ritual diario",
    ["Daily Warrior"] = "Guerrero diario",
    ["Deck Builder"] = "Constructor de barajas",
    ["Deck Explorer"] = "Explorador de barajas",
    ["Deck Master"] = "Maestro de barajas",
    ["Deep Endless"] = "Muy lejos en el modo infinito",
    ["Defeat #1# Boss Blinds"] = "Derrota #1# ciegas jefe",
    ["Discard #1# cards"] = "Descarta #1# cartas",
    ["Double Trouble"] = "Doble problema",
    ["Double Victory"] = "Doble victoria",
    ["Earn $#1# in runs"] = "Gana #1# $ en partidas",
    ["Edition Collector"] = "Coleccionista de ediciones",
    ["Endless Road"] = "Camino sin fin",
    ["Enhance #1# playing cards"] = "Mejora #1# cartas de juego",
    ["Enhancement Pro"] = "Experto en mejoras",
    ["Every Day"] = "Todos los días",
    ["Fight #1# bosses in the Training Grounds"] = "Enfréntate a #1# jefes en el Entrenamiento",
    ["Fight a boss in the Training Grounds"] = "Enfréntate a un jefe en el Entrenamiento",
    ["Film Study"] = "Análisis de vídeo",
    ["Final Ante"] = "Última apuesta inicial",
    ["Flush Expert"] = "Experto en colores",
    ["Flush Finder"] = "Buscador de colores",
    ["Fortune"] = "Fortuna",
    ["Full Bench"] = "Banquillo lleno",
    ["Full House Fanatic"] = "Fanático del full",
    ["Full House Party"] = "Fiesta de full",
    ["Get #1# cards with an Edition"] = "Consigue #1# cartas con edición",
    ["Get #1# Jokers"] = "Consigue #1# comodines",
    ["Get #1# Legendary Jokers"] = "Consigue #1# comodines legendarios",
    ["Get a card with an Edition"] = "Consigue una carta con edición",
    ["Get a Legendary Joker"] = "Consigue un comodín legendario",
    ["Get a Rare or Legendary Joker"] = "Consigue un comodín raro o legendario",
    ["Getting Started"] = "Primeros pasos",
    ["Gold Champion"] = "Campeón de oro",
    ["Growing Savings"] = "Ahorros en aumento",
    ["Hand Dealer"] = "Repartidor de manos",
    ["Hand Veteran"] = "Veterano de manos",
    ["Have #2# Jokers at once"] = "Ten #2# comodines a la vez",
    ["Head to Head"] = "Cara a cara",
    ["High Roller"] = "Gran apostador",
    ["High Scorer"] = "Gran puntuación",
    ["Hot Streak"] = "Racha caliente",
    ["Into the Deep"] = "Hacia lo profundo",
    ["Item Expert"] = "Experto en objetos",
    ["Item Hoarder"] = "Acumulador",
    ["Joker Collector"] = "Coleccionista de comodines",
    ["Joker Expert"] = "Experto en comodines",
    ["Joker Shopper"] = "Comprador de comodines",
    ["Legendary Find"] = "Hallazgo legendario",
    ["Legendary Hunter"] = "Cazador de leyendas",
    ["Legend Seeker"] = "Buscador de leyendas",
    ["Lucky Reroller"] = "Tirada con suerte",
    ["Make #1# cards in The Forge"] = "Crea #1# cartas en La Forja",
    ["Make a new card in The Forge"] = "Crea una carta nueva en La Forja",
    ["Master Smith"] = "Maestro herrero",
    ["Matchmaker"] = "Habitual de las mesas",
    ["Mega Scorer"] = "Megapuntuación",
    ["Millionaire Club"] = "Club de millonarios",
    ["New Look"] = "Nuevo estilo",
    ["Open #1# Booster Packs"] = "Abre #1# sobres",
    ["Pack Hunter"] = "Cazador de sobres",
    ["Pack Opener"] = "Abresobres",
    ["Pack Rat"] = "Acaparador de sobres",
    ["Planet Master"] = "Maestro planetario",
    ["Play #1# Arcade games in The Casino"] = "Juega #1# partidas recreativas en El Casino",
    ["Play #1# Daily Challenges"] = "Juega #1# desafíos diarios",
    ["Play #1# Flushes"] = "Juega #1# colores",
    ["Play Four of a Kind #1# times"] = "Juega póker #1# veces",
    ["Play #1# Full Houses"] = "Juega #1# fulls",
    ["Play #1# hands"] = "Juega #1# manos",
    ["Play #1# Multiplayer matches"] = "Juega #1# partidas multijugador",
    ["Play #1# Straights"] = "Juega #1# escaleras",
    ["Play Three of a Kind #1# times"] = "Juega trío #1# veces",
    ["Play #1# Two Pairs"] = "Juega #1# dobles parejas",
    ["Play a Multiplayer match"] = "Juega una partida multijugador",
    ["Play a Straight Flush"] = "Juega una escalera de color",
    ["Play the Daily Challenge"] = "Juega el desafío diario",
    ["Pocket Change"] = "Calderilla",
    ["Pure Skill"] = "Puro talento",
    ["Quad Squad"] = "La banda del póker",
    ["Questmaster"] = "Maestro de misiones",
    ["Rare Taste"] = "Gusto por lo raro",
    ["Reach Ante #1#"] = "Alcanza la apuesta inicial #1#",
    ["Reach Ante #2#"] = "Alcanza la apuesta inicial #2#",
    ["Red Challenge"] = "Desafío rojo",
    ["Redeem #1# Vouchers"] = "Canjea #1# vales",
    ["Redeem a Voucher"] = "Canjea un vale",
    ["Reroll the shop #1# times"] = "Renueva la tienda #1# veces",
    ["Rival Breaker"] = "Rompe-rivales",
    ["Rival of the Table"] = "Rival de la mesa",
    ["Save a deck in the Deck Creator"] = "Guarda una baraja en el Creador de Mazos",
    ["Score #1# in one hand"] = "Consigue #1# en una mano",
    ["Score #2# or more in one hand"] = "Consigue #2# o más en una mano",
    ["Score #2# or more in one hand, #1# times"] = "Consigue #2# o más en una mano, #1# veces",
    ["Sell #1# cards"] = "Vende #1# cartas",
    ["Shiny Find"] = "Hallazgo brillante",
    ["Shiny Things"] = "Cosas brillantes",
    ["Shop Explorer"] = "Explorador de la tienda",
    ["Shuffle Up"] = "A barajar",
    ["Skip #1# Blinds"] = "Sáltate #1# ciegas",
    ["Skip Strategist"] = "Estratega del salto",
    ["Smith"] = "Herrero",
    ["Sparring Partner"] = "Compañero de entrenamiento",
    ["Spectral Touch"] = "Toque espectral",
    ["Stake Climber"] = "Escalador de apuestas",
    ["Stake Ladder"] = "La escalera de apuestas",
    ["Stargazer"] = "Astrónomo",
    ["Start #1# runs"] = "Empieza #1# partidas",
    ["Straight Expert"] = "Experto en escaleras",
    ["Straight Flush!"] = "¡Escalera de color!",
    ["Straight Shooter"] = "Tirador recto",
    ["Table Regular"] = "Habitual de la mesa",
    ["Table Talk"] = "Charla de mesa",
    ["Tag Collector"] = "Coleccionista de etiquetas",
    ["Tarot Master"] = "Maestro del tarot",
    ["Tarot Reader"] = "Lector de tarot",
    ["Training Day"] = "Día de entrenamiento",
    ["Triple Threat"] = "Triple amenaza",
    ["Trophy Hunter"] = "Cazador de trofeos",
    ["Trophy Room"] = "Sala de trofeos",
    ["Trophy Shelf"] = "Estante de trofeos",
    ["Unlock #1# achievements"] = "Desbloquea #1# logros",
    ["Unlock an achievement"] = "Desbloquea un logro",
    ["Use #1# consumables"] = "Usa #1# consumibles",
    ["Use #1# Planet cards"] = "Usa #1# cartas de planeta",
    ["Use #1# Spectral cards"] = "Usa #1# cartas espectrales",
    ["Use #1# Tarot cards"] = "Usa #1# cartas de tarot",
    ["Victory"] = "Victoria",
    ["Voucher Fan"] = "Fan de los vales",
    ["Voucher Finder"] = "Buscador de vales",
    ["Voucher Hunter"] = "Cazador de vales",
    ["Watch a replay of a past run"] = "Mira la repetición de una partida pasada",
    ["Wealthy Player"] = "Jugador adinerado",
    ["Weekly Winner"] = "Ganador de la semana",
    ["Win #1# Multiplayer matches"] = "Gana #1# partidas multijugador",
    ["Win #1# runs"] = "Gana #1# partidas",
    ["Win #1# runs in a row"] = "Gana #1# partidas seguidas",
    ["Win a Multiplayer match"] = "Gana una partida multijugador",
    ["Win a run"] = "Gana una partida",
    ["Win a run without buying a Joker"] = "Gana una partida sin comprar comodines",
    ["Winning Week"] = "Semana ganadora",
    ["Win on #1# different stakes"] = "Gana en #1# apuestas distintas",
    ["Win on #1# Stake or higher"] = "Gana en apuesta #1# o superior",
    ["Win on Black Stake or higher"] = "Gana en apuesta negra o superior",
    ["Win on Gold Stake or higher"] = "Gana en apuesta dorada o superior",
    ["Win on Red Stake or higher"] = "Gana en apuesta roja o superior",
    ["Win with #1# different decks"] = "Gana con #1# barajas distintas",
    ["Workshop"] = "Taller",
  },
}
