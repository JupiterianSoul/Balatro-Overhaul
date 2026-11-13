package.path = "assets/?.lua;" .. package.path
local fails, passes = 0, 0
local function ok(cond, msg)
  if cond then passes = passes + 1 else fails = fails + 1; print("FAIL " .. msg) end
end

local now = 2000000
os.time = function() return now end
love = {filesystem = {getInfo = function() return nil end, read = function() return nil end, write = function() return true end, remove = function() end}}
package.preload["functions/fast_fs"] = function() return {write = function() return true end, read = function() return nil end} end
function mod_loc(s) return s end
local function card(o) return o end
G = {
  SETTINGS = {profile = 1, paused = false, language = "en-us"},
  PROFILES = {[1] = {high_scores = {current_streak = {amt = 0}}, career_stats = {}, deck_usage = {}, progression = {unlocked_icons = {}, unlocked_boss_badges = {}}}},
  GAME = {stake = 1, round_resets = {ante = 1}, round_scores = {hand = {amt = 0}}, current_round = {hands_played = 1}, dollars = 0},
  STAGES = {RUN = 1, MAIN_MENU = 2}, STAGE = 1, STATES = {}, ACHIEVEMENTS = {},
  play = {cards = {}}, hand = {cards = {}, config = {card_limit = 8}}, deck = {cards = {}}, discard = {cards = {}},
  jokers = {cards = {}}, consumeables = {cards = {}, config = {card_limit = 2}}, playing_cards = {},
  FUNCS = {},
}
function win_game() end
Game = {update_game_over = function() end}

local calls = {}
local function stub(name) G.FUNCS[name] = function() calls[name] = (calls[name] or 0) + 1 end end
for _, n in ipairs({"open_mod_menu_fullscreen", "open_mod_menu_inrun", "open_guide_overview", "open_guide_tavern", "open_jukebox", "cash_out",
  "bo_bp_play", "mg_play", "seed_lib_save_current", "open_run_history"}) do stub(n) end
Town = {open = function() end, go = function() end}
BO_SPREPLAY = {watch = function() end}
bom_replay = {watch = function() end}
local equipped = {}
CosmeticsManager = {equip = function(kind, id) equipped[kind] = id end, get_equipped = function(kind) return equipped[kind] end}
local forge = {}
package.preload["functions/forge/forge_store"] = function()
  return {put = function(c) forge[c.id] = c end, get = function(id) return forge[id] end,
    put_item = function(c) forge["i" .. c.id] = c end, get_item = function(id) return forge["i" .. id] end}
end
QuestManager = {process_event = function(ev) calls["q_" .. ev] = (calls["q_" .. ev] or 0) + 1 end}

dofile("assets/functions/progress_gate.lua")
dofile("assets/functions/achievements_data.lua")
dofile("assets/functions/achievements.lua")
dofile("assets/functions/overhaul_stats.lua")
dofile("assets/functions/achievements_hooks.lua")
local AM, S, OA = AchievementManager, Overhaul.stats, Overhaul.achievements
ok(AM.init(), "achievements init")
AM.bridge()
AchievementHooks.install_late()
AchievementHooks.install_late()

local cats = {}
for _, c in ipairs(ACHIEVEMENT_CATEGORY_LIST) do cats[c] = true end
for _, a in ipairs(ACHIEVEMENT_DEFINITIONS) do
  ok(cats[a.category], "category in the list: " .. a.id .. " " .. tostring(a.category))
  ok(type(a.name) == "string" and type(a.description) == "string", "name and description: " .. a.id)
  ok(not (a.name .. a.description .. (a.secret_hint or "")):find("\226\128\148"), "no em dash: " .. a.id)
  ok(not a.description:lower():find("mod menu") and not a.description:lower():find("mod guide"), "no out of date menu names: " .. a.id)
end

local function pc(id, suit) return {base = {id = id, suit = suit or "Spades"}} end
local function hand(name, cards)
  G.play.cards = cards or {pc(2), pc(3), pc(5), pc(7), pc(9)}
  AM.on_hand_played({hand_name = name, chips = 10})
end

for _, h in ipairs({"Flush Five", "Flush House", "Five of a Kind", "Straight Flush", "Royal Flush", "Full House"}) do hand(h) end
for i = 1, 100 do hand("Pair") end
for i = 1, 50 do hand("Two Pair"); hand("Three of a Kind") end
for i = 1, 25 do hand("Four of a Kind"); hand("Straight"); hand("Flush"); hand("Full House") end
for i = 1, 10000 do AM.on_hand_played({hand_name = "", chips = 1}) end
hand("Flush Five", {pc(13), pc(13), pc(13), pc(13), pc(13)})
hand("Four of a Kind", {pc(14, "Spades"), pc(14, "Hearts"), pc(14, "Clubs"), pc(14, "Diamonds"), pc(2)})
G.hand.cards = {} for i = 1, 13 do G.hand.cards[i] = pc(2) end
hand("High Card")
G.hand.cards = {}
S.on("hand_scored", {hand = "Pair", score = 2e9})

G.GAME.blind = {chips = 100, config = {blind = {boss = true}}}
G.GAME.chips = 1000
hand("Pair")
G.GAME.chips = 102
AM.on_hand_played({hand_name = "Pair", chips = 102})
G.GAME.chips = 0

AM._blind_hand_types = {"High Card"}
G.GAME.round_resets.ante = 3
G.GAME.current_round.hands_played = 1
for i = 1, 1000 do AM.on_blind_complete() end
G.playing_cards = {pc(2)}
AM.on_blind_complete()
G.playing_cards = {}
G.GAME.round_resets.ante = 7
G.GAME.dollars = 77
AM.on_blind_complete()
G.GAME.dollars = 0
AM.on_blind_complete()
G.GAME.blind = nil

G.GAME.round_resets.ante = 51
AM.on_ante_complete(51)

for i = 1, 500 do AM.on_run_start() end
for i = 1, 50 do AM.on_blind_skipped(); AM.on_shop_reroll(); AM.on_joker_sold() end
for i = 1, 200 do AM.on_shop_reroll(); AM.on_joker_sold(); AM.on_card_enhanced() end
for i = 1, 500 do AM.on_card_sold(); AM.on_discard() end
G.STATES = {ROUND_EVAL = 7, SHOP = 5, TAROT_PACK = 9, SELECTING_HAND = 1}
for i = 1, 99 do
  for _, st in ipairs({"SELECTING_HAND", "ROUND_EVAL", "SHOP", "SHOP", "TAROT_PACK", "SHOP"}) do G.STATE = G.STATES[st]; AchievementHooks.watch_state() end
end
ok(calls.q_shop_visited == 99 and not OA.unlocked("shops_visited"), "one shop visit per round, opening a pack in the shop does not count")
G.STATE = G.STATES.ROUND_EVAL; AchievementHooks.watch_state(); G.STATE = G.STATES.SHOP; AchievementHooks.watch_state()
G.FUNCS.cash_out()
ok(calls.cash_out == 1, "cash out is not wrapped")
local saved_am = AchievementManager
AchievementManager = nil
S.on("hand_scored", {score = 1})
AchievementManager = saved_am
for i = 1, 50 do AM.on_voucher_used("v_x") end
G.GAME.used_vouchers = {} for i = 1, 10 do G.GAME.used_vouchers["v" .. i] = true end
AM.on_voucher_used("v_y")
for i = 1, 50 do AM.on_edition_obtained() end
for i = 1, 1000 do AM.on_consumable_used("Other") end
for i = 1, 200 do AM.on_consumable_used("Tarot", "c_t" .. (i % 22)); AM.on_consumable_used("Planet", "c_p" .. (i % 12)) end
for i = 1, 100 do AM.on_consumable_used("Spectral") end
for i = 1, 250 do AM.on_quest_claimed() end

G.GAME.dollars = 150
AM._ante_start_dollars = 150
AM.on_money_change(-600)
G.GAME.dollars = 5000
AM.on_money_change(10)
G.GAME.dollars = 0
AM.on_money_change(-5000)
G.GAME.dollars = -5
AM.on_money_change(-5)

local function joker(rarity, edition) return {config = {center = {rarity = rarity}}, edition = edition} end
G.jokers.cards = {}
for i = 1, 20 do G.jokers.cards[i] = joker(1) end
G.jokers.cards[1] = joker(4, {negative = true}); G.jokers.cards[2] = joker(4, {polychrome = true}); G.jokers.cards[3] = joker(4, {holo = true})
G.jokers.cards[4] = joker(4, {foil = true}); G.jokers.cards[5] = joker(4); G.jokers.cards[6] = joker(2); G.jokers.cards[7] = joker(3)
for i = 1, 500 do AM.on_joker_added(G.jokers.cards[1]) end

G.consumeables.cards = {{}, {}}
G.hand.config.card_limit = 12
G.playing_cards = {}
for _, n in ipairs({"Bonus Card", "Mult Card", "Wild Card", "Stone Card", "Lucky Card"}) do G.playing_cards[#G.playing_cards + 1] = {ability = {name = n}} end
for i = 1, 5 do for _, n in ipairs({"Gold Card", "Steel Card", "Glass Card"}) do G.playing_cards[#G.playing_cards + 1] = {ability = {name = n}} end end
G.PROFILES[1].progression.unlocked_icons = {} for i = 1, 150 do G.PROFILES[1].progression.unlocked_icons[i] = "j" .. i end
G.PROFILES[1].progression.unlocked_boss_badges = {} for i = 1, 28 do G.PROFILES[1].progression.unlocked_boss_badges[i] = "bl" .. i end
G.PROFILES[1].progression.bom_daily_streak = 7
QuestManager.quest_data = {daily = {{status = "claimed"}}, daily_streak = 14}
AM.check_periodic()
G.consumeables.cards = {}
G.hand.config.card_limit = 8
G.playing_cards = {}

AM.player_data.stats.total_play_time = 360000
Overhaul.stats.data().time = 360000
AM.check_periodic()

local function win(o)
  o = o or {}
  G.GAME = {stake = o.stake or 1, round_resets = {ante = o.ante or 9}, round_scores = {hand = {amt = 0}}, current_round = {hands_played = 1},
    dollars = o.dollars or 10, skips = o.skips or 1, challenge = o.challenge, seeded = o.seeded, win_ante = 8,
    ostats_t = o.t or 3000, selected_back = {effect = {center = {key = o.deck or "b_red"}}}, custom_run = o.custom, daily = o.daily}
  G.jokers.cards = o.jokers or {joker(1), joker(1)}
  G.play.cards, G.hand.cards, G.discard.cards = {}, {}, {}
  G.playing_cards = {} for i = 1, o.cards or 40 do G.playing_cards[i] = pc(2) end
  AM.on_run_start()
  for i = 1, (o.discards or 1) do AM.on_discard() end
  if o.tarots then for i = 1, 22 do AM.on_consumable_used("Tarot", "c_t" .. i) end end
  if o.planets then for i = 1, 12 do AM.on_consumable_used("Planet", "c_p" .. i) end end
  AM.on_run_end(true, 0, o.t or 3000, o.deck or "b_red")
  S.on("run_end", {won = true})
end

for _, k in ipairs({"b_red", "b_blue", "b_yellow", "b_green", "b_black", "b_magic", "b_nebula", "b_ghost", "b_abandoned", "b_checkered", "b_zodiac", "b_painted", "b_anaglyph", "b_plasma", "b_erratic"}) do win({deck = k}) end
for st = 1, 12 do win({stake = st}) end
for i = 1, 30 do win({challenge = "c_x_" .. i}) end
for _, c in ipairs({"c_bankruptcy_1", "c_gauntlet_1", "c_glass_cannon_1", "c_duality_1", "c_alchemist_1"}) do win({challenge = c}) end
for i = 1, 60 do win() end
G.PROFILES[1].high_scores.current_streak.amt = 5
win({t = 500, skips = 0, discards = 0, jokers = {}, cards = 52, tarots = true, planets = true})
win({jokers = {joker(1)}})
win({jokers = {joker(1), joker(1), joker(1), joker(1), joker(1)}})
win({dollars = -3})
win({seeded = true})
G.GAME.daily = true
for d = 1, 30 do now = now + 86400; win({daily = true}) end

trigger_custom_run_achievement()

G.FUNCS.open_mod_menu_fullscreen()
G.FUNCS.open_guide_overview()
G.FUNCS.open_jukebox()
ok(calls.open_jukebox == 1 and calls.open_guide_overview == 1, "wrapped screens still open")
for i = 1, 50 do Town.open() end
for _, k in ipairs({"tavern", "market", "tailor", "forge", "library", "training", "arcade", "racetrack"}) do Town.go(k) end
local store = require("functions/forge/forge_store")
for i = 1, 10 do store.put({id = "f" .. i}) end
store.put({id = "f1"})
ok(S.get("forge_created") == 10, "editing a forge card is not a new creation")
G.OVERLAY_MENU = {}
for i = 1, 10 do CosmeticsManager.equip("card_back", "b" .. i) end
CosmeticsManager.equip("card_back", "b10")
ok(S.get("tailor_change") == 10, "equipping the same look again does not count")
G.OVERLAY_MENU = nil
for i = 1, 5 do BO_SPREPLAY.watch(i); bom_replay.watch(i) end
G.FUNCS.bo_bp_play(); G.FUNCS.mg_play(); G.FUNCS.seed_lib_save_current(); G.FUNCS.open_run_history()

G.GAME = {stake = 1, round_resets = {ante = 4}, round_scores = {hand = {amt = 0}}, multiplayer = true, ach_traps_sent = 0,
  selected_back = {effect = {center = {key = "b_mp_random"}}}}
G.jokers.cards = {}
local modes = {"nemesis", "faceoff", "ranked", "ascension", "race", "br", "teams", "raid", "swap"}
bom_match = {get_state = function() return {settings = {starting_lives = 4}} end}
for i = 1, 200 do
  now = now + 60
  S.on("mp_match_end", {result = "win", mode = modes[(i - 1) % #modes + 1], pvp_wins = 1, lives = (i == 1) and 1 or 4})
end
for i = 1, 10 do now = now + 60; S.on("mp_match_end", {result = "win", mode = "ranked"}) end
for i = 1, 5 do AM.update_progress("mp_saboteur", i) end

local missing = {}
for _, a in ipairs(ACHIEVEMENT_DEFINITIONS) do
  if not OA.unlocked(a.id) then missing[#missing + 1] = a.id end
end
ok(#missing == 0, "every achievement unlocks from its trigger, missing: " .. table.concat(missing, ", "))

local u, n = OA.count()
ok(u == n and n == #ACHIEVEMENT_DEFINITIONS, "count matches the list")

print(string.format("achievement tests: %d passed, %d failed", passes, fails))
os.exit(fails == 0 and 0 or 1)
