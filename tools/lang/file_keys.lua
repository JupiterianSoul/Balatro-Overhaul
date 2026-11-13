local root = arg[1] or "assets/localization"
local langs = {"fr", "es_ES", "es_419"}
local function load(p)
  local f = loadfile(p)
  if not f then return nil end
  return f()
end
local function walk(en, other, path, out)
  for k, v in pairs(en) do
    local p = path == "" and tostring(k) or (path .. "." .. tostring(k))
    local o = other and other[k]
    if type(v) == "table" and type(v[1]) == "string" and type(o) == "table" and #o > 0 then
    elseif o == nil then
      out.missing[#out.missing + 1] = p
    elseif type(v) == "table" and type(o) == "table" then
      walk(v, o, p, out)
    elseif type(v) == "string" and o == v and #v > 3 and v:match("%a%a%a") then
      out.same[#out.same + 1] = p .. "\t" .. v
    end
  end
end
local en = load(root .. "/en-us.lua")
local total = 0
for _, l in ipairs(langs) do
  local t = load(root .. "/" .. l .. ".lua")
  local out = {missing = {}, same = {}}
  walk(en, t, "", out)
  table.sort(out.missing)
  table.sort(out.same)
  print(("== %s/%s missing %d same %d"):format(root, l, #out.missing, #out.same))
  for _, m in ipairs(out.missing) do print("MISSING\t" .. l .. "\t" .. m) end
  if os.getenv("SHOW_SAME") then for _, m in ipairs(out.same) do print("SAME\t" .. l .. "\t" .. m) end end
  total = total + #out.missing
end
os.exit(total == 0 and 0 or 1)
