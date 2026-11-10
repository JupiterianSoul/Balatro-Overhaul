local T = {}

T.WIDTH = 28

local W = {
  en = {
    card_scored = "When a card scores", card_held = "For each card held in hand", hand_played = "When a hand is played",
    before = "Before a hand scores", after = "After a hand scores", discard = "When a card is discarded",
    first_hand = "When the first hand is drawn", blind_selected = "When a blind is selected", round_end = "At the end of the round",
    blind_skipped = "When a blind is skipped", reroll = "When the shop is rerolled", shop_end = "When you leave the shop",
    card_sold = "When a card is sold", self_sold = "When this joker is sold", pack_opened = "When a booster pack is opened",
    consumable_used = "When a consumable is used",
    card_bought = "When you buy a card", pack_skipped = "When a booster pack is skipped", cards_destroyed = "When playing cards are destroyed",
    card_added = "When a card is added to your deck",
  },
  fr = {
    card_scored = "Quand une carte marque", card_held = "Pour chaque carte en main", hand_played = "Quand une main est jouée",
    before = "Avant qu'une main marque", after = "Après qu'une main a marqué", discard = "Quand une carte est défaussée",
    first_hand = "Quand la première main est piochée", blind_selected = "Quand une blinde est choisie", round_end = "À la fin de la manche",
    blind_skipped = "Quand une blinde est passée", reroll = "Quand la boutique est relancée", shop_end = "Quand vous quittez la boutique",
    card_sold = "Quand une carte est vendue", self_sold = "Quand ce joker est vendu", pack_opened = "Quand un paquet est ouvert",
    consumable_used = "Quand un consommable est utilisé",
    card_bought = "Quand vous achetez une carte", pack_skipped = "Quand un paquet est passé", cards_destroyed = "Quand des cartes à jouer sont détruites",
    card_added = "Quand une carte est ajoutée à votre jeu",
  },
  es = {
    card_scored = "Cuando una carta anota", card_held = "Por cada carta en la mano", hand_played = "Cuando se juega una mano",
    before = "Antes de que una mano anote", after = "Después de que una mano anote", discard = "Cuando se descarta una carta",
    first_hand = "Cuando se roba la primera mano", blind_selected = "Cuando se elige una ciega", round_end = "Al final de la ronda",
    blind_skipped = "Cuando se salta una ciega", reroll = "Cuando se renueva la tienda", shop_end = "Al salir de la tienda",
    card_sold = "Cuando se vende una carta", self_sold = "Cuando se vende este joker", pack_opened = "Cuando se abre un paquete",
    consumable_used = "Cuando se usa un consumible",
    card_bought = "Cuando compras una carta", pack_skipped = "Cuando se salta un paquete", cards_destroyed = "Cuando se destruyen cartas",
    card_added = "Cuando se añade una carta a tu baraja",
  },
}

local S = {
  en = {
    ["if"] = "if", ["and"] = "and", unless = "unless", otherwise = "otherwise", at_least = "at least", at_most = "at most", exactly = "exactly",
    hand_contains = "the hand contains a {C:attention}%s{}", hand_is = "the hand is a {C:attention}%s{}",
    suit = "it is a {C:%s}%s{}", red = "it is {C:red}red{}", black = "it is {C:spades}black{}",
    rank = "its rank is {C:attention}%s{}", face = "it is a {C:attention}face{} card", number = "it is a {C:attention}number{} card",
    even = "its rank is {C:attention}even{}", odd = "its rank is {C:attention}odd{}",
    enhancement = "it is a {C:attention}%s{}", seal = "it has a {C:attention}%s{}", edition = "it is {C:dark_edition}%s{}",
    cards_played = "%s {C:attention}%d{} cards are played", money = "you have %s {C:money}$%d{}",
    hands_left = "%s {C:blue}%d{} hands are left", discards_left = "%s {C:red}%d{} discards are left",
    first_hand = "it is the {C:attention}first hand{} of the round", last_hand = "it is the {C:attention}last hand{} of the round",
    ante = "the ante is %s {C:attention}%d{}", jokers = "you have %s {C:attention}%d{} jokers", boss = "the blind is a {C:attention}Boss Blind{}",
    chance = "with a {C:green}#1# in %d{} chance",
    chips = "{C:chips}+%s{} Chips", mult = "{C:mult}+%s{} Mult", xmult = "{X:mult,C:white} X%s {} Mult", money_give = "earn {C:money}$%s{}",
    retrigger1 = "retrigger the card", retrigger = "retrigger the card {C:attention}%s{} times",
    gain_chips = "this joker gains {C:chips}+%s{} Chips", gain_mult = "this joker gains {C:mult}+%s{} Mult", gain_xmult = "this joker gains {X:mult,C:white} X%s {} Mult",
    create = "create a {C:%s}%s{} card", create_joker = "create a {C:attention}Joker{}", room = "{C:inactive}(Must have room){}",
    level_up = "level up the played {C:attention}poker hand{}",
    change_suit = "it becomes {C:%s}%s{}", change_rank = "its rank becomes {C:attention}%s{}", change_enh = "it becomes a {C:attention}%s{}", change_seal = "it gets a {C:attention}%s{}",
    hand = "{C:blue}+%s{} hand this round", discard = "{C:red}+%s{} discard this round", destroy_self = "this joker is destroyed",
    var_add = "add {C:attention}%s{} to {C:attention}%s{}", var_sub = "take {C:attention}%s{} from {C:attention}%s{}", var_set = "set {C:attention}%s{} to {C:attention}%s{}",
    var_chips = "{C:chips}+%s{} Chips for each {C:attention}%s{}", var_mult = "{C:mult}+%s{} Mult for each {C:attention}%s{}", var = "{C:attention}%s{} is %s {C:attention}%d{}",
    now = "{C:inactive}(Currently %s{C:inactive}){}", now_chips = "{C:chips}+#2#{C:inactive} Chips", now_mult = "{C:mult}+#3#{C:inactive} Mult", now_xmult = "{X:mult,C:white} X#4# {C:inactive} Mult",
    blind = "the blind is the {C:attention}%s{}", deck_cards = "%s {C:attention}%d{} cards are left in the deck", held_cards = "you hold %s {C:attention}%d{} cards",
    consumables = "you have %s {C:attention}%d{} consumables", hand_level = "the hand's level is %s {C:attention}%d{}", round = "the round is %s {C:attention}%d{}",
    destroy_card = "destroy the card", add_card = "add a {C:attention}%s{} to your deck", add_card_any = "add a random card to your deck",
    sell_value = "this joker gains {C:money}$%s{} of sell value",
    perma_chips = "the card permanently gains {C:chips}+%s{} Chips", copy_card = "add a copy of the card to your deck", tag = "create a {C:attention}%s{}",
    disable_boss = "disable the {C:attention}Boss Blind{}", destroy_joker = "destroy a random {C:attention}Joker{}", change_edition = "it becomes {C:dark_edition}%s{}",
    ranks = {[14] = "Ace", [13] = "King", [12] = "Queen", [11] = "Jack"},
    kinds = {Tarot = "Tarot", Planet = "Planet", Spectral = "Spectral"},
  },
  fr = {
    var_add = "ajoute {C:attention}%s{} à {C:attention}%s{}", var_sub = "retire {C:attention}%s{} de {C:attention}%s{}", var_set = "met {C:attention}%s{} à {C:attention}%s{}",
    var_chips = "{C:chips}+%s{} jetons par {C:attention}%s{}", var_mult = "{C:mult}+%s{} Multi par {C:attention}%s{}", var = "{C:attention}%s{} vaut %s {C:attention}%d{}",
    ["if"] = "si", ["and"] = "et", unless = "sauf si", otherwise = "sinon", at_least = "au moins", at_most = "au plus", exactly = "exactement",
    hand_contains = "la main contient un {C:attention}%s{}", hand_is = "la main est un {C:attention}%s{}",
    suit = "sa couleur est {C:%s}%s{}", red = "elle est {C:red}rouge{}", black = "elle est {C:spades}noire{}",
    rank = "sa valeur est {C:attention}%s{}", face = "c'est une {C:attention}figure{}", number = "c'est une carte {C:attention}numérotée{}",
    even = "sa valeur est {C:attention}paire{}", odd = "sa valeur est {C:attention}impaire{}",
    enhancement = "c'est une {C:attention}%s{}", seal = "elle a un {C:attention}%s{}", edition = "elle est {C:dark_edition}%s{}",
    cards_played = "%s {C:attention}%d{} cartes sont jouées", money = "vous avez %s {C:money}%d ${}",
    hands_left = "il reste %s {C:blue}%d{} mains", discards_left = "il reste %s {C:red}%d{} défausses",
    first_hand = "c'est la {C:attention}première main{} de la manche", last_hand = "c'est la {C:attention}dernière main{} de la manche",
    ante = "la mise est %s {C:attention}%d{}", jokers = "vous avez %s {C:attention}%d{} jokers", boss = "c'est une {C:attention}blinde de boss{}",
    chance = "avec {C:green}#1# chance sur %d{}",
    chips = "{C:chips}+%s{} jetons", mult = "{C:mult}+%s{} Multi", xmult = "{X:mult,C:white} X%s {} Multi", money_give = "gagnez {C:money}%s ${}",
    retrigger1 = "la carte se redéclenche", retrigger = "la carte se redéclenche {C:attention}%s{} fois",
    gain_chips = "ce joker gagne {C:chips}+%s{} jetons", gain_mult = "ce joker gagne {C:mult}+%s{} Multi", gain_xmult = "ce joker gagne {X:mult,C:white} X%s {} Multi",
    create = "crée une carte {C:%s}%s{}", create_joker = "crée un {C:attention}Joker{}", room = "{C:inactive}(Doit avoir de la place){}",
    level_up = "améliore la {C:attention}main de poker{} jouée",
    change_suit = "elle devient {C:%s}%s{}", change_rank = "sa valeur devient {C:attention}%s{}", change_enh = "elle devient {C:attention}%s{}", change_seal = "elle reçoit un {C:attention}%s{}",
    hand = "{C:blue}+%s{} main pour cette manche", discard = "{C:red}+%s{} défausse pour cette manche", destroy_self = "ce joker est détruit",
    now = "{C:inactive}(Actuellement %s{C:inactive}){}", now_chips = "{C:chips}+#2#{C:inactive} jetons", now_mult = "{C:mult}+#3#{C:inactive} Multi", now_xmult = "{X:mult,C:white} X#4# {C:inactive} Multi",
    blind = "c'est la {C:attention}%s{}", deck_cards = "il reste %s {C:attention}%d{} cartes dans le jeu", held_cards = "vous avez %s {C:attention}%d{} cartes en main",
    consumables = "vous avez %s {C:attention}%d{} consommables", hand_level = "le niveau de la main est %s {C:attention}%d{}", round = "la manche est %s {C:attention}%d{}",
    destroy_card = "la carte est détruite", add_card = "ajoute une {C:attention}%s{} à votre jeu", add_card_any = "ajoute une carte au hasard à votre jeu",
    sell_value = "ce joker gagne {C:money}%s ${} de valeur de vente",
    perma_chips = "la carte gagne {C:chips}+%s{} jetons pour toujours", copy_card = "ajoute une copie de la carte à votre jeu", tag = "crée un {C:attention}%s{}",
    disable_boss = "désactive la {C:attention}Blinde de boss{}", destroy_joker = "détruit un {C:attention}Joker{} au hasard", change_edition = "elle devient {C:dark_edition}%s{}",
    ranks = {[14] = "As", [13] = "Roi", [12] = "Dame", [11] = "Valet"},
    kinds = {Tarot = "Tarot", Planet = "Planète", Spectral = "Spectrale"},
  },
  es = {
    var_add = "suma {C:attention}%s{} a {C:attention}%s{}", var_sub = "resta {C:attention}%s{} a {C:attention}%s{}", var_set = "pon {C:attention}%s{} en {C:attention}%s{}",
    var_chips = "{C:chips}+%s{} fichas por cada {C:attention}%s{}", var_mult = "{C:mult}+%s{} multi por cada {C:attention}%s{}", var = "{C:attention}%s{} vale %s {C:attention}%d{}",
    ["if"] = "si", ["and"] = "y", unless = "salvo si", otherwise = "si no", at_least = "al menos", at_most = "como mucho", exactly = "exactamente",
    hand_contains = "la mano contiene {C:attention}%s{}", hand_is = "la mano es {C:attention}%s{}",
    suit = "es de {C:%s}%s{}", red = "es {C:red}roja{}", black = "es {C:spades}negra{}",
    rank = "su valor es {C:attention}%s{}", face = "es una {C:attention}figura{}", number = "es una carta {C:attention}numérica{}",
    even = "su valor es {C:attention}par{}", odd = "su valor es {C:attention}impar{}",
    enhancement = "es una {C:attention}%s{}", seal = "tiene un {C:attention}%s{}", edition = "es {C:dark_edition}%s{}",
    cards_played = "se juegan %s {C:attention}%d{} cartas", money = "tienes %s {C:money}$%d{}",
    hands_left = "quedan %s {C:blue}%d{} manos", discards_left = "quedan %s {C:red}%d{} descartes",
    first_hand = "es la {C:attention}primera mano{} de la ronda", last_hand = "es la {C:attention}última mano{} de la ronda",
    ante = "la apuesta es %s {C:attention}%d{}", jokers = "tienes %s {C:attention}%d{} jokers", boss = "la ciega es un {C:attention}jefe{}",
    chance = "con {C:green}#1# probabilidad entre %d{}",
    chips = "{C:chips}+%s{} fichas", mult = "{C:mult}+%s{} multi", xmult = "{X:mult,C:white} X%s {} multi", money_give = "gana {C:money}$%s{}",
    retrigger1 = "la carta se reactiva", retrigger = "la carta se reactiva {C:attention}%s{} veces",
    gain_chips = "este joker gana {C:chips}+%s{} fichas", gain_mult = "este joker gana {C:mult}+%s{} multi", gain_xmult = "este joker gana {X:mult,C:white} X%s {} multi",
    create = "crea una carta de {C:%s}%s{}", create_joker = "crea un {C:attention}joker{}", room = "{C:inactive}(Debe haber espacio){}",
    level_up = "sube de nivel la {C:attention}mano de póker{} jugada",
    change_suit = "pasa a {C:%s}%s{}", change_rank = "pasa a {C:attention}%s{}", change_enh = "se convierte en {C:attention}%s{}", change_seal = "recibe un {C:attention}%s{}",
    hand = "{C:blue}+%s{} mano en esta ronda", discard = "{C:red}+%s{} descarte en esta ronda", destroy_self = "este joker se destruye",
    now = "{C:inactive}(Actualmente %s{C:inactive}){}", now_chips = "{C:chips}+#2#{C:inactive} fichas", now_mult = "{C:mult}+#3#{C:inactive} multi", now_xmult = "{X:mult,C:white} X#4# {C:inactive} multi",
    blind = "la ciega es la {C:attention}%s{}", deck_cards = "quedan %s {C:attention}%d{} cartas en la baraja", held_cards = "tienes %s {C:attention}%d{} cartas en la mano",
    consumables = "tienes %s {C:attention}%d{} consumibles", hand_level = "el nivel de la mano es %s {C:attention}%d{}", round = "la ronda es %s {C:attention}%d{}",
    destroy_card = "la carta se destruye", add_card = "añade una {C:attention}%s{} a tu baraja", add_card_any = "añade una carta al azar a tu baraja",
    sell_value = "este joker gana {C:money}$%s{} de valor de venta",
    perma_chips = "la carta gana {C:chips}+%s{} fichas para siempre", copy_card = "añade una copia de la carta a tu baraja", tag = "crea una {C:attention}%s{}",
    disable_boss = "desactiva la {C:attention}ciega jefe{}", destroy_joker = "destruye un {C:attention}comodín{} al azar", change_edition = "se convierte en {C:dark_edition}%s{}",
    ranks = {[14] = "As", [13] = "Rey", [12] = "Reina", [11] = "Jota"},
    kinds = {Tarot = "Tarot", Planet = "Planeta", Spectral = "Espectral"},
  },
}
T.S = S
T.W = W

local SUIT_COLOUR = {Hearts = "hearts", Diamonds = "diamonds", Spades = "spades", Clubs = "clubs"}
local KIND_COLOUR = {Tarot = "tarot", Planet = "planet", Spectral = "spectral"}
local EN_SUIT = {Hearts = "Heart", Diamonds = "Diamond", Spades = "Spade", Clubs = "Club"}
local EN_SUITS = {Hearts = "Hearts", Diamonds = "Diamonds", Spades = "Spades", Clubs = "Clubs"}
local SEAL_KEY = {Red = "red_seal", Blue = "blue_seal", Gold = "gold_seal", Purple = "purple_seal"}
local EN_SEAL = {Red = "Red Seal", Blue = "Blue Seal", Gold = "Gold Seal", Purple = "Purple Seal"}
local EN_ENH = {m_bonus = "Bonus Card", m_mult = "Mult Card", m_wild = "Wild Card", m_glass = "Glass Card", m_steel = "Steel Card", m_stone = "Stone Card", m_gold = "Gold Card", m_lucky = "Lucky Card"}
local EN_ED = {foil = "Foil", holo = "Holographic", polychrome = "Polychrome"}
local EN_BLIND = {Small = "Small Blind", Big = "Big Blind", Boss = "Boss Blind"}
local BLIND_KEY = {Small = "bl_small", Big = "bl_big"}

local function game_loc(fn, fallback)
  if type(localize) ~= "function" or not (G and G.localization) then return fallback end
  local ok, r = pcall(fn)
  if ok and type(r) == "string" and r ~= "" and r ~= "ERROR" then return r end
  return fallback
end

function T.suit_name(v, plural)
  return game_loc(function() return localize(v, plural and "suits_plural" or "suits_singular") end, (plural and EN_SUITS or EN_SUIT)[v] or tostring(v))
end

function T.hand_name(v)
  return game_loc(function() return localize(v, "poker_hands") end, tostring(v))
end

function T.enh_name(v)
  return game_loc(function() return localize{type = "name_text", set = "Enhanced", key = v} end, EN_ENH[v] or tostring(v))
end

function T.seal_name(v)
  return game_loc(function() return localize{type = "name_text", set = "Other", key = SEAL_KEY[v]} end, EN_SEAL[v] or tostring(v))
end

function T.tag_name(v)
  return game_loc(function() return localize{type = "name_text", set = "Tag", key = v} end, tostring(v):gsub("^tag_", ""):gsub("_", " "))
end

function T.edition_name(v)
  return game_loc(function() return localize{type = "name_text", set = "Edition", key = "e_" .. v} end, EN_ED[v] or tostring(v))
end

function T.blind_name(v)
  if not BLIND_KEY[v] then return EN_BLIND[v] or tostring(v) end
  return game_loc(function() return localize{type = "name_text", set = "Blind", key = BLIND_KEY[v]} end, EN_BLIND[v])
end

function T.rank_name(v, lang)
  local n = tonumber(v)
  if not n then return tostring(v) end
  return (S[lang] or S.en).ranks[n] or tostring(n)
end

local function fmt_n(n)
  n = tonumber(n) or 0
  if n ~= n then return "0" end
  if math.abs(n) >= 1e9 then
    local m, e = string.format("%.2e", n):match("^(.-)e([-+]%d+)$")
    if m then return (m:gsub("%.?0+$", "")) .. "e" .. tostring(tonumber(e)) end
  end
  if n == math.floor(n) then return string.format("%d", n) end
  return (string.format("%.2f", n):gsub("0+$", ""))
end
T.fmt_n = fmt_n

local function var_name(vars, i)
  local v = type(vars) == "table" and vars[i or 1]
  return v and v.name or "?"
end
T.var_name = var_name

function T.only_text(o, lang, vars)
  local s = S[lang] or S.en
  local id = o.id
  if id == "var" then return string.format(s.var, var_name(vars, o.var), s[o.op or "at_least"] or s.at_least, tonumber(o.n) or 0) end
  if id == "hand" then return string.format(o.mode == "is" and s.hand_is or s.hand_contains, T.hand_name(o.v)) end
  if id == "suit" then
    if o.v == "red" then return s.red end
    if o.v == "black" then return s.black end
    return string.format(s.suit, SUIT_COLOUR[o.v] or "attention", T.suit_name(o.v, lang == "es"))
  end
  if id == "rank" then
    if s[o.v] and type(o.v) == "string" then return s[o.v] end
    return string.format(s.rank, T.rank_name(o.v, lang))
  end
  if id == "enhancement" then return string.format(s.enhancement, T.enh_name(o.v)) end
  if id == "seal" then return string.format(s.seal, T.seal_name(o.v)) end
  if id == "edition" then return string.format(s.edition, T.edition_name(o.v)) end
  if id == "chance" then return string.format(s.chance, tonumber(o.n) or 4) end
  if id == "first_hand" or id == "last_hand" or id == "boss" then return s[id] end
  if id == "blind" then
    if o.v == "Boss" then return s.boss end
    return string.format(s.blind, T.blind_name(o.v))
  end
  if s[id] then return string.format(s[id], s[o.op or "at_least"] or s.at_least, tonumber(o.n) or 0) end
  return ""
end

function T.give_text(g, lang, vars)
  local s = S[lang] or S.en
  local id, n = g.id, fmt_n(g.n)
  if id == "var_add" then
    if (tonumber(g.n) or 0) < 0 then return string.format(s.var_sub, fmt_n(-g.n), var_name(vars, g.var)) end
    return string.format(s.var_add, n, var_name(vars, g.var))
  end
  if id == "var_set" then return string.format(s.var_set, var_name(vars, g.var), n) end
  if id == "var_chips" or id == "var_mult" then return string.format(s[id], n, var_name(vars, g.var)) end
  if id == "money" then return string.format(s.money_give, n) end
  if id == "retrigger" then return (tonumber(g.n) or 1) <= 1 and s.retrigger1 or string.format(s.retrigger, n) end
  if id == "create" then
    if g.v == "Joker" then return s.create_joker end
    return string.format(s.create, KIND_COLOUR[g.v] or "tarot", s.kinds[g.v] or s.kinds.Tarot)
  end
  if id == "change" then
    if g.what == "suit" then return string.format(s.change_suit, SUIT_COLOUR[g.v] or "attention", T.suit_name(g.v, true)) end
    if g.what == "rank" then return string.format(s.change_rank, T.rank_name(g.v, lang)) end
    if g.what == "seal" then return string.format(s.change_seal, T.seal_name(g.v)) end
    if g.what == "edition" then return string.format(s.change_edition, T.edition_name(g.v)) end
    return string.format(s.change_enh, T.enh_name(g.v))
  end
  if id == "level_up" or id == "destroy_self" or id == "destroy_card" or id == "copy_card" or id == "disable_boss" or id == "destroy_joker" then return s[id] end
  if id == "tag" then return string.format(s.tag, T.tag_name(g.v)) end
  if id == "add_card" then
    if g.v == "c_base" or not EN_ENH[g.v] then return s.add_card_any end
    return string.format(s.add_card, T.enh_name(g.v))
  end
  if id == "sell_value" then return string.format(s.sell_value, n) end
  if s[id] then return string.format(s[id], n) end
  return ""
end

function T.when_text(when, lang)
  return (W[lang] or W.en)[when] or ""
end

local function cap(str)
  local first = str:match("^({[^}]*})") or ""
  local rest = str:sub(#first + 1)
  return first .. rest:sub(1, 1):upper() .. rest:sub(2)
end

function T.sentence(rule, lang, vars)
  local s = S[lang] or S.en
  local out = T.when_text(rule.when, lang)
  local conds, nots, chance = {}, {}, nil
  for _, o in ipairs(rule.only or {}) do
    if o.id == "chance" then chance = T.only_text(o, lang, vars)
    elseif o.neg then nots[#nots + 1] = T.only_text(o, lang, vars)
    else conds[#conds + 1] = T.only_text(o, lang, vars) end
  end
  if #conds > 0 then out = out .. ", " .. s["if"] .. " " .. table.concat(conds, " " .. s["and"] .. " ") end
  if #nots > 0 then out = out .. ", " .. s.unless .. " " .. table.concat(nots, " " .. s["and"] .. " ") end
  if chance then out = out .. ", " .. chance end
  local gives = {}
  for _, g in ipairs(rule.give or {}) do gives[#gives + 1] = T.give_text(g, lang, vars) end
  if #gives == 0 then return nil end
  out = out .. ": " .. table.concat(gives, ", ")
  local alts = {}
  for _, g in ipairs(rule.alt or {}) do alts[#alts + 1] = T.give_text(g, lang, vars) end
  if #alts > 0 then out = out .. ", " .. s.otherwise .. " " .. table.concat(alts, ", ") end
  return out
end

local function visible_len(str)
  local plain = str:gsub("{[^}]*}", ""):gsub("[\128-\191]", "")
  return #plain
end
T.visible_len = visible_len

function T.wrap(str, width)
  width = width or T.WIDTH
  local buf, open = {}, false
  local i = 1
  while i <= #str do
    local ch = str:sub(i, i)
    if ch == "{" then
      local j = str:find("}", i, true) or #str
      local tag = str:sub(i, j)
      open = tag ~= "{}"
      buf[#buf + 1] = tag
      i = j + 1
    else
      buf[#buf + 1] = (ch == " " and open) and "\1" or ch
      i = i + 1
    end
  end
  local lines, line = {}, ""
  for word in table.concat(buf):gmatch("%S+") do
    local cand = line == "" and word or (line .. " " .. word)
    if line ~= "" and visible_len(cand) > width then
      lines[#lines + 1] = line
      line = word
    else
      line = cand
    end
  end
  if line ~= "" then lines[#lines + 1] = line end
  for k, l in ipairs(lines) do lines[k] = l:gsub("\1", " ") end
  return lines
end

function T.lines(c, lang)
  if type(c.text) == "table" and type(c.text[lang]) == "table" and #c.text[lang] > 0 then return c.text[lang] end
  local out = {}
  local gains = {}
  local room = false
  local used = {}
  for _, rule in ipairs(c.rules or {}) do
    local sen = T.sentence(rule, lang, c.vars)
    if sen then
      for _, l in ipairs(T.wrap(cap(sen))) do out[#out + 1] = l end
    end
    for _, g in ipairs(rule.give or {}) do
      if g.id == "gain_chips" or g.id == "gain_mult" or g.id == "gain_xmult" then gains[g.id] = true end
      if g.id == "create" then room = true end
      if g.var then used[g.var] = true end
    end
    for _, g in ipairs(rule.alt or {}) do if g.var then used[g.var] = true end end
    for _, o in ipairs(rule.only or {}) do if o.var then used[o.var] = true end end
  end
  local s = S[lang] or S.en
  local now = {}
  if gains.gain_chips then now[#now + 1] = s.now_chips end
  if gains.gain_mult then now[#now + 1] = s.now_mult end
  if gains.gain_xmult then now[#now + 1] = s.now_xmult end
  if #now > 0 then out[#out + 1] = string.format(s.now, table.concat(now, "{C:inactive}, ")) end
  local shown = {}
  for i, v in ipairs(type(c.vars) == "table" and c.vars or {}) do
    if used[i] and i <= 4 then shown[#shown + 1] = "{C:inactive}" .. v.name .. ":{} {C:attention}#" .. (4 + i) .. "#{}" end
  end
  if #shown > 0 then
    for _, l in ipairs(T.wrap("{C:inactive}({}" .. table.concat(shown, "{C:inactive},{} ") .. "{C:inactive}){}")) do out[#out + 1] = l end
  end
  if room then out[#out + 1] = s.room end
  return out
end

function T.vars(card, defs)
  local p = G and G.GAME and G.GAME.probabilities and G.GAME.probabilities.normal or 1
  local x = card and card.ability and type(card.ability.extra) == "table" and card.ability.extra or {}
  local out = {fmt_n(p), fmt_n(tonumber(x.chips) or 0), fmt_n(tonumber(x.mult) or 0), fmt_n(tonumber(x.xmult) or 1)}
  local cur = type(x.vars) == "table" and x.vars or {}
  for i = 1, 4 do
    local d = type(defs) == "table" and defs[i]
    out[4 + i] = fmt_n(tonumber(cur[i]) or (d and tonumber(d.start)) or 0)
  end
  return out
end

return T
