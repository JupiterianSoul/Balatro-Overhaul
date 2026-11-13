#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")/../menu_shots" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUTR="${SPM_OUT:-$ROOT/.night/sp_modes}"
mkdir -p "$OUTR"
INIT="wait:2|lua:G.PROFILES[G.SETTINGS.profile].name = 'Tester' G.SETTINGS.tutorial_complete = true G.SETTINGS.tutorial_progress = nil G.SETTINGS.sub_showcases_seen = setmetatable({}, {__index = function() return true end}) love.mouse.setPosition(4, 4)|close|wait:1"
BOTGO="lua:G.SETTINGS.GAMESPEED = 4 BOT.start({brain = 'rules', delay = 0.05}) BOT.on_run_end = function() BOT.stop() return true end"
SIG="local function sig(cards) local p = {} for _, c in ipairs(cards or {}) do p[#p + 1] = bom_replay.card_sig(c) end table.sort(p) return #p .. ':' .. bom_replay.hash(table.concat(p, ';')) end local g = G.GAME"
FINAL="$SIG HLOG('FINAL', LABEL, 'ante', g.round_resets.ante, 'round', g.round, 'dollars', g.dollars, 'chips', tostring(g.chips), 'best', tostring(g.round_scores and g.round_scores.hand and g.round_scores.hand.amt), 'jokers', sig(G.jokers and G.jokers.cards), 'deck', sig(G.playing_cards), 'cons', sig(G.consumeables and G.consumeables.cards), 'hands', bom_replay.hand_hash(g.hands), 'seed', g.pseudorandom.seed)"
CAP="${SPM_ANTE:-0}"
if [ "$CAP" -gt 0 ]; then
  OVER="until:not BOT.active or (G.GAME.round_resets.ante >= $CAP and G.STATE == G.STATES.SHOP and G.shop ~= nil)|until:not BOT.active or (G.GAME.round_resets.ante >= $CAP and G.STATE == G.STATES.SHOP and G.shop ~= nil)|until:not BOT.active or (G.GAME.round_resets.ante >= $CAP and G.STATE == G.STATES.SHOP and G.shop ~= nil)|until:not BOT.active or (G.GAME.round_resets.ante >= $CAP and G.STATE == G.STATES.SHOP and G.shop ~= nil)|lua:if BOT.active then BOT.stop() end|wait:4|lua:if G.STATE ~= G.STATES.GAME_OVER then BO_HISTORY.record(false, 'lose') end"
else
  OVER="until:not BOT.active|until:not BOT.active|until:not BOT.active|until:not BOT.active|until:not BOT.active|wait:4"
fi
START_solo="lua:G.FUNCS.start_run(nil, {stake = 1, back = G.P_CENTERS.b_red})"
START_seeded="lua:G.GAME.viewed_back = Back(G.P_CENTERS.b_blue) G.FUNCS.start_run(nil, {stake = 3, seed = '${SPM_SEED:-QAREPLAY}', back = G.P_CENTERS.b_blue})"
START_challenge="lua:local ch for _, c in ipairs(G.CHALLENGES) do if c.id == '${SPM_CH:-c_knife_1}' then ch = c end end G.FUNCS.start_run(nil, {stake = 1, challenge = ch})"
START_custom="lua:RunRules.start({${SPM_RULES:-dollars = 60, hands = 8, discards = 6, joker_slots = 7}}, {rules_source = 'custom', stake = 1, back = G.P_CENTERS.b_red})"
START_daily="lua:BO_DAILY.start()"
START_forge="lua:local S, FJ = JokerForge.store, JokerForge.joker S.put({id = 'qaheart', name = 'QA Heart', rarity = 1, cost = 4, art = {atlas = 'Joker', x = 0, y = 0}, rules = {{when = 'card_scored', only = {{id = 'suit', v = 'Hearts'}}, give = {{id = 'mult', n = 4}}}}}) S.put({id = 'qagold', name = 'QA Gold', rarity = 2, cost = 6, art = {atlas = 'Joker', x = 4, y = 4}, rules = {{when = 'round_end', give = {{id = 'money', n = 2}}}}}) FJ.register_all() RunRules.start({starting_jokers = {FJ.key_of('qaheart'), FJ.key_of('qagold')}, joker_slots = 7}, {rules_source = 'custom', stake = 1, back = G.P_CENTERS.b_red})"
WATCHED="until:bom_playback.state() and bom_playback.state().done"
IDLE="(function() for _, q in pairs(G.E_MANAGER.queues) do for _, ev in ipairs(q) do if ev.blocking and not ev.complete then return false end end end return true end)()"
WATCH="lua:BO_HISTORY.list = nil for _, e in ipairs(BO_HISTORY.load()) do if e.mode == MODE then HLOG('ROW', e.mode, e.result, 'sprp', tostring(e.sprp), 'watch', tostring(BO_HISTORY.can_watch(e))) BO_HISTORY.open_detail(e.id) break end end|wait:2|lua:G.FUNCS.bo_hist_watch(G.OVERLAY_MENU:get_UIE_by_ID('bo_hist_watch'))|until:bom_playback.active() and G.STAGE == G.STAGES.RUN and G.PB_BAR ~= nil|lua:HLOG('NOTE', tostring(bom_playback.state() and bom_playback.state().note))|wait:1|shot:play_start|lua:local S = bom_playback.state() S.ff_user, S.ff = true, true bom_playback.apply_speed()|$WATCHED|$WATCHED|$WATCHED|$WATCHED|$WATCHED|until:$IDLE|wait:2|lua:LABEL = 'play_' .. MODE $FINAL local s = bom_playback.state() HLOG('PLAYBACK', MODE, 'done', tostring(s.done), 'drifted', tostring(s.drifted), 'why', tostring(s.drift_why), 'info', tostring(s.drift_info), 'at', s.i, #s.entries, 'resyncs', tostring(s.resync_n or 0), 'first', tostring(s.first_diff))|shot:play_done|lua:G.FUNCS.pb_leave()|until:G.OVERLAY_MENU ~= nil and G.OVERLAY_MENU:get_UIE_by_ID('bo_hist_watch') ~= nil|wait:2|lua:HLOG('BACK', G.STAGE, tostring(G.OVERLAY_MENU ~= nil))|shot:back_detail"
fails=0
for m in ${SPM_MODES:-solo seeded challenge custom daily}; do
  data="$OUTR/data_$m"
  st="START_$m"
  if [ "${SPM_SKIP_REC:-0}" != 1 ]; then
  rm -rf "$data" "$HERE/out/spm_rec_${m}${SPM_TAG:-}" "$HERE/out/spm_play_${m}${SPM_TAG:-}"
  mkdir -p "$data"
  MENU_DATA="$data" SHOT_UNTIL=150 TMO=${SPM_TMO:-900} bash "$HERE/run.sh" "spm_rec_${m}${SPM_TAG:-}" plain "$INIT|${!st}|until:G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil|wait:1|lua:local t = {} for _, c in ipairs(G.jokers.cards) do t[#t + 1] = c.config.center.key end HLOG('JOKERS', table.concat(t, ' '))|$BOTGO|$OVER|lua:LABEL = 'record_$m' $FINAL|shot:rec_end|quit" | tail -2
  fi
  [ -n "${SPM_PRERUN:-}" ] && MENU_DATA="$data" SHOT_UNTIL=150 TMO=300 bash "$HERE/run.sh" "spm_pre_${m}${SPM_TAG:-}" plain "$INIT|$SPM_PRERUN|wait:1|quit" | tail -1
  rowmode=$m; [ "$m" = forge ] && rowmode=custom
  JK="lua:local t = {} for _, c in ipairs(G.jokers and G.jokers.cards or {}) do t[#t + 1] = c.config.center.key end HLOG('JOKERS', table.concat(t, ' '))"
  MENU_DATA="$data" SHOT_UNTIL=150 TMO=${SPM_TMO:-900} bash "$HERE/run.sh" "spm_play_${m}${SPM_TAG:-}" plain "$INIT${SPM_PREWATCH:+|$SPM_PREWATCH}|lua:MODE = '$rowmode'|$WATCH|$JK|quit" | tail -2
  r=$(grep -hE "^[0-9.]+ FINAL" "$HERE/out/spm_rec_${m}${SPM_TAG:-}/times.log" | sed 's/^[0-9.]* //; s/record_[a-z]*//')
  p=$(grep -hE "^[0-9.]+ FINAL" "$HERE/out/spm_play_${m}${SPM_TAG:-}/times.log" | sed 's/^[0-9.]* //; s/play_[a-z]*//')
  pb=$(grep -hE "^[0-9.]+ PLAYBACK" "$HERE/out/spm_play_${m}${SPM_TAG:-}/times.log" | sed 's/^[0-9.]* //')
  echo "REC  $m $r"
  echo "PLAY $m $p"
  echo "     $pb"
  if [ -n "$r" ] && [ "$r" = "$p" ] && echo "$pb" | grep -q "done true drifted nil"; then echo "PASS $m"; else echo "FAIL $m"; fails=$((fails + 1)); fi
done
[ "$fails" -eq 0 ]
