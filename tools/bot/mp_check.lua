local here = arg[0]:match("^(.*)/tools/bot/") or "."
local root = here .. "/assets"
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local H = assert(loadfile(root .. "/bot/mp/worker.lua"))("--lib", root)
local D = require("bot.sim.data")
local E = require("bot.sim.engine")
local C = require("bot.ingame.core")
local F = require("bot.seer.fair")
local S = require("bot.seer.seer")
local PL = require("bot.seer.play")

local mode = arg[1] or "rolls"
local count = tonumber(arg[2]) or 100
local level = arg[3] or "easy"
local first = tonumber(arg[4]) or 1
local max_ante = tonumber(arg[5]) or 9
local tag = os.getenv("MP_CHECK_TAG") or "CHK"
io.stdout:setvbuf("line")
local lv = H.LEVELS[level]
if lv and os.getenv("MP_CHECK_BUDGET") then lv.budget = os.getenv("MP_CHECK_BUDGET") end
if lv and os.getenv("MP_CHECK_NOCAP") == "1" then lv.shop = nil end
if lv and os.getenv("MP_CHECK_NODL") == "1" then lv.hand, lv.pick, lv.soft = nil, nil, nil end
if lv and tonumber(os.getenv("MP_CHECK_DL")) then
    lv.hand, lv.pick = tonumber(os.getenv("MP_CHECK_DL")), tonumber(os.getenv("MP_CHECK_DL"))
    lv.soft = tonumber(os.getenv("MP_CHECK_SOFT")) or lv.hand
end

local BAN = {}
for _, k in ipairs(H.MP_BANS) do BAN[k] = true end

local fails = 0
local fallbacks = 0
local function fail(msg)
    fails = fails + 1
    if fails <= 30 then print("FAIL " .. msg) end
end

local function check_state(s, who)
    for k = 1, s.n_jok do
        local key = D.JOKERS[s.j_id[k]].key
        if BAN[key] then fail(who .. " owns " .. key) end
    end
    for i = 1, s.n_sj do
        if s.sj_kind[i] == E.K_JOKER and BAN[D.JOKERS[s.sj_id[i]].key] then fail(who .. " shop has " .. D.JOKERS[s.sj_id[i]].key) end
    end
    for i = 1, s.n_pk do
        if s.pk_kind[i] == E.K_JOKER and BAN[D.JOKERS[s.pk_id[i]].key] then fail(who .. " pack has " .. D.JOKERS[s.pk_id[i]].key) end
    end
    for i = 1, s.n_sv do
        if BAN[D.VOUCHERS[s.sv_id[i]].key] then fail(who .. " shop voucher " .. D.VOUCHERS[s.sv_id[i]].key) end
    end
    for i = 1, #D.VOUCHERS do
        if s.used_v[i] == 1 and BAN[D.VOUCHERS[i].key] then fail(who .. " redeemed " .. D.VOUCHERS[i].key) end
    end
    if s.voucher and s.voucher > 0 and BAN[D.VOUCHERS[s.voucher].key] then fail(who .. " next voucher " .. D.VOUCHERS[s.voucher].key) end
    for i = 1, s.n_tags do
        local t = D.TAGS[s.tags[i]]
        if t and BAN[t.key] then fail(who .. " tag " .. t.key) end
    end
    if s.blind and s.blind > 0 and BAN[D.BLINDS[s.blind].key] then fail(who .. " blind " .. D.BLINDS[s.blind].key) end
end

local function new_bot(id, i)
    local r = H.new({bot = id, seed = tag .. i, deck = "b_red", stake = 1 + (i % 8), level = level, win_ante = 99})
    assert(r.ok, "new failed")
    if os.getenv("MP_CHECK_RSEED") == "1" then math.randomseed(i) end
    return H.bots[id]
end

local function rolls()
    local n = 0
    for i = first, first + count - 1 do
        local b = new_bot("R" .. i, i)
        local s = b.core.s
        check_state(s, "seed " .. i)
        s.win_ante = 8
        for ante = 1, 16 do
            s.ante = ante
            for k = 1, 40 do
                local R = E.I.create_card(s, 1, 1 + (k % 2), k % 8 == 0, nil, true, nil, k % 2 == 0 and "sho" or "buf")
                if R.kind == E.K_JOKER then
                    n = n + 1
                    if BAN[D.JOKERS[R.id].key] then fail("seed " .. i .. " a" .. ante .. " rolled " .. D.JOKERS[R.id].key) end
                end
            end
            for _ = 1, 4 do
                local v = E.get_next_voucher(s)
                if BAN[D.VOUCHERS[v].key] then fail("seed " .. i .. " voucher " .. D.VOUCHERS[v].key) end
                local t = E.get_next_tag(s)
                if BAN[D.TAGS[t].key] then fail("seed " .. i .. " tag " .. D.TAGS[t].key) end
                local bo = E.get_new_boss(s)
                if BAN[D.BLINDS[bo].key] then fail("seed " .. i .. " boss " .. D.BLINDS[bo].key) end
                n = n + 3
            end
        end
        H.drop({bot = "R" .. i})
    end
    print(string.format("rolls seeds=%d rolls=%d fails=%d", count, n, fails))
end

local prof = {}
local function add(k, ms)
    local p = prof[k]
    if not p then p = {n = 0, ms = 0, max = 0} prof[k] = p end
    p.n, p.ms = p.n + 1, p.ms + ms
    if ms > p.max then p.max = ms end
end

local function wrap(tbl, name, key)
    local f = tbl[name]
    tbl[name] = function(...)
        local t0 = os.clock()
        local a, b, c, d = f(...)
        add(type(key) == "function" and key(...) or key, (os.clock() - t0) * 1000)
        return a, b, c, d
    end
end

local function pct(list, q)
    if #list == 0 then return 0 end
    table.sort(list)
    return list[math.max(1, math.ceil(#list * q))]
end

local function games()
    local step0 = C.step
    local cur, low = nil, nil
    C.step = function(self, a)
        local ok = step0(self, a)
        local s = self.s
        check_state(s, cur)
        if s.ante < low then fail(cur .. " ante went from " .. low .. " to " .. s.ante) end
        if s.ante > low then low = s.ante end
        return ok
    end
    local dec0 = C.decide
    C.decide = function(self)
        local a, why = dec0(self)
        if type(why) == "string" and why:sub(1, 8) == "fallback" then fallbacks = fallbacks + 1 end
        return a, why
    end
    wrap(C, "decide", function(self) return "decide." .. self.s.phase end)
    wrap(F, "propose", "fair.propose")
    wrap(F, "evaluate", "fair.evaluate")
    wrap(S, "rollout", "seer.rollout")
    wrap(PL, "solve", "play.solve")
    local adv, hand, antes = {}, {}, {}
    local boss = {}
    local t_all = os.clock()
    for i = first, first + count - 1 do
        local id = "G" .. i
        cur, low = "seed " .. i, 1
        local b = new_bot(id, i)
        local s = b.core.s
        local steps = 0
        while steps < 400 do
            steps = steps + 1
            local t0 = os.clock()
            local r = H.advance({bot = id})
            if not r.ok or r.done then break end
            adv[#adv + 1] = (os.clock() - t0) * 1000
            if s.ante > max_ante then break end
            H.pvp({bot = id, on = os.getenv("MP_CHECK_PVP") ~= "0" and r.blind == "L" and r.ante >= 2})
            for _ = 1, 40 do
                local t1 = os.clock()
                local h = H.hand({bot = id})
                hand[#hand + 1] = (os.clock() - t1) * 1000
                if h.ok and h.over and r.blind == "L" then
                    local g = math.floor((r.ante - 1) / 3) + 1
                    boss[g] = boss[g] or {}
                    table.insert(boss[g], math.log10(math.max(1, h.chips or 0)))
                end
                if not h.ok or h.over then break end
            end
            if s.phase == "game_over" then break end
        end
        antes[#antes + 1] = s.ante
        print(string.format("game %d ante %d %s", i, s.ante, s.phase))
        H.drop({bot = id})
    end
    local sum, asum = 0, 0
    for _, v in ipairs(adv) do sum = sum + v end
    for _, v in ipairs(antes) do asum = asum + v end
    local hsum = 0
    for _, v in ipairs(hand) do hsum = hsum + v end
    print(string.format("level=%s games=%d mean_ante=%.2f total_cpu=%.0fs", level, count, asum / #antes, os.clock() - t_all))
    print(string.format("advance n=%d mean=%.0f p50=%.0f p95=%.0f max=%.0f", #adv, sum / math.max(1, #adv), pct(adv, 0.5), pct(adv, 0.95), pct(adv, 1)))
    print(string.format("hand n=%d mean=%.0f p50=%.0f p95=%.0f max=%.0f", #hand, hsum / math.max(1, #hand), pct(hand, 0.5), pct(hand, 0.95), pct(hand, 1)))
    for g = 1, 6 do
        local l = boss[g]
        if l then
            local t = 0
            for _, v in ipairs(l) do t = t + v end
            print(string.format("boss_log10_chips antes %d-%d n=%d mean=%.3f", g * 3 - 2, g * 3, #l, t / #l))
        end
    end
    local keys = {}
    for k in pairs(prof) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
        local p = prof[k]
        print(string.format("prof %-22s n=%6d total=%8.0fms mean=%7.1f max=%7.0f", k, p.n, p.ms, p.ms / p.n, p.max))
    end
    print(string.format("rollout_cuts=%d solve_cuts=%d fallbacks=%d", S.cuts, PL.cuts or 0, fallbacks))
    print(string.format("games fails=%d", fails))
end

if mode == "rolls" then rolls() else games() end
os.exit(fails == 0 and 0 or 1)
