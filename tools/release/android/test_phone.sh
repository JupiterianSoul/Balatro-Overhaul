#!/usr/bin/env bash
unset WAYLAND_DISPLAY
export SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
night="${NIGHT:-$repo/.night/phone}"
official="${1:-}"
size="${SIZE:-1560x720}"
shots="${SHOTS:-play,game,saves,settings,about}"
lang="${LANG_CODE:-en}"
tag="${TAG:-$lang-$size}"
game="$night/game"
out="$night/shots/$tag"

[[ -n "${INSTALLER_APK:-}" && -f "$INSTALLER_APK" ]] || { echo "set INSTALLER_APK to a built phone installer"; exit 1; }
[[ "${KEEP_SAVE:-0}" == "1" ]] || rm -rf "$night/xdg"
rm -rf "$game" "$out"
mkdir -p "$game" "$out" "$night/xdg"
unzip -q -o "$INSTALLER_APK" assets/game.love -d "$game"

export XDG_DATA_HOME="$night/xdg"
export OVERHAUL_CRASH_URL="${OVERHAUL_CRASH_URL:-http://127.0.0.1:9/crash}"
if [[ -n "$official" ]]; then
    export OVERHAUL_OFFICIAL_APK="$official"
else
    unset OVERHAUL_OFFICIAL_APK
fi
export LAUNCHER_SHOT_DIR="$out" LAUNCHER_SHOTS="$shots" LAUNCHER_LANG="$lang" LAUNCHER_MUTE=1 LAUNCHER_NO_ASK=1
[[ -n "${OVERHAUL_FEED:-}" ]] || export OVERHAUL_NO_UPDATE_CHECK=1
export OVERHAUL_INKJOKER_BIN=/nonexistent/inkjoker
bridge="$night/bridge-$tag"
if [[ "${APP:-0}" == "1" ]]; then
    rm -rf "$bridge"
    mkdir -p "$bridge"
    echo 1 > "$bridge/can_install"
    rm -f "$night/xdg/love/BalatroOverhaul/BalatroOverhaul.apk"
    export OVERHAUL_BRIDGE_FAKE="$bridge"
    export LAUNCHER_SHOTS="play+app"
fi

timeout "${LIMIT:-240}" xvfb-run -a -s "-screen 0 ${size}x24" bash -c '
    love "$1" > "$2" 2>&1 &
    pid=$!
    if [[ "$3" != "0" ]]; then
        sleep "$3"
        import -window root "$4/game_screen.png" || true
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -9 "$pid" 2>/dev/null || true
    fi
    wait "$pid"
' _ "$game/assets/game.love" "$night/log-$tag.txt" "${GAME_SHOT:-0}" "$out" || echo "love exited with $?"

save="$XDG_DATA_HOME/love/BalatroOverhaul"
echo "marker: $({ tr '\n' ' ' < "$save/overhaul_game/.overhaul_installed"; } 2>/dev/null || echo missing)"
echo "play marker: $([[ -e "$save/launcher_play" ]] && cat "$save/launcher_play" || echo none)"
echo "official copy left: $([[ -e "$save/official.zip" ]] && echo yes || echo no)"
echo "installed files: $(find "$save/overhaul_game" -type f 2>/dev/null | wc -l)"
echo "shots: $(ls "$out" | tr '\n' ' ')"
grep -v "^$" "$night/log-$tag.txt" | tail -8 || true
[[ "${APP:-0}" == "1" ]] || exit 0

apk="$bridge/installed.apk"
[[ -f "$apk" ]] || { echo "app: the launcher made no app"; exit 1; }
app="$night/app"
rm -rf "$app" "$night/app-apk"
mkdir -p "$app" "$night/app-apk"
unzip -q -o "$apk" assets/game.love -d "$night/app-apk"
unzip -q -o "$night/app-apk/assets/game.love" -d "$app"
[[ "${KEEP_APP_SAVE:-0}" == "1" ]] || rm -rf "$night/xdg-app"
mkdir -p "$night/xdg-app"
echo "app apk: $(stat -c %s "$apk") bytes, game package $(stat -c %s "$night/app-apk/assets/game.love") bytes"
signer="${APKSIGNER:-$(command -v apksigner || ls "$HOME"/Android/Sdk/build-tools/*/apksigner 2>/dev/null | tail -1)}"
if [[ -n "$signer" ]]; then
    echo "app signatures from Android 5 up: $("$signer" verify --verbose --min-sdk-version 21 "$apk" 2>&1 | sed -nE 's/^Verified using (v[12]) scheme.*: (true|false)$/\1 \2/p' | tr '\n' ' ')"
fi
echo "app game built in: $([[ -f "$app/overhaul_built" ]] && head -2 "$app/overhaul_built" | tr '\n' ' ' || echo no)"
echo "app official copies: $(find "$app/vanilla" -type f 2>/dev/null | wc -l), patch folder: $([[ -d "$app/patch" ]] && echo yes || echo no)"
unset OVERHAUL_OFFICIAL_APK OVERHAUL_BRIDGE_FAKE LAUNCHER_SHOT_DIR LAUNCHER_SHOTS
export XDG_DATA_HOME="$night/xdg-app"
timeout "${LIMIT:-240}" xvfb-run -a -s "-screen 0 ${size}x24" bash -c '
    love "$1" > "$2" 2>&1 &
    pid=$!
    sleep "$3"
    import -window root "$4/app_first.png" || true
    sleep "$5"
    import -window root "$4/app_screen.png" || true
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
' _ "$app" "$night/log-app-$tag.txt" "${APP_FIRST:-2}" "$out" "${APP_SHOT:-12}" || echo "app run exited with $?"
appsave="$XDG_DATA_HOME/love/BalatroOverhaul"
echo "app patched itself at start: $([[ -d "$appsave/overhaul_game" ]] && echo yes || echo no)"
echo "app saves: $(ls "$appsave" 2>/dev/null | tr '\n' ' ')"
grep -v "^$" "$night/log-app-$tag.txt" | tail -5 || true
exit 0
