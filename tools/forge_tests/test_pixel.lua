local root = arg and arg[1] or "."
package.path = root .. "/assets/?.lua;" .. package.path
local P = require("functions/forge/forge_pixel")

local fails, count = 0, 0
local function check(name, ok)
    count = count + 1
    if not ok then fails = fails + 1; print("FAIL " .. name) end
end

local RED, BLUE, WHITE = P.hex("fe5f55"), P.hex("009dff"), P.hex("ffffff")
local r, g, b, a = P.unpack(RED)
check("pack and unpack", r == 254 and g == 95 and b == 85 and a == 255)
check("hex round trip", P.to_hex(BLUE) == "009dff")
check("clear is transparent", select(4, P.unpack(P.CLEAR)) == 0)

local d = P.new()
check("joker size", d.w == 71 and d.h == 95 and #d.px == 71 * 95)
P.set(d, 3, 4, RED)
check("set and get", P.get(d, 3, 4) == RED and P.get(d, 4, 4) == P.CLEAR)
check("outside is nil", P.get(d, -1, 0) == nil and P.get(d, 71, 0) == nil)
P.set(d, 200, 200, RED)
check("set outside is ignored", #d.px == 71 * 95)

d.mirror = true
P.set(d, 0, 10, BLUE)
check("mirror sets both sides", P.get(d, 0, 10) == BLUE and P.get(d, 70, 10) == BLUE)
d.mirror = false

local pts = P.line_points(0, 0, 5, 2)
check("line starts and ends on its points", pts[1][1] == 0 and pts[1][2] == 0 and pts[#pts][1] == 5 and pts[#pts][2] == 2)
check("line has one point per column", #pts == 6)
local diag = P.line_points(2, 2, 2, 7)
check("vertical line", #diag == 6 and diag[6][1] == 2)

local e = P.new(10, 10)
P.rect(e, 1, 1, 8, 8, WHITE)
check("box outline", P.get(e, 1, 1) == WHITE and P.get(e, 8, 5) == WHITE and P.get(e, 4, 4) == P.CLEAR)
local n = P.fill(e, 4, 4, RED)
check("fill stays inside the box", n == 36 and P.get(e, 4, 4) == RED and P.get(e, 0, 0) == P.CLEAR and P.get(e, 1, 1) == WHITE)
check("fill same colour does nothing", P.fill(e, 4, 4, RED) == 0)
P.rect(e, 0, 0, 9, 9, BLUE, true)
check("filled box", P.get(e, 4, 4) == BLUE and P.get(e, 0, 9) == BLUE)

local m = P.new(10, 4)
P.line(m, 4, 0, 4, 3, WHITE)
m.mirror = true
local filled = P.fill(m, 0, 0, RED)
check("mirror fill fills both sides", filled == 36 and P.get(m, 0, 0) == RED and P.get(m, 9, 3) == RED and P.get(m, 4, 0) == WHITE)
m.mirror = false

local f = P.new(4, 1)
P.set(f, 0, 0, RED)
P.flip(f)
check("flip", P.get(f, 3, 0) == RED and P.get(f, 0, 0) == P.CLEAR)

local u = P.new(5, 5)
P.begin(u); P.set(u, 1, 1, RED); P.finish(u)
P.begin(u); P.set(u, 2, 2, BLUE); P.finish(u)
check("two undo steps", #u.undo == 2)
P.undo_step(u)
check("undo removes the last change", P.get(u, 2, 2) == P.CLEAR and P.get(u, 1, 1) == RED)
P.undo_step(u)
check("undo again", P.get(u, 1, 1) == P.CLEAR and not P.can_undo(u))
P.redo_step(u)
check("redo", P.get(u, 1, 1) == RED and P.can_redo(u))
P.redo_step(u)
check("redo again", P.get(u, 2, 2) == BLUE and not P.can_redo(u))
P.undo_step(u)
P.begin(u); P.set(u, 4, 4, WHITE); P.finish(u)
check("a new change clears redo", not P.can_redo(u) and P.get(u, 4, 4) == WHITE)
P.begin(u)
check("an empty stroke leaves no undo step", P.finish(u) == false and #u.undo == 2)
P.begin(u); P.set(u, 0, 0, RED); P.cancel(u)
check("cancel restores", P.get(u, 0, 0) == P.CLEAR)

local s = P.new(3, 2)
P.set(s, 0, 0, RED); P.set(s, 2, 1, BLUE)
local s2 = P.to_2x(s)
check("2x size", s2.w == 6 and s2.h == 4)
check("2x copies each pixel to a 2 by 2 block", P.get(s2, 0, 0) == RED and P.get(s2, 1, 1) == RED and P.get(s2, 2, 0) == P.CLEAR and P.get(s2, 4, 2) == BLUE and P.get(s2, 5, 3) == BLUE)
local big = P.to_2x(P.new())
check("joker 2x is 142 by 190", big.w == 142 and big.h == 190)

print(string.format("%d checks, %d failed", count, fails))
os.exit(fails == 0 and 0 or 1)
