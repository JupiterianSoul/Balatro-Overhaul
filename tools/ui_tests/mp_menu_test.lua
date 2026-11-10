local root = (arg and arg[0] and arg[0]:match("^(.*)/tools/ui_tests/") or ".") .. "/assets/"
local fails = 0
local function check(name, cond, detail)
    if not cond then fails = fails + 1 print("FAIL " .. name .. " " .. tostring(detail)) else print("ok   " .. name) end
end

local function colour(r, g, b) return {r, g, b, 1} end
G = {UIT = {T = 1, B = 2, C = 3, R = 4, O = 5, ROOT = 7},
    C = {RED = colour(1, 0, 0), BLUE = colour(0, 0, 1), GREEN = colour(0, 1, 0), GOLD = colour(1, 1, 0), PURPLE = colour(1, 0, 1), BLACK = colour(0, 0, 0),
        WHITE = colour(1, 1, 1), CLEAR = {0, 0, 0, 0}, ORANGE = colour(1, 0.5, 0), PALE_GREEN = colour(0.5, 1, 0.5), L_BLACK = colour(0.2, 0.2, 0.2), MONEY = colour(1, 1, 0),
        JOKER_GREY = colour(0.5, 0.5, 0.5),
        UI = {TEXT_LIGHT = colour(1, 1, 1), TEXT_DARK = colour(0, 0, 0), BACKGROUND_INACTIVE = colour(0.4, 0.4, 0.4), TEXT_INACTIVE = colour(0.5, 0.5, 0.5)}},
    FUNCS = {}, SETTINGS = {profile = 1, language = "en-us"}, PROFILES = {{name = "Tester"}}, STAGES = {MAIN_MENU = 1, RUN = 2}, STAGE = 1,
    P_CENTERS = {}, P_CENTER_POOLS = {Back = {}, Stake = {}}, P_BLINDS = {}, ROOM = {T = {x = 0, y = 0, w = 20, h = 11}}, CARD_W = 2.05, CARD_H = 2.75,
    ASSET_ATLAS = {}, GAME = {}, F_QUIT_BUTTON = true,
    E_MANAGER = {events = {}, add_event = function(self, e) self.events[#self.events + 1] = e end},
    CONTROLLER = {snap_to = function() end}, FILE_HANDLER = {}}
function G:save_settings() self.saved_settings = true end
function G:save_progress() self.saved_progress = true end
love = {timer = {getTime = function() return os.clock() end}}
Event = function(t) return t end
mod_loc = function(s) return s end
mod_loc_register = function() end
localize = function(a) if type(a) == "table" then return a.key or "ERROR" end return tostring(a) end
play_sound = function() end
number_format = function(n) return tostring(n) end
lighten = function(c) return c end
darken = function(c) return c end
adjust_alpha = function(c) return c end
local function node(n, cfg, nodes) return {n = n, config = cfg or {}, nodes = nodes or {}} end
UIBox_button = function(a)
    local rows = {}
    for _, l in ipairs(a.label or {"LABEL"}) do rows[#rows + 1] = node(G.UIT.R, {align = "cm", minw = a.minw}, {node(G.UIT.T, {text = l, scale = a.scale})}) end
    return node(a.col and G.UIT.C or G.UIT.R, {align = "cm"}, {node(G.UIT.C, {button = a.button ~= "nil" and a.button or nil, ref_table = a.ref_table, minw = a.minw or 2.7, minh = a.minh or 0.9, id = a.id, colour = a.colour}, rows)})
end
create_UIBox_generic_options = function(a) return node(G.UIT.ROOT, {back_func = a.back_func}, a.contents) end
create_text_input = function(a) return node(G.UIT.C, {id = "text_input", ref_table = a.ref_table, ref_value = a.ref_value}) end
create_option_cycle = function(a) return node(G.UIT.R, {cycle = true, options = a.options}) end
create_tabs = function(a) return node(G.UIT.R, {tabs = a.tabs}) end
UIBox = function(a) return {definition = a.definition, remove = function() end, recalculate = function() end, get_UIE_by_ID = function() return nil end} end
Sprite = function() return {states = {drag = {}, collide = {}}, ARGS = {}} end
CardArea = function(x, y, w, h, cfg) return {T = {x = x, y = y, w = w, h = h}, cards = {}, config = cfg, emplace = function(self, c) self.cards[#self.cards + 1] = c end} end
Card = function(x, y, w, h, base, center) return {center = center} end
Back = function(center) return {generate_UI = function() return node(G.UIT.ROOT, {}, {node(G.UIT.T, {text = center.name})}) end} end
get_stake_sprite = function() return Sprite() end

dofile(root .. "functions/ui_kit.lua")
local windows = {}
local real_window = UIK.window
UIK.window = function(a)
    windows[#windows + 1] = a
    return real_window(a)
end
G.FUNCS.overlay_menu = function(a) G.OVERLAY_MENU = {def = a.definition, get_UIE_by_ID = function() return {config = {}, UIBox = {recalculate = function() end}} end} end
G.FUNCS.exit_overlay_menu = function() G.OVERLAY_MENU = nil end

local sent = {}
local listeners = {}
bom_events = {register = function(t, fn) listeners[t] = listeners[t] or {}; table.insert(listeners[t], fn); return true end}
bom_core = {is_connected = function() return true end, send = function(m) sent[#sent + 1] = m; return true end, connect = function(fn) fn() end,
    player_key = function() return string.rep("a", 24) end, mods_field = function() return {} end, disconnect = function() sent[#sent + 1] = {type = "disconnect"} end}
bom_room = {my_profile_name = function() return G.PROFILES[1].name end, is_default_name = function(n) return n == "" or n:match("^P%d*$") ~= nil end,
    game_version = function() return "test" end, version_text = function(v) return tostring(v) end, held_for = function() return nil end}
bom_match = {get_phase = function() return 0 end, PHASE = {NONE = 0}}
bom_gamemodes = {get_display_list = function() return {} end}

bom_kit = dofile(root .. "multiplayer/bom_kit.lua")
bom_badges = dofile(root .. "multiplayer/bom_badges.lua")

local RANKS = {}
for i = 1, 10 do RANKS[i] = {flavour = "Flavour " .. i, colour = colour(1, 1, 1)} end
bom_ranked = {S = {restore = {code = ""}, seen = {}, games = {}, catalog = {}, unlocks = {}, equipped = {}}, RANKS = RANKS, RARITY_COLOUR = {}, SLOT_NAMES = {},
    rank_name = function(r) return "Rank" .. tostring(r) end, rank_colour = function() return colour(1, 1, 1) end, badge_rank_of = function(_, r) return r, false end,
    badge_node = function() return node(G.UIT.O, {object = {}}) end, item = function() return nil end, send = function(m) sent[#sent + 1] = m end,
    request_profile = function() end, fx = function() end}
bom_ranked.ui_refresh = function() bom_ranked.refreshed = (bom_ranked.refreshed or 0) + 1 end
local RU = dofile(root .. "multiplayer/bom_ranked_ui.lua")
bom_ranked_ui = RU
RU.register()
bom_ranked.ui_refresh = function() bom_ranked.refreshed = (bom_ranked.refreshed or 0) + 1 end

mpm_menu = dofile(root .. "multiplayer/mpm_menu.lua")
mpm_profile = dofile(root .. "multiplayer/mpm_profile.lua")
mpm_collection = dofile(root .. "multiplayer/mpm_collection.lua")
mpm_mods = dofile(root .. "multiplayer/mpm_mods.lua")
bom_browse = dofile(root .. "multiplayer/bom_browse.lua")
bom_ui = {overlay = function(a) G.FUNCS.overlay_menu(a) end}
G.FUNCS.mods_button = function() G.opened_mods = true end
G.FUNCS.mp_open_friends = function() G.opened_friends = true end
mpm_menu.init()
mpm_profile.init()
mpm_collection.init()
mpm_mods.init()

local function last_window() return windows[#windows] end
local function build_all(w, label)
    for _, t in ipairs(w.tabs) do
        local ok, res = pcall(t.build)
        check(label .. " tab " .. t.key .. " builds", ok and type(res) == "table" and res.n ~= nil, res)
    end
end

local function find(nd, pred, seen)
    if type(nd) ~= "table" then return nil end
    if pred(nd) then return nd end
    for _, c in pairs(nd.nodes or {}) do
        local hit = find(c, pred)
        if hit then return hit end
    end
    return nil
end

check("MP menu off by default", not mpm_menu.is_active())
G.FUNCS.mpm_enter()
check("enter turns MP mode on", mpm_menu.is_active())
local left, right, big = mpm_menu.left_specs(), mpm_menu.right_specs("quit"), mpm_menu.big_specs()
check("left column", #left == 3 and left[1].label == "PROFILE" and left[2].id == "collection_button" and left[3].button == "mpm_open_friends")
check("right column", #right == 3 and right[1].button == "mpm_exit" and right[2].button == "options" and right[3].button == "quit")
check("big buttons", big[1].id == "main_menu_play" and big[2].mods and big[3].button == "mp_open_ranked")
local mods_btn = mpm_menu.mods_button(4.14, 1.75, 1.0)
check("mods button has BETA sticker", find(mods_btn, function(n) return n.config and n.config.text == "BETA" end) ~= nil)
check("mods button opens MP mods", find(mods_btn, function(n) return n.config and n.config.button == "mpm_open_mods" end) ~= nil)
local bell = mpm_menu.bell_row(15)
check("bell row aligned right at panel width", bell.config.align == "cr" and bell.config.minw == 15)
mpm_menu.set_unread(12)
check("bell count capped", mpm_menu.bell.text == "9+" and mpm_menu.bell_colour[1] == 1)
mpm_menu.set_unread(0)
check("bell count zero", mpm_menu.bell.text == "0" and mpm_menu.bell_colour[4] == 0.3)

G.FUNCS.open_multiplayer_menu()
local w = last_window()
check("open_multiplayer_menu opens PLAY", w and w.id == "mpm_play")
build_all(w, "play")
local daily_req = 0
for _, m in ipairs(sent) do if m.type == "daily_get" then daily_req = daily_req + 1 end end
check("daily and weekly requested", daily_req == 2, daily_req)
local ends = (os.time() + 3 * 3600 + 120) * 1000
for _, fn in ipairs(listeners.daily_ruleset) do fn({type = "daily_ruleset", kind = "daily", key = "2026-11-02", ends_at = ends,
    ruleset = {id = "daily-1", name = "Blitz", desc = "Short timer", mode = "nemesis", settings = {starting_lives = 3, timer = true, timer_base_seconds = 60}, layers = {}, bans = {jokers = {"j_joker"}}}}) end
check("daily subtitle", mpm_menu.daily_sub("daily"):find("Blitz, 3h", 1, true) ~= nil, mpm_menu.daily_sub("daily"))
check("weekly still loading", mpm_menu.daily_sub("weekly") == "Loading...", mpm_menu.daily_sub("weekly"))
G.FUNCS.mpm_daily({config = {ref_table = {kind = "daily"}}})
w = last_window()
check("daily window", w.id == "mpm_daily" and w.footer == nil)
build_all(w, "daily")
bom_daily = {start = function(kind) G.daily_started = kind end}
G.FUNCS.mpm_daily({config = {ref_table = {kind = "daily"}}})
w = last_window()
check("daily play button with L9 start", w.footer and #w.footer == 1)
G.FUNCS.mpm_daily_start({config = {ref_table = {kind = "daily"}}})
check("daily start hook called", G.daily_started == "daily")
local pairs_list = mpm_menu.rule_pairs({mode = "nemesis", settings = {starting_lives = 4, pvp_start_round = 2, timer = true, timer_base_seconds = 150, the_order = true, hide_opp_score = true, allow_score_preview = false}, bans = {jokers = {"a", "b"}, tags = {"c"}}})
local byk = {}
for _, p in ipairs(pairs_list) do byk[p[1]] = p[2] end
check("rule pairs", byk["Lives"] == "4" and byk["PvP from ante"] == "2" and byk["Ready timer"] == "150 s" and byk["Score preview"] == "Off" and byk["Banned cards"] == "3")

G.FUNCS.mpm_open_friends()
check("friends falls back to old window", G.opened_friends == true)
G.FUNCS.mps_open_inbox = function() G.inbox = true end
G.FUNCS.mpm_open_inbox()
check("bell calls L6 inbox", G.inbox == true)

local S = bom_ranked.S
G.FUNCS.mp_open_ranked()
w = last_window()
check("ranked window tabs", w.id == "mp_ranked" and #w.tabs == 4 and w.tabs[1].key == "main" and w.tabs[4].key == "rules")
build_all(w, "ranked (no data)")
S.profile = {rank = 3, tier = 2, rp = 1040, xp = 120, xpNeed = 300, level = 4, packs = 2, matches = 12, wins = 7, streak = 2, peakRank = 4, peakRp = 1250}
S.season = {name = "Autumn 2026", secondsLeft = 86400 * 40}
S.history = {}
for i = 1, 12 do S.history[i] = {mode = i % 2 == 0 and "1v1" or "br", bots = i % 3 == 0, result = i % 2 == 0 and "win" or "lose", ante = i, delta = i % 2 == 0 and 25 or -15, placement = 1, players = 2} end
S.board = {top = {}, me = {pos = 3, rp = 1040}}
for i = 1, 20 do S.board.top[i] = {pos = i, name = "Player" .. i, rp = 3000 - i * 50, rank = 9 - math.floor(i / 3), tier = 1, me = i == 3} end
for _, fn in ipairs(listeners.menu_info) do fn({type = "menu_info", online = 41, ranked_queue = 3, queue = 1, matches = 5,
    ruleset = {id = "ranked", name = "Ranked", desc = "Fixed", mode = "nemesis", settings = {starting_lives = 4, ruleset_id = "ranked"}, bans = {}, layers = {}, locked = true}}) end
build_all(w, "ranked")
RU.update_view()
check("counts text", RU.Q.view.counts == "3 in the ranked queue, 41 online", RU.Q.view.counts)

local n0 = #sent
G.FUNCS.mp_ranked_queue()
local fm = sent[#sent]
check("play ranked sends ranked find_match", fm and fm.type == "find_match" and fm.ranked == true and fm.name == "Tester" and fm.pkey ~= nil and #sent == n0 + 1, fm and fm.type)
local consumed = listeners.searching[1]({type = "searching", ranked = true})
check("searching consumed and shown", consumed == true and RU.Q.status == "searching")
RU.update_view()
check("searching status text", RU.Q.view.status:find("Searching for an opponent", 1, true) == 1, RU.Q.view.status)
build_all(w, "ranked searching")
G.FUNCS.mp_ranked_queue_cancel()
check("cancel sends cancel_search", sent[#sent].type == "cancel_search" and RU.Q.status == nil)
G.FUNCS.mp_ranked_queue()
consumed = listeners.ranked_error[1]({type = "ranked_error", ["for"] = "find_match", code = "mods_not_allowed", mods = {"Cryptid"}})
RU.update_view()
check("mods refusal shown", consumed == true and RU.Q.status == "error" and RU.Q.view.status:find("Cryptid", 1, true) ~= nil, RU.Q.view.status)
check("non-queue ranked_error passes through", listeners.ranked_error[1]({type = "ranked_error", reason = "x"}) == nil)
G.PROFILES[1].name = "P1"
G.FUNCS.mp_ranked_queue()
check("default name blocked before queue", RU.Q.status == "error" and RU.Q.error == "name")
G.PROFILES[1].name = "Tester"
G.FUNCS.mp_ranked_queue()
listeners.room_ready[1]({type = "room_ready", ranked = true})
check("match found clears queue", RU.Q.status == nil)

G.FUNCS.mpm_open_profile()
w = last_window()
check("profile window tabs", w.id == "mpm_profile" and #w.tabs == 5 and w.tabs[1].key == "progression" and w.tabs[2].key == "showcase" and w.tabs[5].key == "history")
build_all(w, "profile (history loading)")
local asked = sent[#sent]
check("history requested", asked.type == "match_history" and asked.pkey ~= nil, asked.type)
for _, fn in ipairs(listeners.match_history) do fn({type = "match_history", items = {
    {id = "m1", at = 1793600000000, mode = "nemesis", ranked = true, players = {{name = "Tester"}, {name = "Bob", is_bot = true}}, result = "win", rp_delta = 24, has_replay = true, placement = 1, status = ""},
    {id = "m2", at = 1793500000000, mode = "party_br", ranked = false, players = {{name = "Tester"}, {name = "Ann"}, {name = "Lou"}}, result = "lose", rp_delta = nil, placement = 3, status = "held"},
}}) end
build_all(w, "profile")
bom_replay = {watch = function(id) G.watched = id end}
local okh, hist = pcall(w.tabs[5].build)
check("history with replay builds", okh and find(hist, function(n) return n.config and n.config.button == "mpm_watch_replay" end) ~= nil, hist)
G.FUNCS.mpm_watch_replay({config = {ref_table = {id = "m1"}}})
check("watch replay hook", G.watched == "m1")
mpm_profile.name.value = "  Zed  "
G.FUNCS.mpm_name_save()
check("name check sent", sent[#sent].type == "name_check" and sent[#sent].name == "Zed", sent[#sent].name)
for _, fn in ipairs(listeners.name_check) do fn({type = "name_check", ok = false, reason = "taken", name = "Zed"}) end
check("taken keeps old name", G.PROFILES[1].name == "Tester" and mpm_profile.name.status:find("already", 1, true) ~= nil)
mpm_profile.name.value = "Zed"
G.FUNCS.mpm_name_save()
for _, fn in ipairs(listeners.name_check) do fn({type = "name_check", ok = true, name = "Zed"}) end
check("ok saves the name", G.PROFILES[1].name == "Zed" and G.saved_settings and sent[#sent].type == "ranked_profile" and sent[#sent].name == "Zed")

G.P_CENTERS.j_mp_alpha = {key = "j_mp_alpha", set = "Joker", order = 2, name = "Alpha"}
G.P_CENTERS.j_mp_beta = {key = "j_mp_beta", set = "Joker", order = 1, name = "Beta"}
G.P_CENTERS.j_joker = {key = "j_joker", set = "Joker", order = 1, name = "Joker"}
G.P_CENTER_POOLS.Back = {{key = "b_red", name = "Red Deck", pos = {x = 0, y = 0}}, {key = "b_mp_violet", name = "Violet", pos = {x = 1, y = 0}}}
G.P_CENTER_POOLS.Stake = {{key = "stake_white"}, {key = "stake_mp_planet", name = "Planet"}}
G.P_BLINDS = {bl_mp_nemesis = {order = 1, name = "Nemesis"}, bl_small = {order = 0}}
local jk = mpm_collection.jokers()
check("MP jokers only, in order", #jk == 2 and jk[1].key == "j_mp_beta")
check("MP decks, stakes, blinds", #mpm_collection.decks() == 1 and #mpm_collection.stakes() == 1 and #mpm_collection.blinds() == 1)
G.FUNCS.mpm_open_collection()
w = last_window()
check("collection without reworks", w.id == "mpm_collection" and #w.tabs == 6)
build_all(w, "collection")
bom_reworks = {available = function() return {"j_joker", "j_missing"} end, mp_text = function() return {"+5 Mult", "MP text"} end}
G.FUNCS.mpm_open_collection()
w = last_window()
check("collection with reworks tab", #w.tabs == 7 and w.tabs[7].key == "reworks")
build_all(w, "collection reworks")
check("reworks keep real cards only", #mpm_collection.reworks() == 1)

ModWorkshop = {filtered = function() return {{key = "a"}, {key = "b"}, {key = "c"}} end, mp_ok = function(e) return e.key ~= "b" end}
mpm_mods.init()
G.FUNCS.mpm_open_mods()
check("MP mods opens the mods menu in MP mode", G.opened_mods and G.MODS_MENU.mp_only == true)
mpm_mods = mpm_mods
local okw = pcall(function() return mpm_mods end)
check("workshop filter keeps MP mods", #ModWorkshop.filtered() == 2 and okw)
local hdr = mpm_mods.header()
check("BETA note in header", find(hdr, function(n) return n.config and n.config.text == "Mods in multiplayer are in beta. They may cause issues." end) ~= nil)
G.FUNCS.mpm_mods_back()
check("back clears MP mode", G.MODS_MENU.mp_only == nil and #ModWorkshop.filtered() == 3)
G.FUNCS.mods_button()
check("normal mods button stays normal", G.MODS_MENU.mp_only == nil)

bom_browse.state.status = "ok"
bom_browse.state.rooms = {
    {id = "r1", name = "Bob", players = 1, maxPlayers = 2, joinable = true, sameVersion = true, mode = "nemesis", lives = 4, ping = 40, roster = {{pid = 0, name = "Bob", rank = {rank = 3, tier = 2, name = "Gold"}}}},
    {id = "r2", name = "Ann", players = 2, maxPlayers = 2, full = true, inMatch = true, ante = 3, sameVersion = true, mode = "party_br", party = true, ping = 400, roster = {{pid = 0, name = "Ann", is_bot = false}}},
}
local bdef = bom_browse.definition()
w = last_window()
check("browse is a UIK window", w.id == "mp_browse" and #w.tabs == 1 and w.footer ~= nil and bdef ~= nil)
build_all(w, "browse")
bom_spectate = {browse_tab = function() return node(G.UIT.R, {}, {}) end}
bom_browse.definition()
w = last_window()
check("watch live tab when L11 module exists", #w.tabs == 2 and w.tabs[2].key == "live")

G.FUNCS.mpm_exit()
check("singleplayer leaves MP mode", not mpm_menu.is_active())

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
