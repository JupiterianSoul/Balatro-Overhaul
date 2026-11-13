#!/usr/bin/env bash
unset WAYLAND_DISPLAY
export SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null
set -uo pipefail
export OVERHAUL_NO_SAVE_SCAN=1
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
rel="${RELEASE_DIR:-$repo/dist/release}"
work="${E2E_DIR:-$repo/.night/e2e}"
case "$work" in
    "$repo"/.night/*) ;;
    *) echo "E2E_DIR must be under $repo/.night"; exit 1 ;;
esac
tarball="$(ls "$rel"/BalatroOverhaulLauncher-*-linux-x86_64.tar.gz 2>/dev/null | head -1)"
[[ -n "$tarball" ]] || { echo "No Linux package in $rel"; exit 1; }
steps="${E2E_STEPS:-install boot bot}"
if [[ -z "${E2E_NETNS:-}" ]] && command -v unshare >/dev/null && unshare -rn true 2>/dev/null; then
    E2E_NETNS=1 exec unshare -rn sh -c 'ip link set lo up 2>/dev/null; exec bash "$0" "$@"' "${BASH_SOURCE[0]}" "$@"
fi
fail=0
say() { echo "e2e: $*"; }

rm -rf "$work"
mkdir -p "$work/pkg" "$work/data" "$work/home"
tar -xzf "$tarball" -C "$work/pkg"
app="$work/pkg/Balatro Overhaul Launcher"
export XDG_DATA_HOME="$work/data"
game="$XDG_DATA_HOME/BalatroOverhaulLauncher/Overhaul"

if [[ " $steps " == *" install "* ]]; then
    say "1 empty folder: $(ls "$work/data" | wc -l) items in the data folder"
    timeout -k 5 300 xvfb-run -a "$app/balatro-overhaul-launcher" --cli install > "$work/install.txt" 2>&1
    cat "$work/install.txt"
    grep -q "^OK installed" "$work/install.txt" || { say "FAIL install"; fail=1; }
    python3 -B "$repo/tools/release/patcher/roundtrip_check.py" "$game" --manifest "$rel/patchset/manifest.lua" | tail -2 || fail=1
    for case_ in old modded notgame; do
        timeout -k 5 120 xvfb-run -a "$app/balatro-overhaul-launcher" --cli check --balatro "$repo/.night/fake/$case_/Balatro.exe" 2>&1 | tail -1 | sed "s/^/e2e: $case_: /"
    done
    HOME="$work/home" timeout -k 5 120 xvfb-run -a "$app/balatro-overhaul-launcher" --cli check 2>&1 | tail -1 | sed "s/^/e2e: missing: /"
fi

if [[ " $steps " == *" boot "* ]]; then
    secs="${BOOT_SECS:-35}"
    timeout -k 5 $((secs + 60)) xvfb-run -a -s "-screen 0 1280x720x24" bash -c '
        "$1/AppRun" --overhaul-run "$2" > "$3/boot_stdout.txt" 2>&1 &
        pid=$!
        sleep "$4"
        import -window root "$3/boot.png"
        alive=0; kill -0 $pid 2>/dev/null && alive=1
        kill $pid 2>/dev/null; sleep 1; kill -9 $pid 2>/dev/null
        echo "alive_after_boot=$alive"
    ' _ "$app" "$game" "$work" "$secs" | tee "$work/boot.txt"
    grep -q "alive_after_boot=1" "$work/boot.txt" || { say "FAIL game did not stay up"; fail=1; }
    [[ -f "$XDG_DATA_HOME/love/Overhaul/settings.jkr" || -d "$XDG_DATA_HOME/love/Overhaul" ]] && say "game save folder: $XDG_DATA_HOME/love/Overhaul"
    grep -i "error\|traceback" "$work/boot_stdout.txt" | head -5
fi

if [[ " $steps " == *" bot "* ]]; then
    fake="$work/repo"
    mkdir -p "$fake/tools"
    cp -r "$repo/tools/sp_soak" "$repo/tools/turbo" "$fake/tools/"
    rm -rf "$fake/tools/sp_soak/out"
    ln -s "$game" "$fake/assets"
    SOAK_OUT_DIR="$work/soak" SOAK_MENUS=0 SOAK_RESTARTS=0 SOAK_FAIR=1 SOAK_DECK=b_red SOAK_STAKE=1 SOAK_JOBS=1 \
        bash "$fake/tools/sp_soak/run.sh" 1 1 "${BOT_RUNS:-3}" "${BOT_SECS:-240}" > "$work/soak_run.txt" 2>&1
    tail -3 "$work/soak_run.txt"
    log="$work/soak/soak_1.log"
    best="$(grep -o "SELECT_BLIND ante=[0-9]*" "$log" 2>/dev/null | cut -d= -f2 | sort -n | tail -1)"
    say "bot best ante: ${best:-none}"
    grep "RUN_END\|^\[.*\] ERROR" "$log" 2>/dev/null | cut -c1-120 | sed 's/^/e2e: /'
    [[ "${best:-0}" -ge 2 ]] || { say "FAIL bot did not reach Ante 2"; fail=1; }
fi

if (( fail )); then
    say "FAIL"
    exit 1
fi
say "OK"
