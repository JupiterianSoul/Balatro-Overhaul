local M = {}

local function L(s)
    if mod_loc then
        local ok, r = pcall(mod_loc, s)
        if ok and r then return r end
    end
    return s
end

local FR = {
    ["Race"] = "Course",
    ["Everyone races to the target ante, no PvP"] = "Tout le monde fonce vers la mise initiale visée, sans JcJ",
    ["Trap cards"] = "Cartes piège",
    ["Trap Packs in the shop"] = "Paquets de pièges en boutique",
    ["Deck draft"] = "Draft des jeux",
    ["Ban and pick decks in turn"] = "Bannir puis choisir les jeux à tour de rôle",
    ["Target ante"] = "Mise initiale visée",
    ["First to clear it wins"] = "Le premier à la finir gagne",
    ["MP balance reworks, Justice banned"] = "Rééquilibrages MP, Justice bannie",
}
FR["Race to ante %d"] = "Course jusqu'à la mise initiale %d"
local ES = {
    ["Race"] = "Carrera",
    ["Everyone races to the target ante, no PvP"] = "Todos corren hasta la apuesta inicial objetivo, sin JcJ",
    ["Trap cards"] = "Cartas trampa",
    ["Trap Packs in the shop"] = "Sobres de trampas en la tienda",
    ["Deck draft"] = "Draft de barajas",
    ["Ban and pick decks in turn"] = "Vetar y elegir barajas por turnos",
    ["Target ante"] = "Apuesta inicial objetivo",
    ["First to clear it wins"] = "Gana el primero en superarla",
    ["MP balance reworks, Justice banned"] = "Ajustes de equilibrio MP, Justicia vetada",
    ["Race to ante %d"] = "Carrera hasta la apuesta inicial %d",
}

local function register_party()
    local P = bom_party
    if P and P.KINDS then
        local found = false
        for _, x in ipairs(P.KINDS) do if x == "race" then found = true end end
        if not found then P.KINDS[#P.KINDS + 1] = "race" end
        P.KIND_NAME.race = "Race"
        P.KIND_INFO.race = "Everyone races to the target ante, no PvP"
    end
end

local function insert_after(list, key, defs)
    for _, d in ipairs(defs) do
        for _, x in ipairs(list) do if x.key == d.key then return end end
    end
    local at = #list
    for i, x in ipairs(list) do if x.key == key then at = i break end end
    for i, d in ipairs(defs) do table.insert(list, at + i, d) end
end

local function register_lobby()
    local LS = bom_lobby_settings
    if not (LS and LS.DEFS) then return end
    local function race_on(s)
        local party = bom_party and bom_party.active and bom_party.active()
        if party then return (s.party_kind or "br") == "race" end
        return (s.mode or "nemesis") == "race"
    end
    insert_after(LS.DEFS, "the_order", {
        {key = "traps", tab = "match", kind = "toggle", label = "Trap cards", info = "Trap Packs in the shop"},
        {key = "race_target", tab = "match", kind = "stepper", label = "Target ante", info = "First to clear it wins", min = 1, max = 12, show = race_on},
    })
    insert_after(LS.DEFS, "different_decks", {
        {key = "deck_draft", tab = "players", kind = "toggle", label = "Deck draft", info = "Ban and pick decks in turn", no_party = true},
    })
end

local function register_rulesets()
    local RS = bom_rulesets
    if not (RS and RS.register) then return end
    if RS.NEW_SETTINGS then
        local add = {traps = false, deck_draft = false, race_target = 4}
        for k, v in pairs(add) do if RS.NEW_SETTINGS[k] == nil then RS.NEW_SETTINGS[k] = v end end
        if RS.install_settings then pcall(RS.install_settings) end
    end
end

function M.init()
    if mod_loc_register then pcall(mod_loc_register, {fr = FR, es = ES}) end
    pcall(register_party)
    pcall(register_lobby)
    pcall(register_rulesets)
    if bom_party_run and bom_party_run.rules_lines and not M.rules_wrapped then
        M.rules_wrapped = true
        local orig = bom_party_run.rules_lines
        bom_party_run.rules_lines = function(s)
            s = s or (bom_match and bom_match.get_settings and bom_match.get_settings()) or {}
            local ok, pk = pcall(function() return bom_party.kind() end)
            local k = s.party_kind or (ok and pk or nil)
            if k == "race" then return {string.format(L("Race to ante %d"), tonumber(s.race_target) or 4), L("Ties go to whoever got there first")} end
            return orig(s)
        end
    end
end

return M
