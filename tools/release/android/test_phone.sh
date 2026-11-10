#!/usr/bin/env bash
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
if [[ -n "$official" ]]; then
    export OVERHAUL_OFFICIAL_APK="$official"
else
    unset OVERHAUL_OFFICIAL_APK
fi
export LAUNCHER_SHOT_DIR="$out" LAUNCHER_SHOTS="$shots" LAUNCHER_LANG="$lang" LAUNCHER_MUTE=1 LAUNCHER_NO_ASK=1
[[ -n "${OVERHAUL_FEED:-}" ]] || export OVERHAUL_NO_UPDATE_CHECK=1
export OVERHAUL_INKJOKER_BIN=/nonexistent/inkjoker
export OVERHAUL_EXPORT_DIR="$night/download"
mkdir -p "$OVERHAUL_EXPORT_DIR"

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
echo "marker: $(tr '\n' ' ' < "$save/overhaul_game/.overhaul_installed" 2>/dev/null || echo missing)"
echo "play marker: $([[ -e "$save/launcher_play" ]] && cat "$save/launcher_play" || echo none)"
echo "official copy left: $([[ -e "$save/official.zip" ]] && echo yes || echo no)"
echo "installed files: $(find "$save/overhaul_game" -type f 2>/dev/null | wc -l)"
echo "shots: $(ls "$out" | tr '\n' ' ')"
grep -v "^$" "$night/log-$tag.txt" | tail -8 || true
exit 0
