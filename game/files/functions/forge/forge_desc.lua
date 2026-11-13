local DE = {}

DE.COLOURS = {"mult", "chips", "money", "attention", "green", "purple", "tarot", "planet", "spectral", "enhanced", "legendary", "edition", "dark_edition", "hearts", "diamonds", "spades", "clubs", "inactive"}
DE.NAMES = {
  mult = "Mult", chips = "Chips", money = "Money", attention = "Attention", green = "Green", purple = "Purple", tarot = "Tarot", planet = "Planet",
  spectral = "Spectral", enhanced = "Enhanced", legendary = "Legendary", edition = "Edition", dark_edition = "Negative", hearts = "Hearts",
  diamonds = "Diamonds", spades = "Spades", clubs = "Clubs", inactive = "Grey", red = "Red", blue = "Blue", gold = "Gold", white = "White",
}

local function pieces(s)
  local lead = s:match("^[%(%[\"']+") or ""
  local rest = s:sub(#lead + 1)
  local trail = rest:match("[%.,:;!?%)%]\"']+$") or ""
  local core = rest:sub(1, #rest - #trail)
  local out = {}
  for _, p in ipairs({lead, core, trail}) do if p ~= "" then out[#out + 1] = p end end
  return out
end

function DE.parse(line)
  line = tostring(line or "")
  local words, simple = {}, true
  local cur, chars = nil, {}
  local function flush()
    if #chars == 0 then return end
    local s = {}
    for k, x in ipairs(chars) do s[k] = x[1] end
    local pos = 1
    for k, p in ipairs(pieces(table.concat(s))) do
      local c = chars[pos][2]
      for q = pos, pos + #p - 1 do if chars[q][2] ~= c then simple = false end end
      words[#words + 1] = {t = p, c = c, g = k > 1 or nil}
      pos = pos + #p
    end
    chars = {}
  end
  local i, n = 1, #line
  while i <= n do
    local ch = line:sub(i, i)
    local j = ch == "{" and line:find("}", i + 1, true)
    if j then
      local inner = line:sub(i + 1, j - 1)
      if inner == "" then
        cur = nil
      else
        local c = inner:match("^C:([%w_]+)$")
        if not c then simple = false; c = inner:match("C:([%w_]+)") end
        cur = c
      end
      i = j + 1
    elseif ch == " " then
      flush()
      i = i + 1
    else
      if ch == "{" or ch == "}" then simple = false else chars[#chars + 1] = {ch, cur} end
      i = i + 1
    end
  end
  flush()
  return words, simple
end

function DE.build(words)
  local out, cur = {}, nil
  for k, w in ipairs(words or {}) do
    local sp = k > 1 and not w.g
    if w.c ~= cur then
      if cur then out[#out + 1] = "{}" end
      if sp then out[#out + 1] = " " end
      if w.c then out[#out + 1] = "{C:" .. w.c .. "}" end
      cur = w.c
    elseif sp then
      out[#out + 1] = " "
    end
    out[#out + 1] = w.t
  end
  if cur then out[#out + 1] = "{}" end
  return table.concat(out)
end

function DE.plain(words)
  local out = {}
  for k, w in ipairs(words or {}) do
    if k > 1 and not w.g then out[#out + 1] = " " end
    out[#out + 1] = w.t
  end
  return table.concat(out)
end

function DE.split(text)
  local out = {}
  for t in tostring(text or ""):gsub("[{}]", ""):gmatch("%S+") do
    for k, p in ipairs(pieces(t)) do out[#out + 1] = {t = p, g = k > 1 or nil} end
  end
  return out
end

function DE.retext(words, text, brush)
  words = words or {}
  local new = DE.split(text)
  local n, m = #words, #new
  local L = {}
  for i = 0, n do L[i] = {}; for j = 0, m do L[i][j] = 0 end end
  for i = n - 1, 0, -1 do
    for j = m - 1, 0, -1 do
      if words[i + 1].t == new[j + 1].t then L[i][j] = L[i + 1][j + 1] + 1 else L[i][j] = math.max(L[i + 1][j], L[i][j + 1]) end
    end
  end
  local out, i, j = {}, 0, 0
  local gap_old, gap_new = {}, {}
  local function close_gap()
    for k, t in ipairs(gap_new) do
      local c = brush
      if c == nil and gap_old[k] then c = gap_old[k].c end
      out[#out + 1] = {t = t.t, c = c, g = t.g}
    end
    gap_old, gap_new = {}, {}
  end
  while i < n or j < m do
    if i < n and j < m and words[i + 1].t == new[j + 1].t then
      close_gap()
      out[#out + 1] = {t = new[j + 1].t, c = words[i + 1].c, g = new[j + 1].g}
      i, j = i + 1, j + 1
    elseif j < m and (i >= n or L[i][j + 1] >= L[i + 1][j]) then
      gap_new[#gap_new + 1] = new[j + 1]
      j = j + 1
    else
      gap_old[#gap_old + 1] = words[i + 1]
      i = i + 1
    end
  end
  close_gap()
  return out
end

function DE.paint(words, k, brush)
  local w = words and words[k]
  if not w then return end
  if w.c == brush then w.c = nil else w.c = brush end
end

return DE
