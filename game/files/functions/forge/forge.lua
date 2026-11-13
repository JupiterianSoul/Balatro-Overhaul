local Store = require("functions/forge/forge_store")
local FJ = require("functions/forge/forge_joker")
local UI = require("functions/forge/forge_ui")
local PXUI = require("functions/forge/forge_pixel_ui")
local BUI = require("functions/forge/forge_builder_ui")
local Text = require("functions/forge/forge_text")
local Kinds = require("functions/forge/forge_kinds")
local Mods = require("functions/forge/forge_mods")
local ModsUI = require("functions/forge/forge_mods_ui")
local Online = require("functions/forge/forge_online")
require("functions/forge/forge_room")

JokerForge = JokerForge or {}
pcall(Store.ensure_dirs)
JokerForge.store = Store
JokerForge.joker = FJ
JokerForge.ui = UI
JokerForge.pixel = PXUI
UI.tabs_extra.pixel = PXUI.footer
UI.tabs_extra.builder = BUI.footer
JokerForge.builder = BUI
JokerForge.kinds = Kinds
ForgeKinds = Kinds
JokerForge.mods = Mods
JokerForge.mods_ui = ModsUI
JokerForge.online = Online
ForgeMods = Mods
FJ.text_for = function(c, lang) return Text.lines(c, lang) end
FJ.vars_for = function(center, card)
  local c = center and center.forge_id and Store.get(center.forge_id)
  return Text.vars(card, c and c.vars)
end

function JokerForge.mods_tab() return ModsUI.tab() end
function JokerForge.tavern_button(o)
  o = o or {}
  return UIBox_button({label = {mod_loc("THE FORGE")}, button = "open_joker_forge", minw = o.minw or 5, minh = o.minh or 1, colour = G.C.RED})
end

local function register_strings()
  if not mod_loc_register then return end
  mod_loc_register{
    fr = {
      ["THE FORGE"] = "LA FORGE", ["Creations"] = "Créations", ["Nothing made yet"] = "Rien de créé pour l'instant", ["MAKE SOMETHING"] = "CRÉER", ["Everything"] = "Tout", ["DELETE IT?"] = "LE SUPPRIMER ?",
      ["Make jokers, tarots, decks, blinds and more,"] = "Créez des jokers, des tarots, des jeux, des blindes et plus,", ["with their own rules and art, and play them in your runs."] = "avec leurs règles et leur dessin, et jouez-les dans vos parties.",
      ["JOKER FORGE"] = "FORGE À JOKERS",
      ["Forge"] = "Forge",
      ["My jokers"] = "Mes jokers",
      ["Builder"] = "Créateur",
      ["Pixel editor"] = "Pixel art",
      ["Use in runs"] = "Dans les parties",
      ["Edit"] = "Modifier",
      ["Duplicate"] = "Dupliquer",
      ["Delete"] = "Supprimer",
      ["DELETE"] = "SUPPRIMER",
      ["DELETE THIS JOKER?"] = "SUPPRIMER CE JOKER ?",
      ["It leaves the collection and the shop for good."] = "Il quitte la collection et la boutique pour de bon.",
      ["No jokers yet"] = "Aucun joker pour l'instant",
      ["Build one with its own rules and art,"] = "Créez-en un avec ses règles et son dessin,",
      ["then find it in the shop of your next run."] = "puis trouvez-le dans la boutique de votre prochaine partie.",
      ["MAKE A JOKER"] = "CRÉER UN JOKER",
      ["NEW JOKER"] = "NOUVEAU JOKER",
      ["Rules, name, rarity and cost of a joker."] = "Règles, nom, rareté et prix d'un joker.",
      ["Draw or touch up a joker's art."] = "Dessinez ou retouchez le dessin d'un joker.",
      ["Build your own jokers, draw their art,"] = "Créez vos propres jokers, dessinez-les,",
      ["and play them in your runs."] = "et jouez-les dans vos parties.",
      ["1 joker"] = "1 joker",
      ["%d jokers"] = "%d jokers",
      ["copy"] = "copie",
      ["Does nothing yet"] = "Ne fait rien pour l'instant",
      ["Lost joker"] = "Joker perdu",
      ["This creation was deleted"] = "Cette création a été supprimée",
      ["Pencil"] = "Crayon",
      ["Eraser"] = "Gomme",
      ["Fill"] = "Remplir",
      ["Line"] = "Ligne",
      ["Box"] = "Cadre",
      ["Pick colour"] = "Pipette",
      ["Move"] = "Déplacer",
      ["Flip"] = "Retourner",
      ["Undo"] = "Annuler",
      ["Redo"] = "Rétablir",
      ["Mirror"] = "Miroir",
      ["Grid"] = "Grille",
      ["Any colour"] = "Autre couleur",
      ["ANY COLOUR"] = "AUTRE COULEUR",
      ["Red"] = "Rouge",
      ["Green"] = "Vert",
      ["Blue"] = "Bleu",
      ["USE IT"] = "VALIDER",
      ["START FROM"] = "PARTIR DE",
      ["BACK TO THE BUILDER"] = "RETOUR AU CRÉATEUR",
      ["Blank card"] = "Carte vierge",
      ["Empty"] = "Vide",
      ["Or a joker's art:"] = "Ou le dessin d'un joker :",
      ["New joker"] = "Nouveau joker", ["Lost card"] = "Carte perdue",
    },
    es = {
      ["THE FORGE"] = "LA FORJA", ["Creations"] = "Creaciones", ["Nothing made yet"] = "Aún no has creado nada", ["MAKE SOMETHING"] = "CREAR", ["Everything"] = "Todo", ["DELETE IT?"] = "¿BORRARLO?",
      ["Make jokers, tarots, decks, blinds and more,"] = "Crea jokers, tarots, barajas, ciegas y más,", ["with their own rules and art, and play them in your runs."] = "con sus reglas y su dibujo, y juégalos en tus partidas.",
      ["JOKER FORGE"] = "FORJA DE COMODINES",
      ["Forge"] = "Forja",
      ["My jokers"] = "Mis jokers",
      ["Builder"] = "Creador",
      ["Pixel editor"] = "Pixel art",
      ["Use in runs"] = "En las partidas",
      ["Edit"] = "Editar",
      ["Duplicate"] = "Duplicar",
      ["Delete"] = "Borrar",
      ["DELETE"] = "BORRAR",
      ["DELETE THIS JOKER?"] = "¿BORRAR ESTE COMODÍN?",
      ["It leaves the collection and the shop for good."] = "Sale de la colección y de la tienda para siempre.",
      ["No jokers yet"] = "Aún no hay jokers",
      ["Build one with its own rules and art,"] = "Crea uno con sus reglas y su dibujo,",
      ["then find it in the shop of your next run."] = "y encuéntralo en la tienda de tu próxima partida.",
      ["MAKE A JOKER"] = "CREAR UN COMODÍN",
      ["NEW JOKER"] = "NUEVO COMODÍN",
      ["Rules, name, rarity and cost of a joker."] = "Reglas, nombre, rareza y precio de un joker.",
      ["Draw or touch up a joker's art."] = "Dibuja o retoca el dibujo de un joker.",
      ["Build your own jokers, draw their art,"] = "Crea tus propios jokers, dibújalos",
      ["and play them in your runs."] = "y juégalos en tus partidas.",
      ["1 joker"] = "1 joker",
      ["%d jokers"] = "%d jokers",
      ["copy"] = "copia",
      ["Does nothing yet"] = "Aún no hace nada",
      ["Lost joker"] = "Comodín perdido",
      ["This creation was deleted"] = "Esta creación se borró",
      ["Pencil"] = "Lápiz",
      ["Eraser"] = "Goma",
      ["Fill"] = "Rellenar",
      ["Line"] = "Línea",
      ["Box"] = "Marco",
      ["Pick colour"] = "Cuentagotas",
      ["Move"] = "Mover",
      ["Flip"] = "Voltear",
      ["Undo"] = "Deshacer",
      ["Redo"] = "Rehacer",
      ["Mirror"] = "Espejo",
      ["Grid"] = "Cuadrícula",
      ["Any colour"] = "Otro color",
      ["ANY COLOUR"] = "OTRO COLOR",
      ["Red"] = "Rojo",
      ["Green"] = "Verde",
      ["Blue"] = "Azul",
      ["USE IT"] = "USARLO",
      ["START FROM"] = "EMPEZAR DESDE",
      ["BACK TO THE BUILDER"] = "VOLVER AL CREADOR",
      ["Blank card"] = "Carta en blanco",
      ["Empty"] = "Vacío",
      ["Or a joker's art:"] = "O el dibujo de un joker:",
      ["New joker"] = "Nuevo joker", ["Lost card"] = "Carta perdida",
    },
  }
end

register_strings()
pcall(Mods.load)
Mods.install_hooks()
FJ.install_hooks()
Kinds.install_hooks()

return JokerForge
