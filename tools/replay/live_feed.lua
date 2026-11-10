local f = assert(io.open(LIVE_FILE, "r"))
local d = bom_core.json.decode(f:read("*a"))
f:close()
local B = tonumber(LIVE_BATCH) or 6
local pid = tonumber(LIVE_PID) or tonumber(d.you) or 0
local streams, seqs, queue = {}, {}, {}
for k, st in pairs(d.streams or {}) do
    local batches = {}
    for i = 1, #st, B do
        local b = {}
        for j = i, math.min(i + B - 1, #st) do b[#b + 1] = st[j] end
        batches[#batches + 1] = b
    end
    local first = math.min(tonumber(LIVE_FIRST) or 2, #batches)
    local init = {}
    for n = 1, first do
        for _, e in ipairs(batches[n]) do init[#init + 1] = e end
    end
    streams[k], seqs[k] = init, first
    for n = first + 1, #batches do queue[#queue + 1] = { pid = tonumber(k), seq = n, a = batches[n] } end
end
table.sort(queue, function(a, b)
    if a.seq ~= b.seq then return a.seq < b.seq end
    return a.pid < b.pid
end)
for i = 1, #queue - 1, 7 do queue[i], queue[i + 1] = queue[i + 1], queue[i] end
local out = {}
for i, q in ipairs(queue) do
    out[#out + 1] = q
    if i % 5 == 0 then out[#out + 1] = q end
end
LIVE = { q = out, i = 0, every = tonumber(LIVE_EVERY) or 0.4, next = love.timer.getTime() + (tonumber(LIVE_DELAY) or 0), ended = false, n = #out }
local PB = bom_playback
if not LIVE_WRAPPED then
    local up = PB.update
    PB.update = function(dt)
        local L = LIVE
        if L and not L.ended and PB.active() and love.timer.getTime() >= L.next then
            L.next = love.timer.getTime() + L.every
            L.i = L.i + 1
            local q = L.q[L.i]
            if q then
                PB.feed(q.pid, q.seq, q.a)
            elseif not LIVE_NO_END then
                L.ended = true
                PB.live_ended("over")
            end
        end
        return up(dt)
    end
    LIVE_WRAPPED = true
end
HLOG("LIVE_QUEUE", #out, "first", tostring(seqs["0"]), tostring(seqs["1"]), "pid", pid)
LIVE_OK = PB.start({ mode = "live", id = d.id, header = d.header or {}, streams = streams, seqs = seqs, pid = pid, see_jokers = true })
