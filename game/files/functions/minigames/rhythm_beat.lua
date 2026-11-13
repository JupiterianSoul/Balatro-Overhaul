require("love.filesystem")
require("love.sound")
require("love.data")

local path, kind, out_name, cache_dir, algo = ...
local out = love.thread.getChannel(out_name)
local floor, max, min, exp, log, sqrt, pi = math.floor, math.max, math.min, math.exp, math.log, math.sqrt, math.pi

local function send(t) out:push(t) end

local function percentile_cuts(vals, cuts)
    local sorted = {}
    for i = 1, #vals do sorted[i] = vals[i] end
    table.sort(sorted)
    local out_cuts = {}
    for i, q in ipairs(cuts) do
        out_cuts[i] = sorted[max(1, min(#sorted, floor(q * #sorted + 0.5)))] or 0
    end
    return out_cuts
end

local function analyse(sd)
    local rate, chn, n = sd:getSampleRate(), sd:getChannelCount(), sd:getSampleCount()
    local ptr
    local okf, ffi = pcall(require, "ffi")
    if okf and sd.getFFIPointer and sd:getBitDepth() == 16 then
        local okp, p = pcall(function() return ffi.cast("int16_t*", sd:getFFIPointer()) end)
        if okp then ptr = p end
    end
    local H = floor(rate / 100)
    local fr = rate / H
    local frames = floor(n / H)
    if frames < fr * 8 then return nil, "short" end
    local a1 = 1 - exp(-2 * pi * 150 / rate)
    local a2 = 1 - exp(-2 * pi * 2500 / rate)
    local lp1, lp2 = 0, 0
    local A = {{}, {}, {}}
    local idx = 0
    for f = 1, frames do
        local el, em, eh = 0, 0, 0
        for _ = 1, H do
            local x
            if ptr then
                if chn == 2 then x = (ptr[idx * 2] + ptr[idx * 2 + 1]) * (0.5 / 32768) else x = ptr[idx * chn] / 32768 end
            elseif chn == 2 then
                x = (sd:getSample(idx, 1) + sd:getSample(idx, 2)) * 0.5
            else
                x = sd:getSample(idx, 1)
            end
            idx = idx + 1
            lp1 = lp1 + a1 * (x - lp1)
            lp2 = lp2 + a2 * (x - lp2)
            local m, h = lp2 - lp1, x - lp2
            el, em, eh = el + lp1 * lp1, em + m * m, eh + h * h
        end
        A[1][f], A[2][f], A[3][f] = sqrt(el / H), sqrt(em / H), sqrt(eh / H)
        if f % 3000 == 0 then send({p = 0.35 + 0.35 * f / frames}) end
    end
    local W = {1.0, 1.0, 0.8}
    local band_on = {{}, {}, {}}
    local o = {}
    for b = 1, 3 do
        local a, flux, sum = A[b], band_on[b], 0
        for f = 1, frames do
            local d = a[f] - (a[f - 2] or a[1])
            flux[f] = d > 0 and d or 0
            sum = sum + flux[f]
        end
        local mean = sum / frames
        if mean > 0 then
            for f = 1, frames do flux[f] = flux[f] / mean end
        end
    end
    for f = 1, frames do
        o[f] = W[1] * band_on[1][f] + W[2] * band_on[2][f] + W[3] * band_on[3][f]
    end
    local pre = {[0] = 0}
    for f = 1, frames do pre[f] = pre[f - 1] + o[f] end
    local R = 25
    local on = {}
    for f = 1, frames do
        local lo, hi = max(1, f - R), min(frames, f + R)
        local d = o[f] - (pre[hi] - pre[lo - 1]) / (hi - lo + 1)
        on[f] = d > 0 and d or 0
    end
    send({p = 0.75})
    local lo_lag, hi_lag = floor(fr * 60 / 200), floor(fr * 60 / 60 + 0.5)
    local function ac(L)
        local s = 0
        for f = 1, frames - L do s = s + on[f] * on[f + L] end
        return s / (frames - L)
    end
    local acs = {}
    for L = max(1, floor(lo_lag / 4)), min(hi_lag * 4, frames - 1) do acs[L] = ac(L) end
    local best_l, best_s = lo_lag, -1
    for L = lo_lag, hi_lag do
        local bpm = 60 * fr / L
        local z = log(bpm / 120) / log(2)
        local w = exp(-0.5 * (z / 0.8) ^ 2)
        local s = w * (acs[L] + (acs[2 * L] or 0) / 2 + (acs[4 * L] or 0) / 4 + (acs[floor(L / 2 + 0.5)] or 0) + (acs[floor(L / 4 + 0.5)] or 0) / 2)
        if s > best_s then best_s, best_l = s, L end
    end
    send({p = 0.8})
    local function peak(i)
        local a, b, c = on[i - 1] or 0, on[i] or 0, on[i + 1] or 0
        return max(a, b, c)
    end
    local best_p, best_ph, best_sc = best_l, 0, -1
    for step = -75, 75 do
        local P = best_l + step * 0.02
        for ph = 0, floor(P) do
            local s, t = 0, ph + 1
            while t <= frames do
                s = s + peak(floor(t + 0.5))
                t = t + P
            end
            if s > best_sc then best_sc, best_p, best_ph = s, P, ph end
        end
        if step % 25 == 0 then send({p = 0.8 + 0.15 * (step + 75) / 150}) end
    end
    local per = best_p / 4
    local slots = floor((frames - best_ph - 1) / per)
    local vals, lanes = {}, {}
    for k = 0, slots - 1 do
        local c = best_ph + 1 + k * per
        local a, b = floor(c - per * 0.35 + 0.5), floor(c + per * 0.35 + 0.5)
        local v, at = 0, floor(c + 0.5)
        for i = max(1, a), min(frames, b) do
            if on[i] > v then v, at = on[i], i end
        end
        v = v * ((k % 4 == 0) and 1.2 or (k % 2 == 0) and 1.05 or 0.9)
        vals[k + 1] = v
        local bl, bm, bh = band_on[1][at] or 0, band_on[2][at] or 0, band_on[3][at] or 0
        local band = (bl >= bm and bl >= bh) and 1 or (bm >= bh and 2 or 3)
        local alt = (floor(k / 2) + floor(k / 16)) % 2
        lanes[k + 1] = band - 1 + alt
    end
    local cuts = percentile_cuts(vals, {0.30, 0.42, 0.52, 0.61, 0.69, 0.77, 0.84, 0.91, 0.97})
    local s, l = {}, {}
    for k = 1, slots do
        local v, d = vals[k], 0
        if v > 0 then
            for i = 1, #cuts do
                if v >= cuts[i] then d = i end
            end
        end
        s[k] = tostring(d)
        l[k] = tostring(lanes[k])
    end
    return {
        bpm = 60 * fr / best_p,
        first = best_ph / fr,
        slots = slots,
        dur = n / rate,
        s = table.concat(s),
        l = table.concat(l),
    }
end

local ok, err = pcall(function()
    local raw = love.filesystem.read(path)
    if not raw then error("read " .. tostring(path)) end
    local sum = love.data.encode("string", "hex", love.data.hash("sha256", raw))
    local cache = cache_dir .. "/" .. sum .. "-" .. tostring(algo) .. ".lua"
    local cached = love.filesystem.read(cache)
    if cached then
        send({done = cached, sum = sum, cached = true})
        return
    end
    send({p = 0.05})
    local fd = love.filesystem.newFileData(raw, "song." .. tostring(kind or "ogg"))
    raw = nil
    local sd = love.sound.newSoundData(fd)
    fd:release()
    send({p = 0.35})
    local c, why = analyse(sd)
    sd:release()
    if not c then error(why) end
    local text = string.format("return {v = %d, bpm = %.5f, first = %.4f, slots = %d, dur = %.2f, s = %q, l = %q}\n",
        algo, c.bpm, c.first, c.slots, c.dur, c.s, c.l)
    love.filesystem.createDirectory(cache_dir)
    love.filesystem.write(cache, text)
    send({done = text, sum = sum})
end)
if not ok then send({err = tostring(err)}) end
