FINK = FINK or {maxdt = 0}
local STATE = os.getenv("FAKE_INKJOKER_STATE") or "/tmp/fake_inkjoker_state"

if not FINK.hooked then
  FINK.hooked = true
  local upd = love.update
  love.update = function(dt)
    if FINK.watch and dt > FINK.maxdt then FINK.maxdt = dt end
    return upd(dt)
  end
end

function FINK.mode(m)
  local f = io.open(STATE .. "/mode", "w")
  f:write(m)
  f:close()
end

function FINK.open()
  local B = ForgeBuilder
  if not B.state.draft then B.new_draft({kind = "joker"}) end
  JokerForge.ui.open("builder", "tavern")
  G.FUNCS.forge_b_generate()
end

function FINK.tabs(tag)
  local tabs = {}
  for _, t in ipairs(JokerForge.ui.tabs()) do tabs[#tabs + 1] = t.key end
  local px = ForgeInkUI.pixel_button(2.5, 0.6) ~= nil
  HLOG("fink", tag, "available", tostring(ForgeInk.available()), "engine", tostring(ForgeInk.engine), "tabs", table.concat(tabs, ","), "pixel_button", tostring(px), "ink_page", tostring(ForgeBuilder.state.ink))
end

function FINK.go(m, count)
  FINK.mode(m)
  ForgeInkUI.state.count = count or 2
  ForgeInkUI.state.phase = "idle"
  FINK.maxdt, FINK.watch = 0, true
  if not (UIK._win and UIK._win._cur == "builder" and ForgeBuilder.state.ink) then FINK.open() end
  G.FUNCS.forge_ink_generate()
end

function FINK.log(tag)
  local s = ForgeInkUI.state
  local f = io.open(STATE .. "/calls.log", "r")
  local calls = f and f:read("*a") or ""
  if f then f:close() end
  local last = ""
  for line in calls:gmatch("[^\n]+") do last = line end
  HLOG("fink", tag, "phase", s.phase, "job", s.job, "results", #s.results, "error", s.error, "maxdt", string.format("%.3f", FINK.maxdt), "last", last:sub(1, 160))
end

function FINK.check_args(kind, want_model)
  local f = io.open(STATE .. "/calls.log", "r")
  local last = ""
  if f then
    for line in f:read("*a"):gmatch("[^\n]+") do if line:sub(1, 9) == "generate " then last = line end end
    f:close()
  end
  local has_kind = last:find("--kind " .. kind, 1, true) ~= nil
  local has_model = last:find("--model", 1, true) ~= nil
  HLOG("fink_args", kind, "kind", tostring(has_kind), "model", tostring(has_model), (has_kind and has_model == want_model) and "OK" or "BAD")
end

function FINK.calls_with(word)
  local f = io.open(STATE .. "/calls.log", "r")
  local n = 0
  if f then
    for line in f:read("*a"):gmatch("[^\n]+") do if line:find(word, 1, true) then n = n + 1 end end
    f:close()
  end
  return n
end

function FINK.no_engine()
  ForgeInk.engine = false
  FINK.tabs("no_engine")
  ForgeInk.engine = true
end

function FINK.no_ink()
  ForgeInk.found = false
  local tabs = {}
  for _, t in ipairs(JokerForge.ui.tabs()) do tabs[#tabs + 1] = t.key end
  HLOG("fink", "no_ink", "available", ForgeInk.available(), "tabs", table.concat(tabs, ","))
end
