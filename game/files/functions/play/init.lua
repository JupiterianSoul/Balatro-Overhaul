Play = Play or {}
Play.MODULES = {"random_run", "speedrun", "speedrun_board", "speedrun_online", "run_origin", "play_menu"}

for _, name in ipairs(Play.MODULES) do
    local ok, err = pcall(require, "functions/play/" .. name)
    if not ok then print("[Play] load " .. name .. ": " .. tostring(err)) end
end

return Play
