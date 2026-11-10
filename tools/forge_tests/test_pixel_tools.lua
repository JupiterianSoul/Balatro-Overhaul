local root = arg and arg[1] or "."
package.path = root .. "/assets/?.lua;" .. package.path
local P = require("functions/forge/forge_pixel")

local fails, count = 0, 0
local function check(name, ok)
    count = count + 1
    if not ok then fails = fails + 1; print("FAIL " .. name) end
end

local RED, BLUE, WHITE, BLACK = P.hex("fe5f55"), P.hex("009dff"), P.hex("ffffff"), P.hex("000000")
local function alpha(c) return select(4, P.unpack(c)) end
local function n_of(d, c)
    local n = 0
    for i = 1, #d.px do if d.px[i] == c then n = n + 1 end end
    return n
end

local d = P.new(10, 10)
check("one art layer", #d.layers == 1 and d.layers[1].role == "art" and d.px == d.layers[1].px)
check("brush 1 is one pixel", #P.brush_offsets(1) == 1)
check("brush 2 is a 2 by 2 block", #P.brush_offsets(2) == 4)
check("brush 3 is round", #P.brush_offsets(3) == 9 or #P.brush_offsets(3) == 5)
check("brush 5 is round, not square", #P.brush_offsets(5) < 25 and #P.brush_offsets(5) > 9)
P.stamp(d, 5, 5, RED, 2)
check("stamp size 2", P.get(d, 5, 5) == RED and P.get(d, 6, 6) == RED and P.get(d, 4, 4) == P.CLEAR)
P.stroke(d, 0, 0, 9, 0, BLUE, 1, "dither")
check("dither paints every other pixel", P.get(d, 0, 0) == BLUE and P.get(d, 1, 0) == P.CLEAR and P.get(d, 2, 0) == BLUE)

local s = P.new(4, 1)
P.clear(s, P.hex("808080"))
local seen = {}
P.stroke(s, 0, 0, 3, 0, nil, 1, "shade", seen)
P.stroke(s, 3, 0, 0, 0, nil, 1, "shade", seen)
local r = P.unpack(P.get(s, 0, 0))
check("shade darkens once per stroke", r < 128 and r > 80)
P.stroke(s, 0, 0, 0, 0, nil, 1, "light", {})
check("light brightens", P.unpack(P.get(s, 0, 0)) > r)
local e = P.new(3, 1)
P.stroke(e, 0, 0, 2, 0, nil, 1, "shade", {})
check("shade leaves empty pixels empty", alpha(P.get(e, 1, 0)) == 0)

local el = P.new(11, 7)
P.ellipse(el, 0, 0, 10, 6, WHITE)
check("ellipse touches its box sides", P.get(el, 0, 3) == WHITE and P.get(el, 10, 3) == WHITE and P.get(el, 5, 0) == WHITE and P.get(el, 5, 6) == WHITE)
check("ellipse is hollow and skips corners", P.get(el, 5, 3) == P.CLEAR and P.get(el, 0, 0) == P.CLEAR)
local disc = P.new(11, 7)
P.ellipse(disc, 0, 0, 10, 6, WHITE, true)
check("disc is filled", P.get(disc, 5, 3) == WHITE and P.get(disc, 0, 0) == P.CLEAR and n_of(disc, WHITE) > n_of(el, WHITE))

local t = P.new(6, 1)
P.clear(t, P.hex("101010"))
P.set(t, 3, 0, P.hex("181818"))
check("fill without tolerance stops at a near colour", P.fill(t, 0, 0, RED) == 3 and P.get(t, 4, 0) ~= RED)
P.clear(t, P.hex("101010"))
P.set(t, 3, 0, P.hex("181818"))
check("fill with tolerance goes through it", P.fill(t, 0, 0, RED, 10) == 6)
local ev = P.new(5, 1)
P.set(ev, 0, 0, BLUE); P.set(ev, 4, 0, BLUE); P.set(ev, 2, 0, WHITE)
check("fill every match", P.fill(ev, 0, 0, RED, 0, true) == 2 and P.get(ev, 4, 0) == RED and P.get(ev, 2, 0) == WHITE)

local g = P.new(11, 1)
check("gradient fills the area", P.gradient(g, 0, 0, 10, 0, BLACK, WHITE) == 11)
check("gradient goes from A to B", P.get(g, 0, 0) == BLACK and P.get(g, 10, 0) == WHITE and P.get(g, 5, 0) ~= BLACK and P.get(g, 5, 0) ~= WHITE)
local gd = P.new(16, 4)
P.gradient(gd, 0, 0, 15, 0, BLACK, WHITE, "dither")
local two = true
for i = 1, #gd.px do if gd.px[i] ~= BLACK and gd.px[i] ~= WHITE then two = false end end
check("dither gradient uses only A and B", two and n_of(gd, BLACK) > 16 and n_of(gd, WHITE) > 16)

local sel = P.new(10, 10)
P.select_rect(sel, 2, 2, 4, 4)
P.clear(sel, RED)
check("selection keeps a clear inside it", n_of(sel, RED) == 9 and P.get(sel, 1, 1) == P.CLEAR)
P.stamp(sel, 1, 2, BLUE, 3)
check("drawing stays inside the selection", P.get(sel, 0, 2) == P.CLEAR and P.get(sel, 2, 2) == BLUE)
P.select_rect(sel, 7, 7, 8, 8, "add")
check("add to the selection", sel.sel.x1 == 8 and sel.sel.mask[7 * 10 + 7 + 1] and sel.sel.mask[2 * 10 + 2 + 1])
P.select_rect(sel, 7, 7, 8, 8, "subtract")
check("subtract from the selection", not sel.sel.mask[7 * 10 + 7 + 1] and sel.sel.x1 == 4)
P.select_none(sel)
check("deselect", sel.sel == nil)
P.select_all(sel)
check("select all", sel.sel.x0 == 0 and sel.sel.y1 == 9)
P.select_none(sel)

local w = P.new(6, 1)
P.set(w, 0, 0, RED); P.set(w, 1, 0, RED); P.set(w, 3, 0, RED)
P.select_wand(w, 0, 0, 0)
check("wand picks the touching pixels of one colour", w.sel.x1 == 1 and not w.sel.mask[4])
P.select_wand(w, 0, 0, 0, true)
check("wand every match", w.sel.mask[4] and not w.sel.mask[3])

local l = P.new(10, 10)
P.select_lasso(l, {{1, 1}, {8, 1}, {8, 8}, {1, 8}})
check("lasso fills its shape", l.sel.mask[5 * 10 + 5 + 1] and l.sel.mask[1 * 10 + 1 + 1] and not l.sel.mask[0 * 10 + 0 + 1])
local tri = P.new(10, 10)
P.select_lasso(tri, {{0, 0}, {9, 0}, {0, 9}})
check("lasso triangle leaves the far corner", tri.sel.mask[1 * 10 + 1 + 1] and not tri.sel.mask[9 * 10 + 9 + 1])

local mv = P.new(6, 6)
P.set(mv, 1, 1, RED)
P.select_rect(mv, 0, 0, 2, 2)
P.move(mv, 3, 2)
check("move carries the selected pixels", P.get(mv, 1, 1) == P.CLEAR and P.get(mv, 4, 3) == RED)
check("move carries the selection", mv.sel.x0 == 3 and mv.sel.y0 == 2)
P.select_none(mv)
P.move(mv, -1, 0)
check("move without a selection moves the layer", P.get(mv, 3, 3) == RED and P.get(mv, 4, 3) == P.CLEAR)

local fl = P.new(4, 4)
P.set(fl, 0, 0, RED)
P.flip_v(fl)
check("flip up", P.get(fl, 0, 3) == RED and P.get(fl, 0, 0) == P.CLEAR)
local fs = P.new(6, 1)
P.set(fs, 0, 0, RED)
P.select_rect(fs, 0, 0, 2, 0)
P.flip(fs)
check("flip inside the selection", P.get(fs, 2, 0) == RED and P.get(fs, 5, 0) == P.CLEAR)

local ro = P.new(5, 5)
P.set(ro, 0, 0, RED)
P.rotate(ro)
check("rotate a quarter turn", P.get(ro, 4, 0) == RED and P.get(ro, 0, 0) == P.CLEAR)

local cp = P.new(6, 6)
P.set(cp, 1, 1, RED); P.set(cp, 2, 1, BLUE)
P.select_rect(cp, 1, 1, 2, 1)
local clip = P.copy(cp)
check("copy", clip.w == 2 and clip.h == 1 and clip.px[1] == RED and clip.px[2] == BLUE)
P.select_none(cp)
P.paste(cp, clip, 3, 4)
check("paste where asked and select it", P.get(cp, 3, 4) == RED and P.get(cp, 4, 4) == BLUE and cp.sel and cp.sel.x0 == 3)
P.select_rect(cp, 1, 1, 2, 1)
local cut = P.cut(cp)
check("cut", cut.px[1] == RED and P.get(cp, 1, 1) == P.CLEAR and P.get(cp, 3, 4) == RED)

local ol = P.new(5, 5)
P.set(ol, 2, 2, RED)
check("outline adds four pixels", P.outline(ol, BLACK) == 4 and P.get(ol, 2, 1) == BLACK and P.get(ol, 1, 1) == P.CLEAR and P.get(ol, 2, 2) == RED)

local ly = P.new(4, 4)
P.set(ly, 0, 0, RED)
check("add an art layer", P.add_layer(ly) and #ly.layers == 2 and ly.active == 2 and P.get(ly, 0, 0) == P.CLEAR)
P.set(ly, 0, 0, BLUE)
P.set(ly, 1, 0, BLUE)
check("add the soul layer on top", P.add_layer(ly, "soul") and ly.layers[3].role == "soul" and ly.active == 3)
check("only one soul layer", not P.add_layer(ly, "soul"))
check("a new art layer goes under the soul", P.add_layer(ly) and ly.layers[3].role == "art" and ly.layers[4].role == "soul")
check("art layers can not pass the soul", not P.move_layer(ly, 3, 1))
P.delete_layer(ly, 3)
ly.active = 3
P.relink(ly)
P.set(ly, 3, 3, WHITE)
local flat = P.flatten(ly, "art")
check("flatten stacks the art layers", flat[1] == BLUE and flat[2] == BLUE)
check("soul is kept apart", flat[3 * 4 + 3 + 1] == P.CLEAR and P.flatten(ly, "soul")[3 * 4 + 3 + 1] == WHITE)
ly.layers[2].visible = false
check("hidden layers are left out", P.flatten(ly, "art")[1] == RED)
ly.layers[2].visible = true
ly.active = 2
P.relink(ly)
check("merge down", P.merge_down(ly) and #ly.layers == 2 and ly.layers[1].px[1] == BLUE and ly.active == 1)
check("the last art layer stays", not P.delete_layer(ly, 1))

local u = P.new(4, 4)
P.begin(u); P.add_layer(u); P.set(u, 1, 1, RED); P.finish(u)
P.undo_step(u)
check("undo removes a new layer", #u.layers == 1 and P.get(u, 1, 1) == P.CLEAR and u.px == u.layers[1].px)
P.redo_step(u)
check("redo brings it back", #u.layers == 2 and P.get(u, 1, 1) == RED and u.px == u.layers[u.active].px)
P.begin(u)
u.layers[1].visible = false
check("hiding a layer is a step", P.finish(u))

local cols = P.new(3, 1)
P.set(cols, 0, 0, RED); P.set(cols, 1, 0, RED); P.set(cols, 2, 0, BLUE)
local list = P.colours(cols)
check("colours of the art, most used first", #list == 2 and list[1] == RED and list[2] == BLUE)

local src = {}
for i = 1, 142 * 190 do src[i] = RED end
local fit = P.fit(src, 142, 190, 71, 95)
check("fit a 2x picture exactly", fit.w == 71 and n_of(fit, RED) == 71 * 95)
local small = {BLUE, BLUE, BLUE, BLUE}
local sf = P.fit(small, 2, 2, 6, 6)
check("a small picture is centred at its size", n_of(sf, BLUE) == 4 and P.get(sf, 2, 2) == BLUE and P.get(sf, 0, 0) == P.CLEAR)
local snapped = P.fit({P.hex("fd5e56")}, 1, 1, 1, 1, P.palette_colours())
check("snap to the Balatro colours", snapped.px[1] == P.hex("fe5f55"))
local wide = {}
for i = 1, 300 * 100 do wide[i] = WHITE end
local wf = P.fit(wide, 300, 100, 71, 95)
check("a wide picture keeps its shape", P.get(wf, 0, 47) == WHITE and P.get(wf, 35, 5) == P.CLEAR)

local fd = P.flat_doc(ly)
check("flat doc is one layer", #fd.layers == 1 and fd.px[1] == BLUE)

print(string.format("%d checks, %d failed", count, fails))
os.exit(fails == 0 and 0 or 1)
