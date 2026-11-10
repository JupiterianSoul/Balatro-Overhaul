
local mp_config = {}

mp_config.SERVER_URL          = "wss://balatro-overhaul-muliplayer.onrender.com/ws"
mp_config.HEARTBEAT_INTERVAL  = 25
mp_config.CONNECT_TIMEOUT     = 75
mp_config.RECONNECT_DELAY     = 3
mp_config.MAX_MSG_PER_FRAME   = 50

mp_config.DEFAULT_STARTING_LIVES = 4
mp_config.DEFAULT_MODE           = "attrition"
mp_config.DEFAULT_RULESET        = nil
mp_config.DEFAULT_ANTE_TIMER     = false
mp_config.DEFAULT_ANTE_TIMER_BASE = 120
mp_config.DEFAULT_STAKE          = 1
mp_config.DEFAULT_DECK           = "Red Deck"

mp_config.DEFAULT_PVP_START_ROUND      = 2
mp_config.DEFAULT_SHOWDOWN_START_ANTES = 3
mp_config.DEFAULT_PVP_COUNTDOWN        = 3
mp_config.DEFAULT_TIMER_INCREMENT      = 0
mp_config.DEFAULT_TIMER_FORGIVENESS    = 0

mp_config.BOSS_SYNC_INTERVAL  = 1

mp_config.HUD_TEXT_SMALL      = 0.343
mp_config.HUD_TEXT_MEDIUM     = 0.406
mp_config.HUD_TEXT_LABEL      = 0.312
mp_config.PVP_DISMISS_DELAY   = 3.0
mp_config.PVP_RESULT_HOLD     = 2.2
mp_config.PVP_RESULT_GAP      = 0.35
mp_config.STATUS_INDICATOR_X  = 18
mp_config.STATUS_INDICATOR_Y  = 18

mp_config.LOG_LEVEL           = "INFO"

return mp_config
