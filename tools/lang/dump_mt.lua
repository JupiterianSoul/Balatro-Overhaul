local f = assert(io.open("assets/functions/mod_localization.lua")):read("*a")
G = {SETTINGS = {language = "en-us"}}
assert(loadstring(f))()
local MT
for i = 1, 20 do local n, v = debug.getupvalue(mod_loc, i) if not n then break end if n == "MOD_TRANSLATIONS" then MT = v end end
local lang = arg[1] or "fr"
local keys = {}
for k in pairs(MT[lang]) do keys[#keys + 1] = k end
table.sort(keys)
for _, k in ipairs(keys) do
  local v = MT[lang][k]
  if type(v) == "string" then io.write((k:gsub("[\t\n]", " ")), "\t", (v:gsub("[\t\n]", " ")), "\n") end
end
