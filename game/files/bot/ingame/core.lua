local E = require("bot.sim.engine")
local ST = require("bot.sim.state")
local SN = require("bot.sim.snapshot")
local PL = require("bot.seer.play")

local C = {}
C.__index = C

C.WEIGHTS = "bot/nn/w16.bnnw"
C.WEIGHTS_NAME = "w16"
C.HYBRID = {easy = {ro = 0}, fast = {ro = 8, ro_a = 0}, normal = {ro = 128, ro_a = 32}, deep = {ro = 256, ro_a = 32, ro_c = 4}}

C.SEER = {
    fast = {horizon = 1, tight_horizon = 2, beam = 2, tight_beam = 3, depth = 2, solve_beam = 4, solve_plays = 2, solve_discards = 4},
    normal = {},
    deep = {horizon = 3, tight_horizon = 4, tight_beam = 6, depth = 4, tight_margin = 0.8},
}
C.FAIR_SIMS = {fast = 64, normal = 200, deep = 800}
C.FAIR_SEER = {easy = {budget = "lite", worlds = 1}, fast = {budget = "lite", worlds = 2}, normal = {budget = "lite"}, deep = {budget = "std"}}
C.MAX_ECON = 40

C.W14_BASE = {who = "greedy", weights = "", sims = 32, K = 24, per = 6, decks = "", stakes = "", part = 0, parts = 1, out = "", max_moves = 3000, max_shop = 40,
    mix = -1, score_prior = 0, score_top = 6, score_temp = 4, skip_pen = 1, skip_ante = 1, type_mass = 0, tm_plays = 0, quick_clear = 0, pace = 0, pace_net = 0, prefix = "", first = 1, seeds = 10, jsonl = "", fair = 0, search_ph = "", rec = "", solver = "", solver_qc = 0, set = "", curve = 0, trace = 0, list = "", leaf_money = 0, leaf_rent = 0, leaf_dead = 0, rent_prior = 1, rent_from = 0, sell_dead = 0, c_puct = 1.5, worlds = 1, ro = 0, ro_a = 0, ro_z = 2, ro_c = 3, ro_h = 0, ro_ph = "shop,pack,blind_select", ro_from = 0, ro_mon = 0, ro_net = 0, ro_t = 0.25, log = ""}
C.W14_BASE.digest = 0
C.W14_BASE.teach, C.W14_BASE.blog, C.W14_BASE.t_skip = 0, 0, 0
C.W14_BASE.vlog = 0
C.W14_BASE.ro_res, C.W14_BASE.ro_resw = "", 1
C.W14_BASE.solver_h, C.W14_BASE.solver_en, C.W14_BASE.solver_hb = 0, 0, 0
C.W14_BASE.swap_play, C.W14_BASE.swap_shop = 0, 0
C.W14_BASE.ro_plan, C.W14_BASE.ro_plan_c, C.W14_BASE.ro_planh, C.W14_BASE.ro_fast, C.W14_BASE.ro_useplanet, C.W14_BASE.ro_order, C.W14_BASE.ro_book = 0, 0, 0, 0, 0, 0, ""
C.W14 = {who = "net", sims = 32, K = 24, fair = 1, search_ph = "shop,pack,blind_select", quick_clear = 1, pace = 1.25, ro_h = 1, ro_mon = 0.5,
    ro_net = 9, ro = 128, ro_a = 16, ro_z = 2, curve = 1, solver = "std", solver_qc = 0, ro_fast = 1, solver_h = 5, solver_en = 32, solver_hb = 1,
    ro_order = 1, ro_base = 0, solver_tie = 1, ro_h2 = "3,4,5,6,7", ro_c = 5, solver_sell = 1, ro_jt = 1, ro_jth = 1, ro_jtab = "bot/w14/stab.txt",
    ro_swap = 1, ro_ordro = 2, ro_useplanet = 1}
C.W14_RO = {easy = 0, fast = 32, normal = 128, deep = 256}
C.W14_NAME = "w16"

local function copy_action(a)
    local o = {type = a.type}
    for k, v in pairs(a) do
        if type(v) == "table" then
            local t = {}
            for i, x in ipairs(v) do t[i] = x end
            o[k] = t
        else
            o[k] = v
        end
    end
    return o
end
C.copy_action = copy_action

C.FIELDS = {
    play = {"cards"}, discard = {"cards"}, use = {"card", "targets"}, sell = {"area", "card"}, reorder_jokers = {"order"},
    buy = {"card"}, buy_and_use = {"card"}, redeem = {"card"}, open = {"card"}, pick = {"card", "targets"},
}

local function clean(a)
    local o = {type = a.type}
    for _, k in ipairs(C.FIELDS[a.type] or {}) do
        local v = a[k]
        if type(v) == "table" then
            if #v > 0 then
                local t = {}
                for i, x in ipairs(v) do t[i] = x end
                o[k] = t
            end
        elseif v ~= nil then
            o[k] = v
        end
    end
    return o
end
C.clean = clean

local function fallback(s)
    local ph = s.phase
    if ph == "play" then return PL.fast_action(s)
    elseif ph == "shop" then return {type = "leave"}
    elseif ph == "pack" then return {type = "skip"}
    elseif ph == "blind_select" then return {type = "select"}
    elseif ph == "round_eval" then return {type = "cash_out"} end
    return nil
end
C.fallback = fallback

function C.new(kind, setup, budget, weights_path, sampler_seed)
    local self = setmetatable({}, C)
    self.sampler_seed = sampler_seed or "GAME"
    self.kind = kind
    self.budget = budget or "normal"
    self.s = E.new_run(setup)
    self.econ = 0
    self.queue = nil
    if kind == "seer" then
        local S = require("bot.seer.seer")
        self.seer = S.new(C.SEER[self.budget] or {})
    elseif kind == "fairseer" then
        local F = require("bot.seer.fair")
        local o = C.FAIR_SEER[self.budget] or C.FAIR_SEER.normal
        self.fair = F.new({budget = o.budget, worlds = o.worlds, sampler_seed = self.sampler_seed})
    elseif kind == "hybrid" then
        local F = require("bot.seer.fair")
        local o = C.FAIR_SEER[self.budget] or C.FAIR_SEER.normal
        self.fair = F.new({budget = o.budget, worlds = o.worlds, sampler_seed = self.sampler_seed})
        self.hybrid = true
        local WT = require("bot.nn.weights")
        local NET = require("bot.nn.net")
        local MC = require("bot.nn.mcts")
        C.shared_w = C.shared_w or WT.load(weights_path or C.WEIGHTS)
        local function new_mc()
            return MC.new(NET.new(C.shared_w), {K = 24, seed = 99991, alpha = 0.5, quick_clear = 1, pace = 1.25, nodes = 34, full = true})
        end
        self.mc = new_mc()
        self.step_buf = {type = "play", cards = {}}
        local h = C.HYBRID[self.budget] or C.HYBRID.normal
        if h.ro > 0 then
            local RO = require("bot.nn.rollout")
            self.ro = RO.chooser(self.mc, new_mc(), {ro = h.ro, ro_a = h.ro_a, ro_z = 2, ro_c = h.ro_c or 3, ro_h = 1, ro_mon = 0.5, ro_net = 9, max_shop = 40})
        end
    elseif kind == "w14" then
        self:w14_init(weights_path)
    elseif kind == "fair" then
        local WT = require("bot.nn.weights")
        local NET = require("bot.nn.net")
        local MC = require("bot.nn.mcts")
        local W = WT.load(weights_path or C.WEIGHTS)
        local sims = C.FAIR_SIMS[self.budget] or C.FAIR_SIMS.normal
        self.sims = sims
        self.mc = MC.new(NET.new(W), {K = 24, seed = 99991, alpha = 0.5, nodes = sims + 2, full = true})
        self.step_buf = {type = "play", cards = {}}
    else
        error("unknown brain " .. tostring(kind))
    end
    return self
end

function C:w14_init(weights_path)
    local WT = require("bot.nn.weights")
    local NET = require("bot.nn.net")
    local MC = require("bot.nn.mcts")
    local F = require("bot.seer.fair")
    local o = {}
    for k, v in pairs(C.W14_BASE) do o[k] = v end
    for k, v in pairs(C.W14) do o[k] = v end
    o.ro = C.W14_RO[self.budget] or C.W14_RO.normal
    self.opt = o
    C.shared_w14 = C.shared_w14 or WT.load(weights_path or C.WEIGHTS)
    local W = C.shared_w14
    local function new_mc()
        return MC.new(NET.new(W), {K = o.K, seed = 99991, alpha = 0.5, mix = o.mix >= 0 and o.mix or nil, score_prior = o.score_prior, score_top = o.score_top,
            score_temp = o.score_temp, skip_pen = o.skip_pen, skip_ante = o.skip_ante, type_mass = o.type_mass, tm_plays = o.tm_plays, quick_clear = o.quick_clear,
            pace = o.pace, pace_net = o.pace_net, leaf_money = o.leaf_money, leaf_rent = o.leaf_rent, leaf_dead = o.leaf_dead, rent_prior = o.rent_prior,
            rent_from = o.rent_from, c_puct = o.c_puct, nodes = 2 * o.sims + 2, full = true})
    end
    self.mc = new_mc()
    self.step_buf = {type = "play", cards = {}}
    self.solver = F.new({budget = o.solver, quick_clear = o.solver_qc > 0, honest = o.solver_h, eval_n = o.solver_en, honest_final = o.solver_hb > 0 and 0 or 1,
        tie = o.solver_tie, sell = o.solver_sell})
    self.w14 = true
    if o.ro > 0 then self.ro = require("bot.w14.rollout").chooser(self.mc, new_mc(), o) end
    self.order_key = nil
end

function C:w14_decide()
    local s = self.s
    local ph = s.phase
    local o = self.opt
    local F = require("bot.seer.fair")
    local q = self.queue
    if q and q.i <= #q.acts and q.step == s.step and s.phase == "shop" then
        return q.acts[q.i], "w14 plan"
    end
    self.queue = nil
    self.think = nil
    if o.ro_useplanet > 0 then
        local k = require("bot.w14.plan").planet_slot(s)
        if k then return {type = "use", card = k}, "w14 planet" end
    end
    if o.ro_order > 0 and ph == "blind_select" then
        local PLAN = require("bot.w14.plan")
        if not PLAN.any_flipped(s) then
            local key = s.n_jok
            for k = 1, s.n_jok do key = key .. "," .. s.j_uid[k] end
            if key ~= self.order_key then
                self.order_key = key
                local ord = PLAN.best_order(F.world(F.sanitize(s), "ORD_" .. s.ante))
                if ord then return {type = "reorder_jokers", order = ord}, "w14 joker order" end
            end
        end
    end
    if ph == "play" then
        self.solver.last_cands = nil
        local acts = self.solver:decide(s)
        local lc = self.solver.last_cands
        if lc and #lc > 1 then
            local items = {}
            for i = 1, math.min(4, #lc) do
                local c = lc[i]
                if c.plan and c.plan[1] then items[#items + 1] = {a = copy_action(c.plan[1]), w = c.w or 0, v = c.v or 0} end
            end
            self.think = {kind = "solver", n = lc[1].wk and #lc[1].wk or 0, items = items}
        end
        if acts and acts[1] then return acts[1], "w14 solver" end
        return PL.fast_action(s), "w14 quick play"
    end
    local view = F.world(F.sanitize(s), string.format("FW%s_%d", self.sampler_seed, s.step))
    local mc = self.mc
    mc.commit_edge = nil
    local sims = ("," .. o.search_ph .. ","):find("," .. ph .. ",", 1, true) and o.sims or 0
    if self.cheap and sims > 4 then sims = 4 end
    mc:search(view, sims, {noise = 0, reuse = false, adaptive = true})
    local e = mc:choose(0)
    if self.ro and not self.ro_off and sims > 0 and e and ("," .. o.ro_ph .. ","):find("," .. ph .. ",", 1, true) then
        local a, _, seq = self.ro(s, self.sampler_seed, s.step)
        local lt = require("bot.w14.rollout").last_think
        if lt and #lt > 1 then
            local items, n = {}, 0
            for i = 1, math.min(4, #lt) do items[#items + 1] = {a = copy_action(lt[i].a), v = lt[i].v} n = math.max(n, lt[i].n) end
            self.think = {kind = "ro", n = n, items = items}
        end
        if a then
            if seq and #seq > 1 then self.queue = {acts = seq, i = 1, step = s.step} end
            return a, "w14 rollouts"
        end
    end
    if not e then return nil end
    return copy_action(mc:edge_action(e, self.step_buf, view)), "w14 net"
end

function C:set_budget(budget)
    if budget == self.budget then return end
    self.budget = budget
    if self.w14 then
        self:w14_init()
        return
    end
    if self.seer then
        local S = require("bot.seer.seer")
        self.seer = S.new(C.SEER[budget] or {})
    elseif self.fair then
        local F = require("bot.seer.fair")
        local o = C.FAIR_SEER[budget] or C.FAIR_SEER.normal
        self.fair = F.new({budget = o.budget, worlds = o.worlds, sampler_seed = self.sampler_seed})
        self.queue = nil
    elseif self.mc then
        self.sims = C.FAIR_SIMS[budget] or C.FAIR_SIMS.normal
    end
end

function C:done()
    local s = self.s
    return s.won == 1 or s.phase == "game_over" or s.phase == "win"
end

function C:step(a)
    local ph = self.s.phase
    local ok = E.step(self.s, a)
    if not ok then return false end
    if ph == "shop" or ph == "pack" then self.econ = self.econ + 1 else self.econ = 0 end
    if self.queue then
        local q = self.queue
        if q.i <= #q.acts and q.step + 1 == self.s.step and q.acts[q.i].type == a.type then
            q.i = q.i + 1
            q.step = self.s.step
        else
            self.queue = nil
        end
    end
    return true
end

function C:legal(a)
    if not a then return false end
    local c = ST.clone(self.s)
    return E.step(c, copy_action(a)) and true or false
end

function C:raw_decide()
    local s = self.s
    local ph = s.phase
    if ph == "round_eval" then return {type = "cash_out"}, "cash out" end
    if self.econ >= C.MAX_ECON and (ph == "shop" or ph == "pack") then return fallback(s), "shop guard" end
    if self.w14 then
        return self:w14_decide()
    elseif self.seer then
        return self.seer:choose(s), "seer"
    elseif self.hybrid and not (ph == "play" and (s.mp_pvp == 1 or self.budget ~= "easy")) then
        local F = require("bot.seer.fair")
        local view = F.world(F.sanitize(s), string.format("FW%s_%d", self.sampler_seed, s.step))
        local mc = self.mc
        mc.commit_edge = nil
        mc:search(view, ph == "play" and 0 or (self.cheap and 4 or 32), {noise = 0, reuse = false, adaptive = true})
        local e = mc:choose(0)
        if not e then return nil end
        if self.ro and not self.ro_off and ph ~= "play" then
            local a = self.ro(s, self.sampler_seed, s.step)
            if a then return a, "rollouts" end
        end
        return copy_action(mc:edge_action(e, self.step_buf, view)), "net"
    elseif self.fair then
        local q = self.queue
        if q and q.i <= #q.acts and q.step == s.step then
            return q.acts[q.i], "fair seer plan"
        end
        self.queue = nil
        local acts = self.fair:decide(s)
        if not acts or #acts == 0 then return nil end
        self.queue = {acts = acts, i = 1, step = s.step}
        return acts[1], "fair seer"
    else
        local mc = self.mc
        mc.commit_edge = nil
        mc:search(s, self.sims, {noise = 0, reuse = false, adaptive = true})
        local e = mc:choose(0)
        if not e then return nil end
        return copy_action(mc:edge_action(e, self.step_buf, s)), "fair net " .. tostring(mc.sims_done or self.sims) .. " sims"
    end
end

function C:decide()
    if self:done() then return nil, "run over" end
    self.think = nil
    local ok, a, why = pcall(self.raw_decide, self)
    if ok and a and self:legal(a) then return clean(a), why, self.think end
    self.queue = nil
    local fb = fallback(self.s)
    if fb and self:legal(fb) then
        return clean(fb), ok and "fallback" or ("fallback: " .. tostring(a))
    end
    return nil, ok and "no action" or tostring(a)
end

function C:snap()
    local b = SN.build(self.s)
    local out = {phase = b.phase, ante = b.ante, money = b.money, step = b.step, hand = {}, jokers = {}, consumables = {}}
    for i, c in ipairs(b.hand) do out.hand[i] = c end
    for i, j in ipairs(b.jokers) do out.jokers[i] = j.key end
    for i, c in ipairs(b.consumables) do out.consumables[i] = c end
    if b.shop then
        out.shop = {}
        for i, j in ipairs(b.shop.jokers) do out.shop[i] = j.key end
    end
    if b.pack then
        out.pack = {}
        for i, p in ipairs(b.pack) do out.pack[i] = p end
    end
    return out
end

return C
