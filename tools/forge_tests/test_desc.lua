package.path = "assets/?.lua;" .. package.path
local DE = require("functions/forge/forge_desc")

local fails, total = 0, 0
local function check(name, ok, got)
  total = total + 1
  if not ok then fails = fails + 1; print("FAIL " .. name .. (got ~= nil and (" got: " .. tostring(got)) or "")) end
end
local function round_trip(line, want)
  local w, simple = DE.parse(line)
  local out = DE.build(w)
  check("round trip " .. line, out == (want or line), out)
  return w, simple
end

round_trip("When a card scores, if it is")
round_trip("a {C:hearts}Heart{}: {C:mult}+100{} Mult")
round_trip("{C:attention}5{} times")
round_trip("Aces give {C:chips}+20 Chips{} now")
round_trip(" retrigger the card", "retrigger the card")
round_trip("{C:mult}+4{}", "{C:mult}+4{}")
local _, s1 = DE.parse("a {C:hearts}Heart{}: {C:mult}+100{} Mult")
check("plain tags are simple", s1 == true)
local _, s2 = DE.parse("{X:mult,C:white}X3{} Mult")
check("background tag is not simple", s2 == false)
local w3 = DE.parse("{X:mult,C:white}X3{} Mult")
check("background keeps its text colour", w3[1].t == "X3" and w3[1].c == "white", w3[1].c)
local _, s4 = DE.parse("half{C:mult}way{}")
check("colour inside a word is not simple", s4 == false)

local w = DE.parse("Gives {C:mult}+4{} Mult")
DE.paint(w, 3, "mult")
check("paint a word", DE.build(w) == "Gives {C:mult}+4 Mult{}", DE.build(w))
DE.paint(w, 3, "mult")
check("paint again takes the colour off", DE.build(w) == "Gives {C:mult}+4{} Mult", DE.build(w))
DE.paint(w, 1, nil)
check("plain brush on a plain word does nothing", DE.build(w) == "Gives {C:mult}+4{} Mult", DE.build(w))
DE.paint(w, 2, nil)
check("plain brush clears", DE.build(w) == "Gives +4 Mult", DE.build(w))

w = DE.parse("Gives {C:mult}+4{} Mult")
w = DE.retext(w, "Gives +6 Mult", nil)
check("retyped word keeps its colour", DE.build(w) == "Gives {C:mult}+6{} Mult", DE.build(w))
w = DE.retext(w, "Gives +6 Mult to every card", nil)
check("new words with no brush are plain", DE.build(w) == "Gives {C:mult}+6{} Mult to every card", DE.build(w))
w = DE.retext(w, "Gives +6 Mult to every Heart card", "hearts")
check("new words take the brush", DE.build(w) == "Gives {C:mult}+6{} Mult to every {C:hearts}Heart{} card", DE.build(w))
w = DE.retext(w, "Mult to every Heart card", nil)
check("removed words go", DE.build(w) == "Mult to every {C:hearts}Heart{} card", DE.build(w))
w = DE.retext(w, "Mult {C:red}to{} every Heart card", nil)
check("typed braces are dropped", DE.build(w) == "Mult C:redto every {C:hearts}Heart{} card", DE.build(w))
w = DE.parse("a Heart: x")
DE.paint(w, 2, "hearts")
check("painting a word leaves its punctuation plain", DE.build(w) == "a {C:hearts}Heart{}: x", DE.build(w))
w = DE.retext(w, "a Heart, then x.", nil)
check("retyped punctuation keeps the word colour", DE.build(w) == "a {C:hearts}Heart{}, then x.", DE.build(w))
round_trip("(gives {C:money}$5{})")
w = DE.retext({}, "", "mult")
check("empty line", DE.build(w) == "", DE.build(w))
check("plain text", DE.plain(DE.parse("a {C:hearts}Heart{}: x")) == "a Heart: x")
for _, c in ipairs(DE.COLOURS) do check("name for " .. c, DE.NAMES[c] ~= nil) end

print(string.format("forge desc: %d checks, %d failed", total, fails))
os.exit(fails == 0 and 0 or 1)
