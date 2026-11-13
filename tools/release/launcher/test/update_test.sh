#!/usr/bin/env bash
set -uo pipefail
export OVERHAUL_NO_SAVE_SCAN=1
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../../../.." && pwd)"
rel="${RELEASE_DIR:-$repo/dist/release}"
work="${UPD_DIR:-$repo/.night/upd}"
port="${QA_PORT:-38851}"
dead_port="${MP_TEST_PORT:-38871}"
vanilla="${BALATRO_EXE:-$HOME/.local/share/Steam/steamapps/common/Balatro/Balatro.exe}"
case "$work" in
    "$repo"/.night/*) ;;
    *) echo "UPD_DIR must be under $repo/.night"; exit 1 ;;
esac
[[ -f "$rel/launcher.love" && -f "$rel/feed.json" ]] || { echo "Run tools/release/pack_overhaul.sh --launcher-only first"; exit 1; }
if [[ -z "${UPD_NETNS:-}" ]] && command -v unshare >/dev/null && unshare -rn true 2>/dev/null; then
    UPD_NETNS=1 exec unshare -rn sh -c 'ip link set lo up 2>/dev/null; exec bash "$0" "$@"' "${BASH_SOURCE[0]}" "$@"
fi
fail=0
say() { echo "upd: $*"; }
check() {
    if grep -q -- "$2" "$work/$1.txt"; then
        say "ok   $1: $(grep -m1 -- "$2" "$work/$1.txt" | cut -c1-110)"
    else
        say "FAIL $1 (wanted: $2)"
        sed 's/^/      /' "$work/$1.txt" | tail -6
        fail=1
    fi
}

rm -rf "$work"
mkdir -p "$work/srv/new" "$work/srv/older" "$work/srv/broken" "$work/srv/format2" "$work/data"
export XDG_DATA_HOME="$work/data"
save="$XDG_DATA_HOME/love/BalatroOverhaulLauncher"
game="$save/Overhaul"
old_version="$(sed -n 's/^  overhaul_version = "\(.*\)",$/\1/p' "$rel/patchset/manifest.lua")"

new_version="${NEW_VERSION:-99}"
cp -a --reflink=auto "$repo/assets" "$work/assets_new"
rm "$work/assets_new/globals.lua"
sed "s/^OVERHAUL_VERSION = .*/OVERHAUL_VERSION = '$new_version'/" "$repo/assets/globals.lua" > "$work/assets_new/globals.lua"
python3 -B "$repo/tools/release/patcher/make_patch.py" --vanilla "$vanilla" --assets "$work/assets_new" \
    --exclude "$repo/tools/release/EXCLUDE.txt" --out "$work/new_patchset" | tail -1
zipf="$work/srv/new/patchset-$new_version.zip"
(cd "$work/new_patchset" && find . -type f -printf '%P\n' | LC_ALL=C sort | zip -q -9 -X -D "$zipf" -@)
printf '{"en": "Test update %s", "fr": "Mise à jour de test %s", "es": "Actualización de prueba %s"}\n' "$new_version" "$new_version" "$new_version" > "$work/changelog.json"
python3 -B "$repo/tools/release/patcher/make_feed.py" --manifest "$work/new_patchset/manifest.lua" --zip "$zipf" \
    --changelog "$work/changelog.json" --out "$work/srv/new/feed.json" | sed 's/^/upd: /'
cp "$zipf" "$work/srv/broken/"
python3 -B - "$work/srv/broken/patchset-$new_version.zip" <<'EOF'
import sys
p = sys.argv[1]
d = bytearray(open(p, "rb").read())
d[len(d) // 2] ^= 0xFF
open(p, "wb").write(bytes(d))
EOF
cp "$work/srv/new/feed.json" "$work/srv/broken/feed.json"
python3 -B "$repo/tools/release/patcher/make_feed.py" --manifest "$rel/patchset/manifest.lua" --zip "$rel/patchset-"*.zip \
    --version 2.4 --url "patchset-old.zip" --out "$work/srv/older/feed.json" > /dev/null
python3 -B - "$work/srv/new/feed.json" "$work/srv/format2/feed.json" "$(( $(sed -n 's/^P.FORMAT = \([0-9]*\)$/\1/p' "$repo/tools/release/launcher/feed.lua") + 1 ))" <<'EOF'
import json, sys
f = json.load(open(sys.argv[1]))
f["latest"]["patch_format"] = int(sys.argv[3])
f["page"] = "https://example.invalid/overhaul"
json.dump(f, open(sys.argv[2], "w"))
EOF
cp "$zipf" "$work/srv/format2/"

python3 -m http.server "$port" --bind 127.0.0.1 --directory "$work/srv" > "$work/http.log" 2>&1 &
srv=$!
trap 'kill $srv 2>/dev/null' EXIT
for _ in $(seq 50); do
    python3 -c "import socket; socket.create_connection(('127.0.0.1', $port), 0.2)" 2>/dev/null && break
    sleep 0.1
done

launcher() {
    local name="$1" feed="$2"
    shift 2
    LAUNCHER_LOVE="${LAUNCHER_LOVE:-$rel/launcher.love}" OVERHAUL_FEED="$feed" OVERHAUL_LAUNCHER_CMD="$work/fake_launcher.sh" TMO=300 \
        bash "$here/run_launcher.sh" --cli "$@" > "$work/$name.txt" 2>&1
    echo "rc=$?" >> "$work/$name.txt"
}
feed() { echo "http://127.0.0.1:$port/$1/feed.json"; }

launcher install "$(feed none)" install
check install "^OK installed $old_version,"
launcher older "$(feed older)" update
check older "^OK You have the latest Overhaul ($old_version)"
launcher offline "http://127.0.0.1:$dead_port/feed.json" update
check offline "^OK Could not check for updates"
launcher broken "$(feed broken)" update
check broken "^FAIL The update download is damaged"
check broken "rc=6"
grep -q "OVERHAUL_VERSION = '$old_version'" "$game/globals.lua" && say "ok   broken: the installed $old_version is untouched" || { say "FAIL broken changed the install"; fail=1; }
[[ ! -e "$save/Overhaul.new" ]] && say "ok   broken: no staging folder left" || { say "FAIL staging folder left"; fail=1; }
launcher format2 "$(feed format2)" update
check format2 "^FAIL Overhaul $new_version needs a newer launcher"
launcher new "$(feed new)" update
check new "^update $new_version http://127.0.0.1:$port/new/patchset-$new_version.zip"
check new "^OK installed $new_version, 751 files\|^OK installed $new_version, 7[0-9][0-9] files"
grep -q "OVERHAUL_VERSION = '$new_version'" "$game/globals.lua" && say "ok   new: installed globals.lua says $new_version" || { say "FAIL new: globals.lua not updated"; fail=1; }
python3 -B "$repo/tools/release/patcher/roundtrip_check.py" "$game" --assets "$work/assets_new" --manifest "$work/new_patchset/manifest.lua" > "$work/roundtrip.txt" 2>&1
check roundtrip "^OK"
ls "$save/updates" > "$work/updates_dir.txt"
check updates_dir "^patchset-$new_version.zip$"
launcher restart "$(feed none)" check
check restart "^launcher: Overhaul $new_version for Balatro"
launcher again "$(feed new)" update
check again "^OK You have the latest Overhaul ($new_version)"
cp "$save/overhaul_launcher_link.lua" "$work/link.txt"
check link "feed\"]=\"http://127.0.0.1:$port/new/feed.json\""
check link "fake_launcher.sh"

lrun() {
    local name="$1" data="$2" feed="$3"
    shift 3
    XDG_DATA_HOME="$data" LAUNCHER_LOVE="${LAUNCHER_LOVE:-$rel/launcher.love}" OVERHAUL_FEED="$feed" TMO=120 \
        bash "$here/run_launcher.sh" --cli "$@" > "$work/$name.txt" 2>&1
    echo "rc=$?" >> "$work/$name.txt"
}
lc_save() { echo "$1/love/BalatroOverhaulLauncher/launcher_code"; }
bundled_build="$(unzip -p "$rel/launcher.love" lcode.lua | sed -n 's/^M\.BUILD = \([0-9]*\)$/\1/p')"
lc_make() {
    local build="$1" out="$2" extra="${3:-}"
    rm -rf "$work/lc_tree"
    mkdir -p "$work/lc_tree" "$(dirname "$out")"
    unzip -q "$rel/launcher-code-$bundled_build.zip" -d "$work/lc_tree"
    sed -i "s/^M\.BUILD = .*/M.BUILD = $build/" "$work/lc_tree/lcode.lua"
    sed -i 's/"launcher code: build %d (bundled %d)%s"/"launcher code: build %d (bundled %d)%s, new code"/' "$work/lc_tree/main.lua"
    if [[ "$extra" == crash ]]; then
        sed -i '1i error("broken launcher code")' "$work/lc_tree/main.lua"
    fi
    rm -f "$out"
    (cd "$work/lc_tree" && find . -type f -printf '%P\n' | LC_ALL=C sort | zip -q -9 -X -D "$out" -@)
}
lc_feed() {
    local dir="$1" zip="$2" build="$3"
    python3 -B - "$work/srv/older/feed.json" "$work/srv/$dir/feed.json" "$zip" "$build" <<'PY'
import hashlib, json, os, sys
f = json.load(open(sys.argv[1]))
blob = open(sys.argv[3], "rb").read()
f["latest"]["launcher"] = {"build": int(sys.argv[4]), "url": os.path.basename(sys.argv[3]), "size": len(blob), "sha256": hashlib.sha256(blob).hexdigest()}
json.dump(f, open(sys.argv[2], "w"))
PY
}
if [[ -n "$bundled_build" && -f "$rel/launcher-code-$bundled_build.zip" ]]; then
    next=$((bundled_build + 1))
    lc_make "$next" "$work/srv/lcnew/launcher-code-$next.zip"
    lc_feed lcnew "$work/srv/lcnew/launcher-code-$next.zip" "$next"
    mkdir -p "$work/srv/lcbroken"
    cp "$work/srv/lcnew/launcher-code-$next.zip" "$work/srv/lcbroken/"
    lc_feed lcbroken "$work/srv/lcbroken/launcher-code-$next.zip" "$next"
    python3 -B - "$work/srv/lcbroken/launcher-code-$next.zip" <<'PY'
import sys
p = sys.argv[1]
d = bytearray(open(p, "rb").read())
d[len(d) // 3] ^= 0xFF
open(p, "wb").write(bytes(d))
PY
    d1="$work/lc1"
    rm -rf "$d1" && mkdir -p "$d1"
    lrun lc_before "$d1" "$(feed none)" version
    check lc_before "^launcher code: build $bundled_build (bundled $bundled_build)$"
    lrun lc_get "$d1" "$(feed lcnew)" launcher
    check lc_get "^OK launcher build $next ready"
    lrun lc_after "$d1" "$(feed none)" version
    check lc_after "^launcher code: build $next (bundled $bundled_build), new code$"
    lrun lc_again "$d1" "$(feed lcnew)" launcher
    check lc_again "^OK no launcher update"
    lrun lc_install "$d1" "$(feed none)" install
    check lc_install "^OK installed $old_version,"

    d2="$work/lc2"
    rm -rf "$d2" && mkdir -p "$d2"
    lrun lc_broken "$d2" "$(feed lcbroken)" launcher
    check lc_broken "^FAIL The update download is damaged"
    lrun lc_broken_run "$d2" "$(feed none)" version
    check lc_broken_run "^launcher code: build $bundled_build (bundled $bundled_build)$"
    [[ -z "$(ls "$(lc_save "$d2")" 2>/dev/null | grep zip)" ]] && say "ok   lc_broken: no zip kept" || { say "FAIL lc_broken kept a zip"; fail=1; }

    d3="$work/lc3"
    rm -rf "$d3" && cp -a "$d1" "$d3"
    python3 -B - "$(lc_save "$d3")/launcher-code-$next.zip" <<'PY'
import sys
p = sys.argv[1]
d = bytearray(open(p, "rb").read())
d[100] ^= 0xFF
open(p, "wb").write(bytes(d))
PY
    lrun lc_disk "$d3" "$(feed none)" version
    check lc_disk "^launcher code: build $bundled_build (bundled $bundled_build), dropped $next$"

    newer=$((next + 1))
    rm -rf "$work/full_tree" && mkdir -p "$work/full_tree"
    unzip -q "$rel/launcher.love" -d "$work/full_tree"
    sed -i "s/^M\.BUILD = .*/M.BUILD = $newer/" "$work/full_tree/lcode.lua"
    rm -f "$work/launcher_full.love"
    (cd "$work/full_tree" && zip -q -r -9 -X "$work/launcher_full.love" .)
    d4="$work/lc4"
    rm -rf "$d4" && cp -a "$d1" "$d4"
    LAUNCHER_LOVE="$work/launcher_full.love" lrun lc_full "$d4" "$(feed lcnew)" version
    check lc_full "^launcher code: build $newer (bundled $newer), dropped $next$"
    [[ -z "$(ls "$(lc_save "$d4")" 2>/dev/null)" ]] && say "ok   lc_full: the old launcher code is removed" || { say "FAIL lc_full left $(ls "$(lc_save "$d4")")"; fail=1; }
    LAUNCHER_LOVE="$work/launcher_full.love" lrun lc_full_get "$d4" "$(feed lcnew)" launcher
    check lc_full_get "^OK no launcher update"

    crash=$((next + 5))
    lc_make "$crash" "$work/srv/lccrash/launcher-code-$crash.zip" crash
    lc_feed lccrash "$work/srv/lccrash/launcher-code-$crash.zip" "$crash"
    d5="$work/lc5"
    rm -rf "$d5" && mkdir -p "$d5"
    lrun lc_crash_get "$d5" "$(feed lccrash)" launcher
    check lc_crash_get "^OK launcher build $crash ready"
    lrun lc_crash1 "$d5" "$(feed none)" version
    lrun lc_crash2 "$d5" "$(feed none)" version
    check lc_crash1 "broken launcher code"
    lrun lc_crash3 "$d5" "$(feed none)" version
    check lc_crash3 "^launcher code: build $bundled_build (bundled $bundled_build), dropped $crash$"
else
    say "FAIL no launcher-code-$bundled_build.zip in $rel (pack_overhaul.sh writes it)"
    fail=1
fi

if (( fail )); then
    say "FAIL"
    exit 1
fi
say "OK"
