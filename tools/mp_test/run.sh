#!/usr/bin/env bash
set -uo pipefail

usage() {
    echo "Usage: tools/mp_test/run.sh [--love path/to/Overhaul.love] [--no-rematch]"
    echo "Env: MP_TEST_PORT (37731) MP_TEST_TIMEOUT (1800 s) MP_TEST_SPEED (4) MP_TEST_SERVER_LOG (INFO)"
    echo "Reconnect flows: MP_TEST_FLOW (sockdrop|menu|restart|leave|expiry) MP_TEST_DROPPER (guest) MP_TEST_DROP_AT (shop|pvp) MP_TEST_HOLD (server hold seconds)"
    echo "     MP_TEST_TURBO (1, 0 = normal speed with drawing) TURBO_SPEED (64) TURBO_STEPS (16) TURBO_DT (0.0333)"
    echo "     MP_TEST_OUT (tools/mp_test/out) MP_TEST_MEM (2G) MP_TEST_SHOTS (1 = screenshots on stall and at the end)"
    echo "     MP_TEST_GAMESCOPE (1 = render screenshots on the GPU through headless gamescope)"
    echo "     MP_TEST_CPU_QUOTA (e.g. 100%, per client) MP_TEST_NICE (e.g. 19) MP_TEST_FLOW (settings,lobbyinfo,results,lifemoney)"
    echo "     MP_TEST_GUEST_SCREEN, MP_TEST_GUEST_PHONE (guest only, e.g. 720x1560 and 1 for a portrait phone), MP_TEST_GUEST_ROTATE (seconds between guest rotations)"
    echo "     MP_TEST_RULES (on|off: the lifemoney flow turns every life and money rule on or off and checks a forced round loss)"
    echo "     MP_TEST_MODS (comma list written to mods/enabled.txt, Steamodded = fork alone via MODLOADER_FORK)"
    echo "     MP_TEST_MODS_HOST / MP_TEST_MODS_GUEST (per client, override MP_TEST_MODS; empty = no mods)"
    echo "     MP_TEST_FORGE (1 = host and guest get different Forge creations; add MP_TEST_SETTINGS={\"forge_room_on\":true} for the Forge room)"
    echo "     MP_TEST_SERVER_DIR (another server/ folder, e.g. the live server's code) MP_TEST_CLIENT_URL (clients connect here instead, e.g. wss:// through a TLS front)"
    echo "     MP_TEST_DUMMY_MOD (1 or a role list: installs and enables an empty mod MpTestDummy without starting modded)"
}

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
out="${MP_TEST_OUT:-$here/out}"
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac
turbo="${MP_TEST_TURBO:-1}"
[ -n "${MP_TEST_KEYS:-}${MP_TEST_TPAD:-}${MP_TEST_PAD:-}" ] && export TURBO_DRAW_EVERY="${TURBO_DRAW_EVERY:-0.05}"
mem="${MP_TEST_MEM:-2G}"
shots="${MP_TEST_SHOTS:-0}"
use_gs="${MP_TEST_GAMESCOPE:-0}"
love_file="${MP_TEST_LOVE:-}"
rematch=1

while [ $# -gt 0 ]; do
    case "$1" in
        --love) love_file="$2"; shift 2 ;;
        --no-rematch) rematch=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done

port="${MP_TEST_PORT:-37731}"
speed="${MP_TEST_SPEED:-4}"
tag="mptest$$"
[ "$turbo" = 1 ] || turbo=0
if [ -n "${MP_TEST_TIMEOUT:-}" ]; then
    timeout_s="$MP_TEST_TIMEOUT"
elif [ "$turbo" = 1 ]; then
    timeout_s=90
else
    timeout_s=720
fi
deadline_s=$(( timeout_s > 300 ? timeout_s - 60 : timeout_s * 85 / 100 ))
stage="$out/stage/Overhaul"
server_pid=""
client_pids=()
client_units=()
launched_pid=""

for tool in love xvfb-run rsync python3; do
    command -v "$tool" >/dev/null || { echo "Missing $tool"; exit 1; }
done
bun_cmd=(bun)
if ! command -v bun >/dev/null; then
    if command -v mise >/dev/null; then bun_cmd=(mise exec -- bun); else echo "Missing bun"; exit 1; fi
fi

tree_pids() {
    local p
    for p in $(pgrep -P "$1" 2>/dev/null); do tree_pids "$p"; done
    echo "$1"
}

kill_tree() {
    local all=() p
    for p in "$@"; do
        [ -n "$p" ] && kill -0 "$p" 2>/dev/null && all+=($(tree_pids "$p"))
    done
    [ ${#all[@]} -eq 0 ] && return 0
    kill "${all[@]}" >/dev/null 2>&1
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        local alive=0
        for p in "${all[@]}"; do kill -0 "$p" 2>/dev/null && alive=1 && break; done
        [ "$alive" = 0 ] && return 0
        sleep 0.3
    done
    kill -9 "${all[@]}" >/dev/null 2>&1
    return 0
}

stop_clients() {
    local u
    for u in "${client_units[@]}"; do
        systemctl --user stop "$u.scope" >/dev/null 2>&1
    done
    kill_tree "${client_pids[@]}"
    pkill -9 -f "love $stage" >/dev/null 2>&1
    return 0
}

cleanup() {
    trap - EXIT INT TERM
    stop_clients
    [ -n "${lag_pid:-}" ] && kill_tree "$lag_pid"
    if [ -n "$server_pid" ]; then
        kill_tree "$server_pid"
        kill -0 "$server_pid" 2>/dev/null || wait "$server_pid" 2>/dev/null
    fi
    true
}
trap cleanup EXIT
trap 'exit 130' INT TERM

external="${MP_TEST_EXTERNAL_SERVER:-0}"
if [ "$external" != 1 ] && (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    echo "Port $port is already in use; set MP_TEST_PORT"
    exit 1
fi

roles=(host guest)
if [ -n "${MP_TEST_PARTY:-}" ]; then
    roles=(host)
    for ((i = 2; i <= ${MP_TEST_PARTY_N:-3}; i++)); do roles+=("p$i"); done
fi
[ "${MP_TEST_SOLO:-0}" = 1 ] && roles=(host)
[ "${MP_TEST_VS_BOT:-0}" = 1 ] && roles=(host)
role_list="$(IFS=,; echo "${roles[*]}")"
rm -rf "$out"
mkdir -p "$out/shared" "$stage"
for r in "${roles[@]}"; do mkdir -p "$out/$r/xdg"; done
for r in "${roles[@]}"; do
    if [ "$r" = host ]; then mods="${MP_TEST_MODS_HOST-${MP_TEST_MODS:-}}"; else mods="${MP_TEST_MODS_GUEST-${MP_TEST_MODS:-}}"; fi
    rest=""
    for m in ${mods//,/ }; do
        if [ "$m" = Steamodded ]; then touch "$out/$r/fork"; else rest="$rest $m"; fi
    done
    if [ -n "$rest" ]; then
        mkdir -p "$out/$r/xdg/love/Overhaul/mods"
        printf '%s\n' $rest > "$out/$r/xdg/love/Overhaul/mods/enabled.txt"
        printf 'modded\n' > "$out/$r/xdg/love/Overhaul/mods/session.txt"
    fi
    if [ -n "${MP_TEST_DUMMY_MOD:-}" ] && { [ "$MP_TEST_DUMMY_MOD" = 1 ] || [[ ",$MP_TEST_DUMMY_MOD," == *",$r,"* ]]; }; then
        dm="$out/$r/xdg/love/Overhaul/mods/MpTestDummy"
        mkdir -p "$dm"
        printf '{"id":"MpTestDummy","name":"MP Test Dummy","author":["mp_test"],"description":"Empty mod for the session switch tests","prefix":"mptd","main_file":"main.lua","version":"1.0.0","dependencies":[]}\n' > "$dm/MpTestDummy.json"
        printf 'return\n' > "$dm/main.lua"
        grep -qx MpTestDummy "$out/$r/xdg/love/Overhaul/mods/enabled.txt" 2>/dev/null || echo MpTestDummy >> "$out/$r/xdg/love/Overhaul/mods/enabled.txt"
    fi
done

echo "[mp_test] staging game"
if [ -n "$love_file" ]; then
    (cd "$stage" && python3 -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extractall(".")' "$love_file") || { echo "unpack failed"; exit 1; }
else
    rsync -a --exclude dexopt --exclude DEV_CHANGELOG.txt --exclude ERROR_LOG.txt \
        --exclude SESSION_LOG.txt --exclude FEATURES.txt --exclude info.txt \
        "$repo/assets/" "$stage/"
fi
mv "$stage/main.lua" "$stage/game_main.lua"
cp "$here/main_stub.lua" "$stage/main.lua"
cp "$here/driver.lua" "$stage/mp_test_driver.lua"
cp "$here/../turbo/turbo.lua" "$stage/turbo.lua"
cp "$here/../sp_soak/perf.lua" "$stage/perf.lua"
[ -n "${MP_TEST_FORGE:-}" ] && cp "$repo/tools/forge_tests/room_demo.lua" "$stage/mp_test_room_demo.lua"

if [ "$external" = 1 ]; then
echo "[mp_test] using the server already on port $port"
echo "Balatro MP server on $port (external)" > "$out/server.log"
else
echo "[mp_test] starting server on port $port"
(cd "${MP_TEST_SERVER_DIR:-$repo/server}" && BOT_PACE="${MP_TEST_BOT_PACE:-1}" PORT="$port" LOG_LEVEL="${MP_TEST_SERVER_LOG:-INFO}" MP_REJOIN_HOLD_SECONDS="${MP_TEST_HOLD:-}" exec nice -n 19 "${bun_cmd[@]}" run src/index.ts) > "$out/server.log" 2>&1 &
server_pid=$!
for _ in $(seq 1 60); do
    grep -q "Balatro MP server on" "$out/server.log" 2>/dev/null && break
    kill -0 "$server_pid" 2>/dev/null || break
    sleep 0.5
done
if ! grep -q "Balatro MP server on" "$out/server.log"; then
    echo "[mp_test] server failed to start"; tail -20 "$out/server.log"; exit 1
fi
fi

client_url="ws://127.0.0.1:$port/ws"
lag_pid=""
if [ -n "${MP_TEST_LAG:-}" ]; then
    [ -n "${MP_TEST_LAG_PORT:-}" ] || { echo "MP_TEST_LAG needs MP_TEST_LAG_PORT"; exit 1; }
    LAG_PORT="$MP_TEST_LAG_PORT" LAG_UPSTREAM="ws://127.0.0.1:$port" LAG_MS="$MP_TEST_LAG" LAG_JITTER_MS="${MP_TEST_LAG_JITTER:-}" \
        nice -n 19 "${bun_cmd[@]}" run "$here/lag_proxy.ts" > "$out/lag_proxy.log" 2>&1 &
    lag_pid=$!
    for _ in $(seq 1 40); do grep -q "lag proxy on" "$out/lag_proxy.log" 2>/dev/null && break; sleep 0.25; done
    grep -q "lag proxy on" "$out/lag_proxy.log" || { echo "[mp_test] lag proxy failed"; cat "$out/lag_proxy.log"; exit 1; }
    client_url="ws://127.0.0.1:$MP_TEST_LAG_PORT/ws"
    echo "[mp_test] $(head -1 "$out/lag_proxy.log")"
fi
[ -n "${MP_TEST_CLIENT_URL:-}" ] && client_url="$MP_TEST_CLIENT_URL"

use_scope=1
systemd-run --user --scope -q true >/dev/null 2>&1 || { use_scope=0; echo "[mp_test] systemd-run --user scopes unavailable, running without a memory cap"; }

launch() {
    local role="$1"
    local unit="$tag-$role-${#client_pids[@]}"
    local cap=()
    [ "$use_scope" = 1 ] && cap=(systemd-run --user --scope -q --unit="$unit" -p MemoryMax="$mem" -p CPUQuota="${MP_TEST_CPU_QUOTA:-${MP_TEST_CPU:-400%}}")
    local shot_dir=""
    local runner=(love "$stage")
    [ -n "${MP_TEST_GDB:-}" ] && runner=(gdb -q -batch -x "$MP_TEST_GDB" --args love "$stage")
    if [ "$shots" = 1 ]; then
        shot_dir="$out/$role/shots"
        mkdir -p "$shot_dir"
        if [ "$use_gs" = 1 ]; then
            runner=(gamescope --backend headless -w 1280 -h 720 -W 1280 -H 720 -- love "$stage")
        fi
    fi
    "${cap[@]}" nice -n 19 env -u WAYLAND_DISPLAY SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null \
        MP_TEST_FLOW="${MP_TEST_FLOW:-}" MP_TEST_DROPPER="${MP_TEST_DROPPER:-guest}" \
        MP_TEST_DROP_AT="${MP_TEST_DROP_AT:-shop}" MP_TEST_RESUMED="${MP_TEST_RESUMED:-0}" \
        XDG_DATA_HOME="$out/$role/xdg" \
        MODLOADER_MAIN_ALIAS="game_main.lua" \
        MODLOADER_DOWNLOADS="" \
        MODLOADER_FORK="$([ -f "$out/$role/fork" ] && echo 1)" \
        MP_TEST_ROLE="$role" MP_TEST_SHARED="$out/shared" NO_NAME_PROMPT=1 \
        MP_TEST_PARTY="${MP_TEST_PARTY:-}" MP_TEST_PARTY_ROLES="$role_list" MP_TEST_PARTY_BLINDS="${MP_TEST_PARTY_BLINDS:-3}" \
        MP_TEST_PARTY_EVERY="${MP_TEST_PARTY_EVERY:-0}" MP_TEST_TIMEOUT="${MP_TEST_TIMEOUT:-}" \
        MP_TEST_URL="$client_url" MP_TEST_DEADLINE="$deadline_s" \
        MP_TEST_SPEED="$speed" MP_TEST_REMATCH="$rematch" \
        MP_TEST_PERF="${MP_TEST_PERF:-0}" MP_TEST_PHONE="$([ "$role" = guest ] && echo "${MP_TEST_GUEST_PHONE:-${MP_TEST_PHONE:-0}}" || echo "${MP_TEST_PHONE:-0}")" MP_TEST_ROTATE_EVERY="$([ "$role" = guest ] && echo "${MP_TEST_GUEST_ROTATE:-}")" SOAK_OUT="$out/$role" SOAK_SEED="$role" \
        TURBO="$turbo" TURBO_SHOT_DIR="$shot_dir" \
        xvfb-run -a -s "-screen 0 $([ "$role" = guest ] && echo "${MP_TEST_GUEST_SCREEN:-${MP_TEST_SCREEN:-1280x720}}" || echo "${MP_TEST_SCREEN:-1280x720}")x24" "${runner[@]}" >> "$out/$role/stdout.log" 2>&1 &
    launched_pid=$!
    client_pids+=("$launched_pid")
    client_units+=("$unit")
}

echo "[mp_test] launching host and guest (headless, turbo=$turbo, hard cap $timeout_s s)"
start=$(date +%s)
launch host
host_pid="$launched_pid"
sleep 2
guest_pid=""
if [ "${#roles[@]}" -gt 1 ]; then
    launch "${roles[1]}"
    guest_pid="$launched_pid"
fi
party_pids=()
if [ -n "${MP_TEST_PARTY:-}" ]; then
    for r in "${roles[@]:2}"; do sleep 1; launch "$r"; party_pids+=("$launched_pid"); done
fi
any_alive() {
    local p
    for p in "$host_pid" "$guest_pid" "${party_pids[@]}"; do kill -0 "$p" 2>/dev/null && return 0; done
    return 1
}

capped=0
while any_alive; do
    for r in host guest; do
        if [ -f "$out/shared/relaunch_$r" ]; then
            pid_var="${r}_pid"
            if ! kill -0 "${!pid_var}" 2>/dev/null; then
                rm -f "$out/shared/relaunch_$r"
                echo "[mp_test] relaunching $r (restart flow)"
                MP_TEST_RESUMED=1 launch "$r"
                printf -v "$pid_var" '%s' "$launched_pid"
            fi
        fi
    done
    if [ $(( $(date +%s) - start )) -ge "$timeout_s" ]; then
        capped=1
        echo "[mp_test] FAIL: match hit the hard cap of $timeout_s s (turbo=$turbo), killing clients"
        echo "{\"kind\":\"timeout\",\"t\":$(date +%s),\"cap\":$timeout_s}" >> "$out/shared/runner_events.jsonl"
        break
    fi
    sleep 1
done
echo "[mp_test] clients finished after $(( $(date +%s) - start )) s"
echo "{\"kind\":\"runner_done\",\"seconds\":$(( $(date +%s) - start )),\"turbo\":$turbo,\"capped\":$capped}" > "$out/shared/runner_stats.json"
stop_clients

for r in "${roles[@]}"; do
    for f in mp_match_debug.txt mp_error_trace.log mp_connection.log perf_spikes.log; do
        src=$(find "$out/$r/xdg" -name "$f" 2>/dev/null | head -1)
        [ -n "$src" ] && cp "$src" "$out/$r/$f"
    done
done

MP_TEST_REPORT_ROLES="$role_list" python3 "$here/report.py" "$out" > "$out/report.txt"
if [ -n "${MP_TEST_PARTY:-}" ]; then
    for r in "${roles[@]}"; do grep -h "^\[PARTY " "$out/$r/stdout.log" 2>/dev/null; done > "$out/party.txt"
    echo "[mp_test] party log: $out/party.txt"
    grep -c "" "$out/party.txt"
fi
echo "[mp_test] report: $out/report.txt"
sed -n '1,/^== DISPATCH/p;150q' "$out/report.txt"
