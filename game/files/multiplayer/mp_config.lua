-- ============================================
-- ARCH: mp_config — Centralized configuration for all multiplayer modules.
-- All hardcoded values previously scattered across bom_* files
-- are collected here for visibility and tuning.
-- ============================================

local mp_config = {}

-- ============================================
-- NETWORK
-- ============================================
mp_config.SERVER_URL          = "wss://balatro-overhaul-muliplayer.onrender.com/ws"
mp_config.HEARTBEAT_INTERVAL  = 25     -- seconds between keepalive pings
mp_config.CONNECT_TIMEOUT     = 75     -- FIX: 75s to allow for Render free-tier cold start (~50-60s spin-up)
mp_config.RECONNECT_DELAY     = 3      -- seconds before reconnect attempt (unused currently)
mp_config.MAX_MSG_PER_FRAME   = 50     -- max WebSocket messages processed per update tick

-- ============================================
-- MATCH DEFAULTS
-- ============================================
mp_config.DEFAULT_STARTING_LIVES = 4   -- FIX: default 4 per spec (was 5)
mp_config.DEFAULT_MODE           = "attrition"
mp_config.DEFAULT_RULESET        = nil  -- FEATURE: no ruleset by default (vanilla)
mp_config.DEFAULT_ANTE_TIMER     = false
mp_config.DEFAULT_ANTE_TIMER_BASE = 120 -- seconds
mp_config.DEFAULT_STAKE          = 1    -- 1=White through 8=Gold
mp_config.DEFAULT_DECK           = "Red Deck"

-- FEATURE: Ported from BalatroMultiplayer v0.3.3 — extended match settings
mp_config.DEFAULT_PVP_START_ROUND      = 2    -- Ante at which PvP starts (attrition)
mp_config.DEFAULT_SHOWDOWN_START_ANTES = 3    -- Ante at which all blinds become PvP (showdown)
mp_config.DEFAULT_PVP_COUNTDOWN        = 3    -- Seconds countdown before PvP blind
mp_config.DEFAULT_TIMER_INCREMENT      = 0    -- Timer increment per ante
mp_config.DEFAULT_TIMER_FORGIVENESS    = 0    -- Timer forgiveness count

-- ============================================
-- SYNC
-- ============================================
mp_config.BOSS_SYNC_INTERVAL  = 1      -- PERF: 1s (was 2s) — faster real-time score sync during PvP

-- ============================================
-- UI — HUD
-- ============================================
mp_config.HUD_TEXT_SMALL      = 0.343  -- HUD small text scale
mp_config.HUD_TEXT_MEDIUM     = 0.406  -- HUD medium text scale
mp_config.HUD_TEXT_LABEL      = 0.312  -- HUD label text scale
mp_config.PVP_DISMISS_DELAY   = 3.0    -- seconds to auto-dismiss PvP result popup
mp_config.PVP_RESULT_HOLD     = 2.2
mp_config.PVP_RESULT_GAP      = 0.35
mp_config.STATUS_INDICATOR_X  = 18     -- online status X position (pixels)
mp_config.STATUS_INDICATOR_Y  = 18     -- online status Y position (pixels)

-- ============================================
-- LOGGING
-- ============================================
mp_config.LOG_LEVEL           = "INFO" -- DEBUG | INFO | WARN | ERROR

return mp_config
