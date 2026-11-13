local L = dofile(arg[1] or "tools/release/launcher/lang.lua")
local bad = 0
for _, l in ipairs({"fr", "es"}) do
  for k, v in pairs(L.en) do
    if L[l][k] == nil then bad = bad + 1 print("MISSING\tlauncher\t" .. l .. "\t" .. k) end
    if type(v) == "string" and type(L[l][k]) == "string" then
      local a, b = select(2, v:gsub("%%[sd]", "")), select(2, L[l][k]:gsub("%%[sd]", ""))
      if a ~= b then bad = bad + 1 print("FORMAT\tlauncher\t" .. l .. "\t" .. k) end
    end
  end
end
print("== launcher missing or broken " .. bad)
os.exit(bad == 0 and 0 or 1)
