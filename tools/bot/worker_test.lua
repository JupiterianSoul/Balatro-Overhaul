local here = arg[0]:match("^(.*)/tools/bot/") or "."
local root = here .. "/assets"
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local H = assert(loadfile(root .. "/bot/mp/worker.lua"))("--lib", root)
local fails = 0
local function check(ok, what)
    if not ok then
        fails = fails + 1
        print("FAIL " .. what)
    end
end

local t0 = H.now()
local x = 0
for i = 1, 3e6 do x = x + i % 7 end
check(x > 0 and H.now() > t0, "wall clock moves")
local L = H.LEVELS
check(L.easy.hand < L.medium.hand and L.medium.hand <= L.hard.hand, "hand budgets grow with the level")
check(L.easy.shop < L.medium.shop and L.medium.shop <= L.hard.shop, "shop budgets grow with the level")
check(L.hard.hand <= 4 and L.hard.pick <= 3 and L.hard.shop <= 20, "hard thinks inside the time a person takes: 4 s per hand, 3 s per shop action")
for name, lv in pairs(L) do check((lv.slip or 0) == 0 and not lv.econ_slip, name .. " makes no random mistakes and never leaves the shop on purpose") end
check(L.easy.budget == "normal" and L.easy.soft >= 0.2 and L.easy.pick >= 0.3, "easy gets the old hard search")
check(L.medium.budget == "deep" and L.hard.budget == "deep", "medium and hard get the deep search")
check(L.easy.pick < L.medium.pick and L.medium.pick < L.hard.pick, "shop think time grows with the level")

local SK = H.spend_keep
local DJ = require("bot.sim.data").JOKERS
local bull
for i, j in ipairs(DJ) do if j.key == "j_bull" then bull = i end end
local fake = {phase = "shop", n_jok = 0, j_id = {}, no_interest = 0, interest_cap = 25, money = 40}
check(SK(L.hard.spend, fake) == 25 and SK(L.medium.spend, fake) == 25, "rich hard and medium bots keep the interest cap and spend the rest")
check(SK(L.easy.spend, fake) == 10, "a rich easy bot keeps less")
fake.money = 30
check(SK(L.hard.spend, fake) == nil and SK(L.medium.spend, fake) == nil, "the interest cap plus a little is kept on purpose")
fake.money = 60
fake.phase = "pack"
check(SK(L.hard.spend, fake) == nil, "the rule only acts in the shop")
fake.phase = "shop"
fake.interest_cap, fake.money = 50, 52
check(SK(L.hard.spend, fake) == nil, "Seed Money raises what is kept for interest")
fake.interest_cap, fake.no_interest, fake.money = 25, 1, 20
check(SK(L.medium.spend, fake) == 0, "no interest means no reason to hold money")
fake.no_interest, fake.money, fake.n_jok, fake.j_id = 0, 60, 1, {bull}
check(bull and SK(L.hard.spend, fake) == nil, "Bull is a reason to hold money")
for name, lv in pairs(L) do check(lv.spend and lv.spend.max >= 1 and lv.spend.slack >= 0, name .. " has a spending rule") end

check(H.warm().ok, "warm loads the weights")
assert(H.new({bot = "WT", seed = "WORKERTEST", deck = "b_red", stake = 1, level = "hard", win_ante = 8}).ok)

local function stops_until_play(label)
    local seen, r = {}, nil
    for _ = 1, 40 do
        local w0 = H.now()
        r = H.advance({bot = "WT", stops = true})
        check(H.now() - w0 < L.hard.shop + L.hard.pick + 1, label .. ": advance call inside the shop budget")
        if not r.ok or not r.stop then break end
        seen[#seen + 1] = r.stop
        check(type(r.ante) == "number" and (r.blind == "S" or r.blind == "B" or r.blind == "L"), label .. ": stop names the next blind")
    end
    return seen, r
end

local seen, r = stops_until_play("first blind")
check(seen[1] == "blind_select", "the run starts at blind select")
check(r and r.ok and r.ante == 1 and (r.hands or 0) > 0, "the bot reaches its first blind")

H.pvp({bot = "WT", on = true})
local worst = 0
local h
for _ = 1, 12 do
    local w0 = H.now()
    h = H.hand({bot = "WT"})
    worst = math.max(worst, H.now() - w0)
    if not h.ok or h.over then break end
end
check(h and h.ok, "hands play")
check(worst < L.hard.hand + 0.6, string.format("each hand inside the hand budget (worst %.3f s)", worst))
H.pvp({bot = "WT", on = false})

if h and h.ok and not h.lost then
    seen = stops_until_play("second blind")
    check(seen[1] == "shop", "a shop stop comes after a won blind")
    check(seen[#seen] == "blind_select", "the last stop before a blind is blind select")
end

local function hands_until_over()
    local hh
    for _ = 1, 12 do
        hh = H.hand({bot = "WT"})
        if not hh.ok or hh.over then break end
    end
    return hh
end

h = hands_until_over()
if h and h.ok and not h.lost then
    local bd = H.board({bot = "WT", where = "shop"})
    check(bd.ok and bd.board and bd.board.where == "shop", "board steps from cash out into the shop")
    H.bots.WT.core.s.money = 60
    local stops, acts, left = {}, {}, nil
    local spends = 0
    for _ = 1, 120 do
        r = H.advance({bot = "WT", stops = true, one = true})
        if not r.ok then break end
        if r.stop then stops[#stops + 1] = r.stop end
        if r.act then
            acts[#acts + 1] = r.act
            check(type(r.act.type) == "string" and type(r.act.money) == "number" and type(r.act.jokers) == "number", "each act names its type, the money and the jokers")
            check(type(r.act.cost) == "number" and type(r.act.from) == "string", "each act has its cost and the phase it came from")
            if r.act.type == "leave" then left = r.act end
            if r.act.spend then
                spends = spends + 1
                check(r.act.from == "shop" and r.act.cost > 0 and r.act.money >= 25, "a spend buys something and keeps the interest cap")
            end
        end
        check(r.stop == nil or r.act == nil, "a stop carries no act")
        if not r.stop and not r.more then break end
    end
    check(r and r.ok and (r.hands or 0) > 0, "one action at a time still reaches the next blind")
    check(stops[1] == "blind_select" or stops[1] == "shop", "the first stop after the board is the shop or blind select")
    check(#acts >= 2, "the shop and blind select give at least two acts")
    check(acts[#acts] and acts[#acts].type == "select", "the last act before a blind selects it")
    check(left and type(left.held) == "table" and #left.held == left.jokers, "leave lists the jokers held")
    check(left and left.money < 60 and (spends > 0 or left.money <= 30), "a bot with $60 spends before it leaves the shop")
    check(spends <= L.hard.spend.max, "the rule spends at most its count per shop")
    print(string.format("shop with $60: %d acts, %d by the spending rule, left with $%s", #acts, spends, tostring(left and left.money)))
    for _, a in ipairs(acts) do io.write(a.type, a.key and (" " .. a.key) or "", a.spend and " (spend)" or "", " $", tostring(a.money), "; ") end
    print()
end

H.drop({bot = "WT"})
check(H.bots.WT == nil, "drop frees the bot")
print(fails == 0 and "OK worker_test" or ("FAILED " .. fails))
os.exit(fails == 0 and 0 or 1)
