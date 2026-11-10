local root = arg[1] or "."
local fails = 0
local function check(name, ok)
    if not ok then
        fails = fails + 1
        print("FAIL " .. name)
    end
end

G = {
    STAGES = {RUN = 1, MAIN_MENU = 2},
    STATES = {SHOP = 1, SELECTING_HAND = 2, BLIND_SELECT = 3, TAROT_PACK = 4},
    STAGE = 1,
    GAME = {multiplayer = true, mp_settings = {}, pseudorandom = {seed = "ABCD1234"}},
    FUNCS = {},
    UIDEF = {},
    ARGS = {},
}
local lock = nil
bom_rulesets = {lock_kind = function() return lock end}
local phase = "playing"
bom_match = {PHASE = {MATCH_END = "match_end"}, get_phase = function() return phase end, get_settings = function() return {} end}
local pb_state = nil
bom_playback = {active = function() return pb_state ~= nil end, state = function() return pb_state end}
DynaText = function(c) return {config = c, remove = function() end} end

local F = dofile(root .. "/assets/functions/mp/fair_play.lua")
check("global set", MPFair == F)

G.GAME.multiplayer = nil
check("solo allows everything", F.allowed("speed") and F.allowed("seed"))
G.GAME.multiplayer = true

check("casual default limits speed", F.limited("speed") and F.limited("score") and F.limited("skip"))
check("casual default hides seed", F.seed_hidden())
G.GAME.mp_settings = {allow_fast_speed = true, show_seed = true}
check("host allows fast speed", F.allowed("speed") and not F.allowed("score"))
check("host shows seed", not F.seed_hidden())
G.GAME.mp_settings = {allow_fast_speed = "yes", show_seed = 1}
check("non boolean values do not allow", F.limited("speed") and F.seed_hidden())

G.GAME.mp_settings = {allow_fast_speed = true, show_seed = true}
lock = "ranked"
check("ranked ignores settings", F.limited("speed") and F.seed_hidden())
phase = "match_end"
check("seed shown once the match ends", not F.seed_hidden() and F.limited("speed"))
phase, lock = "playing", nil

pb_state = {mode = "replay", header = {}}
check("replay shows the seed", not F.seed_hidden() and F.allowed("speed"))
pb_state = {mode = "live", header = {ranked = true, settings = {show_seed = true}}}
check("live ranked watch hides the seed", F.seed_hidden())
pb_state = {mode = "live", header = {settings = {}}}
check("live casual watch hides the seed by default", F.seed_hidden())
pb_state = {mode = "live", header = {settings = {show_seed = true}}}
check("live casual watch shows the seed when the host allows it", not F.seed_hidden())
pb_state = {mode = "live", live_over = true, header = {ranked = true}}
check("finished live watch shows the seed", not F.seed_hidden())
pb_state = nil

G.GAME.mp_settings = {}
local copy_btn = {n = 1, nodes = {{n = 2, config = {button = "copy_seed"}, nodes = {}}}}
local menu = {n = 0, nodes = {
    [1] = {n = 1, nodes = {{n = 2, config = {button = "settings"}, nodes = {}}}},
    [3] = {n = 1, nodes = {
        {n = 2, nodes = {{n = 3, config = {text = "Seed: "}}}},
        {n = 2, nodes = {{n = 3, config = {text = "ABCD1234"}}}},
        copy_btn,
    }},
    [4] = {n = 1, nodes = {{n = 2, config = {button = "seed_lib_save_current"}, nodes = {}}}},
    [6] = {n = 1, nodes = {{n = 2, config = {button = "go_to_menu"}, nodes = {}}}},
}}
F.hide_seed_in(menu)
local function has(node, pred)
    if type(node) ~= "table" then return false end
    if pred(node) then return true end
    for _, c in pairs(node.nodes or {}) do if has(c, pred) then return true end end
    return false
end
check("seed text replaced", not has(menu, function(n) return n.config and n.config.text == "ABCD1234" end)
    and has(menu, function(n) return n.config and n.config.text == "Hidden in MP" end))
check("copy and save removed", not has(menu, function(n) return n.config and (n.config.button == "copy_seed" or n.config.button == "seed_lib_save_current") end))
check("other buttons kept after the hole", menu.nodes[1] ~= nil and menu.nodes[6] ~= nil)

local dyn = {n = 0, nodes = {{n = 1, config = {object = DynaText({string = {"ABCD1234"}, scale = 0.75})}}}}
F.hide_seed_in(dyn)
check("dynatext replaced", dyn.nodes[1].config.object.config.string[1] == "Hidden in MP")

print(fails == 0 and "ALL OK" or (fails .. " FAILED"))
os.exit(fails == 0 and 0 or 1)
