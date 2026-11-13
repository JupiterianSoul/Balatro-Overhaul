#!/usr/bin/env bash
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
flow="${SW_FLOW:-1v1}"
work="${SW_OUT:-$here/out_switch/$flow}"
pa="${SW_PORT_A:-37741}"
pb="${SW_PORT_B:-37742}"
pp="${SW_PORT_PROXY:-37740}"
trigger="${SW_TRIGGER:-}"
after="${SW_AFTER:-}"
cap="${SW_TIMEOUT:-600}"
bun_cmd=(bun)
command -v bun >/dev/null || bun_cmd=(mise exec -- bun)

case "$flow" in
    1v1) : "${trigger:=Ante 2 S}" ;;
    bot) export MP_TEST_VS_BOT=1; : "${trigger:=Ante 2 S}" ;;
    party) export MP_TEST_PARTY="${MP_TEST_PARTY:-br}" MP_TEST_PARTY_N="${MP_TEST_PARTY_N:-3}"; : "${trigger:=Resolved [A-Z0-9]+ ante 1}" ;;
    pick) export MP_TEST_PICK_HOLD="${MP_TEST_PICK_HOLD:-12}" MP_TEST_SETTINGS="${MP_TEST_SETTINGS:-{\"joker_picks\":1\}}"; : "${trigger:=\[PICK\] [A-Z0-9]+ started}" ;;
    *) echo "SW_FLOW must be 1v1, bot, party or pick"; exit 1 ;;
esac

pids=()
cleanup() {
    trap - EXIT INT TERM
    [ -n "${run_pid:-}" ] && kill "$run_pid" 2>/dev/null
    for p in "${pids[@]}"; do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
    sleep 1
    for p in "${pids[@]}"; do pkill -9 -P "$p" 2>/dev/null; kill -9 "$p" 2>/dev/null; done
    pkill -f "love $work/run/stage/Overhaul" 2>/dev/null
    true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

for p in "$pa" "$pb" "$pp"; do
    (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null && { echo "port $p in use, set SW_PORT_A/B/PROXY"; exit 1; }
done

rm -rf "$work"
mkdir -p "$work"
db="$work/d1.sqlite"

start_server() {
    local name="$1" port="$2"
    (cd "$repo/server" && BOT_PACE="${MP_TEST_BOT_PACE:-1}" PORT="$port" LOG_LEVEL="${MP_TEST_SERVER_LOG:-INFO}" CF_D1_DATABASE_ID=local D1_LOCAL_FILE="$db" exec "${bun_cmd[@]}" run src/index.ts) > "$work/server_$name.log" 2>&1 &
    local pid=$!
    pids+=("$pid")
    printf -v "pid_$name" '%s' "$pid"
    for _ in $(seq 1 80); do
        grep -q "Balatro MP server on" "$work/server_$name.log" 2>/dev/null && return 0
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.5
    done
    echo "server $name failed to start"; tail -15 "$work/server_$name.log"; exit 1
}

start_server A "$pa"
start_server B "$pb"
echo "[switch] servers A:$pa (pid $pid_A) B:$pb (pid $pid_B), shared D1 $db"

SW_PORT="$pp" SW_A="ws://127.0.0.1:$pa" SW_B="ws://127.0.0.1:$pb" SW_LAG_MS="${SW_LAG_MS:-0}" "${bun_cmd[@]}" run "$here/switch_proxy.ts" > "$work/proxy.log" 2>&1 &
pids+=("$!")
for _ in $(seq 1 40); do grep -q "switch proxy on" "$work/proxy.log" 2>/dev/null && break; sleep 0.25; done
grep -q "switch proxy on" "$work/proxy.log" || { echo "proxy failed"; cat "$work/proxy.log"; exit 1; }

MP_TEST_EXTERNAL_SERVER=1 MP_TEST_PORT="$pa" MP_TEST_CLIENT_URL="ws://127.0.0.1:$pp/ws" MP_TEST_OUT="$work/run" \
    MP_TEST_TIMEOUT="$cap" bash "$here/run.sh" --no-rematch > "$work/run.log" 2>&1 &
run_pid=$!
echo "[switch] flow=$flow clients started, trigger regex: ${trigger:-none} fallback after ${after:-none}${after:+s}"

start=$(date +%s)
switched=0
while kill -0 "$run_pid" 2>/dev/null; do
    now=$(( $(date +%s) - start ))
    fire=0
    if [ -n "$trigger" ] && grep -Eq "$trigger" "$work/server_A.log" 2>/dev/null; then fire=1; why="log match"; fi
    if [ -n "$after" ] && [ "$now" -ge "$after" ]; then fire=1; why="after ${after}s"; fi
    if [ "$fire" = 1 ] && [ "$switched" = 0 ]; then
        sleep "${SW_SETTLE:-0}"
        echo "[switch] t=$(( $(date +%s) - start ))s trigger ($why): proxy -> B, then SIGTERM A"
        curl -s "http://127.0.0.1:$pp/switch?to=B" >/dev/null
        sleep 0.5
        kill -TERM "$pid_A" 2>/dev/null
        switched=1
        switched_s=$(date +%s)
        echo "$(date +%s.%N)" > "$work/switched_at"
    fi
    if [ "$switched" = 1 ] && [ -z "${doomed_at:-}" ] && grep -qh '"type":"rejoin_failed"' "$work"/run/shared/*_events.jsonl 2>/dev/null && ! grep -qh '"type":"rejoin_ok"' "$work"/run/shared/*_events.jsonl 2>/dev/null; then
        doomed_at=$(date +%s)
    fi
    if [ "$switched" = 1 ] && [ $(( $(date +%s) - switched_s )) -ge "${SW_POST:-90}" ]; then
        echo "[switch] no outcome ${SW_POST:-90}s after the switch, stopping clients"
        kill "$run_pid" 2>/dev/null
        break
    fi
    if [ -n "${doomed_at:-}" ] && [ $(( $(date +%s) - doomed_at )) -ge "${SW_GRACE:-10}" ]; then
        echo "[switch] rejoin_failed and no rejoin_ok for ${SW_GRACE:-10}s, stopping clients early"
        kill "$run_pid" 2>/dev/null
        break
    fi
    sleep 0.5
done
wait "$run_pid" 2>/dev/null
echo "[switch] run finished after $(( $(date +%s) - start )) s, switched=$switched"

fail=0
check() {
    if [ "$2" = 1 ]; then echo "[switch] PASS $1"; else echo "[switch] FAIL $1"; fail=1; fi
}
cl="$work/run"
nok=$(grep -h '"type":"rejoin_ok"' "$cl"/shared/*_events.jsonl 2>/dev/null | wc -l)
nlobby=$(grep -c 'back in moved lobby' "$work/server_B.log" 2>/dev/null)
nok=$(( nok + ${nlobby:-0} ))
nfail=$(grep -h '"type":"rejoin_failed"' "$cl"/shared/*_events.jsonl 2>/dev/null | wc -l)
nend=$(grep -h '"type":"match_ended"' "$cl"/shared/*_events.jsonl 2>/dev/null | wc -l)
nlost=$(grep -hc 'connection_lost\|room gone' "$cl"/*/stdout.log 2>/dev/null | paste -sd+ | python3 -c "print(eval(input() or 0))" 2>/dev/null)
echo "[switch] rejoin_ok=$nok rejoin_failed=$nfail match_ended=$nend lost_markers=${nlost:-0}"
grep -h '"type":"rejoin_ok"\|"type":"rejoin_failed"' "$cl"/shared/*_events.jsonl 2>/dev/null | head -2 | cut -c1-400
check "$flow switched" "$switched"
check "$flow rejoin_ok or lobby_rejoined from B (moved)" "$([ "$nok" -gt 0 ] && [ "$nfail" = 0 ] && echo 1 || echo 0)"
check "$flow match ended normally" "$([ "$nend" -gt 0 ] && echo 1 || echo 0)"
echo "[switch] $flow RESULT: $([ "$fail" = 0 ] && echo PASS || echo FAIL) (logs in $work)"
exit "$fail"
