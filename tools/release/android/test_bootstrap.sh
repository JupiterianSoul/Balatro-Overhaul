#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
night="${NIGHT:-$repo/.night/mobile}"
official="${1:-$night/fake/official.apk}"
patch="${2:-$night/patch}"
first="${FIRST_SHOT:-2}"
later="${LATER_SHOT:-60}"
test_dir="$night/boot_test"
shots="$night/shots"

[[ -f "$official" ]] || { echo "no official APK at $official"; exit 1; }
[[ -n "${INSTALLER_APK:-}" || -f "$patch/manifest.lua" ]] || { echo "no patch set at $patch"; exit 1; }

rm -rf "$test_dir"
[[ "${KEEP_SAVE:-0}" == "1" ]] || rm -rf "$night/xdg"
mkdir -p "$test_dir" "$shots" "$night/xdg"
if [[ -n "${INSTALLER_APK:-}" ]]; then
    unzip -q -o "$INSTALLER_APK" assets/game.love -d "$test_dir"
    game="$test_dir/assets/game.love"
else
    python3 -B "$here/make_apk.py" phone-tree --out "$test_dir"
    mkdir -p "$test_dir/patcher"
    cp "$here"/../patcher/{apply,zipread,love_ctx}.lua "$test_dir/patcher/"
    cp -al "$patch" "$test_dir/patch"
    game="$test_dir"
fi

export XDG_DATA_HOME="$night/xdg"
export OVERHAUL_OFFICIAL_APK="$official"
[[ "${NO_OFFICIAL:-0}" == "1" ]] && unset OVERHAUL_OFFICIAL_APK
tag="${TAG:-boot}"
export OVERHAUL_LANG="${OVERHAUL_LANG:-en}"
export OVERHAUL_INKJOKER_BIN=/nonexistent/inkjoker
mkdir -p "$night/launcher_shots"
export LAUNCHER_SHOT_DIR="$night/launcher_shots" LAUNCHER_SHOTS="${LAUNCHER_SHOTS:-play+install,play+play}" LAUNCHER_MUTE=1 LAUNCHER_NO_ASK=1 OVERHAUL_NO_UPDATE_CHECK=1

xvfb-run -a -s "-screen 0 ${SCREEN:-1280x720}x24" bash -c '
    love "$6" > "$1/boot_log.txt" 2>&1 &
    pid=$!
    sleep "$2"
    import -window root "$3/$5_install.png" || true
    if [[ "$4" != "0" ]]; then
        sleep "$4"
        import -window root "$3/$5_game.png" || true
    fi
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
' "$test_dir" "$night" "$first" "$shots" "$later" "$tag" "$game"

save="$XDG_DATA_HOME/love/BalatroOverhaul"
echo "marker: $(cat "$save/overhaul_game/.overhaul_installed" 2>/dev/null || echo missing)"
echo "official copy left: $([[ -e "$save/official.zip" ]] && echo yes || echo no)"
echo "installed files: $(find "$save/overhaul_game" -type f 2>/dev/null | wc -l)"
tail -5 "$night/boot_log.txt" || true
