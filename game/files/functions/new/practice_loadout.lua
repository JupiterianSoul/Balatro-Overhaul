BO_PRACTICE = BO_PRACTICE or {}
local BP = BO_PRACTICE
BP.LO = BP.LO or {}
local LO = BP.LO

local function L(s) return mod_loc and mod_loc(s) or s end

LO.KINDS = {
  {key = 'typical', label = "Typical run"},
  {key = 'mine', label = "From my run"},
  {key = 'build', label = "Build my own"},
}

LO.HANDS = {'High Card', 'Pair', 'Two Pair', 'Three of a Kind', 'Straight', 'Flush', 'Full House', 'Four of a Kind', 'Straight Flush'}

LO.PLANET = {['High Card'] = 'c_pluto', ['Pair'] = 'c_mercury', ['Two Pair'] = 'c_uranus', ['Three of a Kind'] = 'c_venus', ['Straight'] = 'c_saturn',
  ['Flush'] = 'c_jupiter', ['Full House'] = 'c_earth', ['Four of a Kind'] = 'c_mars', ['Straight Flush'] = 'c_neptune'}

LO.BUILDS = {
  {hand = 'Pair', second = 'Two Pair', enh = 'm_mult', tarot = 'c_empress',
    jokers = {'j_jolly', 'j_sly', 'j_mad', 'j_clever', 'j_duo', 'j_spare_trousers', 'j_ride_the_bus', 'j_half'}},
  {hand = 'Flush', second = 'High Card', enh = 'm_bonus', tarot = 'c_heirophant', suit = 'Hearts',
    jokers = {'j_droll', 'j_crafty', 'j_tribe', 'j_lusty_joker', 'j_bloodstone', 'j_smeared', 'j_four_fingers'}},
  {hand = 'Straight', second = 'High Card', enh = 'm_bonus', tarot = 'c_heirophant',
    jokers = {'j_crazy', 'j_devious', 'j_order', 'j_runner', 'j_shortcut', 'j_four_fingers', 'j_superposition'}},
  {hand = 'Three of a Kind', second = 'Full House', enh = 'm_mult', tarot = 'c_empress',
    jokers = {'j_zany', 'j_wily', 'j_trio', 'j_family', 'j_scary_face', 'j_photograph'}},
  {hand = 'High Card', second = 'Pair', enh = 'm_steel', tarot = 'c_chariot',
    jokers = {'j_joker', 'j_abstract', 'j_supernova', 'j_banner', 'j_misprint', 'j_green_joker', 'j_mystic_summit'}},
}

LO.SUPPORT = {'j_joker', 'j_even_steven', 'j_odd_todd', 'j_fibonacci', 'j_scholar', 'j_walkie_talkie', 'j_gros_michel', 'j_ice_cream',
  'j_popcorn', 'j_blue_joker', 'j_scary_face', 'j_smiley', 'j_banner'}
LO.CARRY = {'j_cavendish', 'j_baron', 'j_campfire', 'j_constellation', 'j_hologram', 'j_lucky_cat', 'j_steel_joker', 'j_blackboard'}

local function seen(k)
  local c = G.P_CENTERS[k]
  return c and c.discovered and c.unlocked ~= false and true or false
end

local function hash(s)
  local h = 5381
  s = tostring(s)
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
  return h
end

function LO.rng(seed)
  local s = hash(seed) % 2147483646 + 1
  return function(n)
    s = (s * 16807) % 2147483647
    if n then return s % n + 1 end
    return s / 2147483647
  end
end

local function pick(list, r, taken)
  local pool = {}
  for _, k in ipairs(list) do if seen(k) and not taken[k] then pool[#pool + 1] = k end end
  if #pool == 0 then return nil end
  local k = pool[r(#pool)]
  taken[k] = true
  return k
end

function LO.typical(ante, seed)
  ante = math.max(1, math.min(8, tonumber(ante) or 1))
  local r = LO.rng('typical' .. ante .. '_' .. tostring(seed or 0))
  local b = LO.BUILDS[r(#LO.BUILDS)]
  local n = ({1, 2, 3, 3, 4, 4, 5, 5})[ante]
  local taken, jokers = {}, {}
  local main = math.max(1, n - (ante >= 3 and 1 or 0) - (ante >= 5 and 1 or 0))
  for _ = 1, main do
    local k = pick(b.jokers, r, taken)
    if k then jokers[#jokers + 1] = {k = k} end
  end
  if ante >= 3 then
    local k = pick(LO.SUPPORT, r, taken)
    if k then jokers[#jokers + 1] = {k = k} end
  end
  if ante >= 5 then
    local k = pick(LO.CARRY, r, taken)
    if k then jokers[#jokers + 1] = {k = k} end
  end
  while #jokers < n do
    local k = pick(LO.SUPPORT, r, taken) or pick(b.jokers, r, taken)
    if not k then break end
    jokers[#jokers + 1] = {k = k}
  end
  if #jokers == 0 and G.P_CENTERS.j_joker then jokers[1] = {k = 'j_joker'} end
  if ante >= 4 and #jokers > 0 then jokers[r(#jokers)].e = ante >= 7 and 'holo' or 'foil' end
  local levels = {[b.hand] = 1 + math.floor(ante * 0.8 + 0.5)}
  levels[b.second] = math.max(levels[b.second] or 1, 1 + math.floor(ante / 3))
  local cons = {}
  if ante >= 2 and LO.PLANET[b.hand] and seen(LO.PLANET[b.hand]) then cons[#cons + 1] = LO.PLANET[b.hand] end
  if ante >= 4 and b.tarot and seen(b.tarot) then cons[#cons + 1] = b.tarot end
  local vouchers = {}
  if ante >= 4 and seen('v_grabber') then vouchers[#vouchers + 1] = 'v_grabber' end
  if ante >= 6 and seen('v_wasteful') then vouchers[#vouchers + 1] = 'v_wasteful' end
  return {kind = 'typical', build = b.hand, jokers = jokers, levels = levels, dollars = 2 + 2 * ante, consumables = cons, vouchers = vouchers,
    enh = {key = b.enh, n = 2 * (ante - 1), suit = b.suit}, foil = ante >= 5 and (ante - 4) or 0, seed = hash('deck' .. ante .. tostring(seed or 0))}
end

local function ed_type(e)
  if type(e) == 'string' then return e end
  if type(e) == 'table' then
    if e.type then return e.type end
    for k, v in pairs(e) do if v == true then return k end end
  end
  return nil
end

function LO.from_save(s)
  if not (type(s) == 'table' and s.GAME) then return nil end
  local g = s.GAME
  local areas = s.cardAreas or {}
  local function list(area, set)
    local out = {}
    for _, v in ipairs(area and area.cards or {}) do
      local k = v.save_fields and v.save_fields.center
      if k and G.P_CENTERS[k] and (not set or G.P_CENTERS[k].set ~= 'Default') then out[#out + 1] = {k = k, e = ed_type(v.edition)} end
    end
    return out
  end
  local levels = {}
  for h, v in pairs(g.hands or {}) do
    if type(v) == 'table' and (tonumber(v.level) or 1) > 1 then levels[h] = tonumber(v.level) end
  end
  local cons = {}
  for _, c in ipairs(list(areas.consumeables)) do cons[#cons + 1] = c.k end
  local vouchers = {}
  for k, on in pairs(g.used_vouchers or {}) do if on and G.P_CENTERS[k] then vouchers[#vouchers + 1] = k end end
  table.sort(vouchers)
  local cards = {}
  for _, name in ipairs({'deck', 'hand', 'discard', 'play'}) do
    for _, v in ipairs(areas[name] and areas[name].cards or {}) do
      local f = v.save_fields and v.save_fields.card
      if f and G.P_CARDS[f] then
        cards[#cards + 1] = {f = f, c = v.save_fields.center, e = ed_type(v.edition), s = v.seal}
      end
    end
  end
  local back = s.BACK and s.BACK.name
  local deck
  for _, v in ipairs(G.P_CENTER_POOLS.Back or {}) do if v.name == back then deck = v.key end end
  return {kind = 'mine', source = 'saved', jokers = list(areas.jokers), levels = levels, dollars = tonumber(g.dollars) or 0, consumables = cons,
    vouchers = vouchers, cards = #cards > 0 and cards or nil, deck = deck, ante = g.round_resets and tonumber(g.round_resets.ante) or 1}
end

function LO.from_history(e, ante)
  if type(e) ~= 'table' then return nil end
  local a = tonumber(ante) or tonumber(e.ante) or 1
  local t = LO.typical(a, e.id)
  local jokers = {}
  for _, j in ipairs(e.jokers or {}) do if G.P_CENTERS[j.k] then jokers[#jokers + 1] = {k = j.k, e = j.e} end end
  t.kind, t.source, t.jokers, t.deck, t.ante = 'mine', e.id, jokers, e.deck, tonumber(e.ante) or 1
  if e.hand then t.levels = {[e.hand] = 1 + math.floor(a * 0.8 + 0.5)} end
  return t
end

local function deck_label(k)
  local ok, s = pcall(localize, {type = 'name_text', key = k, set = 'Back'})
  if ok and type(s) == 'string' and s ~= '' and s ~= 'ERROR' then return s end
  return G.P_CENTERS[k] and G.P_CENTERS[k].name or tostring(k)
end

function LO.sources()
  local out = {}
  local s = G.SAVED_GAME or (G.FILES and G.SETTINGS and G.FILES[G.SETTINGS.profile .. '/save.jkr'])
  if type(s) == 'table' and s.GAME and not s.GAME.bo_practice and not s.GAME.multiplayer then
    local lo = LO.from_save(s)
    if lo then out[#out + 1] = {key = 'saved', label = L("Saved run") .. ", " .. localize('k_ante') .. " " .. tostring(lo.ante), lo = lo} end
  end
  local H = rawget(_G, 'BO_HISTORY')
  local list = H and H.load and H.load() or {}
  for i = #list, 1, -1 do
    local e = list[i]
    if type(e) == 'table' and e.id and e.mode ~= 'mp' and e.jokers and #e.jokers > 0 then
      out[#out + 1] = {key = e.id, label = deck_label(e.deck) .. ", " .. localize('k_ante') .. " " .. tostring(e.ante or 1) .. (e.t and (", " .. os.date('%d/%m', e.t)) or ''), entry = e}
      if #out >= 30 then break end
    end
  end
  return out
end

function LO.build_state()
  BP.sel.build = type(BP.sel.build) == 'table' and BP.sel.build or {jokers = {}, levels = {}, dollars = 10, consumables = {}}
  return BP.sel.build
end

function LO.from_build()
  local s = LO.build_state()
  local jokers, levels, cons = {}, {}, {}
  for _, k in ipairs(s.jokers) do if seen(k) then jokers[#jokers + 1] = {k = k} end end
  for h, v in pairs(s.levels) do if (tonumber(v) or 1) > 1 then levels[h] = tonumber(v) end end
  for _, k in ipairs(s.consumables) do if seen(k) then cons[#cons + 1] = k end end
  return {kind = 'build', jokers = jokers, levels = levels, dollars = tonumber(s.dollars) or 0, consumables = cons, vouchers = {}}
end

function LO.resolve(kind, ante)
  if kind == 'mine' then
    local src = LO.sources()
    local want = BP.sel.source
    local hit = src[1]
    for _, v in ipairs(src) do if v.key == want then hit = v end end
    if not hit then return nil end
    BP.sel.source = hit.key
    if hit.lo then return hit.lo end
    return LO.from_history(hit.entry, ante)
  elseif kind == 'build' then
    return LO.from_build()
  end
  return LO.typical(ante, BP.sel.reroll or 0)
end

function LO.discovered(set)
  local out = {}
  for _, v in ipairs(G.P_CENTER_POOLS[set] or {}) do
    if type(v) == 'table' and v.key and seen(v.key) and not v.no_collection and not v.omit then out[#out + 1] = v.key end
  end
  return out
end

local function new_card(area, key, e)
  local c = G.P_CENTERS[key]
  if not (c and area) then return nil end
  local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H, nil, c, {bypass_discovery_center = true, bypass_discovery_ui = true})
  if e then pcall(card.set_edition, card, {[e] = true}, true, true) end
  card:add_to_deck()
  area:emplace(card)
  return card
end

local function rebuild_deck(cards)
  for i = #(G.playing_cards or {}), 1, -1 do
    local c = G.playing_cards[i]
    if c.area then c.area:remove_card(c) end
    c:remove()
  end
  G.playing_cards = {}
  for _, v in ipairs(cards) do
    local front, center = G.P_CARDS[v.f], G.P_CENTERS[v.c] or G.P_CENTERS.c_base
    if front then
      local card = create_playing_card({front = front, center = center}, G.deck, true, true)
      if card then
        if v.e then pcall(card.set_edition, card, {[v.e] = true}, true, true) end
        if v.s then card:set_seal(v.s, true, true) end
      end
    end
  end
  G.GAME.starting_deck_size = #G.playing_cards
end

local function change_deck(lo)
  local list = {}
  for _, c in ipairs(G.playing_cards or {}) do
    if c.config and c.config.center == G.P_CENTERS.c_base then list[#list + 1] = c end
  end
  table.sort(list, function(a, b)
    local sa, sb = a.base.suit or '', b.base.suit or ''
    if sa ~= sb then return sa < sb end
    return (a.base.id or 0) < (b.base.id or 0)
  end)
  local r = LO.rng(lo.seed or 1)
  local enh = lo.enh
  if enh and G.P_CENTERS[enh.key] and (enh.n or 0) > 0 then
    local pool = {}
    for _, c in ipairs(list) do if not enh.suit or c.base.suit == enh.suit then pool[#pool + 1] = c end end
    for _ = 1, math.min(enh.n, #pool) do
      local c = table.remove(pool, r(#pool))
      c:set_ability(G.P_CENTERS[enh.key], nil, true)
    end
  end
  for _ = 1, lo.foil or 0 do
    local c = list[r(#list)]
    if c and not c.edition then pcall(c.set_edition, c, {foil = true}, true, true) end
  end
end

function LO.apply(lo)
  if type(lo) ~= 'table' or not G.GAME then return end
  for _, v in ipairs(lo.vouchers or {}) do
    if G.P_CENTERS[v] and not G.GAME.used_vouchers[v] then
      G.GAME.used_vouchers[v] = true
      pcall(Card.apply_to_run, nil, G.P_CENTERS[v])
    end
  end
  for _, j in ipairs(lo.jokers or {}) do new_card(G.jokers, j.k, j.e) end
  local room = G.consumeables and G.consumeables.config.card_limit or 2
  for i, k in ipairs(lo.consumables or {}) do
    if i <= room then new_card(G.consumeables, k) end
  end
  for h, v in pairs(lo.levels or {}) do
    local cur = G.GAME.hands[h] and G.GAME.hands[h].level or 1
    if G.GAME.hands[h] and v > cur then pcall(level_up_hand, nil, h, true, v - cur) end
  end
  if lo.cards then rebuild_deck(lo.cards) else change_deck(lo) end
  if lo.dollars then G.GAME.dollars = math.max(0, math.floor(lo.dollars)) end
end

local function hand_label(h)
  local ok, s = pcall(localize, h, 'poker_hands')
  if ok and type(s) == 'string' and s ~= '' and s ~= 'ERROR' then return s end
  return h
end
LO.hand_label = hand_label

function LO.summary(lo)
  if type(lo) ~= 'table' then return {} end
  local out = {}
  local lv = {}
  for _, h in ipairs(LO.HANDS) do
    if lo.levels and lo.levels[h] then lv[#lv + 1] = hand_label(h) .. " " .. L("lvl") .. " " .. lo.levels[h] end
  end
  out[#out + 1] = #lv > 0 and table.concat(lv, ", ") or L("Every hand at level 1")
  local deck = {}
  if lo.cards then
    deck[#deck + 1] = string.format(L("%d cards from that run"), #lo.cards)
  else
    if lo.enh and (lo.enh.n or 0) > 0 and G.P_CENTERS[lo.enh.key] then
      local ok, n = pcall(localize, {type = 'name_text', set = 'Enhanced', key = lo.enh.key})
      deck[#deck + 1] = ((ok and type(n) == 'string' and n ~= 'ERROR') and n or lo.enh.key) .. " x" .. lo.enh.n
    end
    if (lo.foil or 0) > 0 then deck[#deck + 1] = L("Foil cards") .. " x" .. lo.foil end
  end
  if #deck > 0 then out[#out + 1] = L("Deck") .. ": " .. table.concat(deck, ", ") end
  local vs = {}
  for _, v in ipairs(lo.vouchers or {}) do
    local ok, n = pcall(localize, {type = 'name_text', set = 'Voucher', key = v})
    vs[#vs + 1] = (ok and type(n) == 'string' and n ~= 'ERROR') and n or v
  end
  if #vs > 0 then out[#out + 1] = L("Vouchers") .. ": " .. table.concat(vs, ", ") end
  return out
end

local function touch() return UIK and UIK.touch and UIK.touch() or false end

local function T(str, scale, colour)
  return {n = G.UIT.T, config = {text = tostring(str or ''), scale = scale, colour = colour or G.C.UI.TEXT_LIGHT, shadow = true}}
end

local function strip(label, items, slots, size, w)
  local cw, ch = G.CARD_W * size, G.CARD_H * size
  local inner
  if #items > 0 then
    local area = CardArea(0, 0, w, ch, {card_limit = math.max(1, slots, #items), card_w = cw, type = 'title_2', highlight_limit = 0})
    for _, it in ipairs(items) do
      local c = G.P_CENTERS[it.k]
      if c then
        local card = Card(0, 0, cw, ch, nil, c, {bypass_discovery_center = true, bypass_discovery_ui = true, bypass_lock = true})
        if it.e then pcall(card.set_edition, card, {[it.e] = true}, true, true) end
        area:emplace(card)
      end
    end
    inner = {n = G.UIT.O, config = {object = area}}
  else
    inner = T(localize('k_none'), touch() and 0.44 or 0.34, G.C.UI.TEXT_INACTIVE)
  end
  return {n = G.UIT.C, config = {align = 'cm', padding = 0.05, r = 0.1, colour = G.C.L_BLACK}, nodes = {
    {n = G.UIT.T, config = {text = label, scale = touch() and 0.38 or 0.3, colour = G.C.UI.TEXT_LIGHT, vert = true, shadow = true}},
    {n = G.UIT.C, config = {align = 'cm', minh = ch + 0.06, minw = w, r = 0.1, colour = G.C.UI.TRANSPARENT_DARK}, nodes = {inner}},
  }}
end

local function cons_items(lo)
  local out = {}
  for _, k in ipairs(lo.consumables or {}) do out[#out + 1] = {k = k} end
  return out
end

local function preview(lo, w)
  local rows = {}
  rows[#rows + 1] = {n = G.UIT.R, config = {align = 'cm', padding = 0.05}, nodes = {
    strip(localize('k_jokers_cap'), lo.jokers or {}, 5, 0.5, w * 0.6),
    {n = G.UIT.C, config = {minw = 0.15}, nodes = {}},
    strip(localize('k_cap_consumables'), cons_items(lo), 2, 0.5, w * 0.22),
  }}
  local lines = LO.summary(lo)
  table.insert(lines, 1, localize('$') .. tostring(lo.dollars or 0))
  rows[#rows + 1] = UIK.note(lines, {w = w, scale = touch() and 0.42 or 0.33, colour = G.C.UI.TEXT_LIGHT})
  return rows
end

local function label_of(kind)
  for _, k in ipairs(LO.KINDS) do if k.key == kind then return L(k.label) end end
  return ''
end

local function sprite(key, w)
  local c = G.P_CENTERS[key]
  local atlas = c and G.ASSET_ATLAS[c.atlas or 'Joker'] or G.ASSET_ATLAS.Joker
  local s = Sprite(0, 0, w, w * G.CARD_H / G.CARD_W, atlas, (c and c.pos) or {x = 0, y = 0})
  s.states.drag.can = false
  return s
end

function LO.build_ui(h)
  local st = LO.build_state()
  local t = touch()
  local cw = UIK.col_w(2)
  local all = LO.discovered('Joker')
  local per_row = t and 7 or 9
  local per = per_row * 2
  local pages = math.max(1, math.ceil(#all / per))
  BP.sel.jpage = math.max(1, math.min(BP.sel.jpage or 1, pages))
  local chosen = {}
  for _, k in ipairs(st.jokers) do chosen[k] = true end
  local items = {}
  for _, k in ipairs(st.jokers) do items[#items + 1] = {k = k} end
  local tw = t and 0.62 or 0.56
  local grid = {}
  local first = (BP.sel.jpage - 1) * per
  for r = 1, 2 do
    local cells = {}
    for c = 1, per_row do
      local k = all[first + (r - 1) * per_row + c]
      if k then
        cells[#cells + 1] = {n = G.UIT.C, config = {align = 'cm', minw = tw + 0.12, minh = tw * G.CARD_H / G.CARD_W + 0.12, r = 0.08, hover = true, shadow = true, padding = 0.04,
          colour = chosen[k] and G.C.GOLD or {0, 0, 0, 0.25}, button = 'bo_bp_jpick', ref_table = {key = k}, id = 'bo_bp_j_' .. k}, nodes = {
          {n = G.UIT.O, config = {object = sprite(k, tw)}},
        }}
      else
        cells[#cells + 1] = {n = G.UIT.C, config = {minw = tw + 0.12, minh = 0.1}, nodes = {}}
      end
      if c < per_row then cells[#cells + 1] = {n = G.UIT.C, config = {minw = 0.06}, nodes = {}} end
    end
    grid[#grid + 1] = {n = G.UIT.R, config = {align = 'cm', padding = 0.03}, nodes = cells}
  end
  local left = {
    {n = G.UIT.R, config = {align = 'cm', padding = 0.04}, nodes = {strip(localize('k_jokers_cap'), items, 5, 0.42, cw - 1.2)}},
    {n = G.UIT.R, config = {align = 'cm'}, nodes = {{n = G.UIT.C, config = {align = 'cm'}, nodes = grid}}},
    UIK.pager{prev = 'bo_bp_jpage', next = 'bo_bp_jpage', prev_ref = {d = -1}, next_ref = {d = 1}, text = BP.sel.jpage .. " / " .. pages, w = cw - 0.4,
      prev_disabled = pages < 2, next_disabled = pages < 2, id = 'bo_bp_jpager'},
  }
  local hands = {}
  for i, hd in ipairs(LO.HANDS) do hands[i] = LO.hand_label(hd) end
  BP.sel.hand_i = math.max(1, math.min(BP.sel.hand_i or 2, #LO.HANDS))
  local hand = LO.HANDS[BP.sel.hand_i]
  local lvl = {v = tonumber(st.levels[hand]) or 1}
  local cons = {{key = nil, label = localize('k_none')}}
  for _, set in ipairs({'Planet', 'Tarot', 'Spectral'}) do
    for _, k in ipairs(LO.discovered(set)) do
      local ok, n = pcall(localize, {type = 'name_text', set = set, key = k})
      cons[#cons + 1] = {key = k, label = (ok and type(n) == 'string' and n ~= 'ERROR') and n or k}
    end
  end
  local copts = {}
  for i, c in ipairs(cons) do copts[i] = c.label end
  local function slot(i)
    local cur = 1
    for j, c in ipairs(cons) do if c.key and c.key == st.consumables[i] then cur = j end end
    return UIK.cycle{label = L("Consumable") .. " " .. i, options = copts, current = cur, w = (cw - 0.4) / 2, cw = 2.0, no_pips = true, id = 'bo_bp_cons' .. i,
      callback = function(j)
        st.consumables[i] = cons[j].key
        local out = {}
        for n = 1, 2 do if st.consumables[n] then out[#out + 1] = st.consumables[n] end end
        st.consumables = out
        UIK.refresh()
      end}
  end
  local half = (cw - 0.4) / 2
  local function pair(a, b) return {n = G.UIT.R, config = {align = 'cm', minw = cw - 0.2}, nodes = {
    {n = G.UIT.C, config = {align = 'cm', minw = half}, nodes = {a}}, {n = G.UIT.C, config = {minw = 0.2}, nodes = {}},
    {n = G.UIT.C, config = {align = 'cm', minw = half}, nodes = {b}}}} end
  local right = {
    pair(UIK.cycle{label = L("Hand"), options = hands, current = BP.sel.hand_i, w = half, cw = 2.2, no_pips = true, id = 'bo_bp_hand',
        callback = function(i) BP.sel.hand_i = i UIK.refresh() end},
      UIK.stepper{label = L("Level"), ref_table = lvl, ref_value = 'v', min = 1, max = 20, w = half, cw = 1.4, id = 'bo_bp_level',
        callback = function(v) st.levels[hand] = v UIK.refresh() end}),
    pair(UIK.stepper{label = L("Money"), ref_table = st, ref_value = 'dollars', min = 0, max = 200, big_step = 10, w = half, cw = 1.4, id = 'bo_bp_money',
        format = function(v) return localize('$') .. tostring(v) end},
      {n = G.UIT.R, config = {align = 'cm', minw = half}, nodes = {UIK.note(LO.summary(LO.from_build())[1] and {LO.summary(LO.from_build())[1]} or {}, {w = half})}}),
    pair(slot(1), slot(2)),
  }
  return {n = G.UIT.R, config = {align = 'cm', minw = UIK.W, minh = h, padding = 0}, nodes = {
    UIK.columns({{UIK.section(L("Jokers you have found"), left, {w = cw, h = h - 0.2})}, {UIK.section(label_of('build'), right, {w = cw, h = h - 0.2})}}, {h = h}),
  }}
end

function BP.loadout_tab()
  local h = UIK.H - UIK.TOP
  local kind = BP.sel.kind or 'typical'
  if kind == 'build' then return LO.build_ui(h) end
  local ante = math.max(1, math.min(8, tonumber(BP.sel.ante) or 1))
  local w = UIK.W - 1
  local rows = {UIK.header(label_of(kind) .. "  (" .. localize('k_ante') .. " " .. ante .. ")", {w = w})}
  if kind == 'mine' then
    local src = LO.sources()
    if #src == 0 then
      rows[#rows + 1] = UIK.note({L("No saved run or Run history yet.")}, {w = w, scale = touch() and 0.42 or 0.36})
      return {n = G.UIT.R, config = {align = 'cm', minw = UIK.W, minh = h}, nodes = {{n = G.UIT.C, config = {align = 'cm'}, nodes = rows}}}
    end
    local opts, cur = {}, 1
    for i, v in ipairs(src) do
      opts[i] = v.label
      if v.key == BP.sel.source then cur = i end
    end
    BP.sel.source = src[cur].key
    rows[#rows + 1] = #opts > 1 and UIK.cycle{label = L("Run"), options = opts, current = cur, w = 7, cw = 4.4, no_pips = true, id = 'bo_bp_source',
      callback = function(i) BP.sel.source = src[i].key UIK.refresh() end} or UIK.value{label = L("Run"), value = opts[1], w = 7, vw = 4.4}
  end
  local lo = LO.resolve(kind, ante)
  if lo then for _, r in ipairs(preview(lo, w - 1)) do rows[#rows + 1] = r end end
  if kind == 'typical' then
    rows[#rows + 1] = {n = G.UIT.R, config = {align = 'cm', padding = 0.1}, nodes = {
      UIK.button{label = L("Another build"), button = 'bo_bp_reroll', colour = UIK.C.purple, id = 'bo_bp_reroll'}}}
  end
  return {n = G.UIT.R, config = {align = 'cm', minw = UIK.W, minh = h}, nodes = {{n = G.UIT.C, config = {align = 'cm'}, nodes = rows}}}
end

G.FUNCS.bo_bp_reroll = function()
  BP.sel.reroll = (BP.sel.reroll or 0) + 1
  UIK.refresh()
end

G.FUNCS.bo_bp_jpage = function(e)
  local d = e and e.config and e.config.ref_table and e.config.ref_table.d or 1
  local per = (touch() and 7 or 9) * 2
  local pages = math.max(1, math.ceil(#LO.discovered('Joker') / per))
  BP.sel.jpage = ((BP.sel.jpage or 1) - 1 + d) % pages + 1
  UIK.refresh()
end

G.FUNCS.bo_bp_jpick = function(e)
  local k = e and e.config and e.config.ref_table and e.config.ref_table.key
  if not k then return end
  local st = LO.build_state()
  for i, v in ipairs(st.jokers) do
    if v == k then
      table.remove(st.jokers, i)
      UIK.refresh()
      return
    end
  end
  if #st.jokers >= 5 then table.remove(st.jokers, 1) end
  st.jokers[#st.jokers + 1] = k
  UIK.refresh()
end

mod_loc_register{
  fr = {
    ["Typical run"] = "Partie type", ["From my run"] = "De ma partie", ["Build my own"] = "Ma composition",
    ["Saved run"] = "Partie sauvegardée", ["lvl"] = "niv.", ["Every hand at level 1"] = "Toutes les mains au niveau 1",
    ["%d cards from that run"] = "%d cartes de cette partie", ["Foil cards"] = "Cartes brillantes",
    ["Loadout"] = "Équipement", ["Fight"] = "Combat", ["Another build"] = "Autre composition", ["Jokers you have found"] = "Jokers découverts",
    ["Consumable"] = "Consommable", ["No saved run or Run history yet."] = "Pas encore de partie sauvegardée ni d'historique.",
  },
  es = {
    ["Typical run"] = "Partida típica", ["From my run"] = "De mi partida", ["Build my own"] = "Mi montaje",
    ["Saved run"] = "Partida guardada", ["lvl"] = "nv.", ["Every hand at level 1"] = "Todas las manos a nivel 1",
    ["%d cards from that run"] = "%d cartas de esa partida", ["Foil cards"] = "Cartas laminadas",
    ["Loadout"] = "Equipo", ["Fight"] = "Combate", ["Another build"] = "Otro montaje", ["Jokers you have found"] = "Comodines descubiertos",
    ["Consumable"] = "Consumible", ["No saved run or Run history yet."] = "Aún no hay partida guardada ni historial.",
  },
}

return LO
