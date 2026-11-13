require("functions/shop/tavern_loc")
local C = require("functions/shop/tavern_catalog")
local S = require("functions/shop/tavern_store")
local A = require("functions/shop/tavern_apply")
local TC = require("functions/shop/tavern_cards")
local U = require("functions/shop/tavern_shop_ui")

Tavern = {catalog = C, store = S, apply = A, cards = TC, shop = U}
TavernApply = A

A.install_hooks()

if G and G.FUNCS then
  G.FUNCS.open_shop_menu_classic = G.FUNCS.open_shop_menu_classic or G.FUNCS.open_shop_menu
  G.FUNCS.open_shop_menu = function(e)
    return G.FUNCS.tavern_open_shop(e)
  end
end

Tavern.custom = require("functions/shop/tavern_custom_ui")
Tavern.random = require("functions/shop/tavern_random")

local function rewire(node)
  if type(node) ~= "table" then return end
  local cfg = node.config
  if cfg and cfg.button == "open_profile_menu" then
    cfg.button = "tavern_custom"
    for _, n in ipairs(node.nodes or {}) do
      for _, t in ipairs(n.nodes or {}) do
        if t.config and t.config.text then t.config.text = mod_loc("CUSTOMIZATION") end
      end
    end
  end
  for _, n in ipairs(node.nodes or {}) do rewire(n) end
end

if rawget(_G, "create_UIBox_tavern_hub") then
  local orig = create_UIBox_tavern_hub
  create_UIBox_tavern_hub = function(...)
    local def = orig(...)
    pcall(rewire, def)
    return def
  end
end

Tavern.town = require("functions/town/town")

return Tavern
