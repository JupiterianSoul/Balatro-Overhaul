#!/usr/bin/env bash
set -uo pipefail
export OVERHAUL_NO_SAVE_SCAN=1
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
work="${UPD_DIR:-$repo/.night/upd}"
port="${QA_PORT:-38851}"
shots="${SHOT_DIR:-$work/shots}"
steps="${GUI_STEPS:-handoff refresh shots ingame lcode}"
case "$work" in
    "$repo"/.night/*) ;;
    *) echo "UPD_DIR must be under $repo/.night"; exit 1 ;;
esac
[[ -f "$work/srv/new/feed.json" ]] || { echo "Run tools/release/launcher/test/update_test.sh first"; exit 1; }
if [[ -z "${UPD_NETNS:-}" ]] && command -v unshare >/dev/null && unshare -rn true 2>/dev/null; then
    UPD_NETNS=1 exec unshare -rn sh -c 'ip link set lo up 2>/dev/null; exec bash "$0" "$@"' "${BASH_SOURCE[0]}" "$@"
fi
fail=0
say() { echo "gui: $*"; }
new_version="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['latest']['version'])" "$work/srv/new/feed.json")"
feed="http://127.0.0.1:$port/new/feed.json"
mkdir -p "$shots"

python3 -m http.server "$port" --bind 127.0.0.1 --directory "$work/srv" > "$work/http_gui.log" 2>&1 &
srv=$!
trap 'kill $srv 2>/dev/null' EXIT
for _ in $(seq 50); do
    python3 -c "import socket; socket.create_connection(('127.0.0.1', $port), 0.2)" 2>/dev/null && break
    sleep 0.1
done

printf '#!/bin/sh\necho "$@" >> "%s/calls.log"\n' "$work" > "$work/recorder.sh"
chmod 755 "$work/recorder.sh"
rm -f "$work/calls.log"

base="$work/gui_base"
rm -rf "$base"
mkdir -p "$base"
XDG_DATA_HOME="$base" OVERHAUL_NO_UPDATE_CHECK=1 bash "$here/run_launcher.sh" --cli install > "$work/gui_base.txt" 2>&1
grep -q "^OK installed [0-9.]*," "$work/gui_base.txt" || { say "FAIL base install"; tail -3 "$work/gui_base.txt"; exit 1; }
fresh() {
    rm -rf "$work/$1"
    cp -a --reflink=auto "$base" "$work/$1"
    echo "$work/$1"
}
save_of() { echo "$1/love/BalatroOverhaulLauncher"; }

if [[ " $steps " == *" handoff "* ]]; then
    d="$(fresh gui_handoff)"
    start=$(date +%s)
    XDG_DATA_HOME="$d" OVERHAUL_FEED="$feed" OVERHAUL_LOVE="$work/recorder.sh" TMO=180 \
        bash "$here/run_launcher.sh" --update --play > "$work/gui_handoff.txt" 2>&1
    rc=$?
    secs=$(( $(date +%s) - start ))
    stamp="$(save_of "$d")/install.lua"
    if [[ $rc -eq 0 ]] && grep -q "\"$new_version\"" "$stamp" && grep -q "BalatroOverhaulLauncher/Overhaul" "$work/calls.log" 2>/dev/null; then
        say "ok   handoff: updated to $new_version, started the game ($(cat "$work/calls.log")), closed itself after ${secs}s"
    else
        say "FAIL handoff rc=$rc after ${secs}s"
        tail -5 "$work/gui_handoff.txt"
        fail=1
    fi
fi

if [[ " $steps " == *" refresh "* ]]; then
    d="$(fresh gui_refresh)"
    XDG_DATA_HOME="$d" OVERHAUL_FEED="$feed" OVERHAUL_LOVE="$work/recorder.sh" XVFB_NUM=97 TMO=200 \
        setsid bash "$here/run_launcher.sh" > "$work/gui_refresh_open.txt" 2>&1 &
    open_pid=$!
    sleep 6
    XDG_DATA_HOME="$d" OVERHAUL_FEED="$feed" OVERHAUL_LOVE="$work/recorder.sh" XVFB_NUM=98 TMO=180 \
        bash "$here/run_launcher.sh" --update --play > "$work/gui_refresh_update.txt" 2>&1
    for _ in $(seq 20); do
        grep -q "install changed to $new_version@" "$work/gui_refresh_open.txt" && break
        sleep 0.5
    done
    if grep -q "install changed to $new_version@.*update feed latest" "$work/gui_refresh_open.txt"; then
        say "ok   refresh: the open launcher saw the update the game asked for and stopped offering $new_version"
    else
        say "FAIL refresh: the open launcher did not notice"
        tail -5 "$work/gui_refresh_open.txt"
        fail=1
    fi
    kill -- -"$open_pid" 2>/dev/null
    wait "$open_pid" 2>/dev/null
fi

if [[ " $steps " == *" shots "* ]]; then
    for size in desktop:1280x720:0 phone:1560x720:1 portrait:720x1560:1; do
        IFS=: read -r name screen touch <<< "$size"
        d="$(fresh "gui_shots_$name")"
        out="$shots/$name"
        rm -rf "$out"
        mkdir -p "$out"
        XDG_DATA_HOME="$d" OVERHAUL_FEED="$feed" OVERHAUL_LOVE="$work/recorder.sh" SCREEN="$screen" LAUNCHER_SIZE="$screen" \
            LAUNCHER_TOUCH="$touch" LAUNCHER_SHOT_DIR="$out" LAUNCHER_SHOTS="play+found,play+progress,play+done" TMO=240 \
            bash "$here/run_launcher.sh" > "$work/gui_shots_$name.txt" 2>&1
        n=$(ls "$out"/*.png 2>/dev/null | wc -l)
        say "shots $name: $n files in $out"
        (( n >= 2 )) || fail=1
    done
fi

if [[ " $steps " == *" ingame "* ]]; then
    rm -f "$work/calls.log"
    export LINK_BODY="return {format = 1, feed = \"$feed\", launcher = {\"$work/recorder.sh\"}}"
    hook="local d = love.filesystem.getSource():match('^(.*)/[^/]+\$') local f = io.open(d .. '/overhaul_launcher_link.lua', 'wb') f:write(os.getenv('LINK_BODY')) f:close() love.filesystem.load('functions/launcher_update.lua')() OverhaulUpdate.check(true)"
    s="wait:2|lua:G.PROFILES[G.SETTINGS.profile].name = 'Tester'|close|lua:$hook|wait:4|shot:01_menu_update|func:overhaul_update_click|wait:1|shot:02_update_prompt|func:overhaul_update_go|wait:4|quit"
    for size in desktop:1280x720:0 phone:1560x720:1; do
        IFS=: read -r name screen phone <<< "$size"
        rm -f "$work/calls.log"
        MENU_OUT="$shots/ingame" PHONE="$phone" SCREEN="$screen" bash "$repo/tools/menu_shots/run.sh" "ingame_$name" plain "$s" > "$work/gui_ingame_$name.txt" 2>&1
        if grep -q -- "--update --play" "$work/calls.log" 2>/dev/null; then
            say "ok   ingame $name: the Update button started the launcher with --update --play"
        else
            say "FAIL ingame $name: no launcher call"
            tail -5 "$work/gui_ingame_$name.txt"
            fail=1
        fi
    done
fi

if [[ " $steps " == *" lcode "* ]]; then
    lfeed="http://127.0.0.1:$port/lcnew/feed.json"
    [[ -f "$work/srv/lcnew/feed.json" ]] || { say "FAIL no lcnew feed (run update_test.sh first)"; fail=1; }
    for size in desktop:1280x720:0 phone:1560x720:1 portrait:720x1560:1; do
        IFS=: read -r name screen touch <<< "$size"
        d="$(fresh "gui_lcode_$name")"
        out="$shots/lcode_$name"
        rm -rf "$out"
        mkdir -p "$out"
        XDG_DATA_HOME="$d" OVERHAUL_FEED="$lfeed" OVERHAUL_LOVE="$work/recorder.sh" SCREEN="$screen" LAUNCHER_SIZE="$screen" \
            LAUNCHER_TOUCH="$touch" LAUNCHER_SHOT_DIR="$out" LAUNCHER_SHOTS="play+lcode" TMO=200 \
            bash "$here/run_launcher.sh" > "$work/gui_lcode_$name.txt" 2>&1
        if grep -q "launcher code build [0-9]* ready" "$work/gui_lcode_$name.txt" && [[ -f "$out/play_lcode.png" ]]; then
            say "ok   lcode $name: downloaded in the background, shot $out/play_lcode.png"
        else
            say "FAIL lcode $name"
            tail -5 "$work/gui_lcode_$name.txt"
            fail=1
        fi
        if [[ "$name" == desktop ]]; then
            d2="$(fresh gui_lcode_press)"
            mkdir -p "$out/press"
            XDG_DATA_HOME="$d2" OVERHAUL_FEED="$lfeed" OVERHAUL_LOVE="$work/recorder.sh" SCREEN="$screen" LAUNCHER_SIZE="$screen" \
                LAUNCHER_SHOT_DIR="$out/press" LAUNCHER_SHOTS="play+lcode,play+tap_lcode_restart,play+after" TMO=200 \
                bash "$here/run_launcher.sh" > "$work/gui_lcode_press.txt" 2>&1
            builds="$(grep -o "^launcher: code build [0-9]*" "$work/gui_lcode_press.txt" | awk '{print $4}' | paste -sd' ')"
            if [[ "$(echo "$builds" | awk '{print NF}')" -ge 2 && "${builds##* }" != "${builds%% *}" ]]; then
                say "ok   lcode restart: RESTART started the launcher again on the new code (builds: $builds)"
            else
                say "FAIL lcode restart (builds: $builds)"
                tail -5 "$work/gui_lcode_press.txt"
                fail=1
            fi
        fi
    done
fi

if (( fail )); then
    say "FAIL"
    exit 1
fi
say "OK"
