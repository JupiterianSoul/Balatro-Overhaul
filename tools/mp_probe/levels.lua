-- usage: luajit tools/mp_probe/levels.lua <assets> <level> <games> [stake] [first_seed]
local root, level, games, stake, first = arg[1], arg[2], tonumber(arg[3]) or 1, tonumber(arg[4]) or 1, tonumber(arg[5]) or 1
local H = assert(loadfile(root .. "/bot/mp/worker.lua"))("--lib", root)
local wins, antes, max_dec, tot_adv, adv_n = 0, 0, 0, 0, 0
for g = 1, games do
    local bot = "L" .. level .. g
    assert(H.new({bot = bot, seed = "LV" .. (first + g), deck = "b_red", stake = stake, level = level, win_ante = 8}).ok)
    local t0 = os.clock()
    local ante = 1
    while true do
        local c0 = os.clock()
        local r = H.advance({bot = bot})
        local d = os.clock() - c0
        tot_adv, adv_n = tot_adv + d, adv_n + 1
        if d > max_dec then max_dec = d end
        if not r.ok then print("ERR", r.err) break end
        if r.done then break end
        ante = r.ante
        H.pvp({bot = bot, on = false})
        local over = false
        for _ = 1, 40 do
            local h = H.hand({bot = bot})
            if not h.ok then print("ERRH", h.err) over = true break end
            if h.lost then over = true end
            if h.over then break end
        end
        if over then break end
    end
    local s = H.bots[bot].core.s
    local won = s.won == 1 or s.phase == "win"
    wins = wins + (won and 1 or 0)
    antes = antes + s.ante
    print(string.format("%s game %d ante %d won %s phase %s secs %.0f", level, g, s.ante, tostring(won), s.phase, os.clock() - t0))
    io.stdout:flush()
    H.drop({bot = bot})
end
print(string.format("RESULT %s games=%d wins=%d mean_ante=%.2f advance_avg=%.2fs advance_max=%.2fs", level, games, wins, antes / games, tot_adv / math.max(1, adv_n), max_dec))
