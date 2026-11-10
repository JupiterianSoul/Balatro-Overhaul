local Q = QOL
local M = Q.feature("settings_search", {})

M.KEY = "Search"
M.SKIP = {Search = true, Guide = true, Jukebox = true, Debug = true}
M.MAX = 9
M.MIN_CHARS = 2
M.state = {query = ""}

function M.norm(s)
    s = tostring(s or ""):lower()
    local map = {["à"] = "a", ["â"] = "a", ["á"] = "a", ["ä"] = "a", ["ç"] = "c", ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
        ["í"] = "i", ["î"] = "i", ["ï"] = "i", ["ñ"] = "n", ["ó"] = "o", ["ô"] = "o", ["ö"] = "o", ["ú"] = "u", ["û"] = "u", ["ü"] = "u"}
    s = s:gsub("[\195][\128-\191]", function(ch) return map[ch] or ch end)
    return s
end

function M.match(entries, query, max)
    local q = M.norm(query):gsub("^%s+", ""):gsub("%s+$", "")
    if #q < M.MIN_CHARS then return {} end
    local first, rest = {}, {}
    for _, e in ipairs(entries) do
        local l = M.norm(e.label)
        if l:find(q, 1, true) == 1 then
            first[#first + 1] = e
        elseif l:find(q, 1, true) or M.norm(e.info):find(q, 1, true) or M.norm(e.section):find(q, 1, true) then
            rest[#rest + 1] = e
        end
    end
    for _, e in ipairs(rest) do first[#first + 1] = e end
    while #first > (max or M.MAX) do table.remove(first) end
    return first
end

local function discard(node, depth)
    depth = depth or 0
    if type(node) ~= "table" or depth > 60 then return end
    local c = node.config
    if c and type(c.object) == "table" and c.object.remove then
        pcall(c.object.remove, c.object)
        c.object = nil
    end
    if type(node.nodes) == "table" then
        for i = 1, table.maxn(node.nodes) do discard(node.nodes[i], depth + 1) end
    end
end

function M.collect(tab, flows, out)
    for _, f in ipairs(flows) do
        local section = ""
        for i = 1, table.maxn(f.items or {}) do
            local it = f.items[i]
            if type(it) == "table" then
                if it.uik_header then
                    section = tostring(it.uik_title or "")
                elseif it.uik_o and it.uik_o.label and it.uik_o.id and it.uik_o.label ~= "" then
                    out[#out + 1] = {label = tostring(it.uik_o.label), info = tostring(it.uik_o.info or ""), id = it.uik_o.id,
                        tab = tab.key, tab_label = tostring(tab.label or tab.key), flow = f.id, section = section}
                end
            end
        end
    end
end

function M.index(args)
    local out = {}
    if not (args and args.tabs) then return out end
    for _, tab in ipairs(args.tabs) do
        if not M.SKIP[tab.key] and tab.build then
            M.capture = {}
            local pages = {}
            for k, v in pairs(UIK._pages) do pages[k] = v end
            local ok, def = pcall(tab.build)
            local flows = M.capture
            M.capture = nil
            for k in pairs(UIK._pages) do UIK._pages[k] = pages[k] end
            if ok then
                M.collect(tab, flows, out)
                discard(def)
            end
        end
    end
    return out
end

M.PATH_COLOUR = {1, 1, 1, 0.72}

function M.result_button(e)
    local w = UIK.row_w(3) - 0.3
    local h = UIK.touch() and 1.05 or 0.95
    local path = e.tab_label .. (e.section ~= "" and (" > " .. e.section) or "")
    return {n = G.UIT.C, config = {align = 'cm', minw = w, maxw = w, minh = h, padding = 0.06, r = 0.1, hover = true, shadow = true, colour = UIK.C.button,
        button = 'qol_search_go', ref_table = e, id = 'qol_search_' .. e.id}, nodes = {
        {n = G.UIT.R, config = {align = 'cm', padding = 0}, nodes = {
            {n = G.UIT.C, config = {align = 'cm', maxw = w - 0.2}, nodes = {
                {n = G.UIT.T, config = {text = e.label, scale = UIK.touch() and 0.44 or 0.4, colour = G.C.UI.TEXT_LIGHT, shadow = true}},
            }},
        }},
        {n = G.UIT.R, config = {align = 'cm', padding = 0}, nodes = {
            {n = G.UIT.C, config = {align = 'cm', maxw = w - 0.2}, nodes = {
                {n = G.UIT.T, config = {text = path, scale = UIK.touch() and 0.32 or 0.29, colour = M.PATH_COLOUR}},
            }},
        }},
    }}
end

function M.results_def()
    local q = M.state.query or ""
    local found = M.match(M.entries or {}, q)
    local nodes
    if #found > 0 then
        local items = {}
        for _, e in ipairs(found) do items[#items + 1] = M.result_button(e) end
        nodes = {UIK.grid(items, 3, {padding = 0.12})}
    else
        local msg = #M.norm(q):gsub("%s", "") < M.MIN_CHARS and mod_loc("Type at least two letters") or mod_loc("No setting found")
        nodes = {{n = G.UIT.R, config = {align = 'cm', padding = 0.2}, nodes = {UIK.text(msg, {colour = G.C.UI.TEXT_INACTIVE})}}}
    end
    return {n = G.UIT.ROOT, config = {align = 'tm', colour = G.C.CLEAR, padding = 0, minw = UIK.W - 0.4}, nodes = nodes}
end

function M.build()
    M.entries = M.index(UIK._win)
    M.last = nil
    local input = UIK.input{id = 'qol_search_input', label = mod_loc("Search settings"), info = mod_loc("Type a few letters of a setting"),
        ref_table = M.state, ref_value = 'query', max_length = 20, prompt = mod_loc("Search"), w = UIK.row_w(1)}
    return {n = G.UIT.R, config = {align = 'tm', minw = UIK.W, padding = 0}, nodes = {
        {n = G.UIT.C, config = {align = 'tm', padding = 0}, nodes = {
            {n = G.UIT.R, config = {align = 'cm', padding = 0}, nodes = {input}},
            {n = G.UIT.R, config = {align = 'tm', padding = 0.05, minh = 0.2}, nodes = {}},
            {n = G.UIT.R, config = {align = 'tm', padding = 0}, nodes = {
                {n = G.UIT.O, config = {id = 'qol_search_results', func = 'qol_search_watch', object = UIBox{definition = M.results_def(), config = {offset = {x = 0, y = 0}, align = 'cm'}}}},
            }},
        }},
    }}
end

function M.refresh_results(e)
    if e.config.object then e.config.object:remove() end
    e.config.object = UIBox{definition = M.results_def(), config = {offset = {x = 0, y = 0}, align = 'cm', parent = e}}
    e.UIBox:recalculate()
end

function M.focus_input()
    if UIK.touch() or not G.OVERLAY_MENU then return end
    local body = G.OVERLAY_MENU:get_UIE_by_ID('uik_body')
    local box = body and body.config.object
    local input = box and box.get_UIE_by_ID and box:get_UIE_by_ID('text_input')
    if input and G.FUNCS.select_text_input then G.FUNCS.select_text_input(input) end
end

function M.find_row(e)
    local menu = G.OVERLAY_MENU
    if not menu then return nil end
    return menu:get_UIE_by_ID(e.id) or (function()
        local body = menu:get_UIE_by_ID('uik_body')
        local box = body and body.config.object
        return box and box.get_UIE_by_ID and box:get_UIE_by_ID(e.id) or nil
    end)()
end

function M.go(e)
    if not (e and e.tab and UIK._win) then return end
    if G.CONTROLLER then G.CONTROLLER.text_input_hook = nil end
    UIK._pages[e.flow] = 1
    UIK.open_tab(e.tab)
    local row = M.find_row(e)
    for p = 2, 8 do
        if row then break end
        UIK._pages[e.flow] = p
        UIK.refresh()
        row = M.find_row(e)
    end
    if not row then
        UIK._pages[e.flow] = 1
        UIK.refresh()
        return
    end
    M.jumped = e.id
    if row.juice_up then row:juice_up(0.25, 0.25) end
    play_sound('paper1', 1.1, 0.5)
end

local function strings()
    if not mod_loc_register then return end
    mod_loc_register{
        fr = {["Search"] = "Recherche", ["Search settings"] = "Chercher un réglage", ["Type a few letters of a setting"] = "Tapez quelques lettres d'un réglage",
            ["Type at least two letters"] = "Tapez au moins deux lettres", ["No setting found"] = "Aucun réglage trouvé"},
        es = {["Search"] = "Buscar", ["Search settings"] = "Buscar ajustes", ["Type a few letters of a setting"] = "Escribe unas letras de un ajuste",
            ["Type at least two letters"] = "Escribe al menos dos letras", ["No setting found"] = "Ningún ajuste encontrado"},
    }
end

function Q.search_tab()
    local def = M.build()
    G.E_MANAGER:add_event(Event({blocking = false, blockable = false, func = function()
        pcall(M.focus_input)
        return true
    end}))
    return def
end

function M.init()
    strings()
    G.FUNCS.qol_search_watch = function(e)
        local q = M.state.query or ""
        if q == M.last then return end
        M.last = q
        local ok, err = pcall(M.refresh_results, e)
        if not ok then print("[QoL] search: " .. tostring(err)) end
    end
    G.FUNCS.qol_search_go = function(e)
        local ok, err = pcall(M.go, e and e.config and e.config.ref_table)
        if not ok then print("[QoL] search go: " .. tostring(err)) end
    end
    if M._wrapped or not (UIK and UIK.flow) then return end
    M._wrapped = true
    local flow = UIK.flow
    UIK.flow = function(o, ...)
        if M.capture and type(o) == "table" then M.capture[#M.capture + 1] = {id = o.id or 'flow', items = o.items or {}} end
        return flow(o, ...)
    end
end

strings()

return M
