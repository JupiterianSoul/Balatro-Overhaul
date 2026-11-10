#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
FIRST=${1:-1}
COUNT=${2:-1}
RUNS=${3:-2}
SECS=${4:-600}
OUT="${BOT_OUT_DIR:-$HERE/out}"
TURBO="${BOT_TURBO:-1}"
mkdir -p "$OUT"
rm -f "$OUT/errors.log"

WORK="$(mktemp -d /tmp/bot_run.XXXXXX)"
trap 'pkill -f "love $WORK/game" 2>/dev/null; rm -rf "$WORK"' EXIT

rsync -a --delete --exclude 'multiplayer/node_modules' "$REPO/assets/" "$WORK/game/"
mv "$WORK/game/main.lua" "$WORK/game/game_main.lua"
cp "$HERE/harness_main.lua" "$WORK/game/main.lua"
cp "$REPO/tools/turbo/turbo.lua" "$WORK/game/turbo.lua"

for ((s = FIRST; s < FIRST + COUNT; s++)); do
    DATA="$WORK/data_$s"
    mkdir -p "$DATA"
    echo "seed $s: start $(date +%T)"
    env -u WAYLAND_DISPLAY SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null \
        NO_NAME_PROMPT=1 XDG_DATA_HOME="$DATA" MODLOADER_MAIN_ALIAS=game_main.lua MODLOADER_DOWNLOADS="$WORK/no_downloads" \
        BOT_OUT="$OUT" BOT_SEED="$s" BOT_RUNS="$RUNS" BOT_SECONDS="$SECS" TURBO="$TURBO" TURBO_SHOT_DIR="${BOT_SHOT_DIR:-}" \
        timeout -k 10 $((SECS + 180)) \
        xvfb-run -a -s "-screen 0 1280x720x24" love "$WORK/game" > "$OUT/stdout_$s.txt" 2>&1
    echo "seed $s: exit $? $(date +%T)"
    grep -h "QUIT\|FATAL_EXIT" "$OUT/bot_$s.log" | tail -1
done

ends=0
errs=0
refused=0
for ((s = FIRST; s < FIRST + COUNT; s++)); do
    f="$OUT/bot_$s.log"
    [ -f "$f" ] || continue
    ends=$((ends + $(grep -c "RUN_END" "$f")))
    errs=$((errs + $(grep -c "\] ERROR" "$f")))
    r=$(grep -o "refused=[0-9]*" "$f" | tail -1 | cut -d= -f2)
    refused=$((refused + ${r:-0}))
done
echo "bot summary: brain=${BOT_BRAIN:-mock} seeds=$COUNT runs_finished=$ends errors=$errs refused=$refused"
[ "$errs" -eq 0 ] && [ "$ends" -ge $((COUNT * RUNS)) ]
