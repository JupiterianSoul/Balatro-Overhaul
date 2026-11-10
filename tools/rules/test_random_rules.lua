local root = arg and arg[1] or "."

G = {SETTINGS = {language = "en-us"}, FUNCS = {}, UIDEF = {run_setup_option = function() end},
  C = {GREEN = {0, 1, 0, 1}, RED = {1, 0, 0, 1}, BLUE = {0, 0, 1, 1}}, P_CENTER_POOLS = {}, P_BLINDS = {}}
for _, pool in ipairs({"Joker", "Tarot", "Planet", "Spectral", "Voucher", "Booster", "Tag"}) do
  G.P_CENTER_POOLS[pool] = {}
  for i = 1, 30 do G.P_CENTER_POOLS[pool][i] = {key = pool:lower() .. "_" .. i} end
end
for i = 1, 20 do G.P_BLINDS["bl_boss" .. i] = {boss = {min = 1}} end
G.P_BLINDS.bl_final = {boss = {showdown = true}}
G.P_BLINDS.bl_small = {}
Back, Game, Card = {}, {}, {}
function get_new_boss() end
function calculate_reroll_cost() end
function ease_ante() end

dofile(root .. "/assets/functions/mod_localization.lua")
dofile(root .. "/assets/functions/run_rules.lua")
dofile(root .. "/assets/functions/play/random_run.lua")

local R, PR = RunRules, PlayRandom
local checks, failed = 0, 0
local function check(ok, msg)
  checks = checks + 1
  if not ok then
    failed = failed + 1
    print("FAIL " .. msg)
  end
end

local function valid(d, v)
  if d.kind == "toggle" then return type(v) == "boolean" end
  if d.kind == "list" then
    if type(v) ~= "table" or #v == 0 then return false end
    local seen = {}
    for _, k in ipairs(v) do
      if seen[k] then return false end
      seen[k] = true
      if d.pool == "Blind" then
        local b = G.P_BLINDS[k]
        if not (b and b.boss and not b.boss.showdown) then return false end
      end
    end
    return true
  end
  if d.kind == "slider" then return type(v) == "number" and v >= d.min and v <= d.max end
  if d.kind == "stepper" then
    if type(v) ~= "number" or v ~= math.floor(v) then return false end
    if (d.min and v < d.min) or (d.max and v > d.max) then return false end
    if d.step and (v - (d.min or 0)) % d.step ~= 0 then return false end
    return true
  end
  if d.kind == "cycle" then
    local opts = type(d.options) == "function" and d.options() or d.options
    for _, o in ipairs(opts or {}) do if o.value == v then return true end end
  end
  return false
end

local pool_keys = {}
for _, e in ipairs(PR.POOL) do
  local d = R.by_key[e[1]]
  check(d ~= nil, "pool key " .. tostring(e[1]) .. " is not a run rule")
  check(PR.TONE[e[3]] ~= nil, "pool key " .. tostring(e[1]) .. " has tone " .. tostring(e[3]))
  if d then
    pool_keys[e[1]] = true
    for _, v in ipairs(e[2]) do
      if e[4] == "ban" then
        check(d.kind == "list" and type(v) == "number" and v > 0, e[1] .. " ban count " .. tostring(v))
        local list = PR.ban_list(d.pool, v)
        check(valid(d, list) and #list == v, e[1] .. " ban list of " .. v)
      else
        check(valid(d, v), e[1] .. " value " .. tostring(v) .. " is not valid")
        check(v ~= d.default, e[1] .. " value " .. tostring(v) .. " is the default")
      end
    end
  end
end

local skipped = {stake = true, back = true, starting_jokers = true, starting_vouchers = true, chips_cap = true}
for a, c in pairs(PR.COMPANION) do
  check(pool_keys[a] ~= nil, "companion parent " .. a .. " is in the pool")
  local d = R.by_key[c[1]]
  check(d ~= nil, "companion key " .. c[1])
  for _, v in ipairs(c[2]) do check(d and valid(d, v), c[1] .. " companion value " .. tostring(v)) end
  pool_keys[c[1]] = true
end
local same_word = {fr = {Inflation = true}, es_ES = {}}
local n_rules, n_pool = 0, 0
for _, d in ipairs(R.registry) do
  n_rules = n_rules + 1
  if pool_keys[d.key] then n_pool = n_pool + 1 end
  check(pool_keys[d.key] or skipped[d.key], "run rule " .. d.key .. " is missing from the random pool")
end

for a, list in pairs(PR.CLASH) do
  check(R.by_key[a] ~= nil, "clash key " .. a)
  for _, b in ipairs(list) do check(R.by_key[b] ~= nil, "clash key " .. b) end
end

for _, lang in ipairs({"fr", "es_ES"}) do
  G.SETTINGS.language = lang
  for k in pairs(pool_keys) do
    local d = R.by_key[k]
    check(same_word[lang][d.label] or mod_loc(d.label) ~= d.label, lang .. " label missing: " .. d.label)
  end
end
G.SETTINGS.language = "en-us"

math.randomseed(1110)
local seen, sizes = {}, {}
local tones = {boon = 0, twist = 0, neutral = 0}
for _ = 1, 4000 do
  local out = PR.roll_rules()
  sizes[#out] = (sizes[#out] or 0) + 1
  check(#out >= 2 and #out <= PR.MAX_RULES, "roll size " .. #out)
  local keys = {}
  for i, r in ipairs(out) do
    local d = R.by_key[r.key]
    check(d and valid(d, r.value), "rolled " .. tostring(r.key) .. "=" .. tostring(r.value))
    check(not keys[r.key], "rolled twice " .. r.key)
    for k in pairs(keys) do check(not PR.clashes(k, r.key), "clash rolled " .. k .. " + " .. r.key) end
    keys[r.key] = true
    seen[r.key .. "=" .. (type(r.value) == "table" and ("#" .. #r.value) or tostring(r.value))] = true
    tones[r.tone] = tones[r.tone] + 1
  end
  local norm = R.normalize(PR.values and (function()
    local v = {}
    for _, r in ipairs(out) do v[r.key] = r.value end
    return v
  end)())
  for _, r in ipairs(out) do
    if type(r.value) == "table" then
      check(type(norm[r.key]) == "table" and #norm[r.key] == #r.value, "normalize kept " .. r.key)
    else
      check(norm[r.key] == r.value, "normalize kept " .. r.key)
    end
  end
end

local all, hit = 0, 0
for _, e in ipairs(PR.POOL) do
  for _, v in ipairs(e[2]) do
    all = all + 1
    local id = e[1] .. "=" .. (e[4] == "ban" and ("#" .. v) or tostring(v))
    if seen[id] then hit = hit + 1 else print("never rolled " .. id) end
  end
end
check(hit == all, "every pool value rolls at least once in 4000 rolls")
check(tones.neutral > 0 and tones.boon > tones.neutral and tones.twist > 0, "tone mix")

print(string.format("random rules: %d of %d run rules in the pool, %d values, sizes 2..6: %s", n_pool, n_rules, all,
  table.concat((function() local t = {} for i = 2, PR.MAX_RULES do t[#t + 1] = i .. "=" .. (sizes[i] or 0) end return t end)(), " ")))
print(string.format("random rules tests: %d checks, %d failed", checks, failed))
os.exit(failed == 0 and 0 or 1)
