-- ============================================
-- MULTIPLAYER REWARDS — Post-match XP, Balacoin, and achievement grants
-- ============================================

local bom_rewards = {}

-- ============================================
-- BALACOIN CALCULATION
-- Win: 50 + (ante-1)*15, capped at 200
-- Loss: flat 10
-- ============================================

function bom_rewards.calculate_bc(result, ante)
    if result ~= "win" then return 10 end
    ante = ante or 1
    return math.min(200, 50 + (ante - 1) * 15)
end

-- ============================================
-- XP CALCULATION
-- Win: 120 base
-- Loss: 40 base
-- ============================================

function bom_rewards.calculate_xp(result)
    if result == "win" then return 120 end
    return 40
end

-- ============================================
-- MATCH END — Called when a match concludes (win, lose, or opponent disconnect)
-- ============================================

local function mp_snapshot()
    local f = rawget(_G, "get_mp_progression_display")
    local d = type(f) == "function" and f() or nil
    if type(d) ~= "table" then return nil end
    return {level = tonumber(d.level) or 1, xp = tonumber(d.xp) or 0, need = tonumber(d.xp_needed) or 1, total = tonumber(d.total_xp) or 0}
end

function bom_rewards.on_match_end(data)
    if not G then return end
    if not G.GAME then return end
    if not data then data = {} end

    local result = data.result or "lose"
    local ante = 1
    pcall(function()
        if G.GAME.round_resets then
            ante = G.GAME.round_resets.ante or 1
        end
    end)

    pcall(function()
        if not (Overhaul and Overhaul.stats and Overhaul.stats.on) or G.GAME.modded_run then return end
        local st = bom_match and bom_match.get_state and bom_match.get_state() or {}
        local mc = rawget(_G, "bom_mode_content")
        Overhaul.stats.on("mp_match_end", {
            result = result, reason = data.reason, mode = mc and mc.mode and mc.mode() or st.mode,
            pvp_wins = data.pvp_wins or st.pvp_wins, pvp_losses = data.pvp_losses or st.pvp_losses,
            ante = ante, opp = st.opp_name, lives = st.my_lives,
        })
    end)

    local xp_amount = bom_rewards.calculate_xp(result)
    local bc_amount = bom_rewards.calculate_bc(result, ante)

    local before = mp_snapshot()
    -- Grant XP
    pcall(function()
        if mp_award_xp then
            mp_award_xp(xp_amount, "multiplayer_match")
        end
    end)

    -- Grant Balacoins
    local coins = 0
    pcall(function()
        if ShopManager and ShopManager.add_balacoin then
            ShopManager.add_balacoin(bc_amount)
            coins = bc_amount
        end
    end)
    pcall(function()
        local after = mp_snapshot()
        if before and after and bom_ranked and bom_ranked.session_progress then
            bom_ranked.session_progress({before = before, after = after, gain = math.max(0, after.total - before.total), coins = coins})
        end
    end)

    -- Quest progress
    pcall(function()
        if QuestManager and QuestManager.update_quest_progress then
            -- Track match played
            local quests = QuestManager.get_active_quests and QuestManager.get_active_quests() or {}
            for _, q in ipairs(quests) do
                if q and q.id == "mp_match_played" then
                    QuestManager.update_quest_progress(q, 1)
                end
                if result == "win" and q and q.id == "mp_match_won" then
                    QuestManager.update_quest_progress(q, 1)
                end
            end
        end
    end)

    -- Track MP stats for achievements
    if result == "win" then
        G.GAME.mp_match_wins = (G.GAME.mp_match_wins or 0) + 1

        -- Untouchable: won without losing a life
        if G.GAME.mp_won_without_life_loss then
            G.GAME.mp_untouchable_flag = true
        end

        -- Comeback Kid: won from 1 life remaining
        if G.GAME.mp_lives == 1 then
            G.GAME.mp_won_from_one_life = true
        end

        -- Persist win count in profile
        pcall(function()
            if mp_record_match then mp_record_match(true) end
            local profile = G.PROFILES[G.SETTINGS.profile]
            if profile and profile.progression then
                profile.progression.mp_match_wins = (profile.progression.mp_match_wins or 0) + 1
                profile.progression.mp_total_matches = (profile.progression.mp_total_matches or 0) + 1
            end
        end)
    else
        pcall(function()
            if mp_record_match then mp_record_match(false) end
            local profile = G.PROFILES[G.SETTINGS.profile]
            if profile and profile.progression then
                profile.progression.mp_total_matches = (profile.progression.mp_total_matches or 0) + 1
            end
        end)
    end

    -- Check achievements
    pcall(function()
        if AchievementManager and AchievementManager.check_all_achievements then
            AchievementManager.check_all_achievements()
        end
    end)

    -- Daily MP challenge completion
    pcall(function()
        if bom_daily and bom_daily.try_complete then
            bom_daily.try_complete(result)
        end
    end)

    -- REMOVED: show_match_results (MATCH RESULTS feature gutted)

    -- DO NOT clear multiplayer flag or disconnect here!
    -- The game over / win screen needs G.GAME.multiplayer to show Rematch button.
    -- The connection needs to stay alive for rematch voting.
    -- Cleanup happens when player explicitly returns to menu (mp_main_menu_from_screen).

    -- Save
    pcall(function()
        if G.save_progress then
            G:save_progress()
        end
    end)
end

-- ============================================
-- LOSE LIFE — Called when player fails a boss blind or loses a round
-- Now delegates to bom_match if available
-- ============================================

function bom_rewards.lose_life()
    if not G then return end
    if not G.GAME then return end
    if not G.GAME.multiplayer then return end

    -- FIX: Life management is now handled by "Lose a Life" button (bom_lose_life_button).
    -- This legacy function should NOT deduct lives — it would cause double-deduction.
    mp_log.info("BOM_REWARDS", "lose_life() called (legacy) — skipping, lives handled by button")
end

mp_log.info("BOM_REWARDS", "Multiplayer rewards module loaded")
return bom_rewards
