local out = {}
local function put(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    out[#out + 1] = table.concat(parts, " ")
end

put("release", tostring(RELEASE_BUILD))
local sp = {}
for _, c in ipairs(G.P_CENTER_POOLS.Joker or {}) do sp[#sp + 1] = c.key end
table.sort(sp)
put("sp_jokers", #sp)
for _, k in ipairs(sp) do
    if not k:match("^j_[a-z0-9_]+$") or k:match("^j_mp_") then put("sp_extra", k) end
end

local all = {}
for k, c in pairs(G.P_CENTERS) do
    if type(c) == "table" and c.set == "Joker" then all[#all + 1] = k end
end
table.sort(all)
for _, k in ipairs(all) do
    if k:match("^j_mp_") then put("mp_joker", k, G.P_CENTERS[k].atlas, "hidden=" .. tostring(ReleaseFlags.ai_hidden(k))) end
end

local col = rawget(_G, "mpm_collection")
if col and col.jokers then
    local list = col.jokers()
    put("mp_collection_jokers", #list)
    for _, c in ipairs(list) do put("mp_collection_joker", c.key) end
end
if col and col.decks then
    local list = col.decks()
    put("mp_collection_decks", #list)
    for _, c in ipairs(list) do put("mp_collection_deck", c.key) end
end

for _, c in ipairs(G.P_CENTER_POOLS.Back or {}) do
    put("back", c.key, c.atlas, "omit=" .. tostring(c.omit), "hidden=" .. tostring(ReleaseFlags.ai_hidden(c)))
end
if bom_decks and bom_decks.options then
    local opts = bom_decks.options()
    put("lobby_mp_decks", #opts)
    for _, o in ipairs(opts) do put("lobby_mp_deck", o.value) end
end

put("default_mp_jokers", tostring(bom_match.defaults().multiplayer_jokers))
put("ranked_mp_jokers", tostring(bom_rulesets.RANKED.settings.multiplayer_jokers))
local shown = "missing"
for _, d in ipairs((bom_lobby_settings and bom_lobby_settings.DEFS) or {}) do
    if d.key == "multiplayer_jokers" then shown = tostring(not d.show or d.show({})) end
end
put("lobby_toggle_shown", shown)

local f = io.open(os.getenv("RF_OUT"), "w")
f:write(table.concat(out, "\n") .. "\n")
f:close()
