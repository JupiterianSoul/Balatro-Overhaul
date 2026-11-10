#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
MS="$REPO/tools/menu_shots"
export MENU_OUT="${MENU_OUT:-$REPO/.night/lang/shots}"
NAME="${LANG_NAME:-lang_sweep}"
LANGS="${LANGS:-en-us fr es_ES}"
N=$(luajit -e "dofile('$HERE/lang_sweep.lua') print(#LS.screens)")
SHOTS="${LANG_SHOTS:-}"
S="wait:2|lua:dofile('$MS/qa_ui_probe.lua') dofile('$HERE/lang_sweep.lua') G.PROFILES[G.SETTINGS.profile].name = 'Tester' G.SETTINGS.tutorial_complete = true G.SETTINGS.tutorial_progress = nil G.FUNCS.trigger_sub_showcase_settings = function() end G.FUNCS.trigger_sub_showcase_perf_settings = function() end G.FUNCS.trigger_sub_showcase_multiplayer = function() end G.SETTINGS.sub_showcases_seen = setmetatable({}, {__index = function() return true end})|close"
PORT=""
[ "${PORTRAIT:-0}" = 1 ] && PORT="|lua:local w, h = love.graphics.getDimensions() if w > h then love.window.updateMode(h, w, {fullscreen = false, resizable = true}) love.resize(love.graphics.getDimensions()) end|wait:1"
for L in $LANGS; do
  S="$S|lua:LS.set_lang('$L')|wait:2.5$PORT"
  for i in $(seq 1 "$N"); do
    S="$S|lua:LS.open($i)|wait:${SWEEP_WAIT:-0.8}"
    case " $SHOTS " in *" $i "*) S="$S|wait:0.6|shot:${L}_$i";; esac
    S="$S|lua:LS.scan($i)"
  done
  if [ "${LANG_RUN:-1}" = 1 ]; then
    S="$S|lua:QA.close_all() G.FUNCS.start_run(nil, {stake = 1, seed = 'LANGRUN'})|until:G.STATE == G.STATES.BLIND_SELECT and G.blind_select ~= nil|wait:1.5|lua:LS.scan_all('run_blind_select')"
    [ -n "$SHOTS" ] && S="$S|shot:${L}_run"
    S="$S|lua:G.FUNCS.options()|wait:0.8|lua:LS.scan('run_options')|lua:QA.close_all() G.FUNCS.overlay_menu{definition = create_UIBox_game_over(), config = {no_esc = true}}|wait:1|lua:QA.scan('run_game_over')"
    S="$S|lua:QA.close_all() G.FUNCS.overlay_menu{definition = create_UIBox_win(), config = {no_esc = true}}|wait:1|lua:QA.scan('run_win')|lua:QA.close_all() G.FUNCS.go_to_menu()|wait:3"
    S="$S|lua:dofile('$MS/mp2_screens_demo.lua') MP2.seed() MP2.lobby(nil)|wait:1.5|lua:LS.scan_all('mp_lobby')"
    [ -n "$SHOTS" ] && S="$S|shot:${L}_lobby"
    S="$S|lua:QA.close_all()"
  fi
done
S="$S|lua:QA.close_all()|quit"
rm -f "$MENU_OUT/$NAME/texts.tsv"
TMO="${TMO:-900}" bash "$MS/run.sh" "$NAME" plain "$S" 2>&1 | grep -E "exit|Oops" | head -5
grep -c "QAUI scan" "$MENU_OUT/$NAME/times.log"
grep -h "lua false\|QAUI open .*\(ERR\|MISSING\)" "$MENU_OUT/$NAME/times.log" | cut -c1-200 | head -20
