local here = arg[0]:match("^(.*)/tools/bot/") or "."
local root = here .. "/assets"
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local level = arg[1] or "medium"
local games = tonumber(arg[2]) or 10
local first = tonumber(arg[3]) or 1
local max_ante = tonumber(arg[4]) or 8
local tag = os.getenv("SPEED_TAG") or "SPD"
io.stdout:setvbuf("line")

local H = assert(loadfile(root .. "/bot/mp/worker.lua"))("--lib", root)
H.warm()

local hands, shops = {}, {}
local antes, wins = 0, 0

local function pct(t, p)
    if #t == 0 then return 0 end
    table.sort(t)
    return t[math.max(1, math.ceil(#t * p))]
end

local function mean(t)
    local s = 0
    for _, v in ipairs(t) do s = s + v end
    return #t > 0 and s / #t or 0
end

for g = 1, games do
    local bot = tag .. level .. g
    assert(H.new({bot = bot, seed = tag .. (first + g), deck = "b_red", stake = 1, level = level, win_ante = max_ante}).ok)
    local ante, done = 1, false
    while not done do
        local w0 = H.now()
        local r
        for _ = 1, 64 do
            r = H.advance({bot = bot, stops = true})
            if not r.ok or not r.stop then break end
        end
        if not r.ok or r.done then break end
        if ante > 1 or r.blind ~= "S" then shops[#shops + 1] = (H.now() - w0) * 1000 end
        ante = r.ante
        if ante > max_ante then break end
        H.pvp({bot = bot, on = r.blind == "L"})
        for _ = 1, 40 do
            local h0 = H.now()
            local h = H.hand({bot = bot})
            hands[#hands + 1] = (H.now() - h0) * 1000
            if not h.ok then done = true break end
            if h.over then
                if h.lost then done = true end
                break
            end
        end
    end
    local s = H.bots[bot].core.s
    antes = antes + s.ante
    if s.ante > max_ante or s.phase == "win" then wins = wins + 1 end
    print(string.format("%s game %d ante %d phase %s", level, g, s.ante, s.phase))
    H.drop({bot = bot})
end

print(string.format("RESULT level=%s games=%d wins=%d mean_ante=%.2f hands=%d hand_ms_mean=%.0f hand_ms_p95=%.0f hand_ms_max=%.0f shops=%d shop_ms_mean=%.0f shop_ms_p95=%.0f shop_ms_max=%.0f",
    level, games, wins, antes / math.max(1, games), #hands, mean(hands), pct(hands, 0.95), pct(hands, 1), #shops, mean(shops), pct(shops, 0.95), pct(shops, 1)))
