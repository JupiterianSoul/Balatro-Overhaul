local Q = QOL
local M = Q.feature("fast_packs", {})

M.SCALE = 0.1
M.WINDOW = 6
M.TRIGGERS = {after = true, before = true, ease = true}

Q.default("qol_fast_packs", false)

function M.allowed()
    if not (Q.on("qol_fast_packs") and Q.solo()) then return false end
    if bom_playback and bom_playback.active and bom_playback.active() then return false end
    return true
end

function M.opening()
    local c = M.card
    if not c then return false end
    if G.pack_cards and G.pack_cards.cards and #G.pack_cards.cards > 0 then M.card = nil return false end
    if (M.till or 0) < (G.TIMERS and G.TIMERS.REAL or 0) then M.card = nil return false end
    return true
end

function M.shorten(event)
    if type(event) ~= "table" or not M.TRIGGERS[event.trigger] then return end
    if not M.opening() then return end
    local d = tonumber(event.delay)
    if d and d > 0 then event.delay = d * M.SCALE end
end

Q.row("Shop", function()
    return Q.toggle('set_qol_fast_packs', "Fast packs", "Booster packs open at once in solo runs", 'qol_fast_packs')
end)

Q.row("Tavern", function()
    local T = rawget(_G, "Tavern")
    local st = T and T.store and T.store.state and T.store.state()
    if not st then return nil end
    M.tavern = {on = st.fast == true}
    return UIK.toggle{id = 'set_qol_tavern_fast', label = mod_loc("Fast Market openings"), info = mod_loc("Market packs and crates open faster"),
        ref_table = M.tavern, ref_value = 'on', callback = function(v)
            local s = T.store.state()
            if s then s.fast = v and true or false end
            if T.shop and T.shop.fast then T.shop.fast.on = v and true or false end
            pcall(function() if G and G.save_progress then G:save_progress() end end)
        end}
end)

local function strings()
    if not mod_loc_register then return end
    mod_loc_register{
        fr = {["Fast packs"] = "Paquets rapides", ["Booster packs open at once in solo runs"] = "Les paquets s'ouvrent d'un coup en solo",
            ["Fast Market openings"] = "Ouvertures rapides au Marché", ["Market packs and crates open faster"] = "Les paquets et caisses du Marché s'ouvrent plus vite"},
        es = {["Fast packs"] = "Sobres rápidos", ["Booster packs open at once in solo runs"] = "Los sobres se abren al instante en solitario",
            ["Fast Market openings"] = "Aperturas rápidas en el Mercado", ["Market packs and crates open faster"] = "Los sobres y cajas del Mercado se abren más rápido"},
    }
end

function M.init()
    strings()
    if M._wrapped or not (Card and Card.open and EventManager and EventManager.add_event) then return end
    M._wrapped = true
    local open = Card.open
    Card.open = function(self, ...)
        local ok, fast = pcall(function() return self.ability and self.ability.set == "Booster" and M.allowed() end)
        if ok and fast then
            M.card = self
            M.till = (G.TIMERS and G.TIMERS.REAL or 0) + M.WINDOW
        end
        return open(self, ...)
    end
    local add = EventManager.add_event
    EventManager.add_event = function(self, event, ...)
        if M.card then pcall(M.shorten, event) end
        return add(self, event, ...)
    end
end

strings()

return M
