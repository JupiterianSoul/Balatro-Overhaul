local ACHIEVEMENT_ORDER = {
    'ante_up', 'ante_upper', 'heads_up', 'low_stakes', 'mid_stakes', 'high_stakes', 'card_player',
    'card_discarder', 'nest_egg', 'flushed', 'speedrunner', 'roi', 'shattered', 'royale', 'retrograde',
    '_10k', '_1000k', '_100000k', 'tiny_hands', 'big_hands', 'you_get_what_you_get', 'rule_bender',
    'rule_breaker', 'legendary', 'astronomy', 'cartomancy', 'clairvoyance', 'extreme_couponer',
    'completionist', 'completionist_plus', 'completionist_plus_plus',
}

local achievement_ids = {}
for i, name in ipairs(ACHIEVEMENT_ORDER) do
    achievement_ids[name] = tostring(i)
end

local Platform = {}

Platform.unlockAchievement = function(_, name)
    local id = achievement_ids[name]
    if not id then
        print("[ACHIEVEMENT] no platform id for " .. tostring(name))
        return
    end
    if love.platform and love.platform.unlockAchievement then
        love.platform.unlockAchievement(id)
    end
end

return Platform
