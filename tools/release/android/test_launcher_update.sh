#!/usr/bin/env bash
unset WAYLAND_DISPLAY
export SDL_VIDEODRIVER=x11 SDL_AUDIODRIVER=dummy ALSOFT_DRIVERS=null
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../.." && pwd)"
rel="${RELEASE_DIR:-$repo/dist/release}"
night="${NIGHT:-$repo/.night/phone-lcode}"
port="${QA_PORT:-38852}"
size="${SIZE:-1560x720}"
official="${1:-${BALATRO_MOBILE_APK:-}}"
apk="$(ls "$rel"/android/BalatroOverhaulLauncher-*-android.apk 2>/dev/null | head -1)"
case "$night" in
    "$repo"/.night/*) ;;
    *) echo "NIGHT must be under $repo/.night"; exit 1 ;;
esac
[[ -f "$apk" ]] || { echo "no phone launcher APK in $rel/android (pack_overhaul.sh or android/pack.sh)"; exit 1; }
[[ -f "$official" ]] || { echo "pass the official Balatro APK (or set BALATRO_MOBILE_APK)"; exit 1; }
if [[ -z "${UPD_NETNS:-}" ]] && command -v unshare >/dev/null && unshare -rn true 2>/dev/null; then
    UPD_NETNS=1 exec unshare -rn sh -c 'ip link set lo up 2>/dev/null; exec bash "$0" "$@"' "${BASH_SOURCE[0]}" "$@"
fi
fail=0
say() { echo "phone-lcode: $*"; }
check() {
    if grep -q -- "$2" "$1"; then
        say "ok   $3: $(grep -m1 -- "$2" "$1" | cut -c1-110)"
    else
        say "FAIL $3 (wanted: $2)"
        tail -6 "$1" | sed 's/^/      /'
        fail=1
    fi
}

rm -rf "$night"
mkdir -p "$night/srv/release" "$night/game"
unzip -q -o "$apk" assets/game.love -d "$night/game"
love_file="$night/game/assets/game.love"
bundled="$(unzip -p "$love_file" launcher/lcode.lua | sed -n 's/^M\.BUILD = \([0-9]*\)$/\1/p')"
native="$(unzip -p "$love_file" native.txt | tr -dc 0-9)"
[[ -n "$bundled" && -n "$native" ]] || { echo "the APK has no launcher/lcode.lua or native.txt"; exit 1; }
next=$((bundled + 1))
src="$rel/launcher-code-phone-$bundled.zip"
[[ -f "$src" ]] || { echo "no $src"; exit 1; }
mkdir -p "$night/tree"
unzip -q "$src" -d "$night/tree"
sed -i "s/^M\.BUILD = .*/M.BUILD = $next/" "$night/tree/launcher/lcode.lua"
sed -i 's/"launcher: code build %d (bundled %d)"/"launcher: code build %d (bundled %d), new code"/' "$night/tree/launcher/main.lua"
(cd "$night/tree" && find . -type f -printf '%P\n' | LC_ALL=C sort | zip -q -9 -X -D "$night/srv/release/launcher-code-phone-$next.zip" -@)
cp "$apk" "$night/srv/release/launcher-android-new.apk"

feed() {
    python3 -B - "$rel/feed.json" "$night/srv/release/feed.json" "$night/srv/release" "$next" "$1" <<'PY'
import hashlib, json, os, sys
f = json.load(open(sys.argv[1]))
d, build, native = sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
def e(name):
    b = open(os.path.join(d, name), "rb").read()
    return {"url": name, "size": len(b), "sha256": hashlib.sha256(b).hexdigest()}
f["latest"]["launcher"] = dict(build=build, **e("launcher-code-phone-%d.zip" % build))
f["latest"]["launcher"]["phone"] = e("launcher-code-phone-%d.zip" % build)
f["latest"]["android_apk"] = dict(native=native, **e("launcher-android-new.apk"))
json.dump(f, open(sys.argv[2], "w"))
PY
}
python3 -B - "$rel/android"/android-patch-*.zip.json "$night/srv/version.json" <<'PY'
import json, sys
e = json.load(open(sys.argv[1]))
json.dump({"version": e["version"], "platform": "android_patch", "build": {"version": e["version"], "url": "http://127.0.0.1:9/" + e["file"], "size": e["size"], "sha256": e["sha256"]}}, open(sys.argv[2], "w"))
PY

python3 -m http.server "$port" --bind 127.0.0.1 --directory "$night/srv" > "$night/http.log" 2>&1 &
srv=$!
trap 'kill $srv 2>/dev/null' EXIT
for _ in $(seq 50); do
    python3 -c "import socket; socket.create_connection(('127.0.0.1', $port), 0.2)" 2>/dev/null && break
    sleep 0.1
done

export XDG_DATA_HOME="$night/xdg" OVERHAUL_OFFICIAL_APK="$official" OVERHAUL_CRASH_URL="http://127.0.0.1:9/crash"
export OVERHAUL_FEED="http://127.0.0.1:$port/version.json" OVERHAUL_NOTES_FEED="http://127.0.0.1:$port/release/feed.json"
export LAUNCHER_MUTE=1 LAUNCHER_NO_ASK=1 OVERHAUL_INKJOKER_BIN=/nonexistent/inkjoker
save="$XDG_DATA_HOME/love/BalatroOverhaul"
run() {
    local name="$1" shots="$2"
    mkdir -p "$night/shots/$name" "$night/bridge"
    LAUNCHER_SHOT_DIR="$night/shots/$name" LAUNCHER_SHOTS="$shots" OVERHAUL_BRIDGE_FAKE="$night/bridge" \
        timeout -k 5 "${LIMIT:-240}" xvfb-run -a -s "-screen 0 ${size}x24" love "$love_file" > "$night/$name.txt" 2>&1
    echo "rc=$?" >> "$night/$name.txt"
}

feed "$native"
run same_native "play+lcode"
check "$night/same_native.txt" "^launcher: code build $bundled (bundled $bundled)$" "first start runs the bundled code"
check "$night/same_native.txt" "launcher code build $next ready" "code update downloaded in the background"
[[ -f "$night/shots/same_native/play_lcode.png" ]] && say "ok   shot $night/shots/same_native/play_lcode.png (RESTART, no app update: same native $native)" || { say "FAIL no shot"; fail=1; }
run restarted "play+tap_lcode_restart,play+after"
check "$night/restarted.txt" "^launcher: code build $next (bundled $bundled), new code$" "next start mounts the new code"
cp "$night/restarted.txt" "$night/restarted_keep.txt"

feed "$((native + 1))"
rm -rf "$night/bridge"
mkdir -p "$night/bridge"
echo 1 > "$night/bridge/can_install"
run apk_offer "play+lapk"
check "$night/apk_offer.txt" "^launcher: code build $next (bundled $bundled), new code$" "the kept code still runs"
[[ -f "$night/shots/apk_offer/play_lapk.png" ]] && say "ok   shot $night/shots/apk_offer/play_lapk.png (UPDATE THE LAUNCHER, native $((native + 1)) > $native)" || { say "FAIL no shot"; fail=1; }
run apk_press "play+tap_lapk,play+pressed"
if grep -q "^install $save/launcher_update.apk$" "$night/bridge/calls.txt" 2>/dev/null && cmp -s "$night/bridge/installed.apk" "$night/srv/release/launcher-android-new.apk"; then
    say "ok   UPDATE THE LAUNCHER downloaded the APK, checked it and asked Android to install it"
else
    say "FAIL no install call: $(cat "$night/bridge/calls.txt" 2>/dev/null | tr '\n' ' ')"
    tail -5 "$night/apk_press.txt"
    fail=1
fi

if (( fail )); then
    say "FAIL"
    exit 1
fi
say "OK"
