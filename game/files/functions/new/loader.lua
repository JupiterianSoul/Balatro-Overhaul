BO_NEW = BO_NEW or {}
BO_NEW.MODULES = {"run_history", "replay_wipe", "daily_board", "sp_replay", "showcase", "boss_practice"}

for _, name in ipairs(BO_NEW.MODULES) do
    local ok, err = pcall(require, "functions/new/" .. name)
    if not ok then print("[New] load " .. name .. ": " .. tostring(err)) end
end

return BO_NEW
