local function load(p) return assert(loadfile(p))() end
local en = load("assets/localization/en-us.lua")
local base = load("assets/localization/" .. (arg[1] or "de") .. ".lua")
local n = 0
local function walk(e, b, path)
  for k, v in pairs(e) do
    local p = path == "" and tostring(k) or (path .. "." .. tostring(k))
    if b == nil or b[k] == nil then
      n = n + 1
      print(p)
    elseif type(v) == "table" and type(b[k]) == "table" then
      walk(v, b[k], p)
    end
  end
end
walk(en, base, "")
io.stderr:write(n .. "\n")
