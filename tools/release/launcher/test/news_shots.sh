#!/usr/bin/env bash
unset WAYLAND_DISPLAY
export SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
work="${NEWS_WORK:-$repo/.night/news-shots}"
out="$work/out"
rm -rf "$work/stage" "$work/pstage" "$work/run"
mkdir -p "$work/stage/patcher" "$work/stage/patchset/files" "$out"
cp "$here/../"*.lua "$work/stage/"
cp "$here/../../patcher/"{apply,zipread,find}.lua "$work/stage/patcher/"
cp "$repo/assets/functions/save_io.lua" "$work/stage/save_io.lua"
cp "$repo/assets/https.lua" "$work/stage/https.lua"
cp "$repo/assets/smods/libs/json/json.lua" "$work/stage/json.lua"
cp "$repo/assets/CHANGELOG.md" "$work/stage/patchset/files/CHANGELOG.md"
printf 'return {\n  format = 2,\n  overhaul_version = "59",\n  overhaul_name = "2.0.4",\n  game_version = "1.0.1o",\n  files = {},\n  vanilla = {},\n}\n' > "$work/stage/patchset/manifest.lua"
cp -r "$work/stage" "$work/pstage"
mv "$work/pstage/core.lua" "$work/pstage/core_pc.lua"
cat > "$work/pstage/core.lua" <<'EOF2'
local C = require("core_pc")
C.PHONE = true
C.APP_APK = "BalatroOverhaul.apk"
C.APP_INFO = "app_info.txt"
C.APP = "com.jupiteriansoul.balatrooverhaul"
C.app_info = function() return {name = os.getenv("FAKE_APP_NAME") or "2.0.4", code = 1, time = 0, splits = {}} end
return C
EOF2
pids=()
run() {
    local tag="$1" stage="$2" size="$3" lang="$4" shots="$5" stamp="$6" seen="$7"; shift 7
    local d="$work/run/${RUNDIR:-$tag}"
    local sd="$d/xdg/love/BalatroOverhaulLauncher"
    if [[ "${KEEP:-0}" != 1 ]]; then
        rm -rf "$d"
        mkdir -p "$sd/Overhaul" "$d/home" "$d/shots"
        [[ -n "$stamp" ]] && printf 'return {overhaul_version = "59", overhaul_name = "%s", time = 1}\n' "$stamp" > "$sd/install.lua"
        [[ -n "$stamp" ]] && printf '\n' > "$sd/Overhaul/main.lua"
        [[ -n "$seen" ]] && printf 'return {news_seen = "%s"}\n' "$seen" > "$sd/settings.lua"
    fi
    env -u WAYLAND_DISPLAY SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null \
        HOME="$d/home" XDG_DATA_HOME="$d/xdg" OVERHAUL_NO_SAVE_SCAN=1 OVERHAUL_NO_UPDATE_CHECK=1 OVERHAUL_NO_SCAN=1 \
        LAUNCHER_SHOT_DIR="$d/shots" LAUNCHER_SHOTS="$shots" LAUNCHER_MUTE=1 LAUNCHER_NO_ASK=1 LAUNCHER_NEWS=1 \
        LAUNCHER_LANG="$lang" LAUNCHER_SIZE="$size" "$@" \
        setsid -w timeout -k 5 90 xvfb-run -a -s "-screen 0 ${size}x24" love "$work/$stage" > "$d/log.txt" 2>&1 &
    local pid=$!
    echo "$pid" >> "$work/pids.txt"
    wait "$pid"
    echo "$tag exit $? | $(grep -h "whats new\|launcher: url" "$d/log.txt" | tr '\n' ' ')"
    grep -iE "error|traceback" "$d/log.txt" | head -5
    rm -f "$out/${tag}_"*.png
    for f in "$d/shots"/*.png; do
        [[ -f "$f" ]] && mv "$f" "$out/${tag}_$(basename "$f")"
    done
    [[ -f "$sd/settings.lua" ]] && echo "  settings: $(tr '\n' ' ' < "$sd/settings.lua")"
}
case "${1:-all}" in
logic)
    run after1 stage 1280x720 en "play,play+tap_news_discord,play+tap_news_github,play+close,play+tap_link_discord,about+tap_about_github" 2.0.4 ""
    KEEP=1 RUNDIR=after1 run after2 stage 1280x720 en "play" 2.0.4 ""
    run fresh stage 1280x720 en "play" "" ""
    run before stage 1280x720 en "play,play+page2" 2.0.3 2.0.3 LAUNCHER_FAKE_FEED=60 LAUNCHER_FAKE_NAME=2.0.4
    ;;
looks)
    for s in land:1280x720 port:720x1280; do
        n="${s%%:*}"; z="${s#*:}"
        for lang in en fr es; do
            run "after_${n}_$lang" stage "$z" "$lang" "play,play+page2,play+close,about" 2.0.4 ""
        done
    done
    for s in phone_land:1560x720 phone_port:720x1560; do
        n="${s%%:*}"; z="${s#*:}"
        for lang in en fr es; do
            run "${n}_$lang" pstage "$z" "$lang" "play,play+close,about" "" ""
        done
    done
    ;;
esac
