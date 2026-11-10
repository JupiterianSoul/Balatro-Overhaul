BO_REPLAY_WIPE = BO_REPLAY_WIPE or {}
local W = BO_REPLAY_WIPE

W.EPOCH = "2026-11-07"
W.MARK = "replay_epoch.txt"
W.DIRS = {"sp_replays"}
W.FILES = {"mp_replay_seq.json"}

local function remove_tree(fs, path)
    local info = fs.getInfo(path)
    if not info then return 0 end
    local n = 0
    if info.type == "directory" then
        for _, item in ipairs(fs.getDirectoryItems(path) or {}) do n = n + remove_tree(fs, path .. "/" .. item) end
    else
        n = 1
    end
    fs.remove(path)
    return n
end

local function strip_history(fs)
    local H = rawget(_G, "BO_HISTORY")
    if not (H and H.FILE and H.parse and H.encode) then return 0 end
    local ok, data = pcall(fs.read, H.FILE)
    if not ok or type(data) ~= "string" then return 0 end
    local list = H.parse(data)
    local n = 0
    for _, e in ipairs(list or {}) do
        if e.replay then e.replay = nil; n = n + 1 end
    end
    if n > 0 then fs.write(H.FILE, H.encode(list)) end
    H.list = nil
    return n
end

local function strip_speedruns(fs)
    local n = 0
    for p = 1, 3 do
        local path = tostring(p) .. "/speedruns.jkr"
        if fs.getInfo(path) and get_compressed and compress_and_save then
            local ok, raw = pcall(get_compressed, path)
            local d = ok and raw and STR_UNPACK and STR_UNPACK(raw)
            if type(d) == "table" and type(d.sprps) == "table" and #d.sprps > 0 then
                d.sprps = {}
                pcall(compress_and_save, path, d)
                n = n + 1
            end
        end
    end
    return n
end

function W.run()
    local fs = love and love.filesystem
    if not (fs and fs.getInfo and fs.read and fs.write) then return false end
    local ok, mark = pcall(fs.read, W.MARK)
    if ok and type(mark) == "string" and mark:match("^%s*(.-)%s*$") == W.EPOCH then return false end
    local files = 0
    for _, d in ipairs(W.DIRS) do files = files + remove_tree(fs, d) end
    for _, f in ipairs(W.FILES) do files = files + remove_tree(fs, f) end
    local hist = select(2, pcall(strip_history, fs)) or 0
    local sr = select(2, pcall(strip_speedruns, fs)) or 0
    fs.write(W.MARK, W.EPOCH)
    print(string.format("[ReplayWipe] epoch %s: %d replay files removed, %s history links and %s speedrun lists cleared", W.EPOCH, files, tostring(hist), tostring(sr)))
    return true
end

pcall(W.run)

return W
