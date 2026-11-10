local root = (arg and arg[1]) or "."
package.path = root .. "/assets/?.lua;" .. package.path

local fails, checks = 0, 0
local function ok(cond, what)
    checks = checks + 1
    if not cond then fails = fails + 1 print("FAIL " .. what) end
end

local defs = {}
local K = {}
local clock = 0
function K.now() return clock end
function K.card_w() return 2.05 end
function K.card_h() return 2.75 end
function K.pops() return {} end
for _, n in ipairs{"pop", "juice", "sound", "shake", "flash", "press"} do K[n] = function() end end
function K.hit(b, x, y, pad)
    pad = pad or 0
    return x >= b.x - pad and x <= b.x + b.w + pad and y >= b.y - pad and y <= b.y + b.h + pad
end

local played, stopped, src_t = false, false, 0
local src = {}
function src.setPitch() end
function src.setVolume() end
function src.play() played = true end
function src.stop() stopped = true end
function src.release() end
function src.isPlaying() return played and not stopped end
function src.tell() return src_t end
love = {audio = {newSource = function() return src end}}

Minigames = {kit = K, L = function(s) return s end, register = function(d) defs[d.key] = d end}
UIK = {touch = function() return false end, C = {muted = {1, 1, 1, 1}}}
G = {C = {RED = {1, 0, 0, 1}, GOLD = {1, 1, 0, 1}, GREEN = {0, 1, 0, 1}, WHITE = {1, 1, 1, 1}, UI = {BACKGROUND_INACTIVE = {0, 0, 0, 1}}}, SETTINGS = {SOUND = {volume = 50, music_volume = 100}}}

dofile(root .. "/assets/functions/minigames/rhythm.lua")
local def = defs.rhythm
ok(def and def.new, "rhythm registers")

local function new()
    local g = def.new()
    g.W, g.H = 10.6, 5.4
    g:start()
    return g
end

local function play(song, diff, perfect)
    local g = new()
    local function click(b) g:press(b.x + b.w / 2, b.y + b.h / 2) end
    click(g.song_btns[song])
    click(g.diff_btns[diff])
    g:key("down")
    played, stopped, src_t = false, false, 0
    click(g.start_btn)
    ok(g.state == "song", "starts the song")
    ok(G.MG_MUSIC == true, "game music muted while playing")
    local notes = g.notes
    local dt = 1 / 60
    local i, steps = 1, 0
    while not g.over and steps < 60 * 400 do
        steps = steps + 1
        clock = clock + dt
        if played then src_t = src_t + dt * 0.7 end
        g:update(dt)
        if perfect then
            while notes[i] and notes[i].t <= g.t do
                if not notes[i].done then g:key(({"d", "f", "j", "k"})[notes[i].lane]) end
                i = i + 1
            end
        end
    end
    ok(g.over, "song ends")
    ok(stopped, "music stopped at the end")
    ok(G.MG_MUSIC == nil, "game music back after the song")
    return g, #notes
end

local counts = {}
for song = 1, 2 do
    for diff = 1, 3 do
        local g, n = play(song, diff, true)
        counts[#counts + 1] = n
        ok(g.miss == 0, string.format("perfect play has no misses (song %d diff %d, %d misses)", song, diff, g.miss))
        ok(g.result == "Full combo!", "full combo result")
        ok(g.perfect + g.good == n, "every note judged")
        ok(g.score > 0, "scores points")
        print(string.format("song %d diff %d: %d notes, score %d, perfect %d, good %d, %.0fs", song, diff, n, g.score, g.perfect, g.good, g.t))
    end
end
ok(counts[1] < counts[2] and counts[2] < counts[3], "short: more notes on harder difficulties")
ok(counts[4] < counts[5] and counts[5] < counts[6], "long: more notes on harder difficulties")
ok(counts[4] > counts[1], "long song has more notes")

local g, n = play(1, 2, false)
ok(g.miss == n and g.combo == 0 and g.score == 0, "no input misses everything")
ok(g.result == "Song complete!", "result without full combo")

local g2 = new()
g2:key("return")
ok(g2.state == "song", "Enter on Play song starts")
ok(g2:pad_btn("dpleft") == true and g2:pad_btn("b") == true, "pad lane buttons are used in a song")
g2:stop()
ok(G.MG_MUSIC == nil, "stop clears the music flag")
local g3 = new()
ok(g3:pad_btn("dpleft") == false, "pad buttons go to the menu outside a song")

print(string.format("rhythm_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
