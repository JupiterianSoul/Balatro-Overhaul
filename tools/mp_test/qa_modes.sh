#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${QA_OUT:-$HERE/out/qa}"
PORT="${QA_PORT:-37781}"
JOBS="${QA_JOBS:-2}"
read -r -a PORTS <<< "${QA_PORTS:-}"
declare -A SCEN
SCEN[nemesis]="MP_TEST_MODE=nemesis"
SCEN[faceoff]="MP_TEST_MODE=faceoff MP_TEST_LIVES=2"
SCEN[ascension]="MP_TEST_MODE=ascension MP_TEST_LIVES=2"
SCEN[swap]="MP_TEST_MODE=swap MP_TEST_LIVES=6"
SCEN[swap_party]="MP_TEST_PARTY=br MP_TEST_PARTY_N=3 MP_TEST_PARTY_LIVES=6 MP_TEST_SETTINGS={\"party_swap\":true,\"different_seeds\":true}"
SCEN[ranked]="MP_TEST_FLOW=rankedq MP_TEST_RANKED_RP=1 MP_TEST_RANKED_LIVES=1 MP_TEST_RQ_ONE=1 MP_TEST_PVP_WEAK=guest"
SCEN[br]="MP_TEST_PARTY=br MP_TEST_PARTY_N=2 MP_TEST_PARTY_BOTS=2 MP_TEST_PARTY_LIVES=2 MP_TEST_HUD=1"
SCEN[teams]="MP_TEST_PARTY=teams MP_TEST_PARTY_N=2 MP_TEST_PARTY_BOTS=2 MP_TEST_PARTY_LIVES=2 MP_TEST_HUD=1"
SCEN[raid]="MP_TEST_PARTY=raid MP_TEST_PARTY_N=2 MP_TEST_PARTY_BOTS=2 MP_TEST_HUD=1"
SCEN[race]="MP_TEST_PARTY=race MP_TEST_PARTY_N=2 MP_TEST_PARTY_BOTS=2 MP_TEST_HUD=1"
SCEN[spectate]="MP_TEST_FLOW=spectate MP_TEST_PARTY=br MP_TEST_PARTY_N=3"
SCEN[emote]="MP_TEST_FLOW=emote MP_TEST_PARTY=teams MP_TEST_PARTY_N=2 MP_TEST_BOTS=6 MP_TEST_TURBO=0"
SCEN[leave]="MP_TEST_FLOW=leave"
SCEN[postleave]="MP_TEST_FLOW=postleave MP_TEST_LIVES=1 MP_TEST_PVP_WEAK=guest"
SCEN[postleave_replay]="MP_TEST_FLOW=postleave MP_TEST_LIVES=1 MP_TEST_PVP_WEAK=guest MP_TEST_POSTLEAVE_REPLAY=1"
ORDER=(nemesis faceoff ascension swap swap_party ranked br teams raid race spectate emote leave postleave)
[ $# -gt 0 ] && ORDER=("$@")
mkdir -p "$OUT"
: > "$OUT/summary.txt"

one() {
    local name=$1 port=$2 rc pass fail lua desync
    env ${SCEN[$name]} MP_TEST_PORT="$port" MP_TEST_SHOTS=1 MP_TEST_TIMEOUT="${QA_TIMEOUT:-900}" MP_TEST_OUT="$OUT/$name" \
        bash "$HERE/run.sh" > "$OUT/$name.log" 2>&1
    rc=$?
    pass=$(grep -c ' PASS ' "$OUT/$name.log")
    fail=$(grep -c ' FAIL ' "$OUT/$name.log")
    lua=$(sed -n '/^== LUA ERRORS ==/,/^== /p' "$OUT/$name/report.txt" 2>/dev/null | grep -c -v -E '^==|^none$|^$')
    desync=$(grep -m1 -o -E 'desyncs: [0-9]+' "$OUT/$name/report.txt" 2>/dev/null)
    rm -rf "$OUT/$name/stage"
    echo "$name rc=$rc pass=$pass fail=$fail lua_errors=$lua ${desync:-desyncs: ?}" >> "$OUT/summary.txt"
}

i=0
for name in "${ORDER[@]}"; do
    if [ -z "${SCEN[$name]:-}" ]; then echo "$name unknown" >> "$OUT/summary.txt"; continue; fi
    if [ ${#PORTS[@]} -gt 0 ]; then p=${PORTS[$((i % ${#PORTS[@]}))]}; else p=$((PORT + i % JOBS)); fi
    one "$name" "$p" &
    i=$((i + 1))
    if [ $((i % JOBS)) -eq 0 ]; then wait; else sleep 20; fi
done
wait
cat "$OUT/summary.txt"
