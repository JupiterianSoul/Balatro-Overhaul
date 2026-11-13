#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out_root="${REPLAY_CHECK_OUT:-$here/out_replay}"
case "$out_root" in /*) ;; *) out_root="$PWD/$out_root" ;; esac
mkdir -p "$out_root"

usage() {
    echo "Usage: tools/mp_test/replay_check.sh [scenario ...]"
    echo "Plays real driver matches with MP_TEST_FLOW=replay, then every human client watches its own replay to the end."
    echo "A scenario fails when a match does not finish, a replay cannot be fetched, or any playback drifts."
    echo "Scenarios: ${!SCEN[*]}"
    echo "In a scenario, ~ stands for a space inside one value."
    echo "Env: MP_TEST_PORT (37731) REPLAY_CHECK_OUT ($here/out_replay) REPLAY_CHECK_TIMEOUT (1500 s per match) REPLAY_CHECK_KEEP_STAGE (0 = the game copy of each match is deleted once it ends)"
}

declare -A SCEN
SCEN[nemesis]="MP_TEST_LIVES=3"
SCEN[traps]="MP_TEST_LIVES=6 MP_TEST_TRAPS=1 MP_TEST_TRAPS_SAFE=1 MP_TEST_SETTINGS={\"traps\":true}"
SCEN[nemesis_settings]="MP_TEST_LIVES=2 MP_TEST_SETTINGS={\"deck_draft\":true,\"stake\":3,\"timer\":true,\"timer_base_seconds\":90,\"traps\":true,\"pvp_win_money\":3,\"gold_on_life_loss\":true,\"multiplayer_jokers\":true}"
SCEN[faceoff]="MP_TEST_MODE=faceoff MP_TEST_LIVES=2"
SCEN[ascension]="MP_TEST_MODE=ascension MP_TEST_LIVES=2"
SCEN[swap]="MP_TEST_MODE=swap MP_TEST_LIVES=6"
SCEN[swap_bot]="MP_TEST_MODE=swap MP_TEST_LIVES=4 MP_TEST_VS_BOT=1 MP_TEST_BOT_PACE=0.2 MP_TEST_REPLAY_WAIT=900"
SCEN[swap_party]="MP_TEST_PARTY=br MP_TEST_PARTY_N=3 MP_TEST_PARTY_LIVES=4 MP_TEST_SETTINGS={\"party_swap\":true,\"different_seeds\":true}"
SCEN[raid]="MP_TEST_PARTY=raid MP_TEST_PARTY_N=2"
SCEN[teams_bots]="MP_TEST_PARTY=teams MP_TEST_PARTY_N=2 MP_TEST_BOTS=6 MP_TEST_PARTY_LIVES=2 MP_TEST_REPLAY_WAIT=900 MP_TEST_BOT_PACE=0.25"
SCEN[br_bots]="MP_TEST_PARTY=br MP_TEST_PARTY_N=2 MP_TEST_BOTS=2 MP_TEST_PARTY_LIVES=2 MP_TEST_REPLAY_WAIT=900 MP_TEST_BOT_PACE=0.25"
SCEN[ranked_bot]="MP_TEST_FLOW=ranked,replay"
SCEN[sockdrop]="MP_TEST_FLOW=sockdrop MP_TEST_REPLAY=1 MP_TEST_LIVES=2"
SCEN[restart]="MP_TEST_FLOW=restart MP_TEST_REPLAY=1 MP_TEST_LIVES=2"
SCEN[choices]="MP_TEST_LIVES=4 MP_TEST_SAME_PLAY=1 MP_TEST_LOSE_AT=1B MP_TEST_SETTINGS={\"balance_enabled\":false,\"traps\":true,\"custom_seed\":\"${REPLAY_CHECK_CHOICES_SEED:-RB004947}\",\"pvp_start_round\":2,\"deck\":\"Yellow~Deck\"}"
SCEN[pb_break]="MP_TEST_LIVES=2 MP_TEST_PB_BREAK=$here/../replay/pb_break.lua"
SCEN[random_deck]="MP_TEST_LIVES=2 MP_TEST_SETTINGS={\"deck\":\"Random~Deck\"}"
SCEN[lilac_deck]="MP_TEST_LIVES=2 MP_TEST_SETTINGS={\"deck\":\"Lilac~Deck\"}"
SCEN[seer_deck]="MP_TEST_LIVES=2 MP_TEST_SETTINGS={\"deck\":\"Seer~Deck\"}"
SCEN[tangerine_deck]="MP_TEST_LIVES=2 MP_TEST_SETTINGS={\"deck\":\"Tangerine~Deck\"}"
SCEN[cobalt_deck]="MP_TEST_LIVES=2 MP_TEST_SETTINGS={\"deck\":\"Cobalt~Deck\"}"
SCEN[gemini_deck]="MP_TEST_LIVES=2 MP_TEST_SETTINGS={\"deck\":\"Gemini~Deck\"}"
SCEN[mp_stake]="MP_TEST_LIVES=2 MP_TEST_SETTINGS={\"deck\":\"Cobalt~Deck\",\"mp_stake\":\"stake_mp_spectral_plus\"}"
SCEN[random_setting]="MP_TEST_LIVES=2 MP_TEST_SETTINGS={\"rules\":{\"number_randomizer\":true,\"random_chaos\":90}}"
ORDER=(nemesis nemesis_settings faceoff ascension swap swap_bot swap_party raid teams_bots br_bots ranked_bot sockdrop restart choices pb_break)
declare -A NEED
NEED[choices]="action:lose_on_purpose action:rich_skip_boss_tag action:rich_reroll_boss action:rich_trap replay:trap_set"
NEED[traps]="replay:trap_set replay:trap_fire"

case "${1:-}" in -h|--help) usage; exit 0 ;; esac
list=("$@")
[ ${#list[@]} -eq 0 ] && list=("${ORDER[@]}")

summary="$out_root/summary.txt"
: > "$summary"
fails=0
for name in "${list[@]}"; do
    spec="${SCEN[$name]:-}"
    if [ -z "$spec" ]; then echo "unknown scenario $name"; usage; exit 2; fi
    dir="$out_root/$name"
    echo "[replay_check] $name: $spec"
    envs=(MP_TEST_FLOW=replay MP_TEST_TIMEOUT="${REPLAY_CHECK_TIMEOUT:-1500}" MP_TEST_OUT="$dir")
    read -r -a parts <<< "$spec"
    for i in "${!parts[@]}"; do parts[$i]="${parts[$i]//\~/ }"; done
    envs+=("${parts[@]}")
    env "${envs[@]}" bash "$here/run.sh" > "$out_root/$name.log" 2>&1
    [ "${REPLAY_CHECK_KEEP_STAGE:-0}" = 1 ] || rm -rf "$dir/stage"
    rep="$dir/report.txt"
    plays=$(grep -cE "PASS replay_playback_" "$rep" 2>/dev/null)
    humans=2
    case "$spec" in *ranked*|*MP_TEST_VS_BOT=1*) humans=1 ;; *MP_TEST_PARTY_N=3*) humans=3 ;; esac
    bad=$(grep -E "FAIL (replay_|match_reached_end|party_played_blinds|.*_match_over|rejoin_ok|run_started|party_run_started)" "$rep" 2>/dev/null)
    for need in ${NEED[$name]:-}; do
        what="${need#*:}"
        case "$need" in
            action:*) grep -q "action $what " "$rep" 2>/dev/null || bad="$bad${bad:+ }not covered: $what" ;;
            replay:*) cat "$dir"/shared/replay_*.json 2>/dev/null | grep -q "\"$what\"" || bad="$bad${bad:+ }not covered: $what" ;;
        esac
    done
    if [ "${plays:-0}" -lt "$humans" ] || [ -n "$bad" ]; then
        fails=$((fails + 1))
        echo "FAIL $name (clean playbacks: ${plays:-0})" | tee -a "$summary"
        [ -n "$bad" ] && echo "$bad" | cut -c1-400 | tee -a "$summary"
    else
        echo "PASS $name (clean playbacks: $plays)" | tee -a "$summary"
        grep -E "PASS replay_playback_" "$rep" | cut -c1-200 >> "$summary"
    fi
done
echo "[replay_check] summary: $summary"
[ "$fails" -eq 0 ]
