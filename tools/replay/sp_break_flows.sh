#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")/../menu_shots" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SRC="${SPB_SRC:-$ROOT/.night/sp_modes/data_custom}"
OUTR="${SPB_OUT:-$ROOT/.night/sp_break}"
mkdir -p "$OUTR"
INIT="wait:2|lua:G.PROFILES[G.SETTINGS.profile].name = 'Tester' G.SETTINGS.tutorial_complete = true G.SETTINGS.tutorial_progress = nil G.SETTINGS.sub_showcases_seen = setmetatable({}, {__index = function() return true end}) love.mouse.setPosition(4, 4)|close|wait:1|lua:CHK = function(name, cond, extra) HLOG('CHK', cond and 'PASS' or 'FAIL', name, tostring(extra)) end FLAGS = function() local u, d = 0, 0 for k, v in pairs(G.P_CENTERS) do if v.unlocked then u = u + 1 end if v.discovered then d = d + 1 end end return u .. '/' .. d .. '/' .. tostring(G.SETTINGS.tutorial_complete) end FLAGS0 = FLAGS() HLOG('FLAGS0', FLAGS0)"
ROW="lua:BO_HISTORY.list = nil ROWID = nil for _, e in ipairs(BO_HISTORY.load()) do if e.mode == '${SPB_MODE:-custom}' then ROWID = e.id SPRP = e.sprp break end end BO_HISTORY.open_detail(ROWID)|wait:1.5"
CLICK="lua:G.FUNCS.bo_hist_watch(G.OVERLAY_MENU:get_UIE_by_ID('bo_hist_watch'))"
INRUN="until:bom_playback.active() and G.STAGE == G.STAGES.RUN and G.PB_BAR ~= nil"
FF="lua:local S = bom_playback.state() S.ff_user, S.ff = true, true bom_playback.apply_speed()"
DONE="until:bom_playback.state() and bom_playback.state().done"
PBLOG="local s = bom_playback.state() or {} HLOG('PB', 'done', tostring(s.done), 'drifted', tostring(s.drifted), 'why', tostring(s.drift_why), 'info', tostring(s.drift_info), 'at', tostring(s.i), tostring(s.entries and #s.entries or s.n))"
CLEAN="lua:$PBLOG local s = bom_playback.state() or {} CHK(LABEL .. ' plays clean to the end', s.done and not s.drifted, s.drift_why)"
BACK="lua:G.FUNCS.pb_leave()|until:G.OVERLAY_MENU ~= nil and G.OVERLAY_MENU:get_UIE_by_ID('bo_hist_watch') ~= nil and not G.screenwipe|wait:1|lua:CHK(LABEL .. ' back on the detail, flags restored', FLAGS() == FLAGS0 and not bom_playback.active() and not (G.GAME and G.GAME.multiplayer), FLAGS())"
case "${1:-play}" in
play)
  rm -rf "$OUTR/data_play"; cp -r "$SRC" "$OUTR/data_play"
  STEPS="$INIT|lua:G.PROFILES[G.SETTINGS.profile].name = '${SPB_NAME:-Maximilienne-Éléonore de la Tour du Pin}'|$ROW|$CLICK|$INRUN|wait:1|shot:00_long_name|until:bom_playback.state().i >= 12|lua:G.FUNCS.run_info()|wait:12|lua:$PBLOG CHK('run info held 12 s, no drift', not bom_playback.state().done and G.OVERLAY_MENU ~= nil)|shot:01_run_info|close|wait:1|lua:G.FUNCS.deck_info()|wait:10|lua:CHK('deck view held 10 s, no drift', not bom_playback.state().done and G.OVERLAY_MENU ~= nil)|shot:02_deck_info|close|wait:1"
  STEPS="$STEPS|lua:for i = 1, 21 do G.FUNCS.pb_pause() G.FUNCS.pb_speed() G.FUNCS.pb_ff() end|wait:0.5|lua:for i = 1, 6 do G.FUNCS.pb_next_ante() end|wait:2|lua:G.FUNCS.pb_prev_ante() G.FUNCS.pb_prev_ante() G.FUNCS.pb_next_ante()|wait:3|lua:local S = bom_playback.state() HLOG('SPAM', 'paused', tostring(S.paused), 'speed', S.speed_i, 'ff', tostring(S.ff_user), 'ante', S.ante, 'i', S.i)|shot:03_after_spam"
  STEPS="$STEPS|lua:love.keypressed('escape')|wait:1|lua:CHK('escape opens nothing during a replay', G.OVERLAY_MENU == nil and bom_playback.active())|rotate|wait:2|shot:04_rotated|rotate|wait:2|shot:05_back_landscape|lua:local S = bom_playback.state() if S.paused then G.FUNCS.pb_pause() end|$FF|$DONE|$DONE|$DONE|$DONE|wait:2|lua:LABEL = 'first watch' $PBLOG|$CLEAN|shot:06_done|lua:LABEL = 'first watch'|$BACK"
  STEPS="$STEPS|$CLICK|$INRUN|$FF|until:bom_playback.state().i >= 25 and G.STATE == G.STATES.HAND_PLAYED|lua:HLOG('LEAVE_AT', G.STATE, bom_playback.state().i)|lua:LABEL = 'leave while scoring'|$BACK|$CLICK|$INRUN|$FF|$DONE|$DONE|$DONE|$DONE|wait:2|lua:LABEL = 'third watch'|$CLEAN|$BACK"
  STEPS="$STEPS|lua:G.FUNCS.exit_overlay_menu()|wait:1|lua:G.FUNCS.start_run(nil, {stake = 1, back = G.P_CENTERS.b_red})|until:G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil|wait:1|lua:CHK('new run after watching is recorded', G.GAME.bo_sprp ~= nil and bom_replay._rec.on and bom_replay._rec.local_only and not bom_playback.active() and not G.GAME.multiplayer, G.GAME.bo_sprp)|lua:CHK('new run after watching keeps the flags', FLAGS() == FLAGS0, FLAGS())|quit"
  MENU_DATA="$OUTR/data_play" SHOT_UNTIL=150 TMO=900 bash "$HERE/run.sh" spb_play plain "$STEPS" | tail -3
  grep -hE "^[0-9.]+ (CHK|PB|SPAM|LEAVE_AT|FLAGS0)" "$HERE/out/spb_play/times.log" ;;
files)
  rm -rf "$OUTR/data_files"; cp -r "$SRC" "$OUTR/data_files"
  P="BO_SPREPLAY.path(SPRP)"
  TRY() { echo "lua:love.filesystem.write($P, $1)|$ROW|lua:CHK('$2: no Watch button or no playback', true)|lua:if G.OVERLAY_MENU:get_UIE_by_ID('bo_hist_watch') then ${CLICK#lua:} end|wait:3|lua:CHK('$2 refused without a crash', not bom_playback.active() and G.STAGE == G.STAGES.MAIN_MENU)|lua:if bom_playback.active() then G.FUNCS.pb_leave() end|until:G.STAGE == G.STAGES.MAIN_MENU and not G.screenwipe|close|wait:0.5"; }
  STEPS="$INIT|$ROW|lua:ORIG = love.filesystem.read($P) HLOG('ORIG', #ORIG)|close"
  STEPS="$STEPS|$(TRY "ORIG:sub(1, math.floor(#ORIG / 2))" truncated)|$(TRY "''" empty)|$(TRY "'garbage {{{ not json'" garbage)|$(TRY "'{\"v\":1,\"entries\":[]}'" no_entries)|$(TRY "(ORIG:gsub('\"seed\":\"[^\"]*\"', '\"seed\":5', 1))" bad_seed)|$(TRY "string.rep('x', 2500000)" huge)"
  STEPS="$STEPS|lua:love.filesystem.write($P, (ORIG:gsub('\"v\":4', '\"v\":2', 1)))|$ROW|$CLICK|$INRUN|lua:CHK('older version replay starts', bom_playback.state().note == 'old', bom_playback.state().note)|$FF|$DONE|$DONE|$DONE|$DONE|wait:2|lua:LABEL = 'older version'|$CLEAN|shot:11_old_done|$BACK"
  STEPS="$STEPS|lua:love.filesystem.write($P, ORIG)|$ROW|$CLICK|$INRUN|until:bom_playback.state().i >= 10|lua:love.filesystem.remove($P)|$FF|$DONE|$DONE|$DONE|$DONE|wait:2|lua:LABEL = 'file deleted while playing'|$CLEAN|$BACK|lua:CHK('no Watch button once the file is gone', G.OVERLAY_MENU:get_UIE_by_ID('bo_hist_watch') == nil)|shot:12_detail_no_watch|close"
  STEPS="$STEPS|lua:love.filesystem.write($P, ORIG) for i = 1, 55 do love.filesystem.write(BO_SPREPLAY.DIR .. '/' .. (1700000000 + i) .. '-1-1.json', '{}') end BO_SPREPLAY.prune() local n, kept, oldest = 0, false, true for _, f in ipairs(love.filesystem.getDirectoryItems(BO_SPREPLAY.DIR)) do if f:match('%.json\$') then n = n + 1 end if f == SPRP .. '.json' then kept = true end if f == '1700000001-1-1.json' then oldest = false end end CHK('prune keeps 50 with the newest', n == 50 and kept and oldest, n)|quit"
  MENU_DATA="$OUTR/data_files" SHOT_UNTIL=150 TMO=900 bash "$HERE/run.sh" spb_files plain "$STEPS" | tail -3
  grep -hE "^[0-9.]+ (CHK|PB|ORIG)" "$HERE/out/spb_files/times.log" ;;
resume)
  D="$OUTR/data_resume"
  [ -n "${SPB_ONLY:-}" ] && [ "${SPB_ONLY%% *}" = 1 ] && { rm -rf "$D"; cp -r "$SRC" "$D"; }
  BOTGO="lua:G.SETTINGS.GAMESPEED = 4 BOT.start({brain = 'rules', delay = 0.05}) BOT.on_run_end = function() BOT.stop() return true end"
  SIG="local function sig(cards) local p = {} for _, c in ipairs(cards or {}) do p[#p + 1] = bom_replay.card_sig(c) end table.sort(p) return #p .. ':' .. bom_replay.hash(table.concat(p, ';')) end local g = G.GAME"
  FINAL="$SIG HLOG('FINAL', 'ante', g.round_resets.ante, 'round', g.round, 'dollars', g.dollars, 'chips', tostring(g.chips), 'jokers', sig(G.jokers and G.jokers.cards), 'deck', sig(G.playing_cards), 'hands', bom_replay.hand_hash(g.hands), 'seed', g.pseudorandom.seed)"
  LOADSAVE="lua:G.SAVED_GAME = get_compressed(G.SETTINGS.profile .. '/save.jkr') if G.SAVED_GAME then G.SAVED_GAME = STR_UNPACK(G.SAVED_GAME) end HLOG('SAVED', G.SAVED_GAME and G.SAVED_GAME.GAME.bo_sprp, G.SAVED_GAME and G.SAVED_GAME.GAME.bo_sprp_n, G.SAVED_GAME and G.SAVED_GAME.GAME.round)"
  CONT="$LOADSAVE|lua:G.FUNCS.start_run(nil, {savetext = G.SAVED_GAME})|until:G.STAGE == G.STAGES.RUN and G.STATE == G.STATES.SHOP and G.shop ~= nil|wait:2|lua:CHK('continue resumes the replay', G.GAME.bo_sprp ~= nil and bom_replay._rec.on and #bom_replay._rec.batch.buf == G.GAME.bo_sprp_n, tostring(G.GAME.bo_sprp_n) .. '/' .. tostring(bom_replay._rec.batch and #bom_replay._rec.batch.buf))"
  S1="$INIT|lua:G.GAME.viewed_back = Back(G.P_CENTERS.b_yellow) G.FUNCS.start_run(nil, {stake = 1, seed = 'QARESUME', back = G.P_CENTERS.b_yellow})|until:G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil|wait:1|$BOTGO|until:(G.GAME.round or 0) >= 2 and G.STATE == G.STATES.SHOP and G.shop ~= nil|lua:BOT.stop()|wait:3|lua:HLOG('FLAGS', FLAGS())|quit"
  S2="$INIT|lua:HLOG('FLAGS', FLAGS())|$ROW|$CLICK|$INRUN|until:bom_playback.state().i >= 20|lua:HLOG('QUIT_DURING_PLAYBACK', bom_playback.state().i)|quit"
  S3="$INIT|lua:HLOG('FLAGS', FLAGS())|lua:CHK('Continue still offered after quitting a replay', G.FILES[G.SETTINGS.profile .. '/save.jkr'] ~= nil)|$ROW|$CLICK|$INRUN|$FF|$DONE|$DONE|$DONE|$DONE|wait:2|lua:LABEL = 'watch before continue'|$CLEAN|$BACK|lua:CHK('the saved run is still there after watching a replay', get_compressed(G.SETTINGS.profile .. '/save.jkr') ~= nil and G.FILES[G.SETTINGS.profile .. '/save.jkr'] ~= nil)|close|wait:1|$CONT|$BOTGO|until:(G.GAME.round or 0) >= 4 and G.STATE == G.STATES.SHOP and G.shop ~= nil|lua:BOT.stop()|wait:3|lua:HLOG('FLAGS', FLAGS())|quit"
  S4="$INIT|$CONT|$BOTGO|until:not BOT.active|until:not BOT.active|until:not BOT.active|until:not BOT.active|wait:4|lua:LABEL = 'rec' $FINAL|quit"
  S5="$INIT|lua:BO_HISTORY.list = nil for _, e in ipairs(BO_HISTORY.load()) do if e.seed == 'QARESUME' then BO_HISTORY.open_detail(e.id) break end end|wait:1.5|$CLICK|$INRUN|$FF|$DONE|$DONE|$DONE|$DONE|wait:2|lua:LABEL = 'resumed run'|$CLEAN|until:G.STATE == G.STATES.GAME_OVER or G.STATE == G.STATES.SHOP|wait:3|lua:$FINAL|quit"
  n=0
  [ -n "${SPB_ONLY:-}" ] || { rm -rf "$D"; cp -r "$SRC" "$D"; }
  for st in "$S1" "$S2" "$S3" "$S4" "$S5"; do
    n=$((n + 1))
    case " ${SPB_ONLY:-1 2 3 4 5} " in *" $n "*) ;; *) continue ;; esac
    MENU_DATA="$D" SHOT_UNTIL=150 TMO=900 bash "$HERE/run.sh" "spb_resume$n" plain "$st" | tail -1
    grep -hE "^[0-9.]+ (CHK|PB|FLAGS|SAVED|FINAL|QUIT_DURING_PLAYBACK)" "$HERE/out/spb_resume$n/times.log" | sed "s/^/[$n] /"
  done ;;
live)
  rm -rf "$OUTR/data_live"; cp -r "$SRC" "$OUTR/data_live"
  LF="${SPB_LIVE_FILE:-$OUTR/live_replay.json}"
  START="lua:LIVE_FILE = '$LF' dofile('$ROOT/tools/replay/live_feed.lua') CHK('live playback starts', LIVE_OK)"
  STEPS="$INIT|lua:LIVE_EVERY = 1.2|$START|$INRUN|wait:2|shot:20_live_bar|lua:G.FUNCS.pb_switch()|wait:3|lua:local s = bom_playback.state() CHK('live switch to the other player', s.pid == 1 and not s.drifted, s.pid)|shot:21_live_switched|lua:G.FUNCS.pb_switch()|wait:3|lua:local s = bom_playback.state() CHK('live switch back', s.pid == 0 and not s.drifted, s.pid)"
  STEPS="$STEPS|lua:for i = 1, 9 do G.FUNCS.pb_pause() G.FUNCS.pb_speed() G.FUNCS.pb_ff() end|wait:1|lua:local S = bom_playback.state() if S.paused then G.FUNCS.pb_pause() end HLOG('LIVE_AT', S.i, #S.entries, LIVE.i, LIVE.n)|$DONE|$DONE|$DONE|$DONE|wait:2|lua:LABEL = 'live' $PBLOG HLOG('LIVE_FED', LIVE.i, LIVE.n, tostring(LIVE.ended))|$CLEAN|shot:22_live_done"
  STEPS="$STEPS|lua:G.FUNCS.pb_leave()|until:G.STAGE == G.STAGES.MAIN_MENU and not G.screenwipe|wait:2|lua:CHK('live leave goes back to the menu', not bom_playback.active() and G.PB_BAR == nil and not (G.GAME and G.GAME.multiplayer) and FLAGS() == FLAGS0, FLAGS())|close|wait:1"
  STEPS="$STEPS|lua:LIVE_FIRST = 0 LIVE_EVERY = 0.8 LIVE_DELAY = 4|$START|wait:2|lua:local s = bom_playback.state() CHK('live before the start waits with its text', s and s.waiting_start == true and G.PB_BAR ~= nil and s.ui.text == mod_loc('Waiting for the match to start...'), s and s.ui and s.ui.text)|lua:CHK('the menu still works while waiting', not bom_playback.blocks_button('options') and not bom_playback.filter_in({ type = 'friends_list' }))|shot:23_live_waiting|$INRUN|until:bom_playback.state().i >= 20|lua:CHK('live started from the first batch', not bom_playback.state().drifted)|lua:G.FUNCS.pb_leave()|until:G.STAGE == G.STAGES.MAIN_MENU and not G.screenwipe|wait:2|lua:CHK('live leave midway', not bom_playback.active() and G.PB_BAR == nil and not (G.GAME and G.GAME.multiplayer), LIVE.i)|wait:2|lua:CHK('feeds after leaving are ignored', not bom_playback.active())|close|wait:1|lua:LIVE_FIRST = 0 LIVE_DELAY = 600|$START|wait:2|lua:bom_playback.live_ended('over')|wait:1|lua:local s = bom_playback.state() or {} CHK('a match that ends before the start says so', s.done and not s.waiting_start and s.ui.text == mod_loc('The match is over'), s.ui and s.ui.text)|shot:24_live_over_waiting|lua:G.FUNCS.pb_leave()|until:G.STAGE == G.STAGES.MAIN_MENU and not G.screenwipe|wait:1|close|wait:1|$START|wait:2|lua:G.FUNCS.start_run(nil, {stake = 1, back = G.P_CENTERS.b_red})|until:G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil|wait:1|lua:CHK('a run started while waiting is a normal run', not bom_playback.active() and G.PB_BAR == nil and G.GAME.bo_sprp ~= nil and bom_replay._rec.on and type(save_run) == 'function' and FLAGS() == FLAGS0, G.GAME.bo_sprp)|wait:3|lua:CHK('the late start does not replace it', not bom_playback.active() and G.GAME.bo_sprp ~= nil)|quit"
  MENU_DATA="$OUTR/data_live" SHOT_UNTIL=150 TMO=900 bash "$HERE/run.sh" spb_live plain "$STEPS" | tail -3
  grep -hE "^[0-9.]+ (CHK|PB|LIVE_)" "$HERE/out/spb_live/times.log" ;;
input)
  rm -rf "$OUTR/data_input"; cp -r "$SRC" "$OUTR/data_input"
  LF="${SPB_LIVE_FILE:-$OUTR/live_replay.json}"
  PROBE() { echo "lua:IM.repause()|wait:2.5|lua:IM.mark()|$2|wait:0.8|lua:IM.after('$1')"; }
  PROBES=""
  for k in space return tab z x c s d a q w e r up down left right 1 2 3 4 5 backspace delete h p m f; do PROBES="$PROBES|$(PROBE "key $k" "lua:IM.keys({'$k'})")"; done
  for b in a b x y leftshoulder rightshoulder dpup dpdown dpleft dpright start back; do PROBES="$PROBES|$(PROBE "pad $b" "lua:IM.pad('$b', true)|wait:0.1|lua:IM.pad('$b', false)")"; done
  PROBES="$PROBES|$(PROBE "click card 1" "lua:IM.press(G.hand.cards[1])|wait:0.1|lua:IM.release()")|$(PROBE "click card 2" "lua:IM.press(G.hand.cards[2])|wait:0.1|lua:IM.release()")|$(PROBE "right click card 3" "lua:IM.press(G.hand.cards[3], 2)|wait:0.1|lua:IM.release()")"
  PROBES="$PROBES|$(PROBE "drag joker" "lua:IM.press(G.jokers.cards[1])|wait:0.1|lua:IM.at(G.jokers.cards[#G.jokers.cards])|wait:0.2|lua:IM.release(G.jokers.cards[#G.jokers.cards])")|$(PROBE "drag hand card" "lua:IM.press(G.hand.cards[1])|wait:0.1|lua:IM.at(G.hand.cards[#G.hand.cards])|wait:0.2|lua:IM.release(G.hand.cards[#G.hand.cards])")|$(PROBE "wheel" "lua:love.wheelmoved(0, -1) love.wheelmoved(0, 1)")"
  MIXK="lua:IM.keys({'space', 'return', 'tab', 'z', 'x', 'c', 's', 'd', 'a', 'q', 'w', 'e', 'up', 'down', 'left', 'right', '1', '2', '3', 'h', 'p', 'm'})|wait:1"
  MIXP=""
  for b in a b x y dpup dpdown dpleft dpright start back; do MIXP="$MIXP|lua:IM.pad('$b', true)|wait:0.1|lua:IM.pad('$b', false)|wait:0.2"; done
  MIXM="lua:IM.press(G.hand.cards[1])|wait:0.1|lua:IM.release()|wait:0.2|lua:IM.press(G.jokers.cards[1])|wait:0.1|lua:IM.at(G.jokers.cards[#G.jokers.cards])|wait:0.2|lua:IM.release(G.jokers.cards[#G.jokers.cards])|wait:0.3|lua:love.wheelmoved(0, -1)|wait:0.3"
  LANG() { echo "lua:G.SETTINGS.language = '$1' G:set_language() bom_playback.build_bar()|wait:1.5|shot:$2|lua:local ok, why = IM.overflow() CHK('$1 bar text fits its buttons', ok and IM.checked >= 8, why .. ' buttons=' .. IM.checked)"; }
  STEPS="$INIT${SPB_INPUT_MODE:+|lua:Controls.set_mode('$SPB_INPUT_MODE') HLOG('MODE', Controls.mode(), tostring(Controls.trackpad_on()))}|lua:dofile('$ROOT/tools/replay/input_mix.lua') CHK('mp replay starts', IM.start('$LF'))|$INRUN|until:bom_playback.state().i >= 14 and G.STATE == G.STATES.SELECTING_HAND and #G.hand.cards > 0|lua:HLOG('BAR', table.concat(IM.bar_buttons(), ' '))$PROBES"
  STEPS="$STEPS|lua:CHK('no key, pad button, click, drag or wheel changed a paused replay', IM.bad == 0 and IM.inert > 20, 'inert=' .. IM.inert .. ' shortcuts=' .. table.concat(IM.shortcuts, ','))"
  STEPS="$STEPS|lua:IM.repause()|wait:2|$(LANG fr 30_bar_fr)|$(LANG es 31_bar_es)|lua:G.SETTINGS.language = 'en-us' G:set_language() bom_playback.build_bar()|wait:1"
  STEPS="$STEPS|lua:love.window.updateMode(960, 540, {fullscreen = false, resizable = true}) love.resize(love.graphics.getDimensions())|wait:2|shot:32_resized|lua:local ok, why = IM.overflow() CHK('bar fits after a resize', ok and IM.checked >= 8, why)|lua:love.window.updateMode(1280, 720, {fullscreen = false, resizable = true}) love.resize(love.graphics.getDimensions())|wait:2|lua:IM.mark()|wait:0.5|lua:IM.after('resize')"
  STEPS="$STEPS|lua:IM.repause()|wait:1"
  for r in 1 2 3; do STEPS="$STEPS|$MIXK$MIXP|$MIXM|lua:local S = bom_playback.state() if S.paused then G.FUNCS.pb_pause() end HLOG('MIX', $r, S.i, #S.entries, tostring(S.drifted))|close|wait:1"; done
  STEPS="$STEPS|$FF|$DONE|$DONE|$DONE|$DONE|wait:2|lua:LABEL = 'mixed input' $PBLOG|$CLEAN|shot:33_done|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV', IM.pad_step('pb_leave'), tostring(IM.focused()))|wait:0.25|lua:IM.pad_after()|lua:HLOG('NAV_END', tostring(IM.focused()))|shot:34_pad_end|lua:IM.pad('b', true)|wait:0.1|lua:IM.pad('b', false)|until:G.STAGE == G.STAGES.MAIN_MENU and not G.screenwipe|wait:1|lua:CHK('B on the pad leaves a finished replay', not bom_playback.active() and FLAGS() == FLAGS0, FLAGS())|quit"
  MENU_DATA="$OUTR/data_input" SHOT_UNTIL=150 TMO=1200 bash "$HERE/run.sh" spb_input plain "$STEPS" | tail -3
  grep -hE "^[0-9.]+ (CHK|PB|BAR|SHORTCUT|PROBE_SKIP|NAV_END|MIX|MODE)" "$HERE/out/spb_input/times.log" ;;
mixiso)
  rm -rf "$OUTR/data_mixiso"; cp -r "$SRC" "$OUTR/data_mixiso"
  LF="${SPB_LIVE_FILE:-$OUTR/live_replay.json}"
  LOGS="lua:local S = bom_playback.state() or {} HLOG('ISO', ISO, S.i, #(S.entries or {}), tostring(S.drifted), tostring(S.drift_why), G.STATE, tostring(IM.focused()))"
  M1="lua:IM.press(G.hand.cards[1])|wait:0.1|lua:IM.release()|wait:0.3|lua:IM.press(G.hand.cards[2], 2)|wait:0.1|lua:IM.release()|wait:0.3|lua:IM.press(G.jokers.cards[1])|wait:0.1|lua:IM.at(G.jokers.cards[#G.jokers.cards])|wait:0.2|lua:IM.release(G.jokers.cards[#G.jokers.cards])|wait:0.3|lua:IM.press(G.hand.cards[1])|wait:0.1|lua:IM.at(G.hand.cards[#G.hand.cards])|wait:0.2|lua:IM.release(G.hand.cards[#G.hand.cards])|wait:0.3|lua:love.wheelmoved(0, -1)|wait:0.3|$LOGS"
  P1=""
  for b in a b dpup dpdown dpleft dpright a b start back a; do P1="$P1|lua:IM.pad('$b', true)|wait:0.1|lua:IM.pad('$b', false) ISO2 = (ISO2 or '') .. ' $b=' .. tostring(IM.focused())|wait:0.3"; done
  P1="${P1#|}|$LOGS|close"
  K1="lua:IM.keys({'tab', 'z', 'c', 's', 'a', 'q', 'w', 'e', 'up', 'down', '1', '2', '3', 'h', 'm', 'backspace'})|wait:1|$LOGS|close"
  STEPS="$INIT|lua:dofile('$ROOT/tools/replay/input_mix.lua') CHK('mp replay starts', IM.start('$LF'))|$INRUN|wait:2|lua:ISO = 'start'|$LOGS"
  for r in 1 2 3 4; do STEPS="$STEPS|lua:ISO = 'mouse$r'|$M1|wait:3"; done
  for r in 1 2 3 4; do STEPS="$STEPS|lua:ISO = 'pad$r' ISO2 = ''|$P1|lua:HLOG('PADFOCUS', ISO2)|wait:3"; done
  for r in 1 2 3 4; do STEPS="$STEPS|lua:ISO = 'keys$r'|$K1|wait:3"; done
  STEPS="$STEPS|$FF|$DONE|$DONE|$DONE|wait:2|lua:LABEL = 'isolated input' $PBLOG|$CLEAN|quit"
  MENU_DATA="$OUTR/data_mixiso" SHOT_UNTIL=150 TMO=1200 bash "$HERE/run.sh" spb_mixiso plain "$STEPS" | tail -3
  grep -hE "^[0-9.]+ (CHK|PB|ISO|PADFOCUS)" "$HERE/out/spb_mixiso/times.log" ;;
control)
  rm -rf "$OUTR/data_control"; cp -r "$SRC" "$OUTR/data_control"
  LF="${SPB_LIVE_FILE:-$OUTR/live_replay.json}"
  LOGS="lua:local S = bom_playback.state() or {} HLOG('ISO', ISO, S.i, #(S.entries or {}), tostring(S.drifted), tostring(S.drift_why), G.STATE, tostring(G.GAME.chips), tostring(G.GAME.current_round.hands_left))"
  STEPS="$INIT|lua:dofile('$ROOT/tools/replay/input_mix.lua') CHK('mp replay starts', IM.start('$LF'))|$INRUN|wait:2|lua:ISO = 'start'|$LOGS"
  for r in 1 2 3 4 5 6; do STEPS="$STEPS|wait:8|lua:ISO = 'idle$r'|$LOGS"; done
  STEPS="$STEPS|lua:LABEL = 'control' $PBLOG|quit"
  MENU_DATA="$OUTR/data_control" SHOT_UNTIL=150 TMO=600 bash "$HERE/run.sh" spb_control plain "$STEPS" | tail -1
  grep -hE "^[0-9.]+ (CHK|PB|ISO)" "$HERE/out/spb_control/times.log" ;;
online)
  rm -rf "$OUTR/data_online"; cp -r "$SRC" "$OUTR/data_online"
  FETCH="SpeedrunOnline.fetching = {id = FID, row = {name = 'Tester', cat = 'ante2'}, at = love.timer.getTime()}"
  REPLY() { echo "lua:FID = '$1' $FETCH bom_events.dispatch({type = 'speedrun_replay', id = '${2:-$1}', ok = $3, z = $4, n = $5, name = 'Racer'})|wait:2|lua:CHK('$6', not bom_playback.active() and G.STAGE == G.STAGES.MAIN_MENU and not love.filesystem.getInfo(BO_SPREPLAY.path('sro-$1')), tostring(SpeedrunOnline.fetching and SpeedrunOnline.fetching.id))|lua:SpeedrunOnline.fetching = nil|close|wait:0.5"; }
  STEPS="$INIT|$ROW|lua:B64, N = SpeedrunWatch.pack(SPRP) CHK('a recorded run packs like an upload', type(B64) == 'string' and N == #love.filesystem.read(BO_SPREPLAY.path(SPRP)), tostring(N))|close|wait:1"
  STEPS="$STEPS|$(REPLY bad01 bad01 true B64 'N + 1' 'a reply with the wrong size is refused')|$(REPLY bad02 bad02 true "'not base64 at all'" N 'a garbage reply is refused')|$(REPLY bad03 bad03 true "love.data.encode('string', 'base64', 'plain')" N 'a reply that is not zlib is refused')|$(REPLY bad04 bad04 false nil nil 'a replay that is not online says so')"
  STEPS="$STEPS|lua:FID = 'mine01' $FETCH bom_events.dispatch({type = 'speedrun_replay', id = 'other99', ok = true, z = B64, n = N})|wait:1.5|lua:CHK('a reply for another replay is ignored', not bom_playback.active() and SpeedrunOnline.fetching ~= nil and SpeedrunOnline.fetching.id == 'mine01')|lua:SpeedrunOnline.fetching = nil bom_events.dispatch({type = 'speedrun_replay', id = 'mine01', ok = true, z = B64, n = N})|wait:1.5|lua:CHK('a reply nobody asked for is ignored', not bom_playback.active())"
  STEPS="$STEPS|lua:FID = 'slow01' $FETCH SpeedrunOnline.fetching.at = love.timer.getTime() - 999 SpeedrunBoard.after_replay = {from = 'board'}|wait:1.5|lua:CHK('a fetch that never answers times out', SpeedrunOnline.fetching == nil and not bom_playback.active())|close|wait:1"
  STEPS="$STEPS|lua:FID = 'good01' $FETCH bom_events.dispatch({type = 'speedrun_replay', id = 'good01', ok = true, z = B64, n = N, name = 'Racer'})|$INRUN|wait:1|lua:CHK('the online replay is saved and plays', love.filesystem.getInfo(BO_SPREPLAY.path('sro-good01')) ~= nil and SpeedrunWatch.cur ~= nil)|shot:40_online_playing|$FF|$DONE|$DONE|$DONE|$DONE|wait:2|lua:LABEL = 'online speedrun replay'|$CLEAN|lua:G.FUNCS.pb_leave()|until:G.STAGE == G.STAGES.MAIN_MENU and not G.screenwipe|wait:2|lua:CHK('leave the online replay', not bom_playback.active() and FLAGS() == FLAGS0, FLAGS())"
  STEPS="$STEPS|lua:FID = 'good01' $FETCH bom_events.dispatch({type = 'speedrun_replay', id = 'good01', ok = true, z = B64, n = N, name = 'Racer'})|$INRUN|lua:CHK('the same online replay plays a second time', SpeedrunWatch.cur ~= nil)|lua:G.FUNCS.pb_leave()|until:G.STAGE == G.STAGES.MAIN_MENU and not G.screenwipe|wait:1|quit"
  MENU_DATA="$OUTR/data_online" SHOT_UNTIL=150 TMO=900 bash "$HERE/run.sh" spb_online plain "$STEPS" | tail -3
  grep -hE "^[0-9.]+ (CHK|PB)" "$HERE/out/spb_online/times.log" ;;
esac
