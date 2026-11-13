#!/usr/bin/env bash
set -u
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "$here/../.." && pwd)"
out="${BOT_OUT_DIR:-$here/out_versus}"
port="${BOT_PORT:-37741}"
cap="${BOT_VERSUS_TIMEOUT:-600}"
turbo="${BOT_TURBO:-1}"
rm -rf "$out"
mkdir -p "$out/shared" "$out/host/xdg" "$out/bot/xdg" "$out/stage"
stage="$out/stage"
rsync -a --exclude DEV_CHANGELOG.txt "$repo/assets/" "$stage/"
mv "$stage/main.lua" "$stage/game_main.lua"
cp "$repo/tools/mp_test/main_stub.lua" "$stage/main.lua"
cp "$repo/tools/mp_test/driver.lua" "$stage/mp_test_driver.lua"
cp "$repo/tools/turbo/turbo.lua" "$stage/turbo.lua"
cp -r "$stage" "$out/stage_bot"
cp "$here/versus_stub.lua" "$out/stage_bot/main.lua"
bun_bin="$(command -v bun || echo "$HOME/.bun/bin/bun")"
(cd "$repo/server" && PORT="$port" LOG_LEVEL=INFO exec "$bun_bin" run src/index.ts) > "$out/server.log" 2>&1 &
server_pid=$!
trap 'kill $server_pid $host_pid $bot_pid 2>/dev/null; pkill -f "$out/stage" 2>/dev/null' EXIT
for _ in $(seq 1 60); do grep -q "Balatro MP server on" "$out/server.log" && break; sleep 0.5; done
grep -q "Balatro MP server on" "$out/server.log" || { echo "server failed"; tail "$out/server.log"; exit 1; }
common=(env -u WAYLAND_DISPLAY SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null NO_NAME_PROMPT=1
    MODLOADER_MAIN_ALIAS=game_main.lua MODLOADER_DOWNLOADS= MP_TEST_URL="ws://127.0.0.1:$port/ws" MP_TEST_SHARED="$out/shared" TURBO="$turbo")
"${common[@]}" XDG_DATA_HOME="$out/host/xdg" MP_TEST_ROLE=host MP_TEST_REMATCH=0 MP_TEST_DEADLINE=$((cap - 30)) \
    timeout $cap xvfb-run -a -s "-screen 0 1280x720x24" love "$stage" > "$out/host/stdout.log" 2>&1 &
host_pid=$!
for _ in $(seq 1 240); do [ -s "$out/shared/room_code.txt" ] && break; sleep 1; done
code="$(tr -d '[:space:]' < "$out/shared/room_code.txt" 2>/dev/null)"
[ -n "$code" ] || { echo "host made no room"; exit 1; }
echo "room code $code"
mkdir -p "$out/bot/xdg/love"
"${common[@]}" XDG_DATA_HOME="$out/bot/xdg" BOT_OUT="$out/bot" BOT_VERSUS_CODE="$code" \
    timeout $cap xvfb-run -a -s "-screen 0 1280x720x24" love "$out/stage_bot" > "$out/bot/stdout.log" 2>&1 &
bot_pid=$!
wait $bot_pid
echo "bot exit $?"
kill $host_pid 2>/dev/null
grep -h "QUIT\|FATAL" "$out/bot/bot_versus.log" | tail -2
python3 "$repo/tools/mp_test/report.py" "$out" > "$out/report.txt" 2>/dev/null
grep -c "\] ERROR" "$out/bot/bot_versus.log"
