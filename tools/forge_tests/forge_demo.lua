local Store = JokerForge.store
local FJ = JokerForge.joker
Store.list = {}
Store.ensure_dirs()
local function crop(x, y)
    local src = love.image.newImageData("resources/textures/1x/Jokers.png")
    local out = love.image.newImageData(71, 95)
    out:paste(src, 0, 0, x * 71, y * 95, 71, 95)
    return out
end
local art = crop(9, 2)
love.filesystem.write("forge/art/demo2.png", art:encode("png"):getString())
local demo = {
    {id = "demo1", name = "Heart Thief", rarity = 1, cost = 5, art = {atlas = "Joker", x = 1, y = 1}},
    {id = "demo2", name = "Gold Tooth", rarity = 2, cost = 6, art = {file = "forge/art/demo2.png"}},
    {id = "demo3", name = "Night Owl", rarity = 3, cost = 8, enabled = false, art = {atlas = "Joker", x = 4, y = 4}},
    {id = "demo4", name = "Lucky Penny", rarity = 1, cost = 4, art = {atlas = "Joker", x = 6, y = 3}},
    {id = "demo5", name = "Big Wheel", rarity = 2, cost = 7, art = {atlas = "Joker", x = 3, y = 6}},
}
for i, c in ipairs(demo) do
    c.created = i
    if c.enabled == nil then c.enabled = true end
    Store.put(c)
end
FJ.register_all()
HLOG("forge_demo", #Store.all(), G.P_CENTERS.j_forge_demo2 and G.P_CENTERS.j_forge_demo2.atlas, #G.P_CENTER_POOLS.Joker)
